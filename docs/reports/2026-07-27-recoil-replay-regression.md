# ADR #165 黄金回放回归报告

> **AI 修改说明**：本报告记录 ADR #165 武器后坐、扩散与控制 Mod 的黄金回放重录证据；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

- 测试时间：2026-07-27 18:12:39 +08:00
- 测试基线提交：`ec6d9c1867db9aa4d7c5af8ad8418c218bafc8ee`
- 数据指纹：`818e3f62ce8dc37e2daabc55147f2d2560ccbdffd0be2902815da301133cbc4b`
- Replay file / recording schema：v3 / v3
- Run seed：`20260619`
- 模块 map hash：`2b2765c9b370f6017558d213fcc1d5ea243b57ac551fe6d521b632b9c92410b9`

## 结论

四条黄金回放已按 ADR #165 的武器 schema v3、后坐模型和当前数据指纹重录，并逐条使用 `replay-runner --rerun-runtime-summary` 通过。输入 wire format 未变，Replay 保持 v3；未增加旧 Replay 或旧黄金基线兼容分支。

重录前，旧 `golden_basic_run` 首先因数据指纹从 `6e401358…` 变化为 `818e3f62…` 被明确拒绝。这是预期结果：武器与相机数据 schema、Gear Mod 数据和表现 profile 都已改变，不能把新运行时套用到旧数据基线。

## 结果

| 回放 | 状态 | 关键覆盖 |
|------|------|----------|
| `golden_basic_run.replay` | 通过 | 冷静主 + 愤怒子、当前武器 / 数据指纹与基础流程 |
| `golden_pause_resume.replay` | 通过 | 暂停 / 恢复、输入和 `GameClock` 冻结 |
| `golden_full_death.replay` | 通过 | 愤怒主 + 冷静子、死亡与结算流程 |
| `golden_level_up_choice.replay` | 通过 | 显式调试成长候选、选择决策与恢复游玩 |

四条回放均在 tick 180 结束，summary 与重跑结果逐字段一致；模块 map hash 保持 ADR #164 当前值。后坐公式、弹道锥、零扩散固定 RNG、多弹丸单次反馈、反冲移动和动态震屏由 L1 / runtime smoke 单独覆盖。Godot 退出时仍打印项目既有 RID / ObjectDB / resource leak 诊断；命令退出码均为 0，未发现新的回放差异。

## 使用命令

```powershell
python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario <scenario>
python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/<scenario>.replay --rerun-runtime-summary
```

其中 `<scenario>` 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_level_up_choice`。
