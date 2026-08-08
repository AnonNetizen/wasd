# Gear Mod 局内规则服务

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 Gear Mod 数据、公共 API、局内实例、持久化与测试边界的代码契约权威；常见联动为 GDD §7.2、ADR #191 / #193、`docs/词表与契约.md` §13、Gameplay Runtime 与 SaveManager 文档。

## 1. 定位

`GearModSystem` 是无状态 autoload，只解释 Gear Mod 定义、固定 modifier、敌人掉落、公共奖励池和手动拾取配置。`GameplayRunLoop` 持有可重复的本局 Mod 实例并负责授予、应用、结果摘要和 Run 快照。

Gear Mod 没有 rank、tier、最大等级、升级预览、满阶、溢出补偿或批量授予接口。以后若重新设计升级机制，必须建立新 ADR 和新 schema；不得在当前 API 中预留休眠字段或兼容壳。

这里的 Gear Mod 是局内构筑系统；`ModLoader` 仍指 `user://mods/<mod_id>/mod.json` 本地数据包接口，两者没有运行时依赖。

## 2. 权威边界

| 责任 | 权威 |
|------|------|
| Mod 定义、slot、rarity、固定 modifiers、公共池、拾取配置 | `client/data/gear_mods.json` schema v4 |
| 敌人来源、掉率、敌人等级范围 | `client/data/gear_mod_drop_tables.csv` |
| 可重复的本局 `mod_ids`、掉落实体、交互仲裁、单份授予、保存恢复 | `GameplayRunLoop` + `GearModPickup` |
| hero / weapon Gear modifier 实际应用 | `Player.set_gear_modifiers()` / `WeaponSystem.set_gear_modifiers()` |
| 内容可用资格 | `ContentUnlockSystem` 冻结的 `content_availability.gear_mod` |
| 正式玩家 UI | HUD 获得反馈、Codex 固定资料与结果页数量聚合；无标题配置面板 |
| 隔离预览 | 开发者测试岛 `resolve_preview_loadout()`，只接受 `{mod_id}`，不读写正式 Meta / Run |

## 3. 数据 schema

`gear_mods.json` 根字段严格为：

- `schema_version = 4`
- `pickup`：固定 `pool_id=gear_mod_pickup`、`interaction_radius=72`、`spawn_vertical_offset=-36`、`spawn_spread=28`
- `reward_pools[]`：`id` + 有序 `mod_ids[]`
- `mods[]`：`id`、`name_key`、`desc_key`、`slot`、`rarity`、固定 `modifiers[]`，以及可选内容解锁 / 图鉴字段

固定 modifier 形状为 `{stat,type,value}`。双端校验器必须明确拒绝 `overflow_gold`、`max_rank`、`rank_modifiers`、`base_value` 和 `value_per_rank`，不能静默忽略旧等级字段。

当前三张武器 Mod：

| Mod | 固定效果 | 敌人 | 掉率 |
|-----|----------|------|------|
| 伤害 | `damage mult 1.20` | `enemy_chaser` | 5% |
| 后坐阻尼 | `recoil mult 0.80` | `enemy_bulwark` | 15% |
| 扩散稳定 | `spread_angle_max mult 0.80` | `enemy_spitter` | 2.5% |

只有玩家归因击杀触发掉落，随机走 `RNG.drop`。奖励源不按本局已持有 id 过滤候选；重复抽到同 id 仍生成可拾取实例。金币祭坛现有“两次结果彼此不重复”规则保持，但不检查玩家所有权。

## 4. 公共 API

| API | 返回 | 语义 |
|-----|------|------|
| `roll_drop_for_enemy(enemy_id, enemy_level := 1, forced_roll := -1.0, allowed_mod_ids := [])` | `Dictionary` | 先按本局内容快照过滤掉落行，再解释匹配项；正式随机走 `RNG.drop`，forced 只供自动测试 |
| `mod_definition(mod_id)` | `Dictionary` | 返回定义副本，未知 id 返回空字典 |
| `modifiers(mod_id)` | `Array[Dictionary]` | 返回该 Mod 的固定 modifier 副本，未知 id 返回空数组 |
| `pickup_config()` | `Dictionary` | 返回统一拾取配置副本；运行时不得自行写死半径或偏移 |
| `reward_pool_ids(pool_id, allowed_mod_ids := [])` | `Array[String]` | 返回与本局内容快照求交后的有序公共池候选副本 |
| `resolve_preview_loadout(selections)` | `Dictionary` | 开发者测试岛纯内存预览；每项只含 `mod_id`，无等级、数量、容量、drain 或存档副作用 |

不提供 `rank_modifiers()`、`max_rank()`、`overflow_gold()`、`next_grant_preview()` 或同义接口。拾取提示直接组合 `mod_definition()` 与 `modifiers()`，不增加升级预览门面。

## 5. GameplayRunLoop 运行语义

1. 新局清空 `_run_gear_mod_ids`。
2. 每次成功拾取只追加一个 `mod_id`；同 id 可重复出现，没有上限、满阶或资源转换。
3. 授予入口不接受 count / rank 参数，也不返回等级或升级状态。
4. 应用时遍历排序后的每个实例，将对应固定 modifiers 按 slot 分发给 Player / WeaponSystem；同 id 的乘法效果逐份相乘。
5. 敌人、缓存和世界事件在奖励产生时锁定 `mod_id` 并生成池化 `GearModPickup`；接触不会拾取，只有最近交互仲裁选中并收到一次 `interact` 后才调用单份授予入口。
6. `GearModPickup` 根节点位置固定，只有视觉子节点悬浮 / 闪烁；无碰撞、无吸附、无超时。正式图标为 40 px CPU 星窗、2 px `#68BCDD` 轮缘、`star_scale=1.8`。
7. Run v17 保存 `gear_mods.mod_ids`、顶层活动 `gear_mod_pickups`、非活动模块槽内拾取快照与冻结 `content_availability`。`mod_ids` 允许重复，保存 / 恢复 / 摘要使用排序副本；未知、锁定、非字符串 id、非有限位置或多余字段使恢复失败。
8. 胜利、死亡、重开或回标题后随 run 一起清空；Meta v4 只保存 Gear Mod 的横向可用资格，不保存本局实例、场上拾取物或库存。

缓存与事件规则保持：Mod 缓存独立抽取两次并左右生成；防御、生存、占点固定生成一件；金币祭坛最多两次且两次结果彼此不重复；血量祭坛不产 Mod；事件敌人仍可触发个体掉落。

## 6. Modifier 分层与确定性

Player 与 WeaponSystem 区分普通、临时和 Gear Mod 层。`set_gear_modifiers()` 替换旧 Gear 层后从基础值重建；同一实例数组重复重建必须得到相同结果，不能在旧运行时结果上继续累加。

重复实例的效果属于合法构筑叠加：两份伤害 Mod 产生 `1.20 × 1.20 = 1.44`，两份后坐或扩散 Mod 产生 `0.80 × 0.80 = 0.64`。Gear 层不混入普通 Player / Weapon snapshot；Run 恢复实体后由 `mod_ids` 统一重建一次，避免双重应用。

Replay v7 的 data fingerprint 包含规范化 Gear Mod 玩法数据：schema、拾取配置、奖励池有序数组、Mod id / slot / fixed modifiers / 默认开放语义和掉落表有序行。名称、描述、图标和本地化等展示字段不参与指纹。

## 7. UI、调试与测试

- 靠近提示只显示绑定、名称和固定效果；乘法值按相对 `1.0` 的有符号百分比显示，多效果用分隔符连接。
- HUD 成功拾取后只显示 Mod 名称，不显示阶级或金币转换。
- 结果页聚合排序后的实例为 `{mod_id,name_key,count}`，显示“名称 ×数量”。
- Codex 只显示 slot、rarity 和固定描述，不显示等级范围。
- 开发者测试岛每个 Mod 只有启用开关，不提供 rank 或 count 控件；独立配置 schema v3 的选择项只含 `mod_id`，旧 v2 直接重置。

`gear-mod-smoke` 覆盖固定效果、重复实例乘算、即时生效、新局清空、Run 恢复和替换式应用幂等；`gear-mod-pickup-smoke` 覆盖正式 SVG / Shader / 对象池、距离、接触不拾取、逐件最近交互、固定提示、重复拾取、授予失败保留和非法快照。runtime / world-event / module-world / save / replay smoke 覆盖各奖励来源、跨模块恢复、Run v17 拒绝旧局与 Replay v7 确定性。

## 8. 迁移与兼容

- `gear_mods.json` 只接受 schema v4，不迁移 v3 数据。
- Run v16→v17 只推进 schema 并标记 `legacy_run_incompatible=true`；不读取或折算 `gear_mods.ranks`。正式加载只删除 Run，Meta v4 保留。
- Replay v6 精确拒绝且不改写源文件，不提供迁移。
- Debug Test Arena 配置 v2 直接重置为 v3 默认，不保留或推断旧 rank。
