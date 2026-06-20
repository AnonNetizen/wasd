# RNG 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `RNG` autoload 的代码契约权威；改随机子流、种子派生、公共 API 或确定性要求时必须同步本文档、`docs/词表与契约.md`、`docs/AI导航.md` 与测试说明。

## 职责

- 提供统一确定性随机入口，禁止业务代码直接调用全局随机函数。
- 按词表中的子流维护独立 `RandomNumberGenerator`。
- 支持一局主 seed 通过域隔离 SHA-256 mixer 派生各子流 seed；禁止依赖 Godot `hash()` 这类可能跨进程漂移的实现。
- 不负责决定何时开局或何时重置回放；F5 起提供 JSON 友好的 RNG 快照 / 恢复 API，具体何时保存由 `SaveManager` 的调用方决定。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 增加随机 API | `client/scripts/autoload/rng.gd` |
| 新增子流 | `docs/词表与契约.md` §11，再跑契约同步 |
| 调试确定性 | 本文档“测试义务”与 `docs/测试策略.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/rng.gd` | `RNG` autoload 实现 |
| `client/scripts/contracts/rng_streams.gd` | 生成常量，后续业务代码引用 |
| `client/data/_contracts.json` | 机器可读 RNG 子流白名单 |
| `client/tools/rng_audit.gd` | headless 跨子流相关性审计 |
| `tools/godot_bridge.py` | 暴露 `rng-audit` 验证命令 |

## 场景 / 节点结构

无场景节点。`RNG` 通过 `client/project.godot` 的 `[autoload]` 注册为全局单例。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| autoload `_ready()` | 创建并登记 6 个默认子流 | `spawn/drop/combat/ui_choice/world/meta` |
| 设置主 seed | 重新派生所有子流 seed | `set_run_seed()` |
| 业务取随机 | 通过具名子流调用 | `RNG.spawn.randi()`、`RNG.stream(id)` |
| 暂停续局 | 保存 / 恢复主 seed 与各子流内部 state | `snapshot()` / `restore_snapshot()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `set_run_seed(seed_value)` | `int` | `void` | 重置所有子流序列 |
| `run_seed()` | 无 | `int` | 返回当前主 seed |
| `snapshot()` | 无 | `Dictionary` | 返回主 seed 与各子流 seed/state；大整数以字符串保存，避免 JSON 精度破坏 |
| `restore_snapshot(snapshot_data)` | `Dictionary` | `void` | 先恢复主 seed，再恢复各子流 state；未知子流忽略 |
| `stream(stream_id)` | `String` | `RNG.Stream` | 未登记 id 报错并回退到 `spawn` |
| `Stream.randi()` | 无 | `int` | 只通过子流调用 |
| `Stream.randf()` | 无 | `float` | 只通过子流调用 |
| `Stream.randf_range(from, to)` | `float`, `float` | `float` | 只通过子流调用 |
| `Stream.pick(values)` | `Array` | `Variant` | 空数组返回 `null` |
| `Stream.weighted_pick(values, weights, luck_bias)` | `Array`, `Array`, `float` | `Variant` | 数组长度必须一致 |

## Signal / Event

无。

## 数据与契约

- 子流 id 权威来源是 `docs/词表与契约.md` §11。
- 当前子流：`spawn`、`drop`、`combat`、`ui_choice`、`world`、`meta`。
- 代码引用应走 `client/scripts/contracts/rng_streams.gd` 生成常量；本 autoload 的初始子流后续应与生成常量保持一致。
- 子流 seed 派生使用 `STREAM_SEED_DOMAIN + run_seed + stream_id` 组成文本，取 SHA-256 hex digest 后按 16 进制逐位折叠到固定模数 `2_147_483_647`；该规则是 F8 回放确定性与跨子流防相关性基线的一部分，改变时必须跑 `rng-audit`、重跑受影响 golden replay 并追加 ADR。

## 依赖

- 上游依赖：Godot `RandomNumberGenerator`。
- 下游调用方：刷怪、掉落、战斗、升级候选、地图 / 机关、局外成长等。
- 禁止依赖：不得读取 `Time` 或业务状态派生随机；不得把某个系统逻辑写进 RNG。

## 扩展点

- 新子流先登记词表并生成常量，再加入 `_streams`。
- 新加权策略应保持确定性，只使用当前子流的 generator。
- 保存 / 回放 RNG 状态时调用 `snapshot()` / `restore_snapshot()`；业务系统不得读取 `RandomNumberGenerator` 内部对象或自行存随机状态。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增子流 | `docs/词表与契约.md`、`rng.gd` | 本文档、AI导航 | `tools/sync_contracts.py --check`、headless boot |
| 调整权重抽取 | `rng.gd` | 本文档、测试策略（若义务变化） | 后续 GUT 单测 |
| 接入回放状态保存 | `rng.gd`、Replay / SaveManager | 对应模块文档 | 回放 / 存档 roundtrip |
| 改 RNG 快照格式 | `rng.gd`、存档调用方 | 本文档、SaveManager / 回放文档 | run 存档 roundtrip + F4 smoke |
| 改子流 seed 派生 | `rng.gd`、`rng_audit.gd` | 本文档、测试策略、ADR、AI记忆 | `python tools/godot_bridge.py --project client rng-audit` + 四条 checked-in replay runner |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 同 seed 不复现 | 是否直接用了全局随机或错误子流；是否改动过子流 seed 派生算法但未重录 golden replay |
| 不同子流结果可互相预测 | 是否改过 seed mixer、子流 id 或 Godot RNG 行为但未跑 `rng-audit`；不要假设“不同 seed”天然独立 |
| 子流 id 报错 | 是否未登记词表或未加入 `_streams` |
| 抽取总是首项 | 权重是否全为 0 或负数 |
| run 存档 hash mismatch | RNG seed/state 是否仍以 JSON number 写入；大整数必须以字符串存 |

## 测试义务

- 必跑正式项目 headless boot。
- 改子流 seed 派生、默认子流集合或 RNG 底层实现时，必跑 `python tools/godot_bridge.py --project client rng-audit`；当前审计采样 10,000 个 run seed、6 个子流、每流前 4 次 `randf()`，最大绝对 Pearson 相关阈值为 0.06。
- F2 后续补 GUT：同主 seed 各子流序列稳定、不同子流互不污染、`weighted_pick()` 边界。
- 改随机行为或子流 seed 派生若影响整局，必须评估并重录受影响黄金回放。

## 迁移 / 兼容

改变 seed 派生算法会影响回放确定性；正式进入回放阶段后必须通过 ADR 或明确版本迁移处理，并重录受影响 golden replay。

## 相关文档

- `docs/游戏设计文档.md` §9.18.1
- `docs/词表与契约.md` §11
- `docs/测试策略.md`
