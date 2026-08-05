# ADR #186 弹药系统删除回放回归报告

> **AI 修改说明**：本报告记录 ADR #186 完全删除弹药系统后的 Replay v4 捕获与逐字段审计；若再次重录 golden 或改变结论，必须同步 `docs/AI记忆/current_state.json`、知识索引与当日会话日志。

日期：2026-08-05
范围：完全删除弹药 / 换弹 / 弹匣掉落后，重录并复跑四条 Replay v4 黄金回放。

## 结论

- 四条 checked-in golden 均已由正式 `GameplayRunLoop` 重新捕获为 Replay v4，并通过 `replay-runner --rerun-runtime-summary`。
- 文件 / recording schema 从 v3 升为 v4，游戏版本从 `v1.10` 升为 `v1.11`，数据指纹从 `d95cd1ece6e4f5344f054d577dd619e27ec10c7c81630c7ea4a641c07ba08caa` 变为 `e774ed3a86b7ef747c34105af52da9c21153e157debe3eed304f51b95a7359dc`。
- 每条 `run_summary` 都删除且只删除六个弹药字段：`active_ammo_magazines`、`ammo_drop_misses`、`ammo_magazine`、`ammo_reserve`、`reload_remaining`、`weapon_reloading`。全部回放文本均无 `ammo` / `reload` / `magazine` / `reserve` 遗留字段。
- 排除上述六个退役字段后，四条新旧 `run_summary` 逐字段完全相等：地图 hash、状态、帧样本、生命、金币、击杀、难度、敌人 / 子弹存在性、奖励选择和对象池统计均未漂移。
- 四条旧回放本来就没有 `reload` 输入事件，因此删除该 action 后 input / decision event 数量保持不变；当前 action 集只包含对应场景实际使用的四技能、冲刺、暂停和返回。
- 当前正式启动摘要为 53 组 contracts、10 个 RNG 子流、17 个 pool id、383 个 locale key；`RNG.ammo` 与 `ammo_magazine` 均不存在。

## 逐条结果

| 回放 | input / decision | 非弹药摘要差异 | runtime rerun |
|------|------------------|----------------|---------------|
| `golden_basic_run.replay` | 10 / 1 | 0 | 通过 |
| `golden_pause_resume.replay` | 14 / 1 | 0 | 通过 |
| `golden_full_death.replay` | 6 / 2 | 0 | 通过 |
| `golden_reward_choice.replay` | 10 / 2 | 0 | 通过 |

四条回放的 `module_map_hash` 均保持 `da44e2109c9dc3cb2868ec8367900a2570692ee4c36574e34305a50216a5c76a`。

## 执行命令

```text
py -3 tools/godot_bridge.py --project client capture-golden-replay --golden-scenario <scenario>
py -3 tools/godot_bridge.py --project client replay-runner --replay-file <golden> --rerun-runtime-summary
```

四个 scenario 依次为 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_reward_choice`。Godot 4.7.1 headless 退出时仍输出既有 RID / ObjectDB / resource 清理诊断，不影响 runner 的通过协议；本任务未运行 performance probe 或 startup probe。
