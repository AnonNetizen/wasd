# Gear Mod 局内规则服务

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 权威：GDD §7.2、ADR #188 / #191、`docs/词表与契约.md` §13。

## 1. 定位

`GearModSystem` 是无状态 autoload 规则服务，只负责解释 Gear Mod 数据：定义、rank modifier、敌人掉落、公共奖励池、手动拾取配置、下一阶预览、最大 rank 和满阶金币。它不拥有库存、实例、loadout、容量、dust 或 Meta 写入能力。

本文件中的 Gear Mod 是局内构筑系统；`ModLoader` 仍指 `user://mods/<mod_id>/mod.json` 本地数据包接口，两者没有运行时依赖。

## 2. 权威边界

| 责任 | 权威 |
|------|------|
| Mod 定义、slot、rarity、max rank、rank 曲线、公共池、拾取配置、溢出金币 | `client/data/gear_mods.json` schema v3 |
| 敌人来源、掉率、等级范围 | `client/data/gear_mod_drop_tables.csv` |
| 本局 `{mod_id: rank}`、掉落实体、交互仲裁、授予、升阶、溢出金币、保存恢复 | `GameplayRunLoop` + `GearModPickup` |
| hero / weapon Gear modifier 实际应用 | `Player.set_gear_modifiers()` / `WeaponSystem.set_gear_modifiers()` |
| 正式玩家 UI | HUD 获得反馈与结果页最终构筑；无标题配置面板 |
| 隔离预览 | 开发者测试岛 `resolve_preview_loadout()`，不读写正式 Meta / Run |

## 3. 数据 schema

`gear_mods.json` 根字段严格为：

- `schema_version = 3`
- `overflow_gold`：满 rank 后每份重复转化的局内金币，当前为 75
- `pickup`：固定 `pool_id=gear_mod_pickup`、`interaction_radius=72`、`spawn_vertical_offset=-36`、`spawn_spread=28`
- `reward_pools[]`：`id` + `mod_ids[]`；当前公共池 `world_event_mod_pool_common`
- `mods[]`：`id`、`name_key`、`desc_key`、`slot`、`rarity`、`max_rank`、`rank_modifiers[]`

rank modifier 使用通用 `{stat,type,base_value,value_per_rank}`。实际值为：

```text
value = base_value + value_per_rank * clamp(rank, 0, max_rank)
```

当前三张武器 Mod：

| Mod | rank 0 → 5 | 敌人 | 掉率 |
|-----|------------|------|------|
| 伤害 | `damage mult 1.10 → 1.35` | `enemy_chaser` | 5% |
| 后坐阻尼 | `recoil mult 0.90 → 0.65` | `enemy_bulwark` | 15% |
| 扩散稳定 | `spread_angle_max mult 0.90 → 0.65` | `enemy_spitter` | 2.5% |

只有玩家归因击杀触发掉落，随机走 `RNG.drop`；系统只返回命中结果，不改变任何局内或跨局状态。

## 4. 公共 API

| API | 返回 | 语义 |
|-----|------|------|
| `roll_drop_for_enemy(enemy_id, enemy_level := 1, forced_roll := -1.0, allowed_mod_ids := [])` | `Dictionary` | 先按本局内容快照过滤掉落行，再解释匹配项；正式随机走 `RNG.drop`，forced 只供自动测试 |
| `mod_definition(mod_id)` | `Dictionary` | 返回定义副本，未知 id 返回空字典 |
| `rank_modifiers(mod_id, rank)` | `Array[Dictionary]` | 钳制 rank 后解析通用 modifiers |
| `max_rank(mod_id)` | `int` | 返回定义的最大内部 rank |
| `overflow_gold()` | `int` | 当前返回 75 |
| `pickup_config()` | `Dictionary` | 返回统一拾取配置副本；运行时不得自行写死半径或偏移 |
| `next_grant_preview(mod_id, current_rank)` | `Dictionary` | 返回拾取后的显示阶级、该阶完整 modifiers 或满阶 75 金币预览，不改变状态 |
| `reward_pool_ids(pool_id, allowed_mod_ids := [])` | `Array[String]` | 返回与本局内容快照求交后的公共池候选副本；空过滤参数供开发者测试岛访问全部内容 |
| `resolve_preview_loadout(selections)` | `Dictionary` | 开发者测试岛纯内存预览；无容量 / drain / 存档副作用 |

## 5. GameplayRunLoop 授予语义

`GameplayRunLoop` 是唯一局内权威：

1. 新局清空 `_run_gear_mod_ranks`。
2. 首次获得写入 rank 0，玩家显示第 1 阶。
3. 重复获得依次升至 rank 5 / 第 6 阶。
4. 第 7 份及以后每份转化为 75 局内金币，reason 为 `gear_mod_overflow`。
5. 敌人、缓存和世界事件在奖励产生时锁定 `mod_id` 并生成池化 `GearModPickup`；接触不会拾取，只有最近交互仲裁选中并收到一次 `interact` 后才调用原子授予入口。
6. `GearModPickup` 根节点位置固定，只有视觉子节点悬浮 / 闪烁；无碰撞、无吸附、无超时。正式图标为 40 px CPU 星窗、2 px `#68BCDD` 轮缘、`star_scale=1.8`。
7. Run v16 保存 `gear_mods.ranks`、顶层活动 `gear_mod_pickups`、非活动模块槽内拾取快照与冻结 `content_availability`。恢复不重抽；未知、锁定、非有限位置或多余字段使 Run 恢复失败。
8. 胜利、死亡、重开或回标题后随 run 一起清空；Meta v4 只保存 Gear Mod 的横向可用资格，不保存任何本局 rank、场上拾取物或库存。

缓存与事件规则：

- Mod 缓存从公共池独立抽取 2 次，再在来源上方左右各偏移 28 px 生成两件。
- 防御、生存、占点固定生成 1 个等权普通 Mod 拾取物。
- 金币祭坛成功时生成 Mod，最多两次且不重复，两次分别落在左右位置。
- 血量祭坛不产 Mod。
- 事件敌人仍可正常触发个体掉落。

## 6. Modifier 分层

Player 与 WeaponSystem 必须区分普通、临时和 Gear Mod 层。`set_gear_modifiers()` 的参数替换旧 Gear 层，然后从基础值重建；重复传入同一数组必须得到相同结果，禁止在当前结果上继续相加或相乘。

Player 与 WeaponSystem 的普通 modifier snapshot / restore 语义必须对称。Gear 层不混入普通 modifier snapshot；它由 Run v16 ranks 统一恢复，避免双重应用。

## 7. UI 与测试

- 靠近提示：显示名称、拾取后阶级和该阶完整效果；乘法值按相对 `1.0` 的有符号百分比显示，加法值显示有符号数值，多效果用分隔符连接；满阶显示转化 75 金币。
- HUD：成功拾取后才调用 `show_gear_mod_drop_feedback(name_key, display_rank, overflow_gold)`；普通显示第 1–6 阶，满阶显示金币转化。
- 结果页：成功与死亡都显示 `{gear_mods:[{mod_id,name_key,rank,display_rank}]}` 最终构筑。
- 正式标题页：没有 Gear Mod 按钮或配置面板。
- 开发者测试岛：可选择 Mod / rank 做纯内存预览，不显示容量或 drain，不读写正式 Meta。

`gear-mod-smoke` 必须覆盖空开局、rank 0–5、第七份 75 金币、不同 Mod 独立、即时生效、新局清空、Run 恢复和 Player / Weapon 替换幂等；`gear-mod-pickup-smoke` 覆盖正式 SVG / Shader / 对象池、距离、接触不拾取、逐件最近交互、提示、溢出、授予失败保留和非法快照；runtime / world-event / module-world / save smoke 覆盖各奖励来源与跨模块 / 续局恢复。
