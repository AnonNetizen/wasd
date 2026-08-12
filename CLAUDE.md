# CLAUDE.md —— Claude Code 平台入口

> 本文件只说明 Claude Code 的加载适配；共同规则正文见 `docs/AI协作/项目规则.md`。

开工顺序：

1. 读 `AGENTS.md`。
2. 读 `docs/AI协作/项目规则.md`。
3. 读 `docs/AI协作/快速开工.md`、`docs/AI记忆/current_state.json` 与 `docs/AI导航.md` 相关段落。
4. 按任务读取直接权威文档。

Claude Code 需从仓库根启动，平台文件位于 `.claude/`：

- 规则适配器：`.claude/rules/game-coding-rules.md`
- Agents：`.claude/agents/`
- Commands：`.claude/commands/`
- Skills：`.claude/skills/`
- Settings：`.claude/settings.json`

`.claude/` 是项目自有配置，不引入外部 hooks / vendor 整包；平台适配不能放宽共同规则。
