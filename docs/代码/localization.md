# Localization 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Localization` autoload 的代码契约权威；改语言列表、翻译入口、Settings 联动或测试义务时必须同步本文档。

## 职责

- `Localization` 负责维护当前语言、响应 `Settings.general.locale` 变化，并提供统一的 `tr_key()` 翻译入口和 `locale_changed` 刷新信号。
- 当前首批语言固定为 `zh_CN` 与 `en`，符合 ADR #64 和 `client/locale/README.md`。
- 玩家可见文本仍必须通过 Godot `tr("key")` 或本模块 `tr_key(key)` 获取；本文档不新增玩家文案。
- 当前 `strings.csv` 已导入为 Godot `.translation` 资源；F7 已让标题、暂停、设置、HUD、升级、结算和局外成长面板接入运行时刷新链路。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 增加 UI 文案 | `client/locale/README.md` 与 `client/locale/strings.csv` |
| 增加语言 | ADR / `client/locale/README.md`，再改本文档和代码 |
| 做语言设置菜单 | `docs/代码/settings.md` 与本文档 |
| 排查翻译缺失 | `strings.csv`、Godot 导入配置、`tr_key()` 调用点 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/localization.gd` | `Localization` autoload 脚本 |
| `client/locale/strings.csv` | 人工维护的双语文案源 |
| `client/locale/README.md` | 本地化配置手册 |
| `client/project.godot` | autoload 注册 |

## 场景 / 节点结构

`Localization` 是 autoload singleton，没有 `.tscn` 场景。它依赖 `Settings` 已经先于它注册。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | 连接 `Settings.setting_changed`，读取 `general.locale` 并调用 `set_locale()` | `_ready()` |
| 切换语言 | 校验语言是否在 `SUPPORTED_LOCALES` 后设置 Godot `TranslationServer` | `set_locale()` |
| 翻译文本 | 调用 `tr(key)`，缺失时回退为 key | `tr_key()` |
| 设置联动 | `Settings.general.locale` 变化时同步切换语言 | `_on_setting_changed()` |
| UI 刷新 | 常驻 UI 订阅 `locale_changed` 后用自身缓存状态刷新已有文本；离树时断开订阅 | `locale_changed` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `current_locale()` | 无 | `String` | 返回当前语言 |
| `supported_locales()` | 无 | `Array[String]` | 返回语言列表拷贝 |
| `set_locale(locale)` | 语言 id | `bool` | 不支持的语言 `push_error` 并返回 `false` |
| `tr_key(key)` | locale key | `String` | 缺失翻译时返回 key |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `locale_changed` | `locale: String` | 当前语言成功变化后 |

## 数据与契约

- 支持语言：`zh_CN`、`en`。
- 默认语言：`zh_CN`，来源于 `Settings` 默认值。
- 文案源：`client/locale/strings.csv`，当前表头为 `keys,zh_CN,en`。
- 新增玩家可见文本必须同时填 `zh_CN` 和 `en`，缺一列时由 AI 先补首版翻译，再交人审。

## 依赖

- 上游依赖：`Settings` 提供 `general.locale`；Godot `TranslationServer` 提供运行时语言状态。
- 下游调用方：标题菜单、暂停菜单、设置面板、Gameplay HUD、升级面板、失败结算面板、局外成长面板和后续数据展示读取翻译。
- 禁止依赖：业务代码不得硬编码玩家可见文本；不得把语言写成 key 后缀。

## 扩展点

- 增加语言：先形成 ADR 或明确决策，再扩展 `SUPPORTED_LOCALES`、`strings.csv` 表头、Godot 导入配置和设置菜单。
- 增加运行时刷新：UI 节点应监听 `locale_changed` 或 Godot 翻译通知刷新已有 label/button/option；如果订阅 `locale_changed`，必须在 `_exit_tree()` 断开，避免离树节点收到后续语言切换。
- 增加格式化：动态数值应保留 `{value}` / `{count}` 等命名占位符，不在代码中拼句子。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增文案 key | `client/locale/strings.csv` | `client/locale/README.md` | `tools/validate_data.py` |
| 新增语言 | `strings.csv`、`localization.gd`、Godot 导入配置 | ADR、词表、本文档 | 数据校验 + 手动切换 |
| 设置菜单语言切换 | UI 场景、`Settings.set_value()` | Settings / UI 文档 | `settings-smoke` + `runtime-smoke` |
| 翻译缺失兜底 | `tr_key()` | 本文档 | L1 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 切换语言报错 | 语言是否在 `SUPPORTED_LOCALES` |
| 翻译显示 key | `strings.csv` 是否有 key，Godot 是否导入翻译资源 |
| 设置语言后未切换 | `Settings.setting_changed` 是否发出 `general.locale` |
| 切换语言后旧 UI 仍显示旧文本 | 目标 UI 是否订阅 `Localization.locale_changed` 并在回调中重画已有状态；节点离树后是否断开 signal |

## 测试义务

- 修改本模块必跑 L0 和 L2 headless boot，确认 autoload 可启动。
- 修改运行时 UI 语言刷新时追加 `python tools/godot_bridge.py --project client settings-smoke` 与 `python tools/godot_bridge.py --project client runtime-smoke`；`settings-smoke` 当前覆盖 SettingsPanel、TitleMenu、PauseMenu、GameplayHud、LevelUpPanel、GameOverPanel 和 MetaProgressionPanel 的既有实例刷新。
- 后续引入 GUT 后，需要覆盖缺 key 行为、语言切换、`Settings` 联动和 UI 刷新。
- 手动回归仍建议切换 `zh_CN -> en` 检查核心 UI 文案即时刷新。

## 迁移 / 兼容

当前没有语言资源迁移。未来新增语言列时，应保证旧 key 不改名；若必须改名，需要同步所有代码 / 数据引用和词表契约。

## 相关文档

- `client/locale/README.md`
- `docs/游戏设计文档.md` §9.4
- `docs/词表与契约.md` locale key 段落
- `docs/代码/settings.md`
