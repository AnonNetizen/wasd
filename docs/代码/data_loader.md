# DataLoader 模块文档

> 权威范围：本页只记录该模块的公共契约、可观察行为、schema、所有权与依赖边界；私有实现和逐测试记录不进入本文档。

## 职责

- 统一加载 `client/data/` 下的 JSON 与 CSV 配置。
- 将官方 JSON / CSV 的物理读取与解析交给纯静态 `DataSourceReader`；`DataLoader` 保留公开读取门面、错误输出、Mod overlay 与 contracts 例外。
- 通过 `ModLoader` 合并 `user://mods/<mod_id>/` 下声明式数据 patch，为本地玩家 mod 提供统一入口。
- 将已加载、已合并且完成坏包隔离的数据交给纯 `DataReferenceIndexBuilder` 构建跨文件校验索引；读取顺序、Mod 边界和 schema 错误仍由 `DataLoader` 持有。
- 将已加载的玩家配置交给纯 `PlayerDataValidator` 校验；`DataLoader` 继续持有文件读取、stat / pool 契约 callback、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的相机反馈配置交给纯 `CameraFeedbackValidator` 校验；`DataLoader` 继续持有文件读取、资源路径错误包装、调用位置、二次索引读取和 schema 计数。
- 将已加载的元素目录交给纯 `ElementCatalogValidator` 校验；`DataLoader` 继续持有单次 Mod-aware 读取、locale / element contract callback、资源路径错误包装、调用位置和两项 schema 计数。
- 将已加载的刷怪波次行交给纯 `SpawnWaveCatalogValidator` 校验；`DataLoader` 继续持有两次独立 Mod-aware 读取、game mode 契约 callback、三类引用索引、资源路径错误包装、调用位置和 raw row count。
- 将已加载的英雄被动目录交给纯 `HeroPassiveCatalogValidator` 校验；`DataLoader` 继续持有两次独立读取、Mod-aware locale / passive id / effect / element callback、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的角色目录交给纯 `CharacterCatalogValidator` 校验；`DataLoader` 继续持有表现引用→schema→引用索引三次独立 Mod-aware 读取、locale / contract / actor scene / stat callback、五类跨目录索引、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的武器目录交给纯 `WeaponCatalogValidator` 校验；`DataLoader` 继续持有三次独立读取、Mod-aware locale / audio / stat / contract callback、共享武器 stat 分类、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的致谢配置交给纯 `CreditsValidator` 校验；`DataLoader` 继续持有文件读取、Mod-aware locale key 校验、资源路径错误包装、调用位置和 schema 计数。
- 将包内与最终合并的 Gear Mod 掉落行交给纯 `GearModDropTableValidator` 校验；`DataLoader` 继续持有读取、错误输出、坏包禁用 / 重读和 schema 计数。
- 将已加载的机关 CSV 行交给纯 `HazardCatalogValidator` 校验；`DataLoader` 继续持有每次独立读取、Mod-aware locale / 契约 callback、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的主动道具配置交给纯 `ActiveItemCatalogValidator` 校验；`DataLoader` 继续持有每次独立读取、Mod-aware locale / tag / effect callback、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的消耗品配置交给纯 `ConsumableCatalogValidator` 校验；`DataLoader` 继续持有每次独立读取、Mod-aware locale / tag / effect callback、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的敌人 AI profiles 交给纯 `EnemyAiProfileValidator` 校验；`DataLoader` 继续持有单次 Mod-aware 读取、action / element / pool 契约 callback、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的敌人金币模型交给纯 `EnemyRewardModelValidator` 校验；`DataLoader` 继续持有文件读取、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的等级曲线交给纯 `LevelProgressionValidator` 校验；`DataLoader` 继续持有文件读取、资源路径错误包装、校验顺序和 schema 计数。
- 将已加载的通用奖励选择池交给纯 `RewardChoicePoolValidator` 校验；`DataLoader` 继续持有文件读取、Mod-aware locale / stat modifier 校验、资源路径错误包装、调用位置和 schema 计数。
- 将已加载的难度 profiles 交给纯 `DifficultyProfileValidator` 校验；`DataLoader` 继续持有文件读取、Mod-aware locale key 校验、资源路径错误包装、调用位置、二次引用索引读取和 schema 计数。
- 将合并后的技能、Gear Mod 与掉落表交给纯 `DataFingerprintBuilder` 归一化；`DataLoader` 只负责数据源与 Mod 环境，Replay 继续负责最终 SHA-256。
- 启动时读取 `res://data/_contracts.json`，为后续数据校验提供词表白名单。
- 提供正式数据 schema 校验入口，当前覆盖 `player.json`、`camera_feedback.json`、`hero_passives.json`、`characters.json`、`weapons.json`、`skills.json` v3、`enemy_ai_profiles.json`、`enemies.csv`、`enemy_rewards.json`、`difficulty_profiles.json`、`gear_mods.json` v6、`gear_mod_drop_tables.csv`、`content_unlock_rules.json`、`hazards.csv`、`map_layouts.json`、`module_worlds.json`、`module_templates.json`、`modules/*.json`、`warzone_directors.json`、`spawn_waves.csv`、`active_items.json`、`consumables.json`、`credits.json`、`game_modes.json`、`level_progression.json`、`reward_choice_pools.json` 与 `strings.csv`。
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
| `client/scripts/data/data_source_reader.gd` | 对单次官方 JSON / CSV 读取与解析返回 typed result；无缓存、无 Node / autoload、无 Mod overlay、无错误输出 |
| `client/scripts/data/data_reference_index_builder.gd` | 从调用方已加载的 JSON / CSV 值构建 18 类跨文件引用索引；纯、静态、无状态，不读取文件 / Mod、不输出错误、不缓存或排序 |
| `client/scripts/data/player_data_validator.gd` | 纯、静态的玩家 schema 校验；只接收已加载 root、stat / pool callback 与错误 sink，不读文件、不持有 Node / cache，也不写 schema 计数 |
| `client/scripts/data/camera_feedback_validator.gd` | 纯、静态的相机反馈 schema 校验；只接收已加载 root 与错误 sink，不读文件、不持有 Node / cache，也不写 schema 计数或引用索引 |
| `client/scripts/data/element_catalog_validator.gd` | 纯、静态的元素 JSON schema 校验；只接收已加载 root、locale / element id / 已登记元素列表 callback 与错误 sink，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或构建引用索引 |
| `client/scripts/data/enemy_ai_profile_validator.gd` | 纯、静态的敌人 AI profile schema 校验；只接收已加载 root、通用契约 callback 与错误 sink，独立校验感知、目标、移动和四类显式攻击，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或构建引用索引 |
| `client/scripts/data/spawn_wave_catalog_validator.gd` | 纯、静态的刷怪波次 CSV schema 校验；只接收已加载 typed rows、enemy / hazard / game mode 索引、mode 契约 callback 与错误 sink，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或构建引用索引 |
| `client/scripts/data/hero_passive_catalog_validator.gd` | 纯、静态的英雄被动 JSON schema 校验；只接收已加载 root、locale / passive id / effect / element callback 与错误 sink，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或构建引用索引 |
| `client/scripts/data/character_catalog_validator.gd` | 纯、静态的角色 JSON schema 校验；只接收已加载 root、weapon / active-item / consumable / skill / hero-passive 五类索引、locale / contract / actor-scene / stat callback 与错误 sink，独立校验角色字段、palette、起始 loadout、技能资源和 base stats，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或加载 PackedScene |
| `client/scripts/data/weapon_catalog_validator.gd` | 纯、静态的武器 JSON schema 校验；只接收已加载 root、共享 weapon stat 列表、locale / audio / stat / pool / element callback 与错误 sink，独立校验 recoil model、武器字段、base stats 和 projectile，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或构建引用索引 |
| `client/scripts/data/credits_validator.gd` | 纯、静态的致谢 schema 校验；只接收已加载 root、locale key callback 与错误 sink，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数 |
| `client/scripts/data/gear_mod_drop_table_validator.gd` | 纯、静态的包内 / 合并掉落行校验；只接收现成 rows / ID 索引与错误 sink，不读文件 / Mod、不持有 Node / cache、不排序 |
| `client/scripts/data/hazard_catalog_validator.gd` | 纯、静态的机关 CSV schema 校验；只接收已加载的 typed rows、locale / 契约 callback 与错误 sink，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或构建引用索引 |
| `client/scripts/data/active_item_catalog_validator.gd` | 纯、静态的主动道具 JSON schema 校验；只接收已加载 root、locale / tag / effect callback 与错误 sink，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或构建引用索引 |
| `client/scripts/data/consumable_catalog_validator.gd` | 纯、静态的消耗品 JSON schema 校验；只接收已加载 root、locale / tag / effect callback 与错误 sink，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或构建引用索引 |
| `client/scripts/data/enemy_reward_model_validator.gd` | 纯、静态的敌人金币模型校验；只接收已加载 root 与错误 sink，不读文件、不持有 Node / cache，也不写 schema 计数 |
| `client/scripts/data/level_progression_validator.gd` | 纯、静态的等级曲线校验；只接收已加载 root 与错误 sink，不读文件、不持有 Node / cache，也不写 schema 计数 |
| `client/scripts/data/reward_choice_pool_validator.gd` | 纯、静态的通用奖励选择池结构校验；只接收已加载 root、locale callback、modifier callback 与错误 sink，不读文件 / Mod / 契约、不持有 Node / cache，也不写 schema 计数 |
| `client/scripts/data/difficulty_profile_validator.gd` | 纯、静态的难度 profile schema 校验；只接收已加载 root、locale key callback 与错误 sink，不读文件 / Mod、不持有 Node / cache，也不写 schema 计数或引用索引 |
| `client/scripts/data/data_fingerprint_builder.gd` | 纯、类型化的玩法指纹 payload 归一化；不读取文件、不访问 autoload、不改变数组顺序 |
| `client/tests/unit/test_data_reference_index_builder.gd` | 锁定引用索引的坏 root / 类型、真实 loader String 产物、strict JSON 对 `StringName` / 数字 ID 的拒绝、空 ID、插入顺序、重复折叠、别名隔离、机关半径与嵌套波次行为 |
| `client/tests/unit/test_data_source_reader.gd` | 锁定 JSON 对象 / 数组 / 标量、`null` 旧失败语义、CSV 有无表头、短行补空、长行截断、空行、空文件、失败元数据与每次重读无缓存 |
| `client/tests/integration/test_data_source_reader_adapter.gd` | 通过真实 `DataLoader.load_json()` / `load_csv()` 门面和 root `ModLoader` 测试替身，锁定失败元数据转 `_fail()`、失败时不调 overlay、成功后才 overlay、contracts 禁止 overlay 与每次重读 |
| `client/tests/unit/test_player_data_validator.gd` | 锁定玩家 root / base stats 硬返回、schema / body 诊断顺序、stat callback 与源顺序 / raw count、金币池双诊断、energy 兼容缺口、错误 sink 和跨调用无状态 |
| `client/tests/unit/test_camera_feedback_validator.gd` | 锁定相机反馈 schema、aim / 两组 shake / 武器振幅指数的诊断顺序、嵌套 Dictionary 短路、int-like / finite / 数值边界、额外 key、错误 sink 和跨调用无状态 |
| `client/tests/unit/test_element_catalog_validator.gd` | 锁定元素 root 硬返回、exact int-like schema、两个规范化计数、字段 / callback / contract-list 时序、elements / components / combinations 历史 bool 缺口、定义覆盖、合法重复 / 无序组合与跨调用无状态 |
| `client/tests/unit/test_spawn_wave_catalog_validator.gd` | 锁定波次 raw row count、行号 / id / mode-wave 去重、mode 契约历史 bool 缺口、三类引用、CSV String 解析、数值 / 时间 / 可选机关边界、诊断 source-order 与跨调用无状态 |
| `client/tests/unit/test_hero_passive_catalog_validator.gd` | 锁定英雄被动 root 硬返回、exact int-like schema、规范化计数、passives Array / id 历史 bool 缺口、字段与 callback 顺序、params 局部短路、element / multiplier 边界、额外字段忽略和跨调用无状态 |
| `client/tests/unit/test_character_catalog_validator.gd` | 锁定角色 root / schema / raw count、完整 callback source-order、id / tag / capability / passive / skill-resource 历史 bool 缺口、scene / locale / element / hero skill、palette、起始 loadout、技能资源 / 数值、base stat source-order、输入不变与跨调用无状态 |
| `client/tests/unit/test_weapon_catalog_validator.gd` | 锁定武器 root / schema / recoil source-order 与 caps、规范化 count、weapon exact-key / 重复、locale / audio / stat callback、required / supported / 特殊 stats、projectile contract / 数值、局部短路、输入不变和跨调用无状态 |
| `client/tests/unit/test_credits_validator.gd` | 锁定致谢 schema、section / entry source order 与计数、String 化重复 id、external 分支、locale callback、错误 sink 和跨调用无状态 |
| `client/tests/unit/test_gear_mod_drop_table_validator.gd` | 锁定掉落表边界、空表、多错误顺序、未知引用、等级范围 / 重复、包输入形状、旧静默诊断与跨调用无状态 |
| `client/tests/unit/test_hazard_catalog_validator.gd` | 锁定机关源行计数、空表、行号 / id 重复、tag trim / 去空 / 契约 / 重复 / 必需顺序、pool / element 契约、CSV 解析 / finite / 数值边界、callback 非短路、额外列忽略与跨调用无状态 |
| `client/tests/unit/test_active_item_catalog_validator.gd` | 锁定主动道具 root / schema / 规范化计数、item 字段顺序、id 重复与不 trim、tag 历史 bool 缺口、charge 局部短路 / 数值关系、use effects 双诊断 / callback、额外字段忽略与跨调用无状态 |
| `client/tests/unit/test_consumable_catalog_validator.gd` | 锁定消耗品 root / schema / 规范化计数、item 字段顺序、id 重复与不 trim、tag 历史 bool 缺口、stack 局部短路 / 数值关系、use effects 双诊断 / callback、额外字段忽略与跨调用无状态 |
| `client/tests/unit/test_enemy_reward_model_validator.gd` | 锁定敌人金币模型的 exact-key / 字段错误顺序、int-like schema、数值 / 有限 / 范围边界、错误 sink 和跨调用无状态 |
| `client/tests/unit/test_level_progression_validator.gd` | 锁定等级曲线有效 / 边界 root、字段错误文本与顺序、int-like 浮点、跨字段关系、额外 root key、错误 sink 参数和跨调用无状态 |
| `client/tests/unit/test_reward_choice_pool_validator.gd` | 锁定奖励池 source count、pool / entry shape 与重复顺序、locale / modifier callback、schema int-like、历史非 Array / 未登记 stat 诊断但 bool 可能仍成功的兼容缺口、错误 sink 和跨调用无状态 |
| `client/tests/unit/test_difficulty_profile_validator.gd` | 锁定难度 profile 的 root / profile exact-key 顺序、合法 String ID 与九段文案重复、五个数值边界、Mod-aware locale callback、源数组计数、错误 sink 和跨调用无状态 |
| `client/scripts/autoload/mod_loader.gd` | 本地 mod manifest 扫描与数据 patch 合并入口 |
| `client/data/_contracts.json` | 由 `tools/sync_contracts.py` 生成的词表镜像 |
| `client/data/player.json` | schema v4 玩家统一身体半径、基础属性、防御、冲刺与掉落规则 |
| `client/data/camera_feedback.json` | schema v3 瞄准引导、玩家受伤震屏与武器后坐震屏参数 |
| `client/data/elements.json` | schema v1 中性 / 基础 / 复合元素定义、组件与无序组合结果 |
| `client/data/hero_passives.json` | schema v1 英雄被动 id、名称 / 描述 key、通用 effect 与元素承伤倍率参数 |
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
| 配置读取 | 每次公开调用都让 `DataSourceReader` 重新打开官方文件并解析；失败元数据由 `DataLoader` 转为原 `[DataLoader]` 错误，成功后才叠加已启用本地 Mod patch | `DataSourceReader.read_json()` / `read_csv()`、`DataLoader.load_json()` / `load_csv()` |
| schema 校验 | 启动 smoke 或工具调用正式数据校验；运行时会校验合并后的数据 | `validate_project_data()`、`schema_counts()` |
| 玩家配置 | locale 校验后读取 `player.json` 并交给纯 validator；DataLoader 通过既有 stat helper 与 pool 契约 helper 保留字段范围和错误文本，仅在 validator 到达合法非空 `base_stats` 后写入 raw stat count，再继续相机反馈校验 | `PlayerDataValidator.validate()`、`_validate_player_stat_value()`、`_require_player_pool_id()` |
| 相机反馈 | 玩家 schema 后读取 `camera_feedback.json` 并交给纯 validator；随后必须再次 `load_json()`，把新 payload 交给引用 builder，再继续视觉效果校验，不缓存或复用校验 payload | `CameraFeedbackValidator.validate()`、`DataReferenceIndexBuilder.collect_camera_feedback_ids()` |
| 引用索引 | 每个 schema 校验后按原读取顺序重新取得当前合并值，再交给纯 builder 建索引；Gear Mod 必须在坏玩法包隔离后重新读取 | `DataReferenceIndexBuilder.collect_*()` |
| 元素目录 | 表现引用校验后单次读取 `elements.json` 并交给纯 validator；validator 完成元素 source-order 遍历后才通过 DataLoader callback 读取当前 `elements` 契约，再检查组合；Dictionary root 写规范化元素 / 组合数量，随后继续英雄被动，不缓存或构建索引 | `ElementCatalogValidator.validate()`、`contract_values("elements")` |
| 英雄被动目录 | 元素校验后独立读取 `hero_passives.json` 并交给纯 validator；Dictionary root 写规范化 passive 数量，随后再次独立读取供引用 builder 使用，再继续 weapons，不缓存或复用第一次 payload | `HeroPassiveCatalogValidator.validate()`、`DataReferenceIndexBuilder.collect_hero_passive_ids()` |
| 致谢 | 技能校验与引用索引完成后、角色校验前读取 `credits.json` 并交给纯 validator；DataLoader 通过现有 locale helper 保留契约扩展、Mod CSV patch 与导出版 translation fallback，再按 validator 返回的源数组计数写入 schema count | `CreditsValidator.validate()`、`_require_credits_locale_key()` |
| 敌人金币模型 | 敌人 AI profile 校验完成后、`enemies.csv` 与 Mod 隔离前读取 `enemy_rewards.json`；纯 validator 按旧顺序收集错误，DataLoader 补资源路径并仅为 Dictionary root 写 profile count | `EnemyRewardModelValidator.validate()` |
| Gear Mod 掉落 | 敌人索引建好后先校验每包 rows 并隔离坏包，再重读合并 Gear Mod / 世界事件 / 掉落 CSV；合并 rows 数量仍由 DataLoader 记录，错误仍经 `_schema_fail()` 输出 | `GearModDropTableValidator.validate_package_rows()`、`validate_merged_rows()` |
| 机关目录 | Gear Mod 掉落校验后独立读取 `hazards.csv` 并交给纯 validator，写入原始行数后再独立读取一次供引用 builder 使用，然后继续 active items；更早的表现 profile 引用校验也保持自己的读取，三次不缓存、不复用 | `HazardCatalogValidator.validate()`、`DataReferenceIndexBuilder.collect_hazard_ids()` |
| 主动道具目录 | 机关 schema 与第二次机关索引读取后独立读取 `active_items.json` 并交给纯 validator；Dictionary root 写入规范化 item 数量，随后再次独立读取供引用 builder 使用，再继续 consumables。更早的表现 profile 引用校验仍独立读取同一文件，三次不缓存、不复用 | `ActiveItemCatalogValidator.validate()`、`DataReferenceIndexBuilder.collect_active_item_ids()` |
| 消耗品目录 | 主动道具第二次索引读取后独立读取 `consumables.json` 并交给纯 validator；Dictionary root 写入规范化 consumable 数量，随后再次独立读取供引用 builder 使用，再继续 skills。更早的表现引用校验仍独立读取同一文件，三次不缓存、不复用 | `ConsumableCatalogValidator.validate()`、`DataReferenceIndexBuilder.collect_consumable_ids()` |
| 等级曲线 | 角色校验完成后读取 `level_progression.json`，由纯 validator 按旧顺序收集字段错误；DataLoader 补资源路径并仅为 Dictionary root 写入 profile count，再继续奖励池校验 | `LevelProgressionValidator.validate()` |
| 通用奖励选择池 | 等级曲线后读取 `reward_choice_pools.json` 并交给纯 validator；DataLoader 通过既有 locale helper 与 `_validate_modifiers(..., false)` 保留 Mod-aware 文案、stat 契约和 stat 数值边界，仅为 Dictionary root 写入规范化 pool count，再继续难度 profile 校验 | `RewardChoicePoolValidator.validate()`、`_require_reward_choice_locale_key()`、`_validate_reward_choice_modifiers()` |
| 难度 profiles | 奖励池校验后读取 `difficulty_profiles.json` 并交给纯 validator；DataLoader 通过现有 locale helper 保留契约扩展、Mod CSV patch 与导出版 translation fallback，仅为 Dictionary root 写入 validator 返回的规范化 profile count，随后再次读取同一文件构建引用索引 | `DifficultyProfileValidator.validate()`、`_require_difficulty_profile_locale_key()`、`DataReferenceIndexBuilder.collect_difficulty_profile_ids()` |
| 刷怪波次 | game modes 校验→内容解锁→第二次 game mode ID 读取→map layouts 校验后，第一次读取 `spawn_waves.csv` 并交给纯 validator；DataLoader 保留 mode 契约 adapter、三类引用索引和 raw row count，然后第二次独立读取建 wave index，再二读 map layout IDs 并校验 warzone director；两次 wave 读取都经 Mod overlay，不缓存 / 复用 | `SpawnWaveCatalogValidator.validate()`、`_require_spawn_wave_mode_id()`、`DataReferenceIndexBuilder.collect_spawn_wave_ids_by_mode()` |
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

### 内部纯数据源读取 API

`DataSourceReader` 是无状态 `RefCounted` 边界，只使用 Godot `FileAccess` / `JSON` 解析单次官方输入。它不访问 `DataLoader`、`ModLoader`、autoload 或 `user://mods`，不缓存结果，不 `push_error`。

| 静态入口 | 返回 | 保留的兼容语义 |
|----------|------|----------------|
| `read_json(resource_path)` | `JsonReadResult {ok, data, failure_field, failure_expected}` | 打开失败返回 `file / readable JSON file`；`JSON.parse_string()` 返回 `null` 时无论原文是 JSON `null` 还是非法文本，都返回 `json / valid JSON`；其余 root 类型不在本层限制 |
| `read_csv(resource_path, has_header)` | `CsvReadResult {ok, rows, failure_field, failure_expected}` | 打开失败返回 `file / readable CSV file`；有表头时短行补空、长行忽略多余列，无表头时键为从 `"0"` 开始的字符串索引；仅单列空白行被跳过，空文件 / 仅表头文件成功返回空数组 |

`DataLoader.load_json()` / `load_csv()` 仅在 result 成功后调用 `_apply_json_mods()` / `_apply_csv_mods()`；`CONTRACTS_PATH` 仍由 `_apply_json_mods()` 原地短路，禁止 Mod 覆盖。Reader 失败时 `DataLoader` 用 result 的 field / expected 调用原 `_fail()`，并继续返回 JSON 空字典或 CSV 空数组。

### 内部纯引用索引 API

`DataReferenceIndexBuilder` 接收调用方已加载的 `Variant`，每次返回新 `Dictionary`；它不访问 `DataLoader`、`ModLoader`、文件系统或 `user://`，不报告 schema 错误，也不缓存、排序或深拷贝无关数据。

| 分类 | 静态入口 | 保留的兼容语义 |
|------|----------|----------------|
| Camera / 表现 | `collect_camera_feedback_ids()`、`collect_visual_effect_ids()`、`collect_presentation_profile_ids()` | 消费真实 JSON loader 的 String key / ID；Camera 跳过 `schema_version` 且只收 Dictionary profile，visual / presentation 过滤空 ID |
| 普通 JSON | `collect_hero_passive_ids()`、`collect_weapon_ids()`、`collect_enemy_ai_profile_ids()`、`collect_gear_mod_ids()`、`collect_world_event_ids()`、`collect_active_item_ids()`、`collect_consumable_ids()`、`collect_skill_ids()`、`collect_character_ids()`、`collect_difficulty_profile_ids()`、`collect_game_mode_ids()`、`collect_map_layout_ids()` | 只接收原值类型为 String 的 ID；空 String 继续保留，重复 ID 原位折叠且后写不改变首次插入顺序 |
| CSV | `collect_enemy_ids()`、`collect_hazard_ids()` | 消费 `load_csv()` 的 String ID 并过滤空值；机关半径按旧规则从 String 转 int、至少为 1，重复 ID 最后写入值生效但不重排 |
| 波次 | `collect_spawn_wave_ids_by_mode()` | 消费 `load_csv()` 的 String mode / wave ID 并过滤空值，保持 mode 与各 mode 内 wave 的首次插入顺序，返回独立嵌套 Dictionary |

### 内部纯玩家配置校验 API

`PlayerDataValidator.validate(raw_data, validate_stat_value, require_pool_id, report_failure)` 每次返回新的 typed `ValidationResult { is_valid, stat_count, has_stat_count }`。Stat callback 接收 `(field_path, stat, value)`，pool callback 接收 `(field_path, value)` 并返回已登记 id 或空字符串，错误 sink 接收 `(field_path, expected)`；正式接线由 `DataLoader` 补 `PLAYER_DATA_PATH`，复用 `_validate_stat_value()`、`_require_registered(..., "pool_ids")` 与 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、缓存或 schema count；金币池的固定目标使用生成的 `PoolIds.GOLD_ORB`。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并立即返回，且 `has_stat_count=false`；Dictionary root 不做 exact-key 校验，也不校验 `defense` / `dash`。
- Dictionary root 按 schema → body → base stats → gold drop → energy drop 的旧顺序收集错误。`schema_version` 精确为 int-like `4`；body 合法时先按固定 `radius` required、原 Dictionary 插入序 extra、再校验 radius 为有限正数，body 类型错误不阻止后续 base stats。
- `base_stats` 非 Dictionary 或为空时报告 `non-empty Dictionary` 后硬返回；此前 schema / body 错误保留，但 gold / energy 不再执行，stat callback 不调用且 count 不写。合法非空 Dictionary 先拒绝遗留 `pickup_orb_speed`，再把原 Dictionary size 写入 result，随后按 JSON loader 可达的 String key source order 调 stat callback；raw count 包含遗留或未登记 stat。实现仍沿用 `String(raw_key)`，但不把测试字面量的跨类型 key 转换声明为兼容契约。
- gold drop 只校验 Dictionary、正 `pickup_speed` 与 pool id。Pool callback 返回空字符串时，既保留 callback 自身的未登记 / 非空诊断，也继续追加 `gold_drop.pool_id / gold_orb`；返回已登记但非 `gold_orb` 的 id 时同样追加该诊断。gold drop 不做 exact-key 校验。
- energy drop 只校验 Dictionary 与正 `pickup_speed`；`chance`、`amount`、`pool_id`、`rng_stream` 和额外字段继续不在本 GDScript 边界校验。该 under-validation 及 root / defense / dash 缺口只做等价提取，不代表新数据可依赖；收紧必须另立迁移决策并同步 Python schema。
- `DataLoader` 保留 locale 后 / camera feedback 前的调用位置、首次 `load_json()`、资源路径包装和 callback 依赖；仅当 `has_stat_count=true` 时写 `_last_schema_counts.player_stats`，因此 base stats 硬返回继续不留下 count。

### 内部纯相机反馈校验 API

`CameraFeedbackValidator.validate(raw_data, report_failure)` 的错误 sink 只接收 `(field_path, expected)`。正式接线由 `DataLoader` 补 `CAMERA_FEEDBACK_PATH` 并转发到 `_schema_fail()`；validator 不访问 autoload、文件、`user://`、Mod、缓存或引用索引。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并立即返回；额外 root、aim 或 shake key 继续允许。
- Dictionary root 先校验 schema，再校验 aim 的 4 个字段，然后依次校验玩家受伤 shake 的 7 个字段、武器后坐 shake 的 7 个字段，最后单独校验 `weapon_recoil_shake.amplitude_exponent`。
- `aim_look` 或任一 shake profile 非 `Dictionary` 时只报告该 profile 的 `Dictionary` 错误并跳过其内部字段；武器 profile 非 Dictionary 时也跳过末尾的振幅指数，其他 profile 仍按顺序继续。
- `schema_version` 固定为 3，整数值浮点继续视为 int-like。所有数值先要求 number / finite；`pointer_offset_ratio` 必须大于 `0.0` 且不超过 `1.0`，aim 最大偏移 / 死区非负、平滑时间为正；shake 振幅非负，频率 / 增长 / 持续 / 衰减时间为正，两个位置乘数在 `0.0..1.0`；武器振幅指数非负。
- `DataLoader` 保留第一次 `load_json(CAMERA_FEEDBACK_PATH)` 供 validator 使用；随后按既有顺序第二次加载供 `DataReferenceIndexBuilder` 构建 id，不缓存或复用第一次 payload。root 非 Dictionary 不写计数；Dictionary root 即使字段非法也固定写 `camera_feedback_profiles = 2`。

### 内部纯致谢校验 API

`CreditsValidator.validate(raw_data, require_locale_key, report_failure)` 每次返回新的 `ValidationResult`，包含 `is_valid`、`section_count` 与 `entry_count`。locale callback 与错误 sink 分别接收 `(field_path, value)` 和 `(field_path, expected)`；validator 不访问 autoload、文件、`user://`、Mod 或缓存。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并立即返回；Dictionary root 先校验 `schema_version >= 1`，再校验 `sections`。额外 root、section 和 entry key 继续允许。
- `sections` 非 Array 时先报告 `Array`，归一为空数组后继续报告 `non-empty Array`；section 与 entry 按源数组顺序校验，非 Dictionary 元素只报告当前位置的 `Dictionary` 并局部短路。
- section 内按 id → 重复 id → title locale → entries shape → entry 的旧顺序收集错误。重复检测继续使用 `String(id)`；非空 String id 参与 seen 集合，空 String 不参与。
- entry 内按 kind → name → role locale 校验。凡 String 化后的 kind 以 `external_` 开头，即使 kind 枚举本身非法，仍依次校验 URL、license、三个 notice bool；可选 `copyright` 始终最后校验。`staff` 与非 external 前缀的非法 kind 不校验这些额外字段。
- locale 规则继续由 DataLoader 转发现有 `_require_locale_key()`：保留动态 Mod locale prefix、合并后的 `strings.csv` key、导出版 translation fallback，以及原有诊断文本和顺序。
- `section_count` 等于归一化 sections 数组长度；`entry_count` 是所有 Dictionary section 的归一化 entries 数组长度之和，包含其中的非 Dictionary entry。DataLoader 仅在 root 为 Dictionary 时按 sections → entries 顺序写入两个 count。

### 内部纯 Gear Mod 掉落校验 API

`GearModDropTableValidator` 的 `report_failure` 只接收 `(field_path, expected)`；正式接线由 `DataLoader` 补上 `GEAR_MOD_DROP_TABLES_PATH` 并转发到 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、cache 或排序。

| 静态入口 | 输入 | 保留的兼容语义 |
|----------|------|----------------|
| `validate_package_rows()` | 包 payload 的 `drop_rows`、包 id、正式敌人索引、当前包 Mod 索引、错误 sink | 空 Array 合法；非 Array / 非 Dictionary、未知敌人 / 当前包 Mod、等级倒置继续只判包无效而不新增诊断；exact keys 与 CSV 数值 / 整数仍按旧 field / expected 顺序报告；包内重复行不在此阶段拒绝 |
| `validate_merged_rows()` | 已隔离坏包后重新读取的 `Array[Dictionary]`、最终敌人 / Mod 索引、错误 sink | 空表失败；每行按敌人→Mod→概率→最小等级→最大等级→范围→重复继续收集错误；等级解析或下限失败时跳过范围 / 重复；非空未知 id 仍参与 `source:mod:min:max` 重复检测 |

### 内部纯机关目录校验 API

`HazardCatalogValidator.validate(rows, require_locale_key, has_contract_value, report_failure)` 每次返回新的 typed `ValidationResult { is_valid, row_count }`。Locale callback 接收 `(field_path, value)`，契约 callback 接收 `(contract_key, id)`，错误 sink 接收 `(field_path, expected)`；正式接线由 `DataLoader` 补 `HAZARDS_PATH` 和 `locale_keys`，复用 `has_contract_value()` 与 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、缓存或引用索引。

- `row_count` 始终等于输入 typed rows 的原始长度；空表报告 `rows / non-empty CSV` 且计数为 `0`。每行字段从 CSV 行号 `index + 2` 开始，不做 row-level 硬返回。
- 每行严格按 id 非空→id 重复→name locale→tags 解析 / 非空 / 契约 / 重复→`tag_hazard`→pool→damage→element→trigger interval→radius→duration 的旧顺序累计错误。id 不 trim；非空 id 即使重复也仍写入当次 seen。
- tags 继续用 `String(value).split("|", false)` 解析，只对每段 strip 并丢弃空段。只有契约合法的 tag 参与 duplicate seen；合法重复使 bool 失败。为机械保留旧 helper 缺口，未登记 tag 会报错且不进 seen，但本身不拉低 validator bool；只要原始解析结果仍含 `tag_hazard` 且其他字段合法，结果可能仍为 true。该兼容缺口不是新数据依赖面，收紧必须另立 correctness 决策。
- pool / element 必须是对应契约中的非空 String。CSV 数值继续用 `String(value).is_valid_int()` / `is_valid_float()` 解析并检查 finite；damage 可为 `0`，trigger interval 必须大于 `0.0`，radius 最小为 `1`，duration 可为 `0.0`。
- 额外列、header 和 `presentation_profile_id` 不属于本 validator 边界；表现引用、引用索引的 last-write 与 radius clamp 继续由原边界处理。`DataLoader` 在 Gear Mod 掉落后 / active items 前保持 schema 校验调用，无条件写入 validator 返回的 hazards count；当前官方表计数为 `2`，指纹仍只通过 schema counts 间接观察。

### 内部纯主动道具目录校验 API

`ActiveItemCatalogValidator.validate(raw_data, require_locale_key, require_content_tag, require_effect, report_failure)` 每次返回新的 typed `ValidationResult { is_valid, item_count }`。四类 callback 分别接收 locale `(field_path, value)`、tag `(field_path, value)`、effect `(field_path, value)` 与错误 `(field_path, expected)`；tag / effect callback 返回已登记 id 或空字符串。正式接线由 `DataLoader` 补 `ACTIVE_ITEMS_PATH` 和 `locale_keys`，复用 `_require_locale_key()`、`_require_registered(..., "content_tags" / "effects")` 与 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、缓存、表现引用或引用索引。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并硬返回；DataLoader 不写 count。Dictionary root 先校验 int-like 且 `>= 1` 的 schema，再把 `active_items` 非 Array 归一为空数组，因此继续报告 `Array` 与 `non-empty Array`，并把规范化数组长度写入 result。
- 每个 item 按 shape → id 非空 / 重复 → name locale → description locale → default bool → tags → charge → use effects 的旧顺序累计。非 Dictionary item 只局部跳过；id 不 trim、也不查契约，非空重复 id 报错后仍写入 seen。额外 root / item / charge / effect / params key 与 `presentation_profile_id` 继续忽略。
- tags 必须是非空 Array，只有 callback 返回的契约合法 tag 参与 duplicate seen，合法重复使 bool 失败；原数组还必须包含 `tag_active_item`。为机械保留旧 helper 缺口，未登记 tag 会诊断且不进 seen，但本身不拉低 validator bool；若仍含合法 `tag_active_item` 且其余字段合法，结果可能为 true。收紧须另立 correctness 决策。
- charge 非 Dictionary 只使本段失败，随后 use effects 仍执行。Dictionary 内依次要求 mode 非空、非空 mode 必须为 `cooldown`、cooldown 为有限正数、max charges 为 int-like 且至少 `1`、start charges 为 int-like 且非负；只要 max / start 都是 int-like，即使各自下限失败仍继续比较 `start_charges <= max_charges`。
- use effects 非 Array 时先报告 `Array`，归一为空后再报告 `non-empty Array`。entry 非 Dictionary 只报告并继续；Dictionary entry 先要求 effect callback 返回已登记 id，再只检查 `params` 是 Dictionary，不检查 params 内容。
- `DataLoader` 保持机关 validator → 第二次机关索引读取 → 主动道具 validator → 第二次主动道具 ID 索引读取 → consumables 的原调用顺序；更早的表现引用校验提供第三次独立读取。三次 `load_json(ACTIVE_ITEMS_PATH)` 不缓存、不复用，Dictionary root 即使字段非法仍写规范化 item count。

### 内部纯消耗品目录校验 API

`ConsumableCatalogValidator.validate(raw_data, require_locale_key, require_content_tag, require_effect, report_failure)` 每次返回新的 typed `ValidationResult { is_valid, consumable_count, has_consumable_count }`。四类 callback 分别接收 locale `(field_path, value)`、tag `(field_path, value)`、effect `(field_path, value)` 与错误 `(field_path, expected)`；tag / effect callback 返回已登记 id 或空字符串。正式接线由 `DataLoader` 补 `CONSUMABLES_PATH` 和 `locale_keys`，复用 `_require_locale_key()`、`_require_registered(..., "content_tags" / "effects")` 与 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、缓存、表现引用或引用索引。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并硬返回，且不提供 count；Dictionary root 先校验 int-like 且 `>= 1` 的 schema，再把 `consumables` 非 Array 归一为空数组，因此继续报告 `Array` 与 `non-empty Array`，count 是规范化数组长度并包含非 Dictionary 元素。
- 每个 item 按 shape → id 非空 / 重复 → name locale → description locale → default bool → tags → `tag_consumable` → stack → use effects 的旧顺序累计。非 Dictionary item 只局部跳过；id 不 trim、也不查契约，非空重复 id 报错后仍写入 seen。额外 root / item / stack / effect / params key 与 `presentation_profile_id` 继续忽略。
- tags 必须是非空 Array；只有 callback 返回的契约合法 tag 参与 duplicate seen，合法重复使 bool 失败，原数组还必须包含 `tag_consumable`。未登记 tag 继续只诊断、不进 seen，也不单独拉低 validator bool；该历史缺口的收紧需要独立 correctness 决策。
- stack 非 Dictionary 只使本段失败，随后 use effects 仍执行。Dictionary 内按 `max_stack >= 1`、`start_count >= 0`、`pickup_count >= 1` 校验；只要关系两端都是 int-like，即使下限已失败仍继续按 start → pickup 顺序检查不超过 `max_stack`。
- use effects 非 Array 时先报告 `Array`，归一为空后再报告 `non-empty Array`。entry 非 Dictionary 只报告并继续；Dictionary entry 先要求 effect callback 返回已登记 id，再只检查 `params` 是 Dictionary，不检查 params 内容。
- `DataLoader` 保持 active item validator → 第二次 active item 索引读取 → consumable validator → 第二次 consumable ID 索引读取 → skills 的原调用顺序；更早的表现引用校验提供第三次独立读取。三次 `load_json(CONSUMABLES_PATH)` 不缓存、不复用，只有 validator 提供 count 时才写 schema count。

### 内部纯元素目录校验 API

`ElementCatalogValidator.validate(raw_data, require_locale_key, require_element_id, list_registered_element_ids, report_failure)` 每次返回新的 typed `ValidationResult { is_valid, element_count, combination_count }`。Locale callback 接收 `(field_path, value)` 并返回 bool；element id callback 接收相同参数并返回已登记 id 或空字符串；登记列表 callback 无参数并返回当前 `elements` 契约值；错误 sink 接收 `(field_path, expected)`。正式接线由 `DataLoader` 补 `ELEMENTS_PATH` 和 `locale_keys`，复用 `_require_locale_key()`、`_require_registered(..., "elements")`、`contract_values("elements")` 与 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、缓存或引用索引。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并硬返回；DataLoader 不写两个 count。Dictionary root 按 schema → neutral id → unmatched result → elements → 已登记定义覆盖 → combinations 的旧顺序校验；额外 root / element / combination key 继续忽略。
- `schema_version` 精确为 int-like `1`，`1.0` 继续合法；`neutral_element_id` callback 返回空字符串时使总 bool 失败，`unmatched_result` 只要求 String。`elements` 与 `combinations` 非 Array 时各自报告 `Array` 并归一为空数组，但该 helper 诊断本身不改变 aggregate bool；两个 count 分别取规范化数组长度并包含非 Dictionary 项。
- 每个 element 按 shape → id → name locale → kind → components 的旧 source order 校验。Element id callback 对空 / 未登记值只诊断、不进 seen、也不单独拉低 bool；合法 id 重复才报告 `unique element id` 并失败。Kind 只允许 `neutral / primary / composite`。
- components 非 Array 只诊断并归一为空；每个 component 按源顺序走 element id callback，空 / 未登记值只诊断、不进 seen、不单独拉低 bool，只有合法重复才报告 `unique id` 并失败。空 components 合法。
- 完成全部 element 遍历后才调用登记列表 callback，按当前契约顺序报告缺失 `definition for <id>`；该时点保留 DataLoader 旧 `contract_values("elements")` 的 Mod-aware 行为，不提前缓存。
- 每个 combination 按 shape → left → right → result → 无序 pair 重复的旧顺序校验。Left / right callback 返回空字符串时只留下诊断，不直接拉低 bool；result 返回空字符串时失败。Pair 继续对 `[left, right]` 原地排序、以 `|` 连接并进入 seen，因此第二个相同无序 pair 会失败，包含 callback 空结果的 pair 也保持旧 duplicate 行为。
- `DataLoader` 保持 presentation references → elements validator → hero passives validator → 第二次 hero passive 引用读取 → weapons 的原调用位置。`elements.json` 只在本校验点单次经既有 Mod overlay 读取；Dictionary root 即使字段非法仍按 elements → element combinations 顺序写入两个规范化 count。

### 内部纯英雄被动目录校验 API

`HeroPassiveCatalogValidator.validate(raw_data, require_locale_key, require_passive_id, require_effect, require_element, report_failure)` 每次返回新的 typed `ValidationResult { is_valid, passive_count }`。Locale callback 接收 `(field_path, value)` 并返回 bool；passive id / effect / element callback 接收相同参数并返回已登记 id 或空字符串；错误 sink 接收 `(field_path, expected)`。正式接线由 `DataLoader` 补 `HERO_PASSIVES_PATH` 和 `locale_keys`，复用 `_require_locale_key()`、`_require_registered()` 与 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、缓存或引用索引。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并硬返回；DataLoader 不写 count。Dictionary root 先要求 `schema_version` 精确为 int-like `1`，`1.0` 继续合法；额外 root / passive / params key 均忽略。
- `passives` 非 Array 时 callback 报告 `Array` 并归一为空数组，但机械保留旧 helper 没有把该诊断并入 aggregate bool 的缺口；空 Array 合法。`passive_count` 始终等于规范化数组长度并包含非 Dictionary 元素。
- 每项按 shape → passive id → name locale → description locale → effect → params → element → multiplier 的旧 source order 校验。非 Dictionary item 使 bool 失败并继续下一项；locale callback 返回 false 不短路后续字段。
- passive id callback 对空或未登记值返回空字符串时只留下既有诊断，不单独拉低 bool，也不进入 seen；只有 callback 返回的合法非空 id 重复时才报告 `unique passive id` 并使 bool 失败。该 under-validation 只做等价提取，收紧必须另立 correctness 决策。
- effect callback 返回空字符串时使 bool 失败，但仍继续检查 params；params 非 Dictionary 使当前项失败并跳过当前项的 element / multiplier，下一项继续。Element callback 返回空字符串时使 bool 失败但不跳过 multiplier；multiplier 必须是有限 number 且位于闭区间 `0.0..1.0`。
- `DataLoader` 保持 elements → hero passive validator → 第二次 hero passive ID 索引读取 → weapons 的原调用顺序。两次 `load_json(HERO_PASSIVES_PATH)` 均经过既有 Mod overlay，互不缓存或复用；仅 Dictionary root 写入规范化 `hero_passives` count。

### 内部纯敌人金币模型校验 API

`EnemyRewardModelValidator.validate(raw_data, report_failure)` 的错误 sink 只接收 `(field_path, expected)`。正式接线由 `DataLoader` 补 `ENEMY_REWARDS_PATH` 并转发到 `_schema_fail()`；validator 不访问 autoload、文件、`user://` 或缓存。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并立即返回；Dictionary root 先按 `schema_version` → `base_coefficient` → `time_growth_per_tier` → `random_multiplier_min` → `random_multiplier_max` 报缺字段，再按原 Dictionary 插入序报告额外字段。
- exact-key 后继续按 schema → 基础系数 → 阶段增长 → 随机下界 → 随机上界 → 区间关系收集错误；空 Dictionary 因此同时报告 required-field 与标量类型错误。
- `schema_version` 的整数值浮点继续视为 int-like。四个数值字段先要求 number / finite；基础系数和随机上下界必须大于 `0.0`，阶段增长必须大于等于 `0.0`。
- 只要随机上下界原值均为 `int` / `float`，即使有限性或正数校验已经失败，也继续比较 `random_multiplier_min <= random_multiplier_max`。
- `DataLoader` 保留 `load_json(ENEMY_REWARDS_PATH)` 和 profile count：root 非 Dictionary 不写计数；Dictionary root 在 validator 返回后仍写 `enemy_reward_models = 1`，不以字段是否合法为条件。

### 内部纯等级曲线校验 API

`LevelProgressionValidator.validate(raw_data, report_failure)` 的错误 sink 只接收 `(field_path, expected)`。正式接线由 `DataLoader` 补 `LEVEL_PROGRESSION_PATH` 并转发到 `_schema_fail()`；validator 不访问 autoload、文件、`user://` 或缓存。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并立即返回；额外 root key 继续允许。
- Dictionary root 按 `schema_version` → `first_level_cost` → `multiplier_numerator` → `multiplier_denominator` → 分子大于分母关系的旧顺序收集错误。
- 整数值浮点继续视为 int-like。只要分子 / 分母都是 int-like，即使正数下限校验失败也继续检查大小关系；任一操作数非 int-like 时跳过关系错误。
- `DataLoader` 保留 `load_json(LEVEL_PROGRESSION_PATH)` 和 profile count：root 非 Dictionary 不写计数；Dictionary root 在 validator 返回后仍写 `level_progression_profiles = 1`，不以字段是否合法为条件。

### 内部纯通用奖励选择池校验 API

`RewardChoicePoolValidator.validate(raw_data, require_locale_key, validate_modifiers, report_failure)` 返回 typed `ValidationResult { is_valid, pool_count }`。三个 callback 都只接收不带资源路径的字段参数；正式接线由 `DataLoader` 复用 Mod-aware locale helper、stat 契约 / 数值 helper 与 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、契约表、缓存或 schema count。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并立即返回；Dictionary root 允许额外字段，按 schema → pools → pool source-order 校验。`schema_version` 精确为 int-like `1`，因此 GDScript 中 `1.0` 保留旧接受语义。
- `pool_count` 始终取 `_require_array()` 规范化后的 pools 长度；DataLoader 仅在原 root 为 Dictionary 时写入。pool / entry 非 Dictionary 时报告 shape 并继续下一项；空 pools、空 entries 均保留合法。
- 每个 pool 按 id → pool 内 entries 顺序校验；每个 entry 按 id → name locale → desc locale → 重复 id → kind 非空 / `stat_modifier` → 正 weight → 可选正 `min_level` → modifiers 的旧顺序收集错误。合法 String pool / entry id 的重复范围分别是全文件与当前 pool。
- 兼容性上保留旧非 fail-closed 缺口：pools / entries / modifiers 非 Array 时 `_require_array()` 仍会报告，但 pools / entries 路径不会单独把结果置为 false，modifier 路径以 DataLoader 旧 `_validate_modifiers()` 返回值为准；modifier 缺失 / 未登记 stat 会由旧 stat helper 报错，但在 type / value 其余条件有效时 callback 仍可能返回 true并使整体 bool 保持成功。该行为只做等价提取，不代表新 schema 应依赖它；后续若要收紧必须独立决策与迁移。
- `DataLoader` 保留首次 `load_json()`、资源路径包装、locale / modifier adapters、仅 Dictionary root 写 count，以及等级曲线后 / 难度 profile 前的调用位置；validator 不缓存、排序或改变 Mod overlay。

### 内部纯难度 Profile 校验 API

`DifficultyProfileValidator.validate(raw_data, require_locale_key, report_failure)` 返回 typed `ValidationResult { is_valid, profile_count }`。Locale callback 和错误 sink 都只接收不带资源路径的字段参数；正式接线由 `DataLoader` 复用 Mod-aware `_require_locale_key()`，并补 `DIFFICULTY_PROFILES_PATH` 后转发到 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、缓存或引用索引。

- root 非 `Dictionary` 时只报告 `root / Dictionary` 并立即返回，`profile_count` 保持 `0`；Dictionary root 按 required keys → extra keys → schema → profiles shape / non-empty 的旧 source-order 收集错误，计数始终取 `_require_array()` 规范化后的数组长度。
- 每个 profile 先按固定 8 字段的 required keys 和原 Dictionary 插入序 extra keys 校验，再按 `id` → 重复 id → `name_key` → `difficulty_coefficient` → `tier_interval_seconds` → 三个增长字段 → `stage_name_keys` 长度 → 各 locale key / 重复的顺序继续收集错误；非 Dictionary profile 只报 shape 并继续下一项。
- profile id 与 stage locale key 的重复索引保留既有 `String(...)` 取值路径；单测只对 loader 可达的合法 String 输入锁定重复诊断与顺序，不把测试字面量的跨类型转换声明为公开兼容契约。
- schema version 继续接受整数值浮点；难度系数与阶段间隔必须是有限正数，间隔上限 `3600.0`，三个增长字段必须是有限 `0.0..10.0`，阶段文案必须恰好 9 项且逐项通过 DataLoader 持有的 locale 校验。
- `DataLoader` 保留首次 `load_json()`、资源路径包装、locale adapter、仅 Dictionary root 写 count，以及 validator 返回后第二次 `load_json()` 再交给引用 builder 的旧调用位置；校验失败不改变后续引用索引和 game mode 校验的既有执行顺序。

### 内部纯刷怪波次目录校验 API

`SpawnWaveCatalogValidator.validate(rows, enemy_ids, hazard_ids, game_mode_ids, require_mode_id, report_failure)` 每次返回新的 typed `ValidationResult { is_valid, row_count }`。Mode callback 接收 `(field_path, value)` 并返回已登记 id 或空字符串，错误 sink 接收 `(field_path, expected)`；正式接线由 `DataLoader` 补 `SPAWN_WAVES_PATH`，复用 `_require_registered(..., "game_modes")` 与 `_schema_fail()`。Validator 不访问 autoload、文件、`user://`、Mod、缓存或引用 builder。

- `row_count` 始终等于输入 typed rows 的原始长度；空表报告 `rows / non-empty CSV` 且返回 `0`。每行按 CSV 源顺序使用 `line <index + 2>`，额外列继续忽略。
- 每行严格按 id 非空→id 重复→mode 契约→mode 真实定义→wave index / mode 内重复→start→end→时间关系→enemy 非空 / 引用→enemy weight→spawn interval→max alive→budget→hazard weight→hazard 引用→空 hazard / 正权重关系的旧诊断顺序继续执行，中间错误不短路后续字段。
- id 和所有 CSV 数值继续使用原 `String(value).is_valid_int()` / `is_valid_float()` 解析；因此整数列的 `"1.0"` 继续非法。Start 非负，end 为正数且必须大于 start；整数和浮点边界 / finite 错误文本保持。
- 为机械保留旧 `_require_registered()` 接线缺口，空 / 未登记 mode id 会诊断并返回空值，但不单独拉低 aggregate bool；只有 callback 返回合法契约 id 后又不在当前 `game_mode_ids` 索引时才失败。该缺口不是新数据依赖面，收紧须独立 correctness 决策。
- `DataLoader` 保留 game mode 校验→content unlock→game mode IDs 二读→map layouts→wave validator→wave rows 二读建索引→map layout IDs 二读→warzone director 的调用顺序。两次 `load_csv(SPAWN_WAVES_PATH)` 都独立经 Mod overlay，不缓存、不复用首次 rows；schema count 使用 validator 返回的 raw row count。

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `data_reloaded` | 无 | `reload_contracts()` 成功刷新 `_contracts` 后 |

## 数据与契约

- 读取 `res://data/_contracts.json`，并在运行时叠加 `ModLoader.contract_extensions()` 返回的允许动态扩展 id。
- `_contracts.json` 由 `tools/sync_contracts.py` 生成，禁止手改。
- 玩家 mod 不得修改 `_contracts.json` 或生成常量；manifest v2 只允许声明 `gear_mod_ids` 与 `locale_prefixes`，且 Gear Mod / locale key 必须使用 `mod_<package_id>_` 命名空间。
- 当前 F3 schema 覆盖：
  - `player.json`：schema v4 新增 `body`，且 GDScript validator 要求 `body` 必须且只能含正数 `radius`；其余根级配置继续包含 `base_stats`、`defense`、`dash`、`energy_drop` 与 `gold_drop`。非空 `base_stats` 的 stat id 必须来自词表，数值范围按 stat 类型校验；`max_hp` 是正数浮点血量，`health_regen` 是非负 HP/s，两个掉落的 `pickup_speed` 必须为正数。遗留 `pickup_orb_speed` 会被明确拒绝，`luck` 保留为暂未生效属性。等价提取继续保留 GDScript 边界不校验 root exact / defense / dash、energy 其余字段以及 base stats 错误硬返回的旧语义；Python schema 仍可提供更严格的全项目门禁。
  - `characters.json`：schema v4 角色 id、专属 `scene_path`、表现 profile、名称 / 描述 key、可选图鉴图标、默认解锁 / 解锁规则、tags、capabilities、控制配置、起始携带引用和角色基础属性；字段缺失等同默认开放。每个 `palette` 必须且只能含一个合法 HTML 颜色 `primary`，遗留 `secondary` / `accent` 或任何额外键均拒绝。场景必须是正式 `actors/characters/*.tscn` 下存在的 `PackedScene`，不得指向基础场景或越界。不同角色 id 可以复用同一路径；起始武器、主动道具和消耗品引用必须存在于对应数据文件。
    - 纯 validator 保持 schema→character source order、scene→locale→tags / capabilities→element / passive / hero skills→palette→loadout→skill resources→base stats；DataLoader 保留表现引用→schema→引用索引三次独立 Mod-aware 读取、actor `PackedScene` 加载、locale / contract / stat adapters、五类既有索引与 Dictionary-root raw count。角色 / tag / capability / passive / skill-resource contract 返回空时部分只诊断不降低 aggregate bool，以及 capabilities / loadout consumables / skill resources 非 Array 只诊断的旧兼容缺口，均不得在无独立 correctness 决策时顺手收紧。
  - `weapons.json`：schema v5；武器 id、表现 profile、名称 / 描述 key、默认解锁、开火模式、开火音频 id、武器基础属性、子弹对象池、伤害类型与弹体数值。单武器执行 exact-key 校验，任何遗留 `ammo` 或额外字段都会拒绝；根级继续保留旧兼容面。纯 validator 保持 schema→recoil model→weapons、required stat 后 raw stat source-order、recoil / spread cap 与 projectile pool→element→三数值顺序；DataLoader 保留表现引用、校验与引用索引三次独立 Mod-aware 读取、共享 stat 分类、callback adapters 和 Dictionary-root count。
  - `skills.json`：schema v3；技能 id、表现 profile、名称 / 描述 key、`tag_skill`、ability tags、activation required / blocked / granted tags、冷却、能量消耗、目标类型、能力缩放和 `programs[]`。技能首版只允许 `skill_activated` trigger；程序 id 唯一，conditions/actions 必须来自生成契约，概率 / 内部冷却合法；状态、元素、stack rule、ability tag 与 pool 引用继续 fail-fast。
  - `visual_effects.json`：schema v3、唯一 effect id、固定枚举、合法正式资源、预览参数和对象池引用；旧 schema v1/v2 与遗留 `reduced_motion` / `quality_variants` 字段明确拒绝，高频条目必须声明已登记 pool id，catalog 不得指向 editor-only、`output/test_lab` 或裸程序几何。
  - `presentation_profiles.json`：唯一 profile id、父继承无环、cue / anchor 枚举、效果引用与可选音频 / 相机 / 屏幕绑定；首版 `hit_stop_profile_id` 必须为空。
  - `enemy_ai_profiles.json`：schema v5 profile id、视线 / 路径 / 记忆感知、决策间隔、玩家权重、通用移动参数、动作参数和 action id；远程攻击额外必填 `windup/burst_count/shot_interval`。攻击 action 必须携带与类型严格匹配的 `attack` 字典，非攻击 action 禁止携带 `attack`；旧 schema 与遗留攻击字段明确拒绝。纯 validator 保持 profile / 字段 / action source-order、局部 Dictionary 短路、exact-key required 后 raw extra-key 顺序，以及未登记非攻击 action 仅由 callback 诊断而不单独降低 aggregate bool 的历史缺口；DataLoader 仍在 weapons 索引后单次读取并仅对 Dictionary root 写规范化 profile count，随后第二次独立读取构建 enemy AI profile 索引。
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
  - `elements.json`：schema v1；已登记中性 / 基础 / 复合元素 id、名称 locale key、kind、已登记 components、全部契约定义覆盖，以及唯一无序组合的 left / right / result。GDScript 等价边界继续保留 elements / components / combinations 非 Array 与空 / 未登记 element id 的历史 aggregate-bool 缺口。
  - `hero_passives.json`：schema v1；唯一已登记 passive id、名称 / 描述 locale key、已登记通用 effect，以及 Dictionary params 内已登记 element id 与有限 `0.0..1.0` multiplier。GDScript 等价边界继续保留 passives 非 Array、空 / 未登记 id 的历史 aggregate-bool 缺口。
  - `credits.json`：致谢分组、分组标题 locale key、工作人员条目、外部资源 / 库 / 工具条目的 URL、license、是否随构建分发、是否需要 notice 与复核状态。
  - `level_progression.json`：schema v1，`first_level_cost`、`multiplier_numerator`、`multiplier_denominator` 都必须为正整数，且分子必须大于分母；JSON integral float 继续按旧 DataLoader 语义视为整数，额外 root key 不在本层拒绝。运行时用整数有理数逐段向上取整，当前 100 与 13/10 的前十段和累计阈值由 schema tests 固定验证。
  - `reward_choice_pools.json`：schema v1，候选池、唯一条目 id、`stat_modifier` 类型、正权重、正 `min_level`、名称 / 描述 locale key 与属性修正；池和条目引用必须有效。
  - `game_modes.json`：schema v3，模式 id、名称 / 描述 key、默认解锁、participants / teams、角色池、武器池、技能池、敌人池、机关池、主动道具池、消耗品池、content tag blocklist 与玩家基础属性轻量覆盖；各池 id 必须引用对应数据。Gear Mod 不属于模式资源池，遗留 `resource_pools.relics` / `growth_pools` 会被明确拒绝。
  - `strings.csv`：key 前缀、`zh_CN` / `en` 必填、唯一 key。
- 导出版中 `client/data/*.csv` 必须作为原始 CSV 随包分发，DataLoader 依赖 `FileAccess` 读取原文件；`client/locale/strings.csv` 继续由 Godot 作为 `csv_translation` 导入，导出版缺少原始 `strings.csv` 时不枚举 optimized translation 全量 key，只在数据引用 locale key 时用当前翻译资源按需校验。
- 当前也校验模块世界 / 注册表 / 独立模块 JSON；运行时解释见 `docs/代码/module_world_manager.md`。技能、状态、地图、机关、EnemyAI、战区导演和 Gear Mod 仍分别以各自模块文档为权威。

## 依赖

- 上游依赖：生成契约文件、`ModLoader`，以及仅由 `DataSourceReader` / CSV header 校验边界直接使用的 Godot `FileAccess` / `JSON`。
- 内部纯依赖：`DataSourceReader` 只依赖 Godot 物理文件 / 解析 API；`DataReferenceIndexBuilder`、`PlayerDataValidator`、`CameraFeedbackValidator`、`ElementCatalogValidator`、`SpawnWaveCatalogValidator`、`HeroPassiveCatalogValidator`、`CreditsValidator`、`GearModDropTableValidator`、`HazardCatalogValidator`、`ActiveItemCatalogValidator`、`ConsumableCatalogValidator`、`EnemyRewardModelValidator`、`LevelProgressionValidator`、`RewardChoicePoolValidator`、`DifficultyProfileValidator` 与 `DataFingerprintBuilder` 只接收已加载的 `Variant` / `Array[Dictionary]` 和显式索引 / callback。所有边界都不得反向读取 `DataLoader` 或 `ModLoader`；除 Reader 自身外不得读物理数据源。`PlayerDataValidator` 只额外静态引用生成的 `PoolIds.GOLD_ORB`，不查询契约运行时状态。
- 下游调用方：后续所有读取 `client/data/` 的业务模块。
- 禁止依赖：不得直接引用具体玩法系统，避免数据层反向依赖业务层。

## 扩展点

- 新数据格式优先通过新解析函数接入，再由业务模块做 schema 校验。
- 新官方 JSON / CSV 物理读取行为应先收口到 `DataSourceReader`，再由 `DataLoader` 公开门面做错误输出和 Mod overlay；不得在 Reader 中加缓存、autoload 查询或 schema 逻辑。
- 新约定字符串必须先改 `docs/词表与契约.md` 并跑契约同步，不在 DataLoader 内硬编码白名单。
- 热重载可复用 `data_reloaded` 信号扩展。
- 本地 mod 只能通过 `ModLoader` manifest v2 给 Gear Mod 定义、奖励池贡献、掉落和 locale 做声明式 append；不得让业务系统绕过 `DataLoader` 直接读取 `user://mods`。
- 新跨文件引用索引应在 `DataReferenceIndexBuilder` 新增纯静态入口，由 `DataLoader` 在原校验 / 读取时序中显式传入合并后的数据；不得让 builder 自行读文件、扫描 Mod、缓存或排序。
- 新玩家 body / base stat / 掉落结构规则应在 `PlayerDataValidator` 中保持纯静态校验，由 `DataLoader` 继续控制文件读取、stat / pool adapters、资源路径、locale 后 / camera 前的调用位置与 count；不得在 validator 中加载 JSON、查询 Mod / autoload 或写 `_last_schema_counts`。现有 base stats 硬返回、energy under-validation 与金币池双诊断不得在无独立迁移决策时顺手收紧。
- 新相机反馈字段或范围规则应在 `CameraFeedbackValidator` 中保持纯静态校验，由 `DataLoader` 继续控制首次校验读取、第二次索引读取、资源路径、调用位置与计数；不得在 validator 中加载 JSON、收集 profile id 或写 `_last_schema_counts`。
- 新致谢字段或规则应在 `CreditsValidator` 中保持纯静态校验，由 `DataLoader` 继续控制文件读取、Mod-aware locale callback、资源路径、调用位置与计数；不得在 validator 中加载 JSON、查询 Mod / locale 或写 `_last_schema_counts`。
- 新 Gear Mod 掉落字段或规则应在 `GearModDropTableValidator` 的包内与合并入口分别落地，并由 `DataLoader` 保持“先隔离、再重读、再计数 / 校验”；不得在 validator 中读文件、禁用包或缓存合并 rows。
- 新机关字段或 CSV 规则应在 `HazardCatalogValidator` 中保持纯静态校验，由 `DataLoader` 继续控制三次独立读取、Mod-aware locale / 契约 callback、资源路径、Gear Mod 掉落后 / active items 前的位置与 count；不得在 validator 中加载 CSV、查询 Mod / autoload、构建引用索引、校验表现 profile 或写 `_last_schema_counts`。未登记 tag 只诊断不改 bool 的旧缺口不得在无独立 correctness 决策时顺手收紧。
- 新主动道具字段或 JSON 规则应在 `ActiveItemCatalogValidator` 中保持纯静态校验，由 `DataLoader` 继续控制三次独立读取、Mod-aware locale / tag / effect callback、资源路径、机关索引后 / consumables 前的位置与 count；不得在 validator 中加载 JSON、查询 Mod / autoload、构建引用索引、校验表现 profile 或写 `_last_schema_counts`。未登记 tag 只诊断不改 bool 的旧缺口不得在无独立 correctness 决策时顺手收紧。
- 新消耗品字段或 JSON 规则应在 `ConsumableCatalogValidator` 中保持纯静态校验，由 `DataLoader` 继续控制三次独立读取、Mod-aware locale / tag / effect callback、资源路径、主动道具索引后 / skills 前的位置与 count；不得在 validator 中加载 JSON、查询 Mod / autoload、构建引用索引、校验表现 profile 或写 `_last_schema_counts`。未登记 tag 只诊断不改 bool 的旧缺口不得在无独立 correctness 决策时顺手收紧。
- 新元素字段、组件或组合规则应在 `ElementCatalogValidator` 中保持纯静态校验，由 `DataLoader` 继续控制单次 Mod-aware 读取、locale / element contract / 登记列表 callback、资源路径、表现引用后 / hero passives 前的位置与两个 count；不得在 validator 中加载 JSON、查询 Mod / autoload、缓存登记列表、构建引用索引或写 `_last_schema_counts`。elements / components / combinations Array helper 与空 / 未登记 id 只诊断不改 aggregate bool 的旧缺口不得在无独立 correctness 决策时顺手收紧。
- 新刷怪波次字段或 CSV 规则应在 `SpawnWaveCatalogValidator` 中保持纯静态校验，由 `DataLoader` 继续控制两次独立 Mod-aware 读取、mode 契约 callback、enemy / hazard / game mode 索引、资源路径、map layouts 后 / warzone director 前的位置与 raw count；不得在 validator 中加载 CSV、查询 Mod / autoload、构建 wave index 或写 `_last_schema_counts`。未登记 mode 只诊断不改 aggregate bool 的旧缺口不得在无独立 correctness 决策时顺手收紧。
- 新英雄被动字段或 JSON 规则应在 `HeroPassiveCatalogValidator` 中保持纯静态校验，由 `DataLoader` 继续控制两次独立读取、Mod-aware locale / passive id / effect / element callback、资源路径、elements 后 / weapons 前的位置与 count；不得在 validator 中加载 JSON、查询 Mod / autoload、构建引用索引或写 `_last_schema_counts`。passives 非 Array 与空 / 未登记 passive id 只诊断不改 aggregate bool 的旧缺口不得在无独立 correctness 决策时顺手收紧。
- 新角色、palette、起始 loadout、技能资源或 base stat 规则应在 `CharacterCatalogValidator` 中保持纯静态校验，由 `DataLoader` 继续控制表现引用 / schema / 引用索引三次独立读取、locale / contract / actor-scene / stat callback、五类既有索引、资源路径、Credits 后 / LevelProgression 前的调用位置与 Dictionary-root count；不得在 validator 中加载 JSON / PackedScene、查询 Mod / autoload、构建引用索引或写 `_last_schema_counts`。contract 与 Array helper 的历史 aggregate-bool 缺口不得在无独立 correctness 决策时顺手收紧。
- 新武器、recoil、base stat 或 projectile 字段规则应在 `WeaponCatalogValidator` 中保持纯静态校验，由 `DataLoader` 继续控制表现引用 / schema / 引用索引三次独立读取、Mod-aware locale / audio / stat / contract callback、共享 weapon stat 分类、资源路径、hero passives 后 / EnemyAI profiles 前的位置与 count；不得在 validator 中加载 JSON、查询 Mod / autoload、复制通用 stat 分类、校验 presentation profile、构建引用索引或写 `_last_schema_counts`。根级 extra-key 与 `presentation_profile_id` 值只由其他既有边界检查的兼容面不得顺手收紧。
- 新敌人金币模型字段或关系规则应在 `EnemyRewardModelValidator` 中保持纯静态校验，由 `DataLoader` 继续控制文件路径、调用位置与计数；不得在 validator 中加载 JSON 或写 `_last_schema_counts`。
- 新等级曲线字段或关系规则应在 `LevelProgressionValidator` 中保持纯静态校验，由 `DataLoader` 继续控制文件路径、调用位置与计数；不得在 validator 中加载 JSON 或写 `_last_schema_counts`。
- 新通用奖励选择池结构规则应在 `RewardChoicePoolValidator` 中保持纯静态校验，由 `DataLoader` 继续控制文件读取、Mod-aware locale / modifier callback、资源路径、调用位置与计数；不得在 validator 中加载 JSON、查询 Mod / locale / stat 契约或写 `_last_schema_counts`。历史 bool 缺口不得在无独立迁移决策时顺手收紧。
- 新难度 profile 字段或规则应在 `DifficultyProfileValidator` 中保持纯静态校验，由 `DataLoader` 继续控制文件读取、Mod-aware locale callback、资源路径、调用位置、第二次引用索引读取与计数；不得在 validator 中加载 JSON、查询 Mod / locale、构建引用索引或写 `_last_schema_counts`。
- 新增玩法指纹字段时在 `DataFingerprintBuilder` 明确加入归一化规则；不得直接哈希整份展示数据，也不得在 builder 内自行重新加载文件或扫描 Mod。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 加 JSON 数据 schema | `data_loader.gd` + `tools/validate_data.py` | `client/data/README.md`、对应模块文档 | `tools/validate_data.py`、headless boot |
| 改官方 JSON / CSV 物理读取或 DataLoader 公开接线 | `data_source_reader.gd`、`data_loader.gd`、目标 GUT | 本文档 | Reader unit + full GUT + `validate_data` + schema test + `mod-loader-smoke` + L1/runtime/replay smoke + headless boot + Replay regression |
| 改玩家配置校验 / DataLoader 接线 | `player_data_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 | 目标 / full GUT + contracts + `validate_data` + schema test + L1/runtime/actor/save/loading + headless boot + Replay regression |
| 改角色目录校验 / DataLoader 接线 | `character_catalog_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / Character 文档 | 目标 / full GUT + contracts + `validate_data` + schema test + ModLoader/L1/actor/runtime/save/loading/codex/headless + Replay regression |
| 改武器目录校验 / DataLoader 接线 | `weapon_catalog_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / Weapon 文档 | 目标 / full GUT + contracts + `validate_data` + schema test + ModLoader/L1/Gear Mod/runtime/save/settings/module-world/replay/headless + Replay regression |
| 改视觉效果 / profile schema | `data_loader.gd`、`validate_data.py`、catalog / profiles | `visual_effects.md`、数据手册、词表 | `sync_contracts --check` + `validate_data` + `vfx-smoke` |
| 改相机反馈校验 / DataLoader 接线 | `camera_feedback_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / Gameplay Runtime 文档 | 目标 GUT + `validate_data` + schema test + `vfx-smoke` + `runtime-smoke` + headless boot + Replay regression |
| 改致谢校验 / DataLoader 接线 | `credits_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 | 目标 GUT + `validate_data` + schema test + `mod-loader-smoke` + headless boot + Replay regression |
| 改技能 schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/skill_system.md`、必要时 `docs/代码/status_effect_component.md` | `validate_data` + schema test + `l1-smoke` / `runtime-smoke` |
| 加 CSV 表读取 | `data_loader.gd` | `client/data/README.md` | `load_csv()` smoke / 数据校验 |
| 改敌人 AI profile schema / DataLoader 接线 | `enemy_ai_profile_validator.gd`、`data_loader.gd`、目标 GUT、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | 本文档；字段语义变化时追加 `client/data/README.md`、`docs/代码/enemy_ai.md` | 目标 / full GUT + contracts + `validate_data` + schema test + L1/runtime/actor/save + headless boot + Replay regression |
| 改敌人金币 / 难度 profile schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py`、`enemy_rewards.json`、`enemies.csv`、`difficulty_profiles.json` | `client/data/README.md`、`docs/代码/enemy_reward_resolver.md`、Difficulty / Runtime / Save 文档 | contracts + `validate_data` + schema test + L1/runtime/save/replay |
| 改内容解锁 schema / 可选字段 | `data_loader.gd`、`validate_data.py`、schema tests、三类内容数据与 `content_unlock_rules.json` | 数据手册、词表、ContentUnlockSystem / Runtime / Save / Replay 文档 | contracts + data/schema + content-progression/codex/runtime/save/replay |
| 改 Gear Mod 掉落校验 / 坏包隔离接线 | `gear_mod_drop_table_validator.gd`、`data_loader.gd`、schema tests、`mod_loader_v2_smoke.gd` | 本文档、必要时数据手册 / ModLoader 文档 | 目标 GUT + `validate_data` + schema test + `mod-loader-smoke` + headless boot |
| 改机关目录校验 / DataLoader 接线 | `hazard_catalog_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / Hazard 文档 | 目标 GUT + contracts + `validate_data` + schema test + `mod-loader-smoke` + headless boot + Replay regression |
| 改主动道具目录校验 / DataLoader 接线 | `active_item_catalog_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 | 目标 GUT + contracts + `validate_data` + schema test + `mod-loader-smoke` + headless boot + Replay regression |
| 改消耗品目录校验 / DataLoader 接线 | `consumable_catalog_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 | 目标 GUT + contracts + `validate_data` + schema test + `mod-loader-smoke` + headless boot + Replay regression |
| 改元素目录校验 / DataLoader 接线 | `element_catalog_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / SkillSystem 文档 | 目标 / full GUT + contracts + `validate_data` + schema test + `mod-loader-smoke` + L1/loading/codex/runtime/replay + headless boot + Replay regression |
| 改刷怪波次目录校验 / DataLoader 接线 | `spawn_wave_catalog_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / Spawner 文档 | 目标 / full GUT + contracts + `validate_data` + schema test + `mod-loader-smoke` + L1/replay + headless boot + Replay regression |
| 改英雄被动目录校验 / DataLoader 接线 | `hero_passive_catalog_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 | 目标 GUT + contracts + `validate_data` + schema test + headless boot + Replay regression |
| 改敌人金币模型校验 / DataLoader 接线 | `enemy_reward_model_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / EnemyRewardResolver 文档 | 目标 GUT + `validate_data` + schema test + L1 + `mod-loader-smoke` + headless boot + Replay regression |
| 改等级曲线校验 / DataLoader 接线 | `level_progression_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 | 目标 GUT + `validate_data` + schema test + headless boot |
| 改通用奖励选择池校验 / DataLoader 接线 | `reward_choice_pool_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / RewardChoice 文档 | 目标 GUT + `validate_data` + schema test + headless boot + Replay regression |
| 改难度 profile 校验 / DataLoader 接线 | `difficulty_profile_validator.gd`、`data_loader.gd`、目标 GUT、schema tests | 本文档；字段语义变化时追加数据手册 / Difficulty 文档 | 目标 GUT + `validate_data` + schema test + headless boot + Replay regression |
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
| JSON / CSV 读取失败但没有原路径诊断 | 确认 `DataSourceReader` result 返回的 `failure_field` / `failure_expected` 非空，且 `DataLoader.load_json()` / `load_csv()` 仍将原 `resource_path` 与元数据转发给 `_fail()` |
| 官方文件已更改但读到旧值 | Reader 不应保持缓存；确认调用方每次都通过 `DataLoader.load_json()` / `load_csv()` 重读，并排查 Mod overlay 是否有效覆盖了官方值 |
| `data_schema_ok=false` | headless boot 日志前后的 `[DataLoader]` fail-fast 错误 |
| 坏 Mod 的掉落行仍在最终合并表 | 确认 `validate_project_data()` 没有在包隔离前缓存 rows，且隔离后重读了 Gear Mod ids 与 `gear_mod_drop_tables.csv`；`schema_counts().gear_mod_drop_rows` 应只计最终合并行 |
| 导出版打开后像空场景 / 空界面 | 用 console 导出版检查 `data_schema_ok` 与 CSV 计数；若 `enemies`、`hazards`、`spawn_waves` 等为 0，确认 `client/data/*.csv.import` 是 `importer="keep"`，且 `export_presets.cfg` 的 `include_filter` 包含 `*.csv` |
| mod 内容没进数据 | `DataLoader.mod_diagnostics()` 与 `[ModLoader]` warning；确认 manifest `target` / `path` / `array_key` |

## 测试义务

- 必跑 `tools/godot_bridge.py --project client headless-boot`。
- 改 mod 接口或 `contract_values()` 合并逻辑时跑 `tools/godot_bridge.py --project client l1-smoke`。
- 改契约 / 数据时跑 `tools/sync_contracts.py --check` 与 `tools/validate_data.py`。
- F3 schema 变更需跑 `tools/test_data_loader_schema.py`，覆盖黄金样例、未登记 id、缺失 locale key、类型 / 范围错误、跨文件引用错误和 fail-fast 输出格式。
- `DataSourceReader` 或 `DataLoader.load_json()` / `load_csv()` 接线变更需跑 unit + adapter integration GUT：unit 覆盖 JSON Dictionary / Array / scalar、`null` 的旧失败语义、CSV 有无 header、短行补空 / 长行截断 / 空白行 / 空文件、文件打开失败 field / expected 与无缓存；adapter 覆盖 `_fail()` 转发、失败不 overlay、成功后 overlay、contracts 例外与重读。非法 JSON 文本仍会由 Godot 输出 parse error 并被标准 fatal gate 可见；本 unit 只直接锁定 JSON `null`，不在同进程内 suppress 该引擎错误，也不声称现有 schema fixture 已单独覆盖 malformed 输入。再跑 full GUT、Python schema、`mod-loader-smoke`、L1 / runtime / replay smoke、headless boot 与 Replay regression，确认 `DataLoader` 仍在成功后才应用 Mod overlay，`_contracts.json` 仍禁止覆盖，原错误文本 / 读取顺序 / 每次重读 / data hash / Replay v9 摘要不变。
- 引用索引 builder 或 `validate_project_data()` 的索引接线变更需跑目标 GUT unit，覆盖坏 root / 类型、真实 loader String 输入、strict JSON 对非 String ID 的拒绝、各类空 ID、source order、重复折叠、输出无别名、机关 clamp / last-write 和波次嵌套结构；再跑 DataLoader schema 与 headless boot 确认读取、坏 Mod 隔离和 fail-fast 顺序不变。
- 玩家配置 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / raw count、root 与 base stats 两处硬返回、int-like schema、body required → extra → radius 顺序、遗留 stat → callback source-order、stat false 传播、金币 pool callback 空返回后的双诊断、已登记错误 pool、energy 与 root / defense / dash under-validation、错误 sink参数及跨调用无状态；再跑 full GUT、contracts、Python data/schema、L1 / runtime / actor / save / loading smoke、headless boot 与四条 checked-in Replay v9 golden，确认 locale 后 / camera feedback 前调用位置、base stats 硬返回不写 count、data hash 与 Replay 摘要不变。
- 相机反馈 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / 最小边界、root 类型、schema → aim 4 字段 → 玩家 shake 7 字段 → 武器 shake 7 字段 → 振幅指数的诊断顺序、嵌套 Dictionary 短路、integral float、number / finite / 范围、额外 key、错误 sink 参数及跨调用无状态；再跑 Python schema、`vfx-smoke`、`runtime-smoke`、headless boot 与 Replay regression，确认原路径 / expected 文本、玩家后 / 视觉效果前调用位置、二次加载的索引输入、Dictionary root 的 `camera_feedback_profiles = 2`、data hash 与 Replay v9 摘要不变。
- 致谢 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / integral-float schema、root / sections shape、section / entry source order 与计数、String 化重复 id、external 前缀分支、可选 copyright、locale callback、错误 sink 参数及跨调用无状态；再跑 Python schema、`mod-loader-smoke`、headless boot 与 Replay regression，确认原路径 / expected 文本、Mod-aware locale 诊断、Dictionary root 的两个 count、data hash 与 Replay v9 摘要不变。
- Gear Mod 掉落 validator 或接线变更需跑目标 GUT unit，覆盖数值边界、空合并表、多错误顺序、未知 id、等级解析 / 下限 / 倒置、重复 key、包 root / row 形状、exact-key 顺序、旧静默诊断、包内重复合法和跨调用无状态；再跑 Python schema 负例与 `mod-loader-smoke`，确认坏包的合法掉落行会随包隔离、最终 count / 有效包顺序不变。
- 机关目录 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / raw count、空表、行号 / id 重复与 id 不 trim、tags trim / 去空 / 未登记 bool 缺口 / 有效重复 / `tag_hazard`、pool / element 契约、CSV parse / finite / 下限、callback 非短路、额外列 / 表现列忽略与跨调用无状态；再跑 contracts、Python data / schema、`mod-loader-smoke`、headless boot 与 Replay regression，确认 Gear Mod 掉落后 / active items 前的调用位置、表现引用→schema→引用 builder 的三次独立读取、`hazards = 2`、data hash 与 Replay 摘要不变。
- 主动道具目录 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / 规范化 count、root 硬返回、schema int-like、active items 双诊断、item shape / id 重复与不 trim、locale / bool / tag 顺序、未登记 tag bool 缺口、charge 局部短路 / mode / finite / int-like / 下限后关系、use effects 双诊断 / entry / effect / params、callback 非短路、额外 / 表现字段忽略与跨调用无状态；再跑 contracts、Python data / schema、`mod-loader-smoke`、headless boot 与 Replay regression，确认机关索引后 / consumables 前的调用位置、表现引用→schema→引用 builder 的三次独立读取、官方 active item count、data hash 与 Replay 摘要不变。
- 消耗品目录 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / 规范化 count、root 硬返回、schema int-like、consumables 双诊断、item shape / id 重复与不 trim、locale / bool / tag 顺序、未登记 tag bool 缺口、stack 局部短路 / int-like / 下限后关系、use effects 双诊断 / entry / effect / params、callback 非短路、额外 / 表现字段忽略与跨调用无状态；再跑 contracts、Python data / schema、`mod-loader-smoke`、headless boot 与 Replay regression，确认主动道具索引后 / skills 前的调用位置、表现引用→schema→引用 builder 的三次独立读取、官方 consumable count、data hash 与 Replay 摘要不变。
- 元素目录 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / 两个规范化 count、root 硬返回、schema exact int-like、neutral / unmatched source order、elements / components / combinations 非 Array 诊断但 aggregate bool 不变、item shape、空 / 未登记 element id 只诊断且不进 seen、合法 element / component 重复、locale / kind、契约定义列表的遍历后调用时点、left / right callback bool 缺口、result 失败、无序 pair 重复、额外字段忽略、错误 sink 参数与跨调用无状态；再跑 full GUT、contracts、Python data / schema、`mod-loader-smoke`、L1 / loading / codex / runtime / replay smoke、headless boot 与四条 checked-in Replay v9 golden，确认表现引用后 / hero passives 前的调用位置、单次 Mod-aware 读取、Dictionary root 的 `elements` / `element_combinations` count、data hash 与 Replay 摘要不变。
- 刷怪波次 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / raw count、空表、行号 / id / mode-wave 去重、mode 契约 callback 的历史 aggregate-bool 缺口、已登记 mode 的真实定义、enemy / hazard 引用、CSV String int / float 解析、finite / 数值 / 时间关系边界、空 hazard / 正权重关系、错误 source-order、后续检查不短路、额外列忽略与跨调用无状态；再跑 full GUT、contracts、Python data / schema、`mod-loader-smoke`、L1 / replay smoke、headless boot 与四条 checked-in Replay v9 golden，确认 game modes 校验→content unlock→game mode IDs 二读→map layouts→wave validator→wave index 二读→map layout IDs 二读→warzone director 顺序、两次独立 Mod-aware wave 读取、raw `spawn_waves` count、data hash 与 Replay 摘要不变。
- 英雄被动目录 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / 规范化 count、root 硬返回、schema exact int-like、passives 非 Array 诊断但 aggregate bool 不变、空 Array、item shape / source order、空 / 未登记 id 只诊断且不进 seen、合法 id 重复、locale / effect callback 非短路、params 局部短路、element 失败后 multiplier 继续、number / finite / `0.0..1.0` 边界、额外字段忽略、错误 sink 参数与跨调用无状态；再跑 contracts、Python data / schema、headless boot 与四条 checked-in Replay v9 golden，确认 elements 后 / weapons 前的调用位置、两次独立 Mod-aware 读取、Dictionary root 的规范化 `hero_passives` count、data hash 与 Replay 摘要不变。
- 敌人 AI profile validator 或接线变更需跑目标 GUT unit，覆盖 canonical 四类攻击 / 规范化 count、root 硬返回、schema exact int-like `5`、profiles Array / non-empty 双诊断、profile shape / id 重复、contact / sense / targeting / movement 遗留字段、perception 关系、action Array / duplicate、未登记非攻击 action 的历史 aggregate-bool 缺口、非攻击携带 attack、四类 exact-key / 数值 / element / pool / projectile 边界、callback 非短路、输入不变与跨调用无状态；再跑 full GUT、contracts、Python data / schema、L1 / runtime / actor / save smoke、headless boot 与四条 checked-in Replay v9 golden，确认 weapons 索引后校验→第二次 profile 索引读取→enemy rewards→enemies 的调用位置、单次 validator 读取、Dictionary root 的 `enemy_ai_profiles` count、data hash 与 Replay 摘要不变。纯等价提取不得顺手收紧旧 bool 缺口，只重跑不重录，不运行性能 probe。
- 敌人金币模型 validator 或接线变更需跑目标 GUT unit，覆盖 canonical / 最小边界、root 类型、required / extra 与字段错误顺序、int-like schema、number / finite / 正数 / 非负边界、非法上下界仍执行关系比较、错误 sink 参数及跨调用无状态；再跑 Python schema、L1、`mod-loader-smoke`、headless boot 与 Replay regression，确认原路径 / expected 文本、敌人 AI 后 / `enemies.csv` 前调用位置、Dictionary root 的 `enemy_reward_models = 1`、data hash 与 Replay v9 摘要不变。
- 等级曲线 validator 或接线变更需跑目标 GUT unit，覆盖有效 / 最小边界、root 类型、逐字段错误和顺序、integral float、下限失败后的关系检查、非整数跳过关系、额外 root key、错误 sink 参数及跨调用无状态；再跑 Python schema 负例与 headless boot，确认原路径 / expected 文本、角色后 / 奖励池前的调用位置和 schema count 不变。
- 通用奖励选择池 validator 或接线变更需跑目标 GUT unit，覆盖 canonical、root / pool / entry shape、schema exact int-like、source count、pool / entry String 重复、locale / modifier callback 顺序、空 pools / entries、非 Array pools / entries / modifiers 与缺失 / 未登记 stat 的历史“有诊断但 bool 仍可能成功”、modifier false 传播、错误 sink 参数及跨调用无状态；再跑 Python schema、headless boot 与四条 checked-in Replay v9 golden，确认原路径 / expected 文本、等级曲线后 / 难度 profile 前调用位置、Dictionary root 的规范化 `reward_choice_pools` count、data hash 与 Replay 摘要不变。
- 难度 profile validator 或接线变更需跑目标 GUT unit，覆盖 canonical / 数值边界、root / profiles shape、root / profile exact-key required 与 extra source-order、非 Dictionary profile 继续、合法 String ID / stage key 重复、九段 locale 顺序、Mod-aware callback、typed count、错误 sink 参数及跨调用无状态；再跑 Python schema、headless boot 与四条 checked-in Replay v9 golden，确认原路径 / expected 文本、奖励池后 / game mode 前调用位置、Dictionary root 的规范化 `difficulty_profiles` count、第二次读取的引用索引输入、data hash 与 Replay 摘要不变。
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
