# ModuleWorldManager 模块文档

> 权威范围：本页只记录该模块的公共契约、可观察行为、schema、所有权与依赖边界；私有实现和逐测试记录不进入本文档。
> 本文档是 F13 模块世界运行时、坐标、流式状态、限量 / 受约束模板组、后台固定、F14 静态导航查询与 Run v20 模块子快照边界的权威模块契约。

## 1. 职责

`ModuleWorldManager` 是 F13 默认 7×7 无缝模块世界的局内 `Node2D` facade，以正式场景预置在 `GameplayRunLoop/ActiveWorld` 下，不是 autoload。它负责组合纯 layout / state、场景流式和导航边界，并保留既有公开 API、错误文本与 Run v20 九字段 wire：

- 按 run seed 和 `RNG.world` 从已批准模板池组合 49 个世界槽位，失败时回退到已校验安全布局。固定起点为 `(0,6)` 的 `module_start_corner`；意识核等概率选择 `(0,0)`、`(6,0)` 或 `(6,6)`。其后先放置恰好 3 座 `module_teleporter_pad`，两两模块曼哈顿距离 ≥4，再分配世界事件与普通平地。
- 保持模块坐标 `0..6`、局部格 `0..10`、全局格 `0..76` 与世界坐标转换一致；`(38,38)` 映射世界原点。
- 计算稳定 map hash：hash 覆盖世界配置、seed、49 槽 assignment / rotation（含本局意识核角落）与模块 schema v1 等价的 gameplay projection；地形、派生通道、摆放、格尺寸或锚点变化会让旧 run fail closed，视觉层和图块目录不进入 hash。保存模块级迷雾 / 访问状态与按世界槽位隔离的动态状态。
- 常态只激活玩家当前模块周围最多 3×3 个 `ModuleChunk`；另为最多三个后台世界事件固定模块预留容量，manager 场景共预置 12 个 chunk 并循环复用，不创建 49 个槽位节点。
- 在运行开始和 run 恢复时，按 assignment 的唯一 module id 预加载每个模块的规范朝向 `PackedScene`；跨模块只替换离开 / 进入边缘的最多三块，不在边界读取磁盘。
- 从旋转 / 封边后的完整 49 槽地形构建 77×77 walkability mask；玩家跨格时只更新感知范围驱动的局部共享流场，并提供全图 AStar、视线和敌人半径走廊查询。导航不依赖当前激活 chunk。
- 按世界槽位返回稳定行列顺序的有效空 floor 格心：使用旋转、邻接与外圈封边后的真实地形，并排除全部 gameplay placement footprint；`module_place_teleporter` 的中心格同样是 protected footprint，不参与敌人、机关或奖励出生点。

`ModuleWorldLayout` 是 Manager 内部组合的纯 `RefCounted` 静态布局边界：它拥有 world / registry / template 的只读副本、run seed、assignment 与已提交 map hash，并集中坐标转换、旋转 / footprint、邻接 socket、全图 floor flood-fill、外圈 / sealed mask、placement / 空地查询、seeded / fallback / technical assignment 及稳定 hash。它不读取 Node、autoload、文件或 `user://`；Manager 通过显式 typed `RandomPort` 注入 `RNG.world`。生成顺序固定为 fixed start → objective → constrained teleporter → world events → ordinary；受约束组先为全部 job 确定性打乱候选，在临时 assignment 上回溯，三座全部合法后才一次 merge 到 live assignment；无解不得留下部分站点。Run 恢复先生成不污染 live assignment / seed / hash 的 layout `RestoreCandidate`，场景候选与 hash 均通过后才提交。

`ModuleWorldState` 是 Manager 内部组合的纯 `RefCounted` 动态状态边界：它拥有 current / revealed / visited、最多三个 pins 与按槽 payload，并组合 `ModuleSlotStateCodec` 处理 7×7 合法坐标、`"x" / "y"` wire、`"x,y"` slot key、row-major 序列化、strict pins 校验和深拷贝。进入模块先原子提交 visit 状态再刷新流式；离开世界仍由 Manager 先按旧 pins 刷新，再把 current 置为无效。恢复先生成不污染 live state 的 `RestoreCandidate`：pins 重复 / 越界 / 超限会拒绝，revealed / visited / slot payload 继续 fail-soft；只有 layout assignment、场景候选与 map hash 全部通过后才整体提交。

`ModuleChunkStreamingController` 是另一条纯 `RefCounted` 边界：它只持有规范生成场景路径 / 已提交缓存、12 个 scene-authored `ModuleChunk` 的池和当前挂载映射，负责候选场景预加载、提交及 3×3 + pins 的卸载 / 挂载。Manager 仍独占场景候选提交、导航、pin 的 configured / assignment 资格检查和 Run v20 模块子快照顶层显式组装；`ModuleWorldLayout`、`ModuleWorldState`、`ModuleSlotStateCodec` 与 `ModuleChunkStreamingController` 都不是 Node、autoload 或新的 gameplay facade。

`GameplayRunLoop` 仍负责敌人 / 机关 / 金币 / 局内 Gear Mod / `completes_run` 目标 / 世界事件 primitive 的实体生成、首次进入遭遇计划、效果 Runtime、预警、内容可用池过滤、`DifficultyProgression`、敌人生成时金币锁定、`Combat`、`PoolManager` 和 Run v20 总快照。它也从全局 placements 建立传送台索引，仅为活动模块实例化交互表现，并从整张 assignment 的 placements 组装开局可见的 HUD 交互地标；战斗门禁、visited-only 选择 UI、传送事务、Replay / Analytics 和 UI 恢复点仍归 RunLoop。`ModuleWorldManager` 不直接生成玩法实体或解释小地图图标，只提供严格同向 7×7 坐标 / 空地查询、组合事件 / 传送模块并维护 pin。

## 2. 数据边界

| 代码位置 | 责任 |
|----------|------|
| `client/scripts/gameplay/module_world_manager.gd` | `Node2D` 公共 facade、RNG port、场景候选提交、导航 / 流式和 Run v20 模块快照编排 |
| `client/scripts/gameplay/module_world_layout.gd` | 纯 assignment / 坐标 / 旋转 / footprint / 邻接 / 地形 / mask / flood-fill / map hash 与事务式 restore candidate |
| `client/scripts/gameplay/module_world_state.gd` | current / revealed / visited / pins / slot payload、进入 / 离开语义与事务式恢复候选 |
| `client/scripts/gameplay/module_slot_state_codec.gd` | 坐标 wire、row-major 集合、pins 验证及 typed `SlotState` 深拷贝 store |
| `client/scripts/gameplay/module_chunk_streaming_controller.gd` | 生成场景候选缓存、12 chunk 池与 active mapping；按 row-major 计算 3×3 + pins 的挂载变化 |
| `client/tests/unit/test_module_world_state.gd` | 进入 / 离开、pin 三态、row-major、恢复候选、深拷贝与 Run v20 模块 key order 的纯 GUT 覆盖 |
| `client/tests/unit/test_module_world_layout.gd` | RNG 调用与 assignment 插入顺序、precheck、fallback、restore / hash、坐标 / 旋转 / footprint / terrain 的纯 GUT 覆盖 |
| `client/tests/unit/test_module_slot_state_codec.gd` | Codec 未知字段、顺序、引用隔离和拒绝矩阵的纯 GUT 覆盖 |
| `client/tests/unit/test_module_chunk_streaming_controller.gd` | 候选 cache 事务、池容量、pin-only、卸载 / 复用顺序、部分失败及 Manager rebuild / restore 回滚的 GUT 覆盖 |

- 世界配置：`client/data/module_worlds.json`
- 模块注册表：`client/data/module_templates.json`
- 模块玩法内容：`client/data/modules/*.json`
- 模块视觉 / 碰撞生成物：`client/scenes/generated/modules/<id>/rotation_0.tscn`
- 人工 / AI 模板：`client/templates/module_template.json`
- 权威设计：F13 世界见 `F13-ModularGridWorld.md` / ADR #190；JSON 制作与单向烘焙见 ADR #154；F14 导航见 `F14-EnemyNavigationAndPerception.md` / ADR #145 / #146

当前 `module_worlds.json` schema v6 用 `objective_spawn` 声明 `module_objective_core` 与三个等概率候选角落，用 `teleporter_transition` 声明各 0.2 秒的淡出 / 淡入，并在 `limited_template_groups` 中以 `minimum_manhattan_distance=4`、`pick_distinct=1`、`count_per_floor=3` 配置 `module_teleporter_pad`。世界事件组的 minimum 为 0，继续从五个 approved 事件模板中等权无放回选三种。模块 JSON 为 schema v5；`module_teleporter_pad` 是 approved connector，仅允许 0°，中心 `(5,5)` 严格 placement 为 `{type,cell,network_id,interaction_radius}`，首个网络为 `teleporter_network_primary`，半径 180 px。fallback 使用 `(0,2)` / `(3,3)` / `(6,4)` 三座合法站点；如 fallback 也不能产生恰好三站，整局准备失败，不降级为少于三座。

运行时由纯 Layout 用 JSON 计算 assignment、placement、terrain 与 map hash，Manager 再据其结果构建导航并直接实例化预加载的生成 TSCN；不会从 JSON 构建 TileMap 或碰撞，也不连接 LLM。场景预加载使用候选 cache：只有 assignment、生成根 metadata 与 restore map hash 全部通过后才替换已提交 cache；显式 `build_*()` 重建会先清 active 与旧 cache，失败不得留下“空 / 半成品世界 + 旧场景缓存”。restore 失败则必须保留原 assignment、seed、hash、active coords、scene cache 与动态 state。新 AI 模块默认是 `module_review_candidate`；只有人工改为 `module_review_approved` 后才能进入默认池。

## 3. 公共 API

| API | 用途 |
|-----|------|
| `configure(world_def, registry_by_id, templates_by_id, generated_scene_paths_by_id, run_seed, navigation_flow_radius_cells)` | 设置世界、JSON / 规范生成场景映射、局部活动流场半径并生成默认 assignment；按 module id 预加载 assignment 使用的唯一场景，缺少模块生成物时拒绝配置 |
| `build_assignment()` / `build_fallback_assignment()` / `build_technical_slice_assignment()` | seed 组图与三角意识核选择、安全布局、中心 3×3 / 外圈 40 格技术首片 |
| `tick(player_position)` | 始终更新精确玩家导航目标；仅跨全局格时重算流场，同时更新当前模块、迷雾和 chunk 流式变更 |
| `world_to_global_cell()` / `global_cell_to_world()` | 世界坐标与 77×77 全局格转换 |
| `global_cell_to_module_and_local()` / `module_local_to_global_cell()` | 全局格与模块 + 局部格转换 |
| `is_world_position_walkable()` | 判断世界位置是否落在有效 `module_cell_floor`；模块敌人生成 / 恢复门禁复用此入口 |
| `empty_floor_positions_at(module_coord)` | 返回旋转 / 封边后仍为 floor 且不属于任何 gameplay placement footprint 的格心；按行列稳定排序，只读且不检查动态占位 |
| `is_module_visited(module_coord)` | 只读查询指定模块是否已首次进入；传送台发现 / 目标候选复用该语义，不单独存一份解锁表 |
| `navigation_query_to_active_target(from)` | 查询到精确玩家目标的可达性、世界像素路径距离和共享流场下一格中心；来源在活动窗口外时返回不可达 |
| `navigation_query(from, target)` | 在同一静态 mask 上查询守家 / 最后已知位置的 AStar waypoint；仅由 Enemy 决策 tick 调用 |
| `has_terrain_line_of_sight(from, target)` | 用封锁格 supercover 语义判断地形视线 |
| `has_clear_corridor(from, target, clearance)` | 将封锁格按敌人半径扩张后判断连续直线走廊 |
| `placements_at(module_coord)` | 返回已旋转、含 `world_position` 的内容摆放；RunLoop 可对整张 assignment 读取该结果并组装开局可见的 HUD marker payload，visited 只继续控制迷雾与传送发现状态 |
| `set_slot_pinned(module_coord, pinned)` / `pinned_module_coords()` | 固定最多三个事件模块，并把固定集合并入流式 desired set |
| `set_slot_state()` / `slot_state()` | 保存按世界槽位隔离的动态状态 |
| `snapshot()` / `restore_state()` | Run v20 中的 assignment（含目标角落与三站）、内容敏感 map hash、迷雾、固定模块和槽位状态 roundtrip；恢复时事务式重建场景缓存，hash / assignment / 生成场景不一致时返回失败 |
| `debug_summary()` | 输出几何、assignment/hash、访问 / 活跃数、预加载场景数及导航目标格、局部半径 / 边界 / 本次访问格数、流场重建次数和可达格数 |

Manager 的 `set_slot_state()` / `slot_state()` / `snapshot()` / `restore_state()` 字典 API 在 Run v20 中仍保持九字段子 wire：Manager 继续以固定顺序显式写出 `world_id`、`run_seed`、`assignment`、`map_hash`、`current_module`、`revealed`、`visited`、`pinned_slots`、`slot_states`，不得把 Layout / State 的内部字段直接 merge 到顶层。assignment 与 `slot_states` 都按 `y → x` 的 row-major 顺序输出；Layout 内部 Dictionary 保留 seeded fixed source → objective → constrained teleporter → world events → ordinary row-major、fallback / technical source order。Typed `SlotState` 保存完整原 payload；写入、读取、restore candidate、commit 与 snapshot 边界均深拷贝。

Pins 仍最多三个：公共 `set_slot_pinned()` 保留 configured / assignment 资格检查和 chunk 刷新，`ModuleWorldState.mutate_pin()` 只返回 `REJECTED`、`ACCEPTED_NO_REFRESH` 或 `ACCEPTED_REFRESH`，从而保持重复 pin 不刷新、unpin 即使原本不存在也刷新这一旧语义。Run 恢复顺序固定为：校验 configured / world → 准备动态状态候选 → 准备 layout assignment / seed 候选 → 准备生成场景 → 校验候选 hash → 提交场景 cache → 清 active → 原子提交 layout assignment / seed / hash → 重建导航 → 原子提交动态状态 → 按 current 或 pins-only 刷新。场景 cache 提交前任一步失败，都必须保留原 assignment、seed、hash、active/cache 与全部动态状态；显式 `build_*()` 仍是破坏式 rebuild，不在本切片事务化。

## 4. ModuleNavigationField

`ModuleNavigationField` 是 `RefCounted` 内部数据对象，不创建格子 Node：

- 共享目标使用确定性八方向 Dijkstra；活动窗口半径由 `ceil(max_sight_radius / cell_size) + 2` 推导，当前为 8 格、最多 289 格。对角步仅在两个相邻正交格都可走时开放，固定邻居顺序并用全局格索引处理同成本路线。
- 每次重建只清理上一次实际触达的格索引；最小堆使用距离与格索引的并行数值数组，不产生逐节点 `Dictionary`。完整 77×77 距离 / next 数组只在配置时初始化。
- 路径距离使用世界像素，并加上敌人 / 玩家精确位置到各自格心的端点距离。
- 非玩家目标复用 `AStarGrid2D`，`DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES` 禁止斜穿墙角。
- assignment 生成、技术首片构建和 run 恢复成功后重建 mask；越界或封锁目标统一返回 `reachable=false`。
- 流场、AStar 和感知查询都是派生临时状态，不改变 map hash，也不写入 Run v20。刷怪笼锁定的 enemy / position / module_coord 属于 GameplayEffectRuntime action state，而非 Manager assignment。
- 棋盘 placement `(x,y)` 与模块槽坐标一一对应，禁止旋转或镜像。刷怪笼候选空地必须排除玩家、敌人、机关、拾取物、部署物、兴趣点与世界事件占位；执行时若被动态占用则保留同一计划重试，不额外消费 `RNG.spawn`，离开模块才清空。

## 5. ModuleChunk

`ModuleChunk` 是 12 个预置流式槽位共用的薄场景：九个覆盖玩家 3×3 邻域，三个为持续事件或其残敌模块提供后台固定容量。`ModuleChunkStreamingController` 先卸载全部离开 desired set 的 chunk，再按全局 `y → x` 顺序挂载当前 3×3 与 pins 的并集；池取得或单个 `configure()` 失败不回滚本轮已成功挂载项。激活时挂载一个已提交 cache 中的规范朝向 `PackedScene`；生成实例已经包含 Ground / Obstacles / Decoration 三个 `TileMapLayer`、合并后的基础碰撞和四个边缘封锁视觉 / 碰撞子树。Chunk 只对生成根节点应用正交旋转与 1600 px 方形枢轴补偿，并把世界封边方向反映射到规范方向后切换对应子树。它不解析 JSON 建 TileMap、不创建碰撞节点、不扫描 121 格、不重算碰撞，也不应用 `TileMapPattern`。

生成场景的 `TerrainCollision` 显式位于物理层 bit 1、mask 为 0；玩家和敌人都必须保留 `CollisionShape2D`，否则 `CharacterBody2D` 不会与这些边界发生碰撞。敌人的碰撞层不与玩家或其他敌人物理互顶，只用 mask 命中模块地形；原有中心分离继续负责实体间距。`Bullet` 也只查询 bit 1：默认以 `hit_radius` 圆形做首帧重叠和逐帧扫掠，命中后通过 `PoolManager` 回收；`wall_pierce_enabled=true` 时才忽略地形。bit 1 是 ModuleChunk 与 Bullet 的稳定内部契约，不应用玩家、敌人、机关 Area 或伤害目标复用该查询语义。`ModuleWorldManager` 使用显式 `z_index=-90`，使模块地形位于 `WorldBackground(-100)` / `MapManager(-95)` 之上，同时稳定处于玩家、敌人、机关和目标实体之下；不能依赖场景树加入顺序决定遮挡关系。禁止为 121 个格逐格创建 Node，也禁止同时实例化 49 个 chunk。

## 6. 验证

```powershell
python tools/sync_contracts.py --check
python tools/validate_data.py
python tools/test_data_loader_schema.py
python tools/godot_bridge.py --project client gut --test-dir unit
python tools/godot_bridge.py --project client headless-boot
python tools/godot_bridge.py --project client module-world-smoke
python tools/godot_bridge.py --project client module-world-technical-slice-smoke
python tools/godot_bridge.py --project client teleporter-smoke
python tools/godot_bridge.py --project client save-smoke
```

性能测试不属于本模块的默认验证义务；只有用户当次明确要求时，才追加 `python tools/godot_bridge.py --project client startup-probe` 或 `perf-probe`。

`module-world-smoke` 覆盖同 seed assignment / 内容敏感 hash、三个意识核候选角、恰好三种事件与三座传送台、传送台两两距离 ≥4、受约束回溯 / fallback、49 槽 / 77×77 坐标、流式恢复、迷雾、意识核直接完成与 Run v20 子快照。`teleporter-smoke` 专项覆盖 HUD 开局显示全部三站、目的地列表 visited-only、交互战斗门禁、选择 / 取消 / 暂停叠加、全黑帧事务、危险目标恢复、Run v20 选择态与 Replay v10 语义决策。旧 Run v19 保持源文件但不继续。ADR #195 后 `module-world-technical-slice-smoke` 仍是 full 的伴随验证，需要技术首片证据时必须先有同轮 full PASS。

`test_module_slot_state_codec.gd` 专项 unit 必须覆盖：原 payload 与未知嵌套字段无损、输入 / getter / 输出深拷贝、slot state 的 row-major roundtrip、非法 slot / 非字典值隔离、坐标 wire 兼容以及 pins 的重复 / 越界 / 超限拒绝。

`test_module_world_state.gd` 专项 unit 必须覆盖：首次 / 重复 / 跨槽进入与 outside leave、current / revealed / visited 的稳定语义、row-major state wire、pin 三态与上限、strict pins 候选拒绝不污染 live state、revealed / visited / slot 的 fail-soft 恢复、未知 payload 与候选深拷贝，以及 Manager 显式 Run v20 模块 key 顺序。

`test_module_world_layout.gd` 专项 unit 必须覆盖：fixed / pool precheck 前不碰 RNG；seeded 的 objective → constrained teleporter → world events → ordinary → restore 调用 / assignment 顺序；恰好三站、两两距离、候选打乱确定性、临时 assignment 回溯成功后才整体提交、无解失败不污染 live assignment；fallback 三站合法；坐标、旋转、footprint、masked terrain、空地与内容敏感 map hash。

`test_module_chunk_streaming_controller.gd` 必须覆盖：候选 preload 失败不污染已提交 cache、metadata 拒绝、12 chunk 精确池、3×3 + pins / pins-only desired set、全局 row-major 挂载、先卸载后复用、池满与 mount 失败的部分成功语义、reconfigure 清 active，以及 Manager 显式 rebuild 失败清 active/cache/map、篡改 hash restore 保留原 assignment/hash/active/cache。测试中的预期拒绝不得向 Bridge GUT fatal-log 门禁泄漏 `push_error`。

修改 Layout、WorldState、Codec、StreamingController 或 Manager 委托时，四组专项 unit、`module-world-smoke` 和 `module-world-technical-slice-smoke` 均为必跑；technical 仍必须在同轮 full PASS 之后执行。

`module_resource_cache` 与 `module_crossroads` 因奖励从旧 dust 改为局内金币后 gameplay hash 变化，烘焙器已自动降为 `module_review_candidate`。AI 不得重新批准；在人工玩法复核前，它们不会进入正式 approved 池，技术切片临时使用 `module_flat_ground`。
