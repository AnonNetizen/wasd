# DataLoader 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `DataLoader` autoload 的代码契约权威；改公共 API、数据 schema、契约加载、CSV/JSON 解析或 fail-fast 行为时必须同步本文档、`docs/AI导航.md`、`client/data/README.md` 与必要的测试说明。

## 职责

- 统一加载 `client/data/` 下的 JSON 与 CSV 配置。
- 通过 `ModLoader` 合并 `user://mods/<mod_id>/` 下声明式数据 patch，为本地玩家 mod 提供统一入口。
- 启动时读取 `res://data/_contracts.json`，为后续数据校验提供词表白名单。
- 提供正式数据 schema 校验入口，当前覆盖 `player.json`、`characters.json`、`weapons.json`、`skills.json`、`enemy_ai_profiles.json`、`enemies.csv`、`gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv`、`hazards.csv`、`map_layouts.json`、`warzone_directors.json`、`spawn_waves.csv`、`relics.json`、`active_items.json`、`consumables.json`、`credits.json`、`game_modes.json`、`meta_progression.json`、`growth.csv`、`growth_pools.json` 与 `strings.csv`。
- 提供 fail-fast 错误输出，错误信息包含文件、字段路径和期望值。
- 不负责业务解释、数值平衡、热重载 UI、升级奖励应用或游戏模式运行时；这些由后续业务模块接入。

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
| `client/data/player.json` | 当前 JSON 读取样例 |
| `client/data/characters.json` | 角色基础属性、标签、能力、控制配置和起始携带引用边界 |
| `client/data/weapons.json` | 武器与子弹基础数值、对象池、伤害类型和音频 id 边界 |
| `client/data/skills.json` | 项目版轻量 GAS 技能、ability tag、激活条件、资源消耗、目标类型、效果原语和冷却边界 |
| `client/data/enemy_ai_profiles.json` | 敌人生态 AI profile、感知、目标权重和动作列表边界 |
| `client/data/enemies.csv` | 敌人基础数值、生态 tag、AI profile 引用、对象池、伤害类型和模式引用边界 |
| `client/data/gear_mods.json` | 装备 Mod 定义、槽位、稀有度、rank、drain、修正器和分解返还边界 |
| `client/data/gear_mod_drop_tables.csv` | 装备 Mod 掉落来源、概率和敌人等级条件边界 |
| `client/data/gear_mod_fusion_costs.csv` | 装备 Mod 按稀有度 / rank 的升级资源成本边界 |
| `client/data/hazards.csv` | 机关基础数值、对象池、伤害类型和模式引用边界 |
| `client/data/map_layouts.json` | 有限地图、玩家出生点、PCG 机关规则和人工摆点边界 |
| `client/data/warzone_directors.json` | 敌巢战区导演、固定阶段、巢变异主题、生态 encounter、兴趣点和阶段启用 wave 边界 |
| `client/data/spawn_waves.csv` | 刷怪波次、模式引用、敌人 / 机关引用、时间窗和强度数值边界 |
| `client/data/relics.json` | 被动遗物 modifier / behavior 数据边界 |
| `client/data/active_items.json` | 主动道具充能 / 使用效果数据边界 |
| `client/data/consumables.json` | 消耗品堆叠 / 拾取数量 / 使用效果数据边界 |
| `client/data/credits.json` | 游戏内致谢数据源，记录工作人员、外部资源、外部库和发行 notice 状态 |
| `client/data/game_modes.json` | 游戏模式资源池、参与者 / 队伍与轻量覆盖边界 |
| `client/data/meta_progression.json` | 当前复杂 JSON 配置样例 |
| `client/data/growth.csv` | 经验阈值与升级候选数量概率曲线 |
| `client/data/growth_pools.json` | 升级候选池与奖励条目边界 |
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
  - `player.json`：`schema_version`、`base_stats`，stat id 必须来自词表，数值范围按 stat 类型校验；`max_hp` 是正数浮点血量，`health_regen` 是非负 HP/s。
  - `characters.json`：角色 id、名称 / 描述 key、默认解锁、tags、capabilities、控制配置、起始携带引用和角色基础属性；起始武器、主动道具和消耗品引用必须存在于对应数据文件。
  - `weapons.json`：武器 id、名称 / 描述 key、默认解锁、开火模式、开火音频 id、武器基础属性、子弹对象池、伤害类型和弹体数值。
  - `skills.json`：技能 id、名称 / 描述 key、`tag_skill`、ability tags、activation required / blocked / granted tags、冷却、资源消耗、目标类型和效果原语；技能 id、资源、targeting、effect 和 ability tag 必须来自词表 §12-C~12-G，`skill_effect_damage` 的伤害类型交给 `Combat` 词表校验，`skill_effect_apply_status` 的 status / stack_rule / granted ability tags 必须来自词表 §9-A / §9-B / §12-G；当状态效果同时声明正 `magnitude` 与正 `tick_interval` 时，还必须声明已登记 `damage_type`。
  - `enemy_ai_profiles.json`：profile id、感知半径、决策间隔、接触冷却、玩家 / 生态 tag 目标权重、领地参数、动作参数和 action id；action 必须来自词表 §12-B，生态 tag 必须来自 content tags。
  - `enemies.csv`：敌人 id、名称 key、`tag_enemy`、生态 tags、对象池 id、AI profile 引用、生命、移速、接触伤害、接触伤害类型、经验奖励和命中半径；`ai_profile_id` 必须存在于 `enemy_ai_profiles.json`。
  - `gear_mods.json`：装备 Mod id、名称 / 描述 key、英雄 / 武器 slot、稀有度、最大 rank、drain、按 rank 计算的 stat modifier、装配规则和分解返还资源；id、slot、rarity、resource、stack rule 均来自词表 §13-A~§13-E。
  - `gear_mod_drop_tables.csv`：装备 Mod 掉落来源敌人、Mod id、掉落概率和敌人等级区间；敌人必须存在于 `enemies.csv`，Mod 必须存在于 `gear_mods.json`，概率必须是 `0.0..1.0`。
  - `gear_mod_fusion_costs.csv`：装备 Mod 升到目标 rank 的资源成本；rarity 与 resource 必须来自词表，且覆盖 `gear_mods.json` 中每个已使用 rarity 的 `1..max_rank`。
  - `hazards.csv`：机关 id、名称 key、`tag_hazard`、对象池 id、伤害、伤害类型、触发间隔、范围和持续时间。
  - `map_layouts.json`：layout id、模式引用、有限地图菱形外接 bounds、玩家出生点、安全半径、刷怪边距、PCG 机关规则和人工机关摆点；`mode_id` 必须存在于 `game_modes.json`，所有机关 id 必须存在于 `hazards.csv`，bounds 必须是 `grid.cell_width/cell_height` 的奇数倍并匹配菱形斜率。
  - `spawn_waves.csv`：波次 id、模式 id、波次序号、时间窗、敌人引用、敌人权重、刷怪间隔、同时存活上限、预算，以及可选机关引用 / 权重。
  - `warzone_directors.json`：director id、模式引用、固定 mutation、阶段时间窗、阶段启用 wave、生态 encounter 和兴趣点；`mode_id` 必须存在于 `game_modes.json`，`wave_ids` 必须引用同模式 `spawn_waves.csv`，同模式所有 wave 必须至少被一个 phase 引用，encounter enemy tags 必须来自 `content_tags`，兴趣点的 `hazard_ids` 必须非空且机关 / 地图引用必须存在。
  - `relics.json`：遗物 id、名称 / 描述 key、默认解锁、`tag_relic`、数值 modifiers、行为 behaviors，以及至少一个 modifier 或 behavior。
  - `active_items.json`：主动道具 id、名称 / 描述 key、默认解锁、`tag_active_item`、冷却充能、初始 / 最大充能和使用效果原语。
  - `consumables.json`：消耗品 id、名称 / 描述 key、默认解锁、`tag_consumable`、最大堆叠、初始数量、单次拾取数量和使用效果原语。
  - `credits.json`：致谢分组、分组标题 locale key、工作人员条目、外部资源 / 库 / 工具条目的 URL、license、是否随构建分发、是否需要 notice 与复核状态。
  - `meta_progression.json`：局外货币、结算奖励、账号等级、永久升级轨道、解锁项、locale key 与词表 id。
  - `growth.csv`：等级、累计经验阈值、默认候选数、幸运扩展候选概率和概率上限。
  - `growth_pools.json`：候选池、条目 id、类型、权重、等级条件和属性修正。
  - `game_modes.json`：模式 id、名称 / 描述 key、默认解锁、participants / teams、角色池、武器池、技能池、敌人池、机关池、遗物池、主动道具池、消耗品池、成长池、content tag blocklist 与玩家基础属性轻量覆盖；角色池 id 必须存在于 `characters.json`，武器池 id 必须存在于 `weapons.json`，技能池 id 必须存在于 `skills.json`，敌人池 id 必须存在于 `enemies.csv`，机关池 id 必须存在于 `hazards.csv`，遗物池 id 必须存在于 `relics.json`，主动道具池 id 必须存在于 `active_items.json`，消耗品池 id 必须存在于 `consumables.json`。
  - `strings.csv`：key 前缀、`zh_CN` / `en` 必填、唯一 key。
- 当前校验 `characters.json`、`weapons.json`、`skills.json`、`enemy_ai_profiles.json`、`enemies.csv`、`gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv`、`hazards.csv`、`map_layouts.json`、`warzone_directors.json`、`spawn_waves.csv`、`relics.json`、`active_items.json`、`consumables.json`、`credits.json` 与 `game_modes.json` 的数据边界；技能运行时首片由 `docs/代码/skill_system.md` 解释，状态效果生命周期见 `docs/代码/status_effect_component.md`，有限地图 / PCG 解释见 `docs/代码/map_manager.md`，机关运行时解释见 `docs/代码/hazard_system.md`，敌人 AI 的业务解释见 `docs/代码/enemy_ai.md`，战区导演解释见 `docs/代码/warzone_director.md`，装备 Mod 运行时解释见 `docs/代码/gear_mod_system.md`。其余尚不实现角色选择 UI、完整起始携带发放、遗物拾取 / 应用、主动道具栏 / 冷却 / 使用效果、消耗品拾取 / 背包 / 使用 / 数量扣减 / 效果执行、Credits UI、装备 Mod UI / 掉落 / 升级 / 分解运行时、模式选择 UI、匹配、联网、成长抽取、输入 profile 切换或完整模式运行时。

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
| 改技能 schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/skill_system.md`、必要时 `docs/代码/status_effect_component.md` | `validate_data` + schema test + `l1-smoke` / `runtime-smoke` |
| 加 CSV 表读取 | `data_loader.gd` | `client/data/README.md` | `load_csv()` smoke / 数据校验 |
| 改敌人 AI profile schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/enemy_ai.md` | `validate_data` + schema test + `runtime-smoke` |
| 改地图 layout schema | `data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` | `client/data/README.md`、`docs/代码/map_manager.md` | `validate_data` + schema test + `runtime-smoke` |
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
| mod 内容没进数据 | `DataLoader.mod_diagnostics()` 与 `[ModLoader]` warning；确认 manifest `target` / `path` / `array_key` |

## 测试义务

- 必跑 `tools/godot_bridge.py --project client headless-boot`。
- 改 mod 接口或 `contract_values()` 合并逻辑时跑 `tools/godot_bridge.py --project client l1-smoke`。
- 改契约 / 数据时跑 `tools/sync_contracts.py --check` 与 `tools/validate_data.py`。
- F3 schema 变更需跑 `tools/test_data_loader_schema.py`，覆盖黄金样例、未登记 id、缺失 locale key、类型 / 范围错误、跨文件引用错误和 fail-fast 输出格式。

## 迁移 / 兼容

当前 `ModLoader` 不改变存档 schema；存档和回放后续应记录数据指纹，避免缺失 mod 时静默恢复旧局。未来改变 `_contracts.json` schema 或 mod manifest schema 时必须同步 `tools/sync_contracts.py`、`tools/validate_data.py`、`docs/代码/mod_loader.md` 与本文档。

## 相关文档

- `docs/游戏设计文档.md` §9.3 / §9.19
- `docs/词表与契约.md`
- `docs/代码/mod_loader.md`
- `client/data/README.md`
- `docs/测试策略.md`
