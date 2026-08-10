# RunSnapshotCoordinator 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 Run v19 gameplay payload 组装与恢复顺序的代码契约权威；改顶层字段、恢复次序、端口或测试义务时必须同步本文档。

## 职责

- 按稳定插入顺序组装 Gameplay Run v19 的 30 个顶层字段，并对容器值做深拷贝。
- 以 `RestoreBindings` 类型端口编排验证、领域恢复、实体恢复、时钟与 HUD 刷新的固定顺序。
- 保证同步恢复与 staged loading 恢复共用同一业务顺序；staged 差异只由 RunLoop 提供的分批 / yield 端口实现。
- 本模块不负责 RunLoop 生命周期、场景节点、`run_prepared` / `run_prepare_failed` signal、UI 恢复时机、实体材化细节或存档 envelope。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改 Run v19 顶层字段与顺序 | `client/scripts/gameplay/run_snapshot_coordinator.gd` 的 `CaptureState` / `capture()` |
| 改恢复的跨域顺序 | 同文件的 `RestoreBindings` / `restore()` |
| 改具体地图、玩家、Gear Mod 或实体恢复 | `client/scripts/gameplay/gameplay_run_loop.gd` 的 `_snapshot_restore_*` leaf 方法 |
| 改存档 envelope 或 `mod_environment` | `docs/代码/save_manager.md` 与 `client/scripts/autoload/save_manager.gd` |
| 改准备 / 激活 / UI 恢复时机 | `docs/代码/gameplay_loading.md` 与 `GameplayRunLoop` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/run_snapshot_coordinator.gd` | 纯 `RefCounted` 协调器、capture state 与 restore ports |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 保留公开 `create_run_snapshot()` 和私有 `_restore_run_snapshot()` wrapper，构造 state / bindings 并执行 leaf 恢复 |
| `client/tests/unit/test_run_snapshot_coordinator.gd` | 顶层字段顺序、深拷贝、sync / staged 端口顺序等价 |
| `client/tools/save_manager_smoke.gd` | Run v19 完整 round-trip 与实体 / 模块世界恢复集成门禁 |

## 场景 / 节点结构

无。`RunSnapshotCoordinator` 是 `RefCounted`，不进入场景树，不持有 gameplay 节点引用。`GameplayRunLoop` 持有唯一协调器实例。

## 运行流程

### 捕获

1. `GameplayRunLoop.create_run_snapshot()` 在 debug test arena 外构造 `CaptureState`。
2. RunLoop 从现有域对象捕获快照；协调器不反向查找节点或调用字符串 API。
3. `capture()` 按 Run v19 固定顺序输出 30 个字段。`mod_environment` 仍由 `SaveManager.save()` 注入 envelope，不属于本协调器。

### 恢复

| 顺序 | 阶段 |
|------|------|
| 1 | schema、Gear Mod 数字归一、内容进度容器、地面 Gear Mod 快照验证 |
| 2 | Difficulty |
| 3 | ModuleWorld 状态、兴趣点 / 世界事件注册、WorldEvent 状态、active module 激活 |
| 4 | GoldProgression、RewardChoice |
| 5 | kills、enemy serial、Gear Mod instance id、spawn states |
| 6 | RNG、Map 与玩家边界、Player、Weapon |
| 7 | Gear Mod board、modifier / effect source 重建、Skills、GameplayEffectRuntime |
| 8 | Hazards、interest point state 与表现 |
| 9 | Enemies、Bullets、GoldOrbs、EnergyOrbs、GearModPickups |
| 10 | GameClock、HUD |

`ui_restore` 不在上表内：恢复成功后 RunLoop 先暂存，只在 `activate_prepared_run()` 进入 `PLAYING` 后处理。

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `capture(state)` | 已捕获的 `CaptureState` | Run v19 `Dictionary` | 固定 30 字段与插入顺序；容器深拷贝；不注入 `mod_environment` |
| `restore(snapshot_data, bindings, staged_loading)` | Run v19 payload、类型端口、是否 staged | `bool` | 失败 fail-closed；保留旧错误文本和副作用顺序 |

RunLoop 现有 wrapper 名保持不变：外部仍调用 `create_run_snapshot()`，内部恢复路由仍使用 `_restore_run_snapshot()`。

## Signal / Event

无。协调器不发 signal。准备成功 / 失败 signal 仍由 `GameplayRunLoop` 唯一发出。

## 数据与契约

- gameplay payload schema 保持 v19；Meta v4、Replay v9、game v1.18 不变。
- 字段语义与迁移 / 拒绝策略以 `SaveManager` 模块文档为权威。
- 协调器对 schema、内容进度类型和 RunLoop 提供的验证端口 fail-closed。
- 为保持旧行为，后续域失败前已完成的恢复副作用不回滚；实体材化失败语义也未在本次提取中改变。

## 依赖

- 上游：`GameplayRunLoop` 构造 `CaptureState` 和 `RestoreBindings`。
- 下游：`SaveManager` 保存 `create_run_snapshot()` 返回的 gameplay payload；FormalClientBoot / RunLoop 在完整恢复前仍预读角色、难度、内容和 module seed。
- 禁止依赖：协调器不可依赖 scene tree、autoload 具体实现、`UIManager`、`SaveManager`、任意 gameplay Node 或字符串反射。

## 扩展点与常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增 Run 顶层字段 | coordinator + RunLoop capture / restore leaf | SaveManager、测试策略、ADR / GDD（若协议变更） | 字段顺序 unit、save smoke、四组 golden |
| 修改恢复顺序 | coordinator `restore()` | 本文档流程表 | sync / staged parity、save / loading / module-world smoke、golden |
| 修改某域的恢复细节 | RunLoop 对应 `_snapshot_restore_*` | 对应域模块文档 | 该域 GUT / smoke + save |

不得为了新字段绕过 `CaptureState` 直接在 RunLoop 拼接第二份顶层字典，也不得在协调器中反向查找节点。

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 存档 hash / round-trip 漂移 | `capture()` 顶层字段顺序、容器深拷贝、SaveManager 的 `mod_environment` 注入 |
| staged 续局与同步 smoke 结果不同 | `restore()` 端口顺序与 RunLoop 两个 staged leaf 的 yield 位置 |
| 续局后 UI 提前出现 | 不要在 coordinator 内应用 `ui_restore`；检查 RunLoop 的 pending / activate 路由 |
| 后段验证失败后出现部分已恢复状态 | 这是当前兼容语义；如要改为事务恢复，必须单独立项并评估 Run v19 / golden |

## 测试义务

- 先跑 `python tools/godot_bridge.py --project client gut --test-dir unit`，要求 30 字段数量 / 顺序、深拷贝、不包含 `mod_environment` 与 sync / staged 端口顺序等价。
- 改 Run payload / restore 必跑 `save-smoke`、`runtime-smoke`、`loading-smoke`、完整与 technical `module-world-smoke`、`world-event-smoke`、formal headless boot 和四组 Replay v9 golden。
- 同时跑 contracts、data/schema、GDScript / project / semantic lint 与文档健康。
- 人工视觉、听觉、手感与真实保存续玩仍标记“待人工验收”；不运行性能 probe。

## 迁移 / 兼容

本次为内部边界提取，不修改 Meta v4、Run v19、Replay v9 或 game v1.18，不重录 golden。如需改顶层字段、验证时机或失败回滚语义，不属于无行为变化重构，必须按存档 schema 变更独立评审。

## 相关文档

- `docs/代码/gameplay_runtime.md`
- `docs/代码/gameplay_loading.md`
- `docs/代码/save_manager.md`
- `docs/代码/enemy_spawn_service.md`
- `docs/测试策略.md`
