# Gameplay Loading 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式玩家入口加载流程的代码契约权威；改加载界面、开始 / 继续 / 重开编排、准备 / 激活边界、线程资源读取或失败回退时，必须同步本文档、FormalClientBoot / Gameplay Runtime / GameState / UIManager 文档、GDD、测试策略、AI 导航与项目记忆。

## 职责

- 为“开始游戏”“继续游戏”“重开一局”提供同一套玩家可见加载流程。
- 在重任务前先让全屏 `LoadingScreen` 至少渲染一帧，并在整个准备期维持 `GameState.LOADING`。
- 使用 Godot `ResourceLoader` 线程接口读取本局角色、敌人和模块 `PackedScene`；不创建或管理自定义 `Thread`。
- 把对象池预热、初始模块挂载和续局实体恢复留在主线程，并分批让出帧，保证旋转动画持续响应。
- 保证同时最多有一个玩家加载请求、一个 `LoadingScreen` 和一个 `GameplayRunLoop`。
- 准备成功后先移除加载界面，再激活 gameplay；失败时清理半成品 runtime / gameplay 对象池并回到标题菜单。
- 不负责应用冷启动、进入标题菜单前的数据校验耗时、百分比、阶段信息、取消操作或最低展示时长。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改加载界面视觉或文案 | `client/scenes/ui/loading_screen.tscn`、`client/scripts/ui/loading_screen.gd`、`client/locale/strings.csv` |
| 改开始 / 继续 / 重开入口 | `client/scripts/boot/formal_client_boot.gd` |
| 改资源准备与激活边界 | `client/scripts/gameplay/gameplay_run_loop.gd` |
| 改自动回归 | `client/tools/loading_smoke.gd`、`tools/godot_bridge.py` |
| 排查状态或 UI 栈 | `docs/代码/game_state.md`、`docs/代码/ui_manager.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scenes/ui/loading_screen.tscn` | 全屏暗色遮罩、场景内旋转图形、加载文字与 `AnimationPlayer` |
| `client/scripts/ui/loading_screen.gd` | `LoadingScreen` 本地化刷新与动画诊断 |
| `client/scripts/boot/formal_client_boot.gd` | 玩家加载请求、重入保护、加载 UI、成功激活与失败回退 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 玩家加载模式、线程资源读取、分帧准备、准备 / 激活边界 |
| `client/tools/loading_smoke.gd` | 开始、继续、重开、重复请求与失败清理回归 |
| `tools/godot_bridge.py` | `loading-smoke` 命令桥 |
| `client/locale/strings.csv` | `ui_loading` / `ui_loading_failed` |

## 场景 / 节点结构

```text
UIManager/UIRoot
└── LoadingScreen (CanvasLayer, process_mode=ALWAYS, layer=100)
    └── Root (Control, full rect, mouse_filter=STOP)
        ├── Backdrop (ColorRect)
        ├── Center
        │   └── Layout
        │       ├── Spinner (Control)
        │       │   └── Arc (Line2D)
        │       └── LoadingLabel (Label)
        └── SpinnerAnimation (AnimationPlayer, "spin" loop)

FormalClientBoot
└── GameplayRunLoop (准备期间已入树，但尚未激活)
```

旋转图形由场景内 `Line2D` 与 `AnimationPlayer` 构成，不依赖外部位图或首次导入缓存。

## 运行流程

| 阶段 | 发生什么 | 状态 / API |
|------|----------|------------|
| 请求开始 / 继续 / 重开 | `FormalClientBoot` 检查重入保护，清理旧 UI，进入 `LOADING` 并压入唯一 `LoadingScreen` | `_begin_player_gameplay_load()`、`UIManager.push()` |
| 首帧展示 | 延后一帧后才开始存档读取和 runtime 准备 | `await get_tree().process_frame` |
| 继续游戏读取 | 加载界面已可见后读取 / 校验 run envelope；坏档沿用既有不可用提示并回标题 | `SaveManager.load_envelope()` |
| Runtime 准备 | 入树前启用玩家加载模式；线程读取本局 actor / 模块 `PackedScene`，主线程分批预热池、挂载模块和恢复实体 | `configure_player_loading_mode(true)`、`ResourceLoader.load_threaded_request()` |
| 准备成功 | `GameplayRunLoop` 发出 `run_prepared`，启动层先弹出 `LoadingScreen`，再调用激活入口 | `run_prepared`、`activate_prepared_run()` |
| 激活 | 切换到 `PLAYING`，恢复 GameClock 与保存的暂停 / 升级 UI 状态；准备期间 gameplay 输入和时间均不推进 | `GameState.change_state(PLAYING)` |
| 准备失败 | 发出 `run_prepare_failed`；启动层清理半成品 runtime、gameplay 对象池和加载 UI，回标题并显示通用失败提示；续局失败时删除不可恢复的 run | `run_prepare_failed`、`PoolManager.clear_all()` |

同步工具路径不启用玩家加载模式：headless、replay、golden 与既有 smoke 仍在 `_ready()` 中完成同步准备并立即激活，保持确定性时序。

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `GameplayRunLoop.configure_player_loading_mode(enabled)` | `bool` | `void` | 必须在节点入树前调用；正式玩家入口传 `true`，工具入口保持默认 `false` |
| `GameplayRunLoop.activate_prepared_run()` | 无 | `bool` | 仅在准备成功且尚未激活时可调用；成功后进入 `PLAYING` 并恢复保存的 UI 状态 |
| `LoadingScreen.refresh_texts()` | 无 | `void` | 使用 `tr("ui_loading")` 刷新玩家可见文字 |
| `LoadingScreen.animation_is_playing()` | 无 | `bool` | 只读 smoke / 调试入口，不参与业务流程 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `GameplayRunLoop.run_prepared` | 无 | 所有资源、对象池、初始模块或续局实体已准备，但尚未进入 `PLAYING` |
| `GameplayRunLoop.run_prepare_failed` | `reason`, `restoring` | 玩家加载模式准备失败；`restoring` 表示是否来自续局 |
| `GameplayRunLoop.restore_failed` | `reason` | 兼容既有同步续局 / smoke 调用方；玩家入口同时使用 `run_prepare_failed` 统一回退 |

## 数据与契约

- 玩家可见文本只使用 `ui_loading` 与 `ui_loading_failed`，并同时提供 `zh_CN` / `en`。
- 加载界面不显示阶段、百分比、资源路径、技术错误或取消按钮。
- 不增加最低展示时间；准备完成即可移除。
- 不修改 run v4、SaveManager envelope、地图 hash、RNG 子流或 gameplay 行为。
- `GameState.LOADING` 在准备期间不暂停 SceneTree，但 gameplay 节点必须只在 `PLAYING` 时接受输入和推进 `GameClock`。
- 资源路径继续来自已校验的角色 / 敌人数据与模块 assignment，不在加载流程中新增裸路径分支。

## 依赖

- 上游依赖：`FormalClientBoot`、`GameplayRunLoop`、`GameState`、`UIManager`、`SaveManager`、`PoolManager`、`Localization`、Godot `ResourceLoader`。
- 下游调用方：标题菜单开始 / 继续按钮、局内重开信号、`loading-smoke`。
- 禁止依赖：自管 `Thread`、阻塞等待、外部位图 spinner、人工延时、业务脚本直接挂载加载 UI。

## 扩展点

- 未来若增加其他玩家触发的重型场景切换，应复用同一准备 / 激活边界，而不是复制新的加载布尔状态。
- 若未来需要真实进度，必须先有可验证的总工作量契约；不得把阶段名伪装成百分比。
- 冷启动优化和进入标题菜单前的加载属于独立任务，不在本模块内通过提前显示假加载界面解决。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 改遮罩 / spinner / 文案 | loading scene / script / locale | 本文档、locale 手册、UIManager 文档 | `loading-smoke` + 中英文手动检查 |
| 改开始 / 继续 / 重开编排 | `formal_client_boot.gd` | 本文档、FormalClientBoot 文档 | `loading-smoke`、`runtime-smoke`、`save-smoke` |
| 改线程资源读取或分帧批次 | `gameplay_run_loop.gd` | 本文档、Gameplay Runtime 文档 | `loading-smoke`、actor / module-world full + technical、四条黄金回放 |
| 改失败回退 | boot / run loop / SaveManager 调用边界 | 本文档、FormalClientBoot / SaveManager 文档 | `loading-smoke` 坏档与准备失败分支 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 点击后先卡住再出现加载界面 | 重任务是否在首个 `process_frame` 之前执行 |
| spinner 不转 | `LoadingScreen.process_mode`、`AnimationPlayer` 的 `spin` 是否循环、主线程工作是否分批让帧 |
| 同时出现两个加载界面 / RunLoop | `_player_load_in_progress` 是否在所有成功 / 失败出口正确维护 |
| 加载时 gameplay 已移动或计时 | 是否过早调用 `activate_prepared_run()` 或提前切到 `PLAYING` |
| 继续游戏恢复 UI 时闪出暂停菜单 | 是否在移除加载界面后才恢复 `ui_restore` |
| 失败后残留敌人 / UI | 是否清理半成品 RunLoop、`UIManager` 栈与 gameplay 对象池 |
| 工具 / replay 时序漂移 | 工具路径是否误启用了玩家加载模式 |

## 测试义务

- 必跑三档项目 lint、正式 headless boot 与 headless editor 加载。
- 必跑 `python tools/godot_bridge.py --project client loading-smoke`；它覆盖真实开始 / 继续 / 重开、双语文案刷新、旋转跨帧、输入 / 重入阻断、`GameClock` 在 `LOADING` 冻结、坏档隔离和准备失败清理。
- 改正式玩家加载入口或准备 / 激活边界时追加 `actor-scene-smoke`、`runtime-smoke`、`save-smoke`、完整及技术切片 `module-world-smoke`、`settings-smoke`、`l1-smoke` 和四条 checked-in golden replay runner。
- locale / UI 变化追加数据校验，并手动切换 `zh_CN` / `en` 检查文字、遮罩和旋转动画。
- `startup-probe`、`perf-probe` 与 Profiler 仍只在用户当次明确要求性能测试时运行。

## 迁移 / 兼容

本模块不修改存档、回放或数据 schema。旧工具入口保持同步准备；正式玩家入口增加的异步准备只改变加载期间的视觉与任务调度，不改变随机数、地图 assignment、对象快照或激活后的 gameplay 语义。

## 相关文档

- `docs/代码/formal_client_boot.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/game_state.md`
- `docs/代码/ui_manager.md`
- `docs/代码/save_manager.md`
- `docs/测试策略.md`
- `docs/游戏设计文档.md` §9.12 / §9.14
