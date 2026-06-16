# UIManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `UIManager` autoload 的代码契约权威；改 UI 栈 API、暂停联动、节点元数据或测试义务时必须同步本文档。

## 职责

- `UIManager` 负责统一创建、压栈、出栈、替换和清空 UI 场景。
- UI 弹窗、菜单、升级选择、结算界面等后续都应通过 `UIManager.push()` / `pop()` 进入界面栈。
- 带 `pauses_game` 元数据或同名布尔属性的 UI 节点会请求 `GameState.PAUSED`，由 `UIManager` 负责在栈清掉后恢复进入 UI 前的状态。
- 当前切片不负责焦点管理、输入路由、音频 ducking、动画过渡或 UI 资源加载缓存；这些在 F7 / 具体 UI 切片补齐。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 加一个弹窗 | 本文档公共 API 与节点元数据说明 |
| 做暂停菜单 | 本文档暂停联动、`docs/代码/game_state.md` |
| 做语言刷新 | `docs/代码/localization.md` |
| 做 UI 测试 | 本文档测试义务与 `docs/测试策略.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/ui_manager.gd` | `UIManager` autoload 脚本 |
| `client/project.godot` | autoload 注册 |
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
| 压栈 | 实例化 `PackedScene`、挂到 `UIRoot`、记录栈、检查暂停请求 | `push()` / `ui_pushed` |
| 出栈 | 移除栈顶节点、广播、排队释放，并按需恢复暂停前状态 | `pop()` / `ui_popped` |
| 替换 | 弹出栈顶，再压入新场景 | `replace()` / `ui_replaced` |
| 清空 | 逐个弹出并释放当前栈 | `clear()` / `ui_cleared` |

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

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `ui_pushed` | `node`, `context` | UI 场景成功压栈后 |
| `ui_popped` | `node` | UI 场景出栈并准备释放前 |
| `ui_cleared` | 无 | `clear()` 完成后 |
| `ui_replaced` | `node`, `context` | `replace()` 压入新场景后 |

## 数据与契约

UI 根节点可用两种方式声明暂停请求：

- `node.set_meta("pauses_game", true)`
- 脚本上提供布尔属性 `pauses_game = true`

这是当前最小契约。后续可扩展 `modal`、`music_duck`、焦点策略、关闭行为等元数据，但新增字段必须写回本文档和对应 UI 模板。

## 依赖

- 上游依赖：`GameState` 负责状态切换和 `get_tree().paused` 联动。
- 下游调用方：暂停菜单、设置菜单、升级选择、结算面板、局外成长界面。
- 禁止依赖：业务代码不得直接 `add_child` UI 弹窗；暂停逻辑不得直接读写 `get_tree().paused`。

## 扩展点

- 新 UI 场景：放入后续 `client/scenes/ui/`，由调用方以 `PackedScene` 传给 `push()`。
- 暂停菜单：根节点标记 `pauses_game=true`，由 `UIManager` 触发 `GameState.PAUSED`。
- 焦点管理：后续在 `push()` 结束后统一设置首个焦点控件，避免每个菜单散写。
- 过渡动画：后续可在 `push()` / `pop()` 内加入统一动画，但不能破坏栈语义。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增 UI 元数据 | `ui_manager.gd`、UI 模板 | 本文档、AI 导航 | L1 + L2 |
| 加暂停菜单 | UI 场景、`GameState`、`UIManager` | 本文档、GameState 文档 | L2 + L5 暂停 checklist |
| 加设置菜单 | UI 场景、`Settings`、`Localization` | 三份模块文档 | L2 + 手动设置 checklist |
| 改 UI 栈语义 | `ui_manager.gd` | 本文档、测试策略 | L1 + L2 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| UI 没显示 | `PackedScene` 是否为空，节点是否挂到 `UIRoot` |
| 暂停菜单不暂停 | 根节点是否设置 `pauses_game=true` |
| 关闭 UI 后状态错误 | `_state_before_ui_pause` 是否被其他系统提前改写 |
| 暂停时 UI 不响应 | UI 节点和 `UIRoot` 的 `process_mode` 是否为 `ALWAYS` |

## 测试义务

- 当前切片必跑 L0 和 L2 headless boot，确认 autoload 和空栈启动无错。
- 后续引入 GUT 后，需要覆盖 push/pop 栈顺序、`replace()`、`clear()`、暂停请求和恢复状态。
- 接入暂停菜单后，需要执行 L5 暂停 / UI 栈 checklist。

## 迁移 / 兼容

当前没有 UI 资源迁移。未来如果持久化 UI 恢复点或 `run` 续局中的 UI 状态，字段必须归入 `SaveManager` 的 `run` 快照契约，`UIManager` 只负责运行时恢复。

## 相关文档

- `docs/游戏设计文档.md` §9.14
- `docs/代码/game_state.md`
- `docs/代码/settings.md`
- `docs/代码/localization.md`
- `docs/测试策略.md`
