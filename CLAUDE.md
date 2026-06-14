# CLAUDE.md —— Claude Code 开工入口

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Claude Code 的轻量入口适配；改 Claude 平台入口、Agent Skill 适配或外部 AI 资源引用方式时，必须同步 `AGENTS.md`、`docs/AI协作/工具适配指南.md`、`docs/AI协作/AI技能资源评估.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

`AGENTS.md` 仍是本项目所有 AI agent 的通用开工入口；Claude Code 不再安装活跃 `.claude/` 外部工具，外部 AI 库统一通过 `.agents/skills/game-ai-reference` 按需引用 vendor 来源。

## Claude Code 开工顺序

1. 先读 `AGENTS.md`，按其中“开工 5 步”继续。
2. 强制编码规则按 `AGENTS.md` 第 3 步读取；若外部 AI 库建议与本项目规则冲突，以 `AGENTS.md`、当前平台编码规则、`docs/决策记录.md` 为准。
3. 需要引用 GodotPrompter、headless-godot 或 CCGS 时，先读 `.agents/skills/game-ai-reference/SKILL.md`，再按需读取 `.opencode/vendor/ai-resources/` 中的具体文件。
4. 不要假设 `.claude/` 活跃目录存在；不要创建 CCGS 默认 `design/`、`production/`、模板、示例或状态目录。

## Claude 平台文件

| 用途 | 路径 |
|------|------|
| 通用开工入口 | `AGENTS.md` |
| Claude Code 入口速查 | `CLAUDE.md` |
| Agent Skills | `.agents/skills/` |
| 外部 AI 资源整包来源 | `.opencode/vendor/ai-resources/` |
