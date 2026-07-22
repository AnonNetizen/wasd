# Settings 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Settings` autoload 的代码契约权威；改设置 key、默认值、公共 API、持久化策略或测试义务时必须同步本文档。

## 职责

- `Settings` 负责维护正式客户端运行时设置的默认值、读取、修改和变更广播。
- 设置 key 必须来自 `docs/词表与契约.md`，并通过 `client/scripts/contracts/settings_keys.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- F7 首片已接入 `user://settings.cfg` 持久化、类型 / 范围校验、损坏配置回退和 `settings-smoke` 自动验证。
- F7 第二片已接入正式 `SettingsPanel`，标题菜单和暂停菜单都能打开同一设置面板；面板只通过 `Settings.set_value()` 写入，不直接维护偏好副本。ADR #148 后 `gameplay.screen_shake` 已接线并显示：`GameplayCameraController` 监听 `setting_changed`，关闭时立即停止当前 Phantom Camera noise、归零 Camera2D offset 并抑制后续玩家受伤震屏。其他未接线的 `video.*`、松开瞄准停火、瞄准模式和失焦暂停 key 暂时保留但不显示。F9 起默认 `gameplay.aim_mode` 为 `mouse`；当前运行时实际采用鼠标相对玩家 / 视口中心方向瞄准，方向键 / 手柄右摇杆 / D-pad 作为兜底输入。F7 运行时语言刷新已覆盖标题、暂停、设置、HUD、升级、结算和局外成长面板。F7 输入重绑定首片已接入键盘主绑定：`Settings` 保存 `input.*` key，并在加载 / 修改 / 重置时把键盘事件写入对应 `InputMap` action；运行时手柄轴 / 按钮事件仍保留在同一 action 上。F7 收尾 polish 已给设置面板补输入绑定反馈、共用键位提示和一键恢复输入默认。
- `Settings` 不负责玩家进度存档；局外成长与局内续局属于 `SaveManager`。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 增加设置项 | `docs/词表与契约.md` 设置 key 段落，再看本文档 API |
| 调整默认值 | `client/scripts/autoload/settings.gd` 的 `_default_values()` |
| 做设置菜单 | 本文档公共 API 与 `docs/代码/ui_manager.md` |
| 做持久化 / 回退 | 本文档持久化流程与 `client/tools/settings_smoke.gd` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/settings.gd` | `Settings` autoload 脚本 |
| `client/scenes/ui/settings_panel.tscn` | F7 设置面板场景 |
| `client/scripts/ui/settings_panel.gd` | 设置面板控件绑定、读取 / 写入和语言刷新 |
| `client/scripts/contracts/settings_keys.gd` | 自动生成的设置 key 常量 |
| `client/data/_contracts.json` | 自动生成的契约缓存 |
| `client/project.godot` | autoload 注册 |
| `client/tools/settings_smoke.gd` | F7 设置持久化 smoke |
| `tools/godot_bridge.py` | `settings-smoke` 命令入口 |
| `user://settings.cfg` | 玩家本机设置配置文件 |

## 场景 / 节点结构

`Settings` 是 autoload singleton。Godot 在启动时按 `client/project.godot` 的 `[autoload]` 顺序实例化。

F7 设置面板是独立 UI 场景：

```text
SettingsPanel (CanvasLayer)
└── Root
    └── Center
        └── Panel
            └── Layout
                ├── LocaleOption
                ├── MasterVolumeSlider / MusicVolumeSlider / SfxVolumeSlider
                ├── ScreenShakeCheck / RecordReplaysCheck
                ├── 隐藏占位：FullscreenCheck / VsyncCheck / FireOnReleaseCheck / AimModeOption / PauseOnFocusLossCheck
                ├── InputFeedbackLabel
                ├── InputBindingsGrid（移动 / 瞄准 / 主动道具 / 交互 / 详细数值面板 / 暂停 / 确认 / 返回）
                ├── ResetInputBindingsButton
                ├── AnalyticsCheck
                └── CloseButton
```

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `_ready()` 先写入默认值并应用输入绑定，再尝试加载 `user://settings.cfg`；无配置时保留默认值，损坏或不支持版本时回退默认、应用输入绑定并重写干净配置 | `reset_to_defaults(false)` / `load_from_disk()` / `InputMap` |
| 读取 | 调用方用已登记 key 读取当前值 | `get_value()` |
| 修改 | key 通过契约、类型和范围校验后写入、广播并保存到磁盘；`input.*` 变更会先替换对应 action 的键盘事件，`gameplay.screen_shake=false` 会让 camera controller 立即停止且清理震屏 | `set_value()` / `setting_changed` / `save_to_disk()` / `InputMap.action_add_event()` |
| 面板 | `SettingsPanel` 初始化时读取当前值；控件变化后调用 `Settings.set_value()`；语言切换后刷新面板已有 label / option / feedback 文案；输入绑定变更后显示保存或共用提示；离树时断开语言订阅 | `SettingsPanel.refresh()` / `Localization.locale_changed` |
| 重置 | 恢复全部默认值，或只恢复输入绑定默认值；调用方可选择是否立即持久化 | `reset_to_defaults(persist)` / `reset_input_bindings_to_defaults(persist)` |
| smoke | 备份现有 `settings.cfg`，验证缺文件默认值、有效设置 roundtrip、非法值拒绝、坏值 / 坏文件回退、设置面板控件、可见震屏开关写入、标题 / 暂停入口，以及核心 UI 既有实例语言刷新，然后恢复原文件 | `settings-smoke` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `get_value(key, fallback = null)` | 设置 key、兜底值 | 当前值或兜底值 | 未登记 key 会 `push_error` 并返回兜底值 |
| `set_value(key, value)` | 设置 key、新值 | `bool` | key 未登记或值不符合类型 / 范围返回 `false`；值未变化不广播；成功后自动保存 |
| `has_key(key)` | 设置 key | `bool` | 只表示是否登记在契约里 |
| `values()` | 无 | `Dictionary` | 返回深拷贝，调用方不得改内部状态 |
| `input_binding_options()` | 无 | `Array[String]` | 返回当前键盘主绑定允许选项，供设置面板显示和 smoke 断言；业务玩法仍只读 action |
| `reset_input_bindings_to_defaults(persist = true)` | 是否立即保存默认值 | `void` | 只重置 `input.*` 键盘主绑定；会广播发生变化的输入 key，并重新写入 InputMap |
| `reset_to_defaults(persist = false)` | 是否立即保存默认值 | `void` | 不广播逐项变化；设置菜单做“恢复默认”时如需落盘传 `true` |
| `load_from_disk()` | 无 | `bool` | `true` 表示干净加载或缺文件默认值；`false` 表示损坏 / 越界 / 不支持版本等已触发回退 |
| `save_to_disk()` | 无 | `bool` | 写入 `user://settings.cfg`，失败时 `push_error` 并返回 `false` |
| `settings_path()` | 无 | `String` | 返回当前配置路径，供 smoke / 诊断使用 |
| `last_load_recovered()` | 无 | `bool` | 最近一次 `load_from_disk()` 是否发生回退 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `setting_changed` | `key: String`, `value: Variant` | `set_value()` 成功写入新值后 |
| `settings_loaded` | `recovered: bool` | `load_from_disk()` 完成后；`true` 表示至少发生过损坏 / 越界 / 版本回退 |
| `settings_saved` | `path: String` | `save_to_disk()` 成功后 |

## 数据与契约

当前默认设置：

| key | 类型 / 范围 | 默认值 | 用途 |
|-----|-------------|--------|------|
| `general.locale` | string：`zh_CN` / `en` | `zh_CN` | 首选语言 |
| `video.fullscreen` | bool | `false` | 已登记，当前未接线生效；设置面板暂不显示 |
| `video.vsync` | bool | `true` | 已登记，当前未接线生效；设置面板暂不显示 |
| `audio.master` | float：0~1 | `1.0` | 主音量 |
| `audio.music` | float：0~1 | `0.8` | 音乐音量 |
| `audio.sfx` | float：0~1 | `0.9` | 音效音量 |
| `gameplay.fire_on_release` | bool | `false` | 旧自动开火兼容项，当前未接线生效；正式开火改走 `fire` action 按住触发，设置面板暂不显示 |
| `gameplay.aim_mode` | string：`mouse` / `4dir` / `auto` | `mouse` | 已登记；当前运行时默认鼠标瞄准，设置面板暂不显示，`4dir` / `auto` 仍为后续模式扩展预留 |
| `gameplay.screen_shake` | bool | `true` | 已登记，当前未接线生效；设置面板暂不显示 |
| `gameplay.pause_on_focus_loss` | bool | `true` | 已登记，当前未接线生效；设置面板暂不显示 |
| `gameplay.record_replays` | bool | `true` | 自动回放录制开关 |
| `input.move_up` / `input.move_down` / `input.move_left` / `input.move_right` | string：`Settings.input_binding_options()` 返回集合 | `W` / `S` / `A` / `D` | 移动 action 的键盘主绑定 |
| `input.aim_up` / `input.aim_down` / `input.aim_left` / `input.aim_right` | string：`Settings.input_binding_options()` 返回集合 | `Up` / `Down` / `Left` / `Right` | 兜底瞄准 action 的键盘主绑定；鼠标瞄准不通过这些键位表达连续方向 |
| `input.use_active_item` | string：`Settings.input_binding_options()` 返回集合 | `Space` | 主动道具 action 的键盘主绑定 |
| `input.interact` | string：`Settings.input_binding_options()` 返回集合 | `E` | 交互 action 的键盘主绑定；当前用于打开 F12 资源缓存 / Mod 缓存 |
| `input.show_stats_panel` | string：`Settings.input_binding_options()` 返回集合 | `Tab` | 详细数值面板 action 的键盘主绑定；按住显示、松开隐藏，不暂停 |
| `input.pause` | string：`Settings.input_binding_options()` 返回集合 | `Escape` | 暂停 action 的键盘主绑定 |
| `input.ui_confirm` | string：`Settings.input_binding_options()` 返回集合 | `Enter` | UI 确认 action 的键盘主绑定 |
| `input.ui_back` | string：`Settings.input_binding_options()` 返回集合 | `Escape` | UI 返回 action 的键盘主绑定 |
| `privacy.analytics_enabled` | bool | `true` | 数据收集开关 |

新增 key 必须先改 `docs/词表与契约.md`，再运行 `tools/sync_contracts.py` 生成常量和 `_contracts.json`。

配置文件结构：

```ini
[meta]
version=1

[settings]
general.locale="zh_CN"
audio.master=1.0
```

加载规则：
- 缺少 `user://settings.cfg`：不报错，使用默认值。
- 文件无法解析或版本高于当前 `CONFIG_VERSION`：整份配置回退默认值并重写干净文件。
- 单个 key 类型 / 范围非法：该 key 回退默认值，其余合法 key 保留，并重写干净文件。
- 未登记 key 不进入 `_values`，避免旧配置或人工编辑污染运行时状态。
- `input.*` 只替换对应 action 上已有的 `InputEventKey`；`InputEventJoypadButton` / `InputEventJoypadMotion` 由 gameplay runtime 兜底注册并保留，后续可扩展完整手柄重绑定。
- 输入绑定允许共用键位，例如 `pause` 与 `ui_back` 默认都为 `Escape`，因为二者由当前状态 / UI 栈上下文裁决。设置面板会提示“与某动作共用”，但不阻止保存。

## 依赖

- 上游依赖：`DataLoader` 提供契约校验；`SettingsKeys` 提供生成常量。
- 下游调用方：`Localization` 监听 `general.locale`，`AudioManager`、`Analytics`、`Replay` 与 `SettingsPanel` 会读取对应 key；`InputMap` 的键盘主绑定由 `Settings` 统一写入。
- 禁止依赖：业务代码不得绕过 `Settings` 自己维护同名偏好变量。

## 扩展点

- 增加设置项：先登记词表 key，再给 `DEFAULT_VALUES` 增加默认值，并同步设置菜单。
- 扩展持久化 schema：提升 `CONFIG_VERSION`，在 `load_from_disk()` 中补旧 key 兼容或迁移；仍不得混入 `SaveManager` 的 `meta` / `run` 存档。
- 扩展范围校验：在 `_setting_specs()` 维护类型 / 范围 / 枚举，调用点不重复散落校验。
- 接入设置面板：UI 只调用 `Settings.set_value()`；若值被拒绝，面板保留旧值。只有已有下游系统即时生效的设置才能显示给玩家；未接线设置 key 可保留在 `Settings` 中，但面板必须隐藏或禁用。输入绑定控件应显示保存 / 共用 / 恢复默认反馈。新增控件必须同步 `settings-smoke`。
- 扩展输入重绑定：先新增 / 登记 action 与 `input.*` key，再在 `Settings.INPUT_ACTION_BY_SETTING_KEY`、默认值、设置面板和 smoke 中同步；业务脚本仍不得读取物理键。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增设置 key | `docs/词表与契约.md`、`settings.gd` | 本文档、任务模板 | `tools/sync_contracts.py --check`、`tools/validate_data.py` |
| 改默认语言 | `settings.gd` | 本文档、`client/locale/README.md` | headless boot |
| 接入设置菜单 | `settings_panel.tscn`、`settings_panel.gd`、入口菜单脚本 | UI 模块文档 | `settings-smoke` + `runtime-smoke` |
| 改持久化 / 回退 | `settings.gd`、`settings_smoke.gd` | 本文档、FormalClientBoot 文档 | `settings-smoke` + headless boot |
| 改运行时语言刷新 | 目标 UI 脚本、`settings_smoke.gd` | 本文档、Localization / Gameplay Runtime 文档 | `settings-smoke` + `runtime-smoke` |
| 改输入绑定 | `docs/词表与契约.md`、`settings.gd`、`settings_panel.*`、必要的 runtime action 兜底 | 本文档、Gameplay Runtime 文档 | `settings-smoke` + `runtime-smoke` + `sync_contracts.py --check` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 设置 key 写入失败 | key 是否在 `docs/词表与契约.md` 和 `client/data/_contracts.json` 中 |
| 设置值被拒绝 | `_setting_specs()` 的类型、范围或枚举是否符合词表 §5 |
| 重启后设置丢失 | `Settings.set_value()` 是否返回 true；`user://settings.cfg` 是否可写；`settings-smoke` 是否通过 |
| 手动改坏配置后异常 | `load_from_disk()` 是否回退默认并重写干净文件 |
| 修改语言无效 | `Localization` 是否连接了 `Settings.setting_changed` |
| 重绑定后仍有默认键 | runtime 是否又添加了键盘默认事件；键盘主绑定应只由 `Settings` 替换，runtime 只补手柄轴 / 按钮 |
| 重绑定后手柄失效 | `Settings` 是否误删了非 `InputEventKey` 事件；`GameplayRunLoop._ensure_input_actions()` 是否仍注册手柄兜底 |
| 重绑定后提示 key 而不是译文 | `client/locale/strings.csv` 是否已重新导入为 `.translation` 资源；`settings-smoke` 是否通过反馈文案断言 |
| 恢复输入默认无效 | `reset_input_bindings_to_defaults(true)` 是否被调用；`SettingsPanel` 是否刷新控件选择和反馈文本 |
| 启动日志 settings 数量异常 | `DEFAULT_VALUES` 是否漏了契约 key |

## 测试义务

- 修改 `Settings` 必跑：`python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、`python tools/godot_bridge.py --project client settings-smoke`。
- 改设置 key、默认值、范围或持久化 schema 时，追加 `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/lint_project_rules.py`。
- 改 `SettingsPanel`、标题 / 暂停设置入口或本地化刷新时，追加 `python tools/godot_bridge.py --project client runtime-smoke`，确认标题和暂停叠层关闭后 UI 栈恢复。
- 后续引入 GUT 后，`Settings` 需要覆盖默认值、变更广播、未知 key 拒绝、持久化加载和越界拒绝。
- 输入重绑定变化需要执行 L5 设置 / 输入 checklist；当前自动 smoke 覆盖键盘主绑定写入、设置面板控件、共用键位提示和恢复输入默认，完整手柄重绑定仍属于后续切片。

## 迁移 / 兼容

`user://settings.cfg` 当前 `CONFIG_VERSION=1`。后续新增 / 重命名 key 时优先让缺失 key 使用默认值；删除 key 时忽略旧配置中的多余 key；只有配置语义改变时才提升版本并在 `load_from_disk()` 中写明迁移或回退策略。玩家进度迁移仍属于 `SaveManager`，不得放入 `Settings`。

## 相关文档

- `docs/游戏设计文档.md` §9.5
- `docs/词表与契约.md` 设置 key 段落
- `docs/测试策略.md`
- `docs/代码/localization.md`
