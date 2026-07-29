# ADR #175 敌人金币公式黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #175 数据驱动敌人金币公式与难度接口的黄金回放重录证据；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

- 测试时间：2026-07-29 16:48:23 +08:00
- 测试基线提交：`a5d5d7235c66394630bf12082f8abb0060f87d7e`
- 数据指纹：`9d5bcfac5bee46ea07655d2daf1be101a09e0bd104cf394f2030f453b8eeb5f2`
- Replay file / recording schema：v3 / v3
- Run seed：`20260619`
- 模块 map hash：`da44e2109c9dc3cb2868ec8367900a2570692ee4c36574e34305a50216a5c76a`

## 结论

四条黄金回放已按 ADR #175 的 `enemy_rewards.json` schema v1、`difficulty_profiles.json` schema v2、独立 `RNG.economy` 和 Run v10 行为重录，并逐条使用 `replay-runner --rerun-runtime-summary` 通过。Replay 输入 wire format 保持 v3；旧 Run v9 由 SaveManager 明确拒绝，Meta v2 保留。

## 结果

| 回放 | 状态 | 关键覆盖 |
|------|------|----------|
| `golden_basic_run.replay` | 通过 | 当前数据指纹、标准难度 profile、模块 assignment / map hash 与基础流程 |
| `golden_pause_resume.replay` | 通过 | 暂停 / 恢复、输入和 `GameClock` 冻结 |
| `golden_full_death.replay` | 通过 | 死亡、Run 清理与 Meta 保留 |
| `golden_reward_choice.replay` | 通过 | 显式奖励选择决策与恢复游玩 |

四条回放均在 tick 180 结束，summary 与重跑结果逐字段一致。敌人生成时金币锁定、五种敌人的开局范围、跨阶段不重算、世界事件按实际生成阶段、奖励明细续局恢复和恢复不消费 `RNG.economy`，由 `l1-smoke`、`runtime-smoke`、`world-event-smoke`、`module-world-smoke` 与 `save-smoke` 单独覆盖。Godot 退出时仍打印项目既有 RID / ObjectDB / resource leak 诊断；四条命令退出码均为 0，未发现回放差异。

本任务按 ADR #143 不运行性能 probe。经济节奏体验属于 ADR #174 规定的人工验收边界，AI 未执行或代替人工验收。

## 使用命令

```powershell
python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario <scenario>
python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/<scenario>.replay --rerun-runtime-summary
```

其中 `<scenario>` 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_reward_choice`。
