# PlatformServices 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `PlatformServices` 的代码契约权威；改平台 provider、GodotSteam / Steamworks 接入边界、成就 / 富状态 / 联机 API 或测试义务时必须同步 GDD、ADR、`docs/在线服务规划.md`、AI 导航与测试策略。

## 职责

- 作为所有平台 SDK 能力的统一 autoload 门面，业务系统不得直接调用 Steamworks、Epic、主机平台或其他平台 SDK。
- 当前优先预留 Steam：成就、统计提交、富状态 / 状态显示、overlay、好友邀请、Lobby / 联机入口。
- 当前不接入真实 Steamworks SDK，不联网，不创建大厅，不解锁真实成就；所有平台能力默认使用 `none` 空后端安全退化。
- ADR #150 已锁定未来正式 Steam adapter 使用 GodotSteam，但当前不安装或启用插件，也不代表独立 Steamworks Lab 已迁入正式客户端。
- 为未来其他平台保留 provider / capability 抽象，避免业务层写 `if platform == steam` 的分支。
- 记录请求与 diagnostics，方便 smoke、调试 UI 和未来平台设置页检查。
- 与规划中的 `OnlineServices` 分工：本模块只负责平台 SDK；Talo 的跨平台身份、排行榜 / 统计、Live Config、事件上传和轻量社交不进入本模块。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 接 Steamworks SDK | 本文档“扩展点”与 `client/scripts/autoload/platform_services.gd` |
| 规划 GodotSteam + Talo 分层 | `docs/在线服务规划.md` 与 ADR #150 |
| 业务里解锁成就 | 公共 API `unlock_achievement()` |
| 设置 Steam 状态显示 | 公共 API `set_rich_presence()` |
| 加联机 / Lobby 首片 | 公共 API `create_lobby()` / `join_lobby()` / `leave_lobby()` |
| 查为什么平台能力不可用 | `diagnostics()` 与启动日志 `platform_provider` / `platform_available` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/platform_services.gd` | 平台服务 autoload 门面与空后端 |
| `client/project.godot` | 注册 `PlatformServices` autoload |
| `client/scripts/boot/formal_client_boot.gd` | 启动日志输出平台 provider / 可用状态 |
| `client/tools/l1_smoke.gd` | 验证 Steam 优先预留、空后端安全退化和请求记录 |

## 场景 / 节点结构

无独立 `.tscn`。`PlatformServices` 作为 autoload 挂在 `/root/PlatformServices`。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| autoload `_ready()` | 调用 `reload_backend()`，当前选择 `none` provider | `provider_changed` |
| 启动日志 | `FormalClientBoot` 输出 provider 和可用状态 | `active_provider()`、`is_available()` |
| 业务请求 | 成就、富状态、overlay、联机请求先进入门面 | `unlock_achievement()`、`set_rich_presence()`、`create_lobby()` |
| 空后端退化 | 当前记录 diagnostics / request log，返回 `false` | `diagnostics()`、`achievement_requests()`、`multiplayer_requests()` |
| 未来 Steam 接入 | adapter 改写 provider、capability 和实际 SDK 调用 | `supports()`、`capabilities()` |
| 未来 Talo 身份接线 | GodotSteam adapter 申请用途明确的 Steam Web API Ticket，交给 `OnlineServices`；本模块不调用 Talo | 未来票据 API，当前尚未实现 |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `reload_backend()` | 无 | `void` | 重新选择平台后端；当前固定为 `none`，Steam 只预留 |
| `preferred_provider()` | 无 | `String` | 当前返回 `steam` |
| `active_provider()` | 无 | `String` | 当前返回 `none`；未来 Steam adapter 可返回 `steam` |
| `is_available()` | 无 | `bool` | 当前为 `false` |
| `supports(capability)` | `String` | `bool` | 查询 capability 是否可用 |
| `capabilities()` | 无 | `Dictionary` | 返回 capability -> bool 拷贝 |
| `diagnostics()` | 无 | `Array[String]` | 返回平台选择和退化诊断 |
| `platform_user()` | 无 | `Dictionary` | 当前返回空用户；未来填 provider user id / display name |
| `rich_presence()` | 无 | `Dictionary` | 返回本地期望状态显示字段 |
| `achievement_requests()` | 无 | `Array[Dictionary]` | 返回已请求成就操作，供调试 / smoke 使用 |
| `multiplayer_requests()` | 无 | `Array[Dictionary]` | 返回已请求联机操作 |
| `overlay_requests()` | 无 | `Array[Dictionary]` | 返回已请求 overlay 操作 |
| `unlock_achievement(achievement_id)` | `String` | `bool` | 当前记录请求并返回 `false`；接 Steam 后才可返回 `true` |
| `store_stats()` | 无 | `bool` | 当前返回 `false`；接平台统计后提交平台 stats |
| `set_rich_presence(key, value)` | `String`, `String` | `bool` | 当前保存本地期望值并返回 `false` |
| `clear_rich_presence(key)` | `String` | `bool` | 清理本地期望值；真实平台清理留给 adapter |
| `clear_all_rich_presence()` | 无 | `bool` | 清理全部本地期望值 |
| `show_overlay(target)` | `String` | `bool` | 当前记录请求并返回 `false` |
| `create_lobby(max_members, metadata)` | `int`, `Dictionary` | `bool` | 当前记录请求并返回 `false`；不联网 |
| `join_lobby(lobby_id)` | `String` | `bool` | 当前记录请求并返回 `false` |
| `leave_lobby()` | 无 | `bool` | 当前记录请求并返回 `false` |
| `invite_friend(friend_id)` | `String` | `bool` | 当前记录请求并返回 `false` |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `provider_changed` | `provider: String`, `available: bool` | 后端重载后 |
| `achievement_requested` | `achievement_id: String`, `accepted: bool` | 请求解锁成就后 |
| `rich_presence_changed` | `key: String`, `value: String`, `accepted: bool` | 设置或清理状态显示后 |
| `overlay_requested` | `target: String`, `accepted: bool` | 请求打开平台 overlay 后 |
| `multiplayer_requested` | `request: Dictionary`, `accepted: bool` | 请求 Lobby / 联机操作后 |

## 数据与契约

- 当前不读取 `client/data/`，不新增生成契约。
- Provider 常量当前为 `none` 与 `steam`；Steam 是优先 provider，其他平台后续通过同一 provider / capability 模型加入。
- Capability 常量当前为：`achievements`、`stats`、`rich_presence`、`overlay`、`multiplayer`、`lobbies`、`user_identity`。
- 成就 id、统计 key、Lobby metadata schema 尚未落地；未来正式接 Steam 成就时，应新增数据 / 词表 / 校验，而不是在业务层散落裸字符串。

## 依赖

- 上游依赖：Godot autoload、`GameClock` tick（仅用于请求记录）。
- 下游调用方：未来成就系统、标题 / 暂停 UI、联机大厅、状态显示、发行平台集成。
- 未来相邻系统：规划中的 `OnlineServices` 只通过受控票据 / 平台身份结果与本模块协作，不持有 GodotSteam SDK 对象。
- 禁止依赖：业务系统不得直接调用 Steamworks SDK、GodotSteam 单例、第三方平台插件或平台原生 API。
- 禁止混层：`PlatformServices` 不承接 Talo 排行榜、Live Config、事件上传、Continuity 或通用玩家关系；这些能力必须经未来 `OnlineServices`。

## 扩展点

- 接 Steamworks 时，固定官方 GodotSteam 发布版本，并在 `PlatformServices` 内部或相邻 adapter 中唯一完成 SDK 初始化、callback、user identity、achievements、Steam-only stats、rich presence、overlay、Lobby / P2P / invite 转接；业务层和 Talo adapter 不得重复初始化或驱动 callback。
- Talo 需要 Steam 身份时，由 GodotSteam adapter 获取 Web API Ticket，再通过未来 `OnlineServices` 交给 Talo；Talo → Steamworks 同步的排行榜 / 统计不得同时由客户端直写。
- 接 Epic、GOG、主机平台等其他平台时，新增 provider adapter，但保持业务层 API 不变。
- 成就和统计正式化前，先建立数据源和校验，避免业务系统用临时字符串直接解锁。
- 联机正式化前，先补多人同步 / 服务器权威 / 断线恢复设计；`PlatformServices` 只负责平台大厅、邀请和身份，不承载游戏同步协议。
- 平台云存档若未来需要接入，应和 `SaveManager` 协作；不得让平台 SDK 绕过 `SaveManager` 直接写游戏进度。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 接 Steam 成就 | `platform_services.gd` + 成就数据 / 词表 | 本文档、GDD、测试策略 | `l1-smoke`、headless boot、平台手动 smoke |
| 接 Steam 富状态 | `platform_services.gd` | 本文档、GDD | `l1-smoke`、headless boot |
| 接 Steam Lobby | `platform_services.gd` + 联机设计 / runtime | 本文档、GDD、测试策略 | 平台手动 smoke + 断线 checklist |
| 给 Talo 提供 Steam 身份票据 | `platform_services.gd` + GodotSteam adapter + 未来 `OnlineServices` | 本文档、在线服务规划、ADR、测试策略 | 平台身份集成 smoke + 无 Steam / 票据失败退化 |
| 增加其他平台 provider | `platform_services.gd` 或 adapter | 本文档、ADR、AI 导航 | headless boot + provider-specific smoke |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动日志 `platform_provider=none` | 当前正常；Steamworks adapter 尚未接入 |
| `unlock_achievement()` 返回 false | `is_available()` 与 `supports(CAP_ACHIEVEMENTS)` |
| 状态显示没有同步到平台 | `supports(CAP_RICH_PRESENCE)`；当前只保存本地期望值 |
| Lobby 创建失败 | `supports(CAP_MULTIPLAYER)`；当前没有真实平台后端 |
| 业务代码想直接调 Steam API | 改为调用 `PlatformServices`，必要时扩展门面 API |

## 测试义务

- 改 `PlatformServices` 公共 API 或 provider 选择逻辑，必跑：
  - `py -3 tools/lint_gdscript_rules.py`
  - `py -3 tools/lint_semantic_rules.py`
  - `py -3 tools/godot_bridge.py --project client l1-smoke`
  - `py -3 tools/godot_bridge.py --project client headless-boot`
- 接真实 Steamworks SDK 时，除上述命令外必须补平台手动 smoke：Steam 客户端登录、overlay、成就测试 app id、富状态、Lobby 创建 / 加入 / 邀请、离线 / 断网退化。
- 与 Talo 接线时追加：Steam Web API Ticket 成功 / 失败 / 过期、Talo 不可达、账号切换、重复识别和退出清理；普通单机启动、本地存档与回放不得依赖该链路。
- 若平台 API 影响存档、回放或联机同步，按 `docs/测试策略.md` §7 追加对应 SaveManager / Replay / 联机测试。

## 迁移 / 兼容

当前只保留空后端接口，不改变存档、回放或数据 schema。ADR #150 只记录未来供应商路线，不新增 `OnlineServices` API。未来真实平台 / 在线服务接入不得改变既有单机流程：平台或 Talo 不可用时游戏仍应可启动、可游玩、可本地保存和播放本地回放。

## 相关文档

- `docs/游戏设计文档.md` §9.22 / §9.23
- `docs/在线服务规划.md`
- `docs/决策记录.md` ADR #84 / #150
- `docs/测试策略.md`
- `docs/AI导航.md`
