# OPENCODE.md —— OpenCode 开工入口

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 OpenCode 的轻量入口适配；改 OpenCode 平台入口、agent / command / skill / plugin 映射或规则加载方式时，必须同步 `AGENTS.md`、`CLAUDE.md`、`CODEX.md`、`.opencode/`、`.codex/`、`.codebuddy/`、`docs/AI协作/工具适配指南.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

`AGENTS.md` 仍是本项目所有 AI agent 的通用开工入口；`.opencode/opencode.json` 会把本文件与规则入口加载进 OpenCode。

## OpenCode 开工顺序

1. 先读 `AGENTS.md`，按其中“快速开工 5 步”继续；日常接手优先读 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`，完整 `docs/AI记忆/项目记忆.md` 按任务需要再读。
2. 强制编码规则读 `.opencode/rules/game-coding-rules.md`；完整规则正文由 `.opencode/opencode.json` 同时加载 `.codebuddy/rules/game-coding-rules.md`。
3. 面向用户的回复默认中文；仅在用户明确要求或引用代码 / API / 日志原文等特殊场景使用其他语言。
4. 用户问有没有问题 / 风险时，基于事实回答；没发现问题就明确说没有问题，不硬找问题或过度优化。
5. 用户提出新需求后，先简短反馈落地前景、性价比、复杂度和主要风险；有重大隐患时先说清楚，再决定是否实现。
6. 发生上下文总结 / 压缩 / 恢复后，先以用户最后一条明确指令重新对齐当前任务；摘要、`Next Steps` 或 `current_state.json` 只作候选参考，不能被当作授权执行。
7. 大更改完成后按 `AGENTS.md` 的 AI Git 提交策略自动 commit；大型代码改动提交前追加事实型 code review；细微改动不提交也不触发正式 review；提交前必须检查 status/diff/log 并只 stage 本次任务文件。
8. 需要复杂任务拆分时，用 `.opencode/agents/` 下同名 subagent，或用 OpenCode 自带 agent/task 能力。
9. 需要 slash command 时，优先用 `.opencode/opencode.json` 注册的命令；也可按 `.opencode/commands/` 下对应 `.md` 步骤手动执行。
10. 需要可复用流程时，优先加载 `.opencode/skills/` 下项目级 skills；这些 skills 与 `.codex/skills/`、`.codebuddy/skills/` 同名同步，当前含 Godot/GDScript、场景验证、Godot 测试诊断、试玩复盘、文档同步、安全提交、事实 review、AI 资源筛选和 MCP 评估。
11. 外部 AI 库的有用经验已整合进项目级 skills；不再保留 vendor submodule、外部 hooks / plugin、整包 skills 或 `.agents/skills` reference 层。
12. 改 `.opencode/` 后重启 OpenCode；运行中的 session 不会热重载配置。

## OpenCode 平台文件

| 用途 | 路径 |
|------|------|
| 通用开工入口 | `AGENTS.md` |
| OpenCode 入口速查 | `OPENCODE.md` |
| OpenCode 配置 | `.opencode/opencode.json` |
| 编码规则入口 | `.opencode/rules/game-coding-rules.md` |
| Subagents | `.opencode/agents/` |
| Commands | `.opencode/commands/` |
| Skills | `.opencode/skills/` |
| 跨平台适配说明 | `docs/AI协作/工具适配指南.md` |
