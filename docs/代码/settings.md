# Settings 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Settings` autoload 的代码契约权威；改设置 key、默认值、公共 API、持久化策略或测试义务时必须同步本文档。

## 职责

- `Settings` 负责维护正式客户端运行时设置的默认值、读取、修改和变更广播。
- 设置 key 必须来自 `docs/词表与契约.md`，并通过 `client/scripts/contracts/settings_keys.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- 当前切片只提供内存态设置，不负责写入 `user://settings.cfg`；持久化、范围校验和输入重绑定会在后续设置系统切片补齐。
- `Settings` 不负责玩家进度存档；局外成长与局内续局属于 `SaveManager`。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 增加设置项 | `docs/词表与契约.md` 设置 key 段落，再看本文档 API |
| 调整默认值 | `client/scripts/autoload/settings.gd` 的 `_default_values()` |
| 做设置菜单 | 本文档公共 API 与 `docs/代码/ui_manager.md` |
| 做持久化 | 本文档迁移 / 兼容段落与后续 `SaveManager` 文档 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/settings.gd` | `Settings` autoload 脚本 |
| `client/scripts/contracts/settings_keys.gd` | 自动生成的设置 key 常量 |
| `client/data/_contracts.json` | 自动生成的契约缓存 |
| `client/project.godot` | autoload 注册 |

## 场景 / 节点结构

`Settings` 是 autoload singleton，没有 `.tscn` 场景。Godot 在启动时按 `client/project.godot` 的 `[autoload]` 顺序实例化。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `_ready()` 调用 `reset_to_defaults()` 写入内存默认值 | `reset_to_defaults()` |
| 读取 | 调用方用已登记 key 读取当前值 | `get_value()` |
| 修改 | key 通过契约校验后写入并广播 | `set_value()` / `setting_changed` |
| 重置 | 恢复 `DEFAULT_VALUES` 的深拷贝 | `reset_to_defaults()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `get_value(key, fallback = null)` | 设置 key、兜底值 | 当前值或兜底值 | 未登记 key 会 `push_error` 并返回兜底值 |
| `set_value(key, value)` | 设置 key、新值 | `bool` | key 未登记返回 `false`；值未变化不广播 |
| `has_key(key)` | 设置 key | `bool` | 只表示是否登记在契约里 |
| `values()` | 无 | `Dictionary` | 返回深拷贝，调用方不得改内部状态 |
| `reset_to_defaults()` | 无 | `void` | 当前切片不广播逐项变化 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `setting_changed` | `key: String`, `value: Variant` | `set_value()` 成功写入新值后 |

## 数据与契约

当前默认设置：

| key | 默认值 | 用途 |
|-----|--------|------|
| `general.locale` | `zh_CN` | 首选语言 |
| `video.fullscreen` | `false` | 全屏开关占位 |
| `video.vsync` | `true` | 垂直同步占位 |
| `audio.master` | `1.0` | 主音量 |
| `audio.music` | `0.8` | 音乐音量 |
| `audio.sfx` | `0.9` | 音效音量 |
| `gameplay.fire_on_release` | `false` | 松开瞄准是否停火的待决策入口 |
| `gameplay.aim_mode` | `4dir` | 默认瞄准模式 |
| `gameplay.screen_shake` | `true` | 屏幕震动开关 |
| `gameplay.pause_on_focus_loss` | `true` | 失焦暂停开关 |
| `gameplay.record_replays` | `true` | 自动回放录制开关 |
| `privacy.analytics_enabled` | `true` | 数据收集开关 |

新增 key 必须先改 `docs/词表与契约.md`，再运行 `tools/sync_contracts.py` 生成常量和 `_contracts.json`。

## 依赖

- 上游依赖：`DataLoader` 提供契约校验；`SettingsKeys` 提供生成常量。
- 下游调用方：`Localization` 监听 `general.locale`，后续 `AudioManager`、输入重绑定、设置菜单和 `Replay` 会读取对应 key。
- 禁止依赖：业务代码不得绕过 `Settings` 自己维护同名偏好变量。

## 扩展点

- 增加设置项：先登记词表 key，再给 `DEFAULT_VALUES` 增加默认值，并同步设置菜单。
- 增加持久化：后续统一写入 `user://settings.cfg`，但不能混入 `SaveManager` 的 `meta` / `run` 存档。
- 增加范围校验：可以为数值设置建立 schema，但不应在调用点重复散落校验。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增设置 key | `docs/词表与契约.md`、`settings.gd` | 本文档、任务模板 | `tools/sync_contracts.py --check`、`tools/validate_data.py` |
| 改默认语言 | `settings.gd` | 本文档、`client/locale/README.md` | headless boot |
| 接入设置菜单 | UI 场景与 `Settings.set_value()` | UI 模块文档 | L2 + 手动设置 checklist |
| 接入持久化 | 后续 `Settings` 持久化切片 | 本文档、测试策略 | L1 + L2 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 设置 key 写入失败 | key 是否在 `docs/词表与契约.md` 和 `client/data/_contracts.json` 中 |
| 修改语言无效 | `Localization` 是否连接了 `Settings.setting_changed` |
| 启动日志 settings 数量异常 | `DEFAULT_VALUES` 是否漏了契约 key |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查和 L2 headless boot。
- 后续引入 GUT 后，`Settings` 需要覆盖默认值、变更广播、未知 key 拒绝、持久化加载和越界拒绝。
- 接入设置菜单后需要执行 L5 设置 checklist。

## 迁移 / 兼容

当前没有用户配置文件迁移。未来加入 `user://settings.cfg` 后，必须记录配置版本、旧 key 迁移和损坏配置回退策略；不得把玩家存档迁移逻辑放入 `Settings`。

## 相关文档

- `docs/游戏设计文档.md` §9.5
- `docs/词表与契约.md` 设置 key 段落
- `docs/测试策略.md`
- `docs/代码/localization.md`
