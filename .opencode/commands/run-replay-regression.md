---
description: 跑黄金回放回归（GDD 9.9 / ADR #16 / 测试策略 L3）。
---

# /run-replay-regression

## 步骤

1. 检查 `tools/replay_runner.gd` 是否就位；不存在则说明它在 M3+ 落地，当前阶段无法跑。
2. 检查 `tests/replays/golden_*.replay` 是否存在；为空则提示参照测试策略 §2.4 录第一组。
3. 跑：`godot --headless -- script tools/replay_runner.gd tests/replays/golden_*.replay`。
4. 输出报告到 `docs/reports/<YYYY-MM-DD>-replay-regression.md`。
5. 如全过，报告无回归；如 fail，先确认是否本次有意改变行为。

## 不要做

- 不要在 fail 时自动改代码 / 改数据。
- 不要在确认是 bug 前就重录黄金样例。
- 不要污染 git tree（脚本只读 + 写报告，不改源码）。
