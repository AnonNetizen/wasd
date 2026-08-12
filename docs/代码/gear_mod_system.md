# Gear Mod 局内规则服务

> 权威范围：本页只记录该模块的公共契约、可观察行为、schema、所有权与依赖边界；私有实现和逐测试记录不进入本文档。

## 1. 定位

`GearModSystem` 是无状态 autoload，只解释 Gear Mod v6 定义、可组合 components、敌人掉落、公共奖励池 / 贡献和手动拾取配置。`GearModBoard` 是独立的每局领域组件，负责 7×7 解锁格、核心、实例坐标、四邻连接与放置 / 移动原子性。`GameplayEffectRuntime` 管程序注册、稳定事件队列、周期 / 冷却 / action state 和确定性快照；`GameplayRunLoop` 编排地面拾取事务、来源注册、结果摘要和 Run 快照。

Gear Mod 没有 rank、tier、最大等级、升级预览、满阶、溢出补偿或批量授予接口。以后若重新设计升级机制，必须建立新 ADR 和新 schema；不得在当前 API 中预留休眠字段或兼容壳。

这里的 Gear Mod 是局内构筑系统；`ModLoader` 负责 manifest v2 本地包。本地包可以新增命名空间内 Gear Mod，并只组合官方内置原语；它不能扩核心契约、脚本、场景或 Shader。

## 2. 权威边界

| 责任 | 权威 |
|------|------|
| 棋盘、components、rarity、公共池 / 贡献、拾取配置 | `client/data/gear_mods.json` schema v6 |
| 敌人来源、掉率、敌人等级范围 | `client/data/gear_mod_drop_tables.csv` |
| 解锁格、核心、实例坐标、四邻规则与移动授权 | `GearModBoard` |
| trigger / condition / action、周期 / 冷却 / action state | `GameplayEffectRuntime` + Registry + Gateway |
| 单调 `instance_id`、掉落实体、交互预占、确认 / 取消、来源注册与保存恢复 | `GameplayRunLoop` + `GearModPickup` |
| hero / weapon Gear modifier 实际应用 | `Player.set_gear_modifiers()` / `WeaponSystem.set_gear_modifiers()` |
| 内容可用资格 | `ContentUnlockSystem` 冻结的 `content_availability.gear_mod` |
| 正式玩家 UI | `GearModBoardPanel` 的非暂停查看 / 拾取放置、HUD 反馈、Codex 固定资料与结果页数量聚合 |
| 隔离预览 | 开发者测试岛 v4 显式 `{mod_id,x,y}` placements，同一棋盘校验，不读写正式 Meta / Run |

## 3. 数据 schema

`gear_mods.json` 根字段严格为：

- `schema_version = 6`
- `board`：严格 `width=7`、`height=7`、`center={x:3,y:3}` 和逐行 `0,1,3,5,3,1,0` 的 13 个 `initial_unlocked_cells`
- `pickup`：固定 `pool_id=gear_mod_pickup`、`interaction_radius=72`、`spawn_vertical_offset=-36`、`spawn_spread=28`
- `reward_pools[]`：`id` + 有序 `mod_ids[]`
- `reward_pool_contributions[]`：向受支持池追加有序候选；基础与本地贡献按稳定包顺序合并
- `mods[]` 公共字段：`id`、`name_key`、`desc_key`、`rarity`、`components[]`，以及可选内容解锁 / 图鉴字段；本地 Mod 不得声明解锁规则，可选 `placement_sfx_id` 只能引用包内已验证的 namespaced 非循环 SFX
- `modifier={component_id,type:"modifier",slot,modifiers[]}`：slot 仅 `hero` / `weapon`，每个 stat 必须通过 `slot_stat_support`
- `program={component_id,type:"program",program:{program_id,trigger,conditions[],actions[],proc_chance,internal_cooldown}}`；`interval` trigger 才允许 `interval_seconds`
- `board_rule={component_id,type:"board_rule",rule_id:"occupy_only"}`

`conditions[]` 项为 `{condition,params}`，`actions[]` 项为 `{action,params}`。双端校验器必须明确拒绝 v5 `kind` / `map_behavior` / `grid_behavior` 与旧等级字段，不能静默忽略。

当前五张普通 Mod：

| Mod | v6 组件 | 敌人 | 掉率 |
|-----|----------|------|------|
| 伤害 | weapon `modifier`: `damage mult 1.20` | `enemy_chaser` | 5% |
| 后坐阻尼 | weapon `modifier`: `recoil mult 0.80` | `enemy_bulwark` | 15% |
| 扩散稳定 | weapon `modifier`: `spread_angle_max mult 0.80` | `enemy_spitter` | 2.5% |
| 刷怪笼 | module relation + interval `program`，action 为 `spawn_enemy` | `enemy_stalker` | 2.5% |
| 石头 | `board_rule: occupy_only` | `enemy_swarm` | 5% |

只有玩家归因击杀触发掉落，随机走 `RNG.drop`。奖励源不按本局已持有 id 过滤候选；重复抽到同 id 仍生成可拾取实例。金币祭坛现有“两次结果彼此不重复”规则保持，但不检查玩家所有权。

## 4. 公共 API

| API | 返回 | 语义 |
|-----|------|------|
| `roll_drop_for_enemy(enemy_id, enemy_level := 1, forced_roll := -1.0, allowed_mod_ids := [])` | `Dictionary` | 先按本局内容快照过滤掉落行，再解释匹配项；正式随机走 `RNG.drop`，forced 只供自动测试 |
| `mod_definition(mod_id)` | `Dictionary` | 返回定义副本，未知 id 返回空字典 |
| `mod_definitions()` / `board_config()` | 数组 / 字典 | 返回领域组件初始化所需的规范副本 |
| `components(mod_id)` / `modifiers(mod_id)` | `Array[Dictionary]` | 返回全部组件或经槽位校验后的 modifier 副本，未知 id 返回空数组 |
| `pickup_config()` | `Dictionary` | 返回统一拾取配置副本；运行时不得自行写死半径或偏移 |
| `reward_pool_ids(pool_id, allowed_mod_ids := [])` | `Array[String]` | 返回与本局内容快照求交后的有序公共池候选副本 |
| `GearModBoard.legal_targets()` / `placement_preview()` | 数组 / 字典 | 查询已解锁、为空且与核心 / 已占格四邻相接的目标；返回排序副本 |
| `GearModBoard.request_placement(instance_id,mod_id,target)` | `Dictionary` | 正整数实例 ID 的原子放置；失败不改变棋盘 |
| `GearModBoard.unlock_cells(coords,source_id)` | `Dictionary` | 边界校验、按来源幂等，返回本次新解锁格；本期无奖励来源或 UI 按钮 |
| `GearModBoard.request_relocation(instance_id,target,cost_authorizer)` | `Dictionary` | 无授权器默认拒绝；授权后仍要求目标合法且移动后全部普通 Mod 与核心四邻连通；成功移动时 Runtime 注销旧来源并按新格重新注册模块关系程序 |

不提供 `rank_modifiers()`、`max_rank()`、`overflow_gold()`、`next_grant_preview()` 或同义接口。拾取提示直接组合 `mod_definition()` 与 `modifiers()`，不增加升级预览门面。

## 5. GameplayRunLoop 运行语义

1. 新局创建棋盘，派生中心核心，初始化 13 个解锁格；核心只展示主英雄被动，不重复执行被动。
2. 每个地面 Mod 在创建时分配本局单调递增正整数 `instance_id`；活动与模块缓存地面物合计逻辑上限 65536，池仍小规模预热并按需增长。第 65537 个新掉落失败且无补偿。
3. 最近交互只预占实体并打开非暂停配置；没有合法格时仅提示原因，不开 UI。默认目标先取玩家当前模块坐标，否则取曼哈顿最近目标、按 `y,x` 解平局。
4. `ui_confirm` 严格核对预占实体仍有效、实例 ID、Mod 与目标后原子放置、应用效果并回收地面物；成功后若定义保留有效 `placement_sfx_id`，只调用 `AudioManager.play_sfx()` 一次。媒体缺失 / 损坏时 ModLoader 已删除字段，保持静音且不影响玩法提交。预占后不因非致命击退导致的距离变化失效。`ui_back`、死亡或离开 `PLAYING` 只解除预占。未提交事务不进存档。
5. 应用时遍历稳定 placement / component 顺序，将 `modifier` 按 slot 分发给 Player / WeaponSystem，并把 `program` 注册到 Runtime；`board_rule` 不进入 modifier 或事件链。同 id 的乘法效果逐份相乘。
6. 刷怪笼由 Runtime 的 module relation condition + interval trigger 驱动；10 秒后 `spawn_enemy` action 通过 Gateway 从冻结敌池与当前时间开放池交集锁定敌人和合法空地。执行失败保留 action state 且不重抽，离开模块按程序语义清空；生成敌人走普通奖励、掉落、击杀和内容进度链。
7. `GearModPickup` 根节点位置固定，只有视觉子节点悬浮 / 闪烁；无碰撞、无吸附、无超时。正式图标为 40 px CPU 星窗、2 px `#68BCDD` 轮缘、`star_scale=1.8`。
8. Run v19 保存 `gear_mods.next_instance_id`、行优先解锁格 / placements、GameplayEffectRuntime 程序状态和所有带 `instance_id` 的地面物；核心不保存。恢复校验棋盘、Runtime 来源与活动 / 模块缓存实例 ID 全局唯一。
9. 胜利、死亡、重开或回标题后随 run 一起清空；Meta v4 只保存官方 Gear Mod 横向可用资格，不保存本地 Mod、棋盘、实例、场上拾取物或库存。

缓存与事件规则保持：Mod 缓存独立抽取两次并左右生成；防御、生存、占点固定生成一件；金币祭坛最多两次且两次结果彼此不重复；血量祭坛不产 Mod；事件敌人仍可触发个体掉落。

## 6. Modifier 分层与确定性

Player 与 WeaponSystem 区分普通、临时和 Gear Mod 层。`set_gear_modifiers()` 替换旧 Gear 层后从基础值重建；同一 placements 快照重复重建必须得到相同结果，不能在旧运行时结果上继续累加。

重复实例的效果属于合法构筑叠加：两份伤害 Mod 产生 `1.20 × 1.20 = 1.44`，两份后坐或扩散 Mod 产生 `0.80 × 0.80 = 0.64`。Gear 层不混入普通 Player / Weapon snapshot；Run 恢复棋盘 placements 后只从 `modifier` 组件统一重建一次，再恢复 Runtime 程序状态，避免双重应用或重抽。

Replay v9 的 data fingerprint 包含规范化 Gear Mod v6 玩法数据：schema、棋盘、拾取配置、奖励池 / 贡献有序数组、Mod id / components / programs / 默认开放语义、原语契约、掉落表有序行和本地 `mod_environment`。名称、描述、稀有度、图标、`placement_sfx_id` 和本地化等展示 / 媒体字段不参与玩法指纹；本地 gameplay hash 只覆盖包内玩法数据。

## 7. UI、调试与测试

- 靠近提示显示绑定、名称；`modifier` / `program` / `board_rule` 使用中英文结构化效果描述。
- HUD 确认放置后只显示 Mod 名称；无合法格显示明确原因。
- `GearModBoardPanel` 左侧正式地图、右侧棋盘使用同向 7×7 坐标并同步高亮；查看模式按住 Tab，配置模式只允许选择合法空格和确认 / 取消。两者世界不停但完整锁定角色 intent。
- 结果页聚合排序后的实例为 `{mod_id,name_key,count}`，显示“名称 ×数量”。
- Codex 只显示 slot、rarity 和固定描述，不显示等级范围。
- 开发者测试岛每个 Mod 只有启用开关和显式坐标，不提供 rank / count / 移动控件；独立配置 schema v4 使用 `{mod_id,x,y}` 且同一 Mod ID 最多一项，旧 v3 直接重置。没有 ModuleWorld 时依赖模块关系的 program 不激活。

`gear-mod-smoke` 覆盖 v6 components、槽位-stat、复合 Mod、13 格掩码、四邻 / 对角 / 越界 / 占用、重复实例、核心、石头、解锁幂等、移动授权和固定效果；`effect-runtime-smoke` 覆盖程序与刷怪计划；`gear-mod-pickup-smoke` 覆盖确认 / 取消原子性、满盘留地、65536/65537、预占、非法快照以及真实 viewport 鼠标 hover / 点击棋盘格 / 点击确认。纯面板 `mouse_filter`、命中层级或鼠标路由修改只需该完整 pickup smoke、一次最终 file-scoped hook 与待人工验收；只有实际改到 InputService、UIManager、领域事务、Run 或 Replay 时才追加对应专项，golden 不记录原始鼠标命中。

## 8. 迁移与兼容

- `gear_mods.json` 只接受 schema v6，不迁移 v5 `kind` / behavior 数据。
- 旧 Run v18 保持源文件但不显示为可继续，不迁移为 v19；缺包、版本或 gameplay hash 不匹配同样保留文件并阻止继续，不按损坏档隔离。
- 旧 Replay v8 精确拒绝且不改写源文件，不提供迁移。
- Debug Test Arena 配置 v3 直接重置为 v4 默认，不推断旧选择的坐标。
