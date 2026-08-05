# ADR #184 枪口闪光删除回放回归

> **AI 修改说明**：本报告记录 ADR #184 完全删除正式枪口闪光后的 Replay v3 指纹更新与逐字段审计；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

- 日期：2026-08-05
- 对照提交：`62c4be8e feat(gameplay): integrate dual-vortex player slime`
- Replay schema：v3（未升级）
- 游戏版本：v1.10（未升级）
- 旧数据指纹：`7759e7e5ff6a6a2bf9126c5f9431777a2b192a70ddcd8167c45ec084e03fff69`
- 新数据指纹：`d95cd1ece6e4f5344f054d577dd619e27ec10c7c81630c7ea4a641c07ba08caa`

## 结果

| 回放 | 运行时重跑 | 逐字段审计 |
|------|------------|------------|
| `golden_basic_run` | 通过 | 仅 `data_fingerprint` 更新 |
| `golden_full_death` | 通过 | 仅 `data_fingerprint` 更新 |
| `golden_pause_resume` | 通过 | 仅 `data_fingerprint` 更新 |
| `golden_reward_choice` | 通过 | 仅 `data_fingerprint` 更新 |

四条回放均由正式 Godot 4.7.1 headless 运行时重新捕获并用 `--rerun-runtime-summary` 重跑。首次捕获的 `golden_full_death` / `golden_reward_choice` 出现既有的 wall-time / 临界 tick 与派生 `recording_hash` 抖动；这些字段与本次纯表现删除无因果关系，未作为新基线接受。最终 checked-in JSON 与 `62c4be8e` 对照，在移除顶层 `data_fingerprint` 后四条均语义完全相等。

## 结论

删除枪口闪光 catalog、玩家 / 突击枪手 profile 绑定和专用池契约会按设计改变数据指纹，但没有改变 gameplay summary、输入 / 决策事件、frame samples、地图 hash、RNG 可观察结果、Run v11 或 Replay v3 语义。回归结论：无玩法回归。

捕获退出时仍出现项目既有的 RID / ObjectDB / resource 泄漏诊断；命令本身均以 0 退出。本轮未运行 performance probe 或 startup probe。
