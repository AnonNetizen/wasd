# AI 技能资源评估

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档记录外部 AI skills / agents / MCP / rules 资源的筛选结论和项目安装清单；改已安装 skill、引入新资源平台或调整筛选标准时，必须同步 `.opencode/skills/`、`.opencode/opencode.json`、`OPENCODE.md`、`docs/AI协作/README.md`、`docs/AI协作/工具适配指南.md`、`docs/AI导航.md`、`docs/AI记忆/current_state.json`。

## 1. 筛选原则

| 原则 | 说明 |
|------|------|
| 项目相关 | 优先 Godot/GDScript、验证、文档同步、Git 提交、代码审查、MCP 工具评估 |
| 成熟来源 | 优先官方规范 / 文档、官方参考仓库、维护活跃且许可清晰的社区 marketplace |
| 渐进披露 | 只让 skill 名称和描述常驻上下文，完整流程按需加载 |
| 本地可控 | 安装为项目级 `.opencode/skills/<name>/SKILL.md`，不依赖运行时外部平台 |
| 安全默认 | 不引入自动运行脚本、写权限 MCP、token、用户本机绝对路径或宽权限 hook |

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

## 4. 隔离安装的外部整包

这些资源以 Git submodule 形式放在 `.opencode/vendor/ai-resources/`，供人工审阅和后续摘取模式；它们不在 `.opencode/opencode.json` 的 `skills.paths` 中，OpenCode 不会自动加载其中 skills、hooks、commands 或权限配置。

| 资源 | 路径 | 当前用途 | 许可 |
|------|------|----------|------|
| `jame581/GodotPrompter` | `.opencode/vendor/ai-resources/GodotPrompter` | Godot skills、agents、GDScript / testing / debugging / UI / resource 等模式参考 | MIT |
| `abagames/headless-godot-skill-kit` | `.opencode/vendor/ai-resources/headless-godot-skill-kit` | Headless Godot 场景编辑、测试、导出流程参考 | MIT |
| `Donchitos/Claude-Code-Game-Studios` | `.opencode/vendor/ai-resources/Claude-Code-Game-Studios` | 大型游戏工作室式 agents / skills / workflow / gate 模式参考 | MIT |

## 5. 暂不安装的资源

| 资源 | 原因 |
|------|------|
| 大体量 office 文档技能（docx/pdf/pptx/xlsx） | 当前项目以 Markdown/Godot/data 为主，安装会增加维护面；需要导出发行材料时再评估 |
| Webapp / Playwright 测试技能 | 当前没有 Web 应用；MVP 走 Godot headless 和本地 bridge |
| 通用 Git/filesystem/fetch MCP | OpenCode 已有本地工具；项目级 MCP 会扩大权限面 |
| Memory MCP / Pensyve | 项目已有三层 AI 记忆文件；外部持久记忆需单独评估隐私和漂移 |
| Cursor `.mdc` 规则包 | 本项目已有三平台规则入口；只吸收模式，不再引入第四套规则源 |
| Playwright / Browserbase MCP | 当前没有 Web 应用，Godot 项目收益低且权限 / 依赖开销高 |

## 6. 后续维护

- 新增 skill 前先用 `ai-resource-curator` 评估来源、许可证、权限和上下文成本。
- 涉及 MCP 的新增建议先用 `mcp-tool-evaluation` 判断项目级 / 用户级 / 暂不安装。
- 改 `.opencode/skills/` 后需要重启 OpenCode 才能保证运行中 session 看到新技能。
- 改 `.opencode/vendor/ai-resources/` 后只表示外部资源可供审阅；除非同步修改 `.opencode/opencode.json`，否则不会自动启用。
- 每次资源扫库后同步本文件、AI 记忆和当日会话日志。
