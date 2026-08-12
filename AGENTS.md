# AGENTS.md —— AI agent 开工入口

> 修改本文件必须有用户明确授权。本文件只定义开工顺序与平台入口；共同规则正文见 `docs/AI协作/项目规则.md`。

## 快速开工

任何 AI agent 在本项目动手前按顺序完成：

1. 读本文件；Codex / Claude Code / OpenCode 可先读各自平台入口。
2. 读 `docs/AI协作/项目规则.md`，这是唯一共同规则正文。
3. 读 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`；当前状态不是执行授权。
4. 读 `docs/AI导航.md` 相关段落，再按任务读取直接权威：GDD、词表、测试策略、数据 / locale 手册或模块文档。

新机器 clone 后先按 `CONTRIBUTING.md` 第零节配置 `core.quotepath`、commit template 和 Git 身份。

## 平台入口

| 平台 | 入口 | 规则适配器 |
|------|------|------------|
| CodeBuddy | 本文件 | `.codebuddy/rules/game-coding-rules.md` |
| Codex | `CODEX.md` | `.codex/rules/game-coding-rules.md` |
| Claude Code | `CLAUDE.md` | `.claude/rules/game-coding-rules.md` |
| OpenCode | `OPENCODE.md` | `.opencode/rules/game-coding-rules.md` |

平台适配器只负责引导加载共同规则，不能复制或放宽规则正文。

## 任务路由

- 高频数据内容任务先看 `docs/AI协作/任务模板/`。
- 普通代码修改先从目标脚本的 `# Doc:` 或 `docs/代码/README.md` 定位模块文档。
- 设计、schema、契约、测试政策和 AI 工作流分别只改各自直接权威来源。
- 非模板任务按 `docs/AI协作/上下文预算.md` 控制读取范围；禁止盲目全仓搜索。

## 项目能力入口

- Subagents：各平台 `agents/` 目录；复杂或专业任务按角色说明使用。
- Slash commands：各平台 `commands/` 目录。
- Project skills：各平台 `skills/<name>/SKILL.md`。
- 若平台不支持原生能力，读取同名文件作为流程模板，不降低项目规则。

## 不可越过的边界

- `draft/` / `DRAFT/` 未经当前任务明确授权不得读取、搜索、修改或提交。
- 人工检查、L5、真实设备及视觉 / 听觉 / 手感验收只由人工执行。
- 默认中文沟通；需求或授权边界不清时先澄清。
- 用户最后指令高于 TODO、当前状态和历史摘要。
- 代码、验证、文档和 Git 具体规则统一见 `docs/AI协作/项目规则.md`。
