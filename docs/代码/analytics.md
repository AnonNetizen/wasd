# Analytics 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Analytics` autoload 的代码契约权威；改埋点事件名、隐私开关联动、公共 API、缓冲策略或测试义务时必须同步本文档。

## 职责

- `Analytics` 负责接收已登记的游戏事件，并暂存在本地内存队列中，供后续诊断、回放验证或正式埋点管线接入。
- 事件名必须来自 `docs/词表与契约.md`，并通过 `client/scripts/contracts/analytics_events.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- 当前切片不写磁盘、不联网、不上传、不记录个人身份信息；它只是一个可验证的本地事件缓冲层。
- `Analytics` 受 `Settings` 的 `privacy.analytics_enabled` 控制；关闭后会清空已缓冲事件，并拒绝新的 `track_event()` 写入。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 增加埋点事件 | `docs/词表与契约.md` 埋点事件段落，再看本文档数据与契约 |
| 调用埋点 | 本文档公共 API 与 `client/scripts/contracts/analytics_events.gd` |
| 改隐私开关行为 | 本文档运行流程、`docs/代码/settings.md` |
| 接入真实上报 | 本文档迁移 / 兼容段落，先补 ADR / 隐私策略边界 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/analytics.gd` | `Analytics` autoload 脚本 |
| `client/scripts/contracts/analytics_events.gd` | 自动生成的埋点事件常量 |
| `client/scripts/contracts/settings_keys.gd` | 自动生成的隐私设置 key 常量 |
| `client/data/_contracts.json` | 自动生成的契约缓存 |
| `client/project.godot` | autoload 注册 |

## 场景 / 节点结构

`Analytics` 是 autoload singleton，没有 `.tscn` 场景。Godot 在启动时按 `client/project.godot` 的 `[autoload]` 顺序实例化；它依赖 `Settings` 已经完成默认值初始化。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `_ready()` 从 `Settings.privacy.analytics_enabled` 初始化开关，并监听设置变化 | `set_enabled()` / `Settings.setting_changed` |
| 记录 | 调用方传入已登记事件名和参数，模块补充 tick、time、state 诊断上下文 | `track_event()` / `event_tracked` |
| 读取 | 调用方获取缓冲事件快照 | `events()` / `event_count()` |
| 隐私关闭 | 清空缓冲队列并停止接受新事件 | `set_enabled(false)` / `events_cleared` |
| 缓冲溢出 | 保留最近 `MAX_BUFFERED_EVENTS` 条，丢弃最旧事件并累加丢弃计数 | `dropped_count()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `track_event(event_name, params = {})` | 事件名、参数字典 | `bool` | 事件未登记会 `push_error` 并返回 `false`；关闭时返回 `false` 且不写入 |
| `events()` | 无 | `Array[Dictionary]` | 返回深拷贝，调用方不得改内部状态 |
| `clear_events()` | 无 | `void` | 清空缓冲并广播 |
| `event_count()` | 无 | `int` | 当前缓冲数量 |
| `dropped_count()` | 无 | `int` | 因缓冲上限被丢弃的事件数量 |
| `is_enabled()` | 无 | `bool` | 当前隐私开关状态 |
| `set_enabled(enabled)` | 布尔值 | `void` | 关闭时清空缓冲事件 |
| `registered_events()` | 无 | `Array[String]` | 返回已生成的事件名列表 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `event_tracked` | `event_data: Dictionary` | 成功写入本地缓冲后 |
| `analytics_enabled_changed` | `enabled: bool` | 开关状态变化后 |
| `events_cleared` | 无 | 缓冲事件被清空后 |

## 数据与契约

事件名来自 `client/scripts/contracts/analytics_events.gd`，源头是 `docs/词表与契约.md`。新增事件必须先改词表，再运行 `tools/sync_contracts.py` 生成常量和 `_contracts.json`。

当前事件数据结构：

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 已登记事件名 |
| `params` | `Dictionary` | 调用方传入的上下文，当前只保存在内存 |
| `tick` | `int` | `GameClock.tick()` |
| `time` | `float` | `GameClock.now()` |
| `state` | `String` | `GameState.current()` 的诊断快照 |

## 依赖

- 上游依赖：`Settings` 提供 `privacy.analytics_enabled`；`DataLoader` 提供契约校验；`GameClock` 和 `GameState` 提供诊断上下文。
- 下游调用方：后续玩家、敌人、掉落、升级、存档、回放、元进度和模式系统都应通过 `Analytics.track_event()` 记录事件。
- 禁止依赖：业务代码不得绕过 `Analytics` 自建埋点队列、写本地埋点文件或直接接入网络上报。

## 扩展点

- 增加事件：先登记词表事件名，再使用 `ANALYTICS_EVENTS.<CONST>` 调用。
- 增加持久化：必须先明确隐私边界、文件位置、保留周期和清除策略；不能复用 `SaveManager` 的玩家存档格式。
- 增加真实上报：必须先有明确产品 / 隐私决策；默认不得上传。
- 增加事件 schema：可以在 `DataLoader` / `Analytics` 增加参数校验，但不应在调用点散落重复校验。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增事件名 | `docs/词表与契约.md` | 本文档、AI 导航 | `tools/sync_contracts.py --check`、`tools/validate_data.py` |
| 调整隐私默认值 | `client/scripts/autoload/settings.gd` | 本文档、`docs/代码/settings.md` | headless boot |
| 调整缓冲上限 | `analytics.gd` | 本文档 | L1 单测、headless boot |
| 接入真实上报 | 后续上报模块 | ADR、GDD、本文档 | 隐私 checklist + L1/L2 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| `track_event()` 返回 `false` | 事件名是否已登记；`privacy.analytics_enabled` 是否关闭 |
| 启动日志事件数量异常 | `client/data/_contracts.json` 与 `analytics_events.gd` 是否同步 |
| 关闭隐私后仍有事件 | 调用方是否绕过 `Analytics`；是否正确监听 `Settings.setting_changed` |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查和 L2 headless boot。
- 后续引入 GUT 后，`Analytics` 需要覆盖事件字段补齐、未知事件拒绝、隐私开关关闭时不写入、关闭时清空缓冲、缓冲上限与 `dropped_count()`。
- 接入真实上报前必须补隐私 / 删除 / 离线失败回退测试。

## 迁移 / 兼容

当前没有持久化埋点格式，因此没有迁移。未来若增加磁盘队列或上报协议，必须先定义版本号、清除策略、失败回退和隐私关闭后的清理行为；不得默默保留用户已关闭分析后的历史缓冲。

## 相关文档

- `docs/游戏设计文档.md` §9.6
- `docs/词表与契约.md` 埋点事件段落
- `docs/测试策略.md`
- `docs/代码/settings.md`
