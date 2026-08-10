# FormalClientBoot 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式客户端 F1 启动骨架的代码契约权威；改启动场景、项目入口、节点结构或验证方式时必须同步本文档、`client/README.md`、`docs/AI导航.md` 与 `docs/AI记忆/current_state.json`。

## 职责

- 负责提供完整项目 `client/` 的最小 Godot 启动入口。
- 负责让 F1 阶段可以通过 headless 启动验证。
- F2/F3 期间作为正式客户端 smoke 场景，负责触发 autoload 和数据 schema 启动检查；F4 起在数据校验通过后显示标题界面，并在玩家开始游戏、继续 run 存档、重开、打开设置、打开图鉴或 smoke 模式下编排对应流程。ADR #117 后旧局外升级标题入口和 `meta-smoke` 已删除；ADR #189 后图鉴只从标题菜单进入。
- ADR #157 后负责正式玩家入口的统一加载编排、重入保护、成功激活和失败回退；不负责 `GameplayRunLoop` 内部资源准备细节，也不处理应用冷启动。
- ADR #160 后不负责开发者测试岛的入口、CLI、配装、服务隔离或 runtime 生命周期；测试岛只能直接运行独立 debug scene。
- ADR #195 后正式场景仍预加载生产依赖；smoke runner 路径由 `client/tools/smoke_commands.json` 保存，Bridge 把稳定 command id 转为唯一的 `--test-command <id>`，命中后才由 `_install_dynamic_runner()` 加载。普通启动和单项 smoke 不再解析全部测试脚本。
- 不负责长期主菜单视觉包装、输入重绑定 UI 或业务数据解释。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改正式项目启动场景 | `client/project.godot` 与 `client/scenes/boot/main.tscn` |
| 改启动脚本行为 | `client/scripts/boot/formal_client_boot.gd` |
| 推进下一阶段 autoload | `docs/正式项目工作规划.md` F2 |
| 调试 F4 启动 | `docs/代码/gameplay_runtime.md` |
| 调试开始 / 继续 / 重开加载 | `docs/代码/gameplay_loading.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/project.godot` | Godot 项目配置，`run/main_scene` 指向最小启动场景；当前只适配固定 16:9，默认 viewport 为 1920×1080，窗口拉伸采用 `canvas_items + keep` |
| `client/scenes/boot/main.tscn` | 正式项目最小启动场景 |
| `client/scripts/boot/formal_client_boot.gd` | 启动场景脚本，输出启动日志 |
| `client/scripts/debug/debug_console.gd` | debug/dev_tools 构建才动态加载的调试控制台 |
| `client/scenes/gameplay/gameplay_run_loop.tscn` | F4+ 正式 gameplay runtime 场景，由启动脚本实例化 |
| `client/scenes/ui/title_menu.tscn` | 正常启动后的正式标题菜单场景 |
| `client/scenes/ui/loading_screen.tscn` | 开始 / 继续 / 重开期间的统一全屏加载界面 |
| `client/scenes/ui/settings_panel.tscn` | F7 标题设置面板场景 |
| `client/scenes/ui/codex_panel.tscn` | 标题图鉴场景；三分类与锁定信息保密均由专项 smoke 覆盖 |
| `client/scripts/ui/title_menu.gd` | F4 阶段最小标题界面，通过 `UIManager` 挂载 |
| `client/scripts/ui/loading_screen.gd` | 加载文字刷新与旋转动画诊断 |
| `client/scripts/ui/settings_panel.gd` | F7 设置面板，通过 `UIManager` 叠在标题菜单上 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | F4 数据校验通过后挂载的最小可玩闭环 runtime |
| `client/tools/smoke_commands.json` | smoke command id、runner、FormalBoot setup、隔离、成功 / fatal 与逐命令精确 allowlist 的单一描述表 |
| `client/tools/save_manager_smoke.gd` | `save-smoke` command 下挂载的 F5 存档可靠性 smoke |
| `client/tools/settings_smoke.gd` | `settings-smoke` command 下挂载的 F7 设置持久化 smoke |
| `client/tools/content_progression_smoke.gd` | `content-progression-smoke` command 下验证解锁规则、Meta / Run、冻结池与长期进度隔离 |
| `client/tools/codex_smoke.gd` | `codex-smoke` command 下验证标题入口、三分类、锁定隐私、语言与焦点返回 |
| `client/tools/gear_mod_smoke.gd` | `gear-mod-smoke` command 下挂载的 F11 装备 Mod smoke |
| `client/tools/l1_smoke.gd` | `l1-smoke` command 下挂载的 F8 临时 L1 基础设施 smoke |
| `client/tools/f9_demo_smoke.gd` | `f9-demo-smoke` command 下挂载的 F9 Demo / FEA-12 机关 smoke |
| `client/tools/loading_smoke.gd` | `loading-smoke` command 下覆盖真实开始 / 继续 / 重开、重入保护，以及四类缺必需节点时完整 Boot 失败回退与 runtime / pool 清理 |
| `client/tools/replay_smoke.gd` | `replay-smoke` command 下挂载的 F8 Replay 文件 roundtrip smoke |
| `client/tools/replay_runner.gd` | `--replay-runner` 下按需动态加载的 F8 Replay summary diff runner，可读取一个或多个 `.replay` 和可选 expectation JSON |
| `client/tools/replay_input_smoke.gd` | `replay-input-smoke` command 下挂载的 F8 gameplay 输入录制 smoke |
| `client/tools/input_smoke.gd` | `input-smoke` command 下挂载的 GUIDE / InputService 集成 smoke |
| `client/tools/golden_replay_capture.gd` | `--capture-golden-replay` 下挂载的 F8 golden capture 工具，固定 seed 生成 `golden_basic_run.replay`、`golden_pause_resume.replay`、`golden_full_death.replay` 或 `golden_reward_choice.replay` |
| `client/tools/perf_probe.gd` | `--perf-probe` 下挂载的 F8 轻量性能 / 平衡采样 |
| `client/tools/debug_tools_smoke.gd` | `debug-tools-smoke` command 下挂载的调试控制台 / GM 指令 smoke；release descriptor 额外传 `--force-release-debug-tools-off` 模拟 guard |
| `client/README.md` | 正式客户端运行说明 |

## 场景 / 节点结构

```text
FormalClientBoot (Node)
└── GameplayRunLoop (Node2D, instanced from `client/scenes/gameplay/gameplay_run_loop.tscn` while a run is active)

UIManager
└── UIRoot
    ├── TitleMenu (scene; normal boot after data schema passes; shows continue when run.save exists)
    ├── LoadingScreen (scene; start / continue / restart preparation, always-process, input-blocking)
    ├── CodexPanel (scene; title-only, pushed above title menu)
    └── SettingsPanel (scene; pushed above title menu when requested)

FormalClientBoot
└── DebugTestArena (debug/dev_tools only; inherits GameplayRunLoop while active)
```

根节点挂载 `res://scripts/boot/formal_client_boot.gd`。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| Godot 启动 | 读取 `client/project.godot` | `run/main_scene` |
| 主场景加载 | 实例化 `FormalClientBoot` 根节点 | 无 |
| `_ready()` | 调用 `DataLoader.validate_project_data()` 并输出正式客户端启动日志 | `print()` |
| smoke 测试分发 | Bridge 从 `client/tools/smoke_commands.json` 解析稳定 command id；`formal_boot` runner 统一传入 `--test-command <id>`，Boot 再校验 catalog schema、唯一 id、setup 与 runner 路径后动态挂载。未知 / 重复 / 缺值命令 fail closed；直接 script / scene smoke 不进入 Boot | `tools/godot_bridge.py`、`_resolve_test_command_request()`、`_load_formal_test_command()` |
| 正常启动 | 数据校验通过后通过 `UIManager` 显示 `TitleMenu`，保持 `GameState.MAIN_MENU` | `UIManager.push()` |
| 标题设置 | 标题菜单发出 `settings_requested` 后，启动脚本把 `SettingsPanel` 推入 UI 栈；关闭时只弹出设置面板并保留标题菜单 | `UIManager.push()` / `UIManager.pop()` |
| 标题图鉴 | 标题菜单发出 `codex_requested` 后，启动脚本把 `CodexPanel` 推入 UI 栈；关闭或 `ui_back` 时只弹出图鉴并恢复标题焦点 | `UIManager.push()` / `UIManager.pop_expected()` |
| 英雄组合选择 | 新局开始前压入受管组合面板；确认后进入玩家加载，取消时按节点调用 `remove_expected()`，即使它已不是栈顶也不得直接 `queue_free()` | `UIManager.push()` / `UIManager.remove_expected()` |
| 玩家加载入口 | 开始 / 继续 / 重开立即清理旧 UI、进入 `GameState.LOADING` 并压入唯一 `LoadingScreen`；至少渲染一帧后才读取存档或挂载 runtime。重复请求被忽略 | `_begin_player_gameplay_load()`、`UIManager.push()`、`GameState.LOADING` |
| Gameplay runtime 准备 / 激活 | 开始 / 重开先生成新的 `RNG` run seed，并把可选 difficulty profile、`ContentUnlockSystem` 内容可用池和长期进度提交开关在 RunLoop 入树前配置；未指定难度时使用 mode 默认，当前正式 UI 固定标准难度。继续游戏在加载界面出现后读取 Run v19 payload，并恢复保存 profile、冻结内容池、未结算内容进度、武器冷却 / 分层修正、Gear Mod 棋盘、`GameplayEffectRuntime` 程序状态、带 ID 未拾取 Mod、7×7 assignment / 目标角落及战斗状态。空 envelope 失败时保留 `SaveManager.last_error()` 和所有需保留文件，退出 `LOADING` 并显示不可用提示；只有成功读取且 payload 明确带 `legacy_run_incompatible` 时才删除旧 Run。收到 `run_prepared` 后 `pop_expected(LoadingScreen)` 并等待 `ui_removed`，再调用 `activate_prepared_run()`；失败使用 immediate clear 清理半成品，并注销标准、敌人、Gear Mod pickup 与 VFX 声明对象池后回标题 | `configure_difficulty_profile_id()`、`configure_content_availability()`、`configure_content_progress_commits_enabled()`、`run_prepared`、`run_prepare_failed`、`UIManager.ui_removed`、`GameState.PLAYING` |
| F5 存档 smoke | Bridge command `save-smoke` 通过通用测试钩子只挂载 `SaveManagerSmoke`，验证 run 存档 roundtrip、主 / 备 3×3 回退矩阵、坏档隔离、迁移链，以及 FormalBoot 继续“损坏主档 + 不兼容备份”后退出 `LOADING` 且备份字节不变 | `client/tools/save_manager_smoke.gd` |
| F7 设置 smoke | Bridge command `settings-smoke` 通过通用测试钩子只挂载 `SettingsSmoke`，验证设置缺文件默认值、有效配置 roundtrip、非法值拒绝、坏值 / 坏文件回退以及 `Localization` 跟随语言设置 | `client/tools/settings_smoke.gd` |
| 内容进度 smoke | Bridge command `content-progression-smoke` 通过通用测试钩子验证默认开放、稀疏规则、`all/any`、计数器、幂等解锁、Meta v4、死亡 / 通关提交、保存续局、放弃丢弃、池快照冻结和 Replay / 测试隔离 | `client/tools/content_progression_smoke.gd` |
| 图鉴 smoke | Bridge command `codex-smoke` 通过通用测试钩子验证标题入口顺序、英雄 / Gear Mod / 敌人分类、锁定信息不泄露、要求数字进度、完整详情、语言刷新、焦点与返回 | `client/tools/codex_smoke.gd` |
| F11 装备 Mod smoke | Bridge command `gear-mod-smoke` 通过通用测试钩子只挂载 `GearModSmoke`，验证固定效果、重复实例乘算、单份授予、应用、清空、恢复和掉落，且不存在等级 / 升级接口 | `client/tools/gear_mod_smoke.gd` |
| F13 模块世界 smoke | Bridge command `module-world-smoke` 通过通用测试钩子启动默认模块载体，验证 49 槽 assignment/hash、左下起点、三个确定性目标候选、不同 seed、三种不同世界事件、77×77 坐标、3×3 邻域与最多三个事件 pin（共 12 chunk）、起点威胁暂停 / combat gate、敌人出生倍率、跨模块状态、带 ID 未拾取 Mod、刷怪笼程序、迷雾、意识核直接完成、Run v19 模块 / 事件 / 棋盘 / 效果程序子快照恢复与坏 map hash 拒绝 | `client/tools/module_world_smoke.gd` |
| F13 首帧可玩 probe（按需） | 仅在用户明确要求性能测试时，`--startup-probe` 在正式主场景 `_ready()` 首行输出 `BOOT_BEGIN`，启动默认模块载体，进入 `PLAYING` 且找到 `GameplayRunLoop` 后输出 `PLAYABLE` 并退出；Bridge 以两 marker 间单调时钟执行 2 秒硬门槛，进程冷启动另作诊断 | `client/tools/startup_probe.gd`、`tools/godot_bridge.py startup-probe` |
| F8 / F9 L1 smoke | Bridge command `l1-smoke` 通过通用测试钩子只挂载 `L1Smoke`，验证 `RNG`、`GameClock`、`GameState`、`SaveManager`、`Combat`、`ModLoader` 和 `PlatformServices` 的最小基础设施行为 | `client/tools/l1_smoke.gd` |
| F8 Replay smoke | Bridge command `replay-smoke` 通过通用测试钩子只挂载 `ReplaySmoke`，验证 Replay 最小录制、`.replay` 保存 / 读取、摘要对比和 data fingerprint | `client/tools/replay_smoke.gd` |
| F8 Replay runner | `--replay-runner` 启动时动态加载 `ReplayRunner`。单文件入口保持原 summary / expectation 与 runtime rerun 语义；重复传入 `--replay-file` 时在同一进程串行执行，每条之间清理 InputService、Replay、UI、RunLoop 与对象池状态，默认 fail-fast，`--keep-going` 才收集全部失败 | `client/tools/replay_runner.gd`、`tools/godot_bridge.py replay-regression` |
| F8 Replay input smoke | Bridge command `replay-input-smoke` 通过通用测试钩子只挂载 `ReplayInputSmoke`，启动真实 `GameplayRunLoop` 并确认移动 / 瞄准 / pause / ui_back 输入录制到 `Replay.input_events` | `client/tools/replay_input_smoke.gd` |
| 输入系统 smoke | Bridge command `input-smoke` 通过通用测试钩子只挂载 `InputSmoke`，验证 GUIDE 映射、context、设备提示、重绑定捕获和 InputService 物理 tick 边沿 | `client/tools/input_smoke.gd` |
| F8 golden capture | `--capture-golden-replay` 启动时只挂载 `GoldenReplayCapture`，由工具设置固定 seed、启动 `GameplayRunLoop`、采样 180 帧并写入 `client/tests/replays/golden_basic_run.replay`；可用 `--golden-scenario golden_pause_resume` 生成暂停 / 恢复输入场景，`--golden-scenario golden_full_death` 生成正式 Combat 死亡 / 失败页场景，或 `--golden-scenario golden_reward_choice` 显式请求 3 个通用奖励候选并记录选择 decision | `client/tools/golden_replay_capture.gd` |
| F8 perf probe | `--perf-probe` 启动时挂载 `GameplayRunLoop` 与 `PerfProbe`，输出平均 / 最大帧时间、池水位、等级、击杀和 GameClock 指标 JSON | `client/tools/perf_probe.gd` |
| F9 Demo smoke | Bridge command `f9-demo-smoke` 通过通用测试钩子挂载真实 `GameplayRunLoop`，验证 FEA-12 机关存在、造成玩家伤害和 run 保存 roundtrip | `client/tools/f9_demo_smoke.gd` |
| 玩家加载 smoke | Bridge command `loading-smoke` 通过通用测试钩子走真实标题按钮与重开信号，验证加载界面 / `LOADING`、跨帧旋转、输入阻断、重复请求、唯一 RunLoop、续局、重开；四类缺必需节点分别走完整玩家加载，验证失败信号一次、回标题、无残留 LoadingScreen / RunLoop / runtime activity / run-owned pool | `client/tools/loading_smoke.gd` |
| DebugTools smoke | Bridge command `debug-tools-smoke` 通过通用测试钩子挂载 `GameplayRunLoop` 与 `DebugToolsSmoke`；debug 模式验证 `DebugConsole` / `GMCommandRegistry`、help/stats/spawn/gold/hp/damage/heal/dust/kill/clear 命令，release descriptor 额外传入 `--force-release-debug-tools-off`，确认没有调试节点或 debug action | `client/tools/debug_tools_smoke.gd` |
| 重开 / 回标题 | `GameplayRunLoop` 发出重开或回标题信号后，由启动脚本清理运行时和 gameplay 对象池，再重新挂载 run 或标题菜单 | `restart_requested` / `quit_to_title_requested` |
| 存档拒绝 | Run v19 的内容池 / 未结算进度 / Gear Mod 棋盘 / 效果程序状态 / 带 ID 未拾取 Mod / gold / reward choice / difficulty / enemy reward / 7×7 assignment / 目标角落 / map hash / 世界事件 / 显式攻击状态不一致时恢复失败。缺包、包版本或 gameplay hash 不匹配会保留源文件并隐藏继续入口；旧 Run v18 也保留但不显示为可继续，不迁移为 v19。读取返回空 envelope 时 Boot 不调用 `delete()`，以免删除 SaveManager 判定需保留的主档或备份 | `SaveManager.save_status()`、`SaveManager.last_error()`、`restore_failed` |

## 公共 API

| API | 用途 |
|-----|------|
| `debug_tools_enabled()` | 供 smoke / 调试工具读取当前 debug/dev_tools guard 结果 |
| `debug_active_run_loop()` | 供 `GMCommandRegistry` 定位当前活跃 `GameplayRunLoop` |

## Signal / Event

无。

## 数据与契约

- `client/tools/smoke_commands.json` 是 smoke 分发与输出 policy 的唯一来源；每条 command 必须声明稳定 id、runner、隔离策略、精确成功 marker、标准 fatal 开关以及逐命令整行锚定的 expected-error / shutdown allowlist。Bridge 对外 CLI 名称等于 command id，FormalClientBoot 只消费其中 `runner_type=formal_boot` 的条目。
- 通过 `DataLoader.validate_project_data()` 间接读取 F3 目标数据和 `client/locale/strings.csv`。
- `client/project.godot` 的默认 viewport 为 1920×1080；当前只设计 / 验收 16:9，窗口禁止任意拖拽缩放，2D 内容和 UI 通过 `display/window/stretch/mode="canvas_items"` 与 `display/window/stretch/aspect="keep"` 在非 16:9 屏幕上等比缩放并补上下或左右黑边。设置页只应暴露经过验证的 16:9 固定分辨率预设，不接受任意宽高输入；16:10、4:3、21:9 等比例留作未来按独立固定预设接入的优化项，当前不做连续响应式适配。
- 启动日志输出 `data_schema_ok`、`mods`、`player_stats`、`characters`、`weapons`、`skills`、`enemies`、`gear_mods`、`content_unlock_rules`、`hazards`、`map_layouts`、`module_worlds`、`module_templates`、`warzone_directors`、`spawn_waves`、`active_items`、`consumables`、`locale_keys`、`level_progression_profiles`、`reward_choice_pools`、`game_modes`、`mod_environment`、`platform_provider`、`platform_available` 等 smoke 计数 / 状态。
- 启动脚本不硬编码玩家可见文本；标题、加载、HUD、设置、失败页和装备 Mod 面板文案见 `client/locale/strings.csv`。加载界面只显示 `ui_loading`，通用准备失败回标题显示 `ui_loading_failed`。
- 标题菜单的“继续游戏”只在存在当前版本且 `mod_environment` 精确匹配的 Run v19 时可见；标题页提供图鉴和只读 Mod 面板，但不提供 Gear Mod 局外配置。开始新局和重开会删除当前可继续 Run、建立初始棋盘与效果 Runtime、冻结内容 / 本地玩法环境并生成新 seed。继续游戏先显示加载界面，再读取和校验 Run v19；成功时恢复同一世界、棋盘、效果程序状态及带 ID 未拾取 Mod。读取失败返回空 envelope 时回标题并保留 SaveManager 的错误与需保留文件；旧 Run v18、环境不匹配主档或在坏主档之后发现的不兼容备份均保持原位，不作为损坏档隔离。
- DebugTools 只在 `OS.is_debug_build()` 或 `OS.has_feature("dev_tools")` 为真时动态加载；release 构建不应启用 `dev_tools`，也不应包含 `res://scripts/debug/*` 调试资源。
- 正式 boot 与标题菜单不得包含开发者测试岛节点、路径、signal 或 `--debug-test-arena` 参数处理；该零耦合边界由项目 lint 守门。

## 依赖

- 上游依赖：Godot 4.7.1 项目加载机制、已注册的 F2 autoload。
- 下游调用方：`TitleMenu`、英雄组合面板、`LoadingScreen` 和 `SettingsPanel` 场景由本启动脚本通过 `UIManager` 挂载并移除，`GameplayRunLoop` 场景由本启动脚本创建、激活和清理。
- 禁止依赖：不得引用 MVP 场景或脚本；不得用启动脚本临时拼长期 gameplay / UI 层级；不得提前绕过未来 F2 autoload 边界。

## 扩展点

- F2 落地 autoload 后，可以把本场景作为启动烟雾场景继续保留；F4 阶段只承载最小标题 / run 编排，后续 F7 主菜单落地时再切换入口。
- 新增正式主菜单或设置 UI 时应新增对应模块文档；玩家加载流程由 `docs/代码/gameplay_loading.md` 维护，不把资源准备细节塞进启动脚本。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 更换主场景 | `client/project.godot` | 本文档、`client/README.md`、`docs/AI导航.md` | `tools/godot_bridge.py --project client headless-boot` |
| 调整默认分辨率 / 拉伸策略 | `client/project.godot` | 本文档、`client/README.md`、相关 UI 模块文档 | `headless-boot` + `runtime-smoke` + 手动不同窗口尺寸检查 |
| 增加启动前检查 | `client/scripts/boot/formal_client_boot.gd` | 本文档；必要时新增模块文档 | headless boot |
| 调整 smoke command / runner / 输出 policy | `client/tools/smoke_commands.json`、`tools/godot_bridge.py`、必要的 `client/tools/*_smoke.gd` | 本文档、`docs/测试策略.md`、`docs/AI协作/引擎集成.md`、AI导航 | `python tools/test_godot_bridge.py`、目标 smoke；改通用 FormalBoot 路由时追加 headless boot |
| 调整 gameplay runtime 挂载 / 新局 seed / 继续游戏 | `formal_client_boot.gd`、`gameplay_run_loop.tscn`、`gameplay_run_loop.gd` | 本文档、`docs/代码/gameplay_runtime.md`、RNG 文档、AI导航 | headless boot、`l1-smoke`、`runtime-smoke`、`save-smoke`、checked-in replay runner 抽查、手动保存续局 |
| 调整开始 / 继续 / 重开加载 | `formal_client_boot.gd`、`loading_screen.tscn/.gd`、`gameplay_run_loop.gd` | 本文档、Gameplay Loading / Runtime、GameState、UIManager 文档 | `loading-smoke`、`runtime-smoke`、`save-smoke`、module-world full / technical、手动中英文 |
| 调整标题菜单或未来局内 Mod 配置入口 | `formal_client_boot.gd`、`title_menu.tscn`、对应脚本 | 本文档、Gameplay / GearModSystem 文档、AI导航；局内配置需新 ADR | headless boot、runtime / gear-mod smoke、人工标题菜单验收 |
| 调整标题设置入口 | `formal_client_boot.gd`、`title_menu.tscn`、`settings_panel.tscn`、对应脚本 | 本文档、`docs/代码/settings.md`、AI导航 | headless boot、`settings-smoke`、`runtime-smoke` |
| 调整标题图鉴或内容进度 runner | `formal_client_boot.gd`、`title_menu.tscn`、`codex_panel.tscn`、对应脚本与 smoke | 本文档、ContentUnlockSystem / Gameplay Runtime、测试策略、AI 导航 | `content-progression-smoke`、`codex-smoke`、headless boot、`runtime-smoke` |
| 调整 F7 设置 smoke 挂载 | `formal_client_boot.gd`、`client/tools/settings_smoke.gd` | 本文档、`docs/代码/settings.md`、AI导航 | headless boot、`settings-smoke` |
| 调整 F11 Gear Mod smoke 挂载 | `formal_client_boot.gd`、`client/tools/gear_mod_smoke.gd` | 本文档、`docs/代码/gear_mod_system.md`、AI导航 | headless boot、`gear-mod-smoke` |
| 调整输入 / F8 / F9 runner 挂载 | `formal_client_boot.gd`、`client/tools/input_smoke.gd`、`client/tools/l1_smoke.gd`、`client/tools/replay_smoke.gd`、`client/tools/replay_runner.gd`、`client/tools/replay_input_smoke.gd`、`client/tools/golden_replay_capture.gd`、`client/tools/perf_probe.gd`、`client/tools/f9_demo_smoke.gd` | 本文档、InputService / Replay / 测试策略 / F8 工作包 / Gameplay Runtime | `input-smoke`、`l1-smoke`、`replay-smoke`、`replay-runner`、`replay-input-smoke`、`capture-golden-replay`、`capture-golden-replay --golden-scenario golden_pause_resume`、`capture-golden-replay --golden-scenario golden_full_death`、`capture-golden-replay --golden-scenario golden_reward_choice`、`f9-demo-smoke`；性能 probe 仅在用户明确要求时运行 |
| 调整 DebugTools 挂载 | `formal_client_boot.gd`、`client/scripts/debug/*.gd`、`client/tools/debug_tools_smoke.gd` | 本文档、`docs/代码/debug_tools.md`、测试策略、AI导航 | `debug-tools-smoke` + `debug-tools-release-smoke` |
| 补目录说明 | `client/README.md` | `README.md`、`docs/AI导航.md` | docs health |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| headless 报 invalid project | `client/project.godot` 是否存在 |
| 主场景加载失败 | `run/main_scene` 是否指向 `res://scenes/boot/main.tscn` |
| 脚本编译失败 | `client/scripts/boot/formal_client_boot.gd` 类型和路径 |
| `data_schema_ok=false` | 查看同次 headless 日志中的 `[DataLoader]` schema 错误 |
| 数据通过但没有运行时节点 | `formal_client_boot.gd` 是否创建 `GameplayRunLoop`，以及脚本编译是否失败 |
| 场景加载报警或找不到节点 | `gameplay_run_loop.tscn` / UI `.tscn` 的 ext_resource 路径、节点名和脚本 `get_node_or_null()` 路径是否一致 |
| 正常启动没有标题菜单 | `TitleMenu` 是否通过 `UIManager.push()` 挂载，`UIManager.stack_size()` 是否异常 |
| 标题菜单仍显示装备 Mod | `TitleMenu` / `FormalClientBoot` 是否残留 button、signal、preload 或 locale key；正式入口必须为零 |
| 标题菜单仍出现旧局外升级 | `TitleMenu` 是否意外恢复 `MetaProgressionButton` / `meta_progression_requested`；`FormalClientBoot` 是否意外恢复旧连接 |
| 设置面板关闭后没回标题 | `_on_settings_panel_closed()` 是否只弹出 `SettingsPanel`；`UIManager.top()` 是否为设置面板 |
| 有 run 存档但没有继续按钮 | `SaveManager.has_save(slot_0, run)` 是否为真；旧存档是否 hash mismatch 被隔离；标题菜单是否显示 `ui_run_save_unavailable` |
| 普通新局每次地图 / 刷怪序列一样 | 标题开始和重开是否调用 `_start_new_gameplay_run()`；工具路径固定 seed 不代表普通入口随机化失败 |
| replay / smoke / golden 结果漂移 | 工具路径是否误走普通新局入口；回放、golden capture 和 smoke 应显式固定 seed 或直接启动 `_start_gameplay_run()` |
| 点击开始后先卡住才出现加载界面 | 存档读取 / runtime 创建是否在加载界面首个 `process_frame` 之前执行 |
| 重复点击出现两个 RunLoop | `_player_load_in_progress` 是否在请求开始时置位，并只在成功 / 失败收口时清除 |
| 准备失败后仍留加载界面或实体 | `_abort_player_gameplay_load()` 是否清理 UI、半成品 RunLoop 和 gameplay 对象池 |
| 正式导出出现 GM 控制台 | release preset 是否启用 `dev_tools`；`FormalClientBoot._debug_tools_enabled()` 是否被绕过；导出资源是否包含 `res://scripts/debug/*` |
| 正式启动意外引用测试岛 | `lint_project_rules.py` 的 `standalone-debug-test-arena` 门禁；正式 boot / title 必须零引用 |

## 测试义务

- F1 必跑 headless 启动验证：`tools/godot_bridge.py --project client headless-boot`。
- 修改普通新局 / 重开 seed 策略时，追加 `python tools/godot_bridge.py --project client l1-smoke`、`runtime-smoke`、`save-smoke`，并用至少一条 checked-in replay 的 `replay-runner --replay-file ... --rerun-runtime-summary` 确认工具固定 seed 路径未漂移。
- 修改玩家开始 / 继续 / 重开加载编排时，必跑 `python tools/godot_bridge.py --project client loading-smoke`、`runtime-smoke`、`save-smoke`，并按 Gameplay Loading 文档追加 actor / module-world / golden 回归。
- 修改 `save-smoke` descriptor / 挂载或 SaveManager 启动诊断时，追加 `python tools/godot_bridge.py --project client save-smoke`。
- 修改 `settings-smoke` descriptor / 挂载或 Settings 持久化启动诊断时，追加 `python tools/godot_bridge.py --project client settings-smoke`。
- 修改 `content-progression-smoke` / `codex-smoke` descriptor、标题图鉴或内容池注入时，追加 `python tools/godot_bridge.py --project client content-progression-smoke`、`python tools/godot_bridge.py --project client codex-smoke`、`runtime-smoke` 与 headless boot。
- 修改 `gear-mod-smoke` descriptor / 挂载或 GearModSystem 启动诊断时，追加 `python tools/godot_bridge.py --project client gear-mod-smoke`。
- 修改 `input-smoke` / `l1-smoke` / `replay-smoke` / `replay-input-smoke` / `f9-demo-smoke` descriptor，或 `--replay-runner` / `--capture-golden-replay` 专用挂载时，追加对应 `python tools/godot_bridge.py --project client input-smoke`、`l1-smoke`、`replay-smoke`、`replay-runner`、`replay-input-smoke`、`capture-golden-replay`、`capture-golden-replay --golden-scenario golden_pause_resume`、`capture-golden-replay --golden-scenario golden_full_death`、`capture-golden-replay --golden-scenario golden_reward_choice`、`f9-demo-smoke`；改 golden 对照逻辑时还要跑四条 checked-in replay 的 `replay-runner --replay-file ... --rerun-runtime-summary`。修改性能 probe 挂载时只做静态 / headless 基础校验，除非用户当次明确要求运行性能测试。
- 修改 DebugTools 挂载或 release guard 时，追加 `python tools/godot_bridge.py --project client debug-tools-smoke` 与 `python tools/godot_bridge.py --project client debug-tools-release-smoke`。
- 若项目 lint 报正式入口引用测试岛，应删除该耦合并按 `docs/代码/debug_test_arena.md` 从独立 scene 验证；不要在本模块增加测试岛挂载或 CLI。
- 修改标题菜单与局内 Gear Mod 隔离边界时，追加 `gear-mod-smoke`、`runtime-smoke`，并把“标题页无局外入口”保留为人工验收。
- 修改标题设置入口或 `SettingsPanel` 挂载时，追加 `python tools/godot_bridge.py --project client settings-smoke` 与 `python tools/godot_bridge.py --project client runtime-smoke`。
- 修改长期文档或索引后跑 `tools/docs_health_check.py`。
- 通用 smoke catalog / Bridge 路由必须跑 `python tools/test_godot_bridge.py`；FormalClientBoot 仍以 headless boot 和目标 smoke 验证编排，不以 GUT 代替运行时挂载。改 DataLoader schema 时按 DataLoader 测试义务处理。

## 迁移 / 兼容

新游戏流程为“标题开始 → 英雄组合选择 → Loading → 游戏”；选择页默认读取 Meta v4 上次确认组合并与当前解锁英雄求交，首次为冷静主 + 愤怒子，局外禁用同英雄。重开沿用当前组合和 difficulty profile 并重新冻结可用池 / Mod 环境、重建 7×7 世界；继续游戏恢复 Run v19 组合、内容池、效果程序、Gear Mod 棋盘 / 刷怪计划、带 ID 未拾取 Mod、金币、未完成奖励选择、难度、assignment / 目标角落、世界事件、敌人奖励与显式攻击状态。旧 Run v18 保留但不显示继续入口；Meta v4 不受影响。`--module-world-technical-slice` 与 `--open-warzone` 仍只作 opt-in 回归入口；DebugTools 只在 debug/dev_tools 或 smoke 路径启用。

## 相关文档

- `docs/正式项目工作规划.md`
- `docs/代码文档规范.md`
- `docs/测试策略.md`
- `docs/AI导航.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/gameplay_loading.md`
- `docs/代码/debug_tools.md`
- `docs/代码/debug_test_arena.md`
- `docs/代码/content_unlock_system.md`
