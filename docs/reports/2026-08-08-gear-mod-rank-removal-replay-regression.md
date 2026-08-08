# ADR #193 删除 Gear Mod 等级回放回归报告

> **AI 修改说明**：本报告记录 ADR #193 将 Gear Mod 改为无等级独立实例、升级 Replay v7 后的黄金回放证据；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

时间：2026-08-08 15:37:43 +08:00

执行时基线 HEAD：`ee11d39d97a3`（本报告与实现将进入同一独立提交）

范围：Meta v4 / Run v17 / Replay v7 / 游戏 v1.16，四条正式 `GameplayRunLoop` 黄金回放重录、差异审查与运行时摘要复跑。

## 结论

- 四条 checked-in golden 均已重新捕获为文件 schema v7、recording schema v7，并通过 `replay-runner --rerun-runtime-summary`。
- `replay-smoke` 明确拒绝文件或 recording schema v1～v6 及 v8；旧 Replay v6 不迁移、不改写源文件。
- 四条回放的数据指纹统一为 `b35d17c1c75d0f71f20760f843e7d882837c6ef2ecc8d72d157b56c02c0d256d`，模块地图 hash 保持 `2a7ebcdfde4b23311c64199feffe827a64aeaa503afecf23a6ad165f563c200a`。
- 与旧 Replay v6 基线相比，只保留游戏 / 文件 / recording schema、规范化玩法数据指纹、recording hash，以及 `golden_full_death` 的 `gear_mods.ranks` → `mod_ids` 预期结构差异；两处重录产生的 decision time 噪声已恢复旧稳定值并重算 hash。
- `golden_full_death` 仍以 `player_death` 结束且不存在 Meta 存档或残留 Run 存档；其余三条保持既定结束原因。四条运行时摘要均与新捕获文件一致。
- 本次未运行 performance probe、startup probe 或任何人工体验验收。Godot headless 退出时仍有既有 RID / ObjectDB / resource 清理诊断，不影响 runner 的通过协议。

## 逐条结果

| 回放 | recording hash | runtime rerun |
|------|----------------|---------------|
| `golden_basic_run.replay` | `eb9f5936c86d24d933f7b4484100e742d46111ccdbb1301a5e79f18d0f1cbf78` | 通过 |
| `golden_pause_resume.replay` | `85ccfb6238185ff429ce687aa4a2e1db860188cc7b9adac6fe7d482ce0fce3bc` | 通过 |
| `golden_full_death.replay` | `95c2139660296089764f077b0c56946e4fc7815045764ba667ccd897d78b2126` | 通过 |
| `golden_reward_choice.replay` | `d3807cc50d230ba0239972846452d1dc7500e1a0ac1738dbe0d736289ce95c6b` | 通过 |

## 执行命令

```text
py -3 tools/godot_bridge.py --project client replay-smoke
py -3 tools/godot_bridge.py --project client capture-golden-replay --golden-scenario <scenario>
py -3 tools/godot_bridge.py --project client replay-runner --replay-file <golden> --rerun-runtime-summary
```

四个 scenario 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_reward_choice`。
