# CODEX.md —— OpenAI Codex CLI 开工入口

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Codex CLI 的轻量入口适配；改 Codex 平台入口、agent、command 或规则加载方式时，必须同步 `AGENTS.md`、`OPENCODE.md`、`.codex/`、`.opencode/`（如影响跨平台通用能力）、`docs/AI协作/工具适配指南.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

`AGENTS.md` 仍是本项目所有 AI agent 的通用开工入口；本文件只说明 Codex CLI 该读哪些平台适配文件。

## Codex 开工顺序

1. 先读 `AGENTS.md`，按其中“开工 5 步”继续。
2. 强制编码规则优先读 `.codex/rules/game-coding-rules.md`。
3. 面向用户的回复默认中文；仅在用户明确要求或引用代码 / API / 日志原文等特殊场景使用其他语言。
4. 用户问有没有问题 / 风险时，基于事实回答；没发现问题就明确说没有问题，不硬找问题或过度优化。
5. 用户提出新需求后，先简短反馈落地前景、性价比、复杂度和主要风险；有重大隐患时先说清楚，再决定是否实现。
6. 大更改完成后按 `AGENTS.md` 的 AI Git 提交策略自动 commit；细微改动不提交；提交前必须检查 status/diff/log 并只 stage 本次任务文件。
7. 需要 subagent 时，优先用 `.codex/agents/` 下同名角色；不支持自动调度时，把对应 `.md` 当 prompt 模板读。
8. 需要 slash command 时，优先用 `.codex/commands/` 下同名步骤；不支持命令时，按文件步骤手动执行。
9. 如果 `.codex/` 与 `AGENTS.md` 口径冲突，以 `AGENTS.md`、编码规则和 `docs/决策记录.md` 的核心项目约束为准，并同步修正文档漂移。

## Codex 平台文件

| 用途 | 路径 |
|------|------|
| 编码规则入口 | `.codex/rules/game-coding-rules.md` |
| Subagents | `.codex/agents/` |
| Slash commands | `.codex/commands/` |
| 跨平台适配说明 | `docs/AI协作/工具适配指南.md` |
