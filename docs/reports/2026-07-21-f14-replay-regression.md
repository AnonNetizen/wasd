# 2026-07-21 F14 黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #145 / F14 交付时的回归证据；若重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json` 与当日会话日志。

- 测试日期：2026-07-21
- 测试基线 commit：`9eb51866`
- 数据指纹：`5a65b531e81e104b12532662f353a5d768307272b373690aab07d30f9911ca9b`
- 变更原因：ADR #145 新增共享流场、AStar waypoint 与视线 / 路径 / 记忆混合感知，并将 EnemyAI profile 升至 schema v3。
- 执行方式：四个场景分别通过 `capture-golden-replay` 重录，再由 `replay-runner --rerun-runtime-summary` 重建真实 `GameplayRunLoop` 摘要并比较。
- 指纹说明：现有 replay data fingerprint 由契约与 schema 计数组成；本轮 profile 数量与契约集合未变，因此指纹值保持不变，但四条场景仍按 F14 实现重新执行了 capture 与 runtime-summary 校验。

| 回放 | 重录 | 运行时重放 | 结果 |
|------|------|------------|------|
| `golden_basic_run.replay` | 通过 | 通过 | PASS |
| `golden_pause_resume.replay` | 通过 | 通过 | PASS |
| `golden_full_death.replay` | 通过 | 通过 | PASS |
| `golden_level_up_choice.replay` | 通过 | 通过 | PASS |

## 结论

四条 checked-in golden replay 均在相同 seed 下通过运行时摘要、模块地图 hash、稳定帧样本和场景语义比较。未发现非预期回归。

按 ADR #143 和用户本次要求，未运行性能测试。
