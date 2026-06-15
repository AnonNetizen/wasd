# AGENTS.md —— 给所有 AI agent 的开工说明

> 任何 AI agent 在本项目动手前，**必须先按下面顺序读完这 5 份文件**，再开始任何任务。
> 这是规则 14 与 ADR #15 的明文化入口；忽略此约定 = 违反项目规则。
>
> **AI 修改说明**：修改本文件前必须有用户明确授权，并先读 `docs/AI协作/文档维护指南.md`。本文件是所有 AI agent 的通用开工入口；改开工步骤、红线、subagent、slash command、skill 或平台入口时，必须同步 `CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、`.codebuddy/`、`.codex/`、`.opencode/`、`docs/AI导航.md`、`docs/AI协作/README.md`、`docs/AI协作/工具适配指南.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

> 🆕 **新机器 clone 后第一次开工**：先按 [`CONTRIBUTING.md` 第零节「新机器 setup」](CONTRIBUTING.md) 做一次性 git 配置（`core.quotepath` / `commit.template` / 全局身份），再回来读下面 5 步。否则中文文件名会显示为转义码、commit 模板不会生效。
>
> 🛠️ **换 AI 工具？** `AGENTS.md` 是通用入口；Claude Code 可先读 [`CLAUDE.md`](CLAUDE.md)，Codex 可先读 [`CODEX.md`](CODEX.md)，OpenCode 可先读 [`OPENCODE.md`](OPENCODE.md)，其他工具看 [`docs/AI协作/工具适配指南.md`](docs/AI协作/工具适配指南.md)。平台入口只做加载适配，不能放宽项目核心规则。

---

## 🚦 开工 5 步（按顺序，不要跳）

1. **本文件**（`AGENTS.md`）—— 通用入口；若从 Claude / Codex / OpenCode 进入，也可先读 `CLAUDE.md` / `CODEX.md` / `OPENCODE.md` 再回到这里
2. **`docs/AI记忆/项目记忆.md` + `docs/AI记忆/current_state.json`** —— **跨会话/跨机器的项目长时记忆与机器当前状态**
   - 项目快照（v1.5、Godot 4.6.3 + GDScript、文档阶段）
   - 60 条 ADR 摘要
   - 待决策项（A~E）
   - 工具链与基础设施现状
   - **下一步候选**以 `current_state.json` 为机器可读权威；它只提供候选方向，不能覆盖用户最后明确指令
3. **强制编码规则** —— 按当前平台读取：CodeBuddy 读 `.codebuddy/rules/game-coding-rules.md`；Codex 读 `.codex/rules/game-coding-rules.md`；OpenCode 读 `.opencode/rules/game-coding-rules.md`；其他 agent 没有专属规则入口时读 `.codebuddy/rules/game-coding-rules.md` 作为项目规则源
4. **`docs/AI导航.md`** —— 项目地图、扩展点速查、系统依赖图
5. **按当前任务读下列其一**：
   - 高频任务 → `docs/AI协作/任务模板/<任务>.md`
   - 改约定字符串 → `docs/词表与契约.md`
   - 改设计 → `docs/游戏设计文档.md`
   - 改既定决策 → `docs/决策记录.md`
   - 写/改测试 → `docs/测试策略.md`

读完这 5 步就能"接得上"，无需翻历史聊天。

---

## ⛓️ 四条不可妥协的规则（红线节选）

完整列表见当前平台的编码规则入口与 `docs/AI导航.md` 第 6 节红线。这里只抽最易踩的：

1. **数据驱动**：可调数值进 `client/data/`，平表数值优先 CSV、复杂配置优先 JSON，字段说明同步 `client/data/README.md`；玩家可见文本走 `tr("key")` / `client/locale/strings.csv` 且多语言规则同步 `client/locale/README.md`；按键走 InputMap action；约定字符串来自 `docs/词表与契约.md` 白名单且以**自动生成的常量**引用。
2. **统一 autoload**：随机 `RNG.<stream>` / 时间 `GameClock` / 流程 `GameState` / UI 弹窗 `UIManager` / 高频实体 `PoolManager` / 伤害 `Combat.apply_damage` / 持续效果 `StatusEffect` / 存档 `SaveManager` / 音频 `AudioManager`。`SaveManager` 必须支持 `meta` 局外成长和 `run` 暂停退出续局，并具备标准头字段（含 `data_hash`）、版本迁移、原子写入、备份回退和损坏隔离。**禁止**绕过这些走原始 API。
3. **改完同步文档**：新规则 → 规则文件；新决策 → ADR；设计变更 → GDD + AI 导航 + 词表；重要对话 → `docs/AI记忆/项目记忆.md` + `docs/AI记忆/current_state.json` + 当日会话日志（见规则 14-B）。
4. **`draft/` 人工草稿禁区**：`draft/`（含大小写变体如 `DRAFT/`）内是用户人工草稿，AI 默认不得读取、搜索、修改、整理、格式化或引用；只有用户明确点名授权处理该目录时才可进入。遵守此规则是默认行为，AI 不需要在每次回复中主动声明。

## 🗣️ 沟通语言

AI 面向用户的回复、计划、总结、提问与变更说明默认使用中文。仅在用户明确要求其他语言、引用代码 / API / 命令 / 日志 / 错误原文、编辑目标文件已有语言要求、或对外发布文本需要其他语言时，才使用对应语言。

## 🧭 沟通与需求评估

- 用户问“有没有问题 / 风险 / 看一下”时，必须基于事实审查；没有发现实际问题就明确说没有问题或未发现问题，禁止为了显得有用而硬找问题、过度优化或提出无必要改动。
- 用户提出新需求后，先简短反馈该需求在本项目里的落地前景：价值、性价比、实现复杂度和主要风险；如果需求明显有问题、与既定 ADR 冲突、性价比低或存在重大隐患，必须先直接说明并给替代建议，不要闷声实现到最后。
- 发生上下文总结 / 压缩 / 恢复后，必须先以用户最后一条明确指令重新对齐当前任务；`current_state.json`、会话摘要或 `Next Steps` 只作候选参考，不能被当作授权执行。若恢复摘要与用户最后指令冲突或授权边界不清，先问一句再动手。

## 🧩 AI Git 提交策略

- **大更改自动 commit**：完成跨多文件功能 / 工具 / CI / 规则 / ADR / 数据 schema / 代码模块 / 重要文档同步等“可独立回滚”的变更后，AI 默认自行创建一次 git commit，无需用户再次提醒。
- **细微改动不 commit**：拼写、单行措辞、小范围说明、只读诊断、临时验证或用户明确说“先别提交”的改动，不自动 commit；最终回复说明“未提交，原因是细微改动/用户要求”。
- **提交前强制检查**：自动 commit 前必须先看 `git status --short`、`git diff`、`git log --oneline -10`，跑本次变更对应验证，且只 stage AI 本次任务明确修改的文件。
- **禁止带入无关改动**：不得提交用户已有脏改动、其他 agent 的改动、`draft/` / `DRAFT/` 内容、未确认的临时文件或本机私有配置；若无法干净拆分，应停止并询问用户。
- **提交信息**：使用 Conventional Commits（见 `.gitmessage` / `CONTRIBUTING.md`），简洁说明范围；不得使用 `--no-verify`，除非用户明确批准且 commit message 写明原因。

---

## 🛠️ 高频任务直通车

如果你的任务是下面这些之一，直接套对应模板（不必重新摸索）：

| 任务 | 模板 |
|------|------|
| 加遗物 / 道具 | `docs/AI协作/任务模板/加遗物.md`（或用 `/new-relic` 命令） |
| 加敌人 | `docs/AI协作/任务模板/加敌人.md` |
| 加效果原语 | `docs/AI协作/任务模板/加效果原语.md` |
| 加设置项 | `docs/AI协作/任务模板/加设置项.md` |
| 加埋点 | `docs/AI协作/任务模板/加埋点.md` |
| 调数值 | `docs/AI协作/任务模板/调数值.md` |
| 加本地化文本 | `docs/AI协作/任务模板/加本地化文本.md` |

任务不在模板里 → 按 `docs/AI协作/上下文预算.md` 决定读取范围（**禁止盲目全仓搜索**）。

## 🤝 子智能体（Subagents，可主动调用）

复杂或专业任务直接转给对应 subagent，避免主对话被污染：

| Subagent | 何时调用 | 定义位置 |
|----------|---------|---------|
| `data-author` | 加 / 改数据条目（遗物 / 敌人 / locale / 设置 / 埋点） | `.codebuddy/agents/data-author.md` / `.codex/agents/data-author.md` / `.opencode/agents/data-author.md` |
| `contract-validator` | 改了词表、想检查代码常量 / 裸字符串 / id 同步 | `.codebuddy/agents/contract-validator.md` / `.codex/agents/contract-validator.md` / `.opencode/agents/contract-validator.md` |
| `balancer` | 跑回放回归 / sim / 数值平衡建议 | `.codebuddy/agents/balancer.md` / `.codex/agents/balancer.md` / `.opencode/agents/balancer.md` |
| `game-designer` | 评估玩法 / 系统 / 机制设计的优缺点、参考对象、风险和落地路径 | `.codebuddy/agents/game-designer.md` / `.codex/agents/game-designer.md` / `.opencode/agents/game-designer.md` |
| `numeric-designer` | 设计生命、伤害、成长曲线、掉落、局外成长成本、难度波次等数值模型 | `.codebuddy/agents/numeric-designer.md` / `.codex/agents/numeric-designer.md` / `.opencode/agents/numeric-designer.md` |
| `ip-designer` | 设计世界观、主题、角色、阵营、怪物生态和长期 IP 内容框架 | `.codebuddy/agents/ip-designer.md` / `.codex/agents/ip-designer.md` / `.opencode/agents/ip-designer.md` |
| `copywriter-packager` | 包装 UI / 遗物 / 道具 / 商店页 / 宣传语文案，输出中英文草案与 locale 建议 | `.codebuddy/agents/copywriter-packager.md` / `.codex/agents/copywriter-packager.md` / `.opencode/agents/copywriter-packager.md` |
| `ui-art-designer` | 设计 HUD、菜单、升级选择、局外成长界面、图标、信息层级和 UI 美术 brief | `.codebuddy/agents/ui-art-designer.md` / `.codex/agents/ui-art-designer.md` / `.opencode/agents/ui-art-designer.md` |
| `game-art-designer` | 设计角色、敌人、场景、子弹、特效、图标、调色板和资产 brief | `.codebuddy/agents/game-art-designer.md` / `.codex/agents/game-art-designer.md` / `.opencode/agents/game-art-designer.md` |
| `marketing-strategist` | 设计定位、卖点、Steam 页面、预告片、截图、Demo、节日投放和传播优势 | `.codebuddy/agents/marketing-strategist.md` / `.codex/agents/marketing-strategist.md` / `.opencode/agents/marketing-strategist.md` |

支持 subagent 的平台用原生 agent/task 调度；不支持时，把对应 `.md` 当 prompt 模板读，不要跳过角色流程。

## ⚡ 项目级斜杠命令（Slash Commands）

| 命令 | 用途 | 定义位置 |
|------|------|---------|
| `/sync-contracts` | 跑词表→代码常量同步流水线 | `.codebuddy/commands/sync-contracts.md` / `.codex/commands/sync-contracts.md` / `.opencode/commands/sync-contracts.md` |
| `/new-relic <概念>` | 交互式加遗物 | `.codebuddy/commands/new-relic.md` / `.codex/commands/new-relic.md` / `.opencode/commands/new-relic.md` |
| `/run-replay-regression` | 跑黄金回放回归 | `.codebuddy/commands/run-replay-regression.md` / `.codex/commands/run-replay-regression.md` / `.opencode/commands/run-replay-regression.md` |
| `/health-check` | 项目健康度报告 | `.codebuddy/commands/health-check.md` / `.codex/commands/health-check.md` / `.opencode/commands/health-check.md` |
| `/update-memory` | 显式兜底触发记忆更新 | `.codebuddy/commands/update-memory.md` / `.codex/commands/update-memory.md` / `.opencode/commands/update-memory.md` |

OpenCode 命令由 `.opencode/opencode.json` 的 `command` 字段注册；不支持 slash command 的平台按对应 `.md` 步骤手动执行即可。

## 🧠 项目级 Skills（三平台同步）

项目级 skills 必须在 `.codebuddy/skills/<name>/SKILL.md`、`.codex/skills/<name>/SKILL.md` 与 `.opencode/skills/<name>/SKILL.md` 三处同步；OpenCode 由 `.opencode/opencode.json` 注册 `.opencode/skills` 路径，Codex / CodeBuddy 读取各自目录下同名 skill 作为项目级 prompt 模板。当前已安装：`godot-gdscript`、`godot-scene-validation`、`godot-test-diagnostics`、`playtest-review`、`project-doc-sync`、`safe-git-commit`、`code-review-factual`、`ai-resource-curator`、`mcp-tool-evaluation`。

外部 AI 库（GodotPrompter、headless-godot-skill-kit、Claude-Code-Game-Studios）中对本项目有用的 Godot、headless 验证与试玩复盘经验已吸收到上述项目级 skills；不再保留 `.agents/skills` 适配层或 `.opencode/vendor/ai-resources/` submodule。外部建议若与本项目 GDD / ADR / 规则冲突，以本项目为准。筛选依据与来源记录见 `docs/AI协作/AI技能资源评估.md`。

---

## 📝 改完之后

按编码规则末尾的「自检清单」逐条核对；按 `docs/测试策略.md` §7 表履行测试义务；改了重要内容就更新 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与当日会话日志（按项目记忆第 9 节维护）。

不确定写什么？参照本目录最近的 ADR 风格（`docs/决策记录.md`）：**一句话决策 + 一句话理由**。

---

> 本文件由项目维护者人为定义；AI agent 不得未经允许修改。
> 若在新平台/新 IDE 中此文件未被自动加载，请用户在对话开始时显式提示："先读 `AGENTS.md`"。
