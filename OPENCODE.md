# OPENCODE.md —— OpenCode 开工入口

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 OpenCode 的轻量入口适配；改 OpenCode 平台入口、agent/command 映射或规则加载方式时，必须同步 `AGENTS.md`、`CODEX.md`、`.opencode/`、`docs/AI协作/工具适配指南.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`。

`AGENTS.md` 仍是本项目所有 AI agent 的通用开工入口；`.opencode/opencode.json` 会把本文件与规则入口加载进 OpenCode。

## OpenCode 开工顺序

1. 先读 `AGENTS.md`，按其中“开工 5 步”继续。
2. 强制编码规则读 `.opencode/rules/game-coding-rules.md`；完整规则正文由 `.opencode/opencode.json` 同时加载 `.codebuddy/rules/game-coding-rules.md`。
3. 面向用户的回复默认中文；仅在用户明确要求或引用代码 / API / 日志原文等特殊场景使用其他语言。
4. 需要复杂任务拆分时，用 `.opencode/agents/` 下同名 subagent，或用 OpenCode 自带 agent/task 能力。
5. 需要 slash command 时，优先用 `.opencode/opencode.json` 注册的命令；也可按 `.opencode/commands/` 下对应 `.md` 步骤手动执行。
6. 改 `.opencode/` 后重启 OpenCode；运行中的 session 不会热重载配置。

## OpenCode 平台文件

| 用途 | 路径 |
|------|------|
| 通用开工入口 | `AGENTS.md` |
| OpenCode 入口速查 | `OPENCODE.md` |
| OpenCode 配置 | `.opencode/opencode.json` |
| 编码规则入口 | `.opencode/rules/game-coding-rules.md` |
| Subagents | `.opencode/agents/` |
| Commands | `.opencode/commands/` |
| 跨平台适配说明 | `docs/AI协作/工具适配指南.md` |
