# InputService 模块

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 权威范围：项目输入门面、规范 action 与归一化 intent、GUIDE context 生命周期、重绑定持久化、设备提示、Godot UI 兼容桥及 Replay v2 输入接管。插件内部架构见 [`guide.md`](guide.md)，action / binding id 白名单见 [`../词表与契约.md`](../词表与契约.md) §7，架构决策见 [`../决策记录.md`](../决策记录.md) ADR #151。

## 1. 一句话职责

`InputService` 是正式业务唯一输入入口：它把 G.U.I.D.E 的设备输入归一化为 `bool` / `Vector2` intent，并让本地玩家、回放以及未来 AI / 网络输入共享同一语义边界。

它不拥有物理输入解析实现（GUIDE）、游戏设置通用持久化（`Settings`）、回放文件格式（`Replay`）或 Godot `Control` 的鼠标点击派发。

## 2. 代码与资源地图

| 路径 | 职责 |
|------|------|
| `client/scripts/autoload/input_service.gd` | 项目门面；采样、边沿锁存、context、重绑定、提示、UI 桥和回放覆盖 |
| `client/scripts/contracts/actions.gd` | 从词表生成的规范 action 常量；业务代码引用 `Actions.*` |
| `client/resources/input/actions/*.tres` | GUIDE action 资源；`move`、`aim`、`pointer_position` 是 `Vector2`，其余为布尔 |
| `client/resources/input/contexts/gameplay.tres` | 移动、瞄准、开火、技能、交互、暂停与数值面板映射 |
| `client/resources/input/contexts/ui.tres` | UI 方向、确认、返回与暂停映射 |
| `client/resources/input/contexts/debug.tres` | 仅 `dev_tools` 生效的调试输入 |
| `client/tools/generate_guide_input_resources.gd` | 生成 / 更新项目 GUIDE `.tres` 资源的维护工具；不是运行时路径 |
| `user://input_bindings.tres` | `GUIDERemappingConfig` 当前绑定权威，`custom_data.schema_version = 1` |

autoload 启动顺序必须保持 `Settings → GUIDE → InputService → Replay`：`Settings` 提供 v1 迁移源，GUIDE 先初始化运行时，`InputService` 再加载资源与绑定，`Replay` 最后连接和接管 intent。

## 3. 稳定业务契约

### 3.1 规范 intent

业务只通过自动生成的 `Actions` 常量访问：

- `Actions.MOVE`：长度不超过 1 的 `Vector2` 移动 intent。
- `Actions.AIM`：最终归一化的 `Vector2` 瞄准 intent；方向键 / 右摇杆与鼠标 pointer 由玩家适配层按最近有效来源选择。
- `Actions.POINTER_POSITION`：viewport 坐标，只用于项目鼠标瞄准适配，不直接成为玩法方向。
- `Actions.FIRE`、`USE_ACTIVE_ITEM`、`INTERACT`、`SHOW_STATS_PANEL`、`PAUSE`：gameplay 布尔 intent。
- `UI_UP / DOWN / LEFT / RIGHT / CONFIRM / BACK`：UI 布尔 intent。
- `DEBUG_TOGGLE_CONSOLE` / `DEBUG_CLOSE_CONSOLE`：当前 `debug` context 的开发构建调试 intent。`debug_submit_command` 由聚焦的 LineEdit 原生确认事件处理，`debug_toggle_replay` 仍是已登记但尚未映射的预留 id。

旧 `move_up/down/left/right` 与 `aim_up/down/left/right` 只用于 `settings.cfg` v1 和 Replay v1 内存迁移，不得重新进入业务读取路径。

### 3.2 公开方法

| 方法 | 语义 |
|------|------|
| `vector(action_id, participant_id = "player_0") -> Vector2` | 读取规范二维 intent；非当前单机 participant 返回零向量 |
| `is_pressed(action_id, participant_id = "player_0") -> bool` | 读取当前布尔 intent |
| `pointer_viewport_position() -> Vector2` / `pointer_world_position(viewport) -> Vector2` | 读取内部 pointer action 的 viewport 坐标，或按目标 viewport canvas transform 转成世界坐标 |
| `publish_resolved_aim(value)` | Player 适配层把鼠标 / 方向来源合成为最终 aim 后发布；本地录制只记录这个结果 |
| `resolved_aim() -> Vector2` | 读取最终 aim；playback 模式直接返回回放注入的 `aim` |
| `should_use_pointer_aim() -> bool` | 本地物理输入下最近有效瞄准源是否为鼠标；回放期间固定为 `false` |
| `current_device_family() -> StringName` | 返回 `keyboard_mouse` 或 `gamepad` |
| `set_debug_capture_active(enabled)` | DebugConsole 可见时阻断 gameplay、启用 UI 输入语义；release 构建强制保持关闭 |
| `action_resource(action_id) -> GUIDEAction` | 仅项目输入 / UI 提示适配需要时取 GUIDE action；业务不要继续向下访问插件 |
| `prompt_text(action_id) -> String` | 从当前 remap 配置物化并去重安全兜底后，按当前设备生成纯文本提示 |
| `prompt_richtext_async(action_id) -> String` | 复用同一当前绑定映射生成异步 RichText 图标提示 |
| `binding_rows() -> Array[Dictionary]` | 设置页绑定行元数据：稳定 id、label key、设备槽可用性 |
| `binding_text(binding_id, device_group) -> String` | 指定绑定槽的人类可读输入 |
| `begin_remap(binding_id, device_group) -> bool` | 暂停 context 并开始限定设备类型的捕获 |
| `cancel_remap()` | 取消捕获并恢复原 context |
| `resolve_pending_remap(replace_conflicts) -> bool` | 冲突弹窗选择替换或取消 |
| `reset_bindings_to_defaults() -> bool` | 清空 remapping config、恢复发布默认并原子保存 |
| `set_playback_active(enabled)` / `playback_active()` | 开关 Replay 输入覆盖；切换时清空残留值 |
| `inject_playback_value(action_id, value, participant_id) -> bool` | Replay v2 注入 bool / Vector2 intent；仅 playback 模式接受 |
| `clear_playback_values()` | 清空当前回放值 |
| `bindings_path() -> String` | 返回当前绑定文件路径 |
| `debug_inject_input(event)` | 测试边界注入 GUIDE 原始事件；正式业务禁用 |

### 3.3 信号

| 信号 | 用途 |
|------|------|
| `action_pressed` / `action_released` | 物理 tick 可消费的布尔边沿，含 participant id |
| `vector_changed` | 二维 intent 变化 |
| `device_family_changed` | 最近使用设备族变化；设置页与交互提示应刷新 |
| `pointer_activity` | 鼠标移动或按下；UI 可释放手柄导航焦点，不承载 gameplay 瞄准值 |
| `bindings_changed` | 重绑定或恢复默认成功后刷新提示 |
| `remap_started` / `remap_conflict` / `remap_finished` | 设置页捕获与冲突弹窗生命周期 |

当前只支持 `player_0`。未来扩展 participant / 设备分槽时应扩展此门面，而不是让业务直接使用 GUIDE。

## 4. 帧与物理 tick 生命周期

1. GUIDE 在过程帧解析启用 context 的物理输入。
2. `InputService._process()` 采样 action；二维值归一化，布尔变化写入待处理边沿。
3. `InputService._physics_process()` 把边沿锁存并发布到物理 tick，避免高渲染帧率下漏掉短按。
4. `Player`、`WeaponSystem`、`SkillSystem`、`GameplayRunLoop`、菜单与调试控制台只读取 intent 或订阅门面信号。
5. 失焦、context 切换、手柄断开与 playback 切换必须清理残留按住值，必要时发出 release。

鼠标移动把最近瞄准源标记为 pointer；有效手柄 / 键盘方向瞄准把来源标记为 direction。`pointer_position` 保留 viewport 坐标，玩家适配层再结合相机转换为 world direction；回放记录的是最终 `aim`，不是屏幕坐标或原始事件。

## 5. Context 生命周期

| context | 启用条件 | 优先级 | 边界 |
|---------|----------|--------|------|
| `debug` | debug 构建或显式 `dev_tools` feature，release guard 强制关闭 | 20 | 发布构建不启用 |
| `gameplay` | `GameState.PLAYING` 且没有阻断 gameplay 的 UI 栈 | 10 | 正式玩法 intent |
| `ui` | 非 PLAYING、存在 UI 栈或 debug console 捕获文本 | 0 | UI 导航 / 返回 / 确认；调试控制台打开时阻断 gameplay |

GUIDE 用单调启用序号解决同优先级 context 的确定性顺序；禁止改回系统时间戳。捕获重绑定时全部 context 暂停，捕获完成、取消或异常清理后由 `InputService` 按上表重新计算，不能由设置页自行逐个恢复。

## 6. UI 兼容桥

Godot `Control` 的鼠标点击继续使用原生 GUI event。键盘 / 手柄导航由 `InputService` 把 GUIDE 的 `ui_up/down/left/right`、`ui_confirm`、`ui_back` 窄桥接为 Godot `ui_*` `InputEventAction`，仅用于现有焦点系统。

桥内允许 `Input.parse_input_event()`；业务脚本不得直接调用 `Input.*`、`InputMap.*` 或 `GUIDE.*`。Esc 与手柄 Start / B 等关闭 / 退出恢复键保留不可重绑定兜底，避免设置页失去出口。

## 7. 重绑定与持久化

### 7.1 稳定 binding id

binding id 是设置 UI 的绑定槽，不等于 action。完整白名单在词表 §7.1；关键二维组为：

- `input.move_stick` → `move` 手柄二维轴，默认左摇杆。
- `input.aim_stick` → `aim` 手柄二维轴，默认右摇杆。
- `input.move_*` / `input.aim_*` → 键鼠四方向子绑定。
- `input.fire` → `fire` 的键鼠 / 手柄槽。

普通 action 只有一组键鼠和一组手柄槽；首版不支持任意解绑、主副多槽或按手柄分别保存 profile。鼠标位置与 D-pad 兜底固定。

### 7.2 捕获、冲突与保存

- 捕获按 binding 的 value type 选择 bool 或二维轴，并限定键鼠 / 手柄设备族。
- 冲突只在同设备组、同有效 context 内判断；`remap_conflict` 交给 UI 显示“替换 / 取消”。
- 替换会清空冲突槽并写入新输入；取消不改变配置。
- 保存顺序为临时文件 → 旧文件备份 → 原子替换。无效、未来 schema 或损坏资源隔离到 invalid 文件并回退发布默认。
- `GUIDERemappingConfig.custom_data.schema_version` 当前为 `1`；未知 action、context、slot 或输入类型不得部分应用。

`settings.cfg` 当前 schema 为 v2。首次读取 v1 时，`Settings` 中旧 `input.*` 键只作为迁移源，转换成功后不再写回；绑定文件与 SaveManager 的 meta / run schema 相互独立。

## 8. 提示与设备切换

`InputService` 通过 GUIDE formatter 输出当前绑定：设置页按钮使用纯文本，已有缓存箱交互提示使用异步 RichText 图标并以纯文本立即兜底；headless 显示服务器直接返回纯文本，避免图标渲染器申请不可用纹理。设备族变化、绑定变化和语言变化都会刷新提示；异步结果以 generation 防止旧设备结果覆盖新提示。不为没有对应功能的 action 增加 HUD。

热插拔 / 断开时清理手柄残留状态并切换到仍有效设备提示。新增 prompt 展示时先复用 `prompt_text()` / `prompt_richtext_async()`，不要在 UI 中维护独立的“按键名映射表”。

## 9. Replay v2 边界

Replay v2 记录最终 intent：

```json
{
  "action": "aim",
  "value_type": "vector2",
  "value": [0.7071, -0.7071],
  "tick": 120,
  "time": 2.0,
  "participant_id": "player_0"
}
```

布尔 action 使用 `value_type: "bool"` 与布尔 `value`。播放时 `Replay` 先启用 playback，再调用 `inject_playback_value()`；此时本地 GUIDE 采样不污染业务值。v1 旧方向 action 只在加载内存中聚合成 `move` / `aim`，不重写源 fixture。详见 [`replay.md`](replay.md)。

## 10. 修改入口与禁止事项

| 需求 | 优先修改 |
|------|----------|
| 新增业务 action | 词表 §7 → 契约同步 → GUIDE action / context 资源 → InputService → 测试与文档 |
| 改默认键位 / 摇杆 | `client/resources/input/contexts/*.tres` 与 binding spec；同步设置文案 / smoke |
| 改玩家移动 / 瞄准语义 | InputService + Player 适配层 + Replay v2；不要改 GUIDE 设备底层 |
| 改重绑定规则 | InputService remap API、binding schema 与设置页；同步 `settings.md` |
| 改 prompt | InputService formatter 门面；插件 formatter 内部变化再读 `guide.md` |
| 升级 GUIDE | 先按 `client/addons/README.md` 人工比较发布包并重放本地补丁 |

禁止在业务代码中新增 `GUIDE.*`、`Input.*`、`InputMap.*` 或运行时动态创建 InputMap action。仅 GUIDE 插件内部、InputService UI 兼容桥和明确测试边界允许原始 API。

## 11. 故障排查

- **输入全为零**：确认 autoload 顺序、action / context 资源是否存在、当前 GameState / UI 栈是否启用了正确 context。
- **短按偶发漏掉**：检查是否绕过 `action_pressed` 边沿锁存，在过程帧直接消费 GUIDE trigger。
- **关闭窗口后仍持续移动**：检查失焦 / context / 手柄断开路径是否调用统一残留清理。
- **重绑定后界面无响应**：检查捕获取消 / 冲突取消是否清空 pending 状态并 deferred 恢复 context。
- **负轴摇杆捕获失败**：核对 GUIDE 本地 detector 补丁仍同时接受正负轴方向。
- **按键提示未更新**：监听 `device_family_changed`、`bindings_changed` 与语言变化；异步 RichText 结果应防止过期请求覆盖新状态。
- **回放受真实输入污染**：确认 playback 开关先于事件注入，业务没有直接读 GUIDE / Input。
- **绑定文件损坏**：确认 invalid 隔离、backup 与默认回退都生效，且没有把绑定写回 `settings.cfg`。

## 12. 验证义务

- `input-smoke`：键鼠 / 手柄移动瞄准、按钮边沿、context 隔离、失焦、设备切换、提示刷新、捕获取消、负轴轴组、冲突替换 / 取消和防锁死键。
- `settings-smoke`：v1 → v2 迁移、binding roundtrip、重启保持、恢复默认、损坏与未来版本回退。
- `replay-smoke` / `replay-input-smoke`：v2 bool / Vector2、鼠标最终 aim、v1 内存迁移及物理输入隔离。
- 修改输入消费方后运行相应 runtime、module-world、technical-slice、L1 与 debug tools smoke。
- GUIDE 资源或插件变化后运行 Godot 4.7.1 headless editor 和正式 headless boot；真实重绑定、热插拔、图标切换仍需人工键鼠 / 手柄验收。

## 13. 维护清单

修改下列任一内容时同步本文：公开 API / 信号、规范 action、binding id、context / 优先级、设备源选择、边沿锁存、binding schema / 原子保存、Settings v1 迁移、UI 桥、prompt 刷新或 Replay 输入接管。插件内部变化同时更新 [`guide.md`](guide.md) 与 [`../../client/addons/README.md`](../../client/addons/README.md)。
