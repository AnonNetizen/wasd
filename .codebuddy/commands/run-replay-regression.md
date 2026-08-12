---
description: 运行单进程、隔离 user:// 的黄金回放回归。
---

# /run-replay-regression

1. 运行 `python tools/godot_bridge.py --project client replay-regression`。
2. 只有需要一次收集全部失败时才追加 `--keep-going`。
3. 在对话中汇总每条回放结果和首个稳定 summary diff。
4. 确认是有意改变稳定语义前，不得修改或重录 golden。
5. `--allow-data-fingerprint-mismatch` 仅供诊断，结果不算权威通过。
