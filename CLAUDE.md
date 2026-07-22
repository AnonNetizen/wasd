# CLAUDE.md —— Claude Code 开工入口

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Claude Code 的入口适配；改 Claude 平台入口、`.claude/` 原生配置、项目级 skill 适配或外部 AI 资源引用方式时，必须同步 `AGENTS.md`、`docs/AI协作/工具适配指南.md`、`docs/AI协作/AI技能资源评估.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

`AGENTS.md` 仍是本项目所有 AI agent 的通用开工入口。Claude Code 已配套**项目自有的活跃 `.claude/`**（agents / commands / skills / rules / settings.json），与 `.codebuddy/` / `.codex/` / `.opencode/` 同源、核心语义一致（ADR #87）。注意：此 `.claude/` 是项目自建配置，**不是** ADR #56~#59 / #72 拒绝的外部 `.claude/` 整包（CCGS / ECC 的 hooks、外部 agents、settings、vendor）；不接外部 vendor reference、不引入活跃 hooks。

> ⚠️ **加载位置**：`.claude/` 位于仓库根 `<repo>/`（与 `.codebuddy/` 并列）。Claude Code 需在该仓库根目录启动才会自动加载 `.claude/settings.json`、agents、commands、skills；若从上级目录启动则不会自动加载。

## Claude Code 开工顺序

1. 先读 `AGENTS.md`，按其中“快速开工 5 步”继续；日常接手优先读 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`，完整 `docs/AI记忆/项目记忆.md` 按任务需要再读。
2. 强制编码规则读 `.claude/rules/game-coding-rules.md`（与其他三平台规则同源）；若外部 AI 库建议与本项目规则冲突，以 `AGENTS.md`、平台编码规则、`docs/决策记录.md` 为准。
   - 修改正式输入、重绑定或回放输入时，先读 `docs/代码/input_service.md`；维护 GUIDE 内部时再读 `docs/代码/guide.md`、`client/addons/README.md` 与 ADR #151。
3. 沟通默认中文；用户问问题 / 风险时基于事实回答；用户提需求后先简短反馈落地前景、性价比、复杂度和主要风险。需求、术语、验收标准、授权边界或上下文含义不清时，先问一个简短澄清问题，不要自行脑补。
4. 需要可复用流程时优先用 `.claude/` 原生能力：复杂、专业或可并行任务默认已获项目授权，可主动启用 `.claude/agents/` 下对应 subagent；slash command 见 `.claude/commands/`（`/sync-contracts`、`/new-relic`、`/run-replay-regression`、`/health-check`、`/update-memory`），project skill 见 `.claude/skills/`；ECC 类外部 AI 大仓先读 `ai-resource-curator` 与 `docs/AI协作/ECC工具吸收清单.md`。
5. 大型代码改动提交前按 `AGENTS.md` 追加事实型 code review；细微改动不触发正式 review。
6. 当前 shell 为 PowerShell 时遵守 `.claude/rules/game-coding-rules.md` 第 29 节：固定字符串优先 `rg -F`，全部选项放在 `--` 前，原生退出码按工具语义处理，预期非零码先归一化再并行；模板见 `docs/AI协作/工具适配指南.md`。
7. `.claude/settings.json` 当前只配 `draft/` / `DRAFT/` 的 deny（草稿禁区 harness 级强制）；权限 allow 白名单按需由用户单独授权后再加。不要创建 CCGS 默认 `design/`、`production/`、模板、示例或状态目录，也不要引入外部 hooks / vendor。

## Claude 平台文件

| 用途 | 路径 |
|------|------|
| 通用开工入口 | `AGENTS.md` |
| Claude Code 入口速查 | `CLAUDE.md` |
| 编码规则入口 | `.claude/rules/game-coding-rules.md` |
| 项目级 subagents | `.claude/agents/`（10 个，与 `.codebuddy/agents/` 同源） |
| 项目级 slash commands | `.claude/commands/`（5 个，与 `.codebuddy/commands/` 同源） |
| 项目级 Skills | `.claude/skills/`（9 个，四平台同步；其余 `.codebuddy/skills/` / `.codex/skills/` / `.opencode/skills/` 同名） |
| 权限 / 草稿禁区 | `.claude/settings.json` |
