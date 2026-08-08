# F12 — Roguelike 局内奖励与终局

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Roguelike 局内奖励与终局工作包；改动时同步 GDD、ADR、Gameplay / Warzone / Save 文档、数据手册、测试策略与 AI 记忆。

> 历史文件名保留以维持导航稳定。ADR #188 已取代“短刷宝行动、暂存战利品、撤离带回与局外整理”方案；当前正式定位为俯视角射击 Roguelike。

## 核心循环

```text
进入本局（空 Mod）
→ 战斗与探索
→ 敌人 / 缓存 / 世界事件获得局内金币与 Gear Mod
→ 手动拾取无等级 Mod 实例；重复 id 逐份乘算并立即生效
→ 清理意识核
→ 立即显示本局结果与最终构筑
→ 下一局重新空 Mod 开始
```

标准模式不使用刷宝撤离、搜打撤、战利品暂存或跨局带回逻辑，也不把局长作为自动验收门槛。内部 id `mode_standard_survival` 暂时保持稳定，仅更新玩家可见名称和说明。

## Open-warzone 回归路径

open-warzone 只作为保留的技术 / 回归载体，继续使用固定压力阶段和四个兴趣点：

| 兴趣点 | 当前奖励 / 结果 |
|---|---|
| 精英巢点 | 90 即时局内金币 |
| Mod 缓存 | 从公共普通 Mod 池独立抽取两次 |
| 资源缓存 | 60 即时局内金币 |
| 意识核 | `completes_run=true`，清理后立即完成，不携带额外奖励 payload |

缓存仍通过可见箱体和 `interact` action 打开；可伤害目标仍走 `Combat`。所有 Gear Mod 奖励都先生成池化 CPU 拾取实体，玩家再次执行 `interact` 成功后才调用 `GameplayRunLoop` 的单份原子授予入口；每次只追加一个 `mod_id`。

`warzone_directors.json` schema v3 已删除 `resource_rewards`、固定 `gear_mod_rewards`、撤离半径和撤离读条，改用 `gold_reward_amount`、`gear_mod_pool_id`、`gear_mod_rolls` 与 `completes_run`。

## 结果与存档

- 死亡与完成都会删除当前 run，清空局内 Mod。
- 结果页显示击杀、用时及最终 Gear Mod 构筑；同一 Mod ID 聚合数量，再以本地化名称显示，数量不代表等级；不显示带回 / 丢失清单。
- Run v17 保存兴趣点领取状态、可重复的局内 `mod_ids` 和未拾取 Mod；恢复不得重抽缓存、重复发奖或丢失重复实例。旧 Run v16 及更早版本只删除 Run，不转换等级数据。
- Meta v4 不保存任何 Gear Mod 实例、dust 或战利品。

## 验证

- 数据 / schema 同时拒绝旧跨局奖励与撤离字段。
- `runtime-smoke` 覆盖四个兴趣点、即时金币、Mod 缓存两次抽取、意识核直接完成与结果页。
- `gear-mod-smoke` 覆盖固定 damage ×1.20、recoil / spread ×0.80 和重复实例乘算；`gear-mod-pickup-smoke` 覆盖所有来源的手动拾取；`save-smoke` 覆盖恢复不重抽 / 不重复发奖。
- `replay-smoke` 与四条 Replay v7 黄金回放覆盖新结束语义、规范化 Gear Mod 玩法指纹和 `mod_ids` 结构；Replay v6 明确拒绝。当前游戏版本为 v1.16。
- 不运行性能 probe，不以局长作为门槛。

待人工验收：局内掉落 / 重复实例反馈、最终构筑结果页、中英文布局，以及意识核立即通关的实际节奏。
