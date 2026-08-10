# F13 — 7×7 模块 Roguelike 世界

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是模块 Roguelike 世界工作包；改动时同步 GDD、ADR、Module World / Gameplay / Save 文档、数据手册、测试策略与 AI 记忆。

> ADR #142 / #154 / #164 / #166 / #173 / #188 / #190 / #193 / #194 / #196 的当前阶段工作包。模块世界 schema、确定性目标角落、直接通关语义、Gear Mod v6 棋盘 / 当前模块程序、GameplayEffectRuntime 和 Run v19 必须同步 GDD、代码文档、测试策略、数据手册、知识索引与 AI 记忆。

## 目标

- 正式标准模式使用 7×7、每模块 11×11 格的连续模块世界。
- 起点固定在左下 `(0,6)`，使用西 / 南封闭、北 / 东居中开口的 `module_start_corner`；意识核按 run seed 等概率位于左上、右上或右下。
- 每局从五种世界事件模板中等权无放回选择三种，各放一次；其余普通槽使用 approved 模板池。
- 完成 `completes_run` 意识核目标后立即结束，不生成撤离点、读条或后半段路线。

## Schema v5

`module_worlds.json` 已删除：

- `extraction_slot`
- `objective_to_extraction`
- 撤离 role / placement
- 相关路线校验与 metadata

固定槽只包含起点；`objective_spawn` 声明 `module_objective_core` 与三个等概率候选角落。选中目标写入 assignment / map hash / Run 快照，小地图显示当前位置、迷雾与本局意识核方向。

## 运行时边界

- `ModuleWorldManager` 负责 49 槽 assignment、内容敏感 map hash、77×77 walkability、3×3 流式邻域、最多三个事件 pin 与槽位状态。
- `GameplayRunLoop` 负责首次遭遇、敌人 / 机关 / 事件、局内金币、Gear Mod v6 棋盘 / components / 带 ID 地面物、目标完成和 Run v19 总快照。
- 恢复顺序保持 mod environment → assignment / hash → 世界事件 → 棋盘 / 带 ID 地面物 → 敌人 / 子弹 → modifier components 分层应用 → 注册来源并恢复 GameplayEffectRuntime 状态。
- fallback 先覆盖完整 49 格，再以同一确定性目标选择覆盖候选角；技术切片平移到中心 3×3 / 外圈 40 格封锁。两者同样只能以 `completes_run` 目标直接结束。

## 模块审核状态

奖励从旧 dust 改为局内金币后，`module_resource_cache` 与 `module_crossroads` 的 gameplay hash 改变，烘焙器已按规则自动降为 `module_review_candidate`。AI 不得自行重新批准；技术切片 assignment 暂用 `module_flat_ground`。两模块必须由人工玩法复核后才能回到正式 approved 池。`module_start_corner` 已按用户要求完成 Bake，并由用户人工确认西 / 南封闭、北 / 东居中出口和中心出生后批准。

## 验证

- contracts、数据 / schema、module bake / check、module JSON editor。
- `module-world-smoke` 与 `module-world-technical-slice-smoke` 覆盖 49 个唯一槽位、77×77 导航、左下起点、三个确定性目标候选、6–12 次跨越、fallback、中心 3×3 / 外圈 40 格技术首片、迷雾、意识核直接完成、刷怪笼当前模块周期 program、Run v19 / 效果快照 roundtrip 与 hash mismatch。
- `world-event-smoke`、`save-smoke`、`loading-smoke`、`runtime-smoke`、headless boot/editor。
- Replay v9 四条黄金回放重录与运行时回归；旧 Run v18 / Replay v8 保留原文件但拒绝继续 / 播放，不迁移。

性能 probe 不属于默认验证。人工项包括出生房视觉、左下小地图方向、三个目标角覆盖、续局目标稳定与 6 / 12 次跨越路线手感，均保持待人工验收。
