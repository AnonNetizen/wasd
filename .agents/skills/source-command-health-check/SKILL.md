---
name: "source-command-health-check"
description: "运行项目静态健康检查并在对话中汇总风险。"
---

# source-command-health-check

Use when the user asks to run the migrated `health-check` command.

1. Run the relevant pre-commit hooks or the equivalent contract, data, schema, lint and docs commands.
2. Include `python tools/test_docs_health_check.py` before `python tools/docs_health_check.py`.
3. Treat semantic lint warnings as advisory and explain them; other failures are blocking evidence.
4. Report results in the conversation. Do not create a tracked verification report unless the user explicitly asks for a durable report.
5. Do not run Godot, Replay or performance probes unless the requested health scope or changed paths require them.
