# Gameplay Runtime 模块文档

> 权威范围：本页记录正式局内编排、RunLoop 公共边界、协调器所有权、快照兼容和按风险验证。玩法规则仍以 GDD 与各领域模块文档为准。

## 职责

`GameplayRunLoop` 负责正式局内总生命周期与跨领域调用顺序：准备 / 激活、玩家与世界挂载、时间和状态门禁、Combat / 掉落 / 奖励接线、快照编排、最近交互仲裁以及公开 debug / Replay 门面。

RunLoop 不重新实现领域规则。可独立演进的状态和事务由场景内类型化协调器持有：

| 节点 | 所有权 | 明确不拥有 |
|------|--------|------------|
| `TeleportRuntimeCoordinator` | 站点索引、选择 UI、淡出事务、来源站与恢复状态 | SaveManager、Replay、RNG、场景总生命周期 |
| `GearModPlacementCoordinator` | 棋盘、待放置状态、面板、确认 / 取消事务状态 | 存档格式、掉落随机、玩家总生命周期 |
| `WorldEventRuntimeCoordinator` | controller / host、事件节点、模块坐标、波次计划、快照状态 | SaveManager、Replay、全局 RNG、模块世界总生命周期 |

每个协调器通过 typed `Bindings` 接收玩家、模块世界、生成、奖励、UI 和记录端口。RunLoop 保留现有公开方法、signal、错误文本与调用顺序；最近交互仍由 RunLoop 按既有距离和 tie-break 在兴趣点、传送台、Gear Mod 与世界事件候选之间仲裁。

## 场景与代码位置

| 路径 | 作用 |
|------|------|
| `client/scenes/gameplay/gameplay_run_loop.tscn` | 正式 scene-authored 组合根；协调器必须是显式子节点 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 跨领域薄编排、公开 API 与最近交互仲裁 |
| `client/scripts/gameplay/teleport_runtime_coordinator.gd` | 传送状态与事务协调 |
| `client/scripts/gameplay/gear_mod_placement_coordinator.gd` | Gear Mod 放置状态与事务协调 |
| `client/scripts/gameplay/world_event_runtime_coordinator.gd` | 世界事件运行时状态与事务协调 |
| `client/scripts/gameplay/run_snapshot_coordinator.gd` | Run v20 capture / restore 顺序与 typed ports |
| `client/scripts/gameplay/enemy_spawn_service.gd` | 敌人 acquire、配置、恢复与 serial 编排 |
| `client/scripts/gameplay/gameplay_debug_facade.gd` | 标准 debug 查询和命令门面 |

## 公共契约

- signals：退出标题、重开、恢复失败、准备成功 / 失败、测试岛进出，以及奖励选择和 Gear Mod 放置结果。
- 配置：恢复快照、内容可用性、难度、角色组合、加载模式与测试岛用途。
- 生命周期：`activate_prepared_run()`、`create_run_snapshot()`、`save_run_snapshot()`。
- 金币 / 奖励：等级与金币查询、消费、奖励选择请求。
- 事务门面：Gear Mod 确认 / 取消 / Replay 应用，传送 Replay 应用与 pending / completed 查询。
- debug API 保持受控门面，不允许调用方直接修改 player、pool、world event 或 module world 内部状态。

Meta 保持 v4，Run 保持 v20，Replay 保持 v10。协调器状态只通过既有快照字段投影，不新增 wire 字段；旧 Run v19 与 Replay v9 继续明确拒绝，不迁移。

## 关键顺序

- 准备期间保持不可玩；只有 `run_prepared` 后才能 `activate_prepared_run()`。
- 保存 / 恢复由 `RunSnapshotCoordinator` 按现有端口顺序执行；不得在恢复时重抽计划或重新消费 RNG。
- 传送提交顺序保持：玩家移动 → 模块流送 tick → 相机 snap → HUD / 交互刷新；失败不能留下部分提交。
- 最近交互先计算同一坐标系中的距离，再使用既有稳定 tie-break；协调器不得各自抢占输入。
- 世界事件奖励、Gear Mod 放置和传送选择的 Replay 记录仍由 RunLoop 注入的记录端口触发。

## 风险归属与最低验证

| 风险 | 权威证据 |
|------|----------|
| 传送站、选择、淡出或恢复 | `teleporter-smoke`；涉及模块流送再加 `module-world-smoke` |
| Gear Mod 待放置 / 面板 / 确认取消 | `gear-mod-pickup-smoke`；修改棋盘规则才加目标 GUT |
| 世界事件注册、波次、奖励、pin、恢复 | `world-event-smoke`；跨模块恢复再加 `module-world-smoke` |
| Run v20 capture / restore 编排 | `test_run_snapshot_coordinator.gd` + `save-smoke` |
| 公共 signal / 场景接线 / autoload | 目标集成 + formal headless boot |
| Combat、效果或生成领域规则 | 对应领域 GUT / smoke，不在 RunLoop 重复穷举 |
| 稳定玩法摘要、wire 或指纹有意变化 | 对应 Replay / golden；纯内部拆分不要求全量 replay |

本模块不再维护“任意改动都跑 full GUT、runtime-smoke、多条专项 smoke 和四条 replay”的矩阵。按当前 diff 选择一条权威层和一条关键流程闭环；只有变化横跨多个风险所有者时才组合证据。

协调器 / scene 接线变更的典型最小闭环：

```powershell
python tools/lint_gdscript_rules.py
python tools/lint_semantic_rules.py
python tools/godot_bridge.py --project client teleporter-smoke
python tools/godot_bridge.py --project client gear-mod-pickup-smoke
python tools/godot_bridge.py --project client world-event-smoke
python tools/godot_bridge.py --project client module-world-smoke
python tools/godot_bridge.py --project client headless-boot
```

视觉、双语布局、真实手柄焦点、淡入淡出观感、音效和战斗手感属于 L5，只由人工验收。

## 故障排查

- 协调器状态为空：检查场景子节点是否存在、RunLoop 是否在 `_ready()` 先配置 bindings 再启动 run。
- 专项 smoke 找不到旧私有字段：测试应通过对应协调器节点读取内部观测，不在 RunLoop 恢复重复字段。
- 续局状态漂移：检查 Run v20 既有投影和 restore 端口顺序，不在协调器新增存档字段。
- 交互提示冲突：检查 RunLoop 最近候选仲裁，不让协调器直接监听并抢占 interaction action。

## 相关文档

- `docs/测试策略.md`
- `docs/代码/run_snapshot_coordinator.md`
- `docs/代码/module_world_manager.md`
- `docs/代码/world_event_system.md`
- `docs/代码/gear_mod_system.md`
- `docs/代码/gameplay_loading.md`
