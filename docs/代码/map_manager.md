# MapManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/代码文档规范.md`、`docs/游戏设计文档.md` 与 `client/data/README.md`。
> 本文档是有限地图、PCG 初始摆放和人工调整点的代码契约；改地图数据 schema、生成规则、run 快照字段或与 Spawner / HazardSystem 的依赖时必须同步本文档、`docs/代码/gameplay_runtime.md`、`docs/代码/hazard_system.md`、GDD、ADR 和测试策略。

## 职责

- 把每局地图从无限扩展改为有明确边界的开放有限地图。
- 读取 `client/data/map_layouts.json`，解释地图尺寸、玩家出生点、安全半径、刷怪边距、PCG 机关规则和人工摆点。
- 使用 `RNG.world` 生成可复现的初始机关摆放；手工摆点先放置，PCG 会避开它们。
- 给玩家移动和刷怪提供边界 clamp，不直接处理输入、敌人 AI 或机关伤害。
- 提供 JSON 友好的 `snapshot()` / `restore_snapshot()`，让暂停续局恢复同一张地图和同一批机关位置。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 调地图大小 / 出生点 | `client/data/map_layouts.json` |
| 调 PCG 机关数量 / 间距 | `map_layouts.json.pcg.hazards[]` |
| 固定摆放测试机关 | `map_layouts.json.manual_hazards[]` |
| 改地图运行时边界 | `client/scripts/gameplay/map_manager.gd` |
| 排查保存续局地图不一致 | `MapManager.snapshot()` / `restore_snapshot()` 与 `docs/代码/save_manager.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/map_manager.gd` | `MapManager` 节点脚本，解释有限边界、PCG 摆放、spawn clamp 和地图快照 |
| `client/data/map_layouts.json` | 地图 layout 数据源 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 选择当前模式 layout、配置 MapManager、设置玩家边界、生成 / 恢复机关 |
| `client/scenes/gameplay/gameplay_run_loop.tscn` | `ActiveWorld/MapManager` 稳定节点 |
| `client/tools/runtime_smoke.gd` | 覆盖有限 bounds、MapManager 节点和续局后机关恢复 |
| `client/tools/f9_demo_smoke.gd` | 覆盖 FEA-12 机关存在、造成伤害和保存 roundtrip |
| `tools/validate_data.py` / `tools/test_data_loader_schema.py` | `map_layouts.json` schema 与跨文件引用回归 |

## 场景 / 节点结构

```text
GameplayRunLoop
└── ActiveWorld
    ├── WorldBackground
    ├── MapManager
    ├── Player
    ├── hazard_spike_* (pooled Hazard scene, active only)
    ├── bullet_basic_* (pooled Bullet scene, active only)
    └── enemy_* (pooled Enemy scenes, active only)
```

`MapManager` 是 `Node2D`，绘制有限地图边框与出生安全圈；机关节点不挂在 `MapManager` 下，而是由 `GameplayRunLoop` 通过 `PoolManager` 放入 `ActiveWorld`。

## 运行流程

| 阶段 | 发生什么 | 关键 API |
|------|----------|----------|
| 数据加载 | `GameplayRunLoop` 读取 `game_modes.json` 后按 `mode_id` 找第一条 layout | `_load_map_layout()` |
| 配置 | 运行时把 layout 与 `hazards.csv` 行数据交给 `MapManager` | `configure(layout_data, hazard_rows)` |
| 开局 | `MapManager` 先放 `manual_hazards`，再按 `pcg.hazards` 用 `RNG.world` 摆放机关 | `generate_hazard_placements()` |
| 玩家边界 | 玩家出生点和移动位置由有限 `Rect2` clamp | `player_start()`、`bounds()`、`Player.set_movement_bounds()` |
| 刷怪边界 | Spawner 的视野外候选位置会被 clamp 到地图内并留出边缘边距 | `spawn_position(player_position, viewport_size)` |
| 保存 | run payload 保存 layout、bounds、出生点、safe radius、刷怪边距和机关 placement | `snapshot()` |
| 恢复 | 续局先恢复 `MapManager` 快照，再按快照重建机关；旧存档无机关快照时重新生成 | `restore_snapshot()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(layout_data, hazard_rows)` | layout 字典、`hazards.csv` 行字典 | `void` | 每局开局 / 续局前调用；清空旧 placement |
| `generate_hazard_placements(layout_data)` | layout 字典 | `Array[Dictionary]` | 使用 `RNG.world`，返回手工 + PCG placement 深拷贝 |
| `restore_snapshot(snapshot_data)` | run payload 中的 map 字典 | `void` | 只接受 JSON 友好字段；缺字段使用当前配置 fallback |
| `snapshot()` | 无 | `Dictionary` | 保存有限地图和机关 placement |
| `bounds()` | 无 | `Rect2` | 地图以原点为中心 |
| `player_start()` | 无 | `Vector2` | 已 clamp 到 bounds |
| `hazard_placements()` | 无 | `Array[Dictionary]` | 每项含 `hazard_id`、`position`、`source` |
| `clamp_position(world_position)` | 世界坐标 | `Vector2` | clamp 到 bounds |
| `spawn_position(player_position, viewport_size)` | 玩家位置、视口尺寸 | `Vector2` | 用 `RNG.spawn` 选角度，再 clamp 到边缘内侧 |
| `debug_summary()` | 无 | `Dictionary` | smoke / GM 诊断使用 |

## 数据与契约

- `map_layouts.json.schema_version` 当前为 `1`。
- `layouts[].mode_id` 必须存在于 `game_modes.json`。
- `bounds.width` / `bounds.height` 必须大于 `0`，单位 px。
- `pcg.hazards[].id` 与 `manual_hazards[].id` 必须存在于 `hazards.csv`。
- `pcg.hazards[].count` 为目标数量；约束太紧时实际 placement 可以少于目标，但不能越界或进入安全圈。
- PCG 随机只用 `RNG.world`；刷怪候选位置只用 `RNG.spawn`。
- placement 的 `source` 当前只使用 `"manual"` 与 `"pcg"`，用于诊断，不作为 gameplay 分支条件。

## 依赖

- 上游依赖：`DataLoader`、`RNG.world`、`RNG.spawn`、`hazards.csv`。
- 下游调用方：`GameplayRunLoop`、`Player` 移动边界、Spawner 位置选择、HazardSystem 机关生成、runtime / F9 smoke。
- 禁止依赖：不得直接读取输入、直接实例化机关场景、直接造成伤害、直接读写 `SaveManager`；不得按 layout id 或 hazard id 写特殊分支。

## 扩展点

- 新地图：新增 `layouts[]`，绑定现有或新模式；如果同一模式需要多张图，先明确选择规则再扩 schema。
- 新 PCG 内容类型：优先在 `map_layouts.json` 增加同级规则，例如后续 `pcg.points_of_interest`；运行时先做通用规则解释，避免按内容 id 特判。
- 新机关类型：先在 `hazards.csv` 加基础数值，再在 `map_layouts.json` 引用；运行时仍走通用 `Hazard`，除非需要全新行为 primitive。
- 边界表现：可扩展 `MapManager._draw()` 或替换为 TileMap / 美术资源，但玩家移动边界仍由 `bounds()` / `clamp_position()` 提供。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调地图宽高 / 出生点 | `client/data/map_layouts.json` | `client/data/README.md` | `validate_data` + `runtime-smoke` |
| 固定 FEA-12 测试点 | `map_layouts.json.manual_hazards` | `client/data/README.md` | `f9-demo-smoke` |
| 增加 PCG 机关数量 | `map_layouts.json.pcg.hazards` | `client/data/README.md` | `runtime-smoke` + `perf-probe` |
| 改 PCG 约束算法 | `map_manager.gd` | 本文档、测试策略 | `runtime-smoke` + `save-smoke` + golden replay |
| 改 run 地图快照 | `map_manager.gd`、`gameplay_run_loop.gd`、`save_manager.gd` | 本文档、Gameplay Runtime、SaveManager | `save-smoke` + `runtime-smoke` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 玩家出生在边界外 | `player_start` 是否超出 `bounds`；`Player.set_movement_bounds()` 是否被调用 |
| 机关数量少于配置 | `safe_radius` / `min_distance_from_player` / `min_spacing` 是否过大；地图是否太小 |
| 机关压在玩家身上 | `safe_radius` 是否为 0；PCG 是否绕过 `MapManager.generate_hazard_placements()` |
| 刷怪贴边或出界 | `enemy_spawn_margin` 是否太小；Spawner 是否仍使用 `MapManager.spawn_position()` |
| 续局后机关位置变化 | run payload 是否包含 `map.hazard_placements` 和 `hazards`；是否误重新消耗 `RNG.world` |

## 测试义务

- 改 `map_layouts.json` 或 schema：跑 `python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/sync_contracts.py --check`。
- 改 `map_manager.gd` 或 `gameplay_run_loop.gd` 地图接入：跑 `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、`runtime-smoke`、`save-smoke`。
- 改 PCG 摆放、边界或刷怪位置：追加 `f9-demo-smoke`、`l1-smoke`、`perf-probe`，并重跑四条 checked-in golden replay runner 评估行为漂移。

## 迁移 / 兼容

ADR #93 后 runtime payload schema 提升到 `2`，`run` payload 新增 `map` 与 `hazards`。`SaveManager` 的 `run` v1 -> v2 迁移会给旧 payload 补空 map / hazards；旧存档恢复时如缺机关快照，运行时会按当前 layout 重新生成机关，保证可加载但不保证旧局逐帧一致。

## 相关文档

- `docs/游戏设计文档.md` §5 / §9.16
- `docs/决策记录.md` ADR #93
- `docs/代码/gameplay_runtime.md`
- `docs/代码/hazard_system.md`
- `docs/代码/save_manager.md`
- `client/data/README.md`
- `docs/测试策略.md`
