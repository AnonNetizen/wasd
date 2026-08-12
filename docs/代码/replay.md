# Replay 模块文档

> 权威范围：本页只记录该模块的公共契约、可观察行为、schema、所有权与依赖边界；私有实现和逐测试记录不进入本文档。

## 职责

- `Replay` 负责记录一局的确定性回放输入：主 seed、游戏 tick / time、`InputService` 最终归一化 intent、关键决策事件和启动上下文。
- 输入 action 必须来自 `docs/词表与契约.md`，并通过 `client/scripts/contracts/actions.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- 关键决策事件当前复用已登记的 `analytics_events`，例如奖励选择、等级进展、拾取、道具使用等事件；需要新的事件名时先改词表。
- F8 已提供 `.replay` 文件 envelope、`user://replays/` 落盘 / 读取、稳定摘要、`replay-smoke` roundtrip、`replay-runner` 摘要 diff、`client/tests/replays/golden_basic_run.replay`、`golden_pause_resume.replay`、`golden_full_death.replay` 与 `golden_reward_choice.replay` 的运行时摘要 + 稳定帧样本 golden baseline、gameplay 输入录制首片，以及 `replay-runner --rerun-runtime-summary` 的输入播放 / runtime event 播放 / 帧样本 diff 首片；暂不做全量逐帧状态 diff。
- ADR #165 后每颗玩家弹丸固定消耗一次 `RNG.combat` 并独立抽取扩散角，零扩散也不跳过；震屏只使用 `RNG.camera_fx`，开关震屏不得改变弹道或玩家玩法位置。
- ADR #166 的难度结果继续保留在 `run_end` decision；黄金运行时摘要只比较稳定的 `difficulty_level`、`enemy_health_multiplier`、`enemy_damage_multiplier`。`difficulty_time` 会受暂停 UI 与异步过渡的真实帧调度影响，不作为跨进程 golden 字段。
- ADR #170 后敌人显式攻击、爆猎者连锁和玩家击退都由现有输入、`GameClock` 与运行时数据确定，不新增 replay event 或 RNG。爆炸击杀普通敌人的掉落 RNG 按 `runtime_spawn_serial` 稳定顺序消费。
- ADR #188 曾将 Replay 升至 v5，记录局内 Gear Mod 与意识核直接完成语义。
- ADR #189 将 Replay 升至 v6：`context.content_availability` 保存开局冻结的英雄、Gear Mod 与敌人可用池；播放只消费该快照并忽略本机 Meta。旧 Replay v5 明确不兼容且不迁移。
- ADR #193 将 Replay 升至 v7：`run_end` 使用无等级 Gear Mod 实例语义，data fingerprint 纳入规范化 Gear Mod 玩法数据；旧 Replay v6 精确拒绝且不迁移。
- ADR #194 将 Replay 升至 v8：新增严格 `gear_mod_placement` 决策，指纹纳入 7×7 棋盘与当时的 Mod 类型行为。
- ADR #196 将 Replay 升至 v9：指纹纳入 skills v3 programs、Gear Mod v6 components、统一效果契约、掉落 / 奖励池与精确 `mod_environment`；旧 Replay v8 保持源文件但拒绝播放，不迁移。
- ADR #199 将 Replay 升至 v10：新增严格 `teleport_choice` 成功 / 取消语义；runner 在原始交互输入之后注入选择，拒绝来源站、候选或当前选择状态不一致的播放，并在生成摘要前有界等待异步淡出 / 提交 / 淡入事务结束，复核最终 `PLAYING`、目标模块和落点。旧 Replay v9 原文件保留但拒绝播放，不迁移；四条黄金回放已按新 assignment、map hash 与 data fingerprint 重捕获并复跑。
- 任何录制只要 `dropped_input_events` 或 `dropped_decision_events` 大于 0，就只可作为内存诊断结果，不得保存或加载为可播放回放；`stop_recording()` 仍返回保留精确丢弃计数的录制快照。
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
| `client/tests/replays/golden_basic_run.replay` | F8 首条已入库 golden replay；当前覆盖固定 seed、原始 `interact` 打开目的地面板、随后注入 `teleport_choice`、非零淡出入完成及运行时摘要 / 稳定帧样本 |
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
| 需要持久化 | 调用方把无事件丢弃的完整录制写入 `user://replays/<name>.replay`；文件 envelope 包含 schema、game version、data fingerprint、recording hash 和稳定摘要。任一丢弃计数大于 0 时返回空路径并写入 `last_error()` | `save_recording()` / `replay_saved` |
| 需要读取 / 对照 | runner 读取 `.replay` envelope，先拒绝任一丢弃计数大于 0 的不完整录制，再校验 schema 与 recording hash 并比较 summary；可选 expectation JSON 或 `--rerun-runtime-summary` 会按 replay seed 启动 `GameplayRunLoop`，经 `InputService` playback override 播放 `input_events` 并比较运行时摘要 | `load_replay_file()` / `load_recording()` / `replay-runner` |
| 关闭录制设置 | 清空当前内存录制并停止接受新事件 | `set_enabled(false)` / `recording_cleared` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `start_recording(context = {})` | 启动上下文 | `bool` | 关闭或已录制时返回 `false` |
| `stop_recording(reason = "")` | 停止原因 | `Dictionary` | 未录制时返回空字典；成功后发 `replay_recorded` 埋点 |
| `record_input_action(action_name, pressed, strength = 1.0, participant_id = "player_0")` | action、按下状态、被忽略的旧 strength、参与者 | `bool` | deprecated bool 兼容包装；转交 `record_input_value()`，gameplay 不直接调用 |
| `record_input_value(action_name, value, participant_id = "player_0")` | action、`bool` 或 `Vector2`、参与者 | `bool` | v10 规范入口；只接受已登记 action，含四技能与冲刺；Vector2 会归一化并保存为 `[x, y]` |
| `record_input_event(event, action_names, participant_id = "")` | 原始 Godot event、候选 action、参与者 | `bool` | 测试 / 旧边界兼容，只转成 bool；正式 gameplay 与 UI 不得调用 |
| `record_decision(event_name, payload = {})` | 关键事件名、payload | `bool` | event 未登记会 `push_error` 并返回 `false` |
| `save_recording(recording = {}, file_name = "")` | 已完成录制、可选文件名 | `String` | 只写入无事件丢弃的完整录制；任一丢弃计数大于 0 时返回空字符串并设置 `last_error()`；文件名会归一化为 `.replay` |
| `load_recording(path)` | `.replay` 路径 | `Dictionary` | 返回录制 payload；文件无效时返回空字典并设置 `last_error()` |
| `load_replay_file(path)` | `.replay` 路径 | `Dictionary` | 仅接受 file / recording schema v10、无事件丢弃的完整录制，并校验 `context.content_availability` 与 `mod_environment`；返回完整 envelope并校验 `recording_hash`，不完整、旧版或未来版本返回空字典并设置错误 |
| `recording_summary(recording)` | 录制 payload | `Dictionary` | 返回 seed、tick/time、事件数量、停止原因等稳定摘要 |
| `current_data_fingerprint()` | 无 | `String` | 基于统一效果契约、skills v3、Gear Mod v6、掉落 / 奖励池与本地玩法环境的稳定指纹 |
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
| `context` | `Dictionary` | `GameState` 进入 `PLAYING` 时传入的上下文；必须包含稳定排序且非空的 `content_availability` 与精确 `mod_environment` |
| `input_events` | `Array[Dictionary]` | action 输入事件 |
| `decision_events` | `Array[Dictionary]` | 关键决策事件 |
| `dropped_input_events` / `dropped_decision_events` | `int` | 缓冲上限丢弃计数；任一大于 0 代表录制不完整，只保留诊断，不得落盘或加载播放 |

F8 首片 `.replay` 文件 envelope：

| 字段 | 类型 | 说明 |
|------|------|------|
| `file_schema_version` | `int` | 文件 envelope 版本，当前为 10 |
| `created_at` | `String` | wall time 诊断字段，不参与玩法判定 |
| `game_version` | `String` | 当前构建 / 设计版本标签，来自 `SaveManager.GAME_VERSION` |
| `data_fingerprint` | `String` | 统一效果数据 / 原语契约、Gear Mod、掉落 / 奖励池和本地玩法环境的稳定 hash，用于拒绝玩法数据基线漂移 |
| `recording_hash` | `String` | 录制 payload 的稳定 hash，读取时强校验 |
| `recording` | `Dictionary` | 上方内存录制结构 |
| `summary` | `Dictionary` | seed、tick/time、事件数量、停止原因和可选 `run_summary` 等 runner 可比较摘要 |

F8 golden replay 额外在 `recording.run_summary` / `summary.run_summary` 中保存稳定运行时摘要：`scenario`、`capture_frames`、`state`、`ui_stack`、`level`、`gold_balance`、`gold_earned_total`、`kills`、`difficulty_level`、`enemy_health_multiplier`、`enemy_damage_multiplier`、`player_moved_right`、`player_aim_direction` 和场景适配的实体字段。`golden_basic_run` 保留活跃敌人 / 子弹 / 掉落数量和核心对象池统计，并覆盖传送选择态到最终落点；`golden_pause_resume` 聚焦 UI 状态，使用 `enemies_present` / `bullets_present` 避免暂停注入等待帧造成的精确实体数量差；`golden_full_death` 使用 `enemies_present` / `bullets_present` 加 `player_defeated`、`game_over_panel_visible`、`run_save_exists` 和 `meta_save_exists` 验证死亡后进入失败页、删除 run 存档且不再写旧局外货币字段；`golden_reward_choice` 使用 `reward_choice_decisions` 和 `reward_choice_applied` 验证 trigger / pool / entry 记录与修正应用。`run_summary.frame_samples` 保存 30 帧间隔的稳定帧样本，字段包括 `frame`、`state`、`ui_stack`、`level`、`gold_balance`、`gold_earned_total`、`kills`、`player_life`、`player_moved_right`、`player_aim_direction`、`weapon_cooldown_ready`、`enemy_types`、`gold_orbs_present`、实体存在性或数量、`active_gold_orbs`；full-death 样本额外记录 `game_over_panel_visible`。逐帧精确子弹数量、精确玩家坐标、`game_tick` / `game_time` / `difficulty_time` 不进入摘要，因为 headless 挂载、暂停 UI 与异步过渡可能造成非语义的帧调度差异；最终传送模块和落点改由 runner 的事务完成校验直接断言。

输入事件字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `String` | 已登记项目 action；当前 canonical 输入为 `move`、`aim` 与离散按钮 action |
| `value_type` | `String` | `bool` 或 `vector2` |
| `value` | `bool` / `Array[float]` | 按钮状态，或 `[x, y]` 最终归一化 intent |
| `tick` / `time` | `int` / `float` | 录制时的游戏 tick / time |
| `participant_id` | `String` | 可选；未来多人 / AIPlayer 预留 |

当前 gameplay 输入使用固定 `participant_id=player_0`。`InputService` 对 `move` / `aim` 记录最终归一化 Vector2，对离散 action 记录 bool，并只在值发生变化时写入，避免每帧重复记录。鼠标瞄准因此可与手柄瞄准使用同一 wire，不记录鼠标坐标或设备来源。`replay-runner --rerun-runtime-summary` 通过 playback override 注入这些 intent，播放期间忽略物理 GUIDE 输入；事件可带 `frame` 字段，runner 优先按 frame 调度，以覆盖暂停时 `GameClock.tick` 冻结的场景。

`context.content_availability` 的三个数组分别冻结英雄、Gear Mod 和敌人池；`context.mod_environment` 精确记录有序 `{id,version,gameplay_hash}`。捕获与正式开局都在任何池消费 RNG 前生成快照；播放时先校验本机不可变包环境，再由 `GameplayRunLoop` 使用回放内快照，禁止读取或提交本机 `ContentUnlockSystem` Meta，因此同一 v10 Replay 不受本机解锁进度影响。

Gear Mod fingerprint payload 由 `DataLoader` 提供规范化副本，包含 schema v6、7×7 棋盘 / 初始掩码、拾取配置、奖励池 / contribution 有序数组、每个 Mod 的 id / components / programs / 默认开放语义，以及掉落表有序行。统一效果数据、Registry 契约与 skills v3 programs 同样进入指纹；名称、描述、稀有度、图标、`placement_sfx_id` 和本地化等展示 / 媒体字段不参与玩法指纹。

`gear_mod_placement` 是空间配置语义决策。成功 payload 精确为 `{instance_id,mod_id,outcome:"placed",x,y}`，取消精确为 `{instance_id,mod_id,outcome:"cancelled"}`，不得携带多余键。录制时同 tick 的原始 `ui_confirm` / `ui_back` 触发边由该决策替换；容量裁剪在归并后执行，满 4096 条时也不能误丢最老输入。runner 按记录时间对当前 pending transaction 调用正式确认 / 取消 API，不播放鼠标轨迹；实例不存在、Mod 不同或目标非法都立即报告 replay divergence。

`teleport_choice` 是传送网络语义决策，不是 GameState。成功 payload 精确为 `{outcome:"teleported",source_station_id,destination_station_id}`，取消精确为 `{outcome:"cancelled",source_station_id}`，不得携带多余键。录制时同 tick 的 `ui_confirm` / `ui_back` 触发边由该决策替换，但原始 `interact` 输入仍先驱动正式来源站交互；runner 随后调用 `GameplayRunLoop.apply_replay_teleport_choice()` 注入语义选择。传送面板和正式非零淡出入始终处于 `PLAYING`，simulation / `GameClock` 继续随回放帧推进；面板与 pending 事务通过 `InputService` owner capture 屏蔽玩家 gameplay intent，成功 decision 在全黑帧原子提交完成后立即记录，保证淡入期间死亡也不会丢失已经发生的传送。若到摘要边界仍在过渡，则最多再等待 180 个 process frame，并用 `replay_teleport_choice_completed()` 复核最终状态、模块与落点。当前状态不是 `PLAYING`、玩家已死亡、pending 来源或面板不一致、目标不在当下 visited-only 候选、来源变为危险、placement 消失或落点不可走时必须立即报告 replay divergence，不得移动玩家或修改候选。

`runtime_events` 是 F8 golden 工具层事件字段，当前用于 `golden_basic_run` 的 `prepare_teleporter_choice`、`golden_full_death` 的 `defeat_player`，以及 `golden_reward_choice` 的 `request_reward_choice` / `choose_reward_index`。runner 按 `frame` 调度：传送 fixture 只通过正式 Player / ModuleWorld 流送边界预先访问两站并回到来源，后续仍由原始 `interact` 和正式选择 API 驱动；full-death 通过 `Combat.apply_damage()` 触发正式 Player 受伤 / 死亡 / GameState / GameOverPanel 路径；reward choice 调用正式请求与 `RewardChoicePanel.choose_index()`。业务脚本不读取该字段，也不为测试场景添加分支。full-death capture / runner 会在场景前备份 `DEFAULT_SLOT` 的 run/meta payload，临时清空以获得稳定失败页摘要，场景结束后恢复原 payload，避免 headless 工具永久改写本机默认存档。后续若扩展 runtime event，必须继续走正式系统边界，不能直接伪造 `GameState` 或结算数据。

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
- 增加黄金回放：`golden_basic_run.replay`、`golden_pause_resume.replay`、`golden_full_death.replay` 与 `golden_reward_choice.replay` 已由 `golden_replay_capture.gd` 生成并入库；权威全量入口为 `python tools/godot_bridge.py --project client replay-regression`，按文件名排序后在一个隔离 `user://` 的 Godot 进程中串行对照运行时摘要与稳定帧样本。单文件 `replay-runner --replay-file ... --rerun-runtime-summary` 只用于定位。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增可录制 action | `docs/词表与契约.md` | 本文档、AI 导航 | `tools/sync_contracts.py --check`、headless boot |
| 新增关键决策事件 | `docs/词表与契约.md` | 本文档、Analytics 文档 | `tools/sync_contracts.py --check` |
| 调整录制开关 | `settings.gd`、`replay.gd` | 本文档、Settings 文档 | headless boot |
| 接入落盘 / 摘要对照 | `replay.gd`、`client/tools/replay_runner.gd` | 本文档、测试策略、CI 规划 | L1 + L2 + L3 |
| 接入黄金回放 | `client/tests/replays/` 与工具脚本 | 本文档、测试策略 | `capture-golden-replay`、L3 replay runner |
| 调整 replay 文件 schema | `replay.gd`、`client/tools/replay_smoke.gd` | 本文档、测试策略、F8 工作包 | `python tools/godot_bridge.py --project client replay-smoke` |
| 调整 runner diff / 批处理规则 | `client/tools/replay_runner.gd`、`tools/godot_bridge.py` | 本文档、测试策略、F8 工作包 | 单文件 runner + `python tools/godot_bridge.py --project client replay-regression` |
| 调整 gameplay 输入录制或 `teleport_choice` 注入 | `input_service.gd`、`replay.gd`、`replay_runner.gd`、`gameplay_run_loop.gd` | 本文档、InputService / Gameplay Runtime、测试策略、F8 工作包 | `input-smoke` + `replay-input-smoke` + `teleporter-smoke` + 四条 replay runner |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 进入游戏未开始录制 | `Settings.gameplay.record_replays` 是否开启；是否通过 `GameState.change_state(PLAYING)` 进入 |
| 输入记录失败 | action 是否登记在 `docs/词表与契约.md` 和 `_contracts.json` |
| 关键决策记录失败 | event 是否登记为 analytics event |
| 回放不可重现 | 是否有业务代码绕过 `RNG` / `GameClock` / `InputService`；播放时物理 GUIDE context 是否仍在污染 intent |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查、L2 headless boot，以及 `python tools/godot_bridge.py --project client replay-smoke` / `python tools/godot_bridge.py --project client replay-runner`；改 gameplay 输入录制追加 `replay-input-smoke`。改 golden 时追加四种 capture 命令与一次 `replay-regression`；默认 fail-fast，需要完整失败集合才追加 `--keep-going`。`--allow-data-fingerprint-mismatch` 仅供诊断，不能作为权威通过。
- 后续引入 GUT 后，`Replay` 需要覆盖录制开始 / 停止、action 校验、event 校验、设置关闭清空、缓冲丢弃计数和同 seed 录制字段稳定。
- 当前 `.replay` 文件 v10 roundtrip、placement / `teleport_choice` 严格 payload、内容池 / mod environment 校验、恰好 `MAX_DECISION_EVENTS` 可保存并加载的闭区间上界、真实 `MAX_INPUT_EVENTS + 1` / `MAX_DECISION_EVENTS + 1` 溢出诊断与不完整录制保存 / 加载拒绝，以及旧 v9 / 未来版本拒绝由 `replay-smoke` 覆盖；summary diff、四技能 / 冲刺输入播放、组合 / placement / teleport 决策与稳定帧样本 diff 由 `replay-runner` 覆盖。传送还须断言成功、取消可重放，错误来源 / 目标与候选状态产生 divergence，语义选择在原始交互输入之后注入。批量入口每条之间释放输入、Replay、UI、RunLoop 和对象池状态并回到 `MAIN_MENU`。专项 smoke 直接覆盖棋盘、效果 Runtime、拾取 / 传送事务和 Godot Control 鼠标命中；golden 只记录语义选择，不记录原始鼠标轨迹，不得冒充这些行为的 L3 证据。

## 迁移 / 兼容

当前 `.replay` 文件 envelope 与内存 recording schema 都为 10，加载器只接受 v10。旧 v9、缺失版本和未来未知版本都返回空结果、写入明确 `last_error()` 并保持源文件不变；不提供迁移。录制 context / `run_start` decision 必须带 `main_hero_id`、`sub_hero_id`、difficulty profile id / coefficient、`content_availability` 与精确 `mod_environment`。环境缺包、版本或 gameplay hash 不匹配时阻止播放并保留原文件。7×7 assignment、三座传送台与目标角落由同 seed、数据指纹和 `RNG.world` 重建；弹道随机、Gear Mod 掉落和未锁定效果计划由运行时按固定 RNG 子流重算，已提交放置与传送选择由语义 decision 驱动。Gear Mod 棋盘、地面物、传送选择恢复和 Runtime 快照属于 Run v20 而不是 replay 输入字段；不能混合两种格式。游戏标签为 v1.19，Meta 保持 v4。

## 相关文档

- `docs/游戏设计文档.md` §9.9 / §9.18
- `docs/词表与契约.md` action 与 analytics event 段落
- `docs/测试策略.md`
- `docs/代码/rng.md`
- `docs/代码/game_clock.md`
- `docs/代码/game_state.md`
- `docs/代码/analytics.md`
- `docs/代码/input_service.md`
- `docs/代码/content_unlock_system.md`
