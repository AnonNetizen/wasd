# ADR #183 双涡旋史莱姆黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #183 正式玩家半径、双涡旋表现与 primary-only 碎片配色接入后的 Replay v3 捕获审计；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

- 测试日期：2026-08-05（Asia/Hong_Kong）
- 捕获前基线提交：`b7416ca1`
- 数据指纹：`7759e7e5ff6a6a2bf9126c5f9431777a2b192a70ddcd8167c45ec084e03fff69`
- Replay file / recording schema：v3 / v3
- Run seed：`20260619`
- 模块 map hash：`da44e2109c9dc3cb2868ec8367900a2570692ee4c36574e34305a50216a5c76a`

## 结论

四个场景均已重新捕获并逐条使用 `replay-runner --rerun-runtime-summary` 通过。`golden_basic_run` 与 `golden_pause_resume` 首次捕获即与现有文本逐字一致；`golden_full_death` 与 `golden_reward_choice` 的重复捕获只在 decision event 的 wall-time / 临界 tick 及其派生 `recording_hash` 上出现互不一致的抖动，没有任何 gameplay summary、frame sample、data fingerprint、模块 map hash、RNG 结果、玩家位置 / 生命、敌人、弹药、金币、奖励或状态字段变化。

因为同一代码连续捕获仍得到不同的毫秒值，该差异不是 ADR #183 的稳定行为变化。按“若摘要无差异则保留无差异结果”的验收口径，最终保留四条既有黄金文本，不把偶发捕获时序写成新基线；工作树中的四个 replay 文件最终均与 `b7416ca1` 完全一致。

`characters.json` schema v4 与颜色值、`player.json.body.radius`、玩家枪口距离都不进入当前 data fingerprint 投影，因此指纹保持 `7759e7…ff69`。这是对实际算法输出的审计结论，不是预设。软体状态本身不序列化、不消耗 RNG，也不进入 Replay v3 gameplay summary。

## 结果

| 回放 | 结果 | 摘要审计 |
|------|------|----------|
| `golden_basic_run.replay` | 通过；文本不变 | tick 180；移动、模块 hash、弹药 / 池统计与既有基线一致 |
| `golden_pause_resume.replay` | 通过；文本不变 | 暂停 / 恢复、GameClock、UI 栈与既有基线一致 |
| `golden_full_death.replay` | 通过；保留既有文本 | 死亡、Run 清理、Meta 保留与 frame samples 一致；仅捕获 wall-time / 临界 tick 抖动 |
| `golden_reward_choice.replay` | 通过；保留既有文本 | 奖励候选 / 选择、恢复游玩与 frame samples 一致；仅捕获 wall-time 抖动 |

Godot 退出时仍打印项目既有 RID / ObjectDB / resource leak 诊断；四条最终 replay runner 命令退出码均为 0。本任务按 ADR #143 不运行性能 probe。正式游戏内双涡旋辨识度、玩家与 12 px 子弹区分及形变手感仍属于 ADR #174 的用户人工验收边界，AI 未执行或代替。

## 使用命令

```powershell
python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario <scenario>
python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/<scenario>.replay --rerun-runtime-summary
```

其中 `<scenario>` 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_reward_choice`。
