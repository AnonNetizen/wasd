---
description: 跑黄金回放回归（GDD 9.9 / ADR #16 / 测试策略 L3），在单个隔离 Godot 进程中验证全部 golden replay。
allowed-tools: Bash, Read, Edit, Grep, Glob
---

# /run-replay-regression

## 步骤

1. 确认 `client/tools/replay_runner.gd` 与 `client/tests/replays/golden_*.replay` 存在。
2. 运行权威批量入口：
   ```powershell
   py -3 tools/godot_bridge.py --project client replay-regression
   ```
3. 默认遇到首个失败立即停止；需要一次收集全部失败时追加 `--keep-going`。
4. 汇总终端中每个回放的通过 / 失败与首个 summary diff；默认不创建 `docs/reports/` 文件。
5. 如有失败，先确认是否为本次有意改变的稳定语义；确认前不得修改或重录 golden。

## 边界

- `--allow-data-fingerprint-mismatch` 仅供诊断，结果不算权威通过。
- 单文件定位使用 `replay-runner --replay-file <path> --rerun-runtime-summary`。
- 只有 Replay 输入、稳定 gameplay summary 或 data fingerprint 覆盖本次改动时才运行；纯 Godot Control 鼠标命中不属于 L3 证据。
- runner 使用隔离 `user://`，不得污染玩家存档或改写 golden。
