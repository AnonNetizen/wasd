# AI 技能资源评估

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档记录外部 AI skills / agents / MCP / rules 资源的筛选结论和项目安装清单；改已安装 skill、引入新资源平台或调整筛选标准时，必须同步 `.codebuddy/skills/`、`.codex/skills/`、`.opencode/skills/`、`.opencode/opencode.json`、`OPENCODE.md`、`docs/AI协作/README.md`、`docs/AI协作/工具适配指南.md`、`docs/AI导航.md`、`docs/AI记忆/current_state.json`。

## 1. 筛选原则

| 原则 | 说明 |
|------|------|
| 项目相关 | 优先 Godot/GDScript、验证、文档同步、Git 提交、代码审查、MCP 工具评估 |
| 成熟来源 | 优先官方规范 / 文档、官方参考仓库、维护活跃且许可清晰的社区 marketplace |
| 渐进披露 | 只让 skill 名称和描述常驻上下文，完整流程按需加载 |
| 本地可控 | 项目级 skill 同名同步安装为 `.codebuddy/skills/<name>/SKILL.md`、`.codex/skills/<name>/SKILL.md` 与 `.opencode/skills/<name>/SKILL.md`；外部资源只吸收必要流程，不保留整包 vendor、reference skill 或外部 hooks |
| 安全默认 | 不引入 MCP token、用户本机绝对路径或无边界写权限；外部 hooks / rules 若与本项目规则冲突，以 `AGENTS.md` 与 ADR 为准 |

## 2. 已检索来源

| 来源 | 结论 |
|------|------|
| OpenCode Agent Skills 文档 | 确认 `.opencode/skills/<name>/SKILL.md`、frontmatter 字段、命名规则和按需加载机制；项目内同步到 `.codebuddy/skills/` 与 `.codex/skills/` |
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
| `godot-gdscript` | `.codebuddy/skills/godot-gdscript/SKILL.md` / `.codex/skills/godot-gdscript/SKILL.md` / `.opencode/skills/godot-gdscript/SKILL.md` | Godot 4.6.3 + typed GDScript 实现；强化数据驱动、autoload、InputMap、MVP/full client 边界 |
| `godot-scene-validation` | `.codebuddy/skills/godot-scene-validation/SKILL.md` / `.codex/skills/godot-scene-validation/SKILL.md` / `.opencode/skills/godot-scene-validation/SKILL.md` | 使用 `tools/godot_bridge.py` 与数据校验做场景树 / headless / 引擎版本验证；已吸收 headless Godot CLI 安全规则 |
| `godot-test-diagnostics` | `.codebuddy/skills/godot-test-diagnostics/SKILL.md` / `.codex/skills/godot-test-diagnostics/SKILL.md` / `.opencode/skills/godot-test-diagnostics/SKILL.md` | Godot 测试与诊断流程；覆盖 GUT/GdUnit4 规划、headless 失败、场景 / 脚本错误、日志归因和未来 CI 测试门禁 |
| `playtest-review` | `.codebuddy/skills/playtest-review/SKILL.md` / `.codex/skills/playtest-review/SKILL.md` / `.opencode/skills/playtest-review/SKILL.md` | MVP / 完整项目试玩复盘、手感与配置调参评估、里程碑 readiness 和后续任务分级 |
| `project-doc-sync` | `.codebuddy/skills/project-doc-sync/SKILL.md` / `.codex/skills/project-doc-sync/SKILL.md` / `.opencode/skills/project-doc-sync/SKILL.md` | 规则、ADR、AI 记忆、知识库索引和长期文档同步流程 |
| `safe-git-commit` | `.codebuddy/skills/safe-git-commit/SKILL.md` / `.codex/skills/safe-git-commit/SKILL.md` / `.opencode/skills/safe-git-commit/SKILL.md` | 执行 ADR #52 的安全提交流程，避免误 stage 用户脏改或 `DRAFT/` |
| `code-review-factual` | `.codebuddy/skills/code-review-factual/SKILL.md` / `.codex/skills/code-review-factual/SKILL.md` / `.opencode/skills/code-review-factual/SKILL.md` | 事实型代码审查；没发现问题就明确说没有，不硬找问题 |
| `ai-resource-curator` | `.codebuddy/skills/ai-resource-curator/SKILL.md` / `.codex/skills/ai-resource-curator/SKILL.md` / `.opencode/skills/ai-resource-curator/SKILL.md` | 未来继续评估 / 安装 AI skill、agent、plugin、MCP、rules 的筛选流程 |
| `mcp-tool-evaluation` | `.codebuddy/skills/mcp-tool-evaluation/SKILL.md` / `.codex/skills/mcp-tool-evaluation/SKILL.md` / `.opencode/skills/mcp-tool-evaluation/SKILL.md` | 评估 MCP server 是否应项目级 / 用户级安装，控制权限和密钥风险 |

## 4. 外部资源吸收与删除结论

这些资源曾以 Git submodule 形式放在 `.opencode/vendor/ai-resources/`。根据 ADR #59，当前不再保留 vendor 整包或 reference skill；只把与本项目直接相关、且不冲突的流程吸收到三平台项目级 skills。模板、starter project、示例、生产状态、外部 hooks / plugin 和大批量外部 subagents 均删除。

| 资源 | 已吸收 | 已删除 / 未保留 |
|------|----------|-----------------|
| `jame581/GodotPrompter` | GDScript typed patterns、scene organization、Resource 注意事项、Godot testing 诊断口径，吸收到 `godot-gdscript` / `godot-test-diagnostics` | plugin、Cursor / Claude plugin、C#、3D、mobile、multiplayer、XR、server、addon、测试目录等非当前项目范围内容 |
| `abagames/headless-godot-skill-kit` | `--headless --path`、日志捕获、XDG 本地化、`.tscn` 不裸改、smoke/test 分离，吸收到 `godot-scene-validation` / `godot-test-diagnostics` | starter project、模板、独立 patch 脚本、外部 `.agents/skills/headless-godot` |
| `Donchitos/Claude-Code-Game-Studios` | 试玩报告、里程碑复盘、QA 计划的轻量流程，吸收到 `playtest-review`；专业角色范围由本项目已有 subagents 覆盖 | `.claude/` active hooks / rules / settings、49 个外部 agents、Unity / Unreal / live-ops / networking 专项、模板、示例、生产状态、源码 / 测试框架 |

## 4-A. 激活边界

- OpenCode 当前只自动加载 `.opencode/skills`；Codex / CodeBuddy 使用各自 `.codex/skills` 与 `.codebuddy/skills` 下的同名 skill。
- GodotPrompter、headless-godot-skill-kit 与 CCGS 不再作为 vendor 参考来源；不得重新加入 `skills.paths`，不得启用外部 hooks、plugin 或整包 subagents。
- 所有外部游戏设计建议必须先过本项目 `docs/游戏设计文档.md`、ADR 和规则；冲突时以本项目为准。
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
| 外部整包 active plugin / hooks / 大量 subagents / vendor reference 层 | 会制造重复上下文、平台配置膨胀和项目规则冲突；统一删除，只把有用流程吸收到项目级 skill |

## 6. 后续维护

- 新增 skill 前先用 `ai-resource-curator` 评估来源、许可证、权限和上下文成本。
- 涉及 MCP 的新增建议先用 `mcp-tool-evaluation` 判断项目级 / 用户级 / 暂不安装。
- 改 `.opencode/skills/` 后需要重启 OpenCode；改 `.codex/skills/` 或 `.codebuddy/skills/` 后需要开启新会话确认加载 才能保证运行中 session 看到新技能。
- 改 `.opencode/opencode.json`、`.codebuddy/skills/`、`.codex/skills/` 或 `.opencode/skills/` 后，同步本安装清单并说明哪些工具被激活、哪些外部内容被吸收或拒绝。
- 每次资源扫库后同步本文件、AI 记忆和当日会话日志。
