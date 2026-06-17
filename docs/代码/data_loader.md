# DataLoader 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `DataLoader` autoload 的代码契约权威；改公共 API、数据 schema、契约加载、CSV/JSON 解析或 fail-fast 行为时必须同步本文档、`docs/AI导航.md`、`client/data/README.md` 与必要的测试说明。

## 职责

- 统一加载 `client/data/` 下的 JSON 与 CSV 配置。
- 启动时读取 `res://data/_contracts.json`，为后续数据校验提供词表白名单。
- 提供正式数据 schema 校验入口，当前覆盖 `player.json`、`characters.json`、`weapons.json`、`enemies.csv`、`hazards.csv`、`relics.json`、`game_modes.json`、`meta_progression.json`、`growth.csv`、`growth_pools.json` 与 `strings.csv`。
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
| `client/data/_contracts.json` | 由 `tools/sync_contracts.py` 生成的词表镜像 |
| `client/data/player.json` | 当前 JSON 读取样例 |
| `client/data/characters.json` | 角色基础属性、标签、能力和控制配置边界 |
| `client/data/weapons.json` | 武器与子弹基础数值、对象池、伤害类型和音频 id 边界 |
| `client/data/enemies.csv` | 敌人基础数值、对象池、伤害类型和模式引用边界 |
| `client/data/hazards.csv` | 机关基础数值、对象池、伤害类型和模式引用边界 |
| `client/data/relics.json` | 被动遗物 modifier / behavior 数据边界 |
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
| 配置读取 | 调用方按需读 JSON / CSV | `load_json()`、`load_csv()` |
| schema 校验 | 启动 smoke 或工具调用正式数据校验 | `validate_project_data()`、`schema_counts()` |
| 契约查询 | 调用方查询白名单 | `contract_values()`、`has_contract_value()` |
| 重新加载 | 覆盖 `_contracts` 并通知订阅方 | `data_reloaded` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `reload_contracts()` | 无 | `void` | 读取 `CONTRACTS_PATH`，失败时 `push_error` |
| `contracts()` | 无 | `Dictionary` | 返回深拷贝，调用方不得改内部缓存 |
| `contract_values(contract_id)` | `String` | `Array` | 未登记 id 报错并返回空数组 |
| `has_contract_value(contract_id, value)` | `String`, `String` | `bool` | 用于 schema / id 校验 |
| `validate_project_data()` | 无 | `bool` | 校验本阶段正式数据 schema；失败时 `push_error` 并返回 `false` |
| `schema_counts()` | 无 | `Dictionary` | 返回最近一次 schema 校验的关键计数，用于 boot smoke |
| `load_json(resource_path)` | `String` | `Variant` | JSON 需是有效文本；失败返回空字典 |
| `load_csv(resource_path, has_header)` | `String`, `bool` | `Array[Dictionary]` | 默认首行为表头 |
| `data_path(file_name)` | `String` | `String` | 拼出 `res://data/<file_name>` |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `data_reloaded` | 无 | `reload_contracts()` 成功刷新 `_contracts` 后 |

## 数据与契约

- 读取 `res://data/_contracts.json`。
- `_contracts.json` 由 `tools/sync_contracts.py` 生成，禁止手改。
- 当前 F3 schema 覆盖：
  - `player.json`：`schema_version`、`base_stats`，stat id 必须来自词表，数值范围按 stat 类型校验。
  - `characters.json`：角色 id、名称 / 描述 key、默认解锁、tags、capabilities、控制配置、起始武器引用和角色基础属性。
  - `weapons.json`：武器 id、名称 / 描述 key、默认解锁、开火模式、开火音频 id、武器基础属性、子弹对象池、伤害类型和弹体数值。
  - `enemies.csv`：敌人 id、名称 key、`tag_enemy`、对象池 id、生命、移速、接触伤害、接触伤害类型、经验奖励和命中半径。
  - `hazards.csv`：机关 id、名称 key、`tag_hazard`、对象池 id、伤害、伤害类型、触发间隔、范围和持续时间。
  - `relics.json`：遗物 id、名称 / 描述 key、默认解锁、`tag_relic`、数值 modifiers、行为 behaviors，以及至少一个 modifier 或 behavior。
  - `meta_progression.json`：局外货币、结算奖励、账号等级、永久升级轨道、解锁项、locale key 与词表 id。
  - `growth.csv`：等级、累计经验阈值、默认候选数、幸运扩展候选概率和概率上限。
  - `growth_pools.json`：候选池、条目 id、类型、权重、等级条件和属性修正。
  - `game_modes.json`：模式 id、名称 / 描述 key、默认解锁、participants / teams、角色池、武器池、敌人池、机关池、遗物池、成长池、content tag blocklist 与玩家基础属性轻量覆盖；角色池 id 必须存在于 `characters.json`，武器池 id 必须存在于 `weapons.json`，敌人池 id 必须存在于 `enemies.csv`，机关池 id 必须存在于 `hazards.csv`，遗物池 id 必须存在于 `relics.json`。
  - `strings.csv`：key 前缀、`zh_CN` / `en` 必填、唯一 key。
- 当前只校验 `characters.json`、`weapons.json`、`enemies.csv`、`hazards.csv`、`relics.json` 与 `game_modes.json` 的数据边界，不实现角色选择 UI、武器运行时、敌人生成 / AI / 刷怪、机关放置 / 触发 / 碰撞 / 伤害、遗物拾取 / 应用、模式选择 UI、匹配、联网、成长抽取、输入 profile 切换或模式运行时。

## 依赖

- 上游依赖：Godot `FileAccess`、`JSON`、生成契约文件。
- 下游调用方：后续所有读取 `client/data/` 的业务模块。
- 禁止依赖：不得直接引用具体玩法系统，避免数据层反向依赖业务层。

## 扩展点

- 新数据格式优先通过新解析函数接入，再由业务模块做 schema 校验。
- 新约定字符串必须先改 `docs/词表与契约.md` 并跑契约同步，不在 DataLoader 内硬编码白名单。
- 热重载可复用 `data_reloaded` 信号扩展。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 加 JSON 数据 schema | `data_loader.gd` + `tools/validate_data.py` | `client/data/README.md`、对应模块文档 | `tools/validate_data.py`、headless boot |
| 加 CSV 表读取 | `data_loader.gd` | `client/data/README.md` | `load_csv()` smoke / 数据校验 |
| 改契约来源 | `tools/sync_contracts.py`、`_contracts.json` | `docs/词表与契约.md` | `tools/sync_contracts.py --check` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动时 contracts=0 | `client/data/_contracts.json` 是否存在且 JSON 有效 |
| `contract_values()` 返回空 | contract id 是否存在于 `_contracts.json` 的 `contracts` |
| CSV 行字段错位 | 表头数量与数据列数量是否一致 |
| `data_schema_ok=false` | headless boot 日志前后的 `[DataLoader]` fail-fast 错误 |

## 测试义务

- 必跑 `tools/godot_bridge.py --project client headless-boot`。
- 改契约 / 数据时跑 `tools/sync_contracts.py --check` 与 `tools/validate_data.py`。
- F3 schema 变更需跑 `tools/test_data_loader_schema.py`，覆盖黄金样例、未登记 id、缺失 locale key、类型 / 范围错误、跨文件引用错误和 fail-fast 输出格式。

## 迁移 / 兼容

当前不影响存档、回放或旧配置。未来改变 `_contracts.json` schema 时必须同步 `tools/sync_contracts.py`、`tools/validate_data.py` 与本文档。

## 相关文档

- `docs/游戏设计文档.md` §9.3 / §9.19
- `docs/词表与契约.md`
- `client/data/README.md`
- `docs/测试策略.md`
