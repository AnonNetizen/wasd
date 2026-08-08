# Gear Mod 局内规则服务

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 Gear Mod 数据、7×7 空间领域、公共 API、拾取事务、持久化与测试边界的代码契约权威；常见联动为 GDD §7.2、ADR #191 / #193 / #194、`docs/词表与契约.md` §13、Gameplay Runtime 与 SaveManager 文档。

## 1. 定位

`GearModSystem` 是无状态 autoload，只解释 Gear Mod 定义、类型 / 行为、固定 modifier、敌人掉落、公共奖励池和手动拾取配置。`GearModBoard` 是独立的每局领域组件，负责 7×7 解锁格、核心、实例坐标、四邻连接、放置 / 移动原子性、地图行为状态和确定性快照。`GameplayRunLoop` 编排地面拾取事务、效果应用、地图行为、结果摘要和 Run 快照。

Gear Mod 没有 rank、tier、最大等级、升级预览、满阶、溢出补偿或批量授予接口。以后若重新设计升级机制，必须建立新 ADR 和新 schema；不得在当前 API 中预留休眠字段或兼容壳。

这里的 Gear Mod 是局内构筑系统；`ModLoader` 仍指 `user://mods/<mod_id>/mod.json` 本地数据包接口，两者没有运行时依赖。

## 2. 权威边界

| 责任 | 权威 |
|------|------|
| 棋盘、Mod kind / 行为、slot、rarity、固定 modifiers、公共池、拾取配置 | `client/data/gear_mods.json` schema v5 |
| 敌人来源、掉率、敌人等级范围 | `client/data/gear_mod_drop_tables.csv` |
| 解锁格、核心、实例坐标、四邻规则、移动授权与地图行为状态 | `GearModBoard` |
| 单调 `instance_id`、掉落实体、交互预占、确认 / 取消、地图行为与保存恢复 | `GameplayRunLoop` + `GearModPickup` |
| hero / weapon Gear modifier 实际应用 | `Player.set_gear_modifiers()` / `WeaponSystem.set_gear_modifiers()` |
| 内容可用资格 | `ContentUnlockSystem` 冻结的 `content_availability.gear_mod` |
| 正式玩家 UI | `GearModBoardPanel` 的非暂停查看 / 拾取放置、HUD 反馈、Codex 固定资料与结果页数量聚合 |
| 隔离预览 | 开发者测试岛 v4 显式 `{mod_id,x,y}` placements，同一棋盘校验，不读写正式 Meta / Run |

## 3. 数据 schema

`gear_mods.json` 根字段严格为：

- `schema_version = 5`
- `board`：严格 `width=7`、`height=7`、`center={x:3,y:3}` 和逐行 `0,1,3,5,3,1,0` 的 13 个 `initial_unlocked_cells`
- `pickup`：固定 `pool_id=gear_mod_pickup`、`interaction_radius=72`、`spawn_vertical_offset=-36`、`spawn_spread=28`
- `reward_pools[]`：`id` + 有序 `mod_ids[]`
- `mods[]` 公共字段：`id`、`name_key`、`desc_key`、`rarity`、严格 `kind`，以及可选内容解锁 / 图鉴字段
- `kind=effect`：只允许 `slot + modifiers[{stat,type,value}]`
- `kind=map`：只允许声明式 `map_behavior`；当前 `periodic_enemy_spawn` 要求 `interval_seconds=10`、`reset_on_module_exit=true`、`current_layer_only=true`、`normal_rewards=true`
- `kind=grid`：只允许声明式 `grid_behavior={id:"occupy_only"}`

固定 modifier 形状为 `{stat,type,value}`。双端校验器必须明确拒绝 `overflow_gold`、`max_rank`、`rank_modifiers`、`base_value` 和 `value_per_rank`，不能静默忽略旧等级字段。

当前五张普通 Mod：

| Mod | 固定效果 | 敌人 | 掉率 |
|-----|----------|------|------|
| 伤害 | `damage mult 1.20` | `enemy_chaser` | 5% |
| 后坐阻尼 | `recoil mult 0.80` | `enemy_bulwark` | 15% |
| 扩散稳定 | `spread_angle_max mult 0.80` | `enemy_spitter` | 2.5% |
| 刷怪笼 | 对应模块连续停留 10 秒生成一个本层随机敌人 | `enemy_stalker` | 2.5% |
| 石头 | 只占格与连接，无其他效果 | `enemy_swarm` | 5% |

只有玩家归因击杀触发掉落，随机走 `RNG.drop`。奖励源不按本局已持有 id 过滤候选；重复抽到同 id 仍生成可拾取实例。金币祭坛现有“两次结果彼此不重复”规则保持，但不检查玩家所有权。

## 4. 公共 API

| API | 返回 | 语义 |
|-----|------|------|
| `roll_drop_for_enemy(enemy_id, enemy_level := 1, forced_roll := -1.0, allowed_mod_ids := [])` | `Dictionary` | 先按本局内容快照过滤掉落行，再解释匹配项；正式随机走 `RNG.drop`，forced 只供自动测试 |
| `mod_definition(mod_id)` | `Dictionary` | 返回定义副本，未知 id 返回空字典 |
| `mod_definitions()` / `board_config()` | 数组 / 字典 | 返回领域组件初始化所需的规范副本 |
| `modifiers(mod_id)` | `Array[Dictionary]` | 返回该 Mod 的固定 modifier 副本，未知 id 返回空数组 |
| `pickup_config()` | `Dictionary` | 返回统一拾取配置副本；运行时不得自行写死半径或偏移 |
| `reward_pool_ids(pool_id, allowed_mod_ids := [])` | `Array[String]` | 返回与本局内容快照求交后的有序公共池候选副本 |
| `GearModBoard.legal_targets()` / `placement_preview()` | 数组 / 字典 | 查询已解锁、为空且与核心 / 已占格四邻相接的目标；返回排序副本 |
| `GearModBoard.request_placement(instance_id,mod_id,target)` | `Dictionary` | 正整数实例 ID 的原子放置；失败不改变棋盘 |
| `GearModBoard.unlock_cells(coords,source_id)` | `Dictionary` | 边界校验、按来源幂等，返回本次新解锁格；本期无奖励来源或 UI 按钮 |
| `GearModBoard.request_relocation(instance_id,target,cost_authorizer)` | `Dictionary` | 无授权器默认拒绝；授权后仍要求目标合法且移动后全部普通 Mod 与核心四邻连通；map Mod 成功移动时同步清空旧格计时与锁定计划 |

不提供 `rank_modifiers()`、`max_rank()`、`overflow_gold()`、`next_grant_preview()` 或同义接口。拾取提示直接组合 `mod_definition()` 与 `modifiers()`，不增加升级预览门面。

## 5. GameplayRunLoop 运行语义

1. 新局创建棋盘，派生中心核心，初始化 13 个解锁格；核心只展示主英雄被动，不重复执行被动。
2. 每个地面 Mod 在创建时分配本局单调递增正整数 `instance_id`；活动与模块缓存地面物合计逻辑上限 65536，池仍小规模预热并按需增长。第 65537 个新掉落失败且无补偿。
3. 最近交互只预占实体并打开非暂停配置；没有合法格时仅提示原因，不开 UI。默认目标先取玩家当前模块坐标，否则取曼哈顿最近目标、按 `y,x` 解平局。
4. `ui_confirm` 严格核对预占实体仍有效、实例 ID、Mod 与目标后原子放置、应用效果并回收地面物；预占后不因非致命击退导致的距离变化失效。`ui_back`、死亡或离开 `PLAYING` 只解除预占。未提交事务不进存档。
5. 应用时只遍历按实例排序的 `effect` placements，将固定 modifiers 按 slot 分发给 Player / WeaponSystem；同 id 的乘法效果逐份相乘。`map` / `grid` 不进入 modifier 链。
6. 刷怪笼按 placement 坐标映射同坐标 ModuleWorld；连续停留使用缩放后的 `GameClock` 累计。10 秒后从冻结敌池与当前时间开放池交集按既有权重、`RNG.spawn` 锁定敌人和合法空地；执行失败保留计划且不重抽，离开模块清空计时 / 计划，成功后归零。生成敌人走普通奖励、掉落、击杀和内容进度链。
7. `GearModPickup` 根节点位置固定，只有视觉子节点悬浮 / 闪烁；无碰撞、无吸附、无超时。正式图标为 40 px CPU 星窗、2 px `#68BCDD` 轮缘、`star_scale=1.8`。
8. Run v18 保存 `gear_mods.next_instance_id`、行优先解锁格 / placements、按实例排序地图状态和所有带 `instance_id` 的地面物；核心不保存。恢复校验棋盘与活动 / 模块缓存实例 ID 全局唯一。
9. 胜利、死亡、重开或回标题后随 run 一起清空；Meta v4 只保存 Gear Mod 横向可用资格，不保存棋盘、实例、场上拾取物或库存。

缓存与事件规则保持：Mod 缓存独立抽取两次并左右生成；防御、生存、占点固定生成一件；金币祭坛最多两次且两次结果彼此不重复；血量祭坛不产 Mod；事件敌人仍可触发个体掉落。

## 6. Modifier 分层与确定性

Player 与 WeaponSystem 区分普通、临时和 Gear Mod 层。`set_gear_modifiers()` 替换旧 Gear 层后从基础值重建；同一 placements 快照重复重建必须得到相同结果，不能在旧运行时结果上继续累加。

重复实例的效果属于合法构筑叠加：两份伤害 Mod 产生 `1.20 × 1.20 = 1.44`，两份后坐或扩散 Mod 产生 `0.80 × 0.80 = 0.64`。Gear 层不混入普通 Player / Weapon snapshot；Run 恢复棋盘 placements 后只从 effect placements 统一重建一次，避免双重应用。

Replay v8 的 data fingerprint 包含规范化 Gear Mod 玩法数据：schema、棋盘、拾取配置、奖励池有序数组、Mod id / kind / type-specific behavior / fixed modifiers / 默认开放语义和掉落表有序行。名称、描述、稀有度、图标和本地化等展示字段不参与指纹。

## 7. UI、调试与测试

- 靠近提示显示绑定、名称；effect 格式化固定效果，map / grid 使用本地化描述。
- HUD 确认放置后只显示 Mod 名称；无合法格显示明确原因。
- `GearModBoardPanel` 左侧正式地图、右侧棋盘使用同向 7×7 坐标并同步高亮；查看模式按住 Tab，配置模式只允许选择合法空格和确认 / 取消。两者世界不停但完整锁定角色 intent。
- 结果页聚合排序后的实例为 `{mod_id,name_key,count}`，显示“名称 ×数量”。
- Codex 只显示 slot、rarity 和固定描述，不显示等级范围。
- 开发者测试岛每个 Mod 只有启用开关和显式坐标，不提供 rank / count / 移动控件；独立配置 schema v4 使用 `{mod_id,x,y}` 且同一 Mod ID 最多一项，旧 v3 直接重置。没有 ModuleWorld 时 map 行为不激活。

`gear-mod-smoke` 覆盖 13 格掩码、四邻 / 对角 / 越界 / 占用、重复实例、核心、石头、解锁幂等、移动授权和固定效果；`gear-mod-pickup-smoke` 覆盖确认 / 取消原子性、满盘留地、65536/65537、预占、非法快照以及真实 viewport 鼠标 hover / 点击棋盘格 / 点击确认。纯面板 `mouse_filter`、命中层级或鼠标路由修改只需该完整 pickup smoke、一次最终 file-scoped hook 与待人工验收；只有实际改到 InputService、UIManager、领域事务、Run 或 Replay 时才追加对应专项，golden 不记录原始鼠标命中。

## 8. 迁移与兼容

- `gear_mods.json` 只接受 schema v5，不迁移 v4 无坐标数据。
- Run v17→v18 只推进 schema 并标记 `legacy_run_incompatible=true`；不推断旧 `mod_ids` 的坐标。正式加载只删除 Run，Meta v4 保留。
- 旧 Replay v7 精确拒绝且不改写源文件，不提供迁移。
- Debug Test Arena 配置 v3 直接重置为 v4 默认，不推断旧选择的坐标。
