# 2026-07-23 ADR #154 黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #154 模块 JSON 制作与单向 TSCN 烘焙迁移的回归证据；若重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json` 与当日会话日志。

- 测试日期：2026-07-23
- 测试基线 commit：`924eda81`
- 当前数据指纹：`a4027b39870f721a0f116fc6e0487c5aac6379eb00d4148e997597697917ed80`
- golden 记录的数据指纹：`7f5d7456d7690eceeac8d514bd0201d5317b0dd2c7d34fb285284d8e67c7c1c7`
- 稳定模块 map hash：`63f49b0cee98050b07f0feb68722894713a784a4b7238242506d077add0a1083`
- 变更原因：16 个模块从 schema v1 迁为 schema v2 并新增视觉层、稳定 tile catalog 和生成 TSCN，因此全局数据指纹按预期变化；gameplay projection 刻意保持 schema v1 语义。
- 执行方式：不重录 checked-in golden；四个场景分别用 `replay-runner --rerun-runtime-summary --allow-data-fingerprint-mismatch` 重建真实 `GameplayRunLoop` 摘要并与原摘要比较。
- mismatch 许可边界：仅允许这次已解释的全局数据指纹变化，不忽略运行时摘要、稳定帧样本、事件、结束状态或模块 map hash 差异。

| 回放 | 重录 | 运行时重放 | 结果 |
|------|------|------------|------|
| `golden_basic_run.replay` | 否 | 通过 | PASS |
| `golden_pause_resume.replay` | 否 | 通过 | PASS |
| `golden_full_death.replay` | 否 | 通过 | PASS |
| `golden_level_up_choice.replay` | 否 | 通过 | PASS |

## 结论

四条 checked-in golden replay 均保留原文件并通过真实运行时摘要比较；模块 map hash 与迁移前一致。未发现 gameplay、导航、存档或回放摘要回归。

按 ADR #143 和用户本次要求，未运行 startup probe、performance probe 或 Profiler。
