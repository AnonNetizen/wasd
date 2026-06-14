# CLAUDE.md —— Claude Code 开工入口

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Claude Code 的轻量入口适配；改 Claude 平台入口、`.claude/` 工具安装或规则加载方式时，必须同步 `AGENTS.md`、`docs/AI协作/工具适配指南.md`、`docs/AI协作/AI技能资源评估.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

`AGENTS.md` 仍是本项目所有 AI agent 的通用开工入口；`.claude/` 下安装了 Claude Code Game Studios 的 agents / skills / hooks / rules，供 Claude Code 使用。

## Claude Code 开工顺序

1. 先读 `AGENTS.md`，按其中“开工 5 步”继续。
2. 强制编码规则按 `AGENTS.md` 第 3 步读取；若 `.claude/` 工具规则与本项目规则冲突，以 `AGENTS.md`、当前平台编码规则、`docs/决策记录.md` 为准。
3. `.claude/agents/`、`.claude/skills/`、`.claude/hooks/`、`.claude/rules/` 来自 `Donchitos/Claude-Code-Game-Studios`，用于专业分工、工作流、hook 与路径规则参考。
4. `.claude/docs/templates/` 未安装；不要假设 CCGS 的模板目录存在。需要模板时优先使用本项目 `docs/AI协作/任务模板/`、`docs/代码文档规范.md` 和既有项目文档。
5. `.agents/skills/headless-godot/` 来自 `abagames/headless-godot-skill-kit`，用于 headless Godot CLI、场景编辑、测试和导出参考。
6. `.agents/skills/ccgs-game-studio/` 是 CCGS 跨平台适配层；Claude Code 可继续直接用 `.claude/`，其他 agent 通过该 skill 按需读取 `.claude/agents/` 与 `.claude/skills/`。
7. `GodotPrompter` 通过 OpenCode plugin 在 `.opencode/opencode.json` 中注册；Claude Code 如需使用其技能，可参考 `.opencode/vendor/ai-resources/GodotPrompter/skills/`，但不得绕过本项目规则。

## Claude 平台文件

| 用途 | 路径 |
|------|------|
| 通用开工入口 | `AGENTS.md` |
| Claude Code 入口速查 | `CLAUDE.md` |
| Claude agents | `.claude/agents/` |
| Claude skills | `.claude/skills/` |
| Claude hooks | `.claude/hooks/` |
| Claude path rules | `.claude/rules/` |
| Agent Skills | `.agents/skills/` |
| 外部 AI 资源整包来源 | `.opencode/vendor/ai-resources/` |
