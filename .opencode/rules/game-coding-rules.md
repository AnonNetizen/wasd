# 游戏项目编码规则（OpenCode 入口）

> 本文件是 OpenCode 平台的规则入口，随 `.opencode/opencode.json` 的 `instructions` 加载。
> 完整项目规则正文与 CodeBuddy / Codex 保持同一核心语义：`.codebuddy/rules/game-coding-rules.md`、`.codex/rules/game-coding-rules.md`。
> 修改任一平台规则时，必须同步检查 `.codebuddy/rules/game-coding-rules.md`、`.codex/rules/game-coding-rules.md`、本文件、`AGENTS.md`、`OPENCODE.md`、`docs/AI协作/工具适配指南.md`、`docs/代码文档规范.md`。

## OpenCode 必守入口

1. 先读 `AGENTS.md` 的开工 5 步。
2. 再读 `.codebuddy/rules/game-coding-rules.md` 的完整规则正文；该文件通过 `.opencode/opencode.json` 一并加载，是 OpenCode 当前完整规则源。
3. 若 OpenCode 专属格式需要额外约束，只能在本文件追加“平台加载/工具使用”说明，不能放宽项目核心规则。

## OpenCode 平台约束

- `.opencode/agents/*.md` 是 OpenCode subagent 入口；角色语义必须与 `.codebuddy/agents/`、`.codex/agents/` 同名文件一致。
- `.opencode/commands/*.md` 是 OpenCode 命令步骤手册；命令注册在 `.opencode/opencode.json` 的 `command` 字段。
- `.opencode/opencode.json` 必须保留 `$schema: https://opencode.ai/config.json`，避免 OpenCode 启动时因配置字段错误失败。
- 改 `.opencode/` 后需要重启 OpenCode；运行中的 session 不会热重载配置。

## 核心红线速记

- 可调数值进 `client/data/*.json`，字段说明同步 `client/data/README.md`；玩家可见文本走 `tr("key")` / `client/locale/strings.csv`，多语言与占位符说明同步 `client/locale/README.md`；键盘按键、手柄按钮与手柄轴都走 InputMap action + `Settings` 重绑定；约定字符串来自 `docs/词表与契约.md` 且以生成常量引用。
- 随机走 `RNG.<stream>`，时间走 `GameClock`，流程走 `GameState`，UI 走 `UIManager`，池化走 `PoolManager`，伤害走 `Combat.apply_damage`，持续效果走 `StatusEffect`，存档走 `SaveManager`，音频走 `AudioManager`。
- 未来角色 / 道具 / 遗物可以突破默认玩法限制，但必须通过词表登记的 `capability`、content tag、effect / behavior primitive 或可复用 strategy 表达；禁止按 `character_id` / `relic_id` 写一次性特殊分支。
- 代码变更必须按 `docs/代码文档规范.md` 判断对应文档；长期模块、公共 API、数据 schema、依赖方向或测试义务变化时同步详细的 `docs/代码/` 模块文档与相关权威文档，禁止用自动抽取的简短摘要替代。
- 面向用户的回复默认中文；仅在用户明确要求、引用代码 / API / 命令 / 日志原文、目标文件语言要求或对外发布文本需要时使用其他语言。
- `draft/` / `DRAFT/` 是用户人工草稿禁区；除非用户明确点名授权，AI 不得读取、搜索、修改、整理、格式化、总结或引用其中内容，仓库级批量操作需排除该目录；这是默认行为，不需要每次主动汇报。
- `MinimumViableProduct/` 是 MVP 隔离实验区；MVP 文档与客户端代码都放在该目录内，不得混入完整项目根目录 `client/`。
- 改完同步文档：新规则进三个平台规则入口；新决策进 ADR；重要对话进 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与会话日志。
