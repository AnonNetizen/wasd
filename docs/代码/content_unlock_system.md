# ContentUnlockSystem 横向内容解锁与图鉴

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 权威：GDD §7.4、ADR #189、`docs/词表与契约.md` §18。

## 1. 定位与边界

`ContentUnlockSystem` 是智能碎片、Gear Mod、敌人三类横向内容的规则、Meta 状态、对局可用池和图鉴查询唯一门面。它只决定“内容是否可用”，不提供生命、伤害、金币等永久属性成长。

- 智能碎片绑定的被动与技能随碎片整包开放；技能和被动没有独立状态。
- 缺少规则的内容默认开放；默认开放内容不写入 Meta。
- 已经发布为默认开放的内容不得直接改成锁定；确需调整时必须新增 Meta 迁移，为旧档保留资格。
- `GameplayRunLoop` 只持有本局冻结快照和未结算增量，不自行解释规则。
- `CodexPanel` 只消费门面返回的解锁状态；锁定条目不得从其他数据源补取真实信息。

## 2. 代码与数据地图

| 位置 | 职责 |
|------|------|
| `client/scripts/autoload/content_unlock_system.gd` | 规则索引、Meta 查询 / 提交、可用池快照、图鉴脱敏 |
| `client/data/content_unlock_rules.json` | 稀疏规则表，仅登记明确锁定规则 |
| `client/data/characters.json` | 智能碎片的可选 `default_unlocked`、`unlock_rule_id`、`codex_icon_path` |
| `client/data/gear_mods.json` | Gear Mod 的同组可选字段与图鉴详情 |
| `client/data/enemies.csv` | 敌人双语描述、可选解锁字段和图鉴图标 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 冻结池、计数增量、死亡 / 通关提交、Run v14 快照 |
| `client/scripts/ui/codex_panel.gd` | 标题图鉴三分类、隐私显示、语言 / 焦点 / 返回 |
| `client/scripts/autoload/save_manager.gd` | Meta v4 / Run v14 envelope、迁移与旧 Run 拒绝 |
| `client/scripts/autoload/replay.gd` | Replay v6 保存并校验冻结池快照 |

## 3. 数据契约

`content_unlock_rules.json` schema v1：

```json
{
  "schema_version": 1,
  "rules": [
    {
      "id": "example_rule",
      "mode": "all",
      "conditions": [
        {"counter_id": "runs_completed", "target": 3}
      ]
    }
  ]
}
```

- `rules[].id` 必须是唯一 snake_case。
- `mode` 只能使用生成契约 `all` / `any`。
- `counter_id` 只能使用 `runs_ended`、`runs_completed`、`character_run_completed`、`enemy_defeated_total`、`enemy_defeated`。
- `character_run_completed` 和 `enemy_defeated` 必须提供合法 `subject_id`；其他计数器禁止该字段。
- `target` 是大于 0 的整数；不允许脚本表达式、未知引用或闲置规则。
- `default_unlocked=false` 必须引用有效规则；缺字段等同 `true`。默认开放条目不得附带 `unlock_rule_id`。
- 条件对象必须是默认开放内容，避免“先解锁被要求对象才能完成要求”的环形或剧透依赖。
- `skills.json.default_unlocked=false` 是非法配置。

数据校验还保证至少两个默认开放智能碎片、每个正式敌池至少一个 0 秒默认敌人、每个正式 Gear Mod 奖励池至少一个默认成员。

## 4. Meta v4 状态

Meta 使用稀疏 `content_progression`：

```text
content_progression:
  unlocked:
    character: [通过规则获得的 id]
    gear_mod: [通过规则获得的 id]
    enemy: [通过规则获得的 id]
  counters:
    runs_ended: int
    runs_completed: int
    character_run_completed: {character_id: int}
    enemy_defeated_total: int
    enemy_defeated: {enemy_id: int}
```

默认开放内容绝不写入 `unlocked`。Meta v3 → v4 保留既有主 / 副智能碎片选择，初始化空的 `unlocked` 与 `counters`；因此新旧档都会自动看到未声明锁定规则的未来内容。

## 5. 公共 API

| API | 返回 | 语义 |
|-----|------|------|
| `is_unlocked(content_type, content_id)` | `bool` | 仅检查默认开放或 Meta `unlocked`；未知 id 返回 false |
| `build_run_availability_snapshot()` | `Dictionary` | 返回三类已开放 id 的稳定排序副本 |
| `requirement_status(content_type, content_id)` | `Dictionary` | 返回规则模式、已结算 current、target、保存 Run 的 pending 与完成状态 |
| `codex_entries(content_type)` | `Array[Dictionary]` | 稳定排序图鉴条目；锁定项在门面层清空名称、描述、图标和详情 |
| `pending_run_preview()` | `Dictionary` | 只读预览保存 Run 若此刻结算会获得的新解锁，不修改 Meta |
| `commit_run_progress(progress_delta)` | `Dictionary` | 校验并合并计数、评估所有规则、一次原子保存 Meta，返回 `saved/newly_unlocked/counters` |

`newly_unlocked` 固定按 `character` / `gear_mod` / `enemy` 分组。已经记录的 id 不会再次返回；重复提交同一数值增量会再次累计计数，但不会重复写入或提示同一解锁。

## 6. 对局冻结与进度事务

新局在消费任何相关 RNG 前调用 `build_run_availability_snapshot()`。正式智能碎片选择、模块首次遭遇、世界事件、open-warzone 波次、Gear Mod 公共池和敌人掉落表都先与快照求交。

`GameplayRunLoop.content_progress_delta` 使用与 Meta counters 相同的稀疏形状：

1. 玩家归因击杀增加总击杀和指定敌人击杀。
2. 死亡增加结算局数；通关还增加通关数和主 / 副碎片各自通关数。
3. 死亡 / 通关调用一次 `commit_run_progress()`，然后删除 Run 并显示本次新解锁。
4. 保存退出把快照与增量写入 Run v14；续局继续累计。
5. 主动放弃或重开只删除 Run，不提交增量。
6. 本局提交不会改变当前快照；新内容从下一局入池。

## 7. Replay 与隔离

Replay v6 的 context 保存同一 `content_availability`。播放时由 harness 在 RunLoop 挂树前注入该快照，忽略本机 Meta，并关闭长期进度提交；v5 和其他未知版本明确拒绝。

开发者测试岛始终访问全部内容，且不读写正式 Meta / Run。所有 smoke 使用隔离 user 目录或显式关闭 RunLoop 提交；测试失败也不得污染玩家进度。

## 8. 图鉴隐私与 UI

- 入口只在标题菜单，位于设置与退出之间，通过 `UIManager.push/pop` 管理。
- 分类固定为智能碎片、Gear Mod、敌人；不维护“已解锁但未发现”。
- 已开放智能碎片显示基础属性、被动和绑定技能；Mod 显示 slot、rarity、rank 曲线；敌人显示描述和核心战斗属性。
- 锁定条目只显示 `???`、通用剪影、条件语义和 `current/target`。真实 name / desc / icon / stats 必须在 `ContentUnlockSystem.codex_entries()` 层就被移除，不能只依赖控件隐藏。
- 保存退出 Run 的 pending 以“本局暂存 +N”附加到对应条件，不参与 current、规则 complete 或当前池。
- `Localization.locale_changed` 触发就地刷新；`ui_back` 和关闭按钮统一 pop，键鼠 / 手柄焦点由 `UIManager` 恢复。

## 9. 扩展步骤

新增默认开放内容时只添加正常内容定义，不需要写规则或迁移。新增锁定内容时：

1. 在内容定义设置 `default_unlocked=false` 与 `unlock_rule_id`。
2. 在 `content_unlock_rules.json` 添加规则，复用已登记 counter / mode。
3. 补齐中英文名称、描述、要求文案和可选图标。
4. 跑 contracts、data/schema、`content-progression-smoke`、`codex-smoke` 与受影响池 smoke。

若需要新条件类型，先更新 GDD / ADR、词表、生成常量、DataLoader 校验、计数采集和 smoke；禁止在规则表嵌入 GDScript 或自由表达式。

## 10. 故障排查

| 现象 | 首查 |
|------|------|
| 新内容意外锁定 | 内容是否误写 `default_unlocked=false` 或无效 `unlock_rule_id` |
| 达标后当前局立即出现新敌人 / Mod | 消费方是否绕过 RunLoop 冻结快照直接查 Meta |
| Replay 在不同存档结果不同 | v6 context 是否保存 / 注入 `content_availability` |
| 续局进度归零 | Run v14 是否包含 `content_progress_delta`，旧 Run 是否被正确拒绝 |
| 锁定图鉴泄露真实资料 | `codex_entries()` 是否在门面层脱敏；UI 是否越过 locked gate 读 DataLoader |
| smoke 改写玩家存档 | bridge 是否使用隔离 user 目录，RunLoop 是否关闭 progression commit |

## 11. 自动测试义务

- `content-progression-smoke`：默认开放、规则校验、all / any、定向计数、幂等解锁、Meta v4、死亡 / 通关提交、保存续局、放弃丢弃、池冻结、Replay / 测试隔离。
- `codex-smoke`：标题入口、三分类、锁定脱敏、要求和 pending、完整详情、语言刷新、焦点与返回。
- 改敌池 / Mod 池过滤时追加 runtime、Gear Mod、world-event、完整 / 技术 module-world。
- 改存档 / Replay 字段时追加 save、loading、replay、replay-input、四条 Replay v6 黄金回放与 headless editor / boot。

人工验收只由用户执行：16:9 中英文布局、键鼠 / 真实手柄导航、锁定无剧透、结算提示和下一局内容池变化。
