# HazardSystem 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/代码文档规范.md`、`docs/游戏设计文档.md` 与 `client/data/README.md`。
> 本文档是机关运行时的代码契约；改机关数据 schema、触发规则、对象池生命周期、伤害链路、run 快照字段或 FEA-12 测试机关时必须同步本文档、`docs/代码/map_manager.md`、`docs/代码/gameplay_runtime.md`、GDD、ADR 和测试策略。

## 职责

- 提供通用 `Hazard` 节点，解释 `hazards.csv` 的基础数值。
- 通过 `PoolManager` 复用机关实体，避免运行时频繁创建 / 销毁。
- 当玩家进入机关矩形触发范围且冷却结束时，使用 `Combat.apply_damage()` 统一结算伤害。
- 保存机关 id、位置、冷却和激活表现状态，支持暂停续局恢复。
- 当前只实现通用矩形范围机关；具体摆放由 `MapManager` / `map_layouts.json` 负责。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 调机关伤害 / 占格尺寸 / 冷却 | `client/data/hazards.csv` |
| 调机关初始位置 / PCG 数量 | `client/data/map_layouts.json` |
| 改机关触发 / 受击链路 | `client/scripts/gameplay/hazard.gd` |
| 排查对象池残留 | `PoolManager` 与 `GameplayRunLoop._release_active_world_pool_entities()` |
| 验证 FEA-12 | `client/tools/f9_demo_smoke.gd` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/hazard.gd` | 通用机关节点脚本 |
| `client/scenes/gameplay/hazard.tscn` | 通用机关场景资源 |
| `client/data/hazards.csv` | 机关基础数值 |
| `client/data/map_layouts.json` | 机关 PCG 规则和人工摆点 |
| `client/scripts/gameplay/map_manager.gd` | 生成机关 placement |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 注册机关对象池、生成 / 恢复机关节点、保存快照 |
| `client/tools/runtime_smoke.gd` | 覆盖 active hazards 启动和续局恢复 |
| `client/tools/f9_demo_smoke.gd` | 覆盖 FEA-12 造成玩家伤害和保存 roundtrip |
| `client/tools/perf_probe.gd` | 记录 active hazards 与机关池峰值 |

## 场景 / 节点结构

```text
ActiveWorld
├── MapManager
├── Player
└── hazard_spike_* (pooled Hazard scene)
```

当前 `hazard_spike` pool id 复用 `client/scenes/gameplay/hazard.tscn`。不同机关 id 的数值差异来自 `hazards.csv`，不是不同场景。

## 运行流程

| 阶段 | 发生什么 | 关键 API |
|------|----------|----------|
| 预热 | `GameplayRunLoop` 注册并预热 `POOL_IDS.HAZARD_SPIKE` | `PoolManager.register_pool()` / `prewarm()` |
| 开局摆放 | `MapManager` 返回 placement，运行时按 `hazard_id` 查 `hazards.csv` 行数据 | `_spawn_map_hazards()` |
| 配置 | 对象池取得节点后设置 id、伤害、伤害类型、触发间隔、`radius_tiles`、grid cell size、持续时间和目标玩家 | `Hazard.configure()` |
| 物理帧 | 仅在 `GameState.PLAYING` 时消耗 `GameClock.delta_scaled()`；玩家在矩形范围内且冷却结束则触发 | `_physics_process()` |
| 伤害 | 构造 `DamageInfo`，source team 为敌对，target team 为玩家，统一交给 `Combat` | `Combat.apply_damage()` |
| 保存 | run payload 记录活动机关 id、位置和剩余冷却 / 激活时间 | `snapshot()` |
| 恢复 | 先按 id 重新配置，再恢复位置与冷却 | `restore_snapshot()` |
| 清理 | 切回标题 / 退出树时主动 release 活跃池化节点，避免 PoolManager 持有失效节点 | `_pool_release()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(hazard_data, target, grid_cell_size)` | `hazards.csv` 行数据、玩家节点、地图矩形格尺寸 | `void` | 对象池 acquire 后唯一配置入口 |
| `hazard_id()` | 无 | `String` | smoke、调试和保存使用 |
| `snapshot()` | 无 | `Dictionary` | JSON 友好；不保存目标节点引用 |
| `restore_snapshot(snapshot_data)` | 机关快照 | `void` | 配置后调用 |
| `_pool_reset()` | 无 | `void` | 清空运行时状态，供 `PoolManager` 调用 |
| `_pool_release()` | 无 | `void` | 退出 `active_hazards` 组并断开目标引用 |

## 数据与契约

- `hazards.csv.id` 必须唯一，模式池、PCG 和人工摆点都引用此 id。
- `tags` 必须含 `tag_hazard`。
- `pool_id` 必须来自词表 §8；当前 `hazard_spike` 复用通用 `Hazard` 场景。
- `damage_type` 必须来自词表 §9，并经 `Combat` 校验。
- `trigger_interval` 单位秒，运行时下限为 `0.01`。
- `radius_tiles` 为正整数，表示机关矩形 footprint 从中心到边缘占用的半格数；最终半宽 / 半高由 `MapManager.grid_cell_size()` 推导。为让外边缘贴住背景矩形格线，奇数尺寸机关中心吸附到格心，偶数尺寸机关中心吸附到网格顶点。
- 触发判定与视觉矩形使用同一套轴对齐范围：`abs(dx) <= half_width and abs(dy) <= half_height`。不要再用旧的像素 `radius`、菱形或圆形近似。
- `duration` 当前只影响触发后的占位激活表现，不控制伤害总时长。
- FEA-12 首片 id 为 `hazard_fea_12_pulse`，用于测试 PCG 和机关伤害链路；代码不得按该 id 特判。

## 依赖

- 上游依赖：`GameState`、`GameClock`、`PoolManager`、`Combat`、`DamageInfo`、`MapManager`、`hazards.csv`。
- 下游调用方：`GameplayRunLoop`、runtime / F9 smoke、perf probe。
- 禁止依赖：不得直接扣玩家生命、不得绕过 `PoolManager` 实例化高频机关、不得使用原始 `delta` 计时、不得按 `hazard_id` 写特殊分支。

## 扩展点

- 新普通矩形范围机关：只加 `hazards.csv` 行、locale 文案、模式池引用和 `map_layouts.json` 摆放规则；尺寸用 `radius_tiles` 表达为格子的整数倍。
- 新视觉表现：可扩展 `Hazard._draw()` 或替换为子节点资源，但不要改变 `configure()` 契约。
- 新触发 primitive：例如喷火口、激光、毒池，应先确定是否仍可由通用 `Hazard` 参数表达；不能表达时再新增可复用策略字段和对应文档 / smoke，不按单个 id 分支。
- 后续波次机关：`spawn_waves.csv.hazard_id` / `hazard_weight` 是时间压力预留；接入时仍应走 `PoolManager` 与 `Combat`。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调 FEA-12 伤害 / 占格尺寸 | `client/data/hazards.csv` | `client/data/README.md` | `validate_data` + `f9-demo-smoke` |
| 调 FEA-12 位置 | `client/data/map_layouts.json` | `client/data/README.md`、MapManager 文档 | `runtime-smoke` + `f9-demo-smoke` |
| 改机关伤害链路 | `hazard.gd` | 本文档、Combat 文档 | `runtime-smoke` + `f9-demo-smoke` |
| 改机关保存字段 | `hazard.gd`、`gameplay_run_loop.gd`、`save_manager.gd` | 本文档、Gameplay Runtime、SaveManager | `save-smoke` + `runtime-smoke` |
| 新机关对象池 | `docs/词表与契约.md`、`hazards.csv`、`PoolManager` 注册处 | 本文档、词表、数据手册 | `sync_contracts --check` + headless |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 机关不出现 | `map_layouts.json` 是否生成 placement；`game_modes.json.resource_pools.hazards` 是否包含 id；对象池是否注册 |
| 机关出现但不伤害 | `GameState` 是否为 `PLAYING`；玩家是否在 `radius_tiles` 与地图 grid 推导出的矩形范围内；`damage` / `damage_type` 是否有效；玩家是否仍在受伤无敌期 |
| 机关看起来不像矩形格整数倍 | `GameplayRunLoop` 是否把 `MapManager.grid_cell_size()` 传给 `Hazard.configure()`；`hazards.csv.radius_tiles` 是否为正整数；偶数尺寸机关是否吸附到网格顶点；背景网格是否来自同一份 `grid.cell_width/cell_height` |
| 机关重复伤害太快 | `trigger_interval` 是否过低；玩家无敌窗口是否被测试清零 |
| 续局后机关消失 | run payload 是否有 `hazards`；恢复时是否按 `hazard_id` 查到 `hazards.csv` 数据 |
| 切回标题后 pool 报失效节点 | `GameplayRunLoop._exit_tree()` 是否 release 活跃池化节点；`PoolManager.clear_pool()` 是否清掉对应 pool id 映射 |

## 测试义务

- 改 `hazards.csv` 或 `map_layouts.json`：跑 `python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/sync_contracts.py --check`。
- 改 `hazard.gd` / 机关生成或恢复：跑 `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、`runtime-smoke`、`save-smoke`、`f9-demo-smoke`。
- 改机关数量、池化生命周期或性能相关行为：追加 `l1-smoke`、`perf-probe`，并重跑 checked-in golden replay runner 评估稳定摘要变化。

## 迁移 / 兼容

ADR #93 后 runtime payload schema 提升到 `2`，新增 `hazards` 数组保存活动机关。`SaveManager` 的旧 run 迁移会补空数组；旧存档如果没有机关快照，运行时从当前 `map_layouts.json` 重新生成初始机关，保证能继续加载但不保证旧局逐帧一致。

## 相关文档

- `docs/游戏设计文档.md` §5.4 / §9.15.1 / §9.16
- `docs/决策记录.md` ADR #93 / ADR #103 / ADR #105 / ADR #125
- `docs/代码/map_manager.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/combat.md`
- `docs/代码/save_manager.md`
- `client/data/README.md`
- `docs/测试策略.md`
