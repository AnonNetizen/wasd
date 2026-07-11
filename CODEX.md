# CODEX.md —— OpenAI Codex CLI 开工入口

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Codex CLI 的轻量入口适配；改 Codex 平台入口、agent、command、skill 或规则加载方式时，必须同步 `AGENTS.md`、`CLAUDE.md`、`OPENCODE.md`、`.codex/`、`.codebuddy/` / `.opencode/`（如影响跨平台通用能力）、`docs/AI协作/工具适配指南.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

`AGENTS.md` 仍是本项目所有 AI agent 的通用开工入口；本文件只说明 Codex CLI 该读哪些平台适配文件。

## Codex 开工顺序

1. 先读 `AGENTS.md`，按其中“快速开工 5 步”继续；日常接手优先读 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`，完整 `docs/AI记忆/项目记忆.md` 按任务需要再读。
2. 强制编码规则优先读 `.codex/rules/game-coding-rules.md`。
3. 面向用户的回复默认中文；仅在用户明确要求或引用代码 / API / 日志原文等特殊场景使用其他语言。
4. 用户问有没有问题 / 风险时，基于事实回答；没发现问题就明确说没有问题，不硬找问题或过度优化。
5. 用户提出新需求后，先简短反馈落地前景、性价比、复杂度和主要风险；有重大隐患时先说清楚，再决定是否实现。
6. 需求、术语、验收标准、授权边界或上下文含义不清时，先问一个简短澄清问题；不要为了推进而自行脑补。只有低风险、可撤销且已明说假设的细节，才可边做边标注假设。
7. 发生上下文总结 / 压缩 / 恢复后，先以用户最后一条明确指令重新对齐当前任务；摘要、`Next Steps` 或 `current_state.json` 只作候选参考，不能被当作授权执行。
8. 大更改完成后按 `AGENTS.md` 的 AI Git 提交策略自动 commit；大型代码改动提交前追加事实型 code review；细微改动不提交也不触发正式 review；提交前必须检查 status/diff/log 并只 stage 本次任务文件。
9. 当前 shell 为 PowerShell 时遵守 `.codex/rules/game-coding-rules.md` 第 29 节：固定字符串优先 `rg -F`，全部选项放在 `--` 前，原生退出码按工具语义处理，预期非零码先归一化再并行；模板见 `docs/AI协作/工具适配指南.md`。
10. 复杂、专业或可并行的任务默认已获项目授权，可主动用 `.codex/agents/` 下同名角色调度 subagent；只读小任务或直接实现更高效时不必强行拆分；若当前 Codex 运行时不允许原生调度，则把对应 `.md` 当 prompt 模板读。
11. 需要 slash command 时，优先用 `.codex/commands/` 下同名步骤；不支持命令时，按文件步骤手动执行。
12. 需要复用项目级 skill 时，优先读 `.codex/skills/<name>/SKILL.md`；这些 skill 与 `.codebuddy/skills/`、`.opencode/skills/` 同步，已直接吸收项目需要的 Godot、headless 验证、试玩复盘和 AI 协作面审计流程，不需要再跳转 vendor reference；ECC 类外部 AI 大仓先读 `ai-resource-curator` 与 `docs/AI协作/ECC工具吸收清单.md`。
13. 如果 `.codex/` 与 `AGENTS.md` 口径冲突，以 `AGENTS.md`、编码规则和 `docs/决策记录.md` 的核心项目约束为准，并同步修正文档漂移。

## Codex 平台文件

| 用途 | 路径 |
|------|------|
| 编码规则入口 | `.codex/rules/game-coding-rules.md` |
| Subagents | `.codex/agents/` |
| Slash commands | `.codex/commands/` |
| Project Skills（可作 prompt 模板） | `.codex/skills/` |
| 跨平台适配说明 | `docs/AI协作/工具适配指南.md` |
