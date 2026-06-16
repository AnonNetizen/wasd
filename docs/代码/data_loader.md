# DataLoader 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `DataLoader` autoload 的代码契约权威；改公共 API、数据 schema、契约加载、CSV/JSON 解析或 fail-fast 行为时必须同步本文档、`docs/AI导航.md`、`client/data/README.md` 与必要的测试说明。

## 职责

- 统一加载 `client/data/` 下的 JSON 与 CSV 配置。
- 启动时读取 `res://data/_contracts.json`，为后续数据校验提供词表白名单。
- 提供 fail-fast 错误输出，错误信息包含文件、字段路径和期望值。
- 不负责业务解释、数值平衡、热重载 UI 或具体系统 schema 校验；这些由后续 F3+ 业务模块接入。

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
| `client/data/meta_progression.json` | 当前复杂 JSON 配置样例 |

## 场景 / 节点结构

无场景节点。`DataLoader` 通过 `client/project.godot` 的 `[autoload]` 注册为全局单例。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| autoload `_ready()` | 加载 `_contracts.json` | `reload_contracts()` |
| 配置读取 | 调用方按需读 JSON / CSV | `load_json()`、`load_csv()` |
| 契约查询 | 调用方查询白名单 | `contract_values()`、`has_contract_value()` |
| 重新加载 | 覆盖 `_contracts` 并通知订阅方 | `data_reloaded` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `reload_contracts()` | 无 | `void` | 读取 `CONTRACTS_PATH`，失败时 `push_error` |
| `contracts()` | 无 | `Dictionary` | 返回深拷贝，调用方不得改内部缓存 |
| `contract_values(contract_id)` | `String` | `Array` | 未登记 id 报错并返回空数组 |
| `has_contract_value(contract_id, value)` | `String`, `String` | `bool` | 用于 schema / id 校验 |
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
- F3 会继续补正式业务 schema 校验，例如 `player.json`、`growth.csv`、`game_modes.json`。

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
| 加 JSON 数据 schema | 业务模块 + `DataLoader` 辅助函数 | `client/data/README.md`、对应模块文档 | `tools/validate_data.py`、headless boot |
| 加 CSV 表读取 | `data_loader.gd` | `client/data/README.md` | `load_csv()` smoke / 数据校验 |
| 改契约来源 | `tools/sync_contracts.py`、`_contracts.json` | `docs/词表与契约.md` | `tools/sync_contracts.py --check` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动时 contracts=0 | `client/data/_contracts.json` 是否存在且 JSON 有效 |
| `contract_values()` 返回空 | contract id 是否存在于 `_contracts.json` 的 `contracts` |
| CSV 行字段错位 | 表头数量与数据列数量是否一致 |

## 测试义务

- 必跑 `tools/godot_bridge.py --project client headless-boot`。
- 改契约 / 数据时跑 `tools/sync_contracts.py --check` 与 `tools/validate_data.py`。
- F3 开始补 DataLoader schema 单测，覆盖黄金样例、未登记 id fail-fast 和错误格式。

## 迁移 / 兼容

当前不影响存档、回放或旧配置。未来改变 `_contracts.json` schema 时必须同步 `tools/sync_contracts.py`、`tools/validate_data.py` 与本文档。

## 相关文档

- `docs/游戏设计文档.md` §9.3 / §9.19
- `docs/词表与契约.md`
- `client/data/README.md`
- `docs/测试策略.md`
