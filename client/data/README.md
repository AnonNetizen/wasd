# 数值配置手册

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/游戏设计文档.md`、`docs/词表与契约.md` 与 `docs/代码文档规范.md`。
> 本文档是完整项目 `client/data/` 的人工调参数值手册；新增 / 修改数据文件、字段、单位、取值范围或 schema 时，必须同步 GDD、AI导航、词表、对应 `docs/代码/` 模块文档与测试义务。

---

## 目标

- 让策划 / 开发者 / AI 不改代码也能调整玩法数值。
- 所有可调数值集中在 `client/data/`，由 `DataLoader` 读取，代码不写魔法数字。
- 文件格式按数据形态选择：**平表数值优先 CSV，复杂配置优先 JSON**。
- 每个数值字段都写清含义、单位、范围和影响范围，避免“看到字段不知道怎么调”。
- 玩家可见文案不写在数据里，只写 `name_key` / `desc_key` 等本地化 key，译文见 `client/locale/`。

## 快速上手

| 你想做什么 | 改哪里 | 注意 |
|------------|--------|------|
| 改玩家基础血量 / 移速 / 伤害 | `player.json` 的 `base_stats` | 字段名必须来自 `docs/词表与契约.md` 的 stat id |
| 改角色基础属性 / 标签 / 能力 / 起始携带 | `characters.json` | 名字和描述只填 `name_key` / `desc_key`；起始携带填 `starting_loadout`，引用必须存在于对应数据文件 |
| 改武器射速 / 子弹数值 | `weapons.json` | 武器 id 文件内唯一；子弹池、伤害类型和音频前缀必须来自词表 |
| 改敌人血量 / 速度 / 接触伤害 / 中心间距 / 占位色 | `enemies.csv` | 敌人标签、对象池 id、AI profile id、伤害类型必须来自词表或数据注册表 |
| 改敌人生态 AI / 怪物互相克制 | `enemy_ai_profiles.json` | AI action 必须来自词表 §12-B；生态关系通过 content tag 权重表达 |
| 改机关伤害 / 占格尺寸 / 触发周期 | `hazards.csv` | 机关标签、对象池 id、伤害类型必须来自词表；范围尺寸写正整数 `radius_tiles` |
| 改地图边界 / 矩形格 / PCG 机关 / 人工摆点 | `map_layouts.json` | 地图绑定模式 id；bounds 是轴对齐矩形，必须分别整除 `grid.cell_width` / `grid.cell_height`；PCG 使用 `RNG.world` 并按机关占格奇偶吸附到合法矩形格锚点 |
| 改敌巢战区导演 / 阶段主题 / 兴趣点组合 | `warzone_directors.json` | 只按固定时间阶段启用 wave，不读取玩家状态、不做隐藏动态难度；匹配当前 layout 的兴趣点会生成初始 `source="director"` 机关；wave / 机关 / 地图引用必须存在 |
| 加 / 改模块模板 | `modules/<id>.json` + `module_templates.json` | 模块固定 11×11 格；AI 默认产出 `candidate`，通过校验后仍需人工改为 `approved` 才能进入正式池 |
| 改 9×9 世界骨架 / 路线预算 | `module_worlds.json` | 同一世界统一格尺寸；固定起点 / 目标 / 撤离锚点，其余槽位按 `RNG.world` + run seed 组合 |
| 改遗物数值 / 效果声明 | `relics.json` | 用 `modifiers` 和 `behaviors`，不要改逻辑分支 |
| 改主动道具冷却 / 效果声明 | `active_items.json` | 用 `charge` 和 `use_effects`，不要实现运行时分支 |
| 改技能消耗 / 冷却 / 目标 / 伤害 | `skills.json` | 技能不绑定英雄；角色或道具只引用 skill id，资源消耗用 `skill_resources` 声明 |
| 改消耗品堆叠 / 效果声明 | `consumables.json` | 用 `stack` 和 `use_effects`，不要实现拾取 / 背包运行时 |
| 改某个游戏模式可用内容 / 权重 | `game_modes.json` | 模式只组合资源池和轻量覆盖；不要复制角色 / 遗物本体 |
| 改刷怪强度 / 难度曲线 | `spawn_waves.csv` | 大改后需要跑回放 / 平衡验证 |
| 改经验阈值 / 升级候选概率 | `growth.csv` | 候选抽取走 `RNG.ui_choice`，概率字段不要写进代码 |
| 改装备 Mod / 英雄或武器装配 | `gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv` | 装备 Mod 与本地数据包 mod 是不同概念；Mod id / slot / rarity / resource / stack rule 必须先登记契约 |
| 改致谢 / 第三方来源 | `credits.json` + 根目录 `CREDITS.md` | 游戏内 Credits UI 读 `credits.json`；发行前复核许可证与 notice |
| 改界面、道具名、描述文案 | 不在这里改，去 `client/locale/strings.csv` | 数据只引用 key，译文集中管理 |
| 做本地 mod 内容包 | `user://mods/<mod_id>/mod.json` + mod 自带 `data/` patch | 通过 `ModLoader` 声明式追加 JSON / CSV；不改 `client/data/` 原文件，不执行脚本 |

## 文件总览

| 文件 | 状态 | 作用 |
|------|------|------|
| `player.json` | 已建立 | 默认玩家基础属性，完整项目首个数值入口 |
| `game_modes.json` | 已建立 | 游戏模式配置：可用角色 / 武器 / 敌人 / 机关 / 遗物 / 主动道具 / 技能 / 消耗品 / 成长池、权重、禁用列表、参与者 / 队伍预留和轻量覆盖 |
| `characters.json` | 已建立 | 角色列表：基础属性、tags、capabilities、控制配置、技能资源池和起始携带引用 |
| `weapons.json` | 已建立 | 武器与子弹基础配置：射速、弹速、射程、池 id、默认伤害类型 |
| `relics.json` | 已建立 | 被动遗物：`modifiers` + `behaviors`，只存 key 和数值，不存译文 |
| `active_items.json` | 已建立 | 主动道具：充能方式、冷却、效果原语与参数 |
| `skills.json` | 已建立 | 可复用技能：冷却、资源消耗、目标选择和技能效果原语 |
| `consumables.json` | 已建立 | 消耗品：堆叠数量、拾取数量、效果原语与参数 |
| `enemy_ai_profiles.json` | 已建立 | 敌人生态 AI profile：感知、目标权重、动作列表、冲锋 / 领地等复杂行为参数 |
| `enemies.csv` | 已建立 | 敌人基础数值平表：生命、移速、接触伤害、经验奖励、占位色等 |
| `hazards.csv` | 已建立 | 机关基础数值平表：伤害、触发周期、占格尺寸、持续时间 |
| `map_layouts.json` | 已建立 | 有限地图配置：矩形地图边界、矩形格尺寸、玩家出生点、安全半径、PCG 机关规则和人工摆点 |
| `warzone_directors.json` | 已建立 | 敌巢战区导演：固定阶段、巢变异主题、生态 encounter、兴趣点 / 机关组合和阶段启用 wave |
| `module_worlds.json` | 已建立 | F13 模块世界：9×9 槽位、11×11 格、统一格尺寸、固定锚点、模板池、安全布局和技术首片 |
| `module_templates.json` | 已建立 | 模块注册表：角色、JSON 路径、AI 来源、审核状态和可用旋转 |
| `modules/*.json` | 已建立 | 每个模块的 11 行地形令牌、四边通道与敌人 / 机关 / 奖励 / 目标 / 撤离摆放表 |
| `spawn_waves.csv` | 已建立 | 刷怪波次、难度曲线、敌人权重和可选机关权重 |
| `growth.csv` | 已建立 | 经验阈值、升级候选数量和幸运扩展候选概率曲线平表 |
| `growth_pools.json` | 已建立 | 升级选项池、权重、等级条件和候选奖励边界 |
| `gear_mods.json` | JSON | 装备 Mod 定义：英雄 / 武器槽位、稀有度、rank、drain、修正器和分解返还 |
| `gear_mod_drop_tables.csv` | CSV | 装备 Mod 掉落来源、概率和等级条件 |
| `gear_mod_fusion_costs.csv` | CSV | 装备 Mod 按稀有度 / rank 的升级资源成本 |
| `credits.json` | 已建立 | 游戏内致谢数据源：工作人员、外部资源、外部库、适用构建目标与许可 / notice 状态；Steamworks Lab 的随包声明见其 `THIRD_PARTY_NOTICES.txt` |
| `_contracts.json` | 生成文件 | 由 `docs/词表与契约.md` 生成，禁止手改；`DataLoader` 用它校验 id |

## 本地 Mod 数据包

当前项目预留本地 mod 接口，供玩家未来制作内容包；创意工坊暂不接入。分发平台未来只负责把订阅内容放到 `user://mods/<mod_id>/`，游戏内加载仍走 `ModLoader` + `DataLoader`。

最小目录：

```text
user://mods/my_first_mod/
  mod.json
  data/
    relics_patch.json
    strings_patch.csv
```

`mod.json` 示例：

```json
{
  "schema_version": 1,
  "id": "my_first_mod",
  "name": "My First Mod",
  "version": "0.1.0",
  "enabled": true,
  "load_order": 0,
  "contract_extensions": {
    "content_tags": ["mod_my_first_mod_tag"],
    "locale_prefixes": ["mod_my_first_mod_"]
  },
  "data_patches": [
    {
      "type": "json_array_append",
      "target": "relics.json",
      "path": "data/relics_patch.json",
      "array_key": "relics"
    },
    {
      "type": "csv_append",
      "target": "strings.csv",
      "path": "data/strings_patch.csv"
    }
  ]
}
```

| 规则 | 说明 |
|------|------|
| 包 id | `mod.json` 的 `id` 必须等于目录名 `<mod_id>`，重复 id 只会启用第一个 |
| 数据追加 | 当前只支持 `json_array_append` 和 `csv_append`，不支持覆盖 / 删除基础数据 |
| 动态 id | 只允许 manifest 扩展 `character_ids`、`game_modes`、`content_tags`、`locale_prefixes`；值必须以 `mod_<mod_id>_` 开头 |
| 核心契约 | mod 不能扩展 `stats`、`effects`、`events`、`damage_types`、`pool_ids`、`audio_prefixes`、`rng_streams`、`save_kinds` 等需要代码或资源同步的类别 |
| 文案 | mod 文案仍用 CSV，建议通过 `locale_prefixes` 声明 `mod_<mod_id>_` 前缀；基础 `zh_CN` / `en` 列规则不变 |
| 安全 | manifest 的 `path` 只能指向 mod 自身目录内相对路径，禁止 `..`、绝对路径和 `://` |
| 验证 | 启动时 `DataLoader` 校验合并后的数据；错误看 `[ModLoader]` / `[DataLoader]` 日志 |

## 通用格式规则

| 规则 | 说明 |
|------|------|
| 格式选择 | 平表数值优先 CSV，复杂配置优先 JSON；现有文件不强制立即迁移，新增 / 重构时按本规则判断 |
| CSV | 使用标准逗号分隔、首行为表头；适合一行一个条目、列结构稳定的数值表 |
| JSON | 使用标准 JSON，不写注释；适合嵌套对象、数组、可变长度行为、条件树和参数包 |
| UTF-8 / LF | 所有数据文件用 UTF-8 和 LF 换行 |
| snake_case | 字段名和 id 使用蛇形小写，和词表 id 保持一致 |
| `schema_version` | 长期维护数据文件必须有 schema 版本，schema 变更要配迁移 / 校验说明 |
| 单位明确 | 速度用 `px/s`，时间用秒，概率用 `0.0`~`1.0`，倍率用 `1.0` 表示不变 |
| 模式复用 | 角色、遗物、道具、敌人等资源本体默认模式无关；模式配置只引用资源池、权重、条件、禁用列表和轻量覆盖 |
| 多人预留 | 当前只做单人；模式 / 伤害 / 回放 / 存档数据可预留 participant / team / friendly_fire 等字段，但不得提前实现网络协议或复制多人专用资源 |
| 文案 key | 玩家可见名字 / 描述只存 `name_key` / `desc_key` / `hint_key` 等，不存硬文本 |
| 致谢原文 | 外部项目名、人员名、许可证名、URL 与版权声明保持原文；面向玩家的分组标题 / 角色说明用 locale key |
| id 白名单 | `stat`、`effect`、`event`、`damage_type`、`pool_id`、`tag` 等必须先登记到 `docs/词表与契约.md` |
| fail-fast | `DataLoader` 加载时必须校验字段类型、范围、必填项和词表 id；错误信息包含文件名 + 字段路径 + 期望值 |

## CSV / JSON 选择规则

| 数据形态 | 优先格式 | 示例 |
|----------|----------|------|
| 一行一个条目、列固定、经常人工排序 / 筛选 / 批量调参 | CSV | `enemies.csv`、`hazards.csv`、`spawn_waves.csv`、`growth.csv` |
| 数组 / 对象嵌套、每条内容参数数量不同、需要表达条件树 | JSON | `game_modes.json`、`map_layouts.json`、`warzone_directors.json`、`module_worlds.json`、`module_templates.json`、`modules/*.json`、`enemy_ai_profiles.json`、`relics.json`、`active_items.json`、`consumables.json`、`characters.json`、`gear_mods.json`、`growth_pools.json` |
| 玩家可见文案 | CSV | `client/locale/strings.csv` |
| 致谢 / 第三方来源清单 | JSON | `credits.json`，需同时同步根目录 `CREDITS.md` |
| 自动生成契约 | JSON | `_contracts.json`，禁止手改 |

CSV 示例：

```csv
id,max_hp,move_speed,contact_damage,exp_reward
slime,20,90,1,3
bat,12,150,1,2
brute,80,60,2,10
```

JSON 示例：

```json
{
  "id": "relic_split_rounds",
  "behaviors": [
    { "event": "on_hit", "effect": "split", "params": { "count": 2, "angle": 20.0 } },
    { "event": "on_fire", "effect": "pierce", "params": { "count": 1 } }
  ]
}
```

## CSV 通用规则

| 规则 | 说明 |
|------|------|
| 表头必填 | 第一行必须是字段名，字段名使用 `snake_case` |
| `id` 列 | 内容表必须有稳定 `id` 列，id 不得重复 |
| 空值 | 空值只用于可选字段；必填字段空值 fail-fast |
| 数字类型 | `DataLoader` / 校验脚本按字段 schema 转 int / float；人工不要写单位后缀 |
| 布尔值 | 使用 `true` / `false` 小写 |
| 多值 id | CSV 中少量多标签字段使用 `|` 分隔，例如 `tag_enemy|tag_limit_break` |
| 列新增 | 新增列必须同步本文档字段说明和对应 schema |
| 复杂参数 | 不把 JSON 字符串硬塞进 CSV；出现复杂参数时拆到 JSON 文件或独立配置 |

## `player.json`

当前结构：

```json
{
  "schema_version": 1,
  "base_stats": {
    "max_hp": 600.0,
    "health_regen": 1.5,
    "move_speed": 240.0,
    "damage_invulnerability_duration": 0.7,
    "player_separation_radius": 10.0,
    "fire_rate": 2.5,
    "damage": 3.5,
    "bullet_speed": 520.0,
    "bullet_range": 650.0,
    "bullet_count": 1,
    "pickup_range": 96.0,
    "pickup_orb_speed": 360.0,
    "luck": 0.0
  }
}
```

字段说明：

| 字段路径 | 类型 | 单位 / 范围 | 说明 | 调大后的效果 |
|----------|------|-------------|------|--------------|
| `schema_version` | int | `>= 1` | 数据结构版本 | 只在 schema 变更时调整 |
| `base_stats.max_hp` | float | `> 0` | 默认最大生命；当前默认 600.0，采用 Dota 式血量尺度而非旧心数尺度 | 更耐打，失败更晚，也更容易做细粒度伤害 / 回复调参 |
| `base_stats.health_regen` | float | HP/s，`>= 0` | 默认自动生命恢复；只在 `PLAYING` 状态下按 `GameClock` 缩放时间恢复，不超过最大生命 | 更能缓冲小额失误，但过高会抵消低频伤害 |
| `base_stats.move_speed` | float | `px/s`，`> 0` | 默认移动速度 | 走位更灵活，地图探索更快 |
| `base_stats.damage_invulnerability_duration` | float | 秒，`>= 0` | 玩家受伤后的无敌窗口 | 更不容易被贴脸多段瞬杀，但受击节奏更宽松 |
| `base_stats.player_separation_radius` | float | `px`，`>= 0` | 玩家中心排斥半径；与敌人 `separation_radius` 相加后决定敌人被推开的最小中心距离 | 更不容易被敌人中心贴身重叠，但过大可能让围怪显得松散 |
| `base_stats.fire_rate` | float | 每秒发数，`> 0` | 按住开火时的射击频率 | DPS 提升，弹幕更密 |
| `base_stats.damage` | float | `>= 0` | 单发基础伤害 | 击杀更快 |
| `base_stats.bullet_speed` | float | `px/s`，`> 0` | 子弹飞行速度 | 更容易命中远处移动敌人 |
| `base_stats.bullet_range` | float | `px`，`> 0` | 子弹最大射程 | 可打到更远敌人 |
| `base_stats.bullet_count` | int | `>= 1` | 每次开火基础子弹数 | 弹幕覆盖更宽 |
| `base_stats.pickup_range` | float | `px`，`>= 0` | 经验 / 金币自动吸附范围 | 收集更轻松 |
| `base_stats.pickup_orb_speed` | float | `px/s`，`> 0` | 经验球吸附到玩家的移动速度 | 经验球飞来更快，升级节奏更顺 |
| `base_stats.luck` | float | `>= 0` | 幸运值 | 掉落、稀有度、升级 4 选 1 概率更高 |

## 内容数据通用字段

角色、武器、敌人、遗物、道具等内容数据落地后，优先使用这些字段名，便于人和 AI 复用同一结构。

| 字段 | 类型 | 是否常见必填 | 说明 |
|------|------|--------------|------|
| `id` | string | 是 | 内容 id；必须来自对应词表或数据注册表 |
| `name_key` | string | 是 | 名称本地化 key，译文在 `client/locale/strings.csv` |
| `desc_key` | string | 视内容而定 | 描述本地化 key，译文在 `client/locale/strings.csv` |
| `tags` | array[string] | 视内容而定 | 内容标签；破限内容必须含 `tag_limit_break` |
| `capabilities` | array[string] | 视内容而定 | 允许突破的默认规则；id 来自词表 §12 |
| `availability` | object | 否 | 可用条件；需要限制模式时用 tags / 条件声明，由 `game_modes.json` 组合，不在代码写分支 |
| `base_stats` | object | 视内容而定 | 基础属性，字段来自词表 stat |
| `modifiers` | array[object] | 遗物常见 | 数值修正，格式见下节 |
| `behaviors` | array[object] | 行为内容常见 | 行为触发，格式见下节 |

## `game_modes.json`

当前结构：

```json
{
  "schema_version": 1,
  "modes": [
    {
      "id": "mode_standard_survival",
      "name_key": "ui_mode_standard_survival_name",
      "desc_key": "ui_mode_standard_survival_desc",
      "default_unlocked": true,
      "participants": [
        { "id": "local_player", "kind": "player", "team_id": "team_player", "control": "local_player" }
      ],
      "teams": [
        { "id": "team_player", "friendly_fire": false },
        { "id": "team_enemy", "friendly_fire": false }
      ],
      "resource_pools": {
        "characters": [{ "id": "character_default", "weight": 100 }],
        "weapons": [{ "id": "weapon_basic_blaster", "weight": 100 }],
        "enemies": [{ "id": "enemy_chaser", "weight": 100 }],
        "hazards": [
          { "id": "hazard_spike_trap", "weight": 100 },
          { "id": "hazard_fea_12_pulse", "weight": 100 }
        ],
        "relics": [{ "id": "relic_sharp_rounds", "weight": 100 }],
        "active_items": [{ "id": "active_item_blink_burst", "weight": 100 }],
        "skills": [
          { "id": "skill_overdrive_rounds", "weight": 100 }
        ],
        "consumables": [{ "id": "consumable_pocket_bomb", "weight": 100 }]
      },
      "blocklists": { "content_tags": [] },
      "overrides": { "player_base_stats": {} }
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `modes[].id` | string | 词表 §12-A game mode id，文件内唯一 | 游戏模式 id；代码引用走生成常量 |
| `modes[].name_key` / `desc_key` | string | `ui_*_name` / `ui_*_desc` | 模式名称和描述译文 key |
| `modes[].default_unlocked` | bool | true / false | 新存档中是否默认可用 |
| `participants[].id` | string | 模式内唯一 | 参与者 id；当前单人样例为 `local_player` |
| `participants[].kind` | string | 非空 | 参与者类型；当前样例为 `player`，后续 AI / 远端玩家需先补 schema |
| `participants[].team_id` | string | 必须存在于 `teams[].id` | 参与者所属队伍 |
| `participants[].control` | string | 非空，可选 | 控制来源；当前样例为本地玩家输入 |
| `teams[].id` | string | 模式内唯一 | 队伍 id；供伤害、回放、存档和未来多人边界引用 |
| `teams[].friendly_fire` | bool | true / false | 队伍内是否允许友伤；当前只做 schema 预留 |
| `resource_pools.characters[]` | array[object] | 已声明时必须非空 | 本模式可用角色池 |
| `resource_pools.characters[].id` | string | 词表 §12.1 character id，且必须存在于 `characters.json` | 可用角色 id |
| `resource_pools.weapons[]` | array[object] | 已声明时必须非空 | 本模式可用武器池 |
| `resource_pools.weapons[].id` | string | 必须存在于 `weapons.json` | 可用武器 id |
| `resource_pools.enemies[]` | array[object] | 已声明时必须非空 | 本模式可用敌人池 |
| `resource_pools.enemies[].id` | string | 必须存在于 `enemies.csv` | 可用敌人 id |
| `resource_pools.hazards[]` | array[object] | 已声明时必须非空 | 本模式可用机关池 |
| `resource_pools.hazards[].id` | string | 必须存在于 `hazards.csv` | 可用机关 id |
| `resource_pools.relics[]` | array[object] | 已声明时必须非空 | 本模式可用遗物池 |
| `resource_pools.relics[].id` | string | 必须存在于 `relics.json` | 可用遗物 id |
| `resource_pools.active_items[]` | array[object] | 已声明时必须非空 | 本模式可用主动道具池 |
| `resource_pools.active_items[].id` | string | 必须存在于 `active_items.json` | 可用主动道具 id |
| `resource_pools.skills[]` | array[object] | 已声明时必须非空 | 本模式可用技能池；角色或道具仍通过 skill id 引用技能本体 |
| `resource_pools.skills[].id` | string | 词表 §12-C skill id，且必须存在于 `skills.json` | 可用技能 id |
| `resource_pools.consumables[]` | array[object] | 已声明时必须非空 | 本模式可用消耗品池 |
| `resource_pools.consumables[].id` | string | 必须存在于 `consumables.json` | 可用消耗品 id |
| `resource_pools.*[].weight` | int | `>= 0` | 抽取 / 展示权重；具体抽取由后续系统实现 |
| `resource_pools.growth_pools[]` | array[object] | 可选；已声明时必须非空 | 本模式使用的升级候选池；默认标准模式按 ADR #120 不声明该字段，因此不启用局内 3 选 1 |
| `resource_pools.growth_pools[].id` | string | `growth_pools.json` 中已定义池 id | 升级候选池 id |
| `blocklists.content_tags[]` | array[string] | 词表 §12.3 content tag | 禁用某类内容标签；当前样例为空 |
| `overrides.player_base_stats` | object | stat 来自词表 §1 | 轻量覆盖玩家基础属性；只用于模式差异，不复制角色本体 |

`game_modes.json` 只声明模式边界，不实现模式选择 UI、匹配、联网、刷怪、成长抽取、敌人生成、遗物抽取或实际战斗规则。地图尺寸、PCG 机关和人工摆点不写在模式资源池里，改 `map_layouts.json`。默认标准模式不挂 `growth_pools`；未来非默认模式需要局内升级选择时，再显式引用对应升级池。新增资源池类型时，必须同步本文档、`DataLoader` schema、词表或对应数据注册表。

## `map_layouts.json`

当前结构：

```json
{
  "schema_version": 1,
  "layouts": [
    {
      "id": "map_standard_nest",
      "mode_id": "mode_standard_survival",
      "bounds": { "width": 4000.0, "height": 2000.0 },
      "grid": { "cell_width": 160.0, "cell_height": 80.0 },
      "player_start": { "x": -800.0, "y": 400.0 },
      "safe_radius": 320.0,
      "enemy_spawn_margin": 160.0,
      "pcg": {
        "hazards": [
          {
            "id": "hazard_fea_12_pulse",
            "count": 7,
            "min_distance_from_player": 480.0,
            "min_spacing": 320.0
          }
        ]
      },
      "manual_hazards": []
    }
  ]
}
```

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `schema_version` | int | 当前 `1` | 文件 schema 版本 |
| `layouts[].id` | string | 文件内唯一，非空 | 地图 layout id，用于诊断和 run 快照 |
| `layouts[].mode_id` | string | 必须存在于 `game_modes.json` | 该 layout 绑定的游戏模式；当前每个模式使用第一条匹配 layout |
| `bounds.width` / `bounds.height` | number | `> 0`，px；分别为 `grid.cell_width` / `grid.cell_height` 的整数倍 | 有限地图的轴对齐矩形范围；运行时以原点为中心生成可见 / 逻辑矩形边界 |
| `grid.cell_width` | number | `> 0`，px | 单个矩形格的水平宽度 |
| `grid.cell_height` | number | `> 0`，px | 单个矩形格的垂直高度 |
| `player_start.x` | number | 矩形格中心坐标 | 玩家出生点 X 坐标；运行时会吸附并 clamp 到地图边界 |
| `player_start.y` | number | 矩形格中心坐标 | 玩家出生点 Y 坐标；运行时会吸附并 clamp 到地图边界 |
| `safe_radius` | number | `>= 0`，px | PCG 机关距离出生点的最小安全距离下限；运行时可见提示画成按矩形格向外吸附的出生安全矩形，不再画正圆 |
| `enemy_spawn_margin` | number | `>= 0`，px | 刷怪位置距地图边缘的 clamp 边距 |
| `pcg.hazards[]` | array[object] | 可空 | 程序化机关规则；当前使用 `RNG.world` 按 seed 可复现地撒布，并按 `radius_tiles` 奇偶吸附到合法矩形格锚点 |
| `pcg.hazards[].id` | string | 必须存在于 `hazards.csv` | 要生成的机关 id |
| `pcg.hazards[].count` | int | `>= 0` | 目标生成数量；约束太紧时实际生成数量可能少于目标 |
| `pcg.hazards[].min_distance_from_player` | number | `>= 0`，px | 距玩家出生点的额外最小距离，会与 `safe_radius` 取较大值 |
| `pcg.hazards[].min_spacing` | number | `>= 0`，px | 与已放置机关之间的最小间距；同时至少避开双方格子半宽 / 半高推导出的近似半径 |
| `manual_hazards[]` | array[object] | 可空 | 人工固定摆点，先于 PCG 放置，PCG 会避开这些点 |
| `manual_hazards[].id` | string | 必须存在于 `hazards.csv` | 固定摆放的机关 id |
| `manual_hazards[].x` | number | 合法矩形格锚点坐标 | 固定机关世界 X 坐标；奇数 `radius_tiles` 校验为格心，偶数 `radius_tiles` 校验为网格顶点，运行时也会按同一规则吸附并 clamp |
| `manual_hazards[].y` | number | 合法矩形格锚点坐标 | 固定机关世界 Y 坐标；奇数 `radius_tiles` 校验为格心，偶数 `radius_tiles` 校验为网格顶点，运行时也会按同一规则吸附并 clamp |

调参建议：
- 需要改变地图大小或边界节奏时，先改 `bounds`，并保持宽高分别整除 `grid.cell_width/cell_height`，再跑 `runtime-smoke`；`perf-probe` 仅在用户明确要求性能测试时运行。
- 改格子尺度时优先成对调整 `grid.cell_width` / `grid.cell_height`，并保持 `bounds` 为格尺寸整数倍；当前默认一格为 `160 x 160` 的矩形 / 方形俯视格。
- 机关锚点按 `hazards.csv.radius_tiles` 奇偶决定：奇数尺寸中心在格心，偶数尺寸中心在网格顶点，这样机关外边缘才能贴住背景矩形格线。
- 需要测试特定机关交互时，用 `manual_hazards` 固定位置；需要测试 PCG 稳定性时改 `pcg.hazards[].count` / `min_spacing`。
- `hazards.csv` 只管机关基础数值和占格尺寸，`map_layouts.json` 才管初始地图上的机关位置。
- PCG 摆放使用 `RNG.world`，刷怪位置仍使用 `RNG.spawn`，不要把二者混用。
- F12 标准短刷图首片把 `player_start` 放在偏外侧格心，让玩家从边缘切入战区；兴趣点本身仍由 `warzone_directors.json.interest_points[]` 通过 `source="director"` 初始机关表达。

## `enemies.csv`

当前结构：

```csv
id,name_key,tags,pool_id,ai_profile_id,max_hp,move_speed,contact_damage,contact_damage_type,exp_reward,hit_radius,separation_radius,visual_color
enemy_chaser,enemy_chaser_name,tag_enemy,enemy_chaser,enemy_ai_chase_contact,12,110.0,1,physical,3,14.0,9.0,#ff6152
```

字段说明：

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `id` | string | 文件内唯一，非空 | 敌人 id；模式敌人池和后续刷怪表引用此 id |
| `name_key` | string | `enemy_*_name` | 敌人名称译文 key |
| `tags` | string | `|` 分隔的词表 §12.3 content tag，必须含 `tag_enemy` | 内容标签；可被模式 blocklist、刷怪规则或后续内容系统筛选 |
| `pool_id` | string | 词表 §8 pool id | 运行时使用的敌人对象池；当前只校验 id，不实例化场景 |
| `ai_profile_id` | string | 必须存在于 `enemy_ai_profiles.json` | 运行时使用的生态 AI profile；决定感知、目标选择和动作集合 |
| `max_hp` | int | `>= 1` | 敌人最大生命 |
| `move_speed` | number | `> 0`，px/s | 敌人基础移动速度 |
| `contact_damage` | int | `>= 0` | 接触伤害；当前按 600.0 玩家初始生命尺度调参，运行时必须经 `Combat.apply_damage` 结算 |
| `contact_damage_type` | string | 词表 §9 damage type | 接触伤害类型 |
| `exp_reward` | int | `>= 0` | 击杀后经验奖励；后续掉落 / 经验球系统解释 |
| `hit_radius` | number | `> 0`，px | 命中 / 接触半径边界，后续碰撞体或占位图可据此生成 |
| `separation_radius` | number | `>= 0`，px | 敌人中心排斥半径；小于 `hit_radius` 时允许视觉重叠但避免中心完全重合 |
| `visual_color` | string | HTML 色值，如 `#ff6152` | 开发期几何占位图颜色；只表达外观，不承载行为分支 |

`enemies.csv` 只声明敌人基础数值、内容 tag 和 AI profile 引用边界；具体感知、动作评分、怪物互相狩猎 / 逃跑由 `enemy_ai_profiles.json` 与 `EnemyAI` 运行时解释。游戏模式可通过 `resource_pools.enemies` 声明可用敌人池；实际波次选择、生成位置、对象池预热和伤害结算由 `Spawner`、`PoolManager`、`Combat` 与 `EnemyAI` 系统负责。

## `enemy_ai_profiles.json`

当前结构：

```json
{
  "schema_version": 1,
  "profiles": [
    {
      "id": "enemy_ai_predator_stalker",
      "sense_radius": 820.0,
      "decision_interval": 0.12,
      "contact_interval": 0.55,
      "targeting": {
        "player_weight": 0.55,
        "hunt_tags": [{ "tag": "tag_enemy_prey", "weight": 1.65 }],
        "flee_tags": [],
        "territory_radius": 0.0,
        "territory_weight": 0.0
      },
      "movement": {
        "orbit_radius": 190.0,
        "flee_distance": 260.0,
        "charge_range": 320.0,
        "charge_windup": 0.34,
        "charge_duration": 0.42,
        "charge_cooldown": 1.4,
        "charge_speed_scale": 2.65
      },
      "actions": [
        { "id": "ai_action_charge_target", "base_score": 0.95, "speed_scale": 1.0 },
        { "id": "ai_action_approach_target", "base_score": 0.65, "speed_scale": 1.05 }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `profiles[].id` | string | 文件内唯一，非空 | AI profile id；由 `enemies.csv.ai_profile_id` 引用 |
| `profiles[].sense_radius` | number | `> 0`，px | 感知玩家和其他敌人的最大距离 |
| `profiles[].decision_interval` | number | `> 0`，秒 | 重新计算 Utility 分数的间隔 |
| `profiles[].contact_interval` | number | `>= 0`，秒 | 同一敌人目标之间接触伤害冷却；玩家无敌仍由玩家侧裁决 |
| `targeting.player_weight` | number | `>= 0` | 玩家作为目标的权重；为 0 时不会主动追玩家 |
| `targeting.hunt_tags[]` | array[object] | 可为空 | 会被主动狩猎的敌人 content tag 列表 |
| `targeting.hunt_tags[].tag` | string | 词表 §12.3 content tag | 目标敌人必须带有该 tag |
| `targeting.hunt_tags[].weight` | number | `>= 0` | 该 tag 对目标评分的权重 |
| `targeting.flee_tags[]` | array[object] | 可为空 | 需要逃离的敌人 content tag 列表 |
| `targeting.territory_radius` | number | `>= 0`，px | 离出生点超过该距离时，守家动作会加分 |
| `targeting.territory_weight` | number | `>= 0` | 超出领地半径后的回家倾向权重 |
| `movement.orbit_radius` | number | `>= 0`，px | 环绕目标的期望半径 |
| `movement.flee_distance` | number | `>= 0`，px | 逃跑行为的目标距离预留；当前首片主要用于语义保留 |
| `movement.charge_range` | number | `>= 0`，px | 进入冲锋评分的最大距离；0 表示不冲锋 |
| `movement.charge_windup` / `charge_duration` / `charge_cooldown` | number | `>= 0`，秒 | 冲锋蓄力、释放和冷却时间 |
| `movement.charge_speed_scale` | number | `>= 0` | 冲锋释放阶段速度倍率 |
| `movement.ranged_attack_range` | number | `> 0`，px；仅远程 action 需要 | 远程攻击可开火的最大距离 |
| `movement.ranged_keep_distance` | number | `>= 0`，px；可选 | 远程敌人低于该距离时尝试后撤 |
| `movement.ranged_cooldown` | number | `> 0`，秒；仅远程 action 需要 | 远程投射物发射间隔 |
| `movement.ranged_initial_cooldown` | number | `>= 0`，秒；可选 | 生成后首次远程开火前的延迟 |
| `movement.ranged_projectile_damage` | number | `> 0` | 远程投射物伤害，运行时走 `Combat.apply_damage()` |
| `movement.ranged_projectile_damage_type` | string | 词表 §9 damage type；可选 | 远程投射物伤害类型，缺省时回退到敌人接触伤害类型 |
| `movement.ranged_projectile_speed` | number | `> 0`，px/s | 远程投射物速度 |
| `movement.ranged_projectile_range` | number | `> 0`，px | 远程投射物最大射程 |
| `movement.ranged_projectile_hit_radius` | number | `> 0`，px | 远程投射物命中半径 |
| `movement.ranged_projectile_lifetime` | number | `> 0`，秒 | 远程投射物最大存活时间 |
| `movement.ranged_projectile_muzzle_distance` | number | `>= 0`，px；可选 | 远程投射物从敌人中心外偏移发射的距离 |
| `actions[]` | array[object] | 至少 1 个 | 此 profile 可参与评分的动作列表 |
| `actions[].id` | string | 词表 §12-B enemy AI action | 动作 id；运行时通过生成常量解释 |
| `actions[].base_score` | number | `>= 0` | 动作基础分；越高越容易选中 |
| `actions[].speed_scale` | number | `>= 0` | 执行该动作时的移动速度倍率 |

当前动作：

| action id | 行为 |
|-----------|------|
| `ai_action_approach_target` | 接近当前最高分目标，通常是玩家或猎物 |
| `ai_action_flee_threat` | 远离当前最高分威胁 |
| `ai_action_orbit_target` | 在目标附近绕行，预留给远程 / 试探型敌人 |
| `ai_action_charge_target` | 近距离进入蓄力和冲锋释放 FSM |
| `ai_action_guard_home` | 离出生点太远时返回领地 |
| `ai_action_ranged_attack` | 保持距离并发射池化投射物；投射参数来自 `movement.ranged_*` 字段 |

调参建议：先改 `base_score` 和 tag `weight`，再改速度 / 半径；远程敌人先调 `ranged_cooldown`、`ranged_projectile_speed` 和 `ranged_keep_distance`，避免命中过密或玩家无法贴近。大幅改变生态关系后需要跑 `runtime-smoke` 和 golden replay；`perf-probe` 仅在用户明确要求性能测试时运行。新增 action 必须先登记 `docs/词表与契约.md` §12-B，再同步生成常量、schema、`docs/代码/enemy_ai.md` 和测试。

## `hazards.csv`

当前结构：

```csv
id,name_key,tags,pool_id,damage,damage_type,trigger_interval,radius_tiles,duration
hazard_spike_trap,hazard_spike_trap_name,tag_hazard,hazard_spike,100,physical,1.0,1,0.35
```

字段说明：

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `id` | string | 文件内唯一，非空 | 机关 id；模式机关池和后续地图 / 波次表引用此 id |
| `name_key` | string | `hazard_*_name` | 机关名称译文 key |
| `tags` | string | `|` 分隔的词表 §12.3 content tag，必须含 `tag_hazard` | 内容标签；可被模式 blocklist、地图规则或后续内容系统筛选 |
| `pool_id` | string | 词表 §8 pool id | 运行时使用的机关对象池；当前 `hazard_spike` 复用通用 `Hazard` 场景 |
| `damage` | int | `>= 0` | 单次触发伤害；运行时必须经 `Combat.apply_damage` 结算 |
| `damage_type` | string | 词表 §9 damage type | 机关伤害类型 |
| `trigger_interval` | number | `> 0`，秒 | 持续存在机关的触发间隔 |
| `radius_tiles` | int | `>= 1` | 机关矩形 footprint 从中心到边缘占用的半格数；最终半宽 / 半高由 `map_layouts.json.grid` 推导，视觉矩形和触发判定都据此生成；奇数尺寸中心吸附格心，偶数尺寸中心吸附网格顶点 |
| `duration` | number | `>= 0`，秒 | 单次触发后的激活 / 预警表现时长 |

`hazards.csv` 只声明机关基础数值和占格尺寸。当前运行时已有通用 `Hazard` 节点：由 `MapManager` 读取 `map_layouts.json` 的 PCG / 人工摆点，经 `PoolManager` 取节点，在玩家进入矩形触发范围且冷却结束时通过 `Combat.apply_damage()` 结算。游戏模式仍通过 `resource_pools.hazards` 声明可用机关池；实际初始位置和格子尺度改 `map_layouts.json`。

## `spawn_waves.csv`

当前结构：

```csv
id,mode_id,wave_index,start_time,end_time,enemy_id,enemy_weight,spawn_interval,max_alive,spawn_budget,hazard_id,hazard_weight
wave_standard_early_chasers,mode_standard_survival,1,0.0,9999.0,enemy_chaser,100,1.15,14,9999,,0
wave_standard_swarm_mix,mode_standard_survival,2,60.0,9999.0,enemy_swarm,45,1.7,10,9999,,0
wave_standard_stalkers,mode_standard_survival,3,240.0,9999.0,enemy_stalker,18,5.0,3,9999,,0
wave_standard_ranged_spitters,mode_standard_survival,4,300.0,9999.0,enemy_spitter,16,5.6,4,9999,,0
wave_standard_mid_bulwarks,mode_standard_survival,5,420.0,9999.0,enemy_bulwark,25,4.2,4,9999,,0
```

字段说明：

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `id` | string | 文件内唯一，非空 | 波次条目 id；用于诊断、调试和未来回放记录 |
| `mode_id` | string | 词表 §12-A game mode id，且必须存在于 `game_modes.json` | 该波次所属游戏模式 |
| `wave_index` | int | `>= 1`，同一 `mode_id` 内唯一 | 波次序号；用于 UI / analytics / 存档快照中的当前波次 |
| `start_time` | number | `>= 0`，秒 | 本波次开始时间，按 `GameClock` 局内时间解释 |
| `end_time` | number | `> start_time`，秒 | 本波次结束时间；后续 Spawner 可据此选择当前波次 |
| `enemy_id` | string | 必须存在于 `enemies.csv` | 本波次主要敌人 id |
| `enemy_weight` | int | `>= 1` | 本波次敌人抽取权重；当前黄金样例只有一个敌人 |
| `spawn_interval` | number | `> 0`，秒 | 基础刷怪间隔；后续 Spawner 必须经 `GameClock` 解释 |
| `max_alive` | int | `>= 1` | 本波次同时存活敌人软上限 |
| `spawn_budget` | int | `>= 0` | 本波次预算；后续可按敌人成本或数量消耗 |
| `hazard_id` | string | 可空；非空时必须存在于 `hazards.csv` | 可选机关 id，用于把机关生成作为波次压力的一部分 |
| `hazard_weight` | int | `>= 0`；大于 0 时 `hazard_id` 必填 | 可选机关权重；`0` 表示本波次不使用机关 |

`spawn_waves.csv` 只声明刷怪 / 难度曲线数据边界；当前初始地图机关由 `map_layouts.json` 管理，波次中的 `hazard_id` / `hazard_weight` 仍是后续“把机关作为时间压力”时的预留字段。F12 标准短刷图用 0:00 / 1:00 / 4:00 / 5:00 / 7:00 打开敌群层级，其中 5:00 远程喷棘者用于制造走位压力；`9999.0` 是软上限后的持续压力窗口，不是硬性局长限制。实际刷怪随机必须走 `RNG.spawn`，局内时间必须走 `GameClock`，高频实体必须走 `PoolManager`。

## `warzone_directors.json`

当前结构：

```json
{
  "schema_version": 1,
  "directors": [
    {
      "id": "director_standard_warzone",
      "mode_id": "mode_standard_survival",
      "mutation_id": "nest_mutation_hunting_ground",
      "description": "Standard short loot-run director. It targets an 8-12 minute clear, uses fixed phases, and never reads player-state pressure.",
      "phases": [
        {
          "id": "phase_insertion",
          "start_time": 0.0,
          "end_time": 60.0,
          "pressure_tag": "warmup",
          "wave_ids": ["wave_standard_early_chasers"],
          "encounter_ids": ["encounter_chaser_screen"]
        },
        {
          "id": "phase_first_reward_node",
          "start_time": 60.0,
          "end_time": 240.0,
          "pressure_tag": "pressure",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_swarm_mix"],
          "encounter_ids": ["encounter_prey_swarm"]
        },
        {
          "id": "phase_route_pressure",
          "start_time": 240.0,
          "end_time": 420.0,
          "pressure_tag": "ecology",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_swarm_mix", "wave_standard_stalkers"],
          "encounter_ids": ["encounter_predator_prey"]
        },
        {
          "id": "phase_minor_nest_core",
          "start_time": 420.0,
          "end_time": 540.0,
          "pressure_tag": "core",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_swarm_mix", "wave_standard_stalkers", "wave_standard_mid_bulwarks"],
          "encounter_ids": ["encounter_territorial_pressure", "encounter_predator_prey"]
        },
        {
          "id": "phase_overtime_collapse",
          "start_time": 540.0,
          "end_time": 9999.0,
          "pressure_tag": "overtime",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_swarm_mix", "wave_standard_stalkers", "wave_standard_mid_bulwarks"],
          "encounter_ids": ["encounter_territorial_pressure", "encounter_predator_prey"]
        }
      ],
      "encounters": [
        {
          "id": "encounter_chaser_screen",
          "kind": "enemy_ecology",
          "enemy_tags": ["tag_enemy"],
          "notes": "Baseline chaser screen for opening readability."
        }
      ],
      "interest_points": [
        {
          "id": "poi_elite_nest",
          "kind": "elite_nest",
          "hazard_ids": ["hazard_fea_12_pulse", "hazard_spike_trap"],
          "map_layout_id": "map_standard_nest",
          "claim_radius": 190.0,
          "claim_start_time": 60.0,
          "target_hp": 120.0,
          "target_hit_radius": 36.0,
          "resource_rewards": [{"resource_id": "gear_mod_dust", "amount": 25}]
        },
        {
          "id": "poi_mod_cache",
          "kind": "mod_cache",
          "hazard_ids": ["hazard_fea_12_pulse"],
          "map_layout_id": "map_standard_nest"
        },
        {
          "id": "poi_resource_cache",
          "kind": "resource_cache",
          "hazard_ids": ["hazard_spike_trap"],
          "map_layout_id": "map_standard_nest"
        },
        {
          "id": "poi_minor_nest_core",
          "kind": "minor_nest_core",
          "hazard_ids": ["hazard_fea_12_pulse", "hazard_spike_trap"],
          "map_layout_id": "map_standard_nest"
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `directors[]` | array[object] | 非空 | 战区导演列表；首片每个模式只允许一个导演 |
| `directors[].id` | string | 文件内唯一，非空 | 导演 id；只用于调试、验证和后续工具 |
| `directors[].mode_id` | string | 必须存在于 `game_modes.json`，且来自词表 §12-A | 该导演绑定的游戏模式 |
| `directors[].mutation_id` | string | 非空 | 巢变异 / 战区主题 id；首片不玩家可见，因此不进 locale / 词表 |
| `directors[].description` | string | 可选，非空 | 开发者说明；不玩家可见 |
| `directors[].phases[]` | array[object] | 非空、按时间升序、不重叠 | 固定节奏阶段；首片用时间而不是玩家状态推进 |
| `phases[].id` | string | 同 director 内唯一，非空 | 阶段 id |
| `phases[].start_time` | number | `>= 0`，秒 | 阶段开始时间，按 `GameClock` 局内时间解释 |
| `phases[].end_time` | number | `> start_time`，秒 | 阶段结束时间；除最后阶段终点包含外，其余阶段终点不包含 |
| `phases[].pressure_tag` | string | 非空 | 调试 / 平衡用节奏标签，不玩家可见 |
| `phases[].wave_ids[]` | array[string] | 非空；必须引用同模式 `spawn_waves.csv` | 当前阶段允许的刷怪 wave；同模式所有 wave 必须至少被一个阶段引用 |
| `phases[].encounter_ids[]` | array[string] | 非空；必须引用同 director 的 `encounters[].id` | 当前阶段的生态 / 遭遇组合标签 |
| `directors[].encounters[]` | array[object] | 非空 | 战区生态组合声明 |
| `encounters[].id` | string | 同 director 内唯一，非空 | encounter id |
| `encounters[].kind` | string | 非空 | encounter 类型；首片为 `enemy_ecology` |
| `encounters[].enemy_tags[]` | array[string] | 非空；必须来自 `content_tags` | 用敌人 tag 表达生态组合，避免按敌人 id 写逻辑 |
| `encounters[].notes` | string | 可选，非空 | 开发者说明；不玩家可见 |
| `directors[].interest_points[]` | array[object] | 非空 | 战区兴趣点 / 机关组合声明；匹配当前 layout 时进入初始地图机关生成 |
| `interest_points[].id` | string | 同 director 内唯一，非空 | 兴趣点 id |
| `interest_points[].kind` | string | 非空 | 兴趣点类型；F12 首片为 `elite_nest` / `mod_cache` / `resource_cache` / `minor_nest_core` 等调试语义 |
| `interest_points[].hazard_ids[]` | array[string] | 非空；每项必须存在于 `hazards.csv` | 兴趣点关联机关；每个 id 会生成一个 `source="director"` placement |
| `interest_points[].map_layout_id` | string | 可选；非空时必须存在于 `map_layouts.json` | 兴趣点所属地图 layout |
| `interest_points[].min_distance_from_player` | number | 可选，`>= 0`，px | 运行时摆放时距玩家出生点的额外最小距离；会与 layout `safe_radius` 取较大值 |
| `interest_points[].min_spacing` | number | 可选，`>= 0`，px | 与已放置机关之间的最小间距；用于把收益点分散到小而密的路线中 |
| `interest_points[].claim_radius` | number | 可选；有奖励或 `completes_run=true` 时必填且 `> 0`，px | 无目标兴趣点中，玩家进入该半径后可领取 / 交互一次兴趣点奖励；有目标兴趣点由目标摧毁触发领取 |
| `interest_points[].extraction_radius` | number | 可选；`completes_run=true` 时必填且 `> 0`，px | 小巢核领取后开启撤离区的基础半径；运行时会吸附为贴合 `map_layouts.json.grid` 的矩形范围 |
| `interest_points[].extraction_hold_time` | number | 可选；`completes_run=true` 时必填且 `> 0`，秒 | 玩家站在撤离区内需要保持的结算读条时间；离开撤离区会重置首版读条进度 |
| `interest_points[].claim_start_time` | number | 可选，`>= 0`，秒 | 奖励最早可领取时间；使用 `GameClock.now()`，不读取玩家状态 |
| `interest_points[].requires_interaction` | bool | 可选 | 为 `true` 时不会进圈自动领取；运行时生成可见缓存箱，玩家进入 `claim_radius` 后按 `interact` action 打开并把奖励放入 `run.pending_loot` |
| `interest_points[].target_hp` | number | 可选，`> 0` | 有值时 `GameplayRunLoop` 会生成可被子弹命中的 `InterestPointTarget`，摧毁后触发同一套奖励；目标生成后立即可受伤，无值时仍按进圈领取 |
| `interest_points[].target_hit_radius` | number | 可选，`> 0`，px | 可伤害目标的命中半径；只在 `target_hp` 存在时使用，视觉 footprint 会向上吸附到地图矩形格整数尺寸 |
| `interest_points[].resource_rewards[]` | array[object] | 可选，非空；`resource_id` 必须来自 `gear_mod_resources`，`amount >= 1` | 领取时先进入 `run.pending_loot.resources`；撤离成功时才通过 `GearModSystem.grant_resource()` 写入 `meta.gear_mods.resources` |
| `resource_rewards[].resource_id` | string | 必须存在于 `gear_mod_resources` | 当前首片使用 `gear_mod_dust` |
| `resource_rewards[].amount` | int | `>= 1` | 发放资源数量 |
| `interest_points[].gear_mod_rewards[]` | array[object] | 可选，非空；`mod_id` 必须存在于 `gear_mods.json`，`count >= 1` | 领取时先进入 `run.pending_loot.gear_mods`；撤离成功时才通过 `GearModSystem.grant_mod()` 写入库存 |
| `gear_mod_rewards[].mod_id` | string | 必须存在于 `gear_mods.json` 且来自 `gear_mod_ids` | 当前首片使用测试武器 Mod |
| `gear_mod_rewards[].count` | int | `>= 1` | 发放 Mod 实例数量 |
| `interest_points[].completes_run` | bool | 可选 | 为 `true` 时领取后开启撤离区；撤离读条完成才删除当前 `run` 存档、提交暂存战利品并显示完成结果面板；首片用于小巢核 |
| `interest_points[].notes` | string | 可选，非空 | 开发者说明；不玩家可见 |

`warzone_directors.json` 是 F10/F12 敌巢战区导演数据源。运行时使用 `phases[].wave_ids` 给 `GameplayRunLoop` 的 Spawner 做阶段 gating；刷怪本身仍由 `spawn_waves.csv` 的时间窗、间隔、预算和同时存活上限决定。F12 标准局按 0-1 分钟投放、1-4 分钟第一收益点、4-7 分钟路线压力、7-9 分钟小巢核、9 分钟后软加压组织；`phase_overtime_collapse` 只表达继续贪局时的高压段，不是硬性强制结束。匹配当前 `map_layout_id` 的 `interest_points[]` 会交给 `MapManager`；有 `target_hp` 的兴趣点先生成独立的格心 target anchor，再把 `hazard_ids[]` 机关放到目标附近并避开该 footprint；无目标兴趣点仍为每个 `hazard_ids[]` 用既有 PCG / 锚点 / 边界规则生成一个初始 `source="director"` placement，并把兴趣点奖励元数据透传给 `GameplayRunLoop`。无 `target_hp` 且无 `requires_interaction` 的兴趣点在玩家进入 `claim_radius` 且达到 `claim_start_time` 后领取；有 `requires_interaction=true` 的兴趣点会生成可见缓存箱，玩家进入半径后按 `interact` action 打开；有 `target_hp` 的兴趣点会生成可伤害目标，目标生成后即可被子弹 / Combat 伤害摧毁，摧毁后按通用 `resource_rewards[]` / `gear_mod_rewards[]` 放入 `run.pending_loot` 暂存；`completes_run=true` 的小巢核领取后只开启撤离区，玩家进入贴合地图矩形格的撤离矩形并完成 `extraction_hold_time` 读条后，才提交暂存战利品、删除当前 `run` 存档并显示完成结果面板。领取状态、目标状态、撤离状态和暂存战利品保存到 run payload，旧存档缺失时按未领取 / 未开启撤离 / 无暂存处理。导演不能读取玩家生命、DPS、受伤次数、输入频率或其它玩家状态；后续若增加随机 mutation、玩家可见主题或更复杂奖励语义，必须先同步 `docs/代码/warzone_director.md`、GDD、ADR、DataLoader schema 和对应 smoke / replay 策略。

## `module_worlds.json` / `module_templates.json` / `modules/*.json`

F13 的正式默认地图是 9×9 无缝模块世界；每模块固定 11×11 格，默认单格 160 px。`module_worlds.json` 定义世界几何、键槽、批准模板池、安全回退布局和中心 3×3 技术首片；`module_templates.json` 是审核门禁注册表；`modules/*.json` 只表达地形和合法 primitive 摆放，不执行脚本。

每个模块 JSON 必须包含恰好 11 行、每行 11 个 `module_cell_tokens`，并声明四边 socket 格位。相邻模块旋转后的 socket 必须完全匹配，外圈不得越界开口。只允许 0/90/180/270° 旋转，不允许镜像。

AI 产出新模块时必须先登记为 `candidate`。通过 schema、占位、通道、全局可达性、安全区和内容预算校验后，仍需人工将注册表状态改为 `approved`。默认模板池只能引用 `approved`；模板复用时，运行状态按世界槽位保存，不按模板 id 共享。可视化人工编辑器不在首版范围；未来工具必须继续读写同一 JSON schema。

`module_worlds.json` 字段：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `worlds[].id` | string | 唯一、非空 | 世界 id；run v4 保存此值 |
| `worlds[].columns` / `worlds[].rows` | int | 首版固定 `9` | 模块槽位宽高 |
| `worlds[].module_columns` / `worlds[].module_rows` | int | 首版固定 `11` | 单模块局部格宽高 |
| `worlds[].cell_size` | int | `> 0`，默认 `160` | 同一世界统一的方格边长，单位 px |
| `worlds[].active_radius` | int | 首版固定 `1` | 当前模块向四周激活的半径；最多 3×3 chunk |
| `worlds[].seal_outer_edges` | bool | 首版必须 `true` | 外圈有效通道不得朝地图外开放 |
| `worlds[].start_slot.x` / `worlds[].start_slot.y` | int | `0..8`，固定 `(4,4)` | 起点模块槽位 |
| `worlds[].objective_slot.x` / `worlds[].objective_slot.y` | int | `0..8` | 目标模块固定槽位 |
| `worlds[].extraction_slot.x` / `worlds[].extraction_slot.y` | int | `0..8` | 撤离模块固定槽位 |
| `worlds[].route_budget.start_to_objective.min_crossings` / `worlds[].route_budget.start_to_objective.max_crossings` | int | `4..6` | 起点到目标的模块跨越预算 |
| `worlds[].route_budget.objective_to_extraction.min_crossings` / `worlds[].route_budget.objective_to_extraction.max_crossings` | int | `3..5` | 目标到撤离的模块跨越预算 |
| `worlds[].route_budget.main_route_modules.min` / `worlds[].route_budget.main_route_modules.max` | int | `8..12` | 主路线模块数预算 |
| `worlds[].route_budget.optional_exploration_modules.max` | int | 首版 `<= 14` | 可选探索模块预算上限 |
| `worlds[].fixed_slots[].slot.x` / `worlds[].fixed_slots[].slot.y` | int | `0..8`、不得重复 | 固定关键槽位坐标 |
| `worlds[].fixed_slots[].template_id` | string | 注册表中存在且 approved；必须在三个配置锚点各放恰好 1 个 start / objective / extraction 角色 | 固定关键模板引用，防止 seeded 世界缺少目标或撤离 |
| `worlds[].fixed_slots[].rotation` | int | `0/90/180/270` | 固定模板旋转，不允许镜像 |
| `worlds[].template_pool` | array[string] | 非空，只能引用 `approved` | 普通槽位随机模板池 |
| `worlds[].fallback_assignment[].slot.x` / `worlds[].fallback_assignment[].slot.y` | int | 完整覆盖 `0..8` | 固定安全布局槽位 |
| `worlds[].fallback_assignment[].template_id` | string | 注册表中存在且 approved | 固定安全布局模板 |
| `worlds[].fallback_assignment[].rotation` | int | `0/90/180/270` | 固定安全布局旋转 |
| `worlds[].technical_slice_assignment[].slot.x` / `worlds[].technical_slice_assignment[].slot.y` | int | 完整覆盖 `0..8` | 中心 3×3 首片与封锁槽位坐标 |
| `worlds[].technical_slice_assignment[].template_id` | string | 注册表中存在 | 首片内部模板或 candidate 封锁模板 |
| `worlds[].technical_slice_assignment[].rotation` | int | `0/90/180/270` | 首片模板旋转 |

`module_templates.json` 字段：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `templates[].id` | string | 唯一、非空 | 模板 id；世界 assignment 引用此值 |
| `templates[].path` | string | `res://data/modules/*.json` 且文件存在 | 独立模块 JSON 路径 |
| `templates[].role` | string | `module_roles` | 起点 / 连接 / 战斗 / 资源 / 机关 / 目标 / 撤离 / 封锁角色 |
| `templates[].tags` | array[string] | 可为空 | 编辑期筛选标签，不直接产生玩法分支 |
| `templates[].source` | string | 首版 `ai` | 内容来源审计字段；AI 只在编辑期产出 JSON |
| `templates[].review_status` | string | `module_review_statuses` | `candidate` 不得进入默认池，人工批准后为 `approved` |
| `templates[].allowed_rotations` | array[int] | `0/90/180/270` 的非空子集 | 允许旋转集合；不支持镜像 |

## `characters.json`

当前结构：

```json
{
  "schema_version": 1,
  "characters": [
    {
      "id": "character_default",
      "name_key": "character_default_name",
      "desc_key": "character_default_desc",
      "default_unlocked": true,
      "tags": ["tag_character"],
      "capabilities": [],
      "control_profile": "default_mouse_shooter",
      "starting_loadout": {
        "weapon_id": "weapon_basic_blaster",
        "active_item_id": "active_item_blink_burst",
        "consumable_ids": ["consumable_pocket_bomb"],
        "skill_ids": ["skill_overdrive_rounds"]
      },
      "skill_resources": [
        {
          "id": "mana",
          "max": 100.0,
          "start": 100.0,
          "regen_per_second": 10.0
        }
      ],
      "base_stats": {
        "max_hp": 600.0,
        "health_regen": 1.5,
        "move_speed": 240.0,
        "fire_rate": 2.5,
        "damage": 3.5,
        "bullet_speed": 520.0,
        "bullet_range": 650.0,
        "bullet_count": 1,
        "pickup_range": 96.0,
        "luck": 0.0
      }
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `characters[].id` | string | 词表 §12.1 character id，文件内唯一 | 角色 id；模式池、局外解锁和存档引用此 id |
| `characters[].name_key` / `desc_key` | string | `character_*_name` / `character_*_desc` | 角色名称和描述译文 key |
| `characters[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续需与跨局解锁 / 装备 Mod 系统的解锁状态保持一致 |
| `characters[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_character` | 内容标签；破限角色还需含 `tag_limit_break` 并声明 capability |
| `characters[].capabilities` | array[string] | 词表 §12.2 capability id，可为空 | 允许突破的默认规则；空数组表示默认鼠标瞄准 / 左右朝向 / 按住开火 / 默认移动 |
| `characters[].control_profile` | string | 非空 | 控制配置标识；当前只做数据边界，不实现输入 profile 切换 |
| `characters[].starting_loadout` | object | 必填 | 角色起始携带内容引用；当前只做 schema，不发放运行时实体 |
| `characters[].starting_loadout.weapon_id` | string | 必须存在于 `weapons.json` | 默认起始武器引用 |
| `characters[].starting_loadout.active_item_id` | string | 必须存在于 `active_items.json` | 默认起始主动道具引用 |
| `characters[].starting_loadout.consumable_ids` | array[string] | 可为空；每项必须存在于 `consumables.json`，文件内不重复 | 默认起始消耗品引用列表；数量规则仍由后续 ConsumableSystem 解释 |
| `characters[].starting_loadout.consumable_ids[]` | string | 必须存在于 `consumables.json` | 单个默认起始消耗品引用 |
| `characters[].starting_loadout.skill_ids` | array[string] | 可为空；每项必须来自词表 §12-C 且存在于 `skills.json`，文件内不重复 | 默认起始技能列表；当前 `SkillSystem` 使用第一个技能响应 `use_active_item` 输入 |
| `characters[].skill_resources[]` | array[object] | 可为空；每项 id 不重复 | 角色拥有的技能资源池；技能通过 `costs[].resource` 消耗这些资源 |
| `characters[].skill_resources[].id` | string | 词表 §12-D skill resource id | 技能资源 id；当前默认 `mana`，后续可加怒气、能量、生命等资源 |
| `characters[].skill_resources[].max` | number | `> 0` | 该资源最大值 |
| `characters[].skill_resources[].start` | number | `0..max` | 开局初始资源值 |
| `characters[].skill_resources[].regen_per_second` | number | `>= 0`，每秒 | `GameClock` 缩放时间下每秒恢复量；0 表示不自动恢复 |
| `characters[].base_stats` | object | stat 来自词表 §1，非空 | 角色基础属性；数值范围同 `player.json` stat 校验 |

`characters.json` 声明角色数据边界和当前起始技能运行时入口；技能本体仍在 `skills.json`，角色只引用 skill id 和资源池。除 `SkillSystem` 已解释的起始技能外，本文件不实现角色选择 UI、实体生成、输入 profile 切换、主动道具栏、消耗品背包、起始遗物运行时或破限能力执行。新增起始遗物、外观资源或特殊能力字段时，必须先有对应数据注册表 / 词表 / schema，再由业务系统解释。

## `weapons.json`

当前结构：

```json
{
  "schema_version": 1,
  "weapons": [
    {
      "id": "weapon_basic_blaster",
      "name_key": "weapon_basic_blaster_name",
      "desc_key": "weapon_basic_blaster_desc",
      "default_unlocked": true,
      "fire_mode": "hold_mouse",
      "fire_audio_id": "sfx_player_shoot",
      "base_stats": {
        "damage": 3.5,
        "fire_rate": 2.5,
        "bullet_speed": 520.0,
        "bullet_range": 650.0,
        "bullet_count": 1,
        "pierce_count": 0,
        "crit_chance": 0.0,
        "crit_mult": 1.5
      },
      "projectile": {
        "pool_id": "bullet_basic",
        "damage_type": "physical",
        "hit_radius": 8.0,
        "muzzle_distance": 24.0,
        "lifetime": 1.25
      }
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `weapons[].id` | string | 文件内唯一，非空 | 武器 id；角色起始武器和模式武器池引用此 id |
| `weapons[].name_key` / `desc_key` | string | `weapon_*_name` / `weapon_*_desc` | 武器名称和描述译文 key |
| `weapons[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `weapons[].fire_mode` | string | 非空 | 开火模式标识；当前只做数据边界，不实现开火策略 |
| `weapons[].fire_audio_id` | string | 可选；已声明时必须符合词表 §10 audio prefix | 开火音效 id；当前只校验前缀，不要求资源已存在 |
| `base_stats.damage` | number | `>= 0` | 单发基础伤害 |
| `base_stats.fire_rate` | number | `> 0` | 每秒发射次数 |
| `base_stats.bullet_speed` | number | `> 0` | 子弹速度，px/s |
| `base_stats.bullet_range` | number | `> 0` | 子弹最大射程，px |
| `base_stats.bullet_count` | int | `>= 1` | 每次发射子弹数 |
| `base_stats.pierce_count` | int | `>= 0` | 穿透次数；`0` 表示不穿透 |
| `base_stats.crit_chance` | number | `0.0`~`1.0` | 暴击率 |
| `base_stats.crit_mult` | number | `> 0` | 暴击倍率 |
| `projectile.pool_id` | string | 词表 §8 pool id | 使用的子弹对象池 |
| `projectile.damage_type` | string | 词表 §9 damage type | 默认伤害类型 |
| `projectile.hit_radius` | number | `> 0` | 命中半径，px |
| `projectile.muzzle_distance` | number | `> 0` | 发射点相对角色中心距离，px |
| `projectile.lifetime` | number | `> 0` | 子弹存活秒数；业务系统可结合射程裁剪 |

`weapons.json` 只声明武器 / 子弹数据边界，不实现 WeaponSystem、子弹实例化、命中判定、音频播放或武器选择 UI。角色通过 `characters[].starting_loadout.weapon_id` 引用默认起始武器；游戏模式可通过 `resource_pools.weapons` 声明可用武器池。

## `relics.json`

当前结构：

```json
{
  "schema_version": 1,
  "relics": [
    {
      "id": "relic_sharp_rounds",
      "name_key": "relic_sharp_rounds_name",
      "desc_key": "relic_sharp_rounds_desc",
      "default_unlocked": true,
      "tags": ["tag_relic"],
      "modifiers": [
        { "stat": "damage", "type": "add", "value": 0.5 }
      ],
      "behaviors": []
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `relics[].id` | string | 文件内唯一，非空 | 遗物 id；模式遗物池引用此 id |
| `relics[].name_key` / `desc_key` | string | `relic_*_name` / `relic_*_desc` | 遗物名称和描述译文 key |
| `relics[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `relics[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_relic` | 内容标签；破限遗物还需含 `tag_limit_break` 并声明 capability / primitive |
| `relics[].modifiers` | array[object] | 可为空；与 `behaviors` 至少一个非空 | 数值修正列表，格式见下节 |
| `relics[].behaviors` | array[object] | 可为空；与 `modifiers` 至少一个非空 | 行为触发列表，格式见下节 |

`relics.json` 只声明被动遗物数据边界，不实现拾取、掉落、升级候选、`ModifierEngine` 应用、行为原语执行、UI 展示或存档快照。游戏模式可通过 `resource_pools.relics` 声明可用遗物池；实际抽取、解锁和应用由后续系统解释。

## `active_items.json`

当前结构：

```json
{
  "schema_version": 1,
  "active_items": [
    {
      "id": "active_item_blink_burst",
      "name_key": "item_blink_burst_name",
      "desc_key": "item_blink_burst_desc",
      "default_unlocked": true,
      "tags": ["tag_active_item"],
      "charge": {
        "mode": "cooldown",
        "cooldown": 8.0,
        "max_charges": 1,
        "start_charges": 1
      },
      "use_effects": [
        {
          "effect": "knockback",
          "params": {
            "force": 180.0,
            "radius": 96.0
          }
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `active_items[].id` | string | 文件内唯一，非空 | 主动道具 id；模式主动道具池引用此 id |
| `active_items[].name_key` / `desc_key` | string | `item_*_name` / `item_*_desc` | 主动道具名称和描述译文 key |
| `active_items[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `active_items[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_active_item` | 内容标签；突破栏位 / 使用规则时需补 capability / 测试说明 |
| `active_items[].charge.mode` | string | 当前为 `cooldown` | 充能模型；新增模型前先补 schema 与运行时设计 |
| `active_items[].charge.cooldown` | number | `> 0` | 单次充能冷却秒数 |
| `active_items[].charge.max_charges` | int | `>= 1` | 最大充能数 |
| `active_items[].charge.start_charges` | int | `0..max_charges` | 开局初始充能数 |
| `active_items[].use_effects[]` | array[object] | 必须非空 | 使用时触发的效果原语列表 |
| `active_items[].use_effects[].effect` | string | 词表 §2 effect id | 使用效果原语 |
| `active_items[].use_effects[].params` | object | 由 effect 解释 | 效果参数；当前只做 schema 校验，不执行 |
| `active_items[].use_effects[].params.force` | number | `> 0` 建议 | `knockback` 击退力度；当前只作为参数声明 |
| `active_items[].use_effects[].params.radius` | number | `> 0` 建议 | `knockback` 生效半径；当前只作为参数声明 |

`active_items.json` 只声明主动道具数据边界，不实现主动道具栏、输入响应、冷却计时、充能 UI、效果执行、掉落 / 解锁或存档快照。游戏模式可通过 `resource_pools.active_items` 声明可用主动道具池；实际使用流程后续必须走 InputMap action `use_active_item`、`GameClock`、`RNG` 和对应业务系统。

## `skills.json`

当前结构：

```json
{
  "schema_version": 1,
  "skills": [
    {
      "id": "skill_overdrive_rounds",
      "name_key": "skill_overdrive_rounds_name",
      "desc_key": "skill_overdrive_rounds_desc",
      "default_unlocked": true,
      "tags": ["tag_skill"],
      "ability_tags": [
        "ability_tag_skill",
        "ability_tag_primary"
      ],
      "activation": {
        "required_tags": [],
        "blocked_tags": ["ability_tag_silenced"],
        "granted_tags": ["ability_tag_activating"]
      },
      "cooldown": 8.0,
      "costs": [{ "resource": "mana", "amount": 40.0 }],
      "targeting": {
        "type": "target_ally",
        "radius": 0.0,
        "max_targets": 1
      },
      "effects": [
        {
          "effect": "skill_effect_weapon_modifiers",
          "params": {
            "duration": 4.0,
            "modifiers": [
              { "stat": "fire_rate", "type": "mult", "value": 1.7 },
              { "stat": "bullet_speed", "type": "mult", "value": 1.15 }
            ]
          }
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `skills[].id` | string | 词表 §12-C skill id，文件内唯一 | 技能 id；角色、主动道具、敌人或事件系统可复用引用 |
| `skills[].name_key` / `desc_key` | string | `skill_*_name` / `skill_*_desc` | 技能名称和描述译文 key |
| `skills[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `skills[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_skill` | 内容标签；模式 blocklist 和后续构筑筛选可复用 |
| `skills[].ability_tags` | array[string] | 词表 §12-G ability tag，非空 | 项目版轻量 GAS 的能力语义标签；用于分类、阻断、解锁和后续 cue / AI 查询，不与 content tag 混用 |
| `skills[].activation` | object | 必填 | 项目版轻量 GAS 的激活条件配置 |
| `skills[].activation.required_tags` | array[string] | 词表 §12-G ability tag，可为空 | 释放者必须拥有的运行时能力标签；缺任一标签则返回 `missing_required_tag` 且不消耗资源 |
| `skills[].activation.blocked_tags` | array[string] | 词表 §12-G ability tag，可为空 | 释放者拥有任一标签时阻断释放；当前默认用 `ability_tag_silenced` 表达沉默 |
| `skills[].activation.granted_tags` | array[string] | 词表 §12-G ability tag，可为空 | 激活 / commit 期间临时授予释放者的标签；当前即时技能会在效果解释后移除 |
| `skills[].cooldown` | number | 秒，`>= 0` | 释放后冷却时间，走 `GameClock` 缩放时间 |
| `skills[].costs[]` | array[object] | 可为空 | 释放消耗列表；为空表示无消耗 |
| `skills[].costs[].resource` | string | 词表 §12-D skill resource id | 消耗的资源 id；释放者必须在 `skill_resources` 中拥有该资源 |
| `skills[].costs[].amount` | number | `>= 0` | 单次释放消耗量 |
| `skills[].targeting` | object | 必填 | 目标选择声明，由 `SkillSystem` 解释 |
| `skills[].targeting.type` | string | 词表 §12-E skill targeting id | 目标选择策略；当前过载弹流使用 `target_ally` 作用于玩家主武器 |
| `skills[].targeting.radius` | number | `> 0`，px | AOE 或近邻目标查询半径 |
| `skills[].targeting.max_targets` | int | `>= 0` | 最大目标数量；0 表示不限制 |
| `skills[].effects[]` | array[object] | 必须非空 | 命中目标后执行的技能效果原语列表 |
| `skills[].effects[].effect` | string | 词表 §12-F skill effect id | 技能效果原语 |
| `skills[].effects[].params` | object | 由 effect 解释 | 技能效果参数 |
| `skills[].effects[].params.amount` | number | `> 0` | `skill_effect_damage` 的伤害量 |
| `skills[].effects[].params.damage_type` | string | 词表 §9 damage type | `skill_effect_damage` 的伤害类型；`skill_effect_apply_status` 做 DoT 时也必须填写；结算走 `Combat.apply_damage` |
| `skills[].effects[].params.status` | string | 词表 §9-A status effect id | `skill_effect_apply_status` 施加的状态 id |
| `skills[].effects[].params.duration` | number | 秒，`> 0` | `skill_effect_apply_status` 的持续时间，过期走 `GameClock` |
| `skills[].effects[].params.stack_rule` | string | 词表 §9-B status stack rule | 状态重复施加时的叠加 / 刷新规则 |
| `skills[].effects[].params.granted_ability_tags` | array[string] | 词表 §12-G ability tag，可为空 | 状态存在期间授予目标的 ability tags；当前沉默使用 `ability_tag_silenced` |
| `skills[].effects[].params.magnitude` | number | 可选 | 状态强度；DoT 中表示单 tick 伤害，减速 / 增伤标记后续可复用 |
| `skills[].effects[].params.tick_interval` | number | 可选，`>= 0` | DoT tick 间隔；与正 `magnitude` 同时出现时必须提供已登记 `damage_type` |
| `skills[].effects[].params.modifiers[]` | array[object] | `skill_effect_weapon_modifiers` 必填；格式同词表 §1 modifier | 临时主武器属性修正列表；当前用于射击强化技能 |

`skills.json` 是技能本体数据；技能不绑定英雄。当前玩法方向要求技能服务射击强化，不再把默认技能池做成近战 AOE 或点燃法术。`SkillSystem` 采用项目版轻量 GAS 语义解释起始技能的 tag gating、冷却、资源消耗、目标选择、`skill_effect_damage`、`skill_effect_apply_status` 和 `skill_effect_weapon_modifiers`：伤害通过 `Combat.apply_damage` 结算，状态通过 `StatusEffectComponent` 管理叠加、过期、ability tag 生命周期，武器强化通过目标的 `WeaponSystem.apply_temporary_modifiers()` 在持续时间到期后还原。当前内置技能为默认主键释放的 `skill_overdrive_rounds`；后续若主动道具、敌人或遗物要释放同一个技能，应引用 skill id，而不是复制技能字段或按英雄 / 道具 id 写分支。

## `consumables.json`

当前结构：

```json
{
  "schema_version": 1,
  "consumables": [
    {
      "id": "consumable_pocket_bomb",
      "name_key": "item_pocket_bomb_name",
      "desc_key": "item_pocket_bomb_desc",
      "default_unlocked": true,
      "tags": ["tag_consumable"],
      "stack": {
        "max_stack": 3,
        "start_count": 0,
        "pickup_count": 1
      },
      "use_effects": [
        {
          "effect": "explode",
          "params": {
            "radius": 96.0,
            "damage": 8.0
          }
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `consumables[].id` | string | 文件内唯一，非空 | 消耗品 id；模式消耗品池引用此 id |
| `consumables[].name_key` / `desc_key` | string | `item_*_name` / `item_*_desc` | 消耗品名称和描述译文 key |
| `consumables[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `consumables[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_consumable` | 内容标签；突破携带规则时需补 capability / 测试说明 |
| `consumables[].stack.max_stack` | int | `>= 1` | 最大可持有数量 |
| `consumables[].stack.start_count` | int | `0..max_stack` | 开局初始数量 |
| `consumables[].stack.pickup_count` | int | `1..max_stack` | 单次拾取增加数量 |
| `consumables[].use_effects[]` | array[object] | 必须非空 | 使用时触发的效果原语列表 |
| `consumables[].use_effects[].effect` | string | 词表 §2 effect id | 使用效果原语 |
| `consumables[].use_effects[].params` | object | 由 effect 解释 | 效果参数；当前只做 schema 校验，不执行 |
| `consumables[].use_effects[].params.radius` | number | `> 0` 建议 | `explode` 爆炸半径；当前只作为参数声明 |
| `consumables[].use_effects[].params.damage` | number | `>= 0` 建议 | `explode` 爆炸伤害；当前只作为参数声明 |

`consumables.json` 只声明消耗品数据边界，不实现拾取物、背包栏、使用输入、数量扣减、效果执行、掉落 / 解锁或存档快照。游戏模式可通过 `resource_pools.consumables` 声明可用消耗品池；实际拾取随机必须走 `RNG.drop`，局内时间必须走 `GameClock`，高频拾取实体必须走 `PoolManager`。

## `modifiers` 格式

```json
{
  "stat": "damage",
  "type": "add",
  "value": 1.5
}
```

| 字段 | 类型 | 合法值 | 说明 |
|------|------|--------|------|
| `stat` | string | 词表 §1 stat id | 被修改属性 |
| `type` | string | `add` / `mult` | 加法或乘法修正 |
| `value` | number | 由具体 stat 决定 | `add` 为直接加值，`mult` 为倍率；`1.3` 表示乘 1.3 |

## `behaviors` 格式

```json
{
  "event": "on_hit",
  "effect": "split",
  "params": {
    "count": 2,
    "angle": 30.0
  }
}
```

| 字段 | 类型 | 合法值 | 说明 |
|------|------|--------|------|
| `event` | string | 词表 §3 behavior.event | 触发时机 |
| `effect` | string | 词表 §2 effect id | 效果原语 |
| `params` | object | 由 effect 定义 | 原语参数；新增参数要同步对应模块文档 |

## `gear_mods.json`

> 装备 Mod 系统见 `docs/AI协作/工作包/F11-GearModLoadout.md` 与 `docs/代码/gear_mod_system.md`。这里的装备 Mod 是玩家装配系统，不是 `ModLoader` 读取的本地数据包 mod。

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

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `mods[].id` | string | 词表 §13-A `gear_mod_id` | 装备 Mod id |
| `mods[].name_key` / `desc_key` | string | `gear_mod_*_name` / `gear_mod_*_desc` | 名称和描述译文 key |
| `mods[].slot` | string | 词表 §13-B | 可装备到英雄或武器 loadout |
| `mods[].rarity` | string | 词表 §13-C | 稀有度；用于掉落展示和升级成本 |
| `mods[].max_rank` | int | `>= 0` | 最大升级 rank；rank 0 表示初始获得状态 |
| `mods[].base_drain` | int | `>= 0` | rank 0 装备容量消耗 |
| `mods[].drain_per_rank` | int | `>= 0` | 每提升 1 rank 增加的容量消耗 |
| `mods[].rank_modifiers[]` | array[object] | stat 来自词表 §1 | 随 rank 计算的 modifiers |
| `rank_modifiers[].base_value` | number | 由 modifier 类型决定 | rank 0 的初始值；`mult` 用 `1.0` 表示不变 |
| `rank_modifiers[].value_per_rank` | number | 可正可负 | 每 rank 增量 |
| `mods[].stack_rule` | string | 词表 §13-E | 同一 loadout 内的重复装备规则；首片为 `unique_by_id` |
| `mods[].dismantle.resource_id` | string | 词表 §13-D | 分解返还资源 |
| `mods[].dismantle.amount` | int | `>= 0` | 分解返还数量；应低于一次升级成本，避免套利 |

首个测试武器 Mod 目标：提高武器基础 `damage`，由玩家击杀 `enemy_chaser` 时以 `1%` 概率掉落。实现时必须用通用掉落表解释，不在敌人或武器代码中写按 id 分支。

## `gear_mod_drop_tables.csv`

```csv
source_enemy_id,mod_id,drop_chance,min_enemy_level,max_enemy_level
enemy_chaser,gear_mod_weapon_damage_test,0.01,1,999
```

字段说明：

| 字段 | 类型 | 单位 / 范围 | 说明 |
|------|------|-------------|------|
| `source_enemy_id` | string | 必须存在于 `enemies.csv` | 掉落来源敌人；首片为最普通小怪 `enemy_chaser` |
| `mod_id` | string | 必须存在于 `gear_mods.json` | 掉落的装备 Mod |
| `drop_chance` | float | `0.0..1.0` | 单次玩家归因击杀掉落概率；首片测试 Mod 为 `0.01` |
| `min_enemy_level` / `max_enemy_level` | int | `>= 1` | 可选等级区间；未实现敌人等级前可先填宽范围 |

掉落随机必须走 `RNG.drop`；怪物互杀、机关击杀或非玩家归因击杀不产出装备 Mod。

## `gear_mod_fusion_costs.csv`

```csv
rarity,rank,resource_id,cost
common,1,gear_mod_dust,20
common,2,gear_mod_dust,35
common,3,gear_mod_dust,55
common,4,gear_mod_dust,85
common,5,gear_mod_dust,130
```

字段说明：

| 字段 | 类型 | 单位 / 范围 | 说明 |
|------|------|-------------|------|
| `rarity` | string | 词表 §13-C | 装备 Mod 稀有度 |
| `rank` | int | `1..max_rank` | 升到该 rank 需要的成本 |
| `resource_id` | string | 词表 §13-D | 消耗的装备 Mod 资源 |
| `cost` | int | `>= 0` | 升级资源消耗 |

首片使用专用 `gear_mod_dust`，避免旧永久升级经济影响新系统。

## `growth.csv`

当前结构：

```csv
level,total_xp_required,candidate_count,bonus_candidate_chance_per_luck,bonus_candidate_chance_cap
1,0,3,0.02,0.35
2,20,3,0.02,0.35
```

字段说明：

| 字段 | 类型 | 单位 / 范围 | 说明 |
|------|------|-------------|------|
| `level` | int | `>= 1`，严格递增 | 玩家局内等级 |
| `total_xp_required` | int | 累计经验，`>= 0`，严格递增 | 达到该等级所需累计经验；第 1 级为 0 |
| `candidate_count` | int | `>= 1`，默认 3 | 本级升级时默认候选数量；只在目标模式声明 `growth_pools` 时生效 |
| `bonus_candidate_chance_per_luck` | float | `0.0`~`1.0` | 每点 `luck` 增加 4 选 1 的概率 |
| `bonus_candidate_chance_cap` | float | `0.0`~`1.0` | 幸运扩展候选概率上限 |

运行时候选数量判定必须走 `RNG.ui_choice`；本表只提供概率参数，不负责抽取实现。ADR #120 后默认标准模式不启用局内 3 选 1，本表作为未来模式 / 工具验证能力保留。

## `growth_pools.json`

当前结构：

```json
{
  "schema_version": 1,
  "pools": [
    {
      "id": "default_level_up",
      "entries": [
        {
          "id": "growth_damage_small",
          "name_key": "ui_growth_damage_small_name",
          "desc_key": "ui_growth_damage_small_desc",
          "kind": "stat_modifier",
          "weight": 100,
          "min_level": 1,
          "modifiers": [
            { "stat": "damage", "type": "add", "value": 0.5 }
          ]
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 范围 | 说明 |
|----------|------|------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `pools[].id` | string | 非空，文件内唯一 | 升级候选池 id；后续由模式或成长系统引用 |
| `pools[].entries` | array[object] | 可为空 | 候选条目列表；当前只落 `stat_modifier` 黄金样例 |
| `entries[].id` | string | 非空，池内唯一 | 候选条目 id；用于回放记录和诊断 |
| `entries[].name_key` / `desc_key` | string | `ui_*` locale key | 升级候选面板展示的名称和描述 |
| `entries[].kind` | string | 非空 | 候选类型；当前黄金样例为 `stat_modifier`，后续类型落地前需同步 schema |
| `entries[].weight` | int | `>= 0` | 抽取权重；实际抽取走 `RNG.ui_choice` |
| `entries[].min_level` | int | `>= 1`，可选 | 条目最早出现等级 |
| `entries[].modifiers` | array[object] | stat 来自词表 §1 | 属性修正奖励；格式同通用 `modifiers`，使用 `value` |

F4 当前已解释 `kind=stat_modifier`，用于升级选择后即时应用属性修正；遗物、主动道具强化、回血、刷新 / 跳过等其他候选类型仍未落地。ADR #120 后默认标准模式不引用本池，未来模式需要局内 3 选 1 时再在 `game_modes.json.resource_pools.growth_pools` 挂接。新增 `kind` 影响运行时行为时，必须同步对应系统模块文档和测试。

## `credits.json`

当前结构：

```json
{
  "schema_version": 1,
  "sections": [
    {
      "id": "staff",
      "title_key": "ui_credits_section_staff",
      "entries": [
        {
          "kind": "staff",
          "name": "Anon London / 伦敦阿农",
          "role_key": "ui_credits_role_project_owner"
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 范围 | 说明 |
|----------|------|------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `sections[].id` | string | 文件内唯一，非空 | 致谢分组 id；供 UI 排序 / 锚点使用，不作为玩法契约 |
| `sections[].title_key` | string | `ui_*` locale key | 分组标题，如工作人员、引擎与外部库 |
| `sections[].entries` | array[object] | 非空 | 本分组的致谢条目 |
| `entries[].kind` | string | `staff` / `external_resource` / `external_library` / `external_tool` | 条目类型；外部条目必须记录来源和许可字段 |
| `entries[].name` | string | 非空 | 人名、项目名、工具名或库名，保持原文 |
| `entries[].role_key` | string | `ui_*` locale key | 面向玩家展示的角色 / 用途说明 |
| `entries[].url` | string | 外部条目必填 | 上游主页或许可证页 |
| `entries[].license` | string | 外部条目必填 | 许可证或服务 / 工具说明；发行前人工复核 |
| `entries[].copyright` | string | 可选 | 上游版权声明，保持原文 |
| `entries[].included_in_build` | bool | 外部条目必填 | 是否随游戏构建或发行包分发 |
| `entries[].requires_notice` | bool | 外部条目必填 | 是否需要在发行包或游戏内保留 notice |
| `entries[].review_required` | bool | 外部条目必填 | 是否仍需发行前人工许可复核 |

`credits.json` 是未来游戏内 Credits UI 的数据源；当前只落数据与 schema，不实现 UI。代码库级人类可读清单在根目录 `CREDITS.md`，两者应同步维护。外部项目名、许可证名、URL 与版权声明可以保持原文；分组标题、角色 / 用途说明走 `client/locale/strings.csv`。

## 调参流程

1. 先看本文档确认字段单位和范围。
2. 只改目标 CSV / JSON，不改 GDScript 常量。
3. 如果新增 id，先改 `docs/词表与契约.md`，再跑 `/sync-contracts` 或等价同步流程。
4. 修改后运行 `python tools/sync_contracts.py --check` 与 `python tools/validate_data.py`；代码落地后由 `DataLoader` fail-fast。
5. 大幅调整基础属性、难度曲线、掉落或升级概率后，按 `docs/测试策略.md` 跑回放 / 平衡验证。

## 新增数据文件或字段时

必须同步：

| 改动 | 必须同步 |
|------|----------|
| 新增数据文件 | 本文档文件总览、GDD §9.3、`docs/AI导航.md`、相关模块文档，并说明为何选 CSV 或 JSON |
| 新增字段 | 本文档字段说明、`DataLoader` schema、相关模块文档、必要时测试策略 |
| 新增 id 类型 | `docs/词表与契约.md`、生成常量、契约校验 |
| 新增玩家可见文案引用 | `client/locale/strings.csv` 与 `client/locale/README.md` |
| 改变玩家可见行为 | GDD、ADR、测试策略、模块文档 |

## 自检清单

- [ ] 数值是否在 `client/data/` 的 CSV / JSON，且格式选择符合“平表 CSV、复杂 JSON”？
- [ ] 字段单位、范围、默认值是否已写进本文档？
- [ ] 是否已运行 `python tools/validate_data.py`？
- [ ] 玩家可见文本是否只存 key，译文是否在 `client/locale/strings.csv`？
- [ ] 所有 id 是否来自 `docs/词表与契约.md`？
- [ ] 大幅平衡改动是否有回放 / sim / 人工试玩记录？
