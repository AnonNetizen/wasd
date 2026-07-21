# MapManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/代码文档规范.md`、`docs/游戏设计文档.md` 与 `client/data/README.md`。
> 本文档是有限地图、矩形俯视格、PCG 初始摆放和人工调整点的代码契约；改地图数据 schema、生成规则、run 快照字段或与 Spawner / HazardSystem 的依赖时必须同步本文档、`docs/代码/gameplay_runtime.md`、`docs/代码/hazard_system.md`、GDD、ADR 和测试策略。

## 职责

- 把每局地图从无限扩展改为有明确边界的开放有限地图。
- 读取 `client/data/map_layouts.json`，解释矩形地图尺寸、矩形格尺寸、玩家出生点、安全半径、刷怪边距、PCG 机关规则和人工摆点。
- 提供统一的世界坐标 ↔ 矩形格锚点吸附口径；玩家出生点落在格心，机关按 `radius_tiles` 奇偶吸附到能让外边缘贴格线的锚点。
- 使用 `RNG.world` 生成可复现的初始机关摆放；手工摆点先放置，PCG 和 WarzoneDirector 兴趣点机关会按同一锚点规则吸附并避开已有 placement；带可伤害目标或交互缓存箱的兴趣点会先生成独立格心 anchor，再把机关放到附近并避开 POI footprint；anchor 摆位首轮尊重 `min_spacing`，空间过紧时降级为只保证不重叠，避免 POI 目标 / 缓存语义消失。
- 给玩家移动、敌人实体移动、刷怪和机关摆放提供同一套轴对齐矩形逻辑边界 clamp，不直接处理输入、敌人 AI 评分或机关伤害。
- 绘制与矩形地图格一致的可见地图边界和出生安全区提示；当前 `bounds` 表示轴对齐矩形范围，可见边界和逻辑边界共享 `boundary_points()` / `boundary_half_extents()`；出生安全区视觉使用吸附到格线的矩形，不再画正圆。
- 提供 JSON 友好的 `snapshot()` / `restore_snapshot()`，让暂停续局恢复同一张地图和同一批机关位置；旧快照里的自由坐标 placement 会在恢复时按当前矩形格吸附并 clamp。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 调地图大小 / 矩形格 / 出生点 | `client/data/map_layouts.json` |
| 调 PCG 机关数量 / 间距 | `map_layouts.json.pcg.hazards[]` |
| 固定摆放测试机关 | `map_layouts.json.manual_hazards[]` |
| 接入战区兴趣点机关 | `client/data/warzone_directors.json` 与 `client/scripts/gameplay/warzone_director.gd` |
| 改地图运行时边界 | `client/scripts/gameplay/map_manager.gd` |
| 排查保存续局地图不一致 | `MapManager.snapshot()` / `restore_snapshot()` 与 `docs/代码/save_manager.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/map_manager.gd` | `MapManager` 节点脚本，解释有限边界、PCG 摆放、spawn clamp 和地图快照 |
| `client/data/map_layouts.json` | 地图 layout 数据源 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 选择当前模式 layout、配置 MapManager、设置玩家 / 敌人移动边界、生成 / 恢复机关 |
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

`MapManager` 是 `Node2D`，绘制矩形有限地图边框与出生安全矩形；机关节点不挂在 `MapManager` 下，而是由 `GameplayRunLoop` 通过 `PoolManager` 放入 `ActiveWorld`。

## 运行流程

| 阶段 | 发生什么 | 关键 API |
|------|----------|----------|
| 数据加载 | `GameplayRunLoop` 读取 `game_modes.json` 后按 `mode_id` 找第一条 layout | `_load_map_layout()` |
| 配置 | 运行时把 layout 与 `hazards.csv` 行数据交给 `MapManager`，解析 bounds 与 `grid.cell_width/cell_height` | `configure(layout_data, hazard_rows)` |
| 开局 | `MapManager` 先放 `manual_hazards`，再按 `pcg.hazards` 摆放机关，最后解释 WarzoneDirector 当前 layout 的兴趣点机关；奇数 `radius_tiles` 吸附格心，偶数吸附网格顶点；带 `target_hp` 的兴趣点会额外生成 `interest_point_target_position` 目标 marker，带 `requires_interaction` 且无目标的兴趣点会额外生成 `interest_point_cache_position` 缓存 marker，并让关联机关避开该 POI 占格；即使关联机关找不到合法摆位，POI marker 仍保留，anchor 摆位也会在严格间距失败后降级为不重叠摆位，避免 POI 奖励 / 撤离 / 交互语义丢失 | `generate_hazard_placements()` |
| 实体边界 | 玩家出生点、玩家移动位置和敌人移动位置由矩形逻辑边界 clamp | `player_start()`、`clamp_position()`、`Player.set_movement_bounds()`、`Enemy.set_movement_bounds()` |
| 可见边界 | 地图边框按 `bounds` 的左上 / 右上 / 右下 / 左下四点绘制成矩形 | `boundary_points()`、`boundary_half_extents()`、`debug_summary()` |
| 出生安全区 | `safe_radius` 仍用于 PCG 避让距离；可见提示按矩形格向外吸附，显示为贴地矩形而不是圆 | `safe_zone_points()`、`safe_zone_half_extents()`、`debug_summary()` |
| 刷怪边界 | Spawner 的视野外候选位置会被 clamp 到矩形地图内并留出边缘边距 | `spawn_position(player_position, viewport_size)` |
| 保存 | run payload 保存 layout、bounds、grid cell size、出生点、safe radius、刷怪边距和机关 placement | `snapshot()` |
| 恢复 | 续局先恢复 `MapManager` 快照，再按快照重建机关；旧存档无机关快照时重新生成，旧 placement 自由坐标会吸附到当前矩形格 | `restore_snapshot()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(layout_data, hazard_rows)` | layout 字典、`hazards.csv` 行字典 | `void` | 每局开局 / 续局前调用；清空旧 placement |
| `generate_hazard_placements(layout_data, director_interest_points)` | layout 字典、可选导演兴趣点数组 | `Array[Dictionary]` | 使用 `RNG.world`，返回手工 + PCG + director placement 深拷贝 |
| `restore_snapshot(snapshot_data)` | run payload 中的 map 字典 | `void` | 只接受 JSON 友好字段；缺字段使用当前配置 fallback；placement 位置会按当前 grid 规范化 |
| `snapshot()` | 无 | `Dictionary` | 保存有限地图和机关 placement |
| `bounds()` | 无 | `Rect2` | 轴对齐矩形地图范围，地图以原点为中心 |
| `boundary_points()` | 无 | `PackedVector2Array` | 可见 / 逻辑矩形地图边界顶点，顺序为左上 / 右上 / 右下 / 左下 |
| `boundary_center()` | 无 | `Vector2` | 矩形边界中心 |
| `boundary_half_extents()` | 无 | `Vector2` | 矩形边界水平 / 垂直半尺寸 |
| `safe_zone_points()` | 无 | `PackedVector2Array` | 出生安全区可见矩形顶点，顺序为左上 / 右上 / 右下 / 左下；`safe_radius == 0` 时为空 |
| `safe_zone_half_extents()` | 无 | `Vector2` | 出生安全区可见矩形半尺寸；按 grid 向外吸附到格线 |
| `grid_cell_size()` | 无 | `Vector2` | 返回单个矩形格宽 / 高，用于背景网格和机关尺寸 |
| `player_start()` | 无 | `Vector2` | 已 clamp 到矩形边界 |
| `hazard_placements()` | 无 | `Array[Dictionary]` | 每项含 `hazard_id`、`position`、`source`；director placement 额外含 `interest_point_id`、可选 `interest_point_target_position` / `interest_point_cache_position` 与 `interest_point_*` 奖励 / 领取 / 交互元数据；带目标或交互缓存箱的 POI 会有一条 `hazard_id=""` 的 marker，供 `GameplayRunLoop` 生成兴趣点目标 / 缓存箱，不会生成真实机关节点 |
| `clamp_position(world_position)` | 世界坐标 | `Vector2` | clamp 到矩形逻辑边界；当前约束玩家和敌人中心点 |
| `snap_to_grid(world_position)` | 世界坐标 | `Vector2` | 吸附到最近矩形格中心 |
| `normalize_hazard_position(world_position, hazard_id)` | 世界坐标、机关 id | `Vector2` | 按 `radius_tiles` 奇偶吸附到合法锚点，并确保完整机关边界留在矩形地图内 |
| `spawn_position(player_position, viewport_size)` | 玩家位置、视口尺寸 | `Vector2` | 用 `RNG.spawn` 选角度，再 clamp 到矩形边缘内侧 |
| `debug_summary()` | 无 | `Dictionary` | smoke / GM 诊断使用 |

## 数据与契约

- `map_layouts.json.schema_version` 当前为 `1`。
- `layouts[].mode_id` 必须存在于 `game_modes.json`。
- `bounds.width` / `bounds.height` 必须大于 `0`，单位 px，并分别是 `grid.cell_width` / `grid.cell_height` 的整数倍。
- `grid.cell_width` / `grid.cell_height` 定义单个矩形格宽 / 高，当前默认 `160 x 160`。
- `player_start` 必须落在矩形格中心；`manual_hazards[]` 按机关 `radius_tiles` 奇偶校验：奇数尺寸在格心，偶数尺寸在网格顶点。PCG 随机候选会运行时吸附到同一类合法锚点。
- `pcg.hazards[].id` 与 `manual_hazards[].id` 必须存在于 `hazards.csv`。
- `pcg.hazards[].count` 为目标数量；约束太紧时实际 placement 可以少于目标，但不能越界或进入出生安全距离。
- `safe_radius` 是 PCG 避让出生点的距离下限，视觉提示会转换成贴格矩形并向外吸附到最近格线；它不是一个正圆地面资产。
- 机关实际边界由 `hazards.csv.radius_tiles` 与当前 grid cell size 推导；奇数 / 偶数锚点不同是为了保证机关外边缘贴住背景矩形格线，PCG 会确保机关完整留在矩形地图内。
- PCG 随机只用 `RNG.world`；刷怪候选位置只用 `RNG.spawn`。
- placement 的 `source` 当前使用 `"manual"`、`"pcg"` 与 `"director"`，用于诊断，不作为 gameplay 分支条件；`"director"` placement 来自 `warzone_directors.json.interest_points[]`，可带 `interest_point_id`，带 `target_hp` 时会附加 `interest_point_target_position` 作为目标格心，带 `requires_interaction` 且无目标时会附加 `interest_point_cache_position` 作为缓存箱格心，并透传 `interest_point_claim_radius`、`interest_point_requires_interaction`、`interest_point_resource_rewards`、`interest_point_gear_mod_rewards`、`interest_point_target_hp`、`interest_point_target_hit_radius`、`interest_point_completes_run`、`interest_point_extraction_radius`、`interest_point_extraction_hold_time` 等元数据给 `GameplayRunLoop`。POI marker 的 `hazard_id` 为空，表示只提供 POI 目标 / 缓存 / 奖励 / 交互 / 撤离元数据；`GameplayRunLoop._spawn_hazard()` 会跳过它。`MapManager` 只负责摆放和快照，不负责发奖励、生成缓存箱、生成目标、开启撤离或结束本局。

## 依赖

- 上游依赖：`DataLoader`、`RNG.world`、`RNG.spawn`、`hazards.csv`、`map_layouts.json.grid`、`WarzoneDirector` 过滤后的兴趣点数据。
- 下游调用方：`GameplayRunLoop`、`Player` / `Enemy` 移动边界、Spawner 位置选择、HazardSystem 机关生成、runtime / F9 smoke。
- 禁止依赖：不得直接读取输入、直接实例化机关场景、直接造成伤害、直接读写 `SaveManager`；不得按 layout id 或 hazard id 写特殊分支。

## 模块世界复用（F13）

ADR #142 的模块大地图（详见 `docs/代码/module_world_manager.md`）把 `MapManager` 当作全图矩形几何 carrier 复用，不分叉边界与格子算法：

- 默认模块模式用世界配置生成单个 99×99 格、15,840×15,840 px 的 bounds，并统一复用 `grid_cell_size()`、`clamp_position()`、`player_start()` 与移动边界注入；跨模块时不重配全图 bounds。
- 模块模式**不调** `generate_hazard_placements()`，也不解释 `WarzoneDirector` 兴趣点。模块 JSON 的敌人、机关、奖励、目标和撤离摆放由 `GameplayRunLoop` 解释，`ModuleWorldManager` 负责 assignment / 流式状态，`ModuleChunk` 负责合并绘制与碰撞。
- `--open-warzone` 对照回归仍走旧 `configure()` + `generate_hazard_placements()` 路径；两条 carrier 共享同一份矩形 grid / bounds / clamp 几何 API。

## 扩展点

- 新地图：新增 `layouts[]`，绑定现有或新模式；如果同一模式需要多张图，先明确选择规则再扩 schema。
- 新 PCG 内容类型：优先在 `map_layouts.json` 增加同级规则，例如后续 `pcg.points_of_interest`；运行时先做通用规则解释，避免按内容 id 特判。
- 战区兴趣点：优先在 `warzone_directors.json.interest_points[]` 声明战区主题机关组合；`MapManager` 只解释 `hazard_ids[]`、可选 `min_distance_from_player` / `min_spacing` 与 layout 过滤后的通用 placement，并透传奖励 / 交互 / 可伤害目标 / 撤离元数据，不按兴趣点 id 分支。有可伤害目标或交互缓存箱时，POI anchor 使用格心，机关围绕 anchor 摆放但不得与 POI footprint 重合；若严格 `min_spacing` 找不到 anchor，会降级到 POI 与已有 POI / 机关 footprint 不重叠的合法点。F12 首片用该机制表达精英巢点、Mod 缓存、资源缓存和小巢核占位；`requires_interaction` 由 `GameplayRunLoop` 解释为可见缓存箱，MapManager 不实例化箱体。
- 新机关类型：先在 `hazards.csv` 加基础数值，再在 `map_layouts.json` 引用；运行时仍走通用 `Hazard`，除非需要全新行为 primitive。
- 边界表现：可扩展 `MapManager._draw()` 或替换为 TileMap / 美术资源；当前可见边界和逻辑边界必须保持同一套矩形轮廓，玩家与敌人中心移动边界由 `bounds()` / `boundary_half_extents()` 注入。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调地图宽高 / 矩形格 / 出生点 | `client/data/map_layouts.json` | `client/data/README.md` | `validate_data` + `runtime-smoke` |
| 固定 FEA-12 测试点 | `map_layouts.json.manual_hazards` | `client/data/README.md` | `f9-demo-smoke` |
| 增加 PCG 机关数量 | `map_layouts.json.pcg.hazards` | `client/data/README.md` | `runtime-smoke`；`perf-probe` 仅在用户明确要求时运行 |
| 增加战区兴趣点机关 / 奖励 | `warzone_directors.json.interest_points` | `client/data/README.md`、WarzoneDirector / Gameplay Runtime 文档 | `validate_data` + `test_data_loader_schema` + `runtime-smoke` + `f9-demo-smoke`；奖励变化追加 `gear-mod-smoke` / `save-smoke` |
| 改 PCG 约束算法 | `map_manager.gd` | 本文档、测试策略 | `runtime-smoke` + `save-smoke` + golden replay |
| 改 run 地图快照 | `map_manager.gd`、`gameplay_run_loop.gd`、`save_manager.gd` | 本文档、Gameplay Runtime、SaveManager | `save-smoke` + `runtime-smoke` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 玩家出生在边界外 | `player_start` 是否超出矩形边界；`Player.set_movement_bounds()` 是否被调用 |
| 玩家出生点 / 人工机关校验失败 | 玩家出生点必须在格心；人工机关看 `hazards.csv.radius_tiles`，奇数在格心，偶数在网格顶点 |
| 敌人跑出地图 | `Enemy.set_movement_bounds()` 是否由 `GameplayRunLoop` 在生成 / 续局恢复时调用；`runtime-smoke` 是否通过矩形移动边界断言 |
| 机关数量少于配置 | `safe_radius` / `min_distance_from_player` / `min_spacing` 是否过大；地图是否太小 |
| 战区兴趣点机关没有生成 | `warzone_directors.json.interest_points[].map_layout_id` 是否匹配当前 layout；`hazard_ids[]` 是否非空且已定义；`MapManager.debug_summary().hazard_sources.director` 是否大于 0；带目标兴趣点若只有关联机关缺失，先查目标 marker 是否仍存在 |
| 兴趣点目标和机关重合 | `interest_points[].min_spacing` 是否小于目标 footprint + 机关 footprint；runtime-smoke 的 `interest point targets should not overlap active hazards` 是否通过 |
| 交互缓存箱和机关重合 | `interest_points[].requires_interaction` 是否生成了 `interest_point_cache_position` marker；runtime-smoke 的 `interest point caches should not overlap active hazards` 是否通过 |
| 机关看起来不像格子整数倍 | `hazards.csv.radius_tiles` 是否为正整数；偶数尺寸机关是否被放在网格顶点；`WorldBackground`、`MapManager`、`Hazard.configure()` 是否拿到同一份 `grid_cell_size` |
| 地图边界看起来不贴矩形格 | `MapManager.debug_summary().boundary_shape` 是否为 `rectangle`；`boundary_points` 是否为 `bounds` 的左上 / 右上 / 右下 / 左下四点；`bounds.width / grid.cell_width` 与 `bounds.height / grid.cell_height` 是否为整数；`runtime-smoke` 的矩形边界断言是否通过 |
| 出生安全区看起来还是正圆或不贴格 | `MapManager.debug_summary().safe_zone_shape` 是否为 `rectangle`；`safe_zone_half_extents` 是否按 `grid.cell_width/cell_height` 向外吸附到格线；`runtime-smoke` 的出生安全区矩形断言是否通过 |
| 机关压在玩家身上 | `safe_radius` 是否为 0；PCG 是否绕过 `MapManager.generate_hazard_placements()` |
| 刷怪贴边或出界 | `enemy_spawn_margin` 是否太小；Spawner 是否仍使用 `MapManager.spawn_position()` |
| 续局后机关位置变化 | run payload 是否包含 `map.hazard_placements` 和 `hazards`；是否误重新消耗 `RNG.world`；旧自由坐标存档恢复后按 `radius_tiles` 奇偶吸附到合法锚点属于兼容行为 |

## 测试义务

- 改 `map_layouts.json` 或 schema：跑 `python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/sync_contracts.py --check`。
- 改 `map_manager.gd` 或 `gameplay_run_loop.gd` 地图接入：跑 `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、`runtime-smoke`、`save-smoke`；改边界形状或逻辑 clamp 时至少跑 `runtime-smoke`。
- 改 PCG 摆放、director 兴趣点接入、边界或刷怪位置：追加 `f9-demo-smoke`、`l1-smoke`，并重跑四条 checked-in golden replay runner 评估行为漂移；`perf-probe` 仅在用户明确要求性能测试时运行。

## 迁移 / 兼容

ADR #93 后 runtime payload schema 提升到 `2`，`run` payload 新增 `map` 与 `hazards`。`SaveManager` 的 `run` v1 -> v2 迁移会给旧 payload 补空 map / hazards；旧存档恢复时如缺机关快照，运行时会按当前 layout 重新生成机关，保证可加载但不保证旧局逐帧一致。

## 相关文档

- `docs/游戏设计文档.md` §5 / §9.16
- `docs/决策记录.md` ADR #93 / ADR #105 / ADR #107 / ADR #113 / ADR #125 / ADR #128
- `docs/代码/gameplay_runtime.md`
- `docs/代码/module_world_manager.md`
- `docs/代码/hazard_system.md`
- `docs/代码/save_manager.md`
- `client/data/README.md`
- `docs/测试策略.md`
