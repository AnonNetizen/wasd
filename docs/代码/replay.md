# Replay 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Replay` autoload 的代码契约权威；改录制格式、公共 API、signal、确定性依赖、落盘策略或测试义务时必须同步本文档。

## 职责

- `Replay` 负责记录一局的确定性回放输入：主 seed、游戏 tick / time、InputMap action、关键决策事件和启动上下文。
- 输入 action 必须来自 `docs/词表与契约.md`，并通过 `client/scripts/contracts/actions.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- 关键决策事件当前复用已登记的 `analytics_events`，例如后续升级、拾取、道具使用等事件；需要新的事件名时先改词表。
- 当前切片只提供内存态录制与快照，不写入 `user://replays/`，不接管输入回放，也不做黄金回放 diff。
- `Replay` 受 `Settings.gameplay.record_replays` 控制；关闭后会清空当前内存录制并拒绝新录制。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 接入玩家输入录制 | 本文档公共 API 与 `docs/词表与契约.md` action 段落 |
| 记录升级 / 拾取等关键决策 | `record_decision()` 与 `client/scripts/contracts/analytics_events.gd` |
| 改自动录制时机 | 本文档运行流程、`docs/代码/game_state.md` |
| 做 `.replay` 文件落盘 | 本文档迁移 / 兼容段落、GDD §9.9、后续 SaveManager 边界 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/replay.gd` | `Replay` autoload 脚本 |
| `client/scripts/contracts/actions.gd` | 自动生成的 InputMap action 常量 |
| `client/scripts/contracts/analytics_events.gd` | 自动生成的关键事件常量 |
| `client/scripts/contracts/settings_keys.gd` | 自动生成的设置 key 常量 |
| `client/project.godot` | autoload 注册 |

## 场景 / 节点结构

`Replay` 是 autoload singleton，没有 `.tscn` 场景。Godot 在启动时按 `client/project.godot` 的 `[autoload]` 顺序实例化；它依赖 `RNG`、`GameState`、`GameClock`、`Settings` 与 `Analytics` 已存在。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | 从 `Settings.gameplay.record_replays` 初始化开关，并监听设置与状态变化 | `set_enabled()` |
| 进入 `PLAYING` | 若启用且未录制，则自动建立内存录制 | `start_recording()` / `recording_started` |
| 输入发生 | 调用方记录已登记 action、按下状态、强度和可选 participant | `record_input_action()` / `input_recorded` |
| 关键决策 | 调用方记录已登记 analytics event 与 payload | `record_decision()` / `decision_recorded` |
| 进入 `GAME_OVER` / `RESULT` / `MAIN_MENU` | 结束内存录制，补齐结束 tick/time 与丢弃计数，并发出本地埋点 | `stop_recording()` / `recording_stopped` |
| 关闭录制设置 | 清空当前内存录制并停止接受新事件 | `set_enabled(false)` / `recording_cleared` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `start_recording(context = {})` | 启动上下文 | `bool` | 关闭或已录制时返回 `false` |
| `stop_recording(reason = "")` | 停止原因 | `Dictionary` | 未录制时返回空字典；成功后发 `replay_recorded` 埋点 |
| `record_input_action(action_name, pressed, strength = 1.0, participant_id = "")` | action、按下状态、强度、参与者 | `bool` | action 未登记会 `push_error` 并返回 `false` |
| `record_decision(event_name, payload = {})` | 关键事件名、payload | `bool` | event 未登记会 `push_error` 并返回 `false` |
| `clear_recording()` | 无 | `void` | 清空内存录制和丢弃计数 |
| `snapshot()` | 无 | `Dictionary` | 返回当前录制深拷贝 |
| `is_enabled()` | 无 | `bool` | 当前是否允许自动录制 |
| `is_recording()` | 无 | `bool` | 当前是否正在内存录制 |
| `input_event_count()` | 无 | `int` | 当前输入事件数 |
| `decision_event_count()` | 无 | `int` | 当前关键决策事件数 |
| `dropped_input_count()` | 无 | `int` | 因输入缓冲上限被丢弃的数量 |
| `dropped_decision_count()` | 无 | `int` | 因决策缓冲上限被丢弃的数量 |
| `registered_actions()` | 无 | `Array[String]` | 返回已生成 action 列表 |
| `set_enabled(enabled)` | 布尔值 | `void` | 关闭时清空当前录制 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `recording_enabled_changed` | `enabled: bool` | 录制开关变化后 |
| `recording_started` | `recording: Dictionary` | 成功开始录制后 |
| `recording_stopped` | `recording: Dictionary` | 成功停止录制后 |
| `input_recorded` | `input_event: Dictionary` | 成功记录输入后 |
| `decision_recorded` | `decision_event: Dictionary` | 成功记录关键决策后 |
| `recording_cleared` | 无 | 当前内存录制被清空后 |

## 数据与契约

当前内存录制结构：

| 字段 | 类型 | 说明 |
|------|------|------|
| `schema_version` | `int` | 当前内存 schema 版本 |
| `run_seed` | `int` | `RNG.run_seed()` 快照 |
| `started_tick` / `ended_tick` | `int` | `GameClock.tick()` 快照 |
| `started_time` / `ended_time` | `float` | `GameClock.now()` 快照 |
| `context` | `Dictionary` | `GameState` 进入 `PLAYING` 时传入的上下文 |
| `input_events` | `Array[Dictionary]` | action 输入事件 |
| `decision_events` | `Array[Dictionary]` | 关键决策事件 |
| `dropped_input_events` / `dropped_decision_events` | `int` | 缓冲上限丢弃计数 |

输入事件字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `String` | 已登记 InputMap action |
| `pressed` | `bool` | 是否按下 |
| `strength` | `float` | 0~1 输入强度 |
| `tick` / `time` | `int` / `float` | 录制时的游戏 tick / time |
| `participant_id` | `String` | 可选；未来多人 / AIPlayer 预留 |

关键决策事件字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `event` | `String` | 已登记 analytics event |
| `payload` | `Dictionary` | 决策上下文，例如候选 id、选择结果或当时属性快照 |
| `tick` / `time` | `int` / `float` | 录制时的游戏 tick / time |

## 依赖

- 上游依赖：`RNG` 提供主 seed；`GameClock` 提供 tick / time；`GameState` 提供自动录制时机；`Settings` 提供录制开关；`DataLoader` 提供 action / event 契约校验；`Analytics` 接收 `replay_recorded` 本地事件。
- 下游调用方：后续 `InputController`、`GrowthSystem`、`ItemSystem`、`SaveManager`、黄金回放 runner 和调试回放 UI。
- 禁止依赖：业务系统不得直接读写 `.replay` 文件；不得绕过 `Replay` 自建输入录制；不得用非确定时间源参与回放内容。

## 扩展点

- 接入输入：`InputController` 将归一化 action / pressed / strength 调给 `record_input_action()`。
- 接入升级选择：升级候选数量、候选 id、玩家选择和 `luck` 快照通过 `record_decision()` 写入。
- 增加落盘：后续写到 `user://replays/<timestamp>.replay`，需要先明确文件 schema、版本、压缩和清理策略。
- 增加重放：后续 `play(file)` / 对照 diff 应只消费录制内容，不读取业务模块私有状态。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增可录制 action | `docs/词表与契约.md` | 本文档、AI 导航 | `tools/sync_contracts.py --check`、headless boot |
| 新增关键决策事件 | `docs/词表与契约.md` | 本文档、Analytics 文档 | `tools/sync_contracts.py --check` |
| 调整录制开关 | `settings.gd`、`replay.gd` | 本文档、Settings 文档 | headless boot |
| 接入落盘 | `replay.gd`、后续 replay runner | 本文档、测试策略、CI 规划 | L1 + L2 + L3 |
| 接入黄金回放 | 后续 `tests/replays/` 与工具脚本 | 本文档、测试策略 | L3 replay runner |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 进入游戏未开始录制 | `Settings.gameplay.record_replays` 是否开启；是否通过 `GameState.change_state(PLAYING)` 进入 |
| 输入记录失败 | action 是否登记在 `docs/词表与契约.md` 和 `_contracts.json` |
| 关键决策记录失败 | event 是否登记为 analytics event |
| 回放不可重现 | 是否有业务代码绕过 `RNG` / `GameClock` 或输入未走 `Replay` |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查和 L2 headless boot。
- 后续引入 GUT 后，`Replay` 需要覆盖录制开始 / 停止、action 校验、event 校验、设置关闭清空、缓冲丢弃计数和同 seed 录制字段稳定。
- 接入 `.replay` 文件与重放 runner 后，必须补 L3 黄金回放样例；有意改变确定性行为时才重录黄金回放并在 commit message 注明影响。

## 迁移 / 兼容

当前没有持久化 `.replay` 文件，因此没有文件迁移。未来落盘后必须固定 `schema_version`，并在格式变化时提供兼容读取或明确旧回放失效策略；不能把玩家续局 `run` 存档和回放文件混成同一格式。

## 相关文档

- `docs/游戏设计文档.md` §9.9 / §9.18
- `docs/词表与契约.md` action 与 analytics event 段落
- `docs/测试策略.md`
- `docs/代码/rng.md`
- `docs/代码/game_clock.md`
- `docs/代码/game_state.md`
- `docs/代码/analytics.md`
