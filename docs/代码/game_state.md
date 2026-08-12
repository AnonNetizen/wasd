# GameState 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `GameState` autoload 的代码契约权威；改状态枚举、切换 API、暂停联动或 signal 顺序时必须同步本文档、`docs/AI导航.md`、GDD 与测试说明。

## 职责

- 维护正式项目全局流程状态。
- 提供唯一状态切换入口 `change_state()`。
- 广播状态退出、切换、进入信号。
- `TELEPORT_CHOICE` 表示传送目的地选择态：SceneTree 与底层 `GameClock` 继续推进，统一 gameplay simulation 保持活动，但玩家 gameplay intent 被锁定；只有叠加 `PAUSED` 才真正冻结。
- 集中管理 `get_tree().paused` 联动，业务系统不得直接读写。
- 不负责 UI 栈、存档、回放落盘或埋点具体实现；这些系统后续订阅状态信号。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 新增流程状态 | `client/scripts/autoload/game_state.gd` 与 GDD §9.12 |
| 接 UI 暂停 | 后续 `UIManager` 模块文档 |
| 接回放 / 埋点 | 后续 `Replay` / `Analytics` 模块文档 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/game_state.gd` | `GameState` autoload 实现 |
| `client/project.godot` | autoload 注册 |

## 场景 / 节点结构

无场景节点。`GameState` 通过 `client/project.godot` 的 `[autoload]` 注册为全局单例。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| autoload `_ready()` | 进入默认 `MAIN_MENU` 并同步暂停状态 | `state_entered` |
| 玩家加载 | 开始 / 继续 / 重开准备期间进入 `LOADING`；SceneTree 不暂停，但 gameplay 不接受输入、不推进 `GameClock`，加载完成并移除遮罩后才进入 `PLAYING` | `FormalClientBoot`、`GameplayRunLoop.run_prepared` |
| 传送选择 | 当前站已发现、来源安全且至少存在一个同网络已发现目标时进入非暂停 `TELEPORT_CHOICE`；世界模拟继续、玩家 gameplay intent 锁定，`UI_BACK` 取消回 `PLAYING`，暂停键可在其上叠加真正冻结的 `PAUSED`，关闭暂停菜单后恢复原选择态 | `GameplayRunLoop`、`TeleportChoicePanel`、`UIManager` |
| 请求切换 | 校验目标状态是否已登记 | `can_change_to()` |
| 切换成功 | 依次发退出、同步暂停、切换、进入 | `state_exited`、`state_changed`、`state_entered` |
| 切换失败 | 输出错误并保持原状态 | `push_error` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `current()` | 无 | `StringName` | 返回当前状态 |
| `context()` | 无 | `Dictionary` | 返回上下文深拷贝 |
| `is_state(state)` | `StringName` | `bool` | 当前状态判断 |
| `is_gameplay_simulation_active()` | 无 | `bool` | `PLAYING` 或非暂停 `TELEPORT_CHOICE` 时返回 true，供世界实体、计时与 RunLoop 统一判断是否推进 |
| `can_change_to(new_state)` | `StringName` | `bool` | 是否是登记状态 |
| `change_state(new_state, context_data)` | `StringName`, `Dictionary` | `bool` | 唯一状态切换入口 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `state_exited` | `state`, `context` | 离开旧状态前 |
| `state_changed` | `old_state`, `new_state`, `context` | 状态字段更新且暂停同步后 |
| `state_entered` | `state`, `context` | 进入新状态后 |

## 数据与契约

- 当前状态常量来自 GDD §9.12。
- `LOADING` 是正式玩家加载请求的准备态，不是 `PLAYING` 的别名；它覆盖开始、继续和重开，但不覆盖当前应用冷启动。
- 当前登记状态为 `MAIN_MENU`、`LOADING`、`PLAYING`、`PAUSED`、`REWARD_CHOICE`、`TELEPORT_CHOICE`、`GAME_OVER`。`REWARD_CHOICE` 只由通过原子校验的通用奖励请求进入并冻结 SceneTree；`TELEPORT_CHOICE` 只由已发现传送台的安全来源进入，不冻结 SceneTree 或 `GameClock`。等级提升本身不切换状态。
- `PAUSED` 可以覆盖 `REWARD_CHOICE` 或 `TELEPORT_CHOICE`；暂停上下文必须保存 underlying state，关闭菜单后恢复原态。Run v20 保存传送选择来源站；续局只有在来源仍存在、属于当前模块且已发现时才重建面板，失败不得擅自移动玩家。
- 暂无外部数据文件。
- 后续若状态 id 进入词表，需要同步 `docs/词表与契约.md` 与生成常量。

## 依赖

- 上游依赖：Godot SceneTree 暂停机制。
- 下游调用方：`GameClock`、`UIManager`、`Replay`、`Analytics`、`SaveManager`、奖励选择 / 结算系统。
- 禁止依赖：不得直接引用具体 UI 场景或玩法节点。

## 扩展点

- 新流程状态必须加入 `STATES`，并同步 GDD / AI 导航。
- UI、回放、埋点等通过 signal 订阅，不在 GameState 内写具体业务。
- 暂停策略变化集中改 `_apply_tree_pause_for_state()`。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增状态 | `game_state.gd` | GDD §9.12、本文档、AI导航 | headless boot，后续 GUT |
| 改暂停联动 | `game_state.gd` | 本文档、测试策略 | headless boot、runtime / teleporter smoke，L5 暂停 checklist |
| 接入 UI 栈 | `UIManager` + 订阅 `GameState` | UIManager 文档 | UI 集成测 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 业务暂停不一致 | 是否绕过 `GameState.change_state()` 直接改 `get_tree().paused` |
| 状态切换无效 | 目标状态是否在 `STATES` 中 |
| 订阅方顺序异常 | 是否依赖了未声明的 signal 顺序 |
| 加载期间 gameplay 已运行 | `FormalClientBoot` 是否先进入 `LOADING`；RunLoop 是否只在 `activate_prepared_run()` 中切到 `PLAYING` |
| 传送面板打开后世界意外停止 | 当前是否为 `TELEPORT_CHOICE`；是否误把该状态加入 SceneTree paused / `GameClock` 冻结集合；世界实体是否统一使用 `is_gameplay_simulation_active()` |
| 传送选择期间玩家仍可移动或开火 | Player / Weapon / Skill / RunLoop 的 gameplay intent 是否继续严格要求 `PLAYING`；不要把输入门禁改成 simulation-active 判断 |
| 关闭暂停菜单后传送选择丢失 | `PAUSED` context 的 underlying state 是否为 `TELEPORT_CHOICE`；RunLoop 是否仍保存原来源站并恢复同一面板 |

## 测试义务

- 必跑正式项目 headless boot。
- F2 后续补 GUT：非法状态拒绝、signal 顺序、`PAUSED` / `REWARD_CHOICE` 的 SceneTree paused 联动，以及 `TELEPORT_CHOICE` 的非暂停 simulation-active 语义。
- 传送状态接入必须覆盖：只发现当前站时不进入选择态、选择与淡出入期间 `GameClock` / 世界推进但玩家 gameplay intent 锁定、`UI_BACK` 取消恢复 `PLAYING`、暂停菜单覆盖后冻结并在关闭时恢复、Run v20 直接选择态及 underlying pause 续局恢复。
- 玩家加载状态变化必须跑 `python tools/godot_bridge.py --project client loading-smoke`。

## 迁移 / 兼容

状态 id 会进入 `run` 存档和回放关键帧；正式存档 / 回放落地后，改名必须走迁移。

## 相关文档

- `docs/游戏设计文档.md` §9.12
- `docs/测试策略.md`
- `docs/AI导航.md`
- `docs/代码/gameplay_loading.md`
