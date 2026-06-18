# GameClock 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `GameClock` autoload 的代码契约权威；改时间 API、暂停冻结、tick 规则或 time scale 行为时必须同步本文档、GDD、AI导航与测试说明。

## 职责

- 提供玩法时间 `now()`、物理 tick `tick()` 和缩放 delta `delta_scaled()`。
- 订阅 `GameState`，在暂停、升级选择和游戏结束等冻结状态返回 0 delta。
- 提供 `wall_now()` 给非玩法诊断 / UI / Analytics 使用。
- F5 起提供 `snapshot()` / `restore_snapshot()`，供局内暂停保存退出后恢复玩法时间、物理 tick 与 time scale。
- 不负责修改 `Engine.time_scale`，也不负责驱动具体业务系统。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改时间缩放 | `client/scripts/autoload/game_clock.gd` |
| 改暂停冻结状态 | `GameState` 与本文档 |
| 调试回放确定性 | GDD §9.18.2 与测试策略 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/game_clock.gd` | `GameClock` autoload 实现 |
| `client/scripts/autoload/game_state.gd` | 冻结状态来源 |
| `client/project.godot` | autoload 注册 |

## 场景 / 节点结构

无场景节点。`GameClock` 通过 `client/project.godot` 的 `[autoload]` 注册为全局单例。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| autoload `_ready()` | 订阅 `GameState.state_changed` | `_on_game_state_changed()` |
| `_process(delta)` | 非冻结时累计玩法时间 | `delta_scaled()` |
| `_physics_process(delta)` | 非冻结时推进 tick | `tick()` |
| 时间缩放改变 | 更新内部倍率并广播 | `time_scale_changed` |
| 续局恢复 | 从 run 快照恢复 elapsed / tick / time_scale，并按当前 `GameState` 重算冻结状态 | `restore_snapshot()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `now()` | 无 | `float` | 受暂停 / time scale 影响 |
| `tick()` | 无 | `int` | 仅非冻结物理帧递增 |
| `delta_scaled(delta)` | `float` | `float` | 冻结时返回 0 |
| `wall_now()` | 无 | `float` | 真实系统时间，不参与玩法判定 |
| `time_scale()` | 无 | `float` | 当前倍率 |
| `set_time_scale(value)` | `float` | `void` | 小于 0 时钳为 0 |
| `reset()` | 无 | `void` | 测试 / 新局重置 |
| `snapshot()` | 无 | `Dictionary` | 返回 `elapsed`、`tick`、`time_scale` |
| `restore_snapshot(snapshot_data)` | `Dictionary` | `void` | 恢复时间字段并重新广播 `time_scale_changed` |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `time_scale_changed` | `time_scale` | `set_time_scale()` 或 `reset()` 后 |

## 数据与契约

无外部数据文件。冻结状态来自 `GameState.PAUSED`、`GameState.LEVEL_UP` 与 `GameState.GAME_OVER`。

## 依赖

- 上游依赖：`GameState`。
- 下游调用方：武器、刷怪、状态效果、机关、回放、存档。
- 禁止依赖：不得读取或修改具体玩法节点；不得使用 `Engine.time_scale` 作为项目时间缩放。

## 扩展点

- 假时钟注入可在后续 GUT / headless sim 中扩展。
- 需要保存续局时由玩法快照生产者调用 `snapshot()`，加载时调用 `restore_snapshot()`，不直接访问内部字段。
- 慢动作效果只应通过 `set_time_scale()`。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 改冻结状态 | `game_clock.gd`、`game_state.gd` | 本文档、GameState 文档 | headless boot，后续 GUT |
| 改 tick 规则 | `game_clock.gd` | 本文档、测试策略 | 回放 / GUT |
| 接入假时钟 | `game_clock.gd` | 本文档 | GUT |
| 改 run 时间快照 | `game_clock.gd`、玩法快照生产者 | 本文档、SaveManager 文档 | run 存档 roundtrip + F4 smoke |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 暂停时仍推进玩法时间 | `GameState` 是否切到冻结状态 |
| tick 不增长 | 当前是否处于 `PAUSED` / `LEVEL_UP` / `GAME_OVER` |
| 回放时间不稳定 | 业务是否绕过 `GameClock` 读取 `Time` |

## 测试义务

- 必跑正式项目 headless boot。
- F2 后续补 GUT：暂停冻结、time scale、`reset()`、tick 推进。
- 回放落地后纳入黄金回放确定性检查。

## 迁移 / 兼容

`tick` / `now` 将进入 run 存档和回放；正式存档 / 回放落地后改变规则必须配迁移或版本处理。

## 相关文档

- `docs/游戏设计文档.md` §9.18.2
- `docs/测试策略.md`
- `docs/AI导航.md`
