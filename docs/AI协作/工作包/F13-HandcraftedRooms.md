# F13 Handcrafted Rooms 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是手工房间制短刷图与房间编辑工作流的阶段工作包；改默认关卡承载形态、房间数据 schema、门 / 清房 / 切房流程、房间校验或验收命令时，必须同步 GDD、ADR、`docs/AI导航.md`、`docs/代码/gameplay_runtime.md`、测试策略、知识库索引与 AI 记忆。

## 1. 目标

F13 将默认短刷图的关卡承载从 F12 的开放有限战区首片，转向更接近《Enter the Gungeon》的手工房间串联。

核心目标不是先做复杂迷宫或完整地图节点，而是先获得可打磨的房间节奏：

```text
进房间 -> 门锁住 -> 清敌 / 躲陷阱 -> 房间完成 -> 出口开门 -> 进入下一个房间
```

手工房间让玩家目标更清楚，也让关卡作者可以精确控制敌人、陷阱、门和奖励节奏。F12 的 Gear Mod、`run.pending_loot`、死亡 / 放弃丢失和撤离 / 完成后结算规则继续保留；变化的是“战斗发生在一个个房间里”，而不是在一张开放有限地图上找兴趣点。

## 2. 设计结论

- **默认下一阶段采用手工房间串联**：标准模式优先验证房间制短刷图，不再继续把开放有限大地图 PCG 作为默认内容打磨主轴。
- **首版连接保持线性**：房间之间暂时按 `room_sequences.json` 的顺序前进；后续再扩展分支、钥匙门、商店、Boss 房、随机房间池或地图节点。
- **编辑器首版不自研完整 UI**：先把 Godot 场景编辑器当房间编辑器用，用可视化 marker 节点摆放门、陷阱和敌人生成点，再配校验 / 预览工具；真正的 `EditorPlugin` 面板等首片稳定后再做。
- **房间内容以手工摆放为主**：房间内敌人生成点、门、陷阱和玩家入口由房间 `.tscn` marker 指定；不要在 F13 首片继续用 PCG 撒房间内容。
- **清房推进是首片完成条件**：房间进入后出口门锁住，房间内敌人清空后出口打开，玩家触碰出口切到下一房间。
- **刷宝结算规则不变**：Gear Mod / dust 仍先进入 `run.pending_loot`；死亡、重开、回标题或主动放弃不带回；成功完成目标或后续撤离才写入 `meta.gear_mods`。

## 3. 房间结构

每个手工房间先用一个 Godot `.tscn` 表达，房间根节点负责声明边界和默认格尺寸，子节点使用 marker 表达可编辑内容。

建议首批 marker：

| Marker | 用途 | 首片字段 |
|--------|------|----------|
| `RoomPlayerStartMarker` | 玩家进入房间后的出生点 | `entry_id` |
| `RoomDoorMarker` | 门 / 出入口 | `door_id`、`target_entry_id`、`direction`、`unlock_rule` |
| `RoomEnemySpawnMarker` | 敌人生成点 | `enemy_id` 或 `enemy_group_id`、`count`、`delay`、`trigger` |
| `RoomHazardMarker` | 陷阱 / 机关摆点 | `hazard_id`、`enabled_at_start` |
| `RoomBoundsMarker` 或房间根配置 | 房间边界 | `bounds`、`grid.cell_width`、`grid.cell_height` |

后续可扩展但首片不做：

- `RoomRewardMarker`：固定奖励 / 宝箱 / 掉落点。
- `RoomObjectiveMarker`：小巢核、精英巢点、开关、护送点等目标。
- `RoomCoverMarker`：掩体 / 障碍 / 可破坏物。
- `RoomCameraZoneMarker`：若未来不再强制玩家居中，可用于特殊房间镜头；当前不做。

## 4. 数据入口

首片建议新增两类数据文件：

| 文件 | 作用 |
|------|------|
| `client/data/rooms.json` | 房间注册表：`room_id`、`scene_path`、`tags`、`clear_condition`、`allowed_modes`、可选推荐难度 / 主题 |
| `client/data/room_sequences.json` | 线性房间序列：`sequence_id`、`room_ids[]`、`final_room_id`、后续可扩展分支图 |

房间内的具体坐标优先保留在 `.tscn` marker 中，不要求策划手写坐标 JSON。这样首版的“关卡编辑器”就是 Godot 场景编辑器 + 项目自定义 marker + 校验命令。

数据原则：

- `room_id`、`sequence_id` 后续若成为跨文件约定字符串，需要登记 `docs/词表与契约.md` 并生成常量。
- `hazard_id` 必须引用 `hazards.csv`。
- `enemy_id` 必须引用 `enemies.csv`。
- 房间 `bounds` 仍使用水平 / 垂直矩形俯视格，不恢复菱形 / 等距地图格。
- 房间内容不按 id 写特殊分支；门、清房、奖励和目标都应通过通用字段解释。

## 5. 系统入口

建议新增 `RoomManager`，让它成为房间制流程的协调点。首片尽量不要把所有房间逻辑塞进 `MapManager`。

| 系统 | F13 职责 |
|------|----------|
| `RoomManager` | 加载当前房间场景、读取 marker、锁 / 开门、判断清房、切换下一房间、输出 room debug summary |
| `MapManager` | 复用矩形边界、grid、clamp 和可见边界能力；房间模式下只管理当前房间 bounds，不再负责 PCG 撒内容 |
| `GameplayRunLoop` | 选择房间序列、接入 `RoomManager`、清理旧房间实体、保存 / 恢复当前房间状态 |
| `Spawner` | 开放地图时间波次在房间首片中退居次要；房间敌人优先由 `RoomEnemySpawnMarker` 驱动 |
| `HazardSystem` | 继续复用 `Hazard` / `PoolManager` / `Combat`；房间陷阱由 `RoomHazardMarker` 指定 |
| `WarzoneDirector` | 首片暂不负责房间内摆点；后续可演化为房间主题、房间池选择或房间序列修饰器，不读取玩家状态、不做隐藏 DDA |
| `SaveManager` | run payload 需要保存 `room_sequence_id`、`current_room_id`、房间索引、门状态、已清理 / 已生成状态、活动实体快照 |

## 6. 首片实施顺序

1. **确立设计与文档**：新增 ADR #127、本工作包、GDD / AI 导航 / 测试策略 / 知识库索引 / AI 记忆同步。
2. **建立房间 marker 场景 / 脚本**：先做纯编辑器可见、运行时可读取的 marker；不做复杂 UI 面板。
3. **新增房间数据 schema**：`rooms.json`、`room_sequences.json` 和 DataLoader / validate_data 校验。
4. **新增 `RoomManager` 首片**：加载一个房间场景，读取 bounds、出生点、门、敌人生成点和陷阱点。
5. **接入运行时切房间**：开局进入房间 1，清敌后开门，触碰出口进入房间 2。
6. **接入保存 / 恢复**：暂停保存后可回到当前房间、当前门状态和活动敌人 / 陷阱状态。
7. **补 smoke**：覆盖两房间切换、清房开门、陷阱生成、保存恢复。

## 7. 首片验收

最小可玩验收：

- 两个手工房间可以从数据序列加载。
- 每个房间有矩形边界、玩家入口、至少一个出口门。
- 第一个房间有 1 个敌人生成点。
- 第二个房间有 1 个敌人生成点 + 1 个陷阱点。
- 进入房间后出口门锁住。
- 房间内敌人清空后出口门打开。
- 玩家触碰出口后切到下一个房间。
- 暂停保存退出后能恢复当前房间、当前门状态和仍然活跃的敌人 / 陷阱。
- 死亡 / 放弃仍按现有 `pending_loot` 规则丢失未结算战利品。

必跑：

- `python tools/validate_data.py`
- `python tools/test_data_loader_schema.py`
- `python tools/lint_project_rules.py`
- `python tools/lint_gdscript_rules.py`
- `python tools/lint_semantic_rules.py`
- `python tools/godot_bridge.py --project client headless-boot`
- `python tools/godot_bridge.py --project client runtime-smoke`
- `python tools/godot_bridge.py --project client save-smoke`

新增房间校验工具后追加：

- 房间 scene 校验：门、入口、bounds、敌人 / 陷阱引用和 marker 越界检查。
- 两房间切换 smoke：清房开门、触碰出口、加载下一房间。

若房间切换改变稳定 runtime summary 或默认战斗节奏，再评估四条 checked-in golden replay 是否重录。

## 8. 暂不做

- 完整自研关卡编辑器 UI。
- 随机房间图、分支地图、钥匙门、商店房、Boss 房。
- 房间池权重、稀有房间、事件房。
- 多出口撤离和复杂小地图。
- 房间内 PCG 内容生成。
- WarzoneDirector 根据玩家表现动态调房间。
- 联机房间同步、服务器权威或多人大厅。

## 9. 需要后续补的文档

进入实现后，需要新增或更新：

- `docs/代码/room_manager.md`
- `docs/代码/map_manager.md`
- `docs/代码/gameplay_runtime.md`
- `client/data/README.md`
- `docs/测试策略.md`
- `docs/AI导航.md` 系统依赖图

如果新增 `rooms.json` / `room_sequences.json` schema、房间 marker 脚本、`RoomManager` 公共 API 或 run payload 字段，必须同步详细模块文档与 save / replay 测试义务。
