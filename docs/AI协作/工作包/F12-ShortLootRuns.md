# F12 Short Loot Runs 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是默认模式短刷图循环的阶段工作包；改默认局长、兴趣点结构、巢核目标、局内成长启用边界或验收命令时，必须同步 GDD、ADR、`docs/AI导航.md`、`docs/代码/gameplay_runtime.md`、`client/data/README.md`、测试策略与 AI 记忆。

## 1. 目标

F12 将标准模式从长时间生存局收束为暗黑式短刷图行动。默认目标是一局 8-12 分钟，玩家高频进入敌巢战区，清精英 / 兴趣点 / 小巢核，带回 Gear Mod、升级资源和结算战利品，再回局外整理英雄 / 武器 Mod loadout。

核心不是“活满倒计时”，而是：

```text
进图 -> 选择收益路线 -> 清精英 / 缓存 / 巢点 -> 拿掉落 -> 击破小巢核 -> 进入撤离区 -> 局外整理 Mod -> 下一把
```

## 2. 设计结论

- **默认模式采用短循环**：首版标准局按 8-12 分钟设计，后续 25 分钟深层破巢可作为高收益 / 挑战模式，不作为默认体验。
- **默认模式不硬切时间**：8-12 分钟是目标完成窗口，不是到点失败倒计时；9 分钟后进入软加压，让玩家可选择撤离 / 结算或继续贪风险。
- **默认模式暂不启用局内 3 选 1**：F4 的经验升级选择系统保留为可复用能力；未来挑战、无尽、幸存者变体或实验模式可以在 `game_modes.json.resource_pools.growth_pools` 挂接升级池重新启用。
- **Gear Mod 是默认长期成长主轴**：标准模式的中长期动机优先来自 Mod 掉落、资源、分解、升级和装配验证，而不是局内属性三选一。
- **战利品需要成功带回**：ADR #122 后默认标准局不再“拿到即永久入账”；Gear Mod / dust 等奖励先进入 `run.pending_loot`，ADR #123 后击破小巢核只开启撤离区，撤离读条成功才写入 `meta.gear_mods`，死亡 / 放弃 / 重开 / 回标题会丢失未结算战利品，保存退出只保存当前 run 继续。
- **当前已落地首片**：默认局已改为偏外侧投放、0-1 / 1-4 / 4-7 / 7-9 / 9+ 分钟导演阶段、四个 director 兴趣点、可暂存 dust / Gear Mod 奖励、小巢核完成面板，以及可被子弹摧毁的精英巢点 / 小巢核目标；资源缓存 / Mod 缓存已改为可见缓存箱，玩家进入领取半径后按 `interact` 打开，不再被子弹摧毁或进圈自动领取；缓存箱已改为独立格心 anchor、矩形 footprint + 低矮俯视箱体表现，并与关联机关 / 陷阱分离摆放，层级位于地图背景之上、机关 / 敌人 / 玩家之下；可伤害目标已改为立即受伤、贴合地图矩形格，并与关联机关分离摆放；击破小巢核会开启贴格矩形撤离区，站进撤离区完成短读条才结算暂存战利品，死亡 / 放弃会丢失；结果面板首片已列出成功带回或失败丢失的 dust / Gear Mod、击杀数和用时；正式核心实体行为 / 美术、多出口撤离、更正式的 Result UI、缓存箱守卫 / 爆出表现待做。

## 3. 标准一局节奏

| 时间窗 | 阶段 | 玩家目标 | 系统重点 |
|--------|------|----------|----------|
| 0:00-1:00 | 投放 | 热手、确认武器与 Mod 装配手感 | 低压敌群、近处目标提示、无升级打断 |
| 1:00-4:00 | 第一收益节点 | 清第一个精英巢点或资源缓存 | 稳定掉落 dust / Mod 机会 / 局内补给 |
| 4:00-7:00 | 第二收益节点 | 选择更高价值兴趣点或转向巢点 | 战区导演升级敌群与机关密度 |
| 7:00-9:00 | 小巢核 | 击破核心节点或精英守卫 | 核心 + 敌群 + 机关组合，验证 build |
| 9:00-12:00 | 撤离 / 加压 | 进入撤离区结算，或继续贪一个高危点 | 高压尾声，不鼓励无限拖局；未撤离则不带回暂存战利品 |

当前首版已接最小撤离交互：击破小巢核后开启一个贴合矩形地图格的撤离区，玩家站入并保持短读条后才结算。关键是每 2-3 分钟至少有一次明确奖励节点，但奖励在撤离成功前只算本局暂存。

## 4. 关卡结构

标准图先做“小而密”的有限开放战区，不做房间迷宫，也不做空旷平原。

```text
        [高危精英巢点]
              |
[资源缓存] -- [小巢核] -- [Mod 缓存]
              |
          [投放点]
```

实际地图不必严格十字形，但应满足：

- 投放点在边缘或偏外侧，避免开局直接站在中心。
- 3 个兴趣点足够首版闭环：精英巢点、Mod 缓存、资源缓存。
- 小巢核是本局终点，不是长 Boss；它应由核心实体 / 机关 / 精英增援共同构成。
- 玩家应能在 10 分钟内完成 2 个兴趣点 + 小巢核。
- 地面范围、机关和巢点 footprint 使用量化矩形格；可伤害兴趣点目标与交互缓存箱必须有独立格心 anchor，不能和机关 / 陷阱重合；非地面资产用落地点 / 阴影 / 遮挡表达。

## 5. 兴趣点首片

| 兴趣点 | 玩法 | 奖励方向 | 首片实现建议 |
|--------|------|----------|--------------|
| 精英巢点 | 清精英与守卫 | 中概率 Gear Mod、稳定 dust | 先复用 WarzoneDirector interest point + director-sourced hazard / wave 组合 |
| Mod 缓存 | 打开守卫箱 / 击破缓存 | Gear Mod 或高权重掉落机会 | 当前首片已生成独立格心可见缓存箱，矩形 footprint + 低矮俯视箱体贴合地图格，进半径后按 `interact` 打开并暂存 Gear Mod，关联机关不会压到箱体 footprint；守卫清空条件和掉落爆出表现后续补 |
| 资源缓存 | 低风险补给点 | `gear_mod_dust`、治疗或局内补给 | 当前首片已生成独立格心可见缓存箱，矩形 footprint + 低矮俯视箱体贴合地图格，进半径后按 `interact` 打开并暂存 dust，关联机关不会压到箱体 footprint；治疗、商店或武器缓存后续补 |
| 小巢核 | 开启撤离 | 结算倍率、保底 Mod / dust、解锁更高战区 | 首片用高血量核心节点开启撤离区，撤离读条成功后提交暂存战利品 |

## 6. 默认模式局内成长边界

默认标准模式暂时不启用经验升级 3 选 1：

- `mode_standard_survival` 不引用 `growth_pools`。
- `GameplayRunLoop` 在没有成长候选池时不生成经验球，也不会进入 `GameState.LEVEL_UP`。
- `growth.csv`、`growth_pools.json`、`LevelUpPanel`、回放 decision 和 UI 恢复能力保留，供未来非默认模式复用。
- `golden_level_up_choice` 只由测试 harness 显式调用 `debug_enable_level_up_growth()` 启用，用来证明 3 选 1 能力未退化；这不代表默认模式重新启用成长池。
- 调试命令仍可给 XP，用于工具链 / 未来模式验证；默认模式 XP 不触发升级。

以后若要启用局内成长，应新增或调整目标模式，在 `game_modes.json.resource_pools.growth_pools` 明确引用升级池，并补对应 smoke / golden replay。

## 7. 数据与系统入口

| 目标 | 主要文件 | 说明 |
|------|----------|------|
| 默认模式资源池 | `client/data/game_modes.json` | 标准模式不挂 `growth_pools`；未来模式可挂 |
| 地图与兴趣点落地 | `client/data/map_layouts.json`、`client/data/warzone_directors.json` | 小地图、投放点、兴趣点和 director 机关 |
| 敌群阶段 | `client/data/spawn_waves.csv`、`client/data/warzone_directors.json` | 8-12 分钟节奏，不再按 25 分钟拉长；当前 5:00 接入 `enemy_spitter` 远程压力 |
| Gear Mod 掉落 | `client/data/gear_mod_drop_tables.csv`、`GearModSystem`、`warzone_directors.json` | 普通怪维持低概率；兴趣点 / 小巢核先进入 `run.pending_loot`，成功结算时才写入 `meta.gear_mods` |
| 结算 / 撤离 | `GameplayRunLoop`、`GameOverPanel` 或后续 Result UI | 小巢核已能开启撤离区；撤离读条成功后提交暂存战利品并显示完成面板，面板列出带回或丢失的 dust / Gear Mod、击杀数和用时；后续补多出口撤离和更正式 Result UI |

## 8. 首片实施顺序

1. 关闭默认模式局内 3 选 1：标准模式移除 `growth_pools` 引用，运行时无成长池时不产经验球 / 不弹升级面板。
2. 调整标准局目标时长：把 WarzoneDirector phase、spawn wave 和兴趣点节奏压进 8-12 分钟。（已做数据首片；无硬倒计时）
3. 做 3 个首片兴趣点：精英巢点、Mod 缓存、资源缓存。（已做 director 机关占位；资源缓存 / Mod 缓存已有独立格心可见缓存箱、矩形 footprint + 低矮俯视箱体表现、避开陷阱 footprint 和 `interact` 打开流程并进入暂存，精英巢点已有可伤害目标和首版暂存奖励，目标立即可被子弹打且贴合地图格；真实守卫和爆出表现待做）
4. 做小巢核终点：击破后开启撤离区，撤离成功给高价值结算或返回局外。（已做 7 分钟压力窗口、小巢核可伤害目标、保底 dust / Mod 暂存奖励、撤离区、完成面板和成功结算入账，目标与陷阱分离摆放；正式核心行为 / 多出口撤离 / 完整结算待做）
5. 调整掉落：普通怪少量，精英 / 兴趣点 / 小巢核显著更高。
6. 加最小结算反馈：展示本局获得的 Mod / dust / 击杀 / 用时。（已做撤离成功 / 死亡失败标题、击杀 / 用时摘要，以及带回 / 丢失 dust 与 Gear Mod 清单；更正式 Result UI 待做）

## 9. 验收

必跑：

- `python tools/validate_data.py`
- `python tools/test_data_loader_schema.py`
- `python tools/lint_project_rules.py`
- `python tools/lint_gdscript_rules.py`
- `python tools/lint_semantic_rules.py`
- `python tools/godot_bridge.py --project client headless-boot`
- `python tools/godot_bridge.py --project client runtime-smoke`
- `python tools/godot_bridge.py --project client f9-demo-smoke`
- `python tools/godot_bridge.py --project client gear-mod-smoke`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_level_up_choice.replay --rerun-runtime-summary`

改地图 / 机关 / 兴趣点密度时追加：

- `python tools/godot_bridge.py --project client perf-probe`（仅用户当次明确要求性能测试时）
- 必要时重跑 / 重录 checked-in golden replay。

改战利品暂存 / 结算 / 撤离规则时追加：

- `python tools/godot_bridge.py --project client save-smoke`
- `python tools/godot_bridge.py --project client gear-mod-smoke`
- 四条 checked-in golden replay rerun，若稳定摘要或数据指纹有意变化再重录。

## 10. 暂不做

- 25 分钟深层破巢默认局。
- 复杂迷宫 / 房间制地图。
- 默认模式局内 3 选 1。
- 多出口撤离 UI、地图大地图标记系统、缓存箱守卫 / 爆出表现。
- 隐藏 DDA 或读取玩家状态动态调难。
