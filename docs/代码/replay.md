# Replay 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Replay` autoload 的代码契约权威；改录制格式、公共 API、signal、确定性依赖、落盘策略或测试义务时必须同步本文档。

## 职责

- `Replay` 负责记录一局的确定性回放输入：主 seed、游戏 tick / time、InputMap action、关键决策事件和启动上下文。
- 输入 action 必须来自 `docs/词表与契约.md`，并通过 `client/scripts/contracts/actions.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- 关键决策事件当前复用已登记的 `analytics_events`，例如后续升级、拾取、道具使用等事件；需要新的事件名时先改词表。
- F8 已提供 `.replay` 文件 envelope、`user://replays/` 落盘 / 读取、稳定摘要、`replay-smoke` roundtrip、`replay-runner` 摘要 diff、`client/tests/replays/golden_basic_run.replay` 的运行时摘要 + 稳定帧样本 golden baseline、gameplay 输入录制首片，以及 `replay-runner --rerun-runtime-summary` 的输入播放 / 帧样本 diff 首片；暂不做全量逐帧状态 diff。
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
| `client/tools/replay_smoke.gd` | F8 replay 文件 roundtrip smoke，覆盖最小录制、保存、读取、摘要对比和 data fingerprint |
| `client/tools/replay_runner.gd` | F8 replay summary diff runner，读取 `.replay`、校验 envelope，并比较内嵌 summary、外部 expectation JSON 或重跑运行时摘要 |
| `client/tools/replay_input_smoke.gd` | F8 gameplay 输入录制 smoke，启动真实 `GameplayRunLoop` 并确认移动 / 瞄准 / pause / ui_back 写入 `Replay.input_events` |
| `client/tools/golden_replay_capture.gd` | F8 golden capture 工具，固定 seed 启动真实 `GameplayRunLoop` 并生成 `golden_basic_run.replay` |
| `client/tests/replays/golden_basic_run.replay` | F8 首条已入库 golden replay；当前覆盖固定 seed 的运行时摘要与稳定帧样本，不是完整输入场景 / 全量逐帧 diff |
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
| 输入发生 | 调用方记录已登记 action、按下状态、强度和可选 participant；当前 gameplay 首片由 `Player` 记录移动 / 瞄准 action 状态变化，由暂停 / UI 栈路径记录 `pause` / `ui_back` 离散事件 | `record_input_action()` / `record_input_event()` / `input_recorded` |
| 关键决策 | 调用方记录已登记 analytics event 与 payload | `record_decision()` / `decision_recorded` |
| 进入 `GAME_OVER` / `RESULT` / `MAIN_MENU` | 结束内存录制，补齐结束 tick/time 与丢弃计数，并发出本地埋点 | `stop_recording()` / `recording_stopped` |
| 需要持久化 | 调用方把完成的录制写入 `user://replays/<name>.replay`；文件 envelope 包含 schema、game version、data fingerprint、recording hash 和稳定摘要 | `save_recording()` / `replay_saved` |
| 需要读取 / 对照 | runner 读取 `.replay` envelope，校验 schema 与 recording hash，比较 summary；可选 expectation JSON 或 `--rerun-runtime-summary` 会按 replay seed 启动 `GameplayRunLoop`、播放 `input_events` 并比较运行时摘要 | `load_replay_file()` / `load_recording()` / `replay-runner` |
| 关闭录制设置 | 清空当前内存录制并停止接受新事件 | `set_enabled(false)` / `recording_cleared` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `start_recording(context = {})` | 启动上下文 | `bool` | 关闭或已录制时返回 `false` |
| `stop_recording(reason = "")` | 停止原因 | `Dictionary` | 未录制时返回空字典；成功后发 `replay_recorded` 埋点 |
| `record_input_action(action_name, pressed, strength = 1.0, participant_id = "")` | action、按下状态、强度、参与者 | `bool` | action 未登记会 `push_error` 并返回 `false` |
| `record_input_event(event, action_names, participant_id = "")` | Godot `InputEvent`、候选 action、参与者 | `bool` | 将 press / release 事件转成 `record_input_action()`；当前用于 pause / ui_back 这类离散输入 |
| `record_decision(event_name, payload = {})` | 关键事件名、payload | `bool` | event 未登记会 `push_error` 并返回 `false` |
| `save_recording(recording = {}, file_name = "")` | 已完成录制、可选文件名 | `String` | 写入 `user://replays/`，返回路径；文件名会归一化为 `.replay` |
| `load_recording(path)` | `.replay` 路径 | `Dictionary` | 返回录制 payload；文件无效时返回空字典并设置 `last_error()` |
| `load_replay_file(path)` | `.replay` 路径 | `Dictionary` | 返回完整 envelope；校验 schema 和 `recording_hash` |
| `recording_summary(recording)` | 录制 payload | `Dictionary` | 返回 seed、tick/time、事件数量、停止原因等稳定摘要 |
| `current_data_fingerprint()` | 无 | `String` | 基于当前 contracts 和 schema counts 的 F8 首片数据指纹 |
| `replay_root()` | 无 | `String` | 返回 `user://replays` |
| `last_error()` | 无 | `String` | 最近一次文件读写 / 校验失败原因 |
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
| `replay_saved` | `path`, `envelope` | `.replay` 文件写入成功后 |
| `replay_loaded` | `path`, `envelope` | `.replay` 文件读取并校验成功后 |
| `replay_load_failed` | `path`, `error` | `.replay` 文件读取或校验失败后 |

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

F8 首片 `.replay` 文件 envelope：

| 字段 | 类型 | 说明 |
|------|------|------|
| `file_schema_version` | `int` | 文件 envelope 版本，当前为 1 |
| `created_at` | `String` | wall time 诊断字段，不参与玩法判定 |
| `game_version` | `String` | 当前构建 / 设计版本标签，来自 `SaveManager.GAME_VERSION` |
| `data_fingerprint` | `String` | 当前 contracts + schema counts 的稳定 hash，用于提示数据基线变化 |
| `recording_hash` | `String` | 录制 payload 的稳定 hash，读取时强校验 |
| `recording` | `Dictionary` | 上方内存录制结构 |
| `summary` | `Dictionary` | seed、tick/time、事件数量、停止原因和可选 `run_summary` 等 runner 可比较摘要 |

F8 首条 golden replay 额外在 `recording.run_summary` / `summary.run_summary` 中保存稳定运行时摘要：`scenario`、`capture_frames`、`state`、`level`、`xp`、`kills`、`player_moved_right`、`player_aim_direction`、活跃敌人 / 子弹 / 掉落数量和核心对象池统计。`run_summary.frame_samples` 保存 30 帧间隔的稳定帧样本，字段包括 `frame`、`state`、`level`、`xp`、`kills`、`player_moved_right`、`player_aim_direction`、`active_enemies`、`bullets_present`、`active_pickups`。逐帧精确子弹数量暂不进入帧样本，因为发射时机可能出现 1 帧级差异；`game_tick` / `game_time` 不进入该摘要，因为 headless 工具挂载时机可能造成少量 tick 差。

输入事件字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `String` | 已登记 InputMap action |
| `pressed` | `bool` | 是否按下 |
| `strength` | `float` | 0~1 输入强度 |
| `tick` / `time` | `int` / `float` | 录制时的游戏 tick / time |
| `participant_id` | `String` | 可选；未来多人 / AIPlayer 预留 |

当前 gameplay 输入录制首片使用固定 `participant_id=player_0`。`Player` 只在移动 / 瞄准 action 的 pressed 状态发生变化时写入事件，避免每帧重复记录；暂停、升级面板、暂停菜单和 `UIManager` 分别在自己的输入路径记录 `pause` / `ui_back`。`replay-runner --rerun-runtime-summary` 已能把这些 `input_events` 以 tick 顺序注入运行时，并比较摘要与稳定帧样本。

关键决策事件字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `event` | `String` | 已登记 analytics event |
| `payload` | `Dictionary` | 决策上下文，例如候选 id、选择结果或当时属性快照 |
| `tick` / `time` | `int` / `float` | 录制时的游戏 tick / time |

## 依赖

- 上游依赖：`RNG` 提供主 seed；`GameClock` 提供 tick / time；`GameState` 提供自动录制时机；`Settings` 提供录制开关；`DataLoader` 提供 action / event 契约校验；`Analytics` 接收 `replay_recorded` 本地事件。
- 下游调用方：当前 `Player`、`GameplayRunLoop`、`LevelUpPanel`、`PauseMenu` 与 `UIManager` 已写入首批 gameplay 输入事件；后续 `InputController`、`GrowthSystem`、`ItemSystem`、`SaveManager`、黄金回放 runner 和调试回放 UI 继续扩展。
- 禁止依赖：业务系统不得直接读写 `.replay` 文件；不得绕过 `Replay` 自建输入录制；不得用非确定时间源参与回放内容。

## 扩展点

- 接入输入：当前首片已直接从 gameplay 路径记录移动 / 瞄准状态变化以及 `pause` / `ui_back` 事件；后续若引入 `InputController`，应将归一化 action / pressed / strength 继续调给 `record_input_action()`，不要绕开 `Replay`。
- 接入升级选择：升级候选数量、候选 id、玩家选择和 `luck` 快照通过 `record_decision()` 写入。
- 增加真实重放：后续 `play(file)` / 对照 diff 应只消费录制内容，不读取业务模块私有状态；当前 `replay-smoke` 覆盖文件 roundtrip，`replay-runner` 覆盖 envelope / summary diff、输入播放首片和首条运行时摘要 golden。
- 增加黄金回放：`golden_basic_run.replay` 已由 `golden_replay_capture.gd` 生成并入库，可通过 `replay-runner --replay-file client/tests/replays/golden_basic_run.replay --rerun-runtime-summary` 对照运行时摘要与稳定帧样本；再下一步扩更多输入场景 golden。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增可录制 action | `docs/词表与契约.md` | 本文档、AI 导航 | `tools/sync_contracts.py --check`、headless boot |
| 新增关键决策事件 | `docs/词表与契约.md` | 本文档、Analytics 文档 | `tools/sync_contracts.py --check` |
| 调整录制开关 | `settings.gd`、`replay.gd` | 本文档、Settings 文档 | headless boot |
| 接入落盘 / 摘要对照 | `replay.gd`、`client/tools/replay_runner.gd` | 本文档、测试策略、CI 规划 | L1 + L2 + L3 |
| 接入黄金回放 | `client/tests/replays/` 与工具脚本 | 本文档、测试策略 | `capture-golden-replay`、L3 replay runner |
| 调整 replay 文件 schema | `replay.gd`、`client/tools/replay_smoke.gd` | 本文档、测试策略、F8 工作包 | `python tools/godot_bridge.py --project client replay-smoke` |
| 调整 runner diff 规则 | `client/tools/replay_runner.gd`、`tools/godot_bridge.py` | 本文档、测试策略、F8 工作包 | `python tools/godot_bridge.py --project client replay-runner` |
| 调整 gameplay 输入录制 | `player.gd`、`gameplay_run_loop.gd`、`level_up_panel.gd`、`pause_menu.gd`、`ui_manager.gd` | 本文档、Gameplay Runtime、测试策略、F8 工作包 | `python tools/godot_bridge.py --project client replay-input-smoke` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 进入游戏未开始录制 | `Settings.gameplay.record_replays` 是否开启；是否通过 `GameState.change_state(PLAYING)` 进入 |
| 输入记录失败 | action 是否登记在 `docs/词表与契约.md` 和 `_contracts.json` |
| 关键决策记录失败 | event 是否登记为 analytics event |
| 回放不可重现 | 是否有业务代码绕过 `RNG` / `GameClock` 或输入未走 `Replay` |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查、L2 headless boot，以及 `python tools/godot_bridge.py --project client replay-smoke` / `python tools/godot_bridge.py --project client replay-runner`；改 gameplay 输入录制追加 `python tools/godot_bridge.py --project client replay-input-smoke`；改首条 golden 时追加 `python tools/godot_bridge.py --project client capture-golden-replay` 和 `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_basic_run.replay --rerun-runtime-summary`。
- 后续引入 GUT 后，`Replay` 需要覆盖录制开始 / 停止、action 校验、event 校验、设置关闭清空、缓冲丢弃计数和同 seed 录制字段稳定。
- 当前 `.replay` 文件 roundtrip 已由 `replay-smoke` 覆盖，summary diff、输入播放和稳定帧样本 diff 首片由 `replay-runner` 覆盖，`golden_basic_run.replay` 覆盖首条真实 `GameplayRunLoop` 运行时摘要；扩展全量帧级 L3 后必须补更多逐帧黄金回放样例；有意改变确定性行为时才重录黄金回放并在 commit message 注明影响。

## 迁移 / 兼容

当前 `.replay` 文件 envelope 版本为 1。未来格式变化必须提升 `file_schema_version`，并在读取时提供兼容读取或明确旧回放失效策略；不能把玩家续局 `run` 存档和回放文件混成同一格式。

## 相关文档

- `docs/游戏设计文档.md` §9.9 / §9.18
- `docs/词表与契约.md` action 与 analytics event 段落
- `docs/测试策略.md`
- `docs/代码/rng.md`
- `docs/代码/game_clock.md`
- `docs/代码/game_state.md`
- `docs/代码/analytics.md`
