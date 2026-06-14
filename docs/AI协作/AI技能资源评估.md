# AI 技能资源评估

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档记录外部 AI skills / agents / MCP / rules 资源的筛选结论和项目安装清单；改已安装 skill、引入新资源平台或调整筛选标准时，必须同步 `.opencode/skills/`、`.opencode/opencode.json`、`OPENCODE.md`、`docs/AI协作/README.md`、`docs/AI协作/工具适配指南.md`、`docs/AI导航.md`、`docs/AI记忆/current_state.json`。

## 1. 筛选原则

| 原则 | 说明 |
|------|------|
| 项目相关 | 优先 Godot/GDScript、验证、文档同步、Git 提交、代码审查、MCP 工具评估 |
| 成熟来源 | 优先官方规范 / 文档、官方参考仓库、维护活跃且许可清晰的社区 marketplace |
| 渐进披露 | 只让 skill 名称和描述常驻上下文，完整流程按需加载 |
| 本地可控 | 优先安装为项目级 `.opencode/skills/<name>/SKILL.md` / `.agents/skills/<name>/SKILL.md` / `.claude/` 工具，来源保留在 `.opencode/vendor/ai-resources/` |
| 安全默认 | 不引入 MCP token、用户本机绝对路径或无边界写权限；外部 hooks / rules 若与本项目规则冲突，以 `AGENTS.md` 与 ADR 为准 |

## 2. 已检索来源

| 来源 | 结论 |
|------|------|
| OpenCode Agent Skills 文档 | 确认 `.opencode/skills/<name>/SKILL.md`、frontmatter 字段、命名规则和按需加载机制 |
| Claude Code Skills 文档 | 借鉴 bundled `/run`、`/verify`、skill-creator、动态验证和渐进披露模式 |
| `anthropics/skills` | 官方示例成熟，重点参考 `skill-creator`、`mcp-builder`、`webapp-testing`、文档类 skill 的组织方式；未直接复制大体量文档技能 |
| `agentskills.io` | 确认 Agent Skills 是跨工具开放格式，适合长期沉淀项目级技能 |
| `modelcontextprotocol/servers` 与 MCP Registry | 参考官方 MCP 服务器分类和安全提示；当前不新增项目级 MCP 服务，避免权限和本机路径问题 |
| `punkpeye/awesome-mcp-servers` / Glama MCP 目录 | 作为后续 MCP 发现入口；抽样 Godot MCP 诊断 / 测试资源后，优先本地化流程，不批量安装 |
| `wshobson/agents` | 成熟多工具 marketplace，参考 `godot-gdscript-patterns`、`code-review-excellence`、`architecture-decision-records`、`github-actions-templates`、`block-no-verify-hook` 等技能模式 |
| `PatrickJS/awesome-cursorrules` | 参考 anti-overengineering、anti-sycophancy、PR review、游戏/图形规则等提示模式；不直接安装 Cursor `.mdc` 文件 |
| Context7 / Ref Tools / GitMCP | 可作为用户级文档查询候选；当前不进仓库配置，避免网络 / 权限和维护负担 |

## 3. 已安装 Skills

| Skill | 路径 | 用途 |
|-------|------|------|
| `godot-gdscript` | `.opencode/skills/godot-gdscript/SKILL.md` | Godot 4.6.3 + typed GDScript 实现；强化数据驱动、autoload、InputMap、MVP/full client 边界 |
| `godot-scene-validation` | `.opencode/skills/godot-scene-validation/SKILL.md` | 使用 `tools/godot_bridge.py` 与数据校验做场景树 / headless / 引擎版本验证 |
| `godot-test-diagnostics` | `.opencode/skills/godot-test-diagnostics/SKILL.md` | Godot 测试与诊断流程；覆盖 GUT/GdUnit4 规划、headless 失败、场景 / 脚本错误、日志归因和未来 CI 测试门禁 |
| `project-doc-sync` | `.opencode/skills/project-doc-sync/SKILL.md` | 规则、ADR、AI 记忆、知识库索引和长期文档同步流程 |
| `safe-git-commit` | `.opencode/skills/safe-git-commit/SKILL.md` | 执行 ADR #52 的安全提交流程，避免误 stage 用户脏改或 `DRAFT/` |
| `code-review-factual` | `.opencode/skills/code-review-factual/SKILL.md` | 事实型代码审查；没发现问题就明确说没有，不硬找问题 |
| `ai-resource-curator` | `.opencode/skills/ai-resource-curator/SKILL.md` | 未来继续评估 / 安装 AI skill、agent、plugin、MCP、rules 的筛选流程 |
| `mcp-tool-evaluation` | `.opencode/skills/mcp-tool-evaluation/SKILL.md` | 评估 MCP server 是否应项目级 / 用户级安装，控制权限和密钥风险 |

## 4. 外部整包来源与正式安装映射

这些资源以 Git submodule 形式放在 `.opencode/vendor/ai-resources/`，用于保留上游来源、许可证和后续更新基准。已按各自 README 安装 AI 工具入口；模板、starter project、示例、生产状态等杂项不安装。

| 资源 | 上游路径 | 正式安装 | 未安装 |
|------|----------|----------|--------|
| `jame581/GodotPrompter` | `.opencode/vendor/ai-resources/GodotPrompter` | OpenCode plugin：`.opencode/opencode.json` `plugin` 指向上游 `.opencode/plugins/godot-prompter.js`，由 plugin 注册 GodotPrompter skills | `.cursor-plugin/`、`.claude-plugin/`、`.github/`、测试目录等平台/维护杂项 |
| `abagames/headless-godot-skill-kit` | `.opencode/vendor/ai-resources/headless-godot-skill-kit` | `.agents/skills/headless-godot/`，并把 `.agents/skills` 加入 `.opencode/opencode.json` `skills.paths` | `templates/godot-base/` starter project、skill 内 `tools/templates/` |
| `Donchitos/Claude-Code-Game-Studios` | `.opencode/vendor/ai-resources/Claude-Code-Game-Studios` | `.claude/agents/`、`.claude/skills/`、`.claude/hooks/`、`.claude/rules/`、`.claude/settings.json`、`.claude/statusline.sh`、`.claude/docs/` 非模板工具文档 | `.claude/docs/templates/`、仓库 `docs/examples/`、`CCGS Skill Testing Framework/`、`design/`、`production/`、`src/`、模板 / 示例 / 状态目录 |

## 4-A. 激活边界

- OpenCode 当前自动加载 `.opencode/skills` 与 `.agents/skills`，并通过本地 plugin 启用 GodotPrompter。
- Claude Code 当前通过根目录 `CLAUDE.md` 与 `.claude/` 使用 CCGS agents / skills / hooks / rules。
- `.opencode/vendor/ai-resources/` 不整体加入 `skills.paths`；只作为上游来源和更新基准。
- 外部 AI 工具输出建议必须先过本项目规则、词表、数据驱动、测试和文档同步要求。

## 5. 暂不安装的资源

| 资源 | 原因 |
|------|------|
| 大体量 office 文档技能（docx/pdf/pptx/xlsx） | 当前项目以 Markdown/Godot/data 为主，安装会增加维护面；需要导出发行材料时再评估 |
| Webapp / Playwright 测试技能 | 当前没有 Web 应用；MVP 走 Godot headless 和本地 bridge |
| 通用 Git/filesystem/fetch MCP | OpenCode 已有本地工具；项目级 MCP 会扩大权限面 |
| Memory MCP / Pensyve | 项目已有三层 AI 记忆文件；外部持久记忆需单独评估隐私和漂移 |
| Cursor `.mdc` 规则包 | 本项目已有三平台规则入口；只吸收模式，不再引入第四套规则源 |
| Playwright / Browserbase MCP | 当前没有 Web 应用，Godot 项目收益低且权限 / 依赖开销高 |
| 外部模板 / starter project / 示例项目 | 用户要求只安装 AI 工具；模板和示例容易污染本项目结构 |

## 6. 后续维护

- 新增 skill 前先用 `ai-resource-curator` 评估来源、许可证、权限和上下文成本。
- 涉及 MCP 的新增建议先用 `mcp-tool-evaluation` 判断项目级 / 用户级 / 暂不安装。
- 改 `.opencode/skills/` 后需要重启 OpenCode 才能保证运行中 session 看到新技能。
- 改 `.opencode/opencode.json`、`.agents/skills/`、`.claude/` 或 `.opencode/vendor/ai-resources/` 后，同步本安装清单并说明哪些工具被激活、哪些模板 / 示例未安装。
- 每次资源扫库后同步本文件、AI 记忆和当日会话日志。
