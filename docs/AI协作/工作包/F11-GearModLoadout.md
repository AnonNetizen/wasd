# F11 Gear Mod Loadout 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是装备 Mod 装配系统的阶段工作包；改装备 Mod 范围、数据 schema、迁移边界或验收命令时，必须同步 GDD、ADR、`docs/AI导航.md`、`client/data/README.md`、`docs/代码/gear_mod_system.md`、测试策略与 AI 记忆。

## 1. 目标

F11 将现有 F6 局外永久升级轨道替换为参考《星际战甲》的装备 Mod 装配系统。首片只做两套可配置 Mod：

- **英雄 Mod 配置**：作用于英雄 / 玩家基础属性、拾取、生存或后续技能资源。
- **武器 Mod 配置**：作用于当前主武器属性，例如基础伤害、射速、弹速和暴击。

系统应提供长期刷取、升级、分解和装配取舍，而不是把所有永久属性无条件叠到下一局。玩家仍通过 `SaveManager` 的 `meta` kind 保存跨局档案，但旧 `MetaProgressionSystem` / `meta_progression.json` 的永久升级轨道要在实现阶段退役。

## 2. 首片范围

必须包含：

1. 新数据文件：`gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv` 或等价拆分。
2. 新运行时模块：`GearModSystem`，负责读取 Mod 定义、保存拥有列表 / rank / 装配、输出当前英雄与武器 modifiers。
3. 两套 loadout：`hero` 与 `weapon`，每套独立槽位、容量和已装备 Mod 列表。
4. 一张测试武器 Mod：增加武器基础 `damage`，普通小怪 `enemy_chaser` 被玩家击杀时有 `1%` 概率掉落。
5. Mod 升级：消耗局外资源提升 rank，rank 提高效果值与 drain。
6. Mod 分解：把重复或不需要的 Mod 转成升级资源。
7. 迁移策略：旧局外永久升级系统停止作为下一局属性来源；旧存档字段迁移或隔离为兼容数据，不能导致坏档。

当前实现状态（2026-06-25）：

- 已完成数据 / 契约首片：`gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv`、测试武器伤害 Mod、`gear_mod_dust`、DataLoader / validate_data / schema regression。
- 已完成运行时首片：`GearModSystem` autoload 保存 `meta.gear_mods`，支持 profile roundtrip、授予、英雄 / 武器 loadout、capacity / drain、唯一装备、升级、分解、`enemy_chaser` 玩家归因击杀掉落和开局 hero / weapon modifier snapshot。
- 已完成最小 UI：标题菜单进入 `GearModPanel`，可切换英雄 / 武器 loadout，查看资源、容量、rank、drain 和效果，并执行装备、卸下、升级和分解。
- 已完成专用验证：`python tools/godot_bridge.py --project client gear-mod-smoke` 覆盖授予、槽位拒绝、装备、重复拒绝、分解返还、容量阻止升级、资源升级、modifier 数值变化、强制掉落、获得提示和 Gear Mod 面板按钮流；`runtime-smoke` 覆盖玩家归因击杀后的强制掉落 HUD 提示路径。
- 待做：旧 `purchased_upgrades` 补偿迁移、更多 Mod 内容与手动迁移 checklist。

首片不做：

- 极性、Forma、不同武器类型专属槽、交易、套装加成、Riven 随机词条。
- 复杂背包筛选 / 排序 UI；可以先做最小可验证列表。
- 运行时玩家本地 mod 数据包扩展装备 Mod 核心契约。这里的装备 Mod 与 `ModLoader` 的本地数据包 mod 是两个概念。

## 3. 推荐数据边界

### `gear_mods.json`

复杂配置优先 JSON。建议结构：

```json
{
  "schema_version": 1,
  "mods": [
    {
      "id": "gear_mod_weapon_damage_test",
      "name_key": "gear_mod_weapon_damage_test_name",
      "desc_key": "gear_mod_weapon_damage_test_desc",
      "slot": "weapon",
      "rarity": "common",
      "max_rank": 5,
      "base_drain": 2,
      "drain_per_rank": 1,
      "rank_modifiers": [
        { "stat": "damage", "type": "mult", "base_value": 1.10, "value_per_rank": 0.05 }
      ],
      "stack_rule": "unique_by_id",
      "dismantle": {
        "resource_id": "gear_mod_dust",
        "amount": 10
      }
    }
  ]
}
```

`docs/词表与契约.md` 已登记首片 `gear_mod_*` id、slot、rarity、resource、stack rule 等需要代码引用的契约；新增条目前仍必须先登记并跑契约同步。

### `gear_mod_drop_tables.csv`

平表掉落优先 CSV。首片可用：

```csv
source_enemy_id,mod_id,drop_chance,min_enemy_level,max_enemy_level
enemy_chaser,gear_mod_weapon_damage_test,0.01,1,999
```

掉落必须在玩家归因击杀时触发，随机走 `RNG.drop`，不能让怪物互杀产出 Mod。

### `gear_mod_fusion_costs.csv`

平表成本优先 CSV：

```csv
rarity,rank,resource_id,cost
common,1,gear_mod_dust,20
common,2,gear_mod_dust,35
common,3,gear_mod_dust,55
common,4,gear_mod_dust,85
common,5,gear_mod_dust,130
```

资源来源为 Mod 分解和局外奖励。首片使用专用 `gear_mod_dust`（模组尘），避免和旧永久升级经济混在一起。

## 4. 存档与迁移

`meta` payload 新增或迁移到以下结构：

```json
{
  "gear_mods": {
    "resources": { "gear_mod_dust": 0 },
    "inventory": [
      { "instance_id": "uuid_or_stable_id", "mod_id": "gear_mod_weapon_damage_test", "rank": 0, "count": 1 }
    ],
    "loadouts": {
      "hero": { "capacity": 8, "equipped": [] },
      "weapon": { "capacity": 8, "equipped": ["instance_id"] }
    }
  }
}
```

实现要求：

- `SaveManager` 仍是唯一存档入口，`meta` kind 保留。
- `MetaProgressionSystem` 的旧购买轨道不能继续给下一局注入永久 modifiers；当前 `GameplayRunLoop` 已改为读取 `GearModSystem` 的 hero / weapon modifiers。
- 如果旧存档已有 purchased upgrades，首片当前保留为 legacy 字段但不生效；后续应迁移为补偿资源、starter Mod 或其它可解释补偿，具体策略必须写 ADR / 模块文档并覆盖 smoke。
- `run` 存档只需要记录开局时已应用的 loadout/modifier 快照；不要在局中读取玩家背包实时改属性。

## 5. UI / 操作边界

当前最小 UI 已支撑验证：

- 标题菜单进入“装备 Mod”界面。
- 切换英雄 / 武器两套配置。
- 查看 Mod 名称、rank、drain、效果、拥有数量。
- 装备 / 卸下 Mod，容量不足时阻止并显示原因。
- 升级 Mod，资源不足时阻止。
- 分解 Mod，获得资源。

所有玩家可见文本走 `client/locale/strings.csv`，英文 `en` 文案长度作为布局验收基准。

玩家归因击杀触发 Mod 掉落时，`GameplayRunLoop` 会把掉落结果交给 `GameplayHud.show_gear_mod_drop_feedback()`，用 `ui_gear_mod_drop_obtained` 显示短暂获得提示；该提示与升级获得提示共用 HUD 样式，但使用独立文案 key。

## 6. 数值首片

测试武器 Mod 推荐：

| 字段 | 建议 |
|------|------|
| slot | `weapon` |
| max_rank | 5 |
| base_drain | 2 |
| drain_per_rank | 1 |
| rank 0 效果 | `damage mult 1.10` |
| 每 rank 增量 | `+0.05` |
| rank 5 效果 | `damage mult 1.35` |
| 掉落来源 | 玩家击杀 `enemy_chaser` |
| 掉落率 | `0.01` |
| 分解资源 | 低于一次升级成本，避免刷分解套利 |

## 7. 验收命令

纯文档 / 数据规划阶段：

- `python -m json.tool docs/AI记忆/current_state.json`
- `python -m json.tool docs/_kb_index.json`
- `python tools/docs_health_check.py`
- `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`

实现阶段至少追加：

- `python tools/sync_contracts.py --check`
- `python tools/validate_data.py`
- `python tools/test_data_loader_schema.py`
- `python tools/godot_bridge.py --project client headless-boot`
- `python tools/godot_bridge.py --project client gear-mod-smoke`
- 改 `GameplayRunLoop` 开局应用、击杀归因或死亡结算旁路时追加 `python tools/godot_bridge.py --project client runtime-smoke`。
- 改旧 meta 迁移 / 补偿时追加 `python tools/godot_bridge.py --project client meta-smoke` 与 `save-smoke`。
- 若默认开局属性或掉落影响 golden 摘要，重跑四条 checked-in replay；有意变化时重录并说明。

## 8. 风险

- **命名冲突**：装备 Mod 与 `ModLoader` 本地数据包 mod 必须在文档、代码和 UI 中区分。
- **经济膨胀**：掉落、分解和升级资源如果循环套利，会破坏刷宝节奏。
- **无脑堆伤害**：首片只有伤害 Mod 时容易形成唯一最优；后续应快速补英雄生存、拾取、射速、弹速、暴击和副作用 Mod。
- **存档迁移**：删除旧局外成长必须通过 SaveManager 迁移，不能让老档坏掉。
