# ModuleWorldManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 F13 模块世界运行时、坐标、流式状态、F14 静态导航查询与 run v4 边界的权威模块契约。

## 1. 职责

`ModuleWorldManager` 是 F13 默认 9×9 无缝模块世界的局内协调点，以正式场景预置在 `GameplayRunLoop/ActiveWorld` 下，不是 autoload。它负责：

- 按 run seed 和 `RNG.world` 从已批准模板池组合 81 个世界槽位，失败时回退到已校验安全布局。
- 保持模块坐标 `0..8`、局部格 `0..10`、全局格 `0..98` 与世界坐标转换一致；`(49,49)` 映射世界原点。
- 计算稳定 map hash：hash 覆盖世界配置、seed、81 槽 assignment / rotation 与模块 schema v1 等价的 gameplay projection；地形、派生通道、摆放、格尺寸或锚点变化会让旧 run fail closed，视觉层和图块目录不进入 hash。保存模块级迷雾 / 访问状态与按世界槽位隔离的动态状态。
- 只激活玩家当前模块周围最多 3×3 个 `ModuleChunk`；九个 chunk 已预置在 manager 场景内并循环复用，不创建 81 个槽位节点。
- 在运行开始和 run 恢复时，为当前 assignment 预加载唯一的模块 / 旋转 `PackedScene`；跨模块只替换离开 / 进入边缘的最多三块，不在边界读取磁盘。
- 从旋转 / 封边后的完整 81 槽地形构建 99×99 walkability mask；玩家跨格时只更新感知范围驱动的局部共享流场，并提供全图 AStar、视线和敌人半径走廊查询。导航不依赖当前激活 chunk。

`GameplayRunLoop` 仍负责敌人 / 机关 / 奖励 / 目标 / 撤离 primitive 的实体生成、`Combat`、`PoolManager` 和 run v4 快照。`ModuleWorldManager` 不直接生成玩法实体。

## 2. 数据边界

- 世界配置：`client/data/module_worlds.json`
- 模块注册表：`client/data/module_templates.json`
- 模块玩法内容：`client/data/modules/*.json`
- 模块视觉 / 碰撞生成物：`client/scenes/generated/modules/<id>/rotation_<degrees>.tscn`
- 人工 / AI 模板：`client/templates/module_template.json`
- 权威设计：F13 世界见 `F13-ModularGridWorld.md` / ADR #142；JSON 制作与单向烘焙见 ADR #154；F14 导航见 `F14-EnemyNavigationAndPerception.md` / ADR #145 / #146

运行时用 JSON 计算 assignment、导航、placement 和 map hash，并直接实例化预加载的生成 TSCN；不会从 JSON 构建 TileMap 或碰撞，也不连接 LLM。新 AI 模块默认是 `module_review_candidate`；只有人工改为 `module_review_approved` 后才能进入默认池。

## 3. 公共 API

| API | 用途 |
|-----|------|
| `configure(world_def, registry_by_id, templates_by_id, generated_scene_paths_by_key, run_seed, navigation_flow_radius_cells)` | 设置世界、JSON / 生成场景映射、局部活动流场半径并生成默认 assignment；预加载 assignment 使用的唯一场景，缺少模块或允许旋转的生成物时拒绝配置 |
| `build_assignment()` / `build_fallback_assignment()` / `build_technical_slice_assignment()` | seed 组图、安全布局、中心 3×3 技术首片 |
| `tick(player_position)` | 始终更新精确玩家导航目标；仅跨全局格时重算流场，同时更新当前模块、迷雾和 chunk 流式变更 |
| `world_to_global_cell()` / `global_cell_to_world()` | 世界坐标与 99×99 全局格转换 |
| `global_cell_to_module_and_local()` / `module_local_to_global_cell()` | 全局格与模块 + 局部格转换 |
| `is_world_position_walkable()` | 判断世界位置是否落在有效 `module_cell_floor`；模块敌人生成 / 恢复门禁复用此入口 |
| `navigation_query_to_active_target(from)` | 查询到精确玩家目标的可达性、世界像素路径距离和共享流场下一格中心；来源在活动窗口外时返回不可达 |
| `navigation_query(from, target)` | 在同一静态 mask 上查询守家 / 最后已知位置的 AStar waypoint；仅由 Enemy 决策 tick 调用 |
| `has_terrain_line_of_sight(from, target)` | 用封锁格 supercover 语义判断地形视线 |
| `has_clear_corridor(from, target, clearance)` | 将封锁格按敌人半径扩张后判断连续直线走廊 |
| `placements_at(module_coord)` | 返回已旋转、含 `world_position` 的内容摆放 |
| `set_slot_state()` / `slot_state()` | 保存按世界槽位隔离的动态状态 |
| `snapshot()` / `restore_state()` | run v4 assignment、内容敏感 map hash、迷雾和槽位状态 roundtrip；恢复时事务式重建场景缓存，hash / assignment / 生成场景不一致时返回失败，不继续恢复旧实体 |
| `debug_summary()` | 输出几何、assignment/hash、访问 / 活跃数、预加载场景数及导航目标格、局部半径 / 边界 / 本次访问格数、流场重建次数和可达格数 |

## 4. ModuleNavigationField

`ModuleNavigationField` 是 `RefCounted` 内部数据对象，不创建格子 Node：

- 共享目标使用确定性八方向 Dijkstra；活动窗口半径由 `ceil(max_sight_radius / cell_size) + 2` 推导，当前为 8 格、最多 289 格。对角步仅在两个相邻正交格都可走时开放，固定邻居顺序并用全局格索引处理同成本路线。
- 每次重建只清理上一次实际触达的格索引；最小堆使用距离与格索引的并行数值数组，不产生逐节点 `Dictionary`。完整 99×99 距离 / next 数组只在配置时初始化。
- 路径距离使用世界像素，并加上敌人 / 玩家精确位置到各自格心的端点距离。
- 非玩家目标复用 `AStarGrid2D`，`DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES` 禁止斜穿墙角。
- assignment 生成、技术首片构建和 run 恢复成功后重建 mask；越界或封锁目标统一返回 `reachable=false`。
- 流场、AStar 和感知查询都是派生临时状态，不改变 map hash，也不写入 run v4。

## 5. ModuleChunk

`ModuleChunk` 是九个预置流式槽位共用的薄场景。激活时挂载一个缓存的生成 `PackedScene`；生成实例已经包含 Ground / Obstacles / Decoration 三个 `TileMapLayer`、合并后的基础碰撞和四个边缘封锁视觉 / 碰撞子树，运行时只切换封边状态。它不解析 JSON 建 TileMap、不创建碰撞节点、不扫描 121 格，也不应用 `TileMapPattern`。

生成场景的 `TerrainCollision` 显式位于物理层 bit 1、mask 为 0；玩家和敌人都必须保留 `CollisionShape2D`，否则 `CharacterBody2D` 不会与这些边界发生碰撞。敌人的碰撞层不与玩家或其他敌人物理互顶，只用 mask 命中模块地形；原有中心分离继续负责实体间距。`Bullet` 也只查询 bit 1：默认以 `hit_radius` 圆形做首帧重叠和逐帧扫掠，命中后通过 `PoolManager` 回收；`wall_pierce_enabled=true` 时才忽略地形。bit 1 是 ModuleChunk 与 Bullet 的稳定内部契约，不应用玩家、敌人、机关 Area 或伤害目标复用该查询语义。`ModuleWorldManager` 使用显式 `z_index=-90`，使模块地形位于 `WorldBackground(-100)` / `MapManager(-95)` 之上，同时稳定处于玩家、敌人、机关和目标实体之下；不能依赖场景树加入顺序决定遮挡关系。禁止为 121 个格逐格创建 Node，也禁止同时实例化 81 个 chunk。

## 6. 验证

```powershell
python tools/sync_contracts.py --check
python tools/validate_data.py
python tools/test_data_loader_schema.py
python tools/godot_bridge.py --project client headless-boot
python tools/godot_bridge.py --project client module-world-smoke
python tools/godot_bridge.py --project client module-world-technical-slice-smoke
python tools/godot_bridge.py --project client save-smoke
```

性能测试不属于本模块的默认验证义务；只有用户当次明确要求时，才追加 `python tools/godot_bridge.py --project client startup-probe` 或 `perf-probe`。

`module-world-smoke` 覆盖同 seed assignment / 内容敏感 hash、不同 seed 普通槽变化、中心坐标、确定性共享流场、半径 8 / 289 格访问上限、连续跨 20 格不退化、活动窗口外查询与全图 AStar 分流、真实模块绕障、路径距离大于直线距离、禁止斜穿墙角、封锁 / 越界目标不可达、技术首片外圈不可进入，以及正式 manager / 九 chunk 场景、assignment 唯一场景预加载、生成 TileMap / 合并碰撞、跨边缘最多三块替换、玩家 / 敌人物理墙体、玩家 / 敌方普通子弹阻挡、`wall_pierce > 0` 穿过同一墙体、旧子弹快照缺字段默认阻挡、穿墙快照随槽位卸载 / 返回保持、生成门禁、无缝跨边界、最多 9 个 active chunk、流式恢复、迷雾、目标撤离、run v4 和 hash mismatch。`module-world-technical-slice-smoke` 通过正式 opt-in 入口追加中心 3×3 / 外圈 72 槽封锁的完整流程回归。
