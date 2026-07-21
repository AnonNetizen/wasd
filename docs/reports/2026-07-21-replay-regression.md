# 2026-07-21 黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #144 交付时的只读回归证据；若同日重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json` 与当日会话日志。

- 测试日期：2026-07-21
- 测试基线 commit：`b9aef61e`
- 数据指纹：`5a65b531e81e104b12532662f353a5d768307272b373690aab07d30f9911ca9b`
- 变更原因：ADR #144 删除敌人种间交互生态，敌人 AI 与战区导演数据升至 schema v2；本次行为和数据指纹变化是有意变更。
- 执行方式：四个场景分别通过 `capture-golden-replay` 重录，再由 `replay-runner --rerun-runtime-summary` 重建真实 `GameplayRunLoop` 摘要并比较。

| 回放 | 重录 | 运行时重放 | 结果 |
|------|------|------------|------|
| `golden_basic_run.replay` | 通过 | 通过 | PASS |
| `golden_pause_resume.replay` | 通过 | 通过 | PASS |
| `golden_full_death.replay` | 通过 | 通过 | PASS |
| `golden_level_up_choice.replay` | 通过 | 通过 | PASS |

## 结论

四条 checked-in golden replay 均已更新到新数据指纹，并在相同 seed 下通过运行时摘要、模块地图 hash、稳定帧样本和场景语义比较。未发现非预期回归。

按 ADR #143 和用户本次要求，未运行性能测试。
