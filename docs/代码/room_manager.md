# RoomManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 F13 手工房间制短刷图运行时的代码契约权威；改房间数据 schema、marker 字段、门 / 清房 / 切房流程、carrier 选择、run payload 房间字段或房间 smoke 时，必须同步 `docs/AI协作/工作包/F13-HandcraftedRooms.md`、`docs/代码/gameplay_runtime.md`、`docs/代码/map_manager.md`、`docs/代码/save_manager.md`、`client/data/README.md`、`docs/词表与契约.md`、`docs/测试策略.md`、GDD 与 ADR #127 / #128。

## 职责

- 在房间 carrier 模式下，按 `room_sequences.json` 的线性序列加载房间。
- 实例化房间 `.tscn`，递归读取 `RoomRoot` / `RoomPlayerStartMarker` / `RoomDoorMarker` / `RoomEnemySpawnMarker` / `RoomHazardMarker` marker，向 `GameplayRunLoop` 返回入场信息（矩形 bounds layout、玩家入口、敌人 / 陷阱生成数据、门数据）。
- 持有门状态（按 `door_unlock_rule` 决定初始锁 / 开），按 `room_clear_condition` 判断清房，清房后解锁 `unlock_on_clear` 出口门。
- 每帧由 `GameplayRunLoop` 驱动 `tick(player_position)`：玩家进入已解锁出口门触发范围时，返回切房 / 完成意图。
- 维护当前房间敌人计数（由 `GameplayRunLoop` 在生成时 `notify_room_enemies_spawned`、击杀时 `notify_enemy_defeated`），用于清房判定。
- 提供房间运行时状态 `snapshot()` / `restore_state()`，供 run payload 保存与续局恢复。

## 非职责

- 不直接 `PoolManager.acquire` 敌人 / 机关，不直接走 `Combat`：对象池生成、伤害结算、击杀归因、战利品掉落仍由 `GameplayRunLoop` 负责。
- 不读取玩家生命 / DPS / 输入节奏等玩家表现，不做隐藏动态难度。
- 不管理 `MapManager` 几何配置（由 `GameplayRunLoop._configure_map_for_room` 用 RoomManager 返回的 bounds layout 调用 `MapManager.configure`）。
- 不播放 UI / 音频，不显示玩家可见文案（首片暂无房间 HUD）。
- 不负责 carrier 选择：是否进入房间 carrier 由 `GameplayRunLoop` 决定（首片 `debug_enable_room_carrier()` 或 run 存档中存在 `room` 块）。

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/room_manager.gd` | `RoomManager` 实现，`Node2D`，房间 carrier 模式下由 `GameplayRunLoop` 挂在 `ActiveWorld` 下并驱动 |
| `client/scripts/gameplay/rooms/room_root.gd` | `RoomRoot`：房间根脚本，`@export` 矩形 bounds / grid，`to_bounds_data()` |
| `client/scripts/gameplay/rooms/room_player_start_marker.gd` | `RoomPlayerStartMarker`：玩家入口，`entry_id` |
| `client/scripts/gameplay/rooms/room_door_marker.gd` | `RoomDoorMarker`：门，`door_id` / `target_entry_id` / `direction` / `unlock_rule` / `trigger_radius` |
| `client/scripts/gameplay/rooms/room_enemy_spawn_marker.gd` | `RoomEnemySpawnMarker`：敌人生成点，`enemy_id` / `count` / `delay` / `trigger` |
| `client/scripts/gameplay/rooms/room_hazard_marker.gd` | `RoomHazardMarker`：陷阱摆点，`hazard_id` / `enabled_at_start` |
| `client/scenes/gameplay/rooms/room_demo_entry.tscn` | 首片演示房间 1：1 敌人 + 出口门（dir_east / unlock_on_clear） |
| `client/scenes/gameplay/rooms/room_demo_arena.tscn` | 首片演示房间 2：1 敌人 + 1 陷阱 + 完成门 |
| `client/data/rooms.json` | 房间注册表 |
| `client/data/room_sequences.json` | 线性房间序列 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | carrier 选择、创建 / 驱动 RoomManager、对象池生成房间内容、清房计数回调、房间快照恢复 |
| `client/tools/room_switch_smoke.gd` | 房间切换 + 存档恢复 headless smoke |

## 场景 / 节点结构

房间 carrier 模式下的运行时节点树（在 `gameplay_run_loop.tscn` 既有结构上追加）：

```
GameplayRunLoop (Node2D)
└── ActiveWorld (Node2D)
    ├── MapManager        # 复用矩形 bounds / grid / clamp，房间模式不做 PCG
    ├── WorldBackground
    ├── Player
    └── RoomManager (Node2D, 运行时由 GameplayRunLoop 创建)
        └── <房间 .tscn 根 RoomRoot>   # 当前房间场景，切房时 queue_free 重建
            ├── PlayerStart (RoomPlayerStartMarker)
            ├── EnemySpawn1 (RoomEnemySpawnMarker)
            ├── Hazard1 (RoomHazardMarker)        # 仅 arena 房
            └── DoorExit / DoorComplete (RoomDoorMarker)
```

被池化的房间敌人 / 陷阱仍由 `PoolManager` 重新挂到 `ActiveWorld` 下（不在 RoomManager 子树内），与开放战区一致。

## 运行流程

**新局（fresh，房间 carrier）**：`GameplayRunLoop._start_run` 设置玩家 / 武器 / HUD 并切到 `PLAYING` 后，走 `_start_room_carrier_fresh()` → `_ensure_room_manager()` 创建 RoomManager → `configure(sequence, rooms_by_id)` → `_enter_room(0, "")`。`_enter_room` 调 `enter_room_index` 加载房间场景、读 marker，用返回的 bounds layout 重配 `MapManager`，把玩家放到 `MapManager.player_start()`（已吸附矩形格），再 `_spawn_room_content` 走对象池生成敌人 / 陷阱并 `notify_room_enemies_spawned`。

**每帧**：`GameplayRunLoop._process` 在 `PLAYING` 且房间 carrier 时只调 `_update_room` → `RoomManager.tick(player_position)`。`tick` 先判清房（`_is_clear_condition_met`：`room_clear_all_enemies` 看 `_enemy_alive <= 0`，`room_clear_none` 直接成立），清房则解锁 `unlock_on_clear` 门并发 `room_cleared`；再检查玩家是否进入某已解锁门 `trigger_radius`，是则返回 `{action:"switch", target_entry_id, is_final}` 并发 `exit_reached`。

**切房**：`GameplayRunLoop._handle_room_switch` 收到 switch 意图：`is_final` → `_complete_run`（提交 `run.pending_loot`、删存档、完成面板）；否则 `_clear_room_entities()`（释放当前房间所有池化实体）→ `_enter_room(next_index, target_entry_id)`。

**击杀计数**：房间敌人用 spawn_key `RoomManager.ROOM_SPAWN_KEY`（`"room"`）。`GameplayRunLoop._on_enemy_defeated` 在 wave_key 为该键时调 `RoomManager.notify_enemy_defeated()`，`_enemy_alive` 减一。

**存档 / 恢复**：`create_run_snapshot()` 的 `room` 字段来自 `RoomManager.snapshot()`（sequence_id / room_index / current_room_id / clear_condition / enemy_alive / enemy_spawned_total / cleared / door_states）。续局时 `_restore_run_snapshot` 检测到非空 `room` 块即把 `_room_carrier_enabled` 置真并 `_restore_room_carrier`：重建 RoomManager、`enter_room_index` 重建当前房间场景与门、`restore_state` 套用门状态与计数；活体敌人 / 陷阱仍由既有 `_restore_enemy_snapshots` / `_restore_hazard_snapshots` 从快照重建（RoomManager 不重新生成 marker 内容）。

## 公共 API

| 方法 | 签名 | 说明 |
|------|------|------|
| `configure` | `(sequence: Dictionary, rooms_by_id: Dictionary) -> void` | 注入序列与 `room_id -> room_data` 映射 |
| `enter_room_index` | `(index: int, entry_id := "") -> Dictionary` | 加载序列第 index 个房间场景、读 marker，返回入场信息；`entry_id` 选玩家入口；不生成池化实体 |
| `tick` | `(player_position: Vector2) -> Dictionary` | 每帧清房 / 开门 / 出口检测；返回 `{}` 或切房意图 |
| `notify_room_enemies_spawned` | `(count: int) -> void` | 生成房间敌人后告知计数 |
| `notify_enemy_defeated` | `() -> void` | 房间敌人被击败时减计数 |
| `snapshot` | `() -> Dictionary` | 房间运行时状态快照 |
| `restore_state` | `(state: Dictionary) -> void` | 在 `enter_room_index` 重建场景后套用门状态与计数 |
| `current_room_id` / `current_room_index` / `is_final_room` / `is_current_room_cleared` / `room_count` | | 只读查询 |
| `debug_doors` | `() -> Dictionary` | smoke / 调试：door_id -> {position, unlocked, target_entry_id} |

入场信息 Dictionary 字段：`room_id`、`clear_condition`、`bounds_layout`（喂 `MapManager.configure`）、`player_start`、`enemy_spawns[]`、`hazard_spawns[]`。

## Signal / Event

- `room_entered(room_id: String, room_index: int)`
- `room_cleared(room_id: String)`
- `exit_reached(target_entry_id: String, is_final: bool)`

首片 `GameplayRunLoop` 通过 `tick` 返回值驱动切房，未连接这些 signal；它们为后续 HUD「出口已开」反馈等预留。

## 数据与词表

- 房间数据：`rooms.json` / `room_sequences.json`，schema 见 `client/data/README.md`，校验见 `data_loader.gd` 与 `tools/validate_data.py`。
- 约定字符串：门 `direction` 走词表 §15-A（`door_directions.gd`），`unlock_rule` 走 §15-B（`door_unlock_rules.gd`），房间 `clear_condition` 走 §15-C（`room_clear_conditions.gd`），均以生成常量引用。
- `room_id` / `sequence_id` / `entry_id` 是开放数据键，不进词表，由 DataLoader 跨文件校验。
- marker 的 `enemy_id` / `hazard_id` 引用 `enemies.csv` / `hazards.csv`，在 `.tscn` 设置，由运行时 `_enemy_rows` / `_hazard_rows` 校验（未知 id fail-fast 跳过生成）。

## 依赖

- 上游：`GameplayRunLoop`（创建 / 驱动 / 生成 / 快照）、`MapManager`（几何）、`DataLoader`（数据加载）、生成契约常量。
- 下游：被 `GameplayRunLoop` 在房间 carrier 分支调用；不被业务脚本直接引用。
- 不依赖：`WarzoneDirector`（房间 carrier 下不创建导演）、开放地图 PCG。

## 扩展点

- 新房间 = 新 `.tscn`（Godot 场景编辑器摆 marker）+ `rooms.json` 一条 + 加入某 `room_sequences.json` 序列；不改逻辑。
- 新门解锁策略 / 清房条件 = 词表 §15-B / §15-C 登记新 id + 在 `RoomManager._is_clear_condition_met` / `_unlock_clear_doors` 实现原语；禁止按 `room_id` 写特殊分支。
- 新 marker 类型（奖励点 / 目标点 / 掩体）= 新 `Marker2D` 子类 + `_collect_markers_recursive` 识别 + `GameplayRunLoop` 消费。

## 常见改动入口

- 调房间内容（敌人 / 门 / 陷阱位置）→ 改对应房间 `.tscn` marker。
- 调房间串联 → 改 `room_sequences.json`。
- 改门 / 清房语义 → 词表 §15 + `RoomManager` 原语 + `data_loader.gd` / `validate_data.py`。
- 改房间存档字段 → `RoomManager.snapshot/restore_state` + `GameplayRunLoop` run payload + `SaveManager` 迁移。

## 故障排查

- 房间不切：确认敌人 spawn_key 为 `room`（否则 `notify_enemy_defeated` 不触发）、门 `unlock_rule` 为 `unlock_on_clear`、玩家进入 `trigger_radius`。
- 启动报 `failed to load room scene`：`rooms.json.scene_path` 路径或 `.tscn` 缺失（DataLoader 已校验存在性，运行时再校验）。
- 续局回到开放战区而非房间：run 存档 `room` 块为空（旧 v2 存档或非房间局）；房间局才写非空 `room`。

## 测试义务

- 改 RoomManager 公共 API / 切房 / 清房 / 门逻辑 → 跑 `room-switch-smoke`。
- 改 run payload 房间字段 / 迁移 → 跑 `save-smoke`（覆盖 v2→v3 room 回填）+ `room-switch-smoke` 存档恢复段。
- 改房间数据 schema → `validate_data.py`、`test_data_loader_schema.py`、`headless-boot`。
- 房间 carrier 为 opt-in，默认 open-warzone 路径不变；改动后 `runtime-smoke` / `f9-demo-smoke` 必须保持绿。
- 若改变默认战斗节奏或稳定 runtime summary → 评估四条 checked-in 黄金回放是否重录。

## 迁移 / 兼容说明

- run payload schema v2 → v3：新增 `room` 块；`SaveManager._migrate_run_v2_to_v3` 把旧 v2（开放战区）存档回填 `room = {}`，续局按「无房间 carrier」走开放战区路径。
- 新增词表 §15-A/B/C 与 rooms / room_sequences 的 schema_counts 改变了 `Replay` 的 `data_fingerprint`，四条黄金回放据此重录，行为 summary 未变。

## 相关 GDD / ADR

- ADR #127：默认短刷图下一阶段转向手工房间制（规划）。
- ADR #128：F13 手工房间制短刷图首片运行时落地（RoomManager + 房间 carrier + run v3）。
- 工作包：`docs/AI协作/工作包/F13-HandcraftedRooms.md`。
