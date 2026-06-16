# CLAUDE.md —— Claude Code 开工入口

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 Claude Code 的轻量入口适配；改 Claude 平台入口、项目级 skill 适配或外部 AI 资源引用方式时，必须同步 `AGENTS.md`、`docs/AI协作/工具适配指南.md`、`docs/AI协作/AI技能资源评估.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

`AGENTS.md` 仍是本项目所有 AI agent 的通用开工入口；Claude Code 不安装活跃 `.claude/` 外部工具，也不再通过 vendor reference 读取外部 AI 库。需要可复用流程时，可把 `.codebuddy/skills/<name>/SKILL.md`、`.codex/skills/<name>/SKILL.md` 或 `.opencode/skills/<name>/SKILL.md` 中的同名项目级 skill 当 prompt 模板读取。

## Claude Code 开工顺序

1. 先读 `AGENTS.md`，按其中“快速开工 5 步”继续；日常接手优先读 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`，完整 `docs/AI记忆/项目记忆.md` 按任务需要再读。
2. 强制编码规则按 `AGENTS.md` 第 3 步读取；若外部 AI 库建议与本项目规则冲突，以 `AGENTS.md`、当前平台编码规则、`docs/决策记录.md` 为准。
3. 需要 Godot、headless 验证、测试诊断或试玩复盘流程时，直接读取 `.codebuddy/skills/`、`.codex/skills/` 或 `.opencode/skills/` 下对应项目级 skill。
4. 大型代码改动提交前按 `AGENTS.md` 追加事实型 code review；细微改动不触发正式 review。
5. 不要假设 `.claude/` 活跃目录或外部 vendor 目录存在；不要创建 CCGS 默认 `design/`、`production/`、模板、示例或状态目录。

## Claude 平台文件

| 用途 | 路径 |
|------|------|
| 通用开工入口 | `AGENTS.md` |
| Claude Code 入口速查 | `CLAUDE.md` |
| Project Skills（可作 prompt 模板） | `.codebuddy/skills/` / `.codex/skills/` / `.opencode/skills/` |
