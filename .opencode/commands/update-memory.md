---
description: 显式触发 AI 记忆更新（长期索引 + current_state.json + 会话日志的兜底入口）。
---

# /update-memory

## 用途

按规则 14-B / ADR #15 / ADR #19 / ADR #44，AI 应主动更新 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与会话日志。本命令是显式兜底。

## 步骤

1. 读 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`、`docs/决策记录.md`、`docs/修改建议.md`、`docs/游戏设计文档.md`、`docs/CICD规划.md` 与最近 git commit log。
2. 对照版本号、ADR 条数、工具链、近期对话脉络是否过期；确认 `current_state.latest_adr`、`open_decisions`、`next_actions`、`last_verified` 是否准确。
3. 修订项目记忆：同位置覆盖而非追加；主文件保持 ≤ 200 行。
4. 覆盖更新 `docs/AI记忆/current_state.json`，不追加历史。
5. 写当日 `docs/AI记忆/会话日志/<YYYY-MM-DD>.md`。
6. 跑 `python tools/docs_health_check.py`。
7. 只记结论 + 关键参数 + 文件指针，不复述完整对话。

## 不要做

- 按 `AGENTS.md` 的 AI Git 提交策略判断；单独记忆维护通常属于细微改动不自动 commit，若属于大更改收尾则随本次任务提交。
- 不要改 ADR / 规则 / 设计文档，除非这是当前主任务的一部分。
- 不要把历史细节塞进项目记忆主索引；短期状态写 `current_state.json`，历史细节写会话日志。
