# FormalClientBoot 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式客户端 F1 启动骨架的代码契约权威；改启动场景、项目入口、节点结构或验证方式时必须同步本文档、`client/README.md`、`docs/AI导航.md` 与 `docs/AI记忆/current_state.json`。

## 职责

- 负责提供完整项目 `client/` 的最小 Godot 启动入口。
- 负责让 F1 阶段可以通过 headless 启动验证。
- F2/F3 期间作为正式客户端 smoke 场景，负责触发 autoload 和数据 schema 启动检查；F4 起在数据校验通过后显示最小标题界面，并在玩家开始游戏、继续 run 存档、重开、打开装备 Mod 面板、打开设置面板或 smoke 模式下编排对应流程。ADR #117 后旧局外升级标题入口和 `meta-smoke` 已删除。
- ADR #157 后负责正式玩家入口的统一加载编排、重入保护、成功激活和失败回退；不负责 `GameplayRunLoop` 内部资源准备细节，也不处理应用冷启动。
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
| `client/scenes/ui/gear_mod_panel.tscn` | F11 标题装备 Mod 面板场景 |
| `client/scenes/ui/settings_panel.tscn` | F7 标题设置面板场景 |
| `client/scripts/ui/title_menu.gd` | F4 阶段最小标题界面，通过 `UIManager` 挂载 |
| `client/scripts/ui/loading_screen.gd` | 加载文字刷新与旋转动画诊断 |
| `client/scripts/ui/gear_mod_panel.gd` | F11 装备 Mod 面板，通过 `UIManager` 叠在标题菜单上 |
| `client/scripts/ui/settings_panel.gd` | F7 设置面板，通过 `UIManager` 叠在标题菜单上 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | F4 数据校验通过后挂载的最小可玩闭环 runtime |
| `client/tools/save_manager_smoke.gd` | `--save-smoke` 下挂载的 F5 存档可靠性 smoke |
| `client/tools/settings_smoke.gd` | `--settings-smoke` 下挂载的 F7 设置持久化 smoke |
| `client/tools/gear_mod_smoke.gd` | `--gear-mod-smoke` 下挂载的 F11 装备 Mod smoke |
| `client/tools/l1_smoke.gd` | `--l1-smoke` 下挂载的 F8 临时 L1 基础设施 smoke |
| `client/tools/f9_demo_smoke.gd` | `--f9-demo-smoke` 下挂载的 F9 Demo / FEA-12 机关 smoke |
| `client/tools/loading_smoke.gd` | `--loading-smoke` 下覆盖真实开始 / 继续 / 重开、重入保护和失败回退 |
| `client/tools/replay_smoke.gd` | `--replay-smoke` 下挂载的 F8 Replay 文件 roundtrip smoke |
| `client/tools/replay_runner.gd` | `--replay-runner` 下挂载的 F8 Replay summary diff runner，可读取指定 `.replay` 和可选 expectation JSON |
| `client/tools/replay_input_smoke.gd` | `--replay-input-smoke` 下挂载的 F8 gameplay 输入录制 smoke |
| `client/tools/input_smoke.gd` | `--input-smoke` 下挂载的 GUIDE / InputService 集成 smoke |
| `client/tools/golden_replay_capture.gd` | `--capture-golden-replay` 下挂载的 F8 golden capture 工具，固定 seed 生成 `golden_basic_run.replay`、`golden_pause_resume.replay`、`golden_full_death.replay` 或 `golden_level_up_choice.replay` |
| `client/tools/perf_probe.gd` | `--perf-probe` 下挂载的 F8 轻量性能 / 平衡采样 |
| `client/tools/debug_tools_smoke.gd` | `--debug-tools-smoke` 下挂载的调试控制台 / GM 指令 smoke，也可配合 `--force-release-debug-tools-off` 模拟 release guard |
| `client/README.md` | 正式客户端运行说明 |

## 场景 / 节点结构

```text
FormalClientBoot (Node)
└── GameplayRunLoop (Node2D, instanced from `client/scenes/gameplay/gameplay_run_loop.tscn` while a run is active)

UIManager
└── UIRoot
    ├── TitleMenu (scene; normal boot after data schema passes; shows continue when run.save exists)
    ├── LoadingScreen (scene; start / continue / restart preparation, always-process, input-blocking)
    ├── GearModPanel (scene; opened from title menu)
    └── SettingsPanel (scene; pushed above title menu when requested)
```

根节点挂载 `res://scripts/boot/formal_client_boot.gd`。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| Godot 启动 | 读取 `client/project.godot` | `run/main_scene` |
| 主场景加载 | 实例化 `FormalClientBoot` 根节点 | 无 |
| `_ready()` | 调用 `DataLoader.validate_project_data()` 并输出正式客户端启动日志 | `print()` |
| 正常启动 | 数据校验通过后通过 `UIManager` 显示 `TitleMenu`，保持 `GameState.MAIN_MENU` | `UIManager.push()` |
| 标题装备 Mod | 标题菜单发出 `gear_mod_requested` 后，启动脚本把 `GearModPanel` 推入 UI 栈；关闭时弹出该面板并保留标题菜单 | `UIManager.push()` / `UIManager.pop()` |
| 标题设置 | 标题菜单发出 `settings_requested` 后，启动脚本把 `SettingsPanel` 推入 UI 栈；关闭时只弹出设置面板并保留标题菜单 | `UIManager.push()` / `UIManager.pop()` |
| 玩家加载入口 | 开始 / 继续 / 重开立即清理旧 UI、进入 `GameState.LOADING` 并压入唯一 `LoadingScreen`；至少渲染一帧后才读取存档或挂载 runtime。重复请求被忽略 | `_begin_player_gameplay_load()`、`UIManager.push()`、`GameState.LOADING` |
| Gameplay runtime 准备 / 激活 | 开始 / 重开先生成新的 `RNG` run seed；继续游戏在加载界面出现后读取 `run` payload。玩家入口为 RunLoop 启用分帧准备模式，收到 `run_prepared` 后先移除加载界面再调用 `activate_prepared_run()`；失败则清理半成品和对象池并回标题。`--runtime-smoke` 等工具路径继续同步挂载，保持固定 seed / 可复现 | `RNG.set_random_run_seed()`、`SaveManager.load_envelope()`、`run_prepared`、`run_prepare_failed`、`GameState.PLAYING` |
| F5 存档 smoke | `--save-smoke` 启动时只挂载 `SaveManagerSmoke`，验证 run 存档 roundtrip、备份回退、坏档隔离和迁移链 | `client/tools/save_manager_smoke.gd` |
| F7 设置 smoke | `--settings-smoke` 启动时只挂载 `SettingsSmoke`，验证设置缺文件默认值、有效配置 roundtrip、非法值拒绝、坏值 / 坏文件回退以及 `Localization` 跟随语言设置 | `client/tools/settings_smoke.gd` |
| F11 装备 Mod smoke | `--gear-mod-smoke` 启动时只挂载 `GearModSmoke`，验证 Gear Mod profile、授予、装备、容量、升级、分解和掉落 | `client/tools/gear_mod_smoke.gd` |
| F13 模块世界 smoke | `--module-world-smoke` 启动默认模块载体，验证 81 槽 assignment/hash、不同 seed、坐标、最多 9 chunk、跨模块状态、迷雾、目标后撤离、run v4 恢复与坏 map hash 拒绝 | `client/tools/module_world_smoke.gd` |
| F13 首帧可玩 probe（按需） | 仅在用户明确要求性能测试时，`--startup-probe` 在正式主场景 `_ready()` 首行输出 `BOOT_BEGIN`，启动默认模块载体，进入 `PLAYING` 且找到 `GameplayRunLoop` 后输出 `PLAYABLE` 并退出；Bridge 以两 marker 间单调时钟执行 2 秒硬门槛，进程冷启动另作诊断 | `client/tools/startup_probe.gd`、`tools/godot_bridge.py startup-probe` |
| F8 / F9 L1 smoke | `--l1-smoke` 启动时只挂载 `L1Smoke`，验证 `RNG`、`GameClock`、`GameState`、`SaveManager`、`Combat`、`ModLoader` 和 `PlatformServices` 的最小基础设施行为 | `client/tools/l1_smoke.gd` |
| F8 Replay smoke | `--replay-smoke` 启动时只挂载 `ReplaySmoke`，验证 Replay 最小录制、`.replay` 保存 / 读取、摘要对比和 data fingerprint | `client/tools/replay_smoke.gd` |
| F8 Replay runner | `--replay-runner` 启动时只挂载 `ReplayRunner`，读取 `.replay` 并比较 envelope summary 或外部 expectation JSON；未传文件时生成临时 smoke replay 自测 runner；带 `--rerun-runtime-summary` 时会按 replay seed 启动 `GameplayRunLoop`、按 tick/frame 播放 `input_events` 与工具层 `runtime_events` 并比较 `run_summary`，未传文件时生成临时输入播放 smoke replay | `client/tools/replay_runner.gd` |
| F8 Replay input smoke | `--replay-input-smoke` 启动时只挂载 `ReplayInputSmoke`，启动真实 `GameplayRunLoop` 并确认移动 / 瞄准 / pause / ui_back 输入录制到 `Replay.input_events` | `client/tools/replay_input_smoke.gd` |
| 输入系统 smoke | `--input-smoke` 启动时只挂载 `InputSmoke`，验证 GUIDE 映射、context、设备提示、重绑定捕获和 InputService 物理 tick 边沿 | `client/tools/input_smoke.gd` |
| F8 golden capture | `--capture-golden-replay` 启动时只挂载 `GoldenReplayCapture`，由工具设置固定 seed、启动 `GameplayRunLoop`、采样 180 帧并写入 `client/tests/replays/golden_basic_run.replay`；可用 `--golden-scenario golden_pause_resume` 生成暂停 / 恢复输入场景，`--golden-scenario golden_full_death` 生成正式 Combat 死亡 / 失败页场景，或 `--golden-scenario golden_level_up_choice` 通过测试 harness 显式启用成长池后生成真实经验球触发的升级选择 decision 场景 | `client/tools/golden_replay_capture.gd` |
| F8 perf probe | `--perf-probe` 启动时挂载 `GameplayRunLoop` 与 `PerfProbe`，输出平均 / 最大帧时间、池水位、等级、击杀和 GameClock 指标 JSON | `client/tools/perf_probe.gd` |
| F9 Demo smoke | `--f9-demo-smoke` 启动时挂载真实 `GameplayRunLoop`，验证 FEA-12 机关存在、造成玩家伤害和 run 保存 roundtrip | `client/tools/f9_demo_smoke.gd` |
| 玩家加载 smoke | `--loading-smoke` 走真实标题按钮与重开信号，验证加载界面 / `LOADING`、跨帧旋转、输入阻断、重复请求、唯一 RunLoop、续局、重开与准备失败回退 | `client/tools/loading_smoke.gd` |
| DebugTools smoke | `--debug-tools-smoke` 启动时挂载 `GameplayRunLoop` 与 `DebugToolsSmoke`；debug 模式验证 `DebugConsole` / `GMCommandRegistry`、help/stats/spawn/xp/hp/damage/heal/dust/kill/clear 命令，`--force-release-debug-tools-off` 模拟 release 时确认没有调试节点或 debug action | `client/tools/debug_tools_smoke.gd` |
| 重开 / 回标题 | `GameplayRunLoop` 发出重开或回标题信号后，由启动脚本清理运行时和 gameplay 对象池，再重新挂载 run 或标题菜单 | `restart_requested` / `quit_to_title_requested` |
| 模块存档拒绝 | run v4 的 assignment 与 map hash 不一致时，runtime 发出 `restore_failed`；启动层只删除该 run、回标题并显示不可用提示，`meta` 不受影响 | `restore_failed` / `SaveManager.delete(..., save_kind_run)` |

## 公共 API

| API | 用途 |
|-----|------|
| `debug_tools_enabled()` | 供 smoke / 调试工具读取当前 debug/dev_tools guard 结果 |
| `debug_active_run_loop()` | 供 `GMCommandRegistry` 定位当前活跃 `GameplayRunLoop` |

## Signal / Event

无。

## 数据与契约

- 通过 `DataLoader.validate_project_data()` 间接读取 F3 目标数据和 `client/locale/strings.csv`。
- `client/project.godot` 的默认 viewport 为 1920×1080；当前只设计 / 验收 16:9，窗口禁止任意拖拽缩放，2D 内容和 UI 通过 `display/window/stretch/mode="canvas_items"` 与 `display/window/stretch/aspect="keep"` 在非 16:9 屏幕上等比缩放并补上下或左右黑边。设置页只应暴露经过验证的 16:9 固定分辨率预设，不接受任意宽高输入；16:10、4:3、21:9 等比例留作未来按独立固定预设接入的优化项，当前不做连续响应式适配。
- 启动日志输出 `data_schema_ok`、`mods`、`player_stats`、`characters`、`weapons`、`enemies`、`hazards`、`map_layouts`、`module_worlds`、`module_templates`、`warzone_directors`、`spawn_waves`、`relics`、`active_items`、`consumables`、`locale_keys`、`growth_levels`、`growth_pools`、`game_modes`、`platform_provider`、`platform_available` 等 smoke 计数 / 状态。
- 启动脚本不硬编码玩家可见文本；标题、加载、HUD、设置、失败页和装备 Mod 面板文案见 `client/locale/strings.csv`。加载界面只显示 `ui_loading`，通用准备失败回标题显示 `ui_loading_failed`。
- 标题菜单的“继续游戏”只在 `SaveManager.has_save(slot_0, run)` 为真时可见；“装备 Mod”常驻可见并由 `GearModPanel` 展示 `GearModSystem` 的 profile / mod summaries；旧“局外升级”标题入口已删除。开始新局和重开会删除旧 `run` 存档，并通过 `RNG.set_random_run_seed()` 生成新的主 seed，避免重复继续旧局或每局固定序列。继续游戏先显示加载界面，再读取和校验 run；若读取失败或坏档被隔离，标题菜单显示既有 `ui_run_save_unavailable` 提示并隐藏继续按钮。成功继续后，`GameplayRunLoop` 在加载界面移除后按 payload 的 `ui_restore` 回到普通游玩、暂停菜单或升级选择面板，不生成新 seed。
- DebugTools 只在 `OS.is_debug_build()` 或 `OS.has_feature("dev_tools")` 为真时动态加载；release 构建不应启用 `dev_tools`，也不应包含 `res://scripts/debug/*` 调试资源。

## 依赖

- 上游依赖：Godot 4.7.1 项目加载机制、已注册的 F2 autoload。
- 下游调用方：`TitleMenu`、`LoadingScreen`、`GearModPanel` 和 `SettingsPanel` 场景由本启动脚本通过 `UIManager` 挂载，`GameplayRunLoop` 场景由本启动脚本创建、激活和清理。
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
| 调整 gameplay runtime 挂载 / 新局 seed / 继续游戏 | `formal_client_boot.gd`、`gameplay_run_loop.tscn`、`gameplay_run_loop.gd` | 本文档、`docs/代码/gameplay_runtime.md`、RNG 文档、AI导航 | headless boot、`l1-smoke`、`runtime-smoke`、`save-smoke`、checked-in replay runner 抽查、手动保存续局 |
| 调整开始 / 继续 / 重开加载 | `formal_client_boot.gd`、`loading_screen.tscn/.gd`、`gameplay_run_loop.gd` | 本文档、Gameplay Loading / Runtime、GameState、UIManager 文档 | `loading-smoke`、`runtime-smoke`、`save-smoke`、module-world full / technical、手动中英文 |
| 调整标题装备 Mod 入口 | `formal_client_boot.gd`、`title_menu.tscn`、`gear_mod_panel.tscn`、对应脚本 | 本文档、`docs/代码/gameplay_runtime.md`、`docs/代码/gear_mod_system.md`、AI导航 | headless boot、`gear-mod-smoke`、手动标题菜单点开 |
| 调整标题设置入口 | `formal_client_boot.gd`、`title_menu.tscn`、`settings_panel.tscn`、对应脚本 | 本文档、`docs/代码/settings.md`、AI导航 | headless boot、`settings-smoke`、`runtime-smoke` |
| 调整 F7 设置 smoke 挂载 | `formal_client_boot.gd`、`client/tools/settings_smoke.gd` | 本文档、`docs/代码/settings.md`、AI导航 | headless boot、`settings-smoke` |
| 调整 F11 Gear Mod smoke 挂载 | `formal_client_boot.gd`、`client/tools/gear_mod_smoke.gd` | 本文档、`docs/代码/gear_mod_system.md`、AI导航 | headless boot、`gear-mod-smoke` |
| 调整输入 / F8 / F9 runner 挂载 | `formal_client_boot.gd`、`client/tools/input_smoke.gd`、`client/tools/l1_smoke.gd`、`client/tools/replay_smoke.gd`、`client/tools/replay_runner.gd`、`client/tools/replay_input_smoke.gd`、`client/tools/golden_replay_capture.gd`、`client/tools/perf_probe.gd`、`client/tools/f9_demo_smoke.gd` | 本文档、InputService / Replay / 测试策略 / F8 工作包 / Gameplay Runtime | `input-smoke`、`l1-smoke`、`replay-smoke`、`replay-runner`、`replay-input-smoke`、`capture-golden-replay`、`capture-golden-replay --golden-scenario golden_pause_resume`、`capture-golden-replay --golden-scenario golden_full_death`、`capture-golden-replay --golden-scenario golden_level_up_choice`、`f9-demo-smoke`；性能 probe 仅在用户明确要求时运行 |
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
| 标题菜单看不到装备 Mod | `TitleMenu` 是否有 `GearModButton`；locale 是否有 `ui_gear_mod_title_entry`；`FormalClientBoot` 是否连接 `gear_mod_requested` |
| 装备 Mod 面板没有 Mod 列表 | `GearModSystem.mod_summaries()` 是否返回当前槽位 Mod；`GearModPanel` 是否能找到 `ModList`；`gear-mod-smoke` 是否通过面板按钮流 |
| 标题菜单仍出现旧局外升级 | `TitleMenu` 是否意外恢复 `MetaProgressionButton` / `meta_progression_requested`；`FormalClientBoot` 是否意外恢复旧连接 |
| 设置面板关闭后没回标题 | `_on_settings_panel_closed()` 是否只弹出 `SettingsPanel`；`UIManager.top()` 是否为设置面板 |
| 有 run 存档但没有继续按钮 | `SaveManager.has_save(slot_0, run)` 是否为真；旧存档是否 hash mismatch 被隔离；标题菜单是否显示 `ui_run_save_unavailable` |
| 普通新局每次地图 / 刷怪序列一样 | 标题开始和重开是否调用 `_start_new_gameplay_run()`；工具路径固定 seed 不代表普通入口随机化失败 |
| replay / smoke / golden 结果漂移 | 工具路径是否误走普通新局入口；回放、golden capture 和 smoke 应显式固定 seed 或直接启动 `_start_gameplay_run()` |
| 点击开始后先卡住才出现加载界面 | 存档读取 / runtime 创建是否在加载界面首个 `process_frame` 之前执行 |
| 重复点击出现两个 RunLoop | `_player_load_in_progress` 是否在请求开始时置位，并只在成功 / 失败收口时清除 |
| 准备失败后仍留加载界面或实体 | `_abort_player_gameplay_load()` 是否清理 UI、半成品 RunLoop 和 gameplay 对象池 |
| 正式导出出现 GM 控制台 | release preset 是否启用 `dev_tools`；`FormalClientBoot._debug_tools_enabled()` 是否被绕过；导出资源是否包含 `res://scripts/debug/*` |

## 测试义务

- F1 必跑 headless 启动验证：`tools/godot_bridge.py --project client headless-boot`。
- 修改普通新局 / 重开 seed 策略时，追加 `python tools/godot_bridge.py --project client l1-smoke`、`runtime-smoke`、`save-smoke`，并用至少一条 checked-in replay 的 `replay-runner --replay-file ... --rerun-runtime-summary` 确认工具固定 seed 路径未漂移。
- 修改玩家开始 / 继续 / 重开加载编排时，必跑 `python tools/godot_bridge.py --project client loading-smoke`、`runtime-smoke`、`save-smoke`，并按 Gameplay Loading 文档追加 actor / module-world / golden 回归。
- 修改 `--save-smoke` 挂载或 SaveManager 启动诊断时，追加 `python tools/godot_bridge.py --project client save-smoke`。
- 修改 `--settings-smoke` 挂载或 Settings 持久化启动诊断时，追加 `python tools/godot_bridge.py --project client settings-smoke`。
- 修改 `--gear-mod-smoke` 挂载或 GearModSystem 启动诊断时，追加 `python tools/godot_bridge.py --project client gear-mod-smoke`。
- 修改 `--input-smoke` / `--l1-smoke` / `--replay-smoke` / `--replay-runner` / `--replay-input-smoke` / `--capture-golden-replay` / `--f9-demo-smoke` 挂载时，追加对应 `python tools/godot_bridge.py --project client input-smoke`、`l1-smoke`、`replay-smoke`、`replay-runner`、`replay-input-smoke`、`capture-golden-replay`、`capture-golden-replay --golden-scenario golden_pause_resume`、`capture-golden-replay --golden-scenario golden_full_death`、`capture-golden-replay --golden-scenario golden_level_up_choice`、`f9-demo-smoke`；改 golden 对照逻辑时还要跑四条 checked-in replay 的 `replay-runner --replay-file ... --rerun-runtime-summary`。修改性能 probe 挂载时只做静态 / headless 基础校验，除非用户当次明确要求运行性能测试。
- 修改 DebugTools 挂载或 release guard 时，追加 `python tools/godot_bridge.py --project client debug-tools-smoke` 与 `python tools/godot_bridge.py --project client debug-tools-release-smoke`。
- 修改标题装备 Mod 入口或 `GearModPanel` 挂载时，追加 `python tools/godot_bridge.py --project client gear-mod-smoke` 并做一次手动标题菜单点开检查。
- 修改标题设置入口或 `SettingsPanel` 挂载时，追加 `python tools/godot_bridge.py --project client settings-smoke` 与 `python tools/godot_bridge.py --project client runtime-smoke`。
- 修改长期文档或索引后跑 `tools/docs_health_check.py`。
- 不需要 GUT 单测；该模块只做 smoke / gameplay runtime 编排。改 DataLoader schema 时按 DataLoader 测试义务处理；改 gameplay runtime 挂载时跑 headless boot。

## 迁移 / 兼容

普通开始 / 重开生成新主 seed，并默认进入 F13 完整模块世界；继续游戏恢复 run v4 的 RNG 与 `module_world` 快照。旧 v3 run 会显示不兼容提示、删除 run 后要求新开，`meta` 不受影响。`--module-world-technical-slice` 是中心 3×3（外圈 72 槽封锁）的 opt-in 启动入口，自动回归入口为 `python tools/godot_bridge.py --project client module-world-technical-slice-smoke`；`--open-warzone` 只保留对照回归，默认 `module-world-smoke`、replay / golden 工具保持固定 seed。DebugTools 只在 debug/dev_tools 构建或 smoke 路径下验证，正式 release 路径由 runtime guard 与导出 preset 资源排除共同约束。

## 相关文档

- `docs/正式项目工作规划.md`
- `docs/代码文档规范.md`
- `docs/测试策略.md`
- `docs/AI导航.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/gameplay_loading.md`
- `docs/代码/debug_tools.md`
