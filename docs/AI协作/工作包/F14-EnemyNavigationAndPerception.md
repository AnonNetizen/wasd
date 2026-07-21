# F14 敌人导航与感知工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是 ADR #145 / #146 的敌人共享流场寻路、混合感知与局部流场修正工作包；改静态导航 mask、流场 / AStar 查询、敌人感知 profile、最后已知位置、攻击视线门禁或验收命令时，必须同步 GDD、ADR、AI 导航、EnemyAI / ModuleWorldManager / Gameplay Runtime 文档、测试策略、数据手册、知识库索引与 AI 记忆。

## 1. 目标与依赖

- F14 是独立于 F13 的 EnemyAI 里程碑。F13 保持完成，只提供完整 99×99 地形、坐标、旋转封边后的 assignment 与封锁格数据。
- 敌人继续只把玩家作为战斗目标；敌方友伤护栏与无伤害中心分离沿用 ADR #144。
- 畅通时保持连续直追；受阻时使用共享流场绕路。感知按地形视线、路径距离、短期记忆分层。
- 开放战区没有模块导航提供者时保留直线兜底，不引入运行时 navmesh、`NavigationAgent2D` 或逐格 Node。

设计参考：Unreal AI Perception 的多感官 / 刺激分层、Splinter Cell: Blacklist 的感知与记忆建模分享，以及 Godot 4.7 的 2D 导航概念；本项目只吸收“当前感知 + 记忆 + 环境可达性”结构，不照搬视野锥、声音事件或 navmesh 运行时烘焙。

- <https://dev.epicgames.com/documentation/unreal-engine/ai-perception-in-unreal-engine?lang=en-US>
- <https://media.gdcvault.com/GDC2014/Presentations/Walsh_Martin_Modeling_AI_Perception.pdf>
- <https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_introduction_2d.html>

## 2. 共享导航

- `ModuleNavigationField` 从完整 assignment 构建 99×99 walkability mask；只有 `module_cell_blocked` 阻挡路径与视线。
- 玩家跨全局格时，以玩家格为终点运行确定性八方向 Dijkstra；活动流场只覆盖玩家格周围的 Chebyshev 有界窗口。`GameplayRunLoop` 从已加载 profile 取最大 `sight_radius`，按 `ceil(max_sight_radius / cell_size) + 2` 自动计算半径，当前 `ceil(860 / 160) + 2 = 8`，单次最多访问 17×17 = 289 格。
- 固定邻居顺序和全局格索引处理同成本路线，斜向移动要求两个正交格均可走；每次只清理上次实际触达索引，Dijkstra 堆使用并行距离 / 格索引数值数组，不为节点创建临时字典。
- 查询返回可达性、含端点偏移的世界像素路径距离、下一格中心和精确目标位置。玩家在同一格内移动只更新精确位置，不重算距离场。
- 活动窗口之外的 `navigation_query_to_active_target()` 返回不可达；`navigation_query()` 仍在完整 99×99 mask 上使用 AStar，供守家和最后已知位置长距离查询。
- 守家与最后已知位置在决策 tick 使用同一 mask 上的 `AStarGrid2D`；直线走廊畅通时直接移动。
- `ModuleWorldManager` 在组图、技术首片和恢复 assignment 后重建导航数据；导航与感知缓存均为派生状态，不进入 run v4。

## 3. 混合感知

`enemy_ai_profiles.json` schema v3 使用：

- `perception.sight_radius`：360° 地形视线畅通时的视觉半径。
- `perception.path_awareness_radius`：视线受阻但共享流场可达时的路径距离半径，必须不大于视觉半径。
- `perception.memory_duration`：丢失当前感知后，只追最后已知位置的时间。

固定顺序为：视线感知 → 路径感知 → 最后已知位置记忆 → 无感知。记忆期间不读取玩家实时位置，不能冲锋或射击；结束后普通敌人停止，守家敌人沿 AStar 路径返回出生点。

冲锋必须在当前感知、距离合法且敌人半径扩张后的走廊畅通时启动；远程攻击必须在射程内且当前具有地形视线时开火。环绕和远程保持距离在相邻可走格中按路径距离带与切向方向评分。

## 4. 已锁定边界

- 不增加视野锥、脚步声事件、怀疑度、巡逻或搜索动画。
- 机关、奖励和其他敌人不进入静态路径阻挡；通用 Bullet 墙体碰撞不属于 F14。
- 不恢复敌人种间猎食、逃跑、目标选择或互伤。
- run schema 保持 v4；恢复后在下一决策 tick 重新感知。
- 性能 probe 仅在用户当次明确要求时运行，本工作包验收不自动运行。
- 活动流场保持同步和确定性；不引入线程、异步路径结果或回放时序差异。

## 5. 验收

- contracts / data / schema 双端校验明确拒绝 schema v2、`sense_radius`、缺失 / 非法 perception、路径半径大于视觉半径和负记忆时间。
- `module-world-smoke` 覆盖确定性流场、真实模块绕障、路径距离大于直线、无斜穿墙角、封锁 / 越界不可达和技术首片外圈封闭；追加验证半径 8 / 289 格上限、连续跨 20 格不退化、同格不重建、活动窗口外不可达且同位置全图 AStar 仍可查询。
- `runtime-smoke` 覆盖直追、流场 waypoint、视线 / 路径感知、1.5 秒记忆、守家回位，以及冲锋 / 远程不穿墙；继续覆盖玩家唯一目标、友伤拒绝和中心分离。
- 运行 GDScript / project / semantic lint、headless boot、完整模块世界、技术首片、runtime、F9、L1、save 与四条黄金回放；不运行 `startup-probe`、`perf-probe` 或 Profiler。
