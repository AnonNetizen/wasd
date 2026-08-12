---
description: 运行项目静态健康检查并在对话中汇总风险。
---

# /health-check

1. 按当前变更范围运行相关 pre-commit hooks；用户要求全量时运行 `pre-commit run --all-files`。
2. 未安装 pre-commit 时依次运行相关 contract、data、schema、lint 工具。
3. 文档部分先跑 `python tools/test_docs_health_check.py`，再跑 `python tools/docs_health_check.py`。
4. 语义 lint warning 是 advisory，需要解释；其他失败作为阻塞证据报告。
5. 结果直接在对话中汇总。除非用户明确要求持久报告，不创建被 Git 跟踪的验证报告。
6. 只有请求范围或变更路径需要时才追加 Godot、Replay 或性能验证。
