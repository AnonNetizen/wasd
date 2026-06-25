# GearModSystem 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是装备 Mod 装配系统的代码契约草案；改数据 schema、存档 payload、掉落 / 升级 / 分解规则、UI 入口或测试义务时，必须同步 F11 工作包、GDD、AI 导航、`client/data/README.md`、测试策略、ADR 和 AI 记忆。

## 1. 职责

`GearModSystem` 将替代旧 `MetaProgressionSystem` 的永久升级轨道，作为跨局成长的主要运行时入口。它负责：

- 读取装备 Mod 定义、掉落表和升级成本。
- 管理玩家拥有的 Mod、rank、重复数量或实例。
- 管理两套 loadout：英雄 Mod 与武器 Mod。
- 校验容量、槽位、唯一装备规则和资源消耗。
- 在新局开始时输出英雄 / 武器 modifiers，交给现有 `ModifierEngine` / `Player` / `WeaponSystem` 管线应用。
- 通过 `SaveManager` 的 `meta` kind 保存和迁移跨局状态，并把旧 `purchased_upgrades` 已购成本补偿为 Gear Mod 升级资源。

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
| `client/scripts/gameplay/gameplay_run_loop.gd` | 新局开始时读取 hero / weapon loadout 快照并分别应用到 Player / WeaponSystem；玩家归因击杀时请求 Gear Mod 掉落并转发 HUD 获得提示 |
| `client/scripts/gameplay/enemy.gd` / `GameplayRunLoop` 击杀归因路径 | 玩家击杀普通小怪时触发 `RNG.drop` 掉落判定 |
| `client/tools/gear_mod_smoke.gd` | F11 headless smoke，覆盖 profile、旧 purchased_upgrades 补偿、授予、装备、容量、升级、分解、掉落、HUD 获得提示和 Gear Mod 面板按钮流 |
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

1. `SaveManager.load(slot, "meta")` 读取 meta payload。
2. `GearModSystem` 归一化 `gear_mods` 字段，补默认资源、空背包、两套 loadout 和稳定 `next_instance_index`。
3. 当前实现保留旧 `purchased_upgrades`、账号等级、旧货币和解锁字段作为 legacy 数据；`GearModSystem` 会按旧升级表成本把尚未补偿的已购等级折算为 `gear_mod_dust`，并在 `gear_mods.legacy_migration.purchased_upgrades_compensation` 记录已补偿等级；`GameplayRunLoop` 已停止读取 `MetaProgressionSystem.current_modifiers()`，旧购买轨道不再影响下一局属性。

### 新局应用

1. 标题开始新局前，读取当前 `hero` / `weapon` loadout。
2. 校验装配仍合法；数据被删除或 rank 超限时 fail-fast 或安全卸下并记录诊断。
3. 生成 hero / weapon 两组 modifiers 快照。
4. `GameplayRunLoop` 配置玩家和武器后，把 hero modifiers 应用到 `Player.apply_modifiers()`，weapon modifiers 应用到 `WeaponSystem.apply_modifiers()`。
5. run 快照保存已应用结果，续局不重新读取背包。

### 掉落

1. 玩家归因击杀敌人后，系统查 `gear_mod_drop_tables.csv`。
2. 所有随机走 `RNG.drop`。
3. 命中后写入 meta inventory，并把 `name_key` 放进掉落结果；`GameplayRunLoop` 转发给 `GameplayHud.show_gear_mod_drop_feedback()`，显示本地化获得提示。
4. 怪物互杀、机关击杀或非玩家归因击杀不掉落装备 Mod。

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
| `equip_mod(loadout_slot, instance_id, slot := "slot_0")` | `Dictionary` | 装备 Mod；容量 / 槽位 / 唯一规则不满足时返回原因 |
| `unequip_mod(loadout_slot, instance_id, slot := "slot_0")` | `Dictionary` | 卸下 Mod |
| `upgrade_mod(instance_id, slot := "slot_0")` | `Dictionary` | 消耗 `gear_mod_fusion_costs.csv` 声明资源升级；已装备且升级后超容量时拒绝 |
| `dismantle_mod(instance_id, slot := "slot_0")` | `Dictionary` | 分解未装备 Mod 并返还资源；已装备 Mod 拒绝 |
| `roll_drop_for_enemy(enemy_id, enemy_level := 1, slot := "slot_0", forced_roll := -1.0)` | `Dictionary` | 解释掉落表并用 `RNG.drop` 判定；`forced_roll` 仅供 smoke / 调试稳定覆盖 |
| `current_modifiers(loadout_slot, slot := "slot_0")` | `Array[Dictionary]` | 输出 hero 或 weapon modifiers |
| `current_all_modifiers(slot := "slot_0")` | `Dictionary` | 同时输出两套 loadout modifier |
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
- profile roundtrip：新档默认字段、旧 meta payload 兼容、保存 / 读取一致。
- 旧档补偿：旧 `purchased_upgrades` 已购等级按 `meta_progression.json` 成本折算为 `gear_mod_dust`，补偿记录保证二次读取不重复发放。
- 掉落：`gear-mod-smoke` 用 `forced_roll=0.0` 稳定覆盖 `enemy_chaser` 掉落；真实运行时玩家归因击杀走 `RNG.drop` 和 1% 数据概率。
- 装备：容量不足、槽位不匹配、同 id 重复装备被拒绝。
- 升级：资源扣除、rank 增长、drain / 效果变化，已装备超容量拒绝。
- 分解：已装备拒绝，未装备返还资源。
- UI：`gear-mod-smoke` 实例化 `GearModPanel`，验证标题、资源、Mod 行、详情效果、装备、升级、卸下、分解和反馈文案解析。
- 新局应用：hero / weapon modifiers 只在新局配置时应用，run 续局使用快照。

当前专用命令为 `python tools/godot_bridge.py --project client gear-mod-smoke`。改 `GameplayRunLoop` 开局应用或死亡结算旁路时，追加 `runtime-smoke`；改旧 F6 迁移兼容时，追加 `meta-smoke` 和 `save-smoke`。

## 10. 迁移说明

旧 `MetaProgressionSystem` 是 F6 首切片实现，不再作为未来局外成长方向。实现 F11 时建议：

1. 已新增 `GearModSystem` 并保留 `SaveManager` 的 `meta` kind，Gear Mod 状态写入 `meta.gear_mods`。
2. 已停止 `MetaProgressionSystem.current_modifiers()` 对 `GameplayRunLoop` 下一局属性的影响；该 API 仅保留 legacy smoke / 迁移参考。
3. `meta_progression.json` 与 `MetaProgressionPanel` 当前仍保留为 legacy UI / 回归诊断，删除前必须完成 smoke 替换和人工迁移 checklist。
4. 旧 `purchased_upgrades` 补偿策略已由 ADR #116 落地：每个旧升级轨道按已购等级的历史花费 1:1 折算为 `gear_mod_dust`，只补偿尚未记录的等级，旧字段不删除。
