# F11 — Gear Mod 局内构筑

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Gear Mod 局内构筑工作包；改动时同步 GDD、ADR、Gear Mod / Gameplay / Save 文档、数据手册、测试策略与 AI 记忆。

> 历史文件名保留以维持导航稳定。ADR #188 已取代旧局外 loadout、库存、dust、升级、分解和融合方案；当前权威是“每局空开局、局内获得、自动升阶、结局清空”。

## 目标

把 Gear Mod 做成俯视角射击 Roguelike 的核心局内构筑层：玩家不在标题页配置 Mod，也不把 Mod 带到下一局；获得时立即改变当前 Player / WeaponSystem 数值。

## 当前规则

- 新局的 Mod ranks 必须为空。
- 首次获得某个 Mod 时写内部 rank 0，HUD 显示“第 1 阶”；重复获得依次升到内部 rank 5 / 玩家可见第 6 阶。
- 第七份及以后不增强，通过 `gear_mod_overflow` 金币事务转为 75 局内金币。
- 同类重复自动升阶，不提供手动装备、卸下、升级、分解或融合。
- 死亡、胜利、重开和新局都清空 Mod；结果页只显示刚结束一局的最终构筑快照。
- 本期不做局内手动配置面板；该功能登记为后续设计事项。

## 权威边界

| 层 | 职责 |
|---|---|
| `GearModSystem` | 无状态规则服务：定义查询、掉落、公共池、max rank、overflow gold、rank modifier 与测试岛预览 |
| `GameplayRunLoop` | `{mod_id: rank}` 权威、统一原子授予、HUD 反馈、Run v15 保存 / 恢复、结果页构筑摘要 |
| `Player` / `WeaponSystem` | `set_gear_modifiers()` 替换专属 Gear Mod 层；普通奖励与临时 modifier 独立保留 |
| `SaveManager` | Run v15 保存局内 ranks；Meta v4 只保存 Gear Mod 内容资格，不保存 rank |
| 开发者测试岛 | 纯内存选择 Mod / rank 并预览，不读写正式 Meta，不解释容量或 drain |

恢复顺序固定为：恢复实体基础状态 → 恢复普通 / 临时 modifier → 从 `gear_mod_ranks` 统一替换 Gear Mod 层一次。重复重建不得累加或连乘漂移。

## 数据

- `client/data/gear_mods.json` schema v2 保存 slot、rarity、max rank、公共奖励池、满阶溢出金币与 rank 效果曲线。
- 伤害曲线保持 `1.10 → 1.35`；后坐与扩散保持 `0.90 → 0.65`。
- `gear_mod_drop_tables.csv`：追击者伤害 Mod 5%，喷吐者扩散 Mod 2.5%，壁垒者后坐 Mod 15%。
- 只有玩家归因击杀能触发敌人 Mod 掉落，随机固定走 `RNG.drop`。
- `gear_mod_fusion_costs.csv`、`gear_mod_dust`、dismantle、drain、fusion 已删除。

## 奖励入口

敌人、Mod 缓存和五类世界事件必须调用同一个局内原子授予入口：

- 防御 / 生存 / 占点完成：固定一个等权普通 Mod。
- 金币祭坛成功：授予 Mod，最多成功两次且两次不同。
- 血量祭坛：不产 Mod。
- Mod 缓存：公共池独立抽取两次。
- 事件敌人：仍可正常触发自身掉落。

## 验证

`gear-mod-smoke` 必须覆盖：空开局、首次 rank 0、六份升至 rank 5、第七份转 75 金币、不同 Mod 独立、立即生效、新局清空、Run 恢复不重发，以及替换式 modifier 的幂等性。

同时运行 contracts、数据 / schema、三档 lint、`runtime-smoke`、`world-event-smoke`、`save-smoke`、`loading-smoke`、正式 / 技术模块世界、开发者测试岛、headless boot/editor 与 Replay v5 黄金回放。

性能 probe 不属于本工作包验收。标题无局外入口、掉落 / 升阶反馈、结果页构筑和中英文布局均为待人工验收。
