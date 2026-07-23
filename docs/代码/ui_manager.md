# UIManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `UIManager` autoload 的代码契约权威；改 UI 栈 API、暂停联动、节点元数据或测试义务时必须同步本文档。

## 职责

- `UIManager` 负责统一创建、压栈、出栈、替换和清空 UI 场景。
- UI 弹窗、菜单、升级选择、结算界面等后续都应通过 `UIManager.push()` / `pop()` 进入界面栈。
- 正式开始 / 继续 / 重开加载界面也由 `UIManager` 管理；`LoadingScreen` 全屏阻断指针与菜单输入，但不声明 `pauses_game`，加载期状态由 `GameState.LOADING` 表达。
- 带 `pauses_game` 元数据或同名布尔属性的 UI 节点会请求 `GameState.PAUSED`，由 `UIManager` 负责在栈清掉后恢复进入 UI 前的状态。
- 当前切片不负责音频 ducking、动画过渡或 UI 资源加载缓存；F7 已开始统一栈顶返回请求和 push 后默认焦点兜底。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 加一个弹窗 | 本文档公共 API 与节点元数据说明 |
| 做暂停菜单 | 本文档暂停联动、`docs/代码/game_state.md` |
| 做语言刷新 | `docs/代码/localization.md`、目标 UI 脚本的 `refresh_texts()` |
| 做 UI 测试 | 本文档测试义务与 `docs/测试策略.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/ui_manager.gd` | `UIManager` autoload 脚本 |
| `client/project.godot` | autoload 注册 |
| `client/scenes/ui/settings_panel.tscn` | F7 设置面板，通过标题菜单和暂停菜单压栈 |
| `client/scenes/ui/loading_screen.tscn` | ADR #157 的全屏玩家加载遮罩，`process_mode=ALWAYS` |
| 后续 `client/scenes/ui/` | UI 场景归属位置 |

## 场景 / 节点结构

启动时 `UIManager` 创建内部节点：

```text
UIManager (autoload Node)
└── UIRoot (CanvasLayer, process_mode=ALWAYS)
```

所有通过 `push()` 创建的 UI 根节点都会挂到 `UIRoot` 下，并被记录在内部栈中。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | 创建 `CanvasLayer` 根节点并允许暂停时处理 | `_ready()` |
| 压栈 | 实例化 `PackedScene`、挂到 `UIRoot`、记录栈、检查暂停请求；仅在最近使用手柄导航时延后一帧把焦点放到 UI 内部 | `push()` / `ui_pushed` |
| 出栈 | 移除栈顶节点、广播、排队释放，并按需恢复暂停前状态 | `pop()` / `ui_popped` |
| 替换 | 弹出栈顶，再压入新场景 | `replace()` / `ui_replaced` |
| 清空 | 逐个弹出并释放当前栈 | `clear()` / `ui_cleared` |
| 返回 | `InputService` 的 `ui_back` 边沿只请求栈顶节点执行 `request_close()`；栈顶不声明该方法时不自动出栈 | InputService action signal / query |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `push(scene, context = {})` | `PackedScene`、上下文 | UI 根节点或 `null` | scene 为空会 `push_error` |
| `pop()` | 无 | 被弹出的节点或 `null` | 节点会 `queue_free()`，调用方不应继续持有使用 |
| `replace(scene, context = {})` | 新场景、上下文 | 新 UI 根节点或 `null` | 会触发一次 pop 和一次 push |
| `clear()` | 无 | `void` | 释放全部 UI 节点 |
| `stack_size()` | 无 | `int` | 当前栈深度 |
| `top()` | 无 | 栈顶节点或 `null` | 返回内部节点引用，不要手动移出树 |
| `stack_snapshot()` | 无 | `Array[Node]` | 返回栈节点数组拷贝 |
| `navigation_focus_visible()` | 无 | `bool` | 从 `InputService` 当前设备族派生；手柄为 `true`，键鼠为 `false` |
| `event_requests_navigation_focus(event)` | `InputEvent` | `bool` | deprecated 兼容入口；正式标题 / UI 应读取 InputService 设备族，不自行解释物理 event |
| `grab_focus_for_navigation(control)` | `Control` | `bool` | 仅在 `navigation_focus_visible()` 为 `true` 且控件可聚焦时抓焦点 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `ui_pushed` | `node`, `context` | UI 场景成功压栈后 |
| `ui_popped` | `node` | UI 场景出栈并准备释放前 |
| `ui_cleared` | 无 | `clear()` 完成后 |
| `ui_replaced` | `node`, `context` | `replace()` 压入新场景后 |
| `navigation_focus_visibility_changed` | `visible` | 最近输入设备导致导航焦点显示策略变化时 |

## 数据与契约

UI 根节点可用两种方式声明暂停请求：

- `node.set_meta("pauses_game", true)`
- 脚本上提供布尔属性 `pauses_game = true`

可关闭 UI 根节点应提供 `request_close()` 方法。`UIManager` 监听 `ui_back` 后只调用栈顶节点的 `request_close()`，不盲目 `pop()`，避免升级面板、失败面板等有业务选择含义的界面被通用返回键绕过。

可聚焦 UI 根节点可选提供 `grab_default_focus()`。如果没有该方法，`UIManager.push()` 会在需要显示导航焦点时延后一帧扫描该 UI 内第一个可见、可聚焦、未禁用的 `Control` 并抓取焦点；如果焦点已经在新 UI 内，则不覆盖。

导航焦点只在 `InputService` 报告最近设备族为手柄时显示；切回键鼠时释放当前焦点，避免按钮常驻高亮。GUIDE 的 `ui_up/down/left/right` 由 `InputService` 窄桥接为 Godot 内置 `ui_*` 事件，让 `Control` 保留原生焦点导航；项目 `ui_confirm` / `ui_back` 语义仍由 `InputService` 裁决，避免同一物理输入被 UIManager 与 Godot Control 双重消费。

这是当前最小契约。后续可扩展 `modal`、`music_duck`、更细的焦点策略、关闭行为等元数据，但新增字段必须写回本文档和对应 UI 模板。

`SettingsPanel` 本身不声明 `pauses_game`：从标题菜单打开时保持 `MAIN_MENU`，从暂停菜单打开时依靠下层 `PauseMenu.pauses_game=true` 维持 `PAUSED`。关闭时只弹出设置面板，下面的标题或暂停菜单保持可见。

`LoadingScreen` 本身也不声明 `pauses_game`：`FormalClientBoot` 在压栈前显式进入 `GameState.LOADING`。其全屏根 `Control` 使用 `mouse_filter=STOP`，层级高于普通菜单，且不提供 `request_close()`；玩家不能通过 `ui_back`、鼠标或菜单按钮取消加载。准备成功时启动层只在它仍为栈顶时 `pop()`，随后才激活 gameplay。

## 依赖

- 上游依赖：`GameState` 负责状态切换和 `get_tree().paused` 联动；`InputService` 提供 UI action、context 与最近设备族。
- 下游调用方：标题菜单、暂停菜单、设置菜单、升级选择、结算面板、局外成长界面。
- 禁止依赖：业务代码不得直接 `add_child` UI 弹窗；暂停逻辑不得直接读写 `get_tree().paused`。

## 扩展点

- 新 UI 场景：放入后续 `client/scenes/ui/`，由调用方以 `PackedScene` 传给 `push()`。
- 玩家加载 UI：复用 `LoadingScreen`，不要为开始 / 继续 / 重开分别创建场景，也不要绕过 `UIManager` 手动挂载。
- 暂停菜单：根节点标记 `pauses_game=true`，由 `UIManager` 触发 `GameState.PAUSED`；如果暂停菜单从 `GameState.LEVEL_UP` 上方打开，`UIManager` 也要把 `LEVEL_UP` 记录为暂停前状态，关闭菜单后恢复回升级选择而不是 `PLAYING`。
- 焦点管理：`push()` 结束后按最近输入设备决定是否给新 UI 设置初始焦点；复杂界面可实现 `grab_default_focus()` 自定义，简单界面走首个可聚焦控件兜底。鼠标 / 键盘模式下不显示常驻按钮高亮，手柄导航时恢复焦点。
- 返回行为：可关闭 UI 实现 `request_close()`；`ui_back` 只作用于当前栈顶并走该方法，关闭按钮和返回键应复用同一业务路径。
- 过渡动画：后续可在 `push()` / `pop()` 内加入统一动画，但不能破坏栈语义。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增 UI 元数据 | `ui_manager.gd`、UI 模板 | 本文档、AI 导航 | L1 + L2 |
| 加暂停菜单 | UI 场景、`GameState`、`UIManager` | 本文档、GameState 文档 | L2 + L5 暂停 checklist |
| 加设置菜单 | UI 场景、`Settings`、`Localization` | 三份模块文档 | L2 + 手动设置 checklist |
| 改标题 / 暂停设置入口 | `title_menu.gd`、`pause_menu.gd`、`formal_client_boot.gd`、`gameplay_run_loop.gd` | Settings / GameplayRuntime 文档 | `settings-smoke` + `runtime-smoke` |
| 改 UI 栈语义 | `ui_manager.gd` | 本文档、测试策略 | L1 + L2 |
| 改加载遮罩 / 阻断行为 | `loading_screen.tscn/.gd`、`formal_client_boot.gd` | 本文档、Gameplay Loading 文档 | `loading-smoke` + 手动中英文 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| UI 没显示 | `PackedScene` 是否为空，节点是否挂到 `UIRoot` |
| 暂停菜单不暂停 | 根节点是否设置 `pauses_game=true` |
| 关闭 UI 后状态错误 | `_state_before_ui_pause` 是否被其他系统提前改写；从升级面板上方关闭暂停菜单时应恢复到 `LEVEL_UP` |
| 暂停时 UI 不响应 | UI 节点和 `UIRoot` 的 `process_mode` 是否为 `ALWAYS` |
| 从暂停菜单打开设置后无法继续 | `SettingsPanel` 是否是栈顶；关闭按钮是否弹出设置面板而不是底层 `PauseMenu` |
| 按返回键没有关闭 UI | 栈顶是否实现 `request_close()`；InputService 的 UI context / `ui_back` 是否有效 |
| 手柄焦点丢失 | InputService 最近设备族、UI context 和 UI bridge 是否有效；UI 是否有可见且 `focus_mode != FOCUS_NONE` 的控件；复杂界面是否需要实现 `grab_default_focus()` |
| 鼠标操作时按钮仍高亮 | 是否绕过 `UIManager.grab_focus_for_navigation()` 直接调用了 `grab_focus()` |
| 加载时仍能点击底层菜单 | `LoadingScreen/Root.mouse_filter` 是否为 `STOP`、CanvasLayer 是否高于普通 UI、是否意外暴露 `request_close()` |

## 测试义务

- 当前切片必跑 L0 和 L2 headless boot，确认 autoload 和空栈启动无错。
- 后续引入 GUT 后，需要覆盖 push/pop 栈顺序、`replace()`、`clear()`、暂停请求和恢复状态。
- 接入暂停菜单或设置面板后，需要执行 L5 暂停 / UI 栈 checklist；自动覆盖包括标题 / 暂停设置入口、`ui_back` 只关闭栈顶、键鼠不显示常驻焦点、手柄导航焦点、context 隔离和 UI bridge 不双触发。
- 修改 `LoadingScreen` 或玩家加载 UI 栈行为时，追加 `python tools/godot_bridge.py --project client loading-smoke`，并手动检查 `zh_CN` / `en` 文案和旋转动画。

## 迁移 / 兼容

当前没有 UI 资源迁移。未来如果持久化 UI 恢复点或 `run` 续局中的 UI 状态，字段必须归入 `SaveManager` 的 `run` 快照契约，`UIManager` 只负责运行时恢复。

## 相关文档

- `docs/游戏设计文档.md` §9.14
- `docs/代码/game_state.md`
- `docs/代码/settings.md`
- `docs/代码/localization.md`
- `docs/代码/input_service.md`
- `docs/代码/gameplay_loading.md`
- `docs/测试策略.md`
