# DataLoader 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `DataLoader` autoload 的代码契约权威；改公共 API、数据 schema、契约加载、CSV/JSON 解析或 fail-fast 行为时必须同步本文档、`docs/AI导航.md`、`client/data/README.md` 与必要的测试说明。

## 职责

- 统一加载 `client/data/` 下的 JSON 与 CSV 配置。
- 通过 `ModLoader` 合并 `user://mods/<mod_id>/` 下声明式数据 patch，为本地玩家 mod 提供统一入口。
- 启动时读取 `res://data/_contracts.json`，为后续数据校验提供词表白名单。
- 提供正式数据 schema 校验入口，当前覆盖 `player.json`、`characters.json`、`weapons.json`、`skills.json`、`enemy_ai_profiles.json`、`enemies.csv`、`enemy_rewards.json`、`difficulty_profiles.json`、`gear_mods.json`、`gear_mod_drop_tables.csv`、`content_unlock_rules.json`、`hazards.csv`、`map_layouts.json`、`module_worlds.json`、`module_templates.json`、`modules/*.json`、`warzone_directors.json`、`spawn_waves.csv`、`relics.json`、`active_items.json`、`consumables.json`、`credits.json`、`game_modes.json`、`level_progression.json`、`reward_choice_pools.json` 与 `strings.csv`。
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
| `client/scripts/autoload/mod_loader.gd` | 本地 mod manifest 扫描与数据 patch 合并入口 |
| `client/data/_contracts.json` | 由 `tools/sync_contracts.py` 生成的词表镜像 |
| `client/data/player.json` | schema v4 玩家统一身体半径、基础属性、防御、冲刺与掉落规则 |
| `client/data/characters.json` | schema v4 角色专属场景、primary-only palette、基础属性、标签、能力、控制配置和起始携带引用边界 |
| `client/data/weapons.json` | schema v5 武器、子弹、后坐与扩散边界；玩家无限射击并精确拒绝遗留 `ammo` |
| `client/data/skills.json` | 项目版轻量 GAS 技能、ability tag、激活条件、资源消耗、目标类型、效果原语和冷却边界 |
| `client/data/visual_effects.json` | 视觉效果 catalog、资源、空间、生命周期、对象池与表现策略 |
| `client/data/presentation_profiles.json` | 表现 profile 继承、cue、效果 / 音频 / 相机 / 屏幕绑定 |
| `client/data/enemy_ai_profiles.json` | schema v5 敌人对玩家 AI profile、感知、动作参数、显式攻击参数和动作列表边界 |
| `client/data/enemies.csv` | 敌人专属场景、独立对象池 / 预热、图鉴描述 / 图标、默认解锁、解锁规则、基础数值、金币价值倍率、通用 tag、AI profile、伤害类型和模式引用边界 |
| `client/data/enemy_rewards.json` | schema v1 敌人金币基础系数、阶段增长和独立随机区间 |
| `client/data/difficulty_profiles.json` | schema v2 难度名称、难度系数、威胁时间与敌人生命 / 伤害曲线 |
| `client/data/gear_mods.json` | 装备 Mod 定义、槽位、稀有度、rank、图鉴图标、默认解锁、解锁规则和修正器边界 |
| `client/data/content_unlock_rules.json` | schema v1 稀疏锁定规则；只登记显式锁定内容，支持 `all` / `any` 与五类进度条件 |
| `client/data/gear_mod_drop_tables.csv` | 装备 Mod 掉落来源、概率和敌人等级条件边界 |
| `client/data/hazards.csv` | 机关基础数值、对象池、伤害类型和模式引用边界 |
| `client/data/map_layouts.json` | 有限地图、玩家出生点、PCG 机关规则和人工摆点边界 |
| `client/data/warzone_directors.json` | schema v2 敌巢战区导演、固定阶段、巢变异主题、兴趣点和阶段启用 wave 边界 |
| `client/data/module_worlds.json` / `module_templates.json` / `modules/*.json` | 世界 schema v5、模块 schema v4：7×7 几何、左下起点、三角意识核候选、首次进入敌人数 / 预警 / 解锁权重、限量事件模板组、approved 模板池、路线预算、11×11 地形与静态内容摆放 |
| `client/data/world_events.json` | schema v1：五类事件、波次、交互半径、奖励、祭坛费用 / 献祭与普通 Mod 池 |
| `client/data/spawn_waves.csv` | 刷怪波次、模式引用、敌人 / 机关引用、时间窗和强度数值边界 |
| `client/data/relics.json` | 被动遗物 modifier / behavior 数据边界 |
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

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `data_reloaded` | 无 | `reload_contracts()` 成功刷新 `_contracts` 后 |

## 数据与契约

- 读取 `res://data/_contracts.json`，并在运行时叠加 `ModLoader.contract_extensions()` 返回的允许动态扩展 id。
- `_contracts.json` 由 `tools/sync_contracts.py` 生成，禁止手改。
- 玩家 mod 不得修改 `_contracts.json` 或生成常量；可在 manifest 中声明 `character_ids`、`game_modes`、`content_tags`、`locale_prefixes` 等少量运行时扩展 id，且必须以 `mod_<mod_id>_` 开头。
- 当前 F3 schema 覆盖：
  - `player.json`：schema v4 新增 `body`，且 `body` 必须且只能含正数 `radius`；其余根级配置继续包含 `base_stats`、`defense`、`dash`、`energy_drop` 与 `gold_drop`。stat id 必须来自词表，数值范围按 stat 类型校验；`max_hp` 是正数浮点血量，`health_regen` 是非负 HP/s，两个掉落的 `pickup_speed` 必须为正数。遗留 `pickup_orb_speed` 会被明确拒绝，`luck` 保留为暂未生效属性。
  - `characters.json`：schema v4 角色 id、专属 `scene_path`、表现 profile、名称 / 描述 key、可选图鉴图标、默认解锁 / 解锁规则、tags、capabilities、控制配置、起始携带引用和角色基础属性；字段缺失等同默认开放。每个 `palette` 必须且只能含一个合法 HTML 颜色 `primary`，遗留 `secondary` / `accent` 或任何额外键均拒绝。场景必须是正式 `actors/characters/*.tscn` 下存在的 `PackedScene`，不得指向基础场景或越界。不同角色 id 可以复用同一路径；起始武器、主动道具和消耗品引用必须存在于对应数据文件。
  - `weapons.json`：schema v5；武器 id、表现 profile、名称 / 描述 key、默认解锁、开火模式、开火音频 id、武器基础属性、子弹对象池、伤害类型与弹体数值。根级和单武器均执行 exact-key 校验，任何遗留 `ammo` 或额外字段都会拒绝。
  - `skills.json`：技能 id、表现 profile、名称 / 描述 key、`tag_skill`、ability tags、activation required / blocked / granted tags、冷却、能量消耗、目标类型、能力缩放声明和效果原语；技能 id、槽位、资源、targeting、effect 和 ability tag 必须来自词表，`skill_effect_damage` 的 `element_id` 交给 `Combat` 校验，`skill_effect_apply_status` 的 status / stack_rule / granted ability tags 必须来自生成契约；当状态效果同时声明正 `magnitude` 与正 `tick_interval` 时，还必须声明已登记 `element_id`。
  - `visual_effects.json`：schema v3、唯一 effect id、固定枚举、合法正式资源、预览参数和对象池引用；旧 schema v1/v2 与遗留 `reduced_motion` / `quality_variants` 字段明确拒绝，高频条目必须声明已登记 pool id，catalog 不得指向 editor-only、`output/test_lab` 或裸程序几何。
  - `presentation_profiles.json`：唯一 profile id、父继承无环、cue / anchor 枚举、效果引用与可选音频 / 相机 / 屏幕绑定；首版 `hit_stop_profile_id` 必须为空。
  - `enemy_ai_profiles.json`：schema v5 profile id、视线 / 路径 / 记忆感知、决策间隔、玩家权重、通用移动参数、动作参数和 action id；远程攻击额外必填 `windup/burst_count/shot_interval`。攻击 action 必须携带与类型严格匹配的 `attack` 字典，非攻击 action 禁止携带 `attack`；旧 schema 与遗留攻击字段明确拒绝。
  - `enemies.csv`：精确表头包含敌人 id、名称 / 描述 key、可选图鉴图标、默认解锁 / 解锁规则、`tag_enemy`、独立对象池 id、专属 `scene_path`、`pool_prewarm`、AI profile 引用、表现 profile、生命、移速、有限正数 `gold_value_multiplier`、命中半径和分离半径；`pool_id` 必须唯一且等于敌人 id。旧 `gold_reward`、`contact_damage`、`contact_interval`、`element_id`、`exp_reward`、`enemy_ranged` 与 `visual_color` 列明确拒绝。场景必须位于正式 `actors/enemies/*.tscn`、存在且为 `PackedScene`，可跨内容 id 复用但不得指向基础场景；`ai_profile_id` 必须存在于 `enemy_ai_profiles.json`。
  - `enemy_rewards.json`：schema v1，只允许 `base_coefficient`、`time_growth_per_tier`、`random_multiplier_min`、`random_multiplier_max`；基础系数与随机上下界必须为有限正数，阶段增长必须为有限非负数，且随机下界不得高于上界。
  - `difficulty_profiles.json`：schema v2，每个 profile 必填唯一 `id`、已本地化 `name_key`、有限正数 `difficulty_coefficient`、威胁曲线和九段阶段名。标准 profile 当前系数为 `1.0`；旧 schema v1、缺字段或多余字段均拒绝。
  - `gear_mods.json`：装备 Mod id、名称 / 描述 key、英雄 / 武器 slot、稀有度、最大 rank、drain、按 rank 计算的 stat modifier、装配规则和分解返还资源；id、slot、rarity、resource、stack rule 均来自词表 §13-A~§13-E。
  - `gear_mod_drop_tables.csv`：装备 Mod 掉落来源敌人、Mod id、掉落概率和敌人等级区间；敌人必须存在于 `enemies.csv`，Mod 必须存在于 `gear_mods.json`，概率必须是 `0.0..1.0`。
  - `gear_mods.json` schema v2：校验公共奖励池、满阶溢出金币、可选图鉴图标、默认解锁 / 解锁规则与每个 Mod 的 rank 0–5 效果曲线；不接受 inventory、drain、dismantle 或 fusion 字段。
  - `content_unlock_rules.json`：schema v1；规则 id 唯一且为 snake_case，mode 只能来自生成的 `all/any` 契约，条件只能使用登记的五类 counter。定向计数器必须携带合法 `subject_id`，聚合计数器禁止携带；锁定内容必须引用有效规则，默认开放内容不得引用规则，规则不得闲置，禁止以锁定内容作为条件对象。`skills.json.default_unlocked=false` 在本阶段非法。
  - 初始可玩性：至少两个默认开放英雄；每个正式敌池至少有一个 0 秒默认开放敌人；每个正式 Gear Mod 奖励池至少有一个默认开放成员。所有相关池过滤发生在运行时 RNG 消费前。
  - `hazards.csv`：机关 id、名称 key、`tag_hazard`、对象池 id、表现 profile、伤害、伤害类型、触发间隔、范围和持续时间。
  - `map_layouts.json`：layout id、模式引用、有限地图矩形 bounds、玩家出生点、安全半径、刷怪边距、PCG 机关规则和人工机关摆点；`mode_id` 必须存在于 `game_modes.json`，所有机关 id 必须存在于 `hazards.csv`，bounds 必须分别整除 `grid.cell_width/cell_height`。
  - `spawn_waves.csv`：波次 id、模式 id、波次序号、时间窗、敌人引用、敌人权重、刷怪间隔、同时存活上限、预算，以及可选机关引用 / 权重。
  - `warzone_directors.json`：schema v2 director id、模式引用、固定 mutation、阶段时间窗、阶段启用 wave 和兴趣点；`mode_id` 必须存在于 `game_modes.json`，`wave_ids` 必须引用同模式 `spawn_waves.csv`，同模式所有 wave 必须至少被一个 phase 引用，兴趣点的 `hazard_ids` 必须非空且机关 / 地图引用必须存在；旧导演敌人组合字段会被明确拒绝。
  - 模块世界：世界必须恰好 7×7、模块必须恰好 11×11；起点固定 `(0,6)`，`objective_spawn` 必须精确声明 `(0,0)` / `(6,0)` / `(6,6)` 三个不重复等概率候选。模块 / 局部 / 全局坐标、placement footprint、引用、审核状态、相邻边缘开放格交集、外圈封闭、三个目标覆盖后的关键路线和内容预算都 fail-fast。模块 schema v4 使用严格 `module_place_world_event`；世界 schema v5 的限量组校验 `pick_distinct`、模板角色、权重和次数，正式 assignment 必须选三种不同事件。默认池只接受 `approved` 模板；`candidate` 只能供人工审核。
  - `world_events.json`：schema v1 严格按事件 kind 校验必填 / 多余字段、正时间、概率、递增费用、波次边界、次数、Mod 池引用和防御目标半径；事件 id、kind、state、reward 与 Mod pool 必须来自生成契约。
  - `relics.json`：遗物 id、名称 / 描述 key、默认解锁、`tag_relic`、数值 modifiers、行为 behaviors，以及至少一个 modifier 或 behavior。
  - `active_items.json`：主动道具 id、名称 / 描述 key、默认解锁、`tag_active_item`、冷却充能、初始 / 最大充能和使用效果原语。
  - `consumables.json`：消耗品 id、名称 / 描述 key、默认解锁、`tag_consumable`、最大堆叠、初始数量、单次拾取数量和使用效果原语。
  - `credits.json`：致谢分组、分组标题 locale key、工作人员条目、外部资源 / 库 / 工具条目的 URL、license、是否随构建分发、是否需要 notice 与复核状态。
  - `level_progression.json`：schema v1，`first_level_cost`、`multiplier_numerator`、`multiplier_denominator` 都必须为正整数；运行时用整数有理数逐段向上取整，当前 100 与 13/10 的前十段和累计阈值由 schema tests 固定验证。
  - `reward_choice_pools.json`：schema v1，候选池、唯一条目 id、`stat_modifier` 类型、正权重、正 `min_level`、名称 / 描述 locale key 与属性修正；池和条目引用必须有效。
  - `game_modes.json`：schema v3，模式 id、名称 / 描述 key、默认解锁、participants / teams、角色池、武器池、技能池、敌人池、机关池、遗物池、主动道具池、消耗品池、content tag blocklist 与玩家基础属性轻量覆盖；角色池 id 必须存在于 `characters.json`，武器池 id 必须存在于 `weapons.json`，技能池 id 必须存在于 `skills.json`，敌人池 id 必须存在于 `enemies.csv`，机关池 id 必须存在于 `hazards.csv`，遗物池 id 必须存在于 `relics.json`，主动道具池 id 必须存在于 `active_items.json`，消耗品池 id 必须存在于 `consumables.json`；遗留 `resource_pools.growth_pools` 会被明确拒绝。
  - `strings.csv`：key 前缀、`zh_CN` / `en` 必填、唯一 key。
- 导出版中 `client/data/*.csv` 必须作为原始 CSV 随包分发，DataLoader 依赖 `FileAccess` 读取原文件；`client/locale/strings.csv` 继续由 Godot 作为 `csv_translation` 导入，导出版缺少原始 `strings.csv` 时不枚举 optimized translation 全量 key，只在数据引用 locale key 时用当前翻译资源按需校验。
- 当前也校验模块世界 / 注册表 / 独立模块 JSON；运行时解释见 `docs/代码/module_world_manager.md`。技能、状态、地图、机关、EnemyAI、战区导演和 Gear Mod 仍分别以各自模块文档为权威。

## 依赖

- 上游依赖：Godot `FileAccess`、`JSON`、生成契约文件、`ModLoader`。
- 下游调用方：后续所有读取 `client/data/` 的业务模块。
- 禁止依赖：不得直接引用具体玩法系统，避免数据层反向依赖业务层。

## 扩展点

- 新数据格式优先通过新解析函数接入，再由业务模块做 schema 校验。
- 新约定字符串必须先改 `docs/词表与契约.md` 并跑契约同步，不在 DataLoader 内硬编码白名单。
- 热重载可复用 `data_reloaded` 信号扩展。
- 本地 mod 只能通过 `ModLoader` 的声明式 JSON / CSV append patch 进入；不得让业务系统绕过 `DataLoader` 直接读取 `user://mods`。

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
| 改地图 layout schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/map_manager.md` | `validate_data` + schema test + `runtime-smoke` |
| 改模块世界 / 模板 schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/module_world_manager.md`、F13 工作包 | `sync_contracts --check` + `validate_data` + schema test + `module-world-smoke` + `save-smoke` |
| 改战区导演 schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/warzone_director.md`、F10 工作包 | `validate_data` + schema test + `runtime-smoke` + `f9-demo-smoke` |
| 改契约来源 | `tools/sync_contracts.py`、`_contracts.json` | `docs/词表与契约.md` | `tools/sync_contracts.py --check` |
| 改 mod 数据合并 | `mod_loader.gd`、`data_loader.gd` | `docs/代码/mod_loader.md`、本文档、GDD | `l1-smoke`、headless boot |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动时 contracts=0 | `client/data/_contracts.json` 是否存在且 JSON 有效 |
| `contract_values()` 返回空 | contract id 是否存在于 `_contracts.json` 的 `contracts` |
| CSV 行字段错位 | 表头数量与数据列数量是否一致 |
| `data_schema_ok=false` | headless boot 日志前后的 `[DataLoader]` fail-fast 错误 |
| 导出版打开后像空场景 / 空界面 | 用 console 导出版检查 `data_schema_ok` 与 CSV 计数；若 `enemies`、`hazards`、`spawn_waves` 等为 0，确认 `client/data/*.csv.import` 是 `importer="keep"`，且 `export_presets.cfg` 的 `include_filter` 包含 `*.csv` |
| mod 内容没进数据 | `DataLoader.mod_diagnostics()` 与 `[ModLoader]` warning；确认 manifest `target` / `path` / `array_key` |

## 测试义务

- 必跑 `tools/godot_bridge.py --project client headless-boot`。
- 改 mod 接口或 `contract_values()` 合并逻辑时跑 `tools/godot_bridge.py --project client l1-smoke`。
- 改契约 / 数据时跑 `tools/sync_contracts.py --check` 与 `tools/validate_data.py`。
- F3 schema 变更需跑 `tools/test_data_loader_schema.py`，覆盖黄金样例、未登记 id、缺失 locale key、类型 / 范围错误、跨文件引用错误和 fail-fast 输出格式。
- 内容解锁 schema 变更还必须覆盖默认开放、缺规则 / 闲置规则、非法 subject、锁定条件对象、技能锁定、初始英雄 / 敌池 / Mod 池枯竭，并跑 `content-progression-smoke`。

## 迁移 / 兼容

当前 `ModLoader` 不改变存档 schema；存档和回放后续应记录数据指纹，避免缺失 mod 时静默恢复旧局。未来改变 `_contracts.json` schema 或 mod manifest schema 时必须同步 `tools/sync_contracts.py`、`tools/validate_data.py`、`docs/代码/mod_loader.md` 与本文档。

## 相关文档

- `docs/游戏设计文档.md` §9.3 / §9.19
- `docs/词表与契约.md`
- `docs/代码/mod_loader.md`
- `docs/代码/content_unlock_system.md`
- `client/data/README.md`
- `docs/测试策略.md`
