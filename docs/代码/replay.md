# Replay 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Replay` autoload 的代码契约权威；改录制格式、公共 API、signal、确定性依赖、落盘策略或测试义务时必须同步本文档。

## 职责

- `Replay` 负责记录一局的确定性回放输入：主 seed、游戏 tick / time、`InputService` 最终归一化 intent、关键决策事件和启动上下文。
- 输入 action 必须来自 `docs/词表与契约.md`，并通过 `client/scripts/contracts/actions.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- 关键决策事件当前复用已登记的 `analytics_events`，例如奖励选择、等级进展、拾取、道具使用等事件；需要新的事件名时先改词表。
- F8 已提供 `.replay` 文件 envelope、`user://replays/` 落盘 / 读取、稳定摘要、`replay-smoke` roundtrip、`replay-runner` 摘要 diff、`client/tests/replays/golden_basic_run.replay`、`golden_pause_resume.replay`、`golden_full_death.replay` 与 `golden_reward_choice.replay` 的运行时摘要 + 稳定帧样本 golden baseline、gameplay 输入录制首片，以及 `replay-runner --rerun-runtime-summary` 的输入播放 / runtime event 播放 / 帧样本 diff 首片；暂不做全量逐帧状态 diff。
- ADR #165 后每颗玩家弹丸固定消耗一次 `RNG.combat` 并独立抽取扩散角，零扩散也不跳过；震屏只使用 `RNG.camera_fx`，开关震屏不得改变弹道或玩家玩法位置。输入 wire format 未变，因此 Replay 保持 v3；后坐力落地时直接重录四条黄金基线，不增加旧黄金兼容。
- ADR #166 后 Replay 仍保持 v3：输入 wire 与调度时钟不变，`run_end` decision 和黄金运行时摘要新增 `difficulty_time`、`difficulty_level`、`enemy_health_multiplier`、`enemy_damage_multiplier`。这些值来自 `DifficultyProgression`，不以 `GameClock.now()` 代替；四条黄金基线因数据指纹和摘要变化重录。
- ADR #170 后 Replay 仍保持 v3：敌人显式攻击、爆猎者连锁和玩家击退都由现有输入、`GameClock` 与运行时数据确定，不新增 replay event 或 RNG。爆炸击杀普通敌人的掉落 RNG 按 `runtime_spawn_serial` 稳定顺序消费；数据指纹与运行时摘要变化，因此四条黄金回放全部重录并重跑。
- `Replay` 受 `Settings.gameplay.record_replays` 控制；关闭后会清空当前内存录制并拒绝新录制。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 接入玩家输入录制 | 本文档公共 API 与 `docs/词表与契约.md` action 段落 |
| 记录奖励选择 / 拾取等关键决策 | `record_decision()` 与 `client/scripts/contracts/analytics_events.gd` |
| 改自动录制时机 | 本文档运行流程、`docs/代码/game_state.md` |
| 做 `.replay` 文件落盘 | 本文档迁移 / 兼容段落、GDD §9.9、后续 SaveManager 边界 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/replay.gd` | `Replay` autoload 脚本 |
| `client/tools/replay_smoke.gd` | F8 replay 文件 roundtrip smoke，覆盖最小录制、保存、读取、摘要对比和 data fingerprint |
| `client/tools/replay_runner.gd` | F8 replay summary diff runner，读取 `.replay`、校验 envelope，并比较内嵌 summary、外部 expectation JSON 或重跑运行时摘要 |
| `client/tools/replay_input_smoke.gd` | F8 gameplay 输入录制 smoke，启动真实 `GameplayRunLoop` 并确认移动 / 瞄准 / pause / ui_back 写入 `Replay.input_events` |
| `client/tools/golden_replay_capture.gd` | F8 golden capture 工具，固定 seed 启动真实 `GameplayRunLoop` 并生成 `golden_basic_run.replay` / `golden_pause_resume.replay` / `golden_full_death.replay` / `golden_reward_choice.replay` |
| `client/tests/replays/golden_basic_run.replay` | F8 首条已入库 golden replay；当前覆盖固定 seed 的运行时摘要与稳定帧样本 |
| `client/tests/replays/golden_pause_resume.replay` | F8 第二条已入库 golden replay；覆盖 pause 输入打开暂停菜单、`ui_back` 恢复运行、`ui_stack` 清空和稳定帧样本 |
| `client/tests/replays/golden_full_death.replay` | F8 第三条已入库 golden replay；覆盖工具层 runtime event 触发正式 Combat 死亡路径、GameOverPanel、run 存档删除和失败页摘要 |
| `client/tests/replays/golden_reward_choice.replay` | F8 第四条已入库 golden replay；测试 harness 显式请求 3 个通用奖励候选，覆盖进入 `REWARD_CHOICE`、记录 `reward_choice` decision、选择后回到 `PLAYING` 并应用修正；等级提升不会自动触发它 |
| `client/scripts/contracts/actions.gd` | 自动生成的项目 action 常量 |
| `client/scripts/autoload/input_service.gd` | 录制归一化 bool / Vector2 intent，并在播放时接收 override 注入 |
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
| 输入发生 | `InputService` 只在最终归一化值变化时记录已登记 action：按钮用 bool，移动 / 鼠标或手柄瞄准用 Vector2；物理 GUIDE event、设备类型和 raw strength 不进入 replay | `record_input_value()` / `input_recorded` |
| 关键决策 | 调用方记录已登记 analytics event 与 payload | `record_decision()` / `decision_recorded` |
| 进入 `GAME_OVER` / `RESULT` / `MAIN_MENU` | 结束内存录制，补齐结束 tick/time 与丢弃计数，并发出本地埋点 | `stop_recording()` / `recording_stopped` |
| 需要持久化 | 调用方把完成的录制写入 `user://replays/<name>.replay`；文件 envelope 包含 schema、game version、data fingerprint、recording hash 和稳定摘要 | `save_recording()` / `replay_saved` |
| 需要读取 / 对照 | runner 读取 `.replay` envelope，校验 schema 与 recording hash，比较 summary；可选 expectation JSON 或 `--rerun-runtime-summary` 会按 replay seed 启动 `GameplayRunLoop`，经 `InputService` playback override 播放 `input_events` 并比较运行时摘要 | `load_replay_file()` / `load_recording()` / `replay-runner` |
| 关闭录制设置 | 清空当前内存录制并停止接受新事件 | `set_enabled(false)` / `recording_cleared` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `start_recording(context = {})` | 启动上下文 | `bool` | 关闭或已录制时返回 `false` |
| `stop_recording(reason = "")` | 停止原因 | `Dictionary` | 未录制时返回空字典；成功后发 `replay_recorded` 埋点 |
| `record_input_action(action_name, pressed, strength = 1.0, participant_id = "player_0")` | action、按下状态、被忽略的旧 strength、参与者 | `bool` | deprecated bool 兼容包装；转交 `record_input_value()`，gameplay 不直接调用 |
| `record_input_value(action_name, value, participant_id = "player_0")` | action、`bool` 或 `Vector2`、参与者 | `bool` | v3 规范入口；只接受已登记 action，含四技能与冲刺；Vector2 会归一化并保存为 `[x, y]` |
| `record_input_event(event, action_names, participant_id = "")` | 原始 Godot event、候选 action、参与者 | `bool` | 测试 / 旧边界兼容，只转成 bool；正式 gameplay 与 UI 不得调用 |
| `record_decision(event_name, payload = {})` | 关键事件名、payload | `bool` | event 未登记会 `push_error` 并返回 `false` |
| `save_recording(recording = {}, file_name = "")` | 已完成录制、可选文件名 | `String` | 写入 `user://replays/`，返回路径；文件名会归一化为 `.replay` |
| `load_recording(path)` | `.replay` 路径 | `Dictionary` | 返回录制 payload；文件无效时返回空字典并设置 `last_error()` |
| `load_replay_file(path)` | `.replay` 路径 | `Dictionary` | 仅接受 file / recording schema v3；返回完整 envelope并校验 `recording_hash`，旧版或未来版本返回空字典并设置错误 |
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
| `file_schema_version` | `int` | 文件 envelope 版本，当前为 3 |
| `created_at` | `String` | wall time 诊断字段，不参与玩法判定 |
| `game_version` | `String` | 当前构建 / 设计版本标签，来自 `SaveManager.GAME_VERSION` |
| `data_fingerprint` | `String` | 当前 contracts + schema counts 的稳定 hash，用于提示数据基线变化 |
| `recording_hash` | `String` | 录制 payload 的稳定 hash，读取时强校验 |
| `recording` | `Dictionary` | 上方内存录制结构 |
| `summary` | `Dictionary` | seed、tick/time、事件数量、停止原因和可选 `run_summary` 等 runner 可比较摘要 |

F8 golden replay 额外在 `recording.run_summary` / `summary.run_summary` 中保存稳定运行时摘要：`scenario`、`capture_frames`、`state`、`ui_stack`、`level`、`gold_balance`、`gold_earned_total`、`kills`、`difficulty_time`、`difficulty_level`、`enemy_health_multiplier`、`enemy_damage_multiplier`、`player_moved_right`、`player_aim_direction` 和场景适配的实体字段。`golden_basic_run` 保留活跃敌人 / 子弹 / 掉落数量和核心对象池统计；`golden_pause_resume` 聚焦 UI 状态，使用 `enemies_present` / `bullets_present` 避免暂停注入等待帧造成的精确实体数量差；`golden_full_death` 使用 `enemies_present` / `bullets_present` 加 `player_defeated`、`game_over_panel_visible`、`run_save_exists` 和 `meta_save_exists` 验证死亡后进入失败页、删除 run 存档且不再写旧局外货币字段；`golden_reward_choice` 使用 `reward_choice_decisions` 和 `reward_choice_applied` 验证 trigger / pool / entry 记录与修正应用。`run_summary.frame_samples` 保存 30 帧间隔的稳定帧样本，字段包括 `frame`、`state`、`ui_stack`、`level`、`gold_balance`、`gold_earned_total`、`kills`、`player_life`、`player_moved_right`、`player_aim_direction`、`weapon_cooldown_ready`、`enemy_types`、`gold_orbs_present`、实体存在性或数量、`active_gold_orbs`；full-death 样本额外记录 `game_over_panel_visible`。逐帧精确子弹数量和精确玩家坐标暂不进入帧样本，因为发射 / 移动采样时机可能出现 1 帧级差异；`game_tick` / `game_time` 不进入该摘要，因为 headless 工具挂载时机可能造成少量 tick 差；玩家可见用时只使用 `difficulty_time`。

输入事件字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `String` | 已登记项目 action；当前 canonical 输入为 `move`、`aim` 与离散按钮 action |
| `value_type` | `String` | `bool` 或 `vector2` |
| `value` | `bool` / `Array[float]` | 按钮状态，或 `[x, y]` 最终归一化 intent |
| `tick` / `time` | `int` / `float` | 录制时的游戏 tick / time |
| `participant_id` | `String` | 可选；未来多人 / AIPlayer 预留 |

当前 gameplay 输入使用固定 `participant_id=player_0`。`InputService` 对 `move` / `aim` 记录最终归一化 Vector2，对离散 action 记录 bool，并只在值发生变化时写入，避免每帧重复记录。鼠标瞄准因此可与手柄瞄准使用同一 wire，不记录鼠标坐标或设备来源。`replay-runner --rerun-runtime-summary` 通过 playback override 注入这些 intent，播放期间忽略物理 GUIDE 输入；事件可带 `frame` 字段，runner 优先按 frame 调度，以覆盖暂停时 `GameClock.tick` 冻结的场景。

`runtime_events` 是 F8 golden 工具层事件字段，当前用于 `golden_full_death` 的 `defeat_player`，以及 `golden_reward_choice` 的 `request_reward_choice` / `choose_reward_index`。runner 按 `frame` 调度这些事件：full-death 在工具脚本内通过 `Combat.apply_damage()` 触发正式 Player 受伤 / 死亡 / GameState / GameOverPanel 路径；reward choice 调用 `GameplayRunLoop.request_reward_choice()` 发起正式请求，再调用 `RewardChoicePanel.choose_index()` 触发正式选择路径。业务脚本不读取该字段，也不为测试场景添加分支。full-death capture / runner 会在场景前备份 `DEFAULT_SLOT` 的 run/meta payload，临时清空以获得稳定失败页摘要，场景结束后恢复原 payload，避免 headless 工具永久改写本机默认存档。后续若扩展 runtime event，必须继续走正式系统边界，不能直接伪造 `GameState` 或结算数据。

关键决策事件字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `event` | `String` | 已登记 analytics event |
| `payload` | `Dictionary` | 决策上下文，例如候选 id、选择结果或当时属性快照 |
| `tick` / `time` | `int` / `float` | 录制时的游戏 tick / time |

## 依赖

- 上游依赖：`RNG` 提供主 seed；`GameClock` 提供 tick / time；`GameState` 提供自动录制时机；`Settings` 提供录制开关；`DataLoader` 提供 action / event 契约校验；`InputService` 提供最终 intent；`Analytics` 接收 `replay_recorded` 本地事件。
- 下游调用方：`InputService` 写入 gameplay intent，奖励选择等系统写关键 decision；黄金 runner 经 `InputService` 播放，不直接伪造 GUIDE 物理事件。
- 禁止依赖：业务系统不得直接读写 `.replay` 文件；不得绕过 `Replay` 自建输入录制；不得用非确定时间源参与回放内容。

## 扩展点

- 接入输入：新增输入只允许由 `InputService` 记录生成 action 和归一化 bool / Vector2 值；gameplay、UI 和 GUIDE 不得各自重复写回放。
- 接入奖励选择：trigger id、pool id、候选 id、候选数量和玩家选择通过 `record_decision()` 写入；`luck` 不进入结果判定。
- 增加真实重放：后续 `play(file)` / 对照 diff 应只消费录制内容，不读取业务模块私有状态；当前 `replay-smoke` 覆盖文件 roundtrip，`replay-runner` 覆盖 envelope / summary diff、输入播放首片和首条运行时摘要 golden。
- 增加黄金回放：`golden_basic_run.replay`、`golden_pause_resume.replay`、`golden_full_death.replay` 与 `golden_reward_choice.replay` 已由 `golden_replay_capture.gd` 生成并入库，可通过对应 `replay-runner --replay-file ... --rerun-runtime-summary` 对照运行时摘要与稳定帧样本；后续在更多运行时能力存在后再补 `golden_relic_synergy` 等场景。

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
| 调整 gameplay 输入录制 | `input_service.gd`、`replay.gd`、`replay_runner.gd` | 本文档、InputService / Gameplay Runtime、测试策略、F8 工作包 | `input-smoke` + `replay-input-smoke` + 四条 replay runner |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 进入游戏未开始录制 | `Settings.gameplay.record_replays` 是否开启；是否通过 `GameState.change_state(PLAYING)` 进入 |
| 输入记录失败 | action 是否登记在 `docs/词表与契约.md` 和 `_contracts.json` |
| 关键决策记录失败 | event 是否登记为 analytics event |
| 回放不可重现 | 是否有业务代码绕过 `RNG` / `GameClock` / `InputService`；播放时物理 GUIDE context 是否仍在污染 intent |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查、L2 headless boot，以及 `python tools/godot_bridge.py --project client replay-smoke` / `python tools/godot_bridge.py --project client replay-runner`；改 gameplay 输入录制追加 `python tools/godot_bridge.py --project client replay-input-smoke`；改 golden 时追加 `capture-golden-replay`、`capture-golden-replay --golden-scenario golden_pause_resume`、`capture-golden-replay --golden-scenario golden_full_death`、`capture-golden-replay --golden-scenario golden_reward_choice` 以及四条 checked-in replay 的 `replay-runner --replay-file ... --rerun-runtime-summary`。
- 后续引入 GUT 后，`Replay` 需要覆盖录制开始 / 停止、action 校验、event 校验、设置关闭清空、缓冲丢弃计数和同 seed 录制字段稳定。
- 当前 `.replay` 文件 v3 roundtrip 与旧版 / 未来版本拒绝由 `replay-smoke` 覆盖，summary diff、四技能 / 冲刺输入播放、组合决策、runtime event 和稳定帧样本 diff 由 `replay-runner` 覆盖。四条黄金回放覆盖两种主英雄、四技能、冲刺、暂停 / 恢复、死亡防御状态和通用奖励选择；有意改变确定性行为时才重录并在提交说明中注明影响。

## 迁移 / 兼容

当前 `.replay` 文件 envelope 与内存 recording schema 都为 3，加载器只接受 v3。旧版、缺失版本和未来未知版本都返回空结果、写入明确 `last_error()` 并保持源文件不变；不提供迁移。录制 context / `run_start` decision 必须带 `main_hero_id` 与 `sub_hero_id`，四技能和冲刺使用当前规范 action。弹道随机由运行时按固定 `RNG.combat` 消耗重算；Player 后坐 / 敌人击退、金币、未完成奖励选择、敌人攻击阶段 / armed / 生成序号、精确出生倍率与世界事件事务属于 Run v9 而不是 replay 输入字段。Replay 只在 decision / `run_end` / summary 保留当前稳定摘要，不能把两种格式混合。

## 相关文档

- `docs/游戏设计文档.md` §9.9 / §9.18
- `docs/词表与契约.md` action 与 analytics event 段落
- `docs/测试策略.md`
- `docs/代码/rng.md`
- `docs/代码/game_clock.md`
- `docs/代码/game_state.md`
- `docs/代码/analytics.md`
- `docs/代码/input_service.md`
