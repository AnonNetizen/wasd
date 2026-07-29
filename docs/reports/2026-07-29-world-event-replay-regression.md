# ADR #173 世界事件黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #173 世界事件系统的黄金回放重录证据；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

- 测试时间：2026-07-29 14:03:40 +08:00
- 测试基线提交：`776b174cef9f11bd885fa61432f40ecdd3b83d6a`
- 数据指纹：`a89fef2c131f09771747a8ff23f85c7cd049a68b678351fabcd6d5e07fef1f5c`
- Replay file / recording schema：v3 / v3
- Run seed：`20260619`
- 模块 map hash：`da44e2109c9dc3cb2868ec8367900a2570692ee4c36574e34305a50216a5c76a`

## 结论

四条黄金回放已按 ADR #173 的 `world_events.json` schema v1、模块世界 schema v3、模块 schema v4、独立 `RNG.world_event` 和 Run v9 行为重录，并逐条使用 `replay-runner --rerun-runtime-summary` 通过。Replay 输入 wire format 保持 v3；没有增加旧 Replay 或旧黄金基线兼容分支。

## 结果

| 回放 | 状态 | 关键覆盖 |
|------|------|----------|
| `golden_basic_run.replay` | 通过 | 当前数据指纹、世界 assignment / map hash 与基础流程 |
| `golden_pause_resume.replay` | 通过 | 暂停 / 恢复、输入和 `GameClock` 冻结 |
| `golden_full_death.replay` | 通过 | 死亡、Run 清理与 Meta 保留 |
| `golden_reward_choice.replay` | 通过 | 显式奖励选择决策与恢复游玩 |

四条回放均在 tick 180 结束，summary 与重跑结果逐字段一致。世界事件的五类规则、固定波次与隐藏奖励、后台 pin、事件敌人目标上下文、祭坛事务和 Run v9 中段恢复由 `world-event-smoke`、`module-world-smoke`、`runtime-smoke`、`save-smoke` 与 L1 单独覆盖。Godot 退出时仍打印项目既有 RID / ObjectDB / resource leak 诊断；四条命令退出码均为 0，未发现回放差异。

## 使用命令

```powershell
py -3 tools/godot_bridge.py capture-golden-replay --golden-scenario <scenario>
py -3 tools/godot_bridge.py replay-runner --replay-file client/tests/replays/<scenario>.replay --rerun-runtime-summary
```

其中 `<scenario>` 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_reward_choice`。
