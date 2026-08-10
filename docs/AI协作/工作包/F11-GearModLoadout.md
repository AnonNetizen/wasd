# F11 — Gear Mod 局内构筑

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Gear Mod 局内构筑工作包；改动时同步 GDD、ADR、Gear Mod / Gameplay / Save 文档、数据手册、测试策略与 AI 记忆。

> 历史文件名保留以维持导航稳定。ADR #196 在 ADR #188 / #193 / #194 基础上将 Gear Mod 升为 v6 可组合组件，并把 program 统一交给 GameplayEffectRuntime；旧 kind / map_behavior / grid_behavior 接口已删除。

## 目标

把 Gear Mod 做成俯视角射击 Roguelike 的 7×7 空间构筑层：棋盘与模块地图同坐标，中心核心派生主英雄被动；玩家只在拾取事务中放置新实例，确认后才生效，不把棋盘带到下一局。

## 当前规则

- 新局从核心与 13 个解锁格开始；每个普通实例有唯一 `instance_id + mod_id + x/y`，不接受 rank 或 count 参数。
- 同一 Mod 可组合 `modifier`、`program` 与 `board_rule`；属性 Mod 仍为伤害 ×1.20、后坐力与扩散上限各 ×0.80，刷怪笼是周期 program，石头是 `occupy_only` board rule。
- 重复获得同一 id 时保留为多个独立实例并逐份乘算，例如两份伤害 Mod 为 1.44，两份后坐力 Mod 为 0.64。
- 所有敌人、缓存和世界事件的 Mod 奖励都先生成池化 CPU 拾取实体；玩家执行 `interact` 成功后才追加实例。
- 不提供等级、升级、满阶、溢出补偿、手动装备、卸下、分解、融合或任何预留接口。
- 死亡、胜利、重开和新局都清空 Mod；结果页只按 id 聚合刚结束一局的实例数量，数量不代表等级。

## 权威边界

| 层 | 职责 |
|---|---|
| `GearModSystem` | 无状态规则服务：定义 / components 查询、掉落、奖励池与测试岛预览；`modifiers(mod_id)` 只聚合 modifier 组件 |
| `GearModBoard` / `GameplayRunLoop` | 前者权威管理核心、解锁、四邻与 placements；后者分配实例 ID、注册 program 来源、编排拾取事务、HUD、Run v19 与结果聚合 |
| `GameplayEffectRuntime` | 按来源实例、组件顺序与 program id 执行触发、条件、动作、ICD、周期和快照；所有副作用经 Gateway |
| `Player` / `WeaponSystem` | `set_gear_modifiers()` 替换专属 Gear Mod 层；普通奖励与临时 modifier 独立保留 |
| `SaveManager` | Run v19 保存棋盘、效果 runtime 状态和带 ID 地面物；Meta v4 只保存内容资格；Run v18 保留原文件但拒绝继续 |
| 开发者测试岛 | 配置 v4 只允许具体 Mod 的显式棋盘坐标，不提供等级或数量控件；旧 v3 重置，不读写正式 Meta / Run |

恢复顺序固定为：内容池 / 地图 → 棋盘与地面实体 → 注册 Gear Mod program 来源 → 恢复效果 runtime 状态 → 普通 / 临时 modifier 与 Gear Mod modifier 层。board rule 不进入 modifier，核心不双算，周期刷怪计划不得重抽。

## 数据

- `client/data/gear_mods.json` schema v6 保存 7×7 board、严格 `components[]`、基础奖励池与贡献；校验器拒绝旧顶层 modifier、kind / map / grid、等级字段和槽位-stat 不匹配。
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

`gear-mod-smoke` 必须覆盖：13 格掩码、核心、四邻 / 对角 / 锁格 / 占用 / 越界、重复实例、复合 components、石头、解锁幂等、移动授权、固定效果与替换层。`gear-mod-pickup-smoke` 覆盖预占、确认 / 取消、满盘留地、65536/65537、自动中止和 Run v19 roundtrip；`effect-runtime-smoke` / module-world 覆盖刷怪笼计划与快照。

同时运行 contracts、数据 / schema、三层 lint、Gear Mod / effect runtime / ModLoader / pickup / input / UI / runtime / world-event / save / loading / 正式与技术模块世界 / 测试岛 / headless，以及四份 Replay v9 黄金回放。当前游戏版本为 v1.18。

性能 probe 不属于本工作包验收。标题无配置入口、掉落 / 重复实例反馈、结果页构筑和中英文布局均为待人工验收。
