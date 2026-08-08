---
name: "source-command-run-replay-regression"
description: "运行单进程、隔离 user:// 的黄金回放回归"
---

# source-command-run-replay-regression

Use this skill when the user asks to run the migrated source command `run-replay-regression`.

## 步骤

1. 确认 `client/tools/replay_runner.gd` 与 `client/tests/replays/golden_*.replay` 存在。
2. 运行 `py -3 tools/godot_bridge.py --project client replay-regression`。
3. 默认 fail-fast；需要全部失败时追加 `--keep-going`。
4. 只汇总终端结果，默认不创建受版本控制的报告。
5. 失败后先确认是否有意改变稳定语义，确认前不得重录 golden。

## 边界

- `--allow-data-fingerprint-mismatch` 只用于诊断，不算权威通过。
- 单文件定位使用 `replay-runner --replay-file <path> --rerun-runtime-summary`。
- 纯 Godot Control 鼠标命中不属于 L3 证据。
- runner 必须隔离 `user://`，不得污染玩家存档或改写 golden。
