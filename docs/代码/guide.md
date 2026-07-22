# G.U.I.D.E 插件模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 vendored G.U.I.D.E 源码架构、本地维护补丁和人工升级边界的权威；项目怎样消费输入、保存绑定及录制回放归 `docs/代码/input_service.md`，版本、哈希与许可清单归 `client/addons/README.md`。

## 1. 定位与维护边界

正式客户端固定使用 G.U.I.D.E `0.14.0`（Godot Unified Input Detection Engine）作为物理输入引擎。插件负责把键盘、鼠标、手柄和可选触摸事件解释为类型化 action，组合 mapping context，提供 modifier / trigger、运行时重绑定与按键提示渲染。业务系统不得直接依赖这些类型；唯一项目适配边界是 `InputService`。

| 层 | 负责 | 不负责 |
|----|------|--------|
| 上游 GUIDE | 物理事件影子状态、input/modifier/trigger 求值、context 合并、remapping、提示格式化、编辑器资源工具 | 项目 action 词表、GameState 语义、回放格式、设置迁移、业务 intent |
| 本地维护型 fork | Godot 4.7.1 与项目 lint 兼容、确定性 context 排序、捕获状态修复、禁用插件改 autoload、源码导航头 | 借维护之名改写上游公共模型或偷偷启用高级 trigger |
| `InputService` | 项目 action 常量、context 生命周期、归一化 intent、重绑定持久化、设备提示、回放注入、UI 窄桥 | 复制一套 GUIDE 求值器或把插件类型泄露给 gameplay |
| 业务调用方 | 消费 `Vector2` / `bool` intent 和项目 signal | 直接访问 `GUIDE`、`Input`、`InputMap` 或物理键码 |

- 官方来源与发布快照见 `client/addons/README.md`；插件不会自动更新。
- 上游代码可按项目需要修改，但必须保留 Jan Thomä 的 `client/addons/guide/LICENSE.md` MIT 许可，以及 `client/addons/guide/THIRD_PARTY_NOTICES.md` 中 Xelu 输入图标的 CC0 来源与 Lato 字体的完整 SIL OFL 1.1 许可。
- `client/addons/guide/` 会随正式资源导出，按发行包第三方依赖处理。
- 当前正式路径只启用键鼠与单个通用手柄。touch、virtual joy、多本地玩家设备槽和组合 / 长按 / 连击等高级 trigger 仍是已入库但未采用的上游能力。

## 2. 代码地图

| 区域 | 主要入口 | 作用 |
|------|----------|------|
| Runtime Core | `guide.gd`、`inputs/guide_input_state.gd`、`guide_input_tracker.gd`、`guide_reset.gd` | 捕获 viewport/window 事件，维护影子输入状态，按帧求值并重置瞬时量 |
| Action / Context | `guide_action.gd`、`guide_mapping_context.gd`、`guide_action_mapping.gd`、`guide_input_mapping.gd` | 定义 action 类型与生命周期，把 context、action、input、modifier、trigger 组合为可求值图 |
| Inputs | `inputs/` | 键盘、鼠标、手柄轴/方向/按钮、触摸和 action-as-input 适配器 |
| Modifiers | `modifiers/` | deadzone、scale、normalize、swizzle、正负拆分、坐标转换等值变换 |
| Triggers | `triggers/` | pressed/down/released 以及 hold/tap/combo/pulse/chord 等状态机 |
| Remapping | `remapping/guide_remapper.gd`、`guide_remapping_config.gd`、`guide_input_detector.gd` | 枚举可重绑定 slot、检测输入、报告冲突并产出配置资源 |
| Prompt UI | `ui/guide_input_formatter.gd`、`ui/renderers/`、`ui/text_providers/`、`ui/icon_maker/` | 把有效 input 渲染为文本或异步 RichText 图标；支持键鼠和多类控制器图标 |
| Virtual Input | `ui/virtual_joy/` | 触摸摇杆和虚拟手柄事件；当前未接入正式项目 |
| Editor Tooling | `plugin.gd`、`editor/`、`debugger/` | Mapping Context 主面板、Inspector 编辑器、类/资源扫描和 debugger |
| Project Adapter | `client/scripts/autoload/input_service.gd` 与 `client/resources/input/` | 仅项目代码；定义正式 context、action、持久化、回放和 UI 桥 |

核心入口的文件头使用：

```gdscript
# Doc: docs/代码/guide.md
# Authority: client/addons/README.md, docs/决策记录.md ADR #151
```

小型 renderer、editor control、触摸脚本和单一 input 类由本文档统一覆盖，不要求每个文件重复加头。

## 3. 核心对象模型

### 3.1 `GUIDEAction`

一个 action 是稳定语义与当前值的资源。`action_value_type` 支持 `BOOL`、`AXIS_1D`、`AXIS_2D`、`AXIS_3D`，内部统一使用 `Vector3`，对外提供相应类型值。状态枚举为 `ONGOING` / `TRIGGERED` / `COMPLETED`；求值生命周期发出 `started`、`ongoing`、`triggered`、`just_triggered`、`completed`，中途取消另发 `cancelled` signal。

项目约束：

- 正式 gameplay action 名必须来自 `docs/词表与契约.md` 和生成的 `Actions` 常量。
- `move`、`aim` 使用 `AXIS_2D`；离散操作使用 `BOOL`。
- 业务不直接连接 `GUIDEAction` signal，由 `InputService` 统一采样和锁存。
- `emit_as_godot_actions` 只用于 `InputService` 的 Godot `Control` 导航兼容桥；它不是正式绑定权威。

### 3.2 Mapping graph

```text
GUIDEMappingContext
└── GUIDEActionMapping
    ├── GUIDEAction
    └── GUIDEInputMapping[]
        ├── GUIDEInput
        ├── GUIDEModifier[]
        └── GUIDETrigger[]
```

- `GUIDEInput` 读取影子状态并产生原始值。
- modifier 按资源声明顺序变换值；deadzone、scale、normalize 等应保留在资源层，不散落到业务代码。
- trigger 判定 `NONE` / `ONGOING` / `TRIGGERED`。没有显式 trigger 时按输入是否 actuated 使用默认行为。
- 同一 context 内允许一个 action 有多个 input mapping；值会合并。同一输入映射到多个 action 时，优先级和 `block_lower_priority_actions` 决定遮挡。

### 3.3 Context

`GUIDE.enable_mapping_context(context, disable_others, priority)`、`disable_mapping_context()` 和 `set_enabled_mapping_contexts()` 维护当前集合。数值越小优先级越高；同优先级按最近启用顺序决胜。项目 fork 用进程内单调序号记录此顺序，不读取系统时间，因此 context 排序不会成为回放非确定源。

正式 context 语义由 `InputService` 管理：

| context | 内容 | 生命周期 |
|---------|------|----------|
| `gameplay` | move、aim、pointer、fire、active item、interact、stats、pause | 实际游玩且没有独占 UI / 捕获时启用 |
| `ui` | 方向导航、确认、返回及安全关闭 | 标题和可交互 UI 启用，暂停时仍处理 |
| `debug` | `debug_*` action | 仅 debug/dev_tools 构建启用 |

输入捕获会暂存 context 集并暂时禁用它们，结束或取消后必须按原优先级恢复。业务不得在别处直接 enable / disable context。

## 4. 运行生命周期

1. Godot 按 `Settings → GUIDE → InputService → Replay` 创建 autoload。GUIDE 设为 `PROCESS_MODE_ALWAYS`，instrument 主 viewport 和后续 Window。
2. `GUIDEInputTracker` 将事件交给 `GUIDE.inject_input()`；`InputEventAction` 会被忽略，避免回灌 Godot action 再次触发 GUIDE。
3. `GUIDEInputState` 更新键、按钮、轴、鼠标和触摸的影子状态；失焦通知清理按住态。
4. GUIDE 在物理帧刷新需要物理处理的 modifier，在过程帧合并 active mapping、应用 modifier / trigger、更新 action 值并发 signal。
5. `InputService` 把 action 值转换为项目 `Vector2` / `bool` intent；短按边沿锁存到下一物理 tick，防止渲染帧高于物理帧时丢输入。
6. GUIDE 在映射或手柄连接变化时发出 `input_mappings_changed`；当前项目由 `InputService` 的重绑定完成、设备连接与最近输入处理器分别刷新绑定提示和设备族，若未来直接订阅该插件 signal 也只能留在适配层。
7. 回放不伪造物理事件，而通过 `InputService` 的 playback override 注入已归一化 intent；播放期间物理 GUIDE 输入不得污染结果。

## 5. Inputs、modifier 与 trigger 使用边界

当前采用：

- `GUIDEInputKey`、`GUIDEInputMouseButton`、`GUIDEInputMousePosition`。
- `GUIDEInputJoyButton`、`GUIDEInputJoyAxis1D`、`GUIDEInputJoyAxis2D`、`GUIDEInputJoyDirection`。
- deadzone、scale、normalize、正负方向 / swizzle 等构造移动和瞄准所需的简单 modifier。
- `Down` / `Pressed` 等能稳定映射到 `bool` 或连续值的基础 trigger。

当前禁止正式 gameplay 使用 hold、tap、combo、pulse、chord 等依赖过程帧时间或历史序列的高级 trigger。这些类型保留上游代码，但首次启用前必须定义 GameClock / replay 语义、增加确定性回归，并另行更新 ADR。

鼠标位置只在适配层转换：GUIDE 提供 viewport position，玩家相机 / Canvas 的 world transform 属于项目职责，不能写进通用插件资源。

## 6. 重绑定与提示

### 6.1 Remapper

`GUIDERemapper.initialize(contexts, config)` 以默认资源和现有 `GUIDERemappingConfig` 建立编辑副本；`get_remappable_items()` 返回稳定 slot，`get_input_collisions()` 只报告冲突，不替项目做策略决定；`set_bound_input()`、`restore_default_for()` 修改编辑副本，`get_mapping_config()` 返回可应用配置。

项目只公开“一组键鼠 + 一组手柄”slot。冲突由设置页在同设备、同有效 context 内提示“替换 / 取消”；互斥 context 可共享输入。Esc、Start / B 等安全关闭兜底不允许移除。配置、迁移、原子保存和损坏隔离见 `docs/代码/input_service.md`。

### 6.2 Detector

`GUIDEInputDetector` 支持 bool / 1D / 2D / 3D 类型过滤、设备过滤、启动倒计时、轴阈值、abort 输入与前后释放清理。项目 fork 必须保证：

- 2D 手柄轴用绝对幅度判断，负方向也能启动捕获。
- 在 `COUNTDOWN`、`INPUT_PRE_CLEAR`、`DETECTING` 或 `INPUT_POST_CLEAR` 任一阶段取消，都会停止 timer、释放临时 input、恢复 context、回到 `IDLE` 并只交付一次 null。
- 捕获期间事件标记 handled，避免同时触发菜单和 gameplay。

### 6.3 Formatter

`GUIDEInputFormatter.for_active_contexts()` / `for_context()` 创建 formatter：

- `action_as_text()` 同步返回可放进普通 Label 的文本。
- `action_as_richtext_async()` 异步生成 `[img]...[/img]`，调用方必须防止 await 返回时 UI 已释放或设备已切换。
- `formatting_options` 控制允许的设备 / 控制器样式；项目只通过 `InputService` 请求当前设备族提示。
- icon maker 使用 `user://_guide_cache`，这是可重建缓存，不是存档或设置权威。

## 7. 编辑器工具

- GUIDE 主面板编辑 `GUIDEMappingContext`、action mapping、input mapping、modifier 和 trigger。
- Inspector / class scanner 负责资源选择和可用 `class_name` 发现；resource scanner 的编辑器诊断不能引入 gameplay 时间依赖。
- debugger 可观察 active context / action，不是正式玩家 UI。
- `plugin.gd` 只注册编辑器界面和项目设置。上游 `_enable_plugin()` / `_disable_plugin()` 自动增删 autoload 的行为已禁用；`project.godot` 是 `GUIDE` autoload 的唯一权威。
- 禁止加入 updater 或自动覆盖 vendored 源码。升级只能走本文件第 11 节和插件清单的人工流程。

## 8. 本地补丁清单

所有补丁都视为项目维护代码，升级时逐项重放：

1. 禁止 editor plugin 自动添加 / 删除 `GUIDE` autoload，由项目显式固定顺序。
2. 按项目强类型规范修复成员声明顺序、危险 `:=`、缺失参数 / 返回类型与上游 GDScript 行尾空白，不设置 addon lint 豁免。
3. context 同优先级 tie-break 改用单调启用序号；编辑器 resource scanner 删除未使用的系统计时诊断。
4. `GUIDEInputDetector` 的 2D joy axis 检测使用绝对幅度，覆盖负轴。
5. detector 在倒计时和清理阶段也能可靠 abort、释放临时状态、恢复原 context 并回到 idle。
6. detector 提供窄化的 synthetic-event 注入入口，供项目 headless 输入 smoke 复用真实检测路径。
7. `GUIDE.release_pressed_inputs()` 为项目 context 切换提供窄化 pressed-state 清理；`GUIDEInputState.focus_lost()` 复用同一路径清理 pending / active 键鼠与手柄按钮 / 轴，避免切换或失焦后残留按住态。
8. 默认按键文本 provider 在 headless 显示服务器下跳过不受支持的本地化标签 API，回退到物理键码字符串。
9. 由 Godot 4.7.1 规范化提示素材 `.import` 并补齐缺失 UID；这些导入元数据随固定发布包一起维护。
10. 核心 runtime / remapping / formatting / editor 入口增加本文档和 ADR #151 的源码头，不改变正式业务 API。

除此清单外，不做无关格式化或功能改写。发现必须改变上游公共 API 的问题时，先更新本文档、ADR 和项目适配层测试。

## 9. 依赖与禁区

- 上游依赖：Godot 4.7.1 `InputEvent`、Viewport / Window input、Resource、EditorPlugin、RichTextLabel 图像缓存。
- 下游唯一正式调用方：`InputService`；editor 工具可直接使用 GUIDE 类型。
- 禁止 gameplay、UI、Replay、Settings 直接依赖 GUIDE 资源路径或 `GUIDE.*`。
- 禁止业务读取 `Input.is_key_pressed()`、`Input.is_joy_button_pressed()`、原始 axis 或自己写物理键码分支。
- `InputMap` 只允许出现在 GUIDE 内部、`InputService` 的 Godot UI 兼容桥和输入测试边界。
- 插件不得调用 `GameClock`。GUIDE 是设备层；项目确定性由归一化 intent 和 Replay 负责。

## 10. 常见改动与排障

| 目标 / 现象 | 优先检查 |
|-------------|----------|
| 加项目 action | 先改词表 / 生成常量，再改 `client/resources/input/` 与 `InputService`；不要先改 GUIDE 类 |
| 加新物理输入类型 | `inputs/`、对应 formatter renderer / text provider、detector 与 smoke；确认是否要向业务暴露 |
| context 优先级异常 | `InputService` 当前状态、GUIDE active context 的 priority / serial、捕获是否恢复完整集合 |
| 快速点击偶尔丢失 | `InputService` 物理 tick 边沿锁存；不要让 gameplay 直接调用 `GUIDEAction.is_triggered()` |
| 失焦后角色继续移动 | `guide.gd` focus notification、`GUIDEInputState.focus_lost()` 与 `InputService` 清理 |
| 手柄负方向无法捕获 | 本地 `_try_detect_axis_2d()` 是否仍使用 `abs(event.axis_value)` |
| 取消捕获后无输入 | detector 是否回到 `IDLE`、context 是否恢复、abort input 是否 `_end_usage()` |
| 提示显示错误控制器 | `InputService` 最近设备族、formatter options、连接变化刷新和异步请求代次 |
| 编辑器禁用插件后运行时报错 | `project.godot` 的 `GUIDE` autoload 不应随插件开关被删除 |
| 更新后解析 / lint 错误 | 对照固定发布包和补丁清单，不要对整个 addon 做无关自动格式化 |

## 11. 测试与人工升级

修改插件 runtime、detector、formatter 或 editor 时至少运行：

- `python tools/lint_gdscript_rules.py`
- `python tools/lint_project_rules.py`
- `python tools/lint_semantic_rules.py --strict`
- `python tools/godot_bridge.py --project client input-smoke`
- `python tools/godot_bridge.py --project client settings-smoke`
- `python tools/godot_bridge.py --project client headless-boot`
- Godot 4.7.1 `--headless --editor --path client --quit-after ...` 编辑器解析

涉及 action 值 / context 时追加 runtime 和 replay smoke；涉及提示或真实设备识别时执行键鼠、至少一个手柄、热插拔和编辑器重启人工验收。

升级步骤：

1. 在仓库外下载目标官方发布包，记录版本、commit、SHA-256 与许可；不追默认分支。
2. 只比较 `addons/guide/`、许可证和发布说明；先阅读可能影响 action/remapping/formatter 的迁移项。
3. 替换 vendored 基线后逐项重放第 8 节补丁，保留 UID / `.import`。
4. 核对 `InputService` 使用的类、方法、signal 和序列化资源仍兼容；不自动迁移用户配置。
5. 更新 `client/addons/README.md`、Credits、本文档、ADR / 记忆，并运行完整输入、设置、回放、headless editor 与 pre-commit 验证。

## 12. 相关文档

- `docs/代码/input_service.md`
- `docs/代码/settings.md`
- `docs/代码/replay.md`
- `docs/代码/gameplay_runtime.md`
- `docs/决策记录.md` ADR #151
- `client/addons/README.md`
- [G.U.I.D.E 官方文档](https://godotneers.github.io/G.U.I.D.E/)
- [G.U.I.D.E 官方源码](https://github.com/godotneers/G.U.I.D.E)
