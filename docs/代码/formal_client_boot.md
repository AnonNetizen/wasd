# FormalClientBoot 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式客户端 F1 启动骨架的代码契约权威；改启动场景、项目入口、节点结构或验证方式时必须同步本文档、`client/README.md`、`docs/AI导航.md` 与 `docs/AI记忆/current_state.json`。

## 职责

- 负责提供完整项目 `client/` 的最小 Godot 启动入口。
- 负责让 F1 阶段可以通过 headless 启动验证。
- F2/F3 期间作为正式客户端 smoke 场景，负责触发 autoload 和数据 schema 启动检查；F4 起在数据校验通过后显示最小标题界面，并在玩家开始游戏、继续 run 存档、打开局外升级面板、打开设置面板或 smoke 模式下编排对应流程。
- 不负责长期主菜单视觉包装、输入重绑定 UI、业务数据解释或完整加载流程；这些属于后续正式 UI / 玩法模块。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改正式项目启动场景 | `client/project.godot` 与 `client/scenes/boot/main.tscn` |
| 改启动脚本行为 | `client/scripts/boot/formal_client_boot.gd` |
| 推进下一阶段 autoload | `docs/正式项目工作规划.md` F2 |
| 调试 F4 启动 | `docs/代码/gameplay_runtime.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/project.godot` | Godot 项目配置，`run/main_scene` 指向最小启动场景，默认 viewport 为 1920×1080，窗口拉伸采用 `canvas_items + keep` |
| `client/scenes/boot/main.tscn` | 正式项目最小启动场景 |
| `client/scripts/boot/formal_client_boot.gd` | 启动场景脚本，输出启动日志 |
| `client/scenes/gameplay/gameplay_run_loop.tscn` | F4+ 正式 gameplay runtime 场景，由启动脚本实例化 |
| `client/scenes/ui/title_menu.tscn` | 正常启动后的正式标题菜单场景 |
| `client/scenes/ui/meta_progression_panel.tscn` | F6 标题局外升级面板场景 |
| `client/scenes/ui/settings_panel.tscn` | F7 标题设置面板场景 |
| `client/scripts/ui/title_menu.gd` | F4 阶段最小标题界面，通过 `UIManager` 挂载 |
| `client/scripts/ui/meta_progression_panel.gd` | F6 阶段标题局外升级面板，通过 `UIManager` 叠在标题菜单上 |
| `client/scripts/ui/settings_panel.gd` | F7 设置面板，通过 `UIManager` 叠在标题菜单上 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | F4 数据校验通过后挂载的最小可玩闭环 runtime |
| `client/tools/save_manager_smoke.gd` | `--save-smoke` 下挂载的 F5 存档可靠性 smoke |
| `client/tools/settings_smoke.gd` | `--settings-smoke` 下挂载的 F7 设置持久化 smoke |
| `client/tools/meta_progression_smoke.gd` | `--meta-smoke` 下挂载的 F6 局外成长 smoke |
| `client/tools/l1_smoke.gd` | `--l1-smoke` 下挂载的 F8 临时 L1 基础设施 smoke |
| `client/tools/replay_smoke.gd` | `--replay-smoke` 下挂载的 F8 Replay 文件 roundtrip smoke |
| `client/tools/replay_runner.gd` | `--replay-runner` 下挂载的 F8 Replay summary diff runner，可读取指定 `.replay` 和可选 expectation JSON |
| `client/tools/golden_replay_capture.gd` | `--capture-golden-replay` 下挂载的 F8 golden capture 工具，固定 seed 生成 `golden_basic_run.replay` |
| `client/tools/perf_probe.gd` | `--perf-probe` 下挂载的 F8 轻量性能 / 平衡采样 |
| `client/README.md` | 正式客户端运行说明 |

## 场景 / 节点结构

```text
FormalClientBoot (Node)
└── GameplayRunLoop (Node2D, instanced from `client/scenes/gameplay/gameplay_run_loop.tscn` while a run is active)

UIManager
└── UIRoot
    ├── TitleMenu (scene; normal boot after data schema passes; shows continue when run.save exists)
    ├── MetaProgressionPanel (scene; pushed above title menu when requested)
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
| 标题局外升级 | 标题菜单发出 `meta_progression_requested` 后，启动脚本把 `MetaProgressionPanel` 推入 UI 栈；关闭时弹出该面板并保留标题菜单 | `UIManager.push()` / `UIManager.pop()` |
| 标题设置 | 标题菜单发出 `settings_requested` 后，启动脚本把 `SettingsPanel` 推入 UI 栈；关闭时只弹出设置面板并保留标题菜单 | `UIManager.push()` / `UIManager.pop()` |
| Gameplay runtime 挂载 | 玩家选择开始、继续游戏或 `--runtime-smoke` 启动时实例化 `gameplay_run_loop.tscn`，进入最小战斗闭环；继续游戏会先从 `SaveManager` 读取 `run` payload，交给 runtime 恢复实体、GameClock、RNG 和 `ui_restore`，读取失败时回标题并显示坏档重置提示 | `PackedScene.instantiate()`、`add_child()`、`SaveManager.load_envelope()`、`GameState.PLAYING` |
| F5 存档 smoke | `--save-smoke` 启动时只挂载 `SaveManagerSmoke`，验证 run 存档 roundtrip、备份回退、坏档隔离和迁移链 | `client/tools/save_manager_smoke.gd` |
| F7 设置 smoke | `--settings-smoke` 启动时只挂载 `SettingsSmoke`，验证设置缺文件默认值、有效配置 roundtrip、非法值拒绝、坏值 / 坏文件回退以及 `Localization` 跟随语言设置 | `client/tools/settings_smoke.gd` |
| F6 局外成长 smoke | `--meta-smoke` 启动时只挂载 `MetaProgressionSmoke`，验证 meta profile roundtrip、结算、购买、解锁和永久 modifier | `client/tools/meta_progression_smoke.gd` |
| F8 L1 smoke | `--l1-smoke` 启动时只挂载 `L1Smoke`，验证 `RNG`、`GameClock`、`GameState`、`SaveManager` 和 `Combat` 的最小基础设施行为 | `client/tools/l1_smoke.gd` |
| F8 Replay smoke | `--replay-smoke` 启动时只挂载 `ReplaySmoke`，验证 Replay 最小录制、`.replay` 保存 / 读取、摘要对比和 data fingerprint | `client/tools/replay_smoke.gd` |
| F8 Replay runner | `--replay-runner` 启动时只挂载 `ReplayRunner`，读取 `.replay` 并比较 envelope summary 或外部 expectation JSON；未传文件时生成临时 smoke replay 自测 runner；带 `--rerun-runtime-summary` 时会按 replay seed 启动 `GameplayRunLoop` 并比较 `run_summary` | `client/tools/replay_runner.gd` |
| F8 golden capture | `--capture-golden-replay` 启动时只挂载 `GoldenReplayCapture`，由工具设置固定 seed、启动 `GameplayRunLoop`、采样 180 帧并写入 `client/tests/replays/golden_basic_run.replay` | `client/tools/golden_replay_capture.gd` |
| F8 perf probe | `--perf-probe` 启动时挂载 `GameplayRunLoop` 与 `PerfProbe`，输出平均 / 最大帧时间、池水位、等级、击杀和 GameClock 指标 JSON | `client/tools/perf_probe.gd` |
| 重开 / 回标题 | `GameplayRunLoop` 发出重开或回标题信号后，由启动脚本清理运行时和 gameplay 对象池，再重新挂载 run 或标题菜单 | `restart_requested` / `quit_to_title_requested` |

## 公共 API

无。该模块目前只提供启动烟雾验证，不对其他系统暴露 API。

## Signal / Event

无。

## 数据与契约

- 通过 `DataLoader.validate_project_data()` 间接读取 F3 目标数据和 `client/locale/strings.csv`。
- `client/project.godot` 的默认 viewport 为 1920×1080；窗口禁止任意拖拽缩放，2D 内容和 UI 通过 `display/window/stretch/mode="canvas_items"` 与 `display/window/stretch/aspect="keep"` 在屏幕比例不匹配时保比例加黑边。后续设置页应只暴露经过验证的分辨率预设列表，不接受任意宽高输入。
- 启动日志输出 `data_schema_ok`、`player_stats`、`characters`、`weapons`、`enemies`、`hazards`、`spawn_waves`、`relics`、`active_items`、`consumables`、`locale_keys`、`growth_levels`、`growth_pools`、`game_modes`、`meta_upgrades`、`meta_unlocks` 等 smoke 计数。
- 启动脚本本身不包含玩家可见文本；标题、HUD、设置、结算面板和局外升级面板文案见 `client/locale/strings.csv`。
- 标题菜单的“继续游戏”只在 `SaveManager.has_save(slot_0, run)` 为真时可见；“局外升级”常驻可见并由 `MetaProgressionPanel` 展示 `MetaProgressionSystem` 的 profile / upgrade summaries。开始新局和重开会删除旧 `run` 存档，避免重复继续旧局。若继续读取失败或坏档被隔离，标题菜单显示 `ui_run_save_unavailable` 提示并隐藏继续按钮。成功继续后，`GameplayRunLoop` 会按 payload 的 `ui_restore` 回到普通游玩、暂停菜单或升级选择面板。

## 依赖

- 上游依赖：Godot 4.6.3 项目加载机制、已注册的 F2 autoload。
- 下游调用方：`TitleMenu` 和 F6 阶段的 `MetaProgressionPanel` 场景由本启动脚本通过 `UIManager` 挂载，`GameplayRunLoop` 场景由本启动脚本创建和清理。
- 禁止依赖：不得引用 MVP 场景或脚本；不得用启动脚本临时拼长期 gameplay / UI 层级；不得提前绕过未来 F2 autoload 边界。

## 扩展点

- F2 落地 autoload 后，可以把本场景作为启动烟雾场景继续保留；F4 阶段只承载最小标题 / run 编排，后续 F7 主菜单落地时再切换入口。
- 新增正式主菜单、加载流程或设置 UI 时应新增对应模块文档，不把长期职责塞进本启动占位脚本。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 更换主场景 | `client/project.godot` | 本文档、`client/README.md`、`docs/AI导航.md` | `tools/godot_bridge.py --project client headless-boot` |
| 调整默认分辨率 / 拉伸策略 | `client/project.godot` | 本文档、`client/README.md`、相关 UI 模块文档 | `headless-boot` + `runtime-smoke` + 手动不同窗口尺寸检查 |
| 增加启动前检查 | `client/scripts/boot/formal_client_boot.gd` | 本文档；必要时新增模块文档 | headless boot |
| 调整 gameplay runtime 挂载 / 继续游戏 | `formal_client_boot.gd`、`gameplay_run_loop.tscn`、`gameplay_run_loop.gd` | 本文档、`docs/代码/gameplay_runtime.md`、AI导航 | headless boot、`runtime-smoke`、`save-smoke`、手动保存续局 |
| 调整标题局外升级入口 | `formal_client_boot.gd`、`title_menu.tscn`、`meta_progression_panel.tscn`、对应脚本 | 本文档、`docs/代码/gameplay_runtime.md`、`docs/代码/meta_progression_system.md`、AI导航 | headless boot、`meta-smoke`、手动标题菜单点开 |
| 调整标题设置入口 | `formal_client_boot.gd`、`title_menu.tscn`、`settings_panel.tscn`、对应脚本 | 本文档、`docs/代码/settings.md`、AI导航 | headless boot、`settings-smoke`、`runtime-smoke` |
| 调整 F7 设置 smoke 挂载 | `formal_client_boot.gd`、`client/tools/settings_smoke.gd` | 本文档、`docs/代码/settings.md`、AI导航 | headless boot、`settings-smoke` |
| 调整 F6 smoke 挂载 | `formal_client_boot.gd`、`client/tools/meta_progression_smoke.gd` | 本文档、`docs/代码/meta_progression_system.md`、AI导航 | headless boot、`meta-smoke` |
| 调整 F8 runner 挂载 | `formal_client_boot.gd`、`client/tools/l1_smoke.gd`、`client/tools/replay_smoke.gd`、`client/tools/replay_runner.gd`、`client/tools/golden_replay_capture.gd`、`client/tools/perf_probe.gd` | 本文档、Replay / 测试策略 / F8 工作包 | `l1-smoke`、`replay-smoke`、`replay-runner`、`capture-golden-replay`、`perf-probe` |
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
| 标题菜单看不到局外升级 | `TitleMenu` 是否发出 `meta_progression_requested`；`ui_meta_progression` 是否在 locale 中；`FormalClientBoot` 是否连接该 signal |
| 局外升级面板关闭后没回标题 | `_on_meta_progression_closed()` 是否 `UIManager.pop()` 顶层面板；`UIManager.top()` 是否为 `MetaProgressionPanel` |
| 设置面板关闭后没回标题 | `_on_settings_panel_closed()` 是否只弹出 `SettingsPanel`；`UIManager.top()` 是否为设置面板 |
| 有 run 存档但没有继续按钮 | `SaveManager.has_save(slot_0, run)` 是否为真；旧存档是否 hash mismatch 被隔离；标题菜单是否显示 `ui_run_save_unavailable` |

## 测试义务

- F1 必跑 headless 启动验证：`tools/godot_bridge.py --project client headless-boot`。
- 修改 `--save-smoke` 挂载或 SaveManager 启动诊断时，追加 `python tools/godot_bridge.py --project client save-smoke`。
- 修改 `--settings-smoke` 挂载或 Settings 持久化启动诊断时，追加 `python tools/godot_bridge.py --project client settings-smoke`。
- 修改 `--meta-smoke` 挂载或 MetaProgressionSystem 启动诊断时，追加 `python tools/godot_bridge.py --project client meta-smoke`。
- 修改 `--l1-smoke` / `--replay-smoke` / `--replay-runner` / `--capture-golden-replay` / `--perf-probe` 挂载时，追加对应 `python tools/godot_bridge.py --project client l1-smoke`、`replay-smoke`、`replay-runner`、`capture-golden-replay`、`perf-probe`；改 golden 对照逻辑时还要跑 `replay-runner --replay-file client/tests/replays/golden_basic_run.replay --rerun-runtime-summary`。
- 修改标题局外升级入口或 `MetaProgressionPanel` 挂载时，追加 `python tools/godot_bridge.py --project client meta-smoke` 并做一次手动标题菜单点开检查。
- 修改标题设置入口或 `SettingsPanel` 挂载时，追加 `python tools/godot_bridge.py --project client settings-smoke` 与 `python tools/godot_bridge.py --project client runtime-smoke`。
- 修改长期文档或索引后跑 `tools/docs_health_check.py`。
- 不需要 GUT 单测；该模块只做 smoke / gameplay runtime 编排。改 DataLoader schema 时按 DataLoader 测试义务处理；改 gameplay runtime 挂载时跑 headless boot。

## 迁移 / 兼容

不影响存档或数据 schema。F8 新增 `--capture-golden-replay` 与 `--rerun-runtime-summary` 只在 headless 工具参数下生效，不改变正常启动路径。

## 相关文档

- `docs/正式项目工作规划.md`
- `docs/代码文档规范.md`
- `docs/测试策略.md`
- `docs/AI导航.md`
- `docs/代码/gameplay_runtime.md`
