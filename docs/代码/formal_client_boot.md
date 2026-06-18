# FormalClientBoot 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式客户端 F1 启动骨架的代码契约权威；改启动场景、项目入口、节点结构或验证方式时必须同步本文档、`client/README.md`、`docs/AI导航.md` 与 `docs/AI记忆/current_state.json`。

## 职责

- 负责提供完整项目 `client/` 的最小 Godot 启动入口。
- 负责让 F1 阶段可以通过 headless 启动验证。
- 不负责 autoload、主菜单、玩法循环、输入、UI 或业务数据解释；这些属于 F2+。
- F2/F3 期间作为正式客户端 smoke 场景，负责触发 autoload 和数据 schema 启动检查；F4 起在数据校验通过后挂载最小可玩闭环 runtime。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改正式项目启动场景 | `client/project.godot` 与 `client/scenes/boot/main.tscn` |
| 改启动脚本行为 | `client/scripts/boot/formal_client_boot.gd` |
| 推进下一阶段 autoload | `docs/正式项目工作规划.md` F2 |
| 调试 F4 启动 | `docs/代码/f4_min_playable_loop.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/project.godot` | Godot 项目配置，`run/main_scene` 指向最小启动场景，默认 viewport 为 1920×1080，窗口拉伸采用 `canvas_items + keep` |
| `client/scenes/boot/main.tscn` | 正式项目最小启动场景 |
| `client/scripts/boot/formal_client_boot.gd` | 启动场景脚本，输出启动日志 |
| `client/scripts/gameplay/f4_run_loop.gd` | F4 数据校验通过后挂载的最小可玩闭环 runtime |
| `client/README.md` | 正式客户端运行说明 |

## 场景 / 节点结构

```text
FormalClientBoot (Node)
└── F4RunLoop (Node2D, runtime child when data schema passes)
```

根节点挂载 `res://scripts/boot/formal_client_boot.gd`。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| Godot 启动 | 读取 `client/project.godot` | `run/main_scene` |
| 主场景加载 | 实例化 `FormalClientBoot` 根节点 | 无 |
| `_ready()` | 调用 `DataLoader.validate_project_data()` 并输出正式客户端启动日志 | `print()` |
| F4 runtime 挂载 | 数据校验通过后创建 `F4RunLoop`，进入最小战斗闭环 | `add_child()`、`GameState.PLAYING` |

## 公共 API

无。该模块目前只提供启动烟雾验证，不对其他系统暴露 API。

## Signal / Event

无。

## 数据与契约

- 通过 `DataLoader.validate_project_data()` 间接读取 F3 目标数据和 `client/locale/strings.csv`。
- `client/project.godot` 的默认 viewport 为 1920×1080；窗口禁止任意拖拽缩放，2D 内容和 UI 通过 `display/window/stretch/mode="canvas_items"` 与 `display/window/stretch/aspect="keep"` 在屏幕比例不匹配时保比例加黑边。后续设置页应只暴露经过验证的分辨率预设列表，不接受任意宽高输入。
- 启动日志输出 `data_schema_ok`、`player_stats`、`characters`、`weapons`、`enemies`、`hazards`、`spawn_waves`、`relics`、`active_items`、`consumables`、`locale_keys`、`growth_levels`、`growth_pools`、`game_modes`、`meta_upgrades`、`meta_unlocks` 等 smoke 计数。
- 启动脚本本身不包含玩家可见文本；F4 HUD 文案见 `client/locale/strings.csv`。

## 依赖

- 上游依赖：Godot 4.6.3 项目加载机制、已注册的 F2 autoload。
- 下游调用方：F4 阶段的 `F4RunLoop` 由本启动脚本挂载。
- 禁止依赖：不得引用 MVP 场景或脚本；不得提前绕过未来 F2 autoload 边界。

## 扩展点

- F2 落地 autoload 后，可以把本场景作为启动烟雾场景继续保留；F4 阶段临时直接挂载最小可玩闭环，后续 F7 主菜单落地时再切换入口。
- 新增主菜单、加载流程或 UI 时应新增对应模块文档，不把长期职责塞进本启动占位脚本。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 更换主场景 | `client/project.godot` | 本文档、`client/README.md`、`docs/AI导航.md` | `tools/godot_bridge.py --project client headless-boot` |
| 调整默认分辨率 / 拉伸策略 | `client/project.godot` | 本文档、`client/README.md`、相关 UI 模块文档 | `headless-boot` + `f4-smoke` + 手动不同窗口尺寸检查 |
| 增加启动前检查 | `client/scripts/boot/formal_client_boot.gd` | 本文档；必要时新增模块文档 | headless boot |
| 调整 F4 runtime 挂载 | `formal_client_boot.gd`、`f4_run_loop.gd` | 本文档、`docs/代码/f4_min_playable_loop.md`、AI导航 | headless boot、手动跑一局 |
| 补目录说明 | `client/README.md` | `README.md`、`docs/AI导航.md` | docs health |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| headless 报 invalid project | `client/project.godot` 是否存在 |
| 主场景加载失败 | `run/main_scene` 是否指向 `res://scenes/boot/main.tscn` |
| 脚本编译失败 | `client/scripts/boot/formal_client_boot.gd` 类型和路径 |
| `data_schema_ok=false` | 查看同次 headless 日志中的 `[DataLoader]` schema 错误 |
| 数据通过但没有 F4 节点 | `formal_client_boot.gd` 是否创建 `F4RunLoop`，以及脚本编译是否失败 |

## 测试义务

- F1 必跑 headless 启动验证：`tools/godot_bridge.py --project client headless-boot`。
- 修改长期文档或索引后跑 `tools/docs_health_check.py`。
- 不需要 GUT 单测；该模块只做 smoke / F4 runtime 编排。改 DataLoader schema 时按 DataLoader 测试义务处理；改 F4 runtime 挂载时跑 headless boot。

## 迁移 / 兼容

不影响存档、数据 schema、回放或旧行为。

## 相关文档

- `docs/正式项目工作规划.md`
- `docs/代码文档规范.md`
- `docs/测试策略.md`
- `docs/AI导航.md`
- `docs/代码/f4_min_playable_loop.md`
