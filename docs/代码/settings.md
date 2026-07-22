# Settings 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Settings` autoload 的代码契约权威；改设置 key、默认值、公共 API、持久化策略或测试义务时必须同步本文档。

## 职责

- `Settings` 负责维护正式客户端运行时设置的默认值、读取、修改和变更广播。
- 设置 key 必须来自 `docs/词表与契约.md`，并通过 `client/scripts/contracts/settings_keys.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- F7 首片已接入 `user://settings.cfg` 持久化、类型 / 范围校验、损坏配置回退和 `settings-smoke` 自动验证。
- F7 第二片已接入正式 `SettingsPanel`，标题菜单和暂停菜单都能打开同一设置面板；普通偏好只通过 `Settings.set_value()` 写入，不直接维护副本。ADR #148 后 `gameplay.screen_shake` 已接线并显示：`GameplayCameraController` 监听 `setting_changed`，关闭时立即停止当前 Phantom Camera noise、归零 Camera2D offset 并抑制后续玩家受伤震屏。其他未接线的 `video.*`、松开瞄准停火、瞄准模式和失焦暂停 key 暂时保留但不显示。F9 起默认 `gameplay.aim_mode` 为 `mouse`；ADR #151 后物理输入与重绑定改由 `InputService` / GUIDE 负责，Settings 只协调 `settings.cfg` v2 和旧 `input.*` v1 key 的一次迁移。当前绑定权威是 `user://input_bindings.tres`，不再写入 InputMap。F7 运行时语言刷新继续覆盖标题、暂停、设置、HUD、升级、结算和局外成长面板。
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
| `client/scripts/autoload/input_service.gd` | GUIDE 重绑定、配置持久化、冲突策略和输入提示；完整契约见 `docs/代码/input_service.md` |
| `client/resources/input/` | GUIDE action 与 gameplay / ui / debug context 默认资源 |
| `client/scripts/contracts/settings_keys.gd` | 自动生成的设置 key 常量 |
| `client/data/_contracts.json` | 自动生成的契约缓存 |
| `client/project.godot` | autoload 注册 |
| `client/tools/settings_smoke.gd` | F7 设置持久化 smoke |
| `tools/godot_bridge.py` | `settings-smoke` 命令入口 |
| `user://settings.cfg` | 玩家本机设置配置文件 |
| `user://input_bindings.tres` | GUIDE remapping config；当前输入绑定权威，不属于 SaveManager 存档 |

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
                ├── InputBindingsGrid（捕获式键鼠 / 手柄绑定；移动 / 瞄准显示方向键和摇杆组）
                ├── ResetInputBindingsButton
                ├── AnalyticsCheck
                └── CloseButton
```

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `_ready()` 先写入普通设置默认值，再加载 `user://settings.cfg`；v1 的旧 `input.*` 由 `InputService` 翻译成 GUIDE remapping config，v2 起不再把绑定写回 Settings | `reset_to_defaults(false)` / `load_from_disk()` / `InputService` |
| 读取 | 调用方用已登记 key 读取当前值 | `get_value()` |
| 修改 | 普通 key 通过契约、类型和范围校验后写入、广播并保存；绑定捕获、冲突替换和重置委托 `InputService`，不得伪装成普通 string setting | `set_value()` / `setting_changed` / `InputService` remap API |
| 面板 | 普通控件读写 Settings；输入行查询 `InputService` 的 slot / prompt 并启动 detector，冲突时只提供替换或取消；语言、设备或映射变化后刷新显示 | `SettingsPanel.refresh()` / `Localization.locale_changed` / InputService signals |
| 重置 | `Settings.reset_to_defaults()` 恢复普通偏好；输入绑定默认值由 `InputService` 独立恢复并保存 | `reset_to_defaults(persist)` / InputService reset API |
| smoke | 备份现有 `settings.cfg`，验证缺文件默认值、有效设置 roundtrip、非法值拒绝、坏值 / 坏文件回退、设置面板控件、可见震屏开关写入、标题 / 暂停入口，以及核心 UI 既有实例语言刷新，然后恢复原文件 | `settings-smoke` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `get_value(key, fallback = null)` | 设置 key、兜底值 | 当前值或兜底值 | 未登记 key 会 `push_error` 并返回兜底值 |
| `set_value(key, value)` | 设置 key、新值 | `bool` | key 未登记或值不符合类型 / 范围返回 `false`；值未变化不广播；成功后自动保存 |
| `has_key(key)` | 设置 key | `bool` | 只表示是否登记在契约里 |
| `values()` | 无 | `Dictionary` | 返回深拷贝，调用方不得改内部状态 |
| `take_legacy_input_bindings()` | 无 | `Dictionary` | 仅供 `InputService` 在启动时一次取走 v1 绑定迁移源；读取后清空，业务和设置 UI 不得调用 |
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
| `gameplay.screen_shake` | bool | `true` | 已接线且在设置面板显示；关闭会即时停止并抑制 Phantom Camera 受伤震屏 |
| `gameplay.pause_on_focus_loss` | bool | `true` | 已登记，当前未接线生效；设置面板暂不显示 |
| `gameplay.record_replays` | bool | `true` | 自动回放录制开关 |
| `input.*` 旧键位 key | string | F7 旧默认 | deprecated；只在读取 `settings.cfg` v1 时迁移为 GUIDE 配置，v2 不再写出或作为运行时权威 |
| `privacy.analytics_enabled` | bool | `true` | 数据收集开关 |

新增 key 必须先改 `docs/词表与契约.md`，再运行 `tools/sync_contracts.py` 生成常量和 `_contracts.json`。

配置文件结构：

```ini
[meta]
version=2

[settings]
general.locale="zh_CN"
audio.master=1.0
```

加载规则：
- 缺少 `user://settings.cfg`：不报错，使用默认值。
- 文件无法解析或版本高于当前 `CONFIG_VERSION`：整份配置回退默认值并重写干净文件。
- 单个 key 类型 / 范围非法：该 key 回退默认值，其余合法 key 保留，并重写干净文件。
- 未登记 key 不进入 `_values`，避免旧配置或人工编辑污染运行时状态。
- 读取 v1 时，合法旧 `input.*` string 由 `InputService` 映射到 GUIDE 的键鼠 slot；迁移只发生在内存 / 新绑定资源，不重写历史源文件。
- v2 不把绑定写入 `[settings]`；未知旧输入 key 只忽略，不进入 `_values`。
- GUIDE 配置的冲突、设备 slot、安全兜底、原子写入、备份和坏文件恢复归 `docs/代码/input_service.md`。

## 依赖

- 上游依赖：`DataLoader` 提供契约校验；`SettingsKeys` 提供生成常量。
- 下游调用方：`Localization` 监听 `general.locale`，`AudioManager`、`Analytics`、`Replay` 与 `SettingsPanel` 会读取对应 key；`InputService` 只向 Settings 请求 v1 迁移数据，不把 GUIDE 资源塞回 `_values`。
- 禁止依赖：业务代码不得绕过 `Settings` 自己维护同名偏好变量。

## 扩展点

- 增加设置项：先登记词表 key，再给 `DEFAULT_VALUES` 增加默认值，并同步设置菜单。
- 扩展持久化 schema：提升 `CONFIG_VERSION`，在 `load_from_disk()` 中补旧 key 兼容或迁移；仍不得混入 `SaveManager` 的 `meta` / `run` 存档。
- 扩展范围校验：在 `_setting_specs()` 维护类型 / 范围 / 枚举，调用点不重复散落校验。
- 接入设置面板：UI 只调用 `Settings.set_value()`；若值被拒绝，面板保留旧值。只有已有下游系统即时生效的设置才能显示给玩家；未接线设置 key 可保留在 `Settings` 中，但面板必须隐藏或禁用。输入绑定控件应显示保存 / 共用 / 恢复默认反馈。新增控件必须同步 `settings-smoke`。
- 扩展输入重绑定：先登记 action 并生成常量，再改 GUIDE action / context 资源、`InputService` slot 元数据、设置面板和 smoke。新增当前 binding 不再新增 `input.*` setting key；业务脚本仍不得读取物理键。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增设置 key | `docs/词表与契约.md`、`settings.gd` | 本文档、任务模板 | `tools/sync_contracts.py --check`、`tools/validate_data.py` |
| 改默认语言 | `settings.gd` | 本文档、`client/locale/README.md` | headless boot |
| 接入设置菜单 | `settings_panel.tscn`、`settings_panel.gd`、入口菜单脚本 | UI 模块文档 | `settings-smoke` + `runtime-smoke` |
| 改持久化 / 回退 | `settings.gd`、`settings_smoke.gd` | 本文档、FormalClientBoot 文档 | `settings-smoke` + headless boot |
| 改运行时语言刷新 | 目标 UI 脚本、`settings_smoke.gd` | 本文档、Localization / Gameplay Runtime 文档 | `settings-smoke` + `runtime-smoke` |
| 改输入绑定 | `docs/词表与契约.md`、GUIDE action/context 资源、`input_service.gd`、`settings_panel.*` | 本文档、InputService / GUIDE / Gameplay Runtime 文档 | `input-smoke` + `settings-smoke` + `runtime-smoke` + `sync_contracts.py --check` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 设置 key 写入失败 | key 是否在 `docs/词表与契约.md` 和 `client/data/_contracts.json` 中 |
| 设置值被拒绝 | `_setting_specs()` 的类型、范围或枚举是否符合词表 §5 |
| 重启后设置丢失 | `Settings.set_value()` 是否返回 true；`user://settings.cfg` 是否可写；`settings-smoke` 是否通过 |
| 手动改坏配置后异常 | `load_from_disk()` 是否回退默认并重写干净文件 |
| 修改语言无效 | `Localization` 是否连接了 `Settings.setting_changed` |
| 重绑定后仍有默认键 | `GUIDERemappingConfig` 是否应用、slot index 是否匹配默认 context；runtime 不应再动态创建 InputMap action |
| 重绑定后手柄失效 | 捕获设备类型 / joy index、context 是否恢复、手柄 slot 是否被错误替换 |
| 重绑定后提示 key 而不是译文 | `client/locale/strings.csv` 是否已重新导入为 `.translation` 资源；`settings-smoke` 是否通过反馈文案断言 |
| 恢复输入默认无效 | `InputService.reset_bindings_to_defaults()` 是否成功；`SettingsPanel` 是否在 `bindings_changed` 后刷新绑定文字和反馈文本 |
| 启动日志 settings 数量异常 | `DEFAULT_VALUES` 是否漏了契约 key |

## 测试义务

- 修改 `Settings` 必跑：`python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、`python tools/godot_bridge.py --project client settings-smoke`。
- 改设置 key、默认值、范围或持久化 schema 时，追加 `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/lint_project_rules.py`。
- 改 `SettingsPanel`、标题 / 暂停设置入口或本地化刷新时，追加 `python tools/godot_bridge.py --project client runtime-smoke`，确认标题和暂停叠层关闭后 UI 栈恢复。
- 后续引入 GUT 后，`Settings` 需要覆盖默认值、变更广播、未知 key 拒绝、持久化加载和越界拒绝。
- 输入重绑定变化需要执行 L5 设置 / 输入 checklist；自动 smoke 覆盖键鼠 / 手柄捕获、冲突替换 / 取消、恢复默认、重启 roundtrip、v1 迁移和坏配置回退。

## 迁移 / 兼容

`user://settings.cfg` 当前 `CONFIG_VERSION=2`。v1 仅为旧 `input.*` 提供一次迁移；v2 不再保存输入绑定。后续新增 / 重命名普通 key 时优先让缺失 key 使用默认值；删除 key 时忽略旧配置中的多余 key。`user://input_bindings.tres` 的 schema 和恢复归 `InputService`，玩家进度迁移仍属于 `SaveManager`，两者都不得混入 `Settings`。

## 相关文档

- `docs/游戏设计文档.md` §9.5
- `docs/词表与契约.md` 设置 key 段落
- `docs/测试策略.md`
- `docs/代码/localization.md`
- `docs/代码/input_service.md`
- `docs/代码/guide.md`
