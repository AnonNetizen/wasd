---
description: 跑黄金回放回归（GDD 9.9 / ADR #16 / 测试策略 L3），确认当前代码下 tests/replays/golden_*.replay 仍能完整复现。
allowed-tools: Bash, Read, Edit, Grep, Glob
---

# /run-replay-regression

## 步骤

1. 检查工具与样例是否就位：
   - `tools/replay_runner.gd`（若不存在 → 提示用户它在 M3+ 落地，当前阶段无法跑）
   - `tests/replays/golden_*.replay`（若为空 → 提示用户参照测试策略 §2.4 录第一组）
2. 跑全量黄金回放：
   ```bash
   godot --headless -- script tools/replay_runner.gd tests/replays/golden_*.replay
   ```
3. 收集结果：每个回放 → 通过 / fail（首个 diff 帧 + 字段）
4. 输出报告到 `docs/reports/<YYYY-MM-DD>-replay-regression.md`，含：
   - 测试时间 / git commit / 数据指纹
   - 每个回放的状态
   - fail 详情（diff 字段、可能的影响范围）
5. **如全过** → 报告"无回归"，提示可继续推进
6. **如有 fail**：
   - 先与用户确认：是否本次改动**有意改变**了行为？
   - **是** → 提示用户重录黄金样例（用 `tools/replay_recorder.gd` 或游戏内录制），并在 commit message 注明影响
   - **否** → 视为 bug，列出 diff 字段帮助定位

## 何时跑

按测试策略 §7 表：
- 改了伤害公式 / 状态效果叠加
- 改了 ModifierEngine
- 改了 Spawner 难度曲线
- 改了任何敌人 / 关键遗物的数值
- 发版前

## 不要做

- 不要在 fail 时自动改代码 / 改数据
- 不要在确认是 bug 前就重录黄金样例
- 不要污染 git tree（脚本只读 + 写报告，不改源码）

## 相关
- 测试策略 §2.4 / §7
- GDD 9.9 / ADR #16
- subagent: `balancer`
