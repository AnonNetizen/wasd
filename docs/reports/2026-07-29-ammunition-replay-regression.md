# ADR #177 弹药与换弹黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #177 弹药、换弹、弹药掉落与默认键位改造的黄金回放重录证据；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

- 测试时间：2026-07-29 18:48:42 +08:00
- 测试基线提交：`faea67c0ec5876024560eba1567dcb6bedce8480`
- 数据指纹：`0a333078f758d69c5c048375c6901c75b189aba785db65dde98e26a82fe67bb4`
- Replay file / recording schema：v3 / v3
- Run seed：`20260619`
- 模块 map hash：`da44e2109c9dc3cb2868ec8367900a2570692ee4c36574e34305a50216a5c76a`

## 结论

四条黄金回放已按 ADR #177 的 `weapons.json` schema v4、输入绑定 schema v2、独立 `RNG.ammo` 与 Run v11 行为重录，并逐条使用 `replay-runner --rerun-runtime-summary` 通过。Replay 输入 wire format 保持 v3；旧 Run v10 由 SaveManager 明确拒绝，Meta v2 保留。

首次复跑发现录制器尚未把新增弹药字段写入 `run_summary`，而重跑器已输出这些字段，导致 `active_ammo_magazines=0` 被判为额外值。现已让 `golden_replay_capture.gd` 与 `replay_runner.gd` 同步记录弹匣、备弹、换弹、场上弹匣、未掉计数和弹匣池统计；重新录制后四条摘要逐字段一致。

## 结果

| 回放 | 状态 | 关键覆盖 |
|------|------|----------|
| `golden_basic_run.replay` | 通过 | 30 / 150 初始弹药、无换弹、弹匣池预热、模块 assignment / map hash |
| `golden_pause_resume.replay` | 通过 | 暂停 / 恢复、输入和 `GameClock` 冻结下的弹药摘要稳定 |
| `golden_full_death.replay` | 通过 | 死亡、弹药摘要、Run 清理与 Meta 保留 |
| `golden_reward_choice.replay` | 通过 | 奖励选择期间弹药状态稳定并恢复游玩 |

四条回放均在 tick 180 结束，summary 与重跑结果逐字段一致。实际 30 发消耗、手动 / 空匣换弹、零弹降级射击、拾取恢复、递增掉率归因边界、对象池失败不扣弹、Run v11 换弹中途与场上弹匣恢复，由 `ammo-weapon-smoke`、`runtime-smoke`、`l1-smoke` 与 `save-smoke` 单独覆盖。Godot 退出时仍打印项目既有 RID / ObjectDB / resource leak 诊断；四条最终复跑命令退出码均为 0。

提交前事实型 review 还修正了两处相邻回归：空弹匣但仍有备弹时，拾取弹药现在也会先直接装满弹匣；RNG 相关性审计已把新增 `ammo` 流纳入样本。最终未发现剩余 P0 / P1 / P2 问题。

本任务按 ADR #143 不运行性能 probe。人工手感、HUD 可读性、打空后二次按压、降级射击反馈和键鼠 / 真实手柄布局属于 ADR #174 的人工验收边界，AI 未执行或代替人工验收。

## 使用命令

```powershell
python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario <scenario>
python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/<scenario>.replay --rerun-runtime-summary
```

其中 `<scenario>` 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_reward_choice`。
