# EnemySpawnService 模块文档

> 权威范围：本页只记录该模块的公共契约、可观察行为、schema、所有权与依赖边界；私有实现和逐测试记录不进入本文档。

## 职责

- `EnemySpawnService` 负责敌人从对象池成功获取后的统一材化：位置与父节点、`wave_key` / `module_slot` metadata、`Enemy.configure()`、运行时序列号、移动边界、生命周期接线，以及 Run v19 entity snapshot 恢复。
- 服务维护 `next_enemy_spawn_serial` 的运行时事实，并向 `GameplayRunLoop` 提供 getter / reset；对外 Run v19 字段名和数值语义不变。
- 服务不负责敌人池注册、生成 wave 规划、内容可用性、模块 walkability、奖励结算、Run v19 外层编排或 staged batch。上述策略继续由 `GameplayRunLoop` 持有。
- 服务不选择敌人、不读取数据文件、不直接消费 RNG / GameClock。随机位置与奖励解析由 RunLoop 以 `Callable` 注入，并由服务控制调用时序。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改普通 / 定点 / 测试岛敌人材化 | `spawn_fresh()` 与 `GameplayRunLoop._spawn_enemy*()` wrapper |
| 改敌人续局恢复顺序 | `restore_enemy()` 与 `GameplayRunLoop._restore_enemy_snapshots()` |
| 改金币奖励或生成位置策略 | `GameplayRunLoop._resolve_enemy_reward_snapshot()` / `_spawn_position()`；不要把策略搬进服务 |
| 改击杀、攻击 / 状态反馈或 VFX | `GameplayRunLoop._connect_enemy_defeated()` 及其 lifecycle handler |
| 调查对象池复用串状态 | `_apply_spawn_metadata()`、Enemy `_pool_reset()` / `_pool_release()` 与专项 GUT |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/enemy_spawn_service.gd` | 材化顺序、序列号、metadata、恢复与依赖注入 |
| `client/scenes/gameplay/gameplay_run_loop.tscn` | 以 `GameplayRunLoop/EnemySpawnService` 直属 Node 声明服务 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 保留策略验证、奖励 / 位置 provider、生命周期接线和原 wrapper 签名 |
| `client/scripts/gameplay/enemy.gd` | `configure()`、`set_runtime_spawn_serial()`、`restore_snapshot()` 的实体实现 |
| `client/tests/integration/test_enemy_spawn_service.gd` | 失败不消费、池复用 metadata、世界事件上下文与 armed restore 顺序 |

## 场景 / 节点结构

```text
GameplayRunLoop (Node2D)
├── EnemySpawnService (Node)
├── ActiveWorld (Node2D)
│   └── <acquired Enemy nodes are reparented here>
└── GameplayFeedbackController / HUD / other controllers
```

服务必须是 RunLoop 直属节点。`ActiveWorld` 是池化敌人的活动父节点；`PoolManager` 仍是获取和释放的唯一入口。

## 运行流程

| 阶段 | 发生什么 | 关键 API |
|------|----------|----------|
| Run 准备 | RunLoop 取得 scene-authored service，重置 serial；玩家、地图与难度就绪后注入 providers / handlers | `configure()`、`reset_spawn_serial()` |
| 普通随机生成 | 先 acquire；成功后解析奖励；奖励成功后才调用随机位置 provider；随后按 fresh 顺序材化 | `spawn_fresh()` |
| 定点 / 世界事件生成 | RunLoop 先做内容可用性和 walkability 检查，再把预定位置、冻结战斗难度与事件 context 交给服务 | `spawn_fresh()` |
| 测试岛生成 | 禁用正式奖励与默认导航，使用单位难度；pre-lifecycle hook 配置 stationary / AI 目标 | `spawn_fresh()` |
| 续局恢复 | RunLoop 校验 snapshot、构造已保存的事件 / 奖励 context；服务不重抽奖励，按恢复顺序接线后调用实体 restore | `restore_enemy()` |
| 保存 | RunLoop 从服务读取下一个 serial，继续写入原 `next_enemy_spawn_serial` | `next_spawn_serial()` |

## 顺序不变量

- Fresh：`acquire → reward（如启用）→ position provider（如有）→ world_position → reparent → metadata → configure → serial → pre-lifecycle hook → bounds → lifecycle/VFX`。
- Restore：`acquire → reparent → saved world_position → metadata → configure(saved difficulty/context) → saved serial/max bump → pre-lifecycle hook → bounds → lifecycle/VFX → Enemy.restore_snapshot()`。
- armed 敌人会在 `Enemy.restore_snapshot()` 内发出 windup；因此 lifecycle / feedback 必须在 restore 前接好，且只收到一次恢复反馈。
- pool acquire 失败不得调用奖励 resolver、随机位置 provider或推进 serial；奖励解析失败会释放已获取实体，且同样不得调用随机位置 provider 或推进 serial。
- `Enemy._pool_reset()` 不保证清理 `wave_key` / `module_slot`，所以每次材化必须覆盖 `wave_key`，并在空模块槽时显式移除旧 `module_slot`。

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(active_world, player, navigation_provider, difficulty_provider, reward_resolver, bounds_handler, lifecycle_handler, acquire_handler?, release_handler?)` | scene 依赖与 callables | `bool` | 必需依赖无效时返回 `false`；生产默认 acquire / release 仍走 `PoolManager`，可选 handler 只用于隔离测试 |
| `reset_spawn_serial(next_serial=1)` | 下一个 serial | `void` | 最小为 1；新局设 1，续局使用 Run v19 保存值 |
| `next_spawn_serial()` | 无 | `int` | 返回下一个可分配 serial，不是最近已分配值 |
| `spawn_fresh(spec)` | `enemy_data`、wave / module、位置或 provider、context、难度及开关 | `{ok, reason, enemy}` | 调用方必须先完成内容与 walkability 验证；不改变 RunLoop 原 wrapper 返回值 |
| `restore_enemy(spec)` | 已校验 snapshot、enemy data、保存位置 / serial / context / 难度 | `{ok, reason, enemy}` | 绝不调用奖励 resolver；若实体支持 `restore_snapshot()`，在 bounds 和 lifecycle 之后调用 |

`spec` 是内部传输字典，不进入存档、数据 schema 或外部 Mod 契约。首片保持 RunLoop 的 `_spawn_enemy()`、`_spawn_enemy_at()`、`debug_test_arena_spawn_at()` 与 `_restore_enemy_snapshots()` 签名不变。

## Signal / Event

本服务不声明 signal。敌人的 `defeated`、attack、status 与表现反馈仍由 RunLoop 注入的 lifecycle handler 接线；服务只保证接线相对 configure / restore 的顺序。

## 数据与契约

- `enemy_data.pool_id` 必须来自已加载且已验证的 `enemies.csv` 行；池注册仍由 RunLoop 完成。
- `wave_key`、`module_slot`、`runtime_spawn_serial`、`reward_snapshot`、`event_instance_id` 与 spawn difficulty 继续使用 Run v19 既有字典形状。
- 服务不新增约定字符串、数据字段、locale 或生成常量；Meta v4、Run v19、Replay v9、游戏 v1.18 均不变。

## 依赖

- 上游：`GameplayRunLoop`、scene-authored `ActiveWorld` / Player、`PoolManager`。
- 下游实体：实现 `configure()` 的池化 `Node2D`；serial、bounds、restore 接口按能力检测。
- 注入策略：navigation、当前难度、奖励解析、边界应用和生命周期接线均由 RunLoop 提供。
- 禁止依赖：DataLoader、RNG、GameClock、HUD、ModuleWorld 的布局 / 规划内部状态，以及具体 Enemy 场景拓扑。

## 扩展点

- 新增敌人类型继续通过数据、actor scene 与 pool 注册进入；不要在服务按 enemy id 增加分支。
- 新生成入口先在 RunLoop 完成资格 / 空间策略，再复用 `spawn_fresh()`；需要实体专属的材化后设置时使用受控 `pre_lifecycle_hook`。
- 新恢复字段先保持 Run v19 外层兼容；只有实体恢复前必须提供的 context 才放入 restore spec。
- 后续若引入类型化 spec，应保持本页顺序与 RunLoop wrapper / wire 兼容，逐入口迁移，不同时改玩法策略。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调整材化 / restore 顺序 | `enemy_spawn_service.gd` | 本文档、`gameplay_runtime.md` | 专项 GUT + runtime / actor / module-world / save / replay regression |
| 调整奖励或随机位置算法 | `gameplay_run_loop.gd`、对应 resolver | 对应奖励 / runtime 文档 | pool 失败不消费断言 + golden replay |
| 调整池复用 metadata | service、`enemy.gd` | 本文档、Enemy AI 文档 | 专项 GUT + runtime smoke |
| 调整世界事件敌人上下文 | RunLoop world-event wrapper、service | world event 文档 | world-event / module-world / save smoke |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 有容量却不生成 | pool 是否注册、acquire 是否返回带 `configure()` 的 `Node2D`、reward resolver 是否返回非空 |
| pool 满后 RNG /奖励序列漂移 | acquire 失败后是否仍调用 reward / position provider，serial 是否被推进 |
| 返回模块后的敌人记在旧槽 | 空 `module_slot` 材化是否显式 `remove_meta()` |
| 续局 armed 预警丢失 / 重复 | restore 是否严格为 `bounds → lifecycle → Enemy.restore_snapshot()`，lifecycle handler 是否防重复连接 |
| 续局后 deterministic serial 冲突 | 保存的 next serial 是否先 reset，逐实体 restored serial 是否执行 max bump |
| 世界事件敌人金币或目标变化 | restore 是否错误重调 reward resolver；fresh 是否收到冻结 combat difficulty 和事件 context |

## 测试义务

- 文件级：`python tools/lint_gdscript_rules.py <touched .gd>` 与 `python tools/lint_semantic_rules.py <touched .gd>`。
- GUT：运行 unit + integration suite，专项覆盖 acquire / reward 失败不消费、跨模块池复用 metadata、世界事件冻结 context / difficulty、armed restore 反馈与 serial max bump。
- Gameplay：`headless-boot`、`runtime-smoke`、`actor-scene-smoke`、完整 / technical `module-world-smoke`、`world-event-smoke` 与 `save-smoke`。
- 确定性：执行四条 checked-in Replay v9 黄金回放对照；不重录 golden，data hash 与摘要必须不变。
- 性能 probe 不属于本模块自动门禁；只有用户另行明确授权时执行。
- 视觉、听觉与手感验收保留为“待人工验收”，AI 不执行或代判。

## 迁移 / 兼容

这是内部职责提取，不改变玩法结果、平衡、公开 signal、RunLoop wrapper、数据 hash 或存档 / 回放 wire。Meta v4、Run v19、Replay v9 与游戏 v1.18 保持不变；无需迁移或 golden 重录。

## 相关文档

- `docs/代码/gameplay_runtime.md`
- `docs/代码/enemy_ai.md`
- `docs/代码/pool_manager.md`
- `docs/代码/module_world_manager.md`
- `docs/代码/world_event_system.md`
- `docs/代码/gameplay_loading.md`
- `docs/测试策略.md`
- `docs/决策记录.md` ADR #197
