# ADR #164 黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #164 全开放平地与首次进入动态遭遇的黄金回放重录证据；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

- 测试时间：2026-07-27 16:54:39 +08:00
- 测试基线提交：`007e6abcffd99c0438ff736ce072d92f7eb13e9c`
- 数据指纹：`6e401358c09555dcdc6a970b23e77463b7897044728c3581b3ad5c372345bc62`
- Replay file / recording schema：v3 / v3
- Run seed：`20260619`
- 模块 map hash：`2b2765c9b370f6017558d213fcc1d5ea243b57ac551fe6d521b632b9c92410b9`

## 结论

四条黄金回放已按 ADR #164 的全开放平地正式池和首次进入动态遭遇重录，并逐条使用 `replay-runner --rerun-runtime-summary` 通过。未增加旧 Replay 迁移或兼容分支。

重录前，旧 `golden_basic_run` 的首个差异为 `run_summary.active_enemies expected=45 actual=0`。这是预期的设计变化：旧模块模式在原地运行波次刷怪，新规则豁免初始模块，只有首次实际进入其他模块才生成遭遇计划。

## 结果

| 回放 | 状态 | 关键覆盖 |
|------|------|----------|
| `golden_basic_run.replay` | 通过 | 冷静主 + 愤怒子、四技能、冲刺、初始模块不刷怪 |
| `golden_pause_resume.replay` | 通过 | 暂停 / 恢复、输入与时间冻结 |
| `golden_full_death.replay` | 通过 | 愤怒主 + 冷静子、新防御层后的死亡流程 |
| `golden_level_up_choice.replay` | 通过 | 显式调试成长候选、选择决策与恢复游玩 |

四条回放均在 tick 180 结束，summary 与重跑结果逐字段一致。Godot 退出时仍打印项目既有的 RID / ObjectDB / resource leak 诊断；命令退出码均为 0，未发现新的回放差异。

## 使用命令

```powershell
python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario <scenario>
python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/<scenario>.replay --rerun-runtime-summary
```

其中 `<scenario>` 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_level_up_choice`。
