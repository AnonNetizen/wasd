# F13 — 9×9 模块 Roguelike 世界

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是模块 Roguelike 世界工作包；改动时同步 GDD、ADR、Module World / Gameplay / Save 文档、数据手册、测试策略与 AI 记忆。

> ADR #142 / #154 / #164 / #166 / #173 / #188 的当前阶段工作包。模块世界 schema、直接通关语义和 Run v13 必须同步 GDD、代码文档、测试策略、数据手册、知识索引与 AI 记忆。

## 目标

- 正式标准模式使用 9×9、每模块 11×11 格的连续模块世界。
- 中心为起点；意识核维持当前约四次模块跨越的位置。
- 每局从五种世界事件模板中等权无放回选择三种，各放一次；其余普通槽使用 approved 模板池。
- 完成 `completes_run` 意识核目标后立即结束，不生成撤离点、读条或后半段路线。

## Schema v4

`module_worlds.json` 已删除：

- `extraction_slot`
- `objective_to_extraction`
- 撤离 role / placement
- 相关路线校验与 metadata

固定骨架只包含起点和意识核目标。小地图只显示当前位置、迷雾与意识核方向。

## 运行时边界

- `ModuleWorldManager` 负责 assignment、内容敏感 map hash、99×99 walkability、3×3 流式邻域、最多三个事件 pin 与槽位状态。
- `GameplayRunLoop` 负责首次遭遇、敌人 / 机关 / 事件、局内金币与 Gear Mod、目标完成和 Run v13 总快照。
- 恢复顺序保持 assignment / hash → 世界事件 → 敌人 / 子弹 → 局内 Gear Mod 替换应用。
- 技术切片与 fallback 同样只能以 `completes_run` 目标直接结束。

## 模块审核状态

奖励从旧 dust 改为局内金币后，`module_resource_cache` 与 `module_crossroads` 的 gameplay hash 改变，烘焙器已按规则自动降为 `module_review_candidate`。AI 不得自行重新批准；技术切片 assignment 暂用 `module_flat_ground`。两模块必须由人工玩法复核后才能回到正式 approved 池。

## 验证

- contracts、数据 / schema、module bake / check、module JSON editor。
- `module-world-smoke` 与 `module-world-technical-slice-smoke` 覆盖无撤离 assignment、约四次跨越、迷雾、意识核直接完成、Run v13 roundtrip 与 hash mismatch。
- `world-event-smoke`、`save-smoke`、`loading-smoke`、`runtime-smoke`、headless boot/editor。
- Replay v5 四条黄金回放。

性能 probe 不属于默认验证。人工项包括候选模块复核与意识核立即通关节奏。
