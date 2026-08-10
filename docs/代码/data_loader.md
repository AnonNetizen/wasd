# DataLoader 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `DataLoader` autoload 的代码契约权威；改公共 API、数据 schema、契约加载、CSV/JSON 解析或 fail-fast 行为时必须同步本文档、`docs/AI导航.md`、`client/data/README.md` 与必要的测试说明。

## 职责

- 统一加载 `client/data/` 下的 JSON 与 CSV 配置。
- 通过 `ModLoader` 合并 `user://mods/<mod_id>/` 下声明式数据 patch，为本地玩家 mod 提供统一入口。
- 将已加载、已合并且完成坏包隔离的数据交给纯 `DataReferenceIndexBuilder` 构建跨文件校验索引；读取顺序、Mod 边界和 schema 错误仍由 `DataLoader` 持有。
- 将包内与最终合并的 Gear Mod 掉落行交给纯 `GearModDropTableValidator` 校验；`DataLoader` 继续持有读取、错误输出、坏包禁用 / 重读和 schema 计数。
- 将合并后的技能、Gear Mod 与掉落表交给纯 `DataFingerprintBuilder` 归一化；`DataLoader` 只负责数据源与 Mod 环境，Replay 继续负责最终 SHA-256。
- 启动时读取 `res://data/_contracts.json`，为后续数据校验提供词表白名单。
- 提供正式数据 schema 校验入口，当前覆盖 `player.json`、`characters.json`、`weapons.json`、`skills.json` v3、`enemy_ai_profiles.json`、`enemies.csv`、`enemy_rewards.json`、`difficulty_profiles.json`、`gear_mods.json` v6、`gear_mod_drop_tables.csv`、`content_unlock_rules.json`、`hazards.csv`、`map_layouts.json`、`module_worlds.json`、`module_templates.json`、`modules/*.json`、`warzone_directors.json`、`spawn_waves.csv`、`active_items.json`、`consumables.json`、`credits.json`、`game_modes.json`、`level_progression.json`、`reward_choice_pools.json` 与 `strings.csv`。
- 提供 fail-fast 错误输出，错误信息包含文件、字段路径和期望值。
- 不负责业务解释、数值平衡、热重载 UI、金币交易、奖励应用或游戏模式运行时；这些由后续业务模块接入。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 新增数据读取 API | `client/scripts/autoload/data_loader.gd` |
| 改数值字段说明 | `client/data/README.md` |
| 改约定字符串来源 | `docs/词表与契约.md` 与 `tools/sync_contracts.py` |
| 调试启动加载失败 | 本文档“故障排查” |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/data_loader.gd` | `DataLoader` autoload 实现 |
| `client/scripts/data/data_reference_index_builder.gd` | 从调用方已加载的 JSON / CSV 值构建 18 类跨文件引用索引；纯、静态、无状态，不读取文件 / Mod、不输出错误、不缓存或排序 |
| `client/scripts/data/gear_mod_drop_table_validator.gd` | 纯、静态的包内 / 合并掉落行校验；只接收现成 rows / ID 索引与错误 sink，不读文件 / Mod、不持有 Node / cache、不排序 |
| `client/scripts/data/data_fingerprint_builder.gd` | 纯、类型化的玩法指纹 payload 归一化；不读取文件、不访问 autoload、不改变数组顺序 |
| `client/tests/unit/test_data_reference_index_builder.gd` | 锁定引用索引的坏 root / 类型、真实 loader String 产物、strict JSON 对 `StringName` / 数字 ID 的拒绝、空 ID、插入顺序、重复折叠、别名隔离、机关半径与嵌套波次行为 |
| `client/tests/unit/test_gear_mod_drop_table_validator.gd` | 锁定掉落表边界、空表、多错误顺序、未知引用、等级范围 / 重复、包输入形状、旧静默诊断与跨调用无状态 |
| `client/scripts/autoload/mod_loader.gd` | 本地 mod manifest 扫描与数据 patch 合并入口 |
| `client/data/_contracts.json` | 由 `tools/sync_contracts.py` 生成的词表镜像 |
| `client/data/player.json` | schema v4 玩家统一身体半径、基础属性、防御、冲刺与掉落规则 |
| `client/data/characters.json` | schema v4 角色专属场景、primary-only palette、基础属性、标签、能力、控制配置和起始携带引用边界 |
| `client/data/weapons.json` | schema v5 武器、子弹、后坐与扩散边界；玩家无限射击并精确拒绝遗留 `ammo` |
| `client/data/skills.json` | schema v3：项目版轻量 GAS 技能、ability tag、激活条件、资源消耗、目标类型、能力缩放与通用效果程序 |
| `client/data/visual_effects.json` | 视觉效果 catalog、资源、空间、生命周期、对象池与表现策略 |
| `client/data/presentation_profiles.json` | 表现 profile 继承、cue、效果 / 音频 / 相机 / 屏幕绑定 |
| `client/data/enemy_ai_profiles.json` | schema v5 敌人对玩家 AI profile、感知、动作参数、显式攻击参数和动作列表边界 |
| `client/data/enemies.csv` | 敌人专属场景、独立对象池 / 预热、图鉴描述 / 图标、默认解锁、解锁规则、基础数值、金币价值倍率、通用 tag、AI profile、伤害类型和模式引用边界 |
| `client/data/enemy_rewards.json` | schema v1 敌人金币基础系数、阶段增长和独立随机区间 |
| `client/data/difficulty_profiles.json` | schema v2 难度名称、难度系数、威胁时间与敌人生命 / 伤害曲线 |
| `client/data/gear_mods.json` | schema v6 的 7×7 棋盘、可组合 `modifier` / `program` / `board_rule`、奖励池贡献、图鉴与解锁边界 |
| `client/data/content_unlock_rules.json` | schema v1 稀疏锁定规则；只登记显式锁定内容，支持 `all` / `any` 与五类进度条件 |
| `client/data/gear_mod_drop_tables.csv` | 装备 Mod 掉落来源、概率和敌人等级条件边界 |
| `client/data/hazards.csv` | 机关基础数值、对象池、伤害类型和模式引用边界 |
| `client/data/map_layouts.json` | 有限地图、玩家出生点、PCG 机关规则和人工摆点边界 |
| `client/data/warzone_directors.json` | schema v2 敌巢战区导演、固定阶段、巢变异主题、兴趣点和阶段启用 wave 边界 |
| `client/data/module_worlds.json` / `module_templates.json` / `modules/*.json` | 世界 schema v5、模块 schema v4：7×7 几何、左下起点、三角意识核候选、首次进入敌人数 / 预警 / 解锁权重、限量事件模板组、approved 模板池、路线预算、11×11 地形与静态内容摆放 |
| `client/data/world_events.json` | schema v1：五类事件、波次、交互半径、奖励、祭坛费用 / 献祭与普通 Mod 池 |
| `client/data/spawn_waves.csv` | 刷怪波次、模式引用、敌人 / 机关引用、时间窗和强度数值边界 |
| `client/data/active_items.json` | 主动道具充能 / 使用效果数据边界 |
| `client/data/consumables.json` | 消耗品堆叠 / 拾取数量 / 使用效果数据边界 |
| `client/data/credits.json` | 游戏内致谢数据源，记录工作人员、外部资源、外部库和发行 notice 状态 |
| `client/data/game_modes.json` | 游戏模式资源池、参与者 / 队伍与轻量覆盖边界 |
| `client/data/level_progression.json` | 金币等级曲线的首段成本与有理倍率边界 |
| `client/data/reward_choice_pools.json` | 通用奖励池、等级过滤、权重与 modifier 边界 |
| `client/locale/strings.csv` | 多语言 key 与译文表 |
| `tools/test_data_loader_schema.py` | DataLoader schema 回归测试：黄金数据、坏 id、缺 locale、类型 / 范围错与跨文件引用错误 |

## 场景 / 节点结构

无场景节点。`DataLoader` 通过 `client/project.godot` 的 `[autoload]` 注册为全局单例。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| autoload `_ready()` | 加载 `_contracts.json` | `reload_contracts()` |
| 配置读取 | 调用方按需读 JSON / CSV，并叠加已启用本地 mod patch | `load_json()`、`load_csv()` |
| schema 校验 | 启动 smoke 或工具调用正式数据校验；运行时会校验合并后的数据 | `validate_project_data()`、`schema_counts()` |
| 引用索引 | 每个 schema 校验后按原读取顺序重新取得当前合并值，再交给纯 builder 建索引；Gear Mod 必须在坏玩法包隔离后重新读取 | `DataReferenceIndexBuilder.collect_*()` |
| Gear Mod 掉落 | 敌人索引建好后先校验每包 rows 并隔离坏包，再重读合并 Gear Mod / 世界事件 / 掉落 CSV；合并 rows 数量仍由 DataLoader 记录，错误仍经 `_schema_fail()` 输出 | `GearModDropTableValidator.validate_package_rows()`、`validate_merged_rows()` |
| 指纹构建 | `DataLoader` 先应用官方数据与有效 Mod patch，再把结果交给 builder 排除展示字段、归一化标量并深拷贝嵌套玩法字段 | `gear_mod_gameplay_fingerprint_payload()`、`effect_gameplay_fingerprint_payload()` |
| 契约查询 | 调用方查询白名单；允许的 mod 动态扩展 id 会并入返回值 | `contract_values()`、`has_contract_value()` |
| 重新加载 | 覆盖 `_contracts` 并通知订阅方 | `data_reloaded` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `reload_contracts()` | 无 | `void` | 读取 `CONTRACTS_PATH`，失败时 `push_error` |
| `contracts()` | 无 | `Dictionary` | 返回深拷贝，调用方不得改内部缓存 |
| `contract_values(contract_id)` | `String` | `Array` | 返回内置契约 + `ModLoader` 允许的动态扩展；未登记 id 报错并返回空数组 |
| `has_contract_value(contract_id, value)` | `String`, `String` | `bool` | 用于 schema / id 校验 |
| `validate_project_data()` | 无 | `bool` | 校验本阶段正式数据 schema；失败时 `push_error` 并返回 `false` |
| `schema_counts()` | 无 | `Dictionary` | 返回最近一次 schema 校验的关键计数，用于 boot smoke |
| `load_json(resource_path)` | `String` | `Variant` | JSON 需是有效文本；失败返回空字典；`_contracts.json` 不允许被 mod patch |
| `load_csv(resource_path, has_header)` | `String`, `bool` | `Array[Dictionary]` | 默认首行为表头；返回值会追加匹配的 mod CSV patch 行 |
| `data_path(file_name)` | `String` | `String` | 拼出 `res://data/<file_name>` |
| `mod_diagnostics()` | 无 | `Array[String]` | 返回 `ModLoader` 的 manifest / patch 诊断 |
| `gear_mod_gameplay_fingerprint_payload()` | 无 | `Dictionary` | 保持原公开 API；输入包含当前有效 Mod 合并结果，数组顺序保持为玩法顺序，展示字段不进入 payload |
| `effect_gameplay_fingerprint_payload()` | 无 | `Dictionary` | 保持原公开 API；返回 skills 深拷贝与同一份 Gear Mod 玩法 payload，供 Replay 数据指纹使用 |

### 内部纯引用索引 API

`DataReferenceIndexBuilder` 接收调用方已加载的 `Variant`，每次返回新 `Dictionary`；它不访问 `DataLoader`、`ModLoader`、文件系统或 `user://`，不报告 schema 错误，也不缓存、排序或深拷贝无关数据。

| 分类 | 静态入口 | 保留的兼容语义 |
|------|----------|----------------|
| Camera / 表现 | `collect_camera_feedback_ids()`、`collect_visual_effect_ids()`、`collect_presentation_profile_ids()` | 消费真实 JSON loader 的 String key / ID；Camera 跳过 `schema_version` 且只收 Dictionary profile，visual / presentation 过滤空 ID |
| 普通 JSON | `collect_hero_passive_ids()`、`collect_weapon_ids()`、`collect_enemy_ai_profile_ids()`、`collect_gear_mod_ids()`、`collect_world_event_ids()`、`collect_active_item_ids()`、`collect_consumable_ids()`、`collect_skill_ids()`、`collect_character_ids()`、`collect_difficulty_profile_ids()`、`collect_game_mode_ids()`、`collect_map_layout_ids()` | 只接收原值类型为 String 的 ID；空 String 继续保留，重复 ID 原位折叠且后写不改变首次插入顺序 |
| CSV | `collect_enemy_ids()`、`collect_hazard_ids()` | 消费 `load_csv()` 的 String ID 并过滤空值；机关半径按旧规则从 String 转 int、至少为 1，重复 ID 最后写入值生效但不重排 |
| 波次 | `collect_spawn_wave_ids_by_mode()` | 消费 `load_csv()` 的 String mode / wave ID 并过滤空值，保持 mode 与各 mode 内 wave 的首次插入顺序，返回独立嵌套 Dictionary |

### 内部纯 Gear Mod 掉落校验 API

`GearModDropTableValidator` 的 `report_failure` 只接收 `(field_path, expected)`；正式接线由 `DataLoader` 补上 `GEAR_MOD_DROP_TABLES_PATH` 并转发到 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、cache 或排序。

| 静态入口 | 输入 | 保留的兼容语义 |
|----------|------|----------------|
| `validate_package_rows()` | 包 payload 的 `drop_rows`、包 id、正式敌人索引、当前包 Mod 索引、错误 sink | 空 Array 合法；非 Array / 非 Dictionary、未知敌人 / 当前包 Mod、等级倒置继续只判包无效而不新增诊断；exact keys 与 CSV 数值 / 整数仍按旧 field / expected 顺序报告；包内重复行不在此阶段拒绝 |
| `validate_merged_rows()` | 已隔离坏包后重新读取的 `Array[Dictionary]`、最终敌人 / Mod 索引、错误 sink | 空表失败；每行按敌人→Mod→概率→最小等级→最大等级→范围→重复继续收集错误；等级解析或下限失败时跳过范围 / 重复；非空未知 id 仍参与 `source:mod:min:max` 重复检测 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `data_reloaded` | 无 | `reload_contracts()` 成功刷新 `_contracts` 后 |

## 数据与契约

- 读取 `res://data/_contracts.json`，并在运行时叠加 `ModLoader.contract_extensions()` 返回的允许动态扩展 id。
- `_contracts.json` 由 `tools/sync_contracts.py` 生成，禁止手改。
- 玩家 mod 不得修改 `_contracts.json` 或生成常量；manifest v2 只允许声明 `gear_mod_ids` 与 `locale_prefixes`，且 Gear Mod / locale key 必须使用 `mod_<package_id>_` 命名空间。
- 当前 F3 schema 覆盖：
  - `player.json`：schema v4 新增 `body`，且 `body` 必须且只能含正数 `radius`；其余根级配置继续包含 `base_stats`、`defense`、`dash`、`energy_drop` 与 `gold_drop`。stat id 必须来自词表，数值范围按 stat 类型校验；`max_hp` 是正数浮点血量，`health_regen` 是非负 HP/s，两个掉落的 `pickup_speed` 必须为正数。遗留 `pickup_orb_speed` 会被明确拒绝，`luck` 保留为暂未生效属性。
  - `characters.json`：schema v4 角色 id、专属 `scene_path`、表现 profile、名称 / 描述 key、可选图鉴图标、默认解锁 / 解锁规则、tags、capabilities、控制配置、起始携带引用和角色基础属性；字段缺失等同默认开放。每个 `palette` 必须且只能含一个合法 HTML 颜色 `primary`，遗留 `secondary` / `accent` 或任何额外键均拒绝。场景必须是正式 `actors/characters/*.tscn` 下存在的 `PackedScene`，不得指向基础场景或越界。不同角色 id 可以复用同一路径；起始武器、主动道具和消耗品引用必须存在于对应数据文件。
  - `weapons.json`：schema v5；武器 id、表现 profile、名称 / 描述 key、默认解锁、开火模式、开火音频 id、武器基础属性、子弹对象池、伤害类型与弹体数值。根级和单武器均执行 exact-key 校验，任何遗留 `ammo` 或额外字段都会拒绝。
  - `skills.json`：schema v3；技能 id、表现 profile、名称 / 描述 key、`tag_skill`、ability tags、activation required / blocked / granted tags、冷却、能量消耗、目标类型、能力缩放和 `programs[]`。技能首版只允许 `skill_activated` trigger；程序 id 唯一，conditions/actions 必须来自生成契约，概率 / 内部冷却合法；状态、元素、stack rule、ability tag 与 pool 引用继续 fail-fast。
  - `visual_effects.json`：schema v3、唯一 effect id、固定枚举、合法正式资源、预览参数和对象池引用；旧 schema v1/v2 与遗留 `reduced_motion` / `quality_variants` 字段明确拒绝，高频条目必须声明已登记 pool id，catalog 不得指向 editor-only、`output/test_lab` 或裸程序几何。
  - `presentation_profiles.json`：唯一 profile id、父继承无环、cue / anchor 枚举、效果引用与可选音频 / 相机 / 屏幕绑定；首版 `hit_stop_profile_id` 必须为空。
  - `enemy_ai_profiles.json`：schema v5 profile id、视线 / 路径 / 记忆感知、决策间隔、玩家权重、通用移动参数、动作参数和 action id；远程攻击额外必填 `windup/burst_count/shot_interval`。攻击 action 必须携带与类型严格匹配的 `attack` 字典，非攻击 action 禁止携带 `attack`；旧 schema 与遗留攻击字段明确拒绝。
  - `enemies.csv`：精确表头包含敌人 id、名称 / 描述 key、可选图鉴图标、默认解锁 / 解锁规则、`tag_enemy`、独立对象池 id、专属 `scene_path`、`pool_prewarm`、AI profile 引用、表现 profile、生命、移速、有限正数 `gold_value_multiplier`、命中半径和分离半径；`pool_id` 必须唯一且等于敌人 id。旧 `gold_reward`、`contact_damage`、`contact_interval`、`element_id`、`exp_reward`、`enemy_ranged` 与 `visual_color` 列明确拒绝。场景必须位于正式 `actors/enemies/*.tscn`、存在且为 `PackedScene`，可跨内容 id 复用但不得指向基础场景；`ai_profile_id` 必须存在于 `enemy_ai_profiles.json`。
  - `enemy_rewards.json`：schema v1，只允许 `base_coefficient`、`time_growth_per_tier`、`random_multiplier_min`、`random_multiplier_max`；基础系数与随机上下界必须为有限正数，阶段增长必须为有限非负数，且随机下界不得高于上界。
  - `difficulty_profiles.json`：schema v2，每个 profile 必填唯一 `id`、已本地化 `name_key`、有限正数 `difficulty_coefficient`、威胁曲线和九段阶段名。标准 profile 当前系数为 `1.0`；旧 schema v1、缺字段或多余字段均拒绝。
  - `gear_mods.json`：schema v6；根级 7×7 board / 13 格掩码、拾取配置、有序奖励池、`reward_pool_contributions[]` 和可组合 `components[]`。`modifier` 必须声明 hero / weapon slot，且所有 stat 通过槽位支持矩阵；`program` 使用通用 trigger / condition / action 契约；`board_rule` 当前只允许 `occupy_only`。每个 `component_id` 在 Mod 内唯一。
  - `gear_mod_drop_tables.csv`：装备 Mod 掉落来源敌人、Mod id、掉落概率和敌人等级区间；敌人必须存在于 `enemies.csv`，Mod 必须存在于隔离后重读的 `gear_mods.json`，概率必须是 `0.0..1.0`，等级必须为至少 1 的整数且最大等级不低于最小等级，最终 `source/mod/level range` 必须唯一。官方 / 最终合并表不可为空；单个本地包可以不贡献掉落行。
  - `gear_mods.json` schema v6：校验宽高 / 中心 / 精确掩码、非法坐标、组件字段、slot-stat 兼容、程序结构 / 原语 / 参数、公共池、奖励池贡献、图鉴和默认解锁；明确拒绝 v5 `kind` / `map_behavior` / `grid_behavior` 以及等级 / 溢出字段。玩法指纹纳入 board、组件程序、奖励池 / 贡献、拾取、掉落与本地玩法环境，排除展示字段。
  - `content_unlock_rules.json`：schema v1；规则 id 唯一且为 snake_case，mode 只能来自生成的 `all/any` 契约，条件只能使用登记的五类 counter。定向计数器必须携带合法 `subject_id`，聚合计数器禁止携带；锁定内容必须引用有效规则，默认开放内容不得引用规则，规则不得闲置，禁止以锁定内容作为条件对象。`skills.json.default_unlocked=false` 在本阶段非法。
  - 初始可玩性：至少两个默认开放英雄；每个正式敌池至少有一个 0 秒默认开放敌人；每个正式 Gear Mod 奖励池至少有一个默认开放成员。所有相关池过滤发生在运行时 RNG 消费前。
  - `hazards.csv`：机关 id、名称 key、`tag_hazard`、对象池 id、表现 profile、伤害、伤害类型、触发间隔、范围和持续时间。
  - `map_layouts.json`：layout id、模式引用、有限地图矩形 bounds、玩家出生点、安全半径、刷怪边距、PCG 机关规则和人工机关摆点；`mode_id` 必须存在于 `game_modes.json`，所有机关 id 必须存在于 `hazards.csv`，bounds 必须分别整除 `grid.cell_width/cell_height`。
  - `spawn_waves.csv`：波次 id、模式 id、波次序号、时间窗、敌人引用、敌人权重、刷怪间隔、同时存活上限、预算，以及可选机关引用 / 权重。
  - `warzone_directors.json`：schema v2 director id、模式引用、固定 mutation、阶段时间窗、阶段启用 wave 和兴趣点；`mode_id` 必须存在于 `game_modes.json`，`wave_ids` 必须引用同模式 `spawn_waves.csv`，同模式所有 wave 必须至少被一个 phase 引用，兴趣点的 `hazard_ids` 必须非空且机关 / 地图引用必须存在；旧导演敌人组合字段会被明确拒绝。
  - 模块世界：世界必须恰好 7×7、模块必须恰好 11×11；起点固定 `(0,6)`，`objective_spawn` 必须精确声明 `(0,0)` / `(6,0)` / `(6,6)` 三个不重复等概率候选。模块 / 局部 / 全局坐标、placement footprint、引用、审核状态、相邻边缘开放格交集、外圈封闭、三个目标覆盖后的关键路线和内容预算都 fail-fast。模块 schema v4 使用严格 `module_place_world_event`；世界 schema v5 的限量组校验 `pick_distinct`、模板角色、权重和次数，正式 assignment 必须选三种不同事件。默认池只接受 `approved` 模板；`candidate` 只能供人工审核。
  - `world_events.json`：schema v1 严格按事件 kind 校验必填 / 多余字段、正时间、概率、递增费用、波次边界、次数、Mod 池引用和防御目标半径；事件 id、kind、state、reward 与 Mod pool 必须来自生成契约。
  - `active_items.json`：主动道具 id、名称 / 描述 key、默认解锁、`tag_active_item`、冷却充能、初始 / 最大充能和使用效果原语。
  - `consumables.json`：消耗品 id、名称 / 描述 key、默认解锁、`tag_consumable`、最大堆叠、初始数量、单次拾取数量和使用效果原语。
  - `credits.json`：致谢分组、分组标题 locale key、工作人员条目、外部资源 / 库 / 工具条目的 URL、license、是否随构建分发、是否需要 notice 与复核状态。
  - `level_progression.json`：schema v1，`first_level_cost`、`multiplier_numerator`、`multiplier_denominator` 都必须为正整数；运行时用整数有理数逐段向上取整，当前 100 与 13/10 的前十段和累计阈值由 schema tests 固定验证。
  - `reward_choice_pools.json`：schema v1，候选池、唯一条目 id、`stat_modifier` 类型、正权重、正 `min_level`、名称 / 描述 locale key 与属性修正；池和条目引用必须有效。
  - `game_modes.json`：schema v3，模式 id、名称 / 描述 key、默认解锁、participants / teams、角色池、武器池、技能池、敌人池、机关池、主动道具池、消耗品池、content tag blocklist 与玩家基础属性轻量覆盖；各池 id 必须引用对应数据。Gear Mod 不属于模式资源池，遗留 `resource_pools.relics` / `growth_pools` 会被明确拒绝。
  - `strings.csv`：key 前缀、`zh_CN` / `en` 必填、唯一 key。
- 导出版中 `client/data/*.csv` 必须作为原始 CSV 随包分发，DataLoader 依赖 `FileAccess` 读取原文件；`client/locale/strings.csv` 继续由 Godot 作为 `csv_translation` 导入，导出版缺少原始 `strings.csv` 时不枚举 optimized translation 全量 key，只在数据引用 locale key 时用当前翻译资源按需校验。
- 当前也校验模块世界 / 注册表 / 独立模块 JSON；运行时解释见 `docs/代码/module_world_manager.md`。技能、状态、地图、机关、EnemyAI、战区导演和 Gear Mod 仍分别以各自模块文档为权威。

## 依赖

- 上游依赖：Godot `FileAccess`、`JSON`、生成契约文件、`ModLoader`。
- 内部纯依赖：`DataReferenceIndexBuilder`、`GearModDropTableValidator` 与 `DataFingerprintBuilder` 只接收已加载的 `Variant` / `Array[Dictionary]` 和显式索引 / callback，不得反向读取 `DataLoader`、`ModLoader`、文件系统或 `user://`。
- 下游调用方：后续所有读取 `client/data/` 的业务模块。
- 禁止依赖：不得直接引用具体玩法系统，避免数据层反向依赖业务层。

## 扩展点

- 新数据格式优先通过新解析函数接入，再由业务模块做 schema 校验。
- 新约定字符串必须先改 `docs/词表与契约.md` 并跑契约同步，不在 DataLoader 内硬编码白名单。
- 热重载可复用 `data_reloaded` 信号扩展。
- 本地 mod 只能通过 `ModLoader` manifest v2 给 Gear Mod 定义、奖励池贡献、掉落和 locale 做声明式 append；不得让业务系统绕过 `DataLoader` 直接读取 `user://mods`。
- 新跨文件引用索引应在 `DataReferenceIndexBuilder` 新增纯静态入口，由 `DataLoader` 在原校验 / 读取时序中显式传入合并后的数据；不得让 builder 自行读文件、扫描 Mod、缓存或排序。
- 新 Gear Mod 掉落字段或规则应在 `GearModDropTableValidator` 的包内与合并入口分别落地，并由 `DataLoader` 保持“先隔离、再重读、再计数 / 校验”；不得在 validator 中读文件、禁用包或缓存合并 rows。
- 新增玩法指纹字段时在 `DataFingerprintBuilder` 明确加入归一化规则；不得直接哈希整份展示数据，也不得在 builder 内自行重新加载文件或扫描 Mod。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 加 JSON 数据 schema | `data_loader.gd` + `tools/validate_data.py` | `client/data/README.md`、对应模块文档 | `tools/validate_data.py`、headless boot |
| 改视觉效果 / profile schema | `data_loader.gd`、`validate_data.py`、catalog / profiles | `visual_effects.md`、数据手册、词表 | `sync_contracts --check` + `validate_data` + `vfx-smoke` |
| 改技能 schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/skill_system.md`、必要时 `docs/代码/status_effect_component.md` | `validate_data` + schema test + `l1-smoke` / `runtime-smoke` |
| 加 CSV 表读取 | `data_loader.gd` | `client/data/README.md` | `load_csv()` smoke / 数据校验 |
| 改敌人 AI profile schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/enemy_ai.md` | `validate_data` + schema test + `runtime-smoke` |
| 改敌人金币 / 难度 profile schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py`、`enemy_rewards.json`、`enemies.csv`、`difficulty_profiles.json` | `client/data/README.md`、`docs/代码/enemy_reward_resolver.md`、Difficulty / Runtime / Save 文档 | contracts + `validate_data` + schema test + L1/runtime/save/replay |
| 改内容解锁 schema / 可选字段 | `data_loader.gd`、`validate_data.py`、schema tests、三类内容数据与 `content_unlock_rules.json` | 数据手册、词表、ContentUnlockSystem / Runtime / Save / Replay 文档 | contracts + data/schema + content-progression/codex/runtime/save/replay |
| 改 Gear Mod 掉落校验 / 坏包隔离接线 | `gear_mod_drop_table_validator.gd`、`data_loader.gd`、schema tests、`mod_loader_v2_smoke.gd` | 本文档、必要时数据手册 / ModLoader 文档 | 目标 GUT + `validate_data` + schema test + `mod-loader-smoke` + headless boot |
| 改地图 layout schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/map_manager.md` | `validate_data` + schema test + `runtime-smoke` |
| 改模块世界 / 模板 schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/module_world_manager.md`、F13 工作包 | `sync_contracts --check` + `validate_data` + schema test + `module-world-smoke` + `save-smoke` |
| 改战区导演 schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/warzone_director.md`、F10 工作包 | `validate_data` + schema test + `runtime-smoke` + `f9-demo-smoke` |
| 改契约来源 | `tools/sync_contracts.py`、`_contracts.json` | `docs/词表与契约.md` | `tools/sync_contracts.py --check` |
| 改 mod 数据合并 | `mod_loader.gd`、`data_loader.gd` | `docs/代码/mod_loader.md`、本文档、GDD | `mod-loader-smoke`、data/schema、headless boot |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动时 contracts=0 | `client/data/_contracts.json` 是否存在且 JSON 有效 |
| `contract_values()` 返回空 | contract id 是否存在于 `_contracts.json` 的 `contracts` |
| CSV 行字段错位 | 表头数量与数据列数量是否一致 |
| `data_schema_ok=false` | headless boot 日志前后的 `[DataLoader]` fail-fast 错误 |
| 坏 Mod 的掉落行仍在最终合并表 | 确认 `validate_project_data()` 没有在包隔离前缓存 rows，且隔离后重读了 Gear Mod ids 与 `gear_mod_drop_tables.csv`；`schema_counts().gear_mod_drop_rows` 应只计最终合并行 |
| 导出版打开后像空场景 / 空界面 | 用 console 导出版检查 `data_schema_ok` 与 CSV 计数；若 `enemies`、`hazards`、`spawn_waves` 等为 0，确认 `client/data/*.csv.import` 是 `importer="keep"`，且 `export_presets.cfg` 的 `include_filter` 包含 `*.csv` |
| mod 内容没进数据 | `DataLoader.mod_diagnostics()` 与 `[ModLoader]` warning；确认 manifest `target` / `path` / `array_key` |

## 测试义务

- 必跑 `tools/godot_bridge.py --project client headless-boot`。
- 改 mod 接口或 `contract_values()` 合并逻辑时跑 `tools/godot_bridge.py --project client l1-smoke`。
- 改契约 / 数据时跑 `tools/sync_contracts.py --check` 与 `tools/validate_data.py`。
- F3 schema 变更需跑 `tools/test_data_loader_schema.py`，覆盖黄金样例、未登记 id、缺失 locale key、类型 / 范围错误、跨文件引用错误和 fail-fast 输出格式。
- 引用索引 builder 或 `validate_project_data()` 的索引接线变更需跑目标 GUT unit，覆盖坏 root / 类型、真实 loader String 输入、strict JSON 对非 String ID 的拒绝、各类空 ID、source order、重复折叠、输出无别名、机关 clamp / last-write 和波次嵌套结构；再跑 DataLoader schema 与 headless boot 确认读取、坏 Mod 隔离和 fail-fast 顺序不变。
- Gear Mod 掉落 validator 或接线变更需跑目标 GUT unit，覆盖数值边界、空合并表、多错误顺序、未知 id、等级解析 / 下限 / 倒置、重复 key、包 root / row 形状、exact-key 顺序、旧静默诊断、包内重复合法和跨调用无状态；再跑 Python schema 负例与 `mod-loader-smoke`，确认坏包的合法掉落行会随包隔离、最终 count / 有效包顺序不变。
- 指纹 builder 或两条公开 payload API 变更需跑 `l1-smoke` 的固定归一化样例与公开转发等价断言，并跑 `replay-smoke` / checked-in golden 确认当前数据指纹不变；仅当玩法数据有意改变时才更新 fingerprint 基线。
- 内容解锁 schema 变更还必须覆盖默认开放、缺规则 / 闲置规则、非法 subject、锁定条件对象、技能锁定、初始英雄 / 敌池 / Mod 池枯竭，并跑 `content-progression-smoke`。

## 迁移 / 兼容

Run v19 与 Replay v9 保存精确 `mod_environment[{id,version,gameplay_hash}]`；缺包、版本或 hash 不匹配时保留源文件并阻止继续 / 播放，不按损坏档隔离。旧 Run v18 与 Replay v8 不迁移。未来改变 `_contracts.json` 或 manifest schema 时必须同步 `tools/sync_contracts.py`、`tools/validate_data.py`、`docs/代码/mod_loader.md` 与本文档。

## 相关文档

- `docs/游戏设计文档.md` §9.3 / §9.19
- `docs/词表与契约.md`
- `docs/代码/mod_loader.md`
- `docs/代码/gameplay_effect_runtime.md`
- `docs/代码/content_unlock_system.md`
- `client/data/README.md`
- `docs/测试策略.md`
