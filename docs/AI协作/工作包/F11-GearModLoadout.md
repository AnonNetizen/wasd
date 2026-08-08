# F11 — Gear Mod 局内构筑

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Gear Mod 局内构筑工作包；改动时同步 GDD、ADR、Gear Mod / Gameplay / Save 文档、数据手册、测试策略与 AI 记忆。

> 历史文件名保留以维持导航稳定。ADR #188 已取代旧局外 loadout、库存、dust、分解和融合方案；ADR #193 进一步取代等级、升级、满阶和溢出条款。当前权威是“每局空开局、手动拾取无等级独立实例、重复 id 逐份乘算、结局清空”。

## 目标

把 Gear Mod 做成俯视角射击 Roguelike 的 7×7 空间构筑层：棋盘与模块地图同坐标，中心核心派生主英雄被动；玩家只在拾取事务中放置新实例，确认后才生效，不把棋盘带到下一局。

## 当前规则

- 新局从核心与 13 个解锁格开始；每个普通实例有唯一 `instance_id + mod_id + x/y`，不接受 rank 或 count 参数。
- 单份固定效果采用旧第 2 档数值：伤害 ×1.20，后坐力与扩散上限各 ×0.80。
- 重复获得同一 id 时保留为多个独立实例并逐份乘算，例如两份伤害 Mod 为 1.44，两份后坐力 Mod 为 0.64。
- 所有敌人、缓存和世界事件的 Mod 奖励都先生成池化 CPU 拾取实体；玩家执行 `interact` 成功后才追加实例。
- 不提供等级、升级、满阶、溢出补偿、手动装备、卸下、分解、融合或任何预留接口。
- 死亡、胜利、重开和新局都清空 Mod；结果页只按 id 聚合刚结束一局的实例数量，数量不代表等级。

## 权威边界

| 层 | 职责 |
|---|---|
| `GearModSystem` | 无状态规则服务：定义查询、掉落、公共池、固定 `modifiers(mod_id)` 与仅含 Mod id 的测试岛预览 |
| `GearModBoard` / `GameplayRunLoop` | 前者权威管理核心、解锁、四邻、placements 与地图状态；后者分配实例 ID、编排拾取事务 / map 行为、HUD、Run v18 与结果聚合 |
| `Player` / `WeaponSystem` | `set_gear_modifiers()` 替换专属 Gear Mod 层；普通奖励与临时 modifier 独立保留 |
| `SaveManager` | Run v18 保存棋盘、地图计划和带 ID 地面物；Meta v4 只保存内容资格；旧 Run v17 及更早版本不兼容 |
| 开发者测试岛 | 配置 v3 只允许勾选具体 Mod，不提供等级或数量控件；旧 v2 重置，不读写正式 Meta |

恢复顺序固定为：内容池 / 地图 → 棋盘与地面实体 → 普通 / 临时 modifier → 从按实例排序的 effect placements 统一替换 Gear Mod 层一次。map / grid 不进入 modifier，核心不双算。

## 数据

- `client/data/gear_mods.json` schema v5 保存 7×7 board、严格 effect / map / grid、公共池与固定行为；校验器拒绝旧等级字段和类型混用。
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

`gear-mod-smoke` 必须覆盖：13 格掩码、核心、四邻 / 对角 / 锁格 / 占用 / 越界、重复实例、石头、解锁幂等、移动授权、固定效果与替换层。`gear-mod-pickup-smoke` 覆盖预占、确认 / 取消、满盘留地、65536/65537、自动中止和 Run v18 roundtrip；module-world 覆盖刷怪笼。

同时运行 contracts、数据 / schema、三层 lint、Gear Mod / pickup / input / UI / runtime / world-event / save / loading / 正式与技术模块世界 / 测试岛 / headless，以及四份 Replay v8 黄金回放。当前游戏版本为 v1.17。

性能 probe 不属于本工作包验收。标题无配置入口、掉落 / 重复实例反馈、结果页构筑和中英文布局均为待人工验收。
