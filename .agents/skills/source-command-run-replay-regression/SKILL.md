---
name: "source-command-run-replay-regression"
description: "运行单进程、隔离 user:// 的黄金回放回归。"
---

# source-command-run-replay-regression

Use when the user asks to run the migrated `run-replay-regression` command.

1. Run `python tools/godot_bridge.py --project client replay-regression`.
2. Add `--keep-going` only when collecting every failure is useful.
3. Report each replay result and the first stable-summary difference in the conversation.
4. Do not modify or recapture golden files until an intentional stable-semantic change is confirmed.
5. The runner must remain isolated from the player's `user://` data.
