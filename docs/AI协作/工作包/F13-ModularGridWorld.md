# F13 模块大地图工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是 ADR #142 的 9×9 模块连续大地图阶段工作包；改世界 / 模块 JSON schema、模块组合、流式激活、迷雾、目标撤离、run v4 或验收命令时，必须同步 GDD、ADR、AI 导航、模块文档、测试策略、数据手册、知识库索引与 AI 记忆。

## 1. 目标与边界

- 标准世界固定 9×9 模块，每模块 11×11 格；单格默认 160×160 px，整图 99×99 格。
- 模块边界无缝；模块只承担制作、组合、流式、存档与预算职责，不做进门切场景。
- 出生、核心目标和撤离属于固定骨架；普通槽位按 `RNG.world` 与 run seed 从 approved AI JSON 模板池组合。
- 单局完成核心后撤离，通常经过 8–12 个模块，可选探索最多约 14 个模块；不要求全图清理。
- 不接运行时 LLM；模块使用 Godot `.tscn` 作为可人工微调的布局 / 表现主源，经确定性 bake 生成 JSON/TRES，candidate 通过自动校验和显式人工批准后入池。

## 2. 数据结构

| 数据 | 职责 |
|------|------|
| `client/data/module_worlds.json` | 世界几何、关键槽、路线预算、正式模板池、fallback 与技术首片 assignment |
| `client/data/module_templates.json` | 模板注册、角色、路径、AI 来源、审核状态与允许旋转 |
| `client/data/modules/*.json` | 单个 11×11 模块的地形令牌、边缘 socket 和格子摆放 |
| `client/scenes/modules/*.tscn` | 11×11 模块的 Ground / Obstacles / Decoration / Placements 编辑主源 |
| `client/resources/modules/*.tres` | 每个允许旋转方向的 TileMapPattern、预计算碰撞和 source hash 运行时产物 |

模块正式角色为 start / connector / combat / resource / hazard / objective / extraction；sealed 仅用于未开放技术首片槽位。格子、摆放、边缘和审核状态必须来自词表 §15 生成常量。

## 3. 运行时职责

- `ModuleWorldManager`：按 seed 组图、fallback、坐标转换、map hash、当前 / 已揭示 / 已访问模块、3×3 活跃邻域、槽位状态与 snapshot / restore。
- `--module-world-technical-slice`：从第一天的完整 9×9 坐标 / 存档结构启动中心 3×3 技术首片，外圈 72 槽使用可解释封锁模块；普通启动已切到完整 9×9。
- `ModuleChunk`：复用正式场景显示当前活跃模块，应用预烘焙 pattern / shape；不得逐格创建 Node 或在激活时重建碰撞。
- `MapManager`：一次配置完整 15,840×15,840 世界边界与 160 px 网格；模块世界不调用旧 PCG / WarzoneDirector 摆点。
- `GameplayRunLoop`：解释模块 placement，继续通过 PoolManager、Combat、兴趣点奖励、pending_loot 与撤离管线生成和结算内容。
- `GameplayHud`：显示 9×9 模块级迷雾、当前位置、目标与撤离状态。

## 4. 分阶段门槛

1. **中心 3×3 技术首片**：完整 9×9 坐标 / 存档结构，外围 72 个 sealed；验证跨边界、active≤9、迷雾、目标撤离和续局。
2. **完整 9×9**：15 个 approved 模板、81 个可达槽、确定性 assignment / hash、全局 flood-fill 与 3 seed 手动试玩。
3. **默认切换**：标准模式改走模块世界，开放战区保留为非默认回归路径；删除旧 RoomManager、房间数据 / 场景 / smoke，run schema 升到 v4。

## 5. 验收

- `sync_contracts --check`、`validate_data`、`test_data_loader_schema`、GDScript / project / semantic lint 全过。
- `module-bake-check` 保证 16 个 authoring scene 与 JSON/TRES 同步，`module-bake-smoke` 覆盖尺寸、格子、marker、id、落墙、连通、旋转、过期与重新批准门禁。
- `module-world-smoke` 覆盖同 seed、不同 seed、跨模块、active≤9、迷雾、目标撤离与保存恢复。
- `headless-boot`、`runtime-smoke`、`save-smoke`、`f9-demo-smoke` 与四条黄金回放按默认行为变化更新并通过；`perf-probe` 的历史验收结果保留，但 ADR #143 后只在用户明确要求性能测试时运行。
- 性能沿用项目预算：首帧≤2 秒、p99≤20 ms、跨模块尖峰<33 ms、内存≤512 MB、敌人≤200、子弹≤500。

## 6. 暂不做

- 完整自研关卡编辑器 Dock、运行时 LLM、联网生成、自动批准候选。
- 模块镜像、非方形模块、模块自定义格尺寸、逐格运行时节点。
- 隐藏 DDA、根据玩家表现改图、多人网络同步。
