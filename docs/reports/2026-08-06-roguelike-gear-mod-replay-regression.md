# ADR #188 Roguelike 与局内 Gear Mod 回放回归报告

> **AI 修改说明**：本报告记录 ADR #188 将 Gear Mod 纯局内化、删除撤离并升级 Replay v5 后的黄金回放证据；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

日期：2026-08-06
范围：Meta v3 / Run v13 / Replay v5 / 游戏 v1.12，四条正式 `GameplayRunLoop` 黄金回放重录与运行时摘要复跑。

## 结论

- 四条 checked-in golden 均已重新捕获为文件 schema v5、recording schema v5，并通过 `replay-runner --rerun-runtime-summary`。
- `replay-smoke` 明确拒绝文件或 recording schema v1～v4 及 v6；旧 Replay v4 不迁移。
- 四条回放的数据指纹统一为 `86434bcc45764303e3db13764a8c607f08b50d8e56c3b4f52baee2c30a86fa22`，模块地图 hash 统一为 `40d2a0870aa54bc856fdf34002ed6d5dd406ad86be6bcefffd543ae35158552d`。
- `golden_full_death` 仍以 `player_death` 结束且不存在 Meta 存档或残留 Run 存档；其余三条保持既定结束原因。四条运行时摘要均与新捕获文件一致。
- 本次未运行 performance probe、startup probe 或任何人工体验验收。Godot headless 退出时仍有既有 RID / ObjectDB / resource 清理诊断，不影响 runner 的通过协议。

## 逐条结果

| 回放 | recording hash | runtime rerun |
|------|----------------|---------------|
| `golden_basic_run.replay` | `85658de30102eb0e1cc3a95987f51f3f74303b0f1e4cdc172511847340be4382` | 通过 |
| `golden_pause_resume.replay` | `d2fa6889aba8e1c0bf1e9f6e76e8c0bd585e96a519a44da166db6a99e811b3e9` | 通过 |
| `golden_full_death.replay` | `5d3ffdbfde3d685c9227a41c1d09da9109e03bf3831f82e05aa59ccdd4154241` | 通过 |
| `golden_reward_choice.replay` | `b6472cd60bdf8b54b33cf8576cacdf930a5a39dd7af41f19a5d138258e9dde7d` | 通过 |

## 执行命令

```text
python tools/godot_bridge.py capture-golden-replay --golden-scenario <scenario>
python tools/godot_bridge.py replay-smoke
python tools/godot_bridge.py replay-runner --replay-file <golden> --rerun-runtime-summary
```

四个 scenario 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_reward_choice`。
