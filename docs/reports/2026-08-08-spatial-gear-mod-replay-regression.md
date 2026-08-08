# ADR #194 空间 Gear Mod 棋盘回放回归报告

> **AI 修改说明**：本报告记录 ADR #194 引入 7×7 Gear Mod 空间棋盘、升级 Replay v8 后的黄金回放证据；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

时间：2026-08-08 18:47:49 +08:00

执行时基线 HEAD：`5a55aa5379ce`（本报告与实现将进入同一独立提交）

范围：Meta v4 / Run v18 / Replay v8 / 游戏 v1.17，四条正式 `GameplayRunLoop` 黄金回放重录、逐字段差异审查与运行时摘要复跑。

## 结论

- 四条 checked-in golden 已重新捕获为文件 schema v8、recording schema v8，并通过 `replay-runner --rerun-runtime-summary`。
- 四条回放的数据指纹统一为 `5fc30d06b63dd7213e8b8fb17eac1ccc30790350f2a2b297c408f1f19f6b2396`，模块地图 hash 保持 `2a7ebcdfde4b23311c64199feffe827a64aeaa503afecf23a6ad165f563c200a`。
- 与 Replay v7 基线相比，保留游戏 / 文件 / recording schema、玩法数据指纹、recording hash、内容可用池新增两个 Mod，以及 `golden_full_death` 的 `gear_mods.mod_ids` → v18 棋盘快照结构差异。
- `golden_full_death` 与 `golden_reward_choice` 的重录 tick / decision time 漂移均恢复为旧稳定值，并通过 Replay 的规范序列化逻辑重算 recording hash；最终 diff 不含时间噪声或整数格式污染。
- `golden_full_death` 仍以 `player_death` 结束且不存在 Meta 存档或残留 Run 存档；其余三条保持既定结束原因。四条运行时摘要均与新捕获文件一致。
- 本次未运行 performance probe、startup probe 或任何人工体验验收。Godot headless 退出时仍有既有 RID / ObjectDB / resource 清理诊断，不影响 runner 的通过协议。

## 逐条结果

| 回放 | recording hash | runtime rerun |
|------|----------------|---------------|
| `golden_basic_run.replay` | `959ad095b7b09e01685f204cdea5b034f3890f9965971a58fb34152fec7666e1` | 通过 |
| `golden_pause_resume.replay` | `8eafb5cadd9114d9663ea363eb1486f0be8ff4e5f06e57e1ec266551c899846c` | 通过 |
| `golden_full_death.replay` | `ae341aa1289d9ea72f8393ca35abf18167d5bf3416eb34a6430968e4d92ddbdc` | 通过 |
| `golden_reward_choice.replay` | `e717091b796d26b6409d0c4bcb0a22b242505d7d8229c60bed23c5763be9ba59` | 通过 |

## 执行命令

```text
python tools/godot_bridge.py --project client replay-smoke
python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario <scenario>
python tools/godot_bridge.py --project client replay-runner --replay-file <golden> --rerun-runtime-summary
```

四个 scenario 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_reward_choice`。
