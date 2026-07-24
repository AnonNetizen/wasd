# GearModSystem 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是装备 Mod 装配系统的代码契约草案；改数据 schema、存档 payload、掉落 / 升级 / 分解规则、UI 入口或测试义务时，必须同步 F11 工作包、GDD、AI 导航、`client/data/README.md`、测试策略、ADR 和 AI 记忆。

## 1. 职责

`GearModSystem` 已替代旧永久升级轨道，作为跨局成长的主要运行时入口。它负责：

- 读取装备 Mod 定义、掉落表和升级成本。
- 管理玩家拥有的 Mod、rank、重复数量或实例。
- 管理两套 loadout：英雄 Mod 与武器 Mod。
- 校验容量、槽位、唯一装备规则和资源消耗。
- 在新局开始时输出英雄 / 武器 modifiers，交给现有 `ModifierEngine` / `Player` / `WeaponSystem` 管线应用。
- 通过 `SaveManager` 的 `meta` kind 保存跨局装备 Mod 状态。
- 为 ADR #159 的开发者测试岛提供纯内存预览解析：不读取背包 / 货币或存档，仍复用正式 slot、`unique_by_id`、rank、drain 与容量规则。

## 2. 非职责

- 不读取或管理 `user://mods/<mod_id>/mod.json`；那是 `ModLoader` 的本地数据包职责。
- 不绕过 `Combat`、`RNG`、`GameClock`、`SaveManager` 或 `DataLoader`。
- 不在局中动态修改玩家背包影响当前属性；当前 run 使用开局 loadout 快照，保障回放和续局稳定。
- 不做随机词条、交易、套装、极性或 Forma；这些属于后续扩展。

## 3. 代码地图

| 路径 | 责任 |
|------|------|
| `client/scripts/autoload/gear_mod_system.gd` | 运行时主入口；读取数据，维护 `meta.gear_mods` profile，处理授予 / 掉落 / 装配 / 升级 / 分解，输出英雄 / 武器 modifiers |
| `client/data/gear_mods.json` | 装备 Mod 定义、slot、rarity、rank 效果、drain 和分解返还 |
| `client/data/gear_mod_drop_tables.csv` | Mod 掉落来源与概率 |
| `client/data/gear_mod_fusion_costs.csv` | Mod 升级成本 |
| `client/scripts/ui/gear_mod_panel.gd` / `.tscn` | 标题菜单下的最小装备 Mod UI：切换英雄 / 武器 loadout、查看资源 / 容量 / Mod 效果，并执行装备、卸下、升级和分解 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 新局开始时读取 hero / weapon loadout 快照并分别应用到 Player / WeaponSystem；玩家归因击杀时请求 Gear Mod 掉落并转发 HUD 暂存提示；F12 兴趣点奖励先进入 `run.pending_loot`，完成小巢核或未来撤离成功时再调用 `grant_resource()` / `grant_mod()` 结算 dust / Mod |
| `client/scripts/gameplay/enemy.gd` / `GameplayRunLoop` 击杀归因路径 | 玩家击杀普通小怪时触发 `RNG.drop` 掉落判定 |
| `client/tools/gear_mod_smoke.gd` | F11 headless smoke，覆盖 profile、授予、装备、容量、升级、分解、掉落、HUD 暂存提示和 Gear Mod 面板按钮流 |
| `tools/godot_bridge.py` | `gear-mod-smoke` 命令入口 |

## 4. 数据契约草案

`gear_mods.json` 每条 Mod 至少包含：

| 字段 | 说明 |
|------|------|
| `id` | 装备 Mod id；实现前进入词表 |
| `name_key` / `desc_key` | 玩家可见名称 / 描述 |
| `slot` | `hero` 或 `weapon` |
| `rarity` | 稀有度，用于升级成本和掉落展示 |
| `max_rank` | 最大 rank |
| `base_drain` / `drain_per_rank` | 装备容量消耗 |
| `rank_modifiers[]` | 按 rank 计算的 modifier，stat 必须来自词表 |
| `stack_rule` | 首片使用 `unique_by_id`，同一 loadout 不可装备重复 id |
| `dismantle` | 分解返还资源；首片为 `gear_mod_dust`，返还量低于一次升级成本 |

掉落表首片使用 `enemy_chaser -> weapon damage Mod -> 1%`，但实现时禁止按 enemy id 写逻辑分支；应由数据表声明 source，再由通用掉落解释器读取。

当前 F11 数据 / 契约首片已经建立：`gear_mod_weapon_damage_test` 为 `weapon` 槽普通 Mod，rank 0 提供 `damage mult 1.10`，每 rank 额外 `+0.05`，`enemy_chaser` 玩家归因击杀掉落率为 `0.01`，升级消耗 `gear_mod_dust`。

## 5. 运行流程

### 新建 / 读取 profile

1. `SaveManager.load(slot, "meta")` 读取 meta payload；缺档时由 `GearModSystem` 直接创建 `gear_mods` 子 payload。
2. `GearModSystem` 归一化 `gear_mods` 字段，补默认资源、空背包、两套 loadout 和稳定 `next_instance_index`。
3. 项目尚未上线，不保留旧局外成长测试档迁移；`GearModSystem` 不读取旧 `purchased_upgrades`、旧货币或旧账号等级字段。

### 新局应用

1. 标题开始新局前，读取当前 `hero` / `weapon` loadout。
2. 校验装配仍合法；数据被删除或 rank 超限时 fail-fast 或安全卸下并记录诊断。
3. 生成 hero / weapon 两组 modifiers 快照。
4. `GameplayRunLoop` 配置玩家和武器后，把 hero modifiers 应用到 `Player.apply_modifiers()`，weapon modifiers 应用到 `WeaponSystem.apply_modifiers()`。
5. run 快照保存已应用结果，续局不重新读取背包。

### 掉落

1. 玩家归因击杀敌人后，系统查 `gear_mod_drop_tables.csv`。
2. 所有随机走 `RNG.drop`。
3. 默认 API 调用命中后可立即写入 meta inventory；F12 标准局由 `GameplayRunLoop` 传入 `commit_immediately=false`，只返回掉落 `mod_id` / `name_key` 并放入 `run.pending_loot`。
4. `GameplayRunLoop` 转发给 `GameplayHud.show_gear_mod_drop_feedback()`，显示本地化暂存提示。
5. 怪物互杀、机关击杀或非玩家归因击杀不掉落装备 Mod。

### 兴趣点奖励

1. F12 `warzone_directors.json.interest_points[]` 可声明 `resource_rewards[]` 与 `gear_mod_rewards[]`。
2. `GameplayRunLoop` 领取兴趣点时只把奖励写入 `run.pending_loot`，不立即写入 `meta.gear_mods` profile。
3. 击破小巢核或未来撤离成功时，`GameplayRunLoop` 统一调用 `GearModSystem.grant_resource()` / `grant_mod()` 结算暂存战利品；死亡、重开、回标题或主动放弃会丢失未结算战利品。
4. 资源奖励显示 `ui_gear_mod_resource_obtained` HUD 暂存反馈；Mod 奖励复用掉落暂存反馈。

### 升级与分解

1. 升级读取 `gear_mod_fusion_costs.csv`，按 `rarity + rank` 消耗 `resource_id` 指定资源并提升 rank。
2. rank 变化后如果已装备 Mod drain 变高导致容量不足，UI 必须阻止升级或要求先卸下；首片建议阻止升级并显示原因。
3. 分解重复 Mod 获得资源；已装备 Mod 不能直接分解。

## 6. 公共 API 草案

| API | 返回 | 说明 |
|-----|------|------|
| `load_or_create_profile(slot := "slot_0")` | `Dictionary` | 读取并归一化 `meta.gear_mods`；缺档时创建并保存 |
| `profile_summary(slot := "slot_0")` | `Dictionary` | UI 摘要：资源、拥有数量、loadout 容量和已用 drain |
| `mod_summaries(loadout_slot, slot := "slot_0")` | `Array[Dictionary]` | UI 列表：rank、drain、可装备状态、升级消耗、分解返还、效果和 equipped 状态 |
| `grant_mod(mod_id, count := 1, slot := "slot_0")` | `Dictionary` | 掉落 / 调试授予；每个实例生成稳定 `instance_id` |
| `grant_resource(resource_id, amount, slot := "slot_0")` | `Dictionary` | 正式资源授予入口；F12 兴趣点和后续结算用它写入 `meta.gear_mods.resources` |
| `equip_mod(loadout_slot, instance_id, slot := "slot_0")` | `Dictionary` | 装备 Mod；容量 / 槽位 / 唯一规则不满足时返回原因 |
| `unequip_mod(loadout_slot, instance_id, slot := "slot_0")` | `Dictionary` | 卸下 Mod |
| `upgrade_mod(instance_id, slot := "slot_0")` | `Dictionary` | 消耗 `gear_mod_fusion_costs.csv` 声明资源升级；已装备且升级后超容量时拒绝 |
| `dismantle_mod(instance_id, slot := "slot_0")` | `Dictionary` | 分解未装备 Mod 并返还资源；已装备 Mod 拒绝 |
| `roll_drop_for_enemy(enemy_id, enemy_level := 1, slot := "slot_0", forced_roll := -1.0, commit_immediately := true)` | `Dictionary` | 解释掉落表并用 `RNG.drop` 判定；默认立即授予以兼容调试 / 面板 smoke，F12 标准局传 `false` 只返回掉落信息并交给 `run.pending_loot`；`forced_roll` 仅供 smoke / 调试稳定覆盖 |
| `current_modifiers(loadout_slot, slot := "slot_0")` | `Array[Dictionary]` | 输出 hero 或 weapon modifiers |
| `current_all_modifiers(slot := "slot_0")` | `Dictionary` | 同时输出两套 loadout modifier |
| `resolve_preview_loadout(selections, capacity := 8)` | `Dictionary` | 纯内存校验 `{mod_id, rank}` 列表并输出合法 selected、hero / weapon modifiers、used_drain 和 diagnostics；不调用 SaveManager |
| `debug_grant_resource(resource_id, amount, slot := "slot_0")` / `debug_set_loadout_capacity(loadout_slot, capacity, slot := "slot_0")` | `Dictionary` | 仅供 smoke / dev_tools 调试，仍走 `SaveManager` |

## 7. UI 行为

`GearModPanel` 由标题菜单“装备 Mod”入口打开，通过 `UIManager.push()` 叠在标题菜单上。面板默认显示武器 Mod，并可切换 `hero` / `weapon` 两套 loadout。

- 左侧列表只显示当前槽位可用的 Mod 实例；首片只有 `gear_mod_weapon_damage_test`，因此英雄页可能为空。
- 右侧详情显示名称、描述、rank、drain 与当前 rank 的 modifier 效果。
- 装备 / 卸下、升级、分解都调用 `GearModSystem` 公共 API；失败原因统一使用系统返回的 `reason` 本地化展示。
- 升级按钮展示下一 rank 的资源消耗；已满 rank 时禁用。
- 已装备 Mod 不能分解；已装备 Mod 升级后若会超过容量，`GearModSystem.upgrade_mod()` 拒绝并返回 `capacity_exceeded`。
- 所有 UI 文案在 `client/locale/strings.csv`，Godot 导入产物 `strings.zh_CN.translation` / `strings.en.translation` 需要随 CSV 变更更新。

## 8. 依赖

- `DataLoader`：读取装备 Mod、掉落表和成本表。
- `SaveManager`：保存 `meta` payload 和迁移。
- `RNG.drop`：掉落判定。
- `Player` / `WeaponSystem`：应用开局 loadout 修正；当前项目没有独立 `ModifierEngine` 运行时。
- `UIManager` / `Localization`：装备 Mod UI 与双语文案。
- `Analytics`：后续可记录获得、升级、分解和装备事件。

## 9. 测试义务

首片实现至少覆盖：

- 数据校验：Mod id、slot、rarity、rank、drain、modifier stat、掉落表 source、成本表 rank。
- profile roundtrip：新档默认字段、保存 / 读取一致。
- 掉落：`gear-mod-smoke` 用 `forced_roll=0.0` 稳定覆盖 `enemy_chaser` 掉落；真实运行时玩家归因击杀走 `RNG.drop` 和 1% 数据概率，并先进入 `run.pending_loot`。
- 兴趣点奖励：`runtime-smoke` 覆盖 resource cache / Mod cache / minor nest core 通过 `GameplayRunLoop` 写入 `run.pending_loot`，并验证 HUD 反馈、死亡不结算、续局恢复与完成面板结算。
- 装备：容量不足、槽位不匹配、同 id 重复装备被拒绝。
- 升级：资源扣除、rank 增长、drain / 效果变化，已装备超容量拒绝。
- 分解：已装备拒绝，未装备返还资源。
- UI：`gear-mod-smoke` 实例化 `GearModPanel`，验证标题、资源、Mod 行、详情效果、装备、升级、卸下、分解和反馈文案解析。
- 新局应用：hero / weapon modifiers 只在新局配置时应用，run 续局使用快照。
- 开发者预览：`debug-test-arena-smoke` 证明不需要 meta inventory 也能解析合法 Mod/rank，并验证 rank 对 drain / modifier 生效、正式 meta/run 哨兵不变。

当前正式专用命令为 `python tools/godot_bridge.py --project client gear-mod-smoke`。改纯预览接口或测试岛 modifier 应用时追加 `debug-test-arena-smoke`；改 `GameplayRunLoop` 开局应用、死亡面板或旧入口移除断言时，追加 `runtime-smoke`；改存档兼容时追加 `save-smoke`。

## 10. 退役说明

旧 `MetaProgressionSystem` 是 F6 首切片实现，ADR #117 后运行时代码与玩家入口已删除。ADR #118 进一步确认项目尚未上线，不维护旧测试档迁移：

1. `SaveManager` 的 `meta` kind 保持不变，Gear Mod 状态写入 `meta.gear_mods`。
2. `client/data/meta_progression.json`、旧 meta 契约常量和旧补偿逻辑已删除。
3. 测试存档如不符合当前 `meta.gear_mods` schema，直接重置或隔离，不补偿旧永久升级投入。
