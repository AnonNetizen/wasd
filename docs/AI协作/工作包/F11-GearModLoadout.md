# F11 — Gear Mod 局内构筑

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Gear Mod 局内构筑工作包；改动时同步 GDD、ADR、Gear Mod / Gameplay / Save 文档、数据手册、测试策略与 AI 记忆。

> 历史文件名保留以维持导航稳定。ADR #188 已取代旧局外 loadout、库存、dust、分解和融合方案；ADR #193 进一步取代等级、升级、满阶和溢出条款。当前权威是“每局空开局、手动拾取无等级独立实例、重复 id 逐份乘算、结局清空”。

## 目标

把 Gear Mod 做成俯视角射击 Roguelike 的核心局内构筑层：玩家不在标题页或局内面板配置 Mod，也不把 Mod 带到下一局；成功拾取一个实例时立即改变当前 Player / WeaponSystem 数值。

## 当前规则

- 新局的 `mod_ids` 必须为空；每次成功拾取只追加一个 Mod id，不接受 rank 或 count 参数。
- 单份固定效果采用旧第 2 档数值：伤害 ×1.20，后坐力与扩散上限各 ×0.80。
- 重复获得同一 id 时保留为多个独立实例并逐份乘算，例如两份伤害 Mod 为 1.44，两份后坐力 Mod 为 0.64。
- 所有敌人、缓存和世界事件的 Mod 奖励都先生成池化 CPU 拾取实体；玩家执行 `interact` 成功后才追加实例。
- 不提供等级、升级、满阶、溢出补偿、手动装备、卸下、分解、融合或任何预留接口。
- 死亡、胜利、重开和新局都清空 Mod；结果页只按 id 聚合刚结束一局的实例数量，数量不代表等级。

## 权威边界

| 层 | 职责 |
|---|---|
| `GearModSystem` | 无状态规则服务：定义查询、掉落、公共池、固定 `modifiers(mod_id)` 与仅含 Mod id 的测试岛预览 |
| `GameplayRunLoop` | 可重复 `mod_ids` 权威、单份原子授予、HUD 反馈、Run v17 保存 / 恢复、结果页数量聚合 |
| `Player` / `WeaponSystem` | `set_gear_modifiers()` 替换专属 Gear Mod 层；普通奖励与临时 modifier 独立保留 |
| `SaveManager` | Run v17 保存局内 `mod_ids`；Meta v4 可保存内容资格，但不保存任何 Mod 实例；旧 Run v16 及更早版本不兼容 |
| 开发者测试岛 | 配置 v3 只允许勾选具体 Mod，不提供等级或数量控件；旧 v2 重置，不读写正式 Meta |

恢复顺序固定为：恢复实体基础状态 → 恢复普通 / 临时 modifier → 从排序后的 `mod_ids` 副本统一替换 Gear Mod 层一次。重复重建不得在旧结果上再次累加；同一数组内的重复 id 必须逐份乘算。

## 数据

- `client/data/gear_mods.json` schema v4 保存 slot、rarity、公共奖励池与固定 `modifiers[{stat,type,value}]`；校验器明确拒绝全部旧等级字段。
- 当前固定值为伤害 `multiply 1.20`、后坐力 `multiply 0.80`、扩散上限 `multiply 0.80`。
- `gear_mod_drop_tables.csv`：追击者伤害 Mod 5%，喷吐者扩散 Mod 2.5%，壁垒者后坐 Mod 15%。
- 只有玩家归因击杀能触发敌人 Mod 掉落，随机固定走 `RNG.drop`。
- `gear_mod_fusion_costs.csv`、`gear_mod_dust`、dismantle、drain、fusion 已删除。

## 奖励入口

敌人、Mod 缓存和五类世界事件必须统一生成手动拾取实体；只有拾取成功时才调用同一个局内单份原子授予入口：

- 防御 / 生存 / 占点完成：固定一个等权普通 Mod 并生成拾取物。
- 金币祭坛成功：生成 Mod 拾取物，最多成功两次且两次不同。
- 血量祭坛：不产 Mod。
- Mod 缓存：公共池独立抽取两次并生成两件拾取物。
- 事件敌人：仍可正常触发自身掉落并生成拾取物。

## 验证

`gear-mod-smoke` 必须覆盖：空开局、单份固定效果、重复 id 逐份乘算、不同 Mod 独立、无等级字段 / API、立即生效、新局清空、Run v17 恢复不重发，以及替换式 modifier 的幂等性。`gear-mod-pickup-smoke` 覆盖所有奖励来源先生成实体、最近距离交互和对象池复用。

同时运行 contracts、数据 / schema、三档 lint、`runtime-smoke`、`world-event-smoke`、`save-smoke`、`loading-smoke`、正式 / 技术模块世界、开发者测试岛、headless boot/editor 与四份 Replay v7 黄金回放。当前游戏版本为 v1.16。

性能 probe 不属于本工作包验收。标题无配置入口、掉落 / 重复实例反馈、结果页构筑和中英文布局均为待人工验收。
