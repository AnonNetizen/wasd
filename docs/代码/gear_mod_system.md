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
- 通过 `SaveManager` 的 `meta` kind 保存和迁移跨局状态。

## 2. 非职责

- 不读取或管理 `user://mods/<mod_id>/mod.json`；那是 `ModLoader` 的本地数据包职责。
- 不绕过 `Combat`、`RNG`、`GameClock`、`SaveManager` 或 `DataLoader`。
- 不在局中动态修改玩家背包影响当前属性；当前 run 使用开局 loadout 快照，保障回放和续局稳定。
- 不做随机词条、交易、套装、极性或 Forma；这些属于后续扩展。

## 3. 规划代码地图

| 路径 | 责任 |
|------|------|
| `client/scripts/autoload/gear_mod_system.gd` | 运行时主入口；读取数据、维护 profile、输出 modifiers |
| `client/data/gear_mods.json` | 装备 Mod 定义、slot、rarity、rank 效果和 drain |
| `client/data/gear_mod_drop_tables.csv` | Mod 掉落来源与概率 |
| `client/data/gear_mod_fusion_costs.csv` | Mod 升级成本 |
| `client/scripts/ui/gear_mod_panel.gd` / `.tscn` | 标题菜单下的最小装备 Mod UI |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 新局开始时读取 loadout 快照并应用英雄 / 武器 modifiers |
| `client/scripts/gameplay/enemy.gd` / `GameplayRunLoop` 击杀归因路径 | 玩家击杀普通小怪时触发 `RNG.drop` 掉落判定 |
| `client/tools/gear_mod_smoke.gd` | 首片 headless 验证 |

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

掉落表首片使用 `enemy_chaser -> weapon damage Mod -> 1%`，但实现时禁止按 enemy id 写逻辑分支；应由数据表声明 source，再由通用掉落解释器读取。

## 5. 运行流程

### 新建 / 读取 profile

1. `SaveManager.load(slot, "meta")` 读取 meta payload。
2. `GearModSystem` 归一化 `gear_mods` 字段，补默认资源、空背包和两套 loadout。
3. 如果旧 payload 含 `purchased_upgrades`，按迁移策略处理，避免继续输出旧永久升级 modifiers。

### 新局应用

1. 标题开始新局前，读取当前 `hero` / `weapon` loadout。
2. 校验装配仍合法；数据被删除或 rank 超限时 fail-fast 或安全卸下并记录诊断。
3. 生成 modifiers 快照。
4. `GameplayRunLoop` 配置玩家和武器后应用 modifiers。
5. run 快照保存已应用结果，续局不重新读取背包。

### 掉落

1. 玩家归因击杀敌人后，系统查 `gear_mod_drop_tables.csv`。
2. 所有随机走 `RNG.drop`。
3. 命中后写入 meta inventory，并通过 UI / HUD 提示获得 Mod。
4. 怪物互杀、机关击杀或非玩家归因击杀不掉落装备 Mod。

### 升级与分解

1. 升级读取 `gear_mod_fusion_costs.csv`，消耗资源并提升 rank。
2. rank 变化后如果已装备 Mod drain 变高导致容量不足，UI 必须阻止升级或要求先卸下；首片建议阻止升级并显示原因。
3. 分解重复 Mod 获得资源；已装备 Mod 不能直接分解。

## 6. 公共 API 草案

| API | 返回 | 说明 |
|-----|------|------|
| `profile_summary(slot := "slot_0")` | `Dictionary` | UI 摘要：资源、拥有数量、loadout 容量 |
| `mod_summaries(loadout_slot)` | `Array[Dictionary]` | UI 列表：rank、drain、可装备状态、效果 |
| `equip_mod(loadout_slot, instance_id)` | `Dictionary` | 装备 Mod；容量 / 槽位 / 唯一规则不满足时返回原因 |
| `unequip_mod(loadout_slot, instance_id)` | `Dictionary` | 卸下 Mod |
| `upgrade_mod(instance_id)` | `Dictionary` | 消耗资源升级 |
| `dismantle_mod(instance_id)` | `Dictionary` | 分解未装备 Mod |
| `grant_mod(mod_id, count := 1)` | `Dictionary` | 掉落 / 调试授予 |
| `current_modifiers(loadout_slot)` | `Array[Dictionary]` | 输出 hero 或 weapon modifiers |

## 7. 依赖

- `DataLoader`：读取装备 Mod、掉落表和成本表。
- `SaveManager`：保存 `meta` payload 和迁移。
- `RNG.drop`：掉落判定。
- `ModifierEngine` / `Player` / `WeaponSystem`：应用修正。
- `UIManager` / `Localization`：装备 Mod UI 与双语文案。
- `Analytics`：后续可记录获得、升级、分解和装备事件。

## 8. 测试义务

首片实现至少覆盖：

- 数据校验：Mod id、slot、rarity、rank、drain、modifier stat、掉落表 source、成本表 rank。
- profile roundtrip：新档默认字段、旧 meta payload 迁移、保存 / 读取一致。
- 掉落：固定 seed 下 `enemy_chaser` 玩家击杀可以触发或稳定不触发；概率边界用合成高概率测试。
- 装备：容量不足、槽位不匹配、同 id 重复装备被拒绝。
- 升级：资源扣除、rank 增长、drain / 效果变化，满级拒绝。
- 分解：已装备拒绝，未装备返还资源。
- 新局应用：hero / weapon modifiers 只在新局配置时应用，run 续局使用快照。

建议新增 `python tools/godot_bridge.py --project client gear-mod-smoke`。如果暂时复用 `meta-smoke`，必须在文档和工具输出中明确覆盖 GearModSystem。

## 9. 迁移说明

旧 `MetaProgressionSystem` 是 F6 首切片实现，不再作为未来局外成长方向。实现 F11 时建议：

1. 新增 `GearModSystem` 并保留 `SaveManager` 的 `meta` kind。
2. 停止 `MetaProgressionSystem.current_modifiers()` 对下一局属性的影响。
3. 将旧 `meta_progression.json` 标记为 legacy 或删除，删除前先完成 DataLoader / UI / smoke 引用替换。
4. 旧 `purchased_upgrades` 迁移成补偿资源或 starter Mod；迁移策略写入 ADR 和 smoke。
