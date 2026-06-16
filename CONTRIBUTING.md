# 贡献指南

> 欢迎参与 **wasd**！本项目以「数据驱动 + AI 友好工程」为核心，所有贡献者（包括 AI agent）都需遵守本指南。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是协作与新机器 setup 入口；改工具链、提交流程、运行依赖或文档同步要求时，必须同步 `README.md`、`AGENTS.md`、`docs/AI导航.md`、`docs/CICD规划.md`、规则自检清单。

---

## 零、新机器 setup（一次性，clone 后必做）

> 仓库级 git 配置存在 `.git/config`，**不会随 clone 同步**；新机器 clone 后必须重做这几步，否则中文文件名会显示为 `\xxx` 转义、commit 模板也不会生效。

```bash
# 1. clone 仓库
git clone <repo-url>
cd wasd

# 2. 仓库级 git 配置（必须）
git config --local core.quotepath false      # 中文文件名正常显示
git config --local commit.template .gitmessage  # 启用 Conventional Commits 模板

# 3. 全局 git 身份（如果新机器还没配过）
git config --global user.name  "<your name>"
git config --global user.email "<your email>"
```

**运行时依赖**（按需安装，纯文档协作可跳过）：

| 工具 | 何时需要 |
|------|---------|
| **CodeBuddy IDE** | 想用项目级 subagents / slash commands（`.codebuddy/agents/`、`.codebuddy/commands/`）|
| **OpenAI Codex CLI** | 想用 Codex 平台配置（`.codex/agents/`、`.codex/commands/`、`.codex/rules/`）|
| **OpenCode** | 想用 OpenCode 协作；入口见 `OPENCODE.md` 与 `.opencode/opencode.json` |
| **Godot 4.6.3** | 真正运行 / 调试 `client/`（M1 起）|
| **Python 3.10+** | 跑 `tools/sync_contracts.py`、`tools/validate_data.py`、`tools/docs_health_check.py` 与后续工具脚本 |
| **gdtoolkit / GUT** | M1 之后的 lint 与单测（详见 `docs/测试策略.md`）|

**AI agent 第一件事**：读 `AGENTS.md` → `docs/AI协作/快速开工.md` → `docs/AI记忆/current_state.json`，需要长期背景时再读 `docs/AI记忆/项目记忆.md`，无需翻历史聊天即可续接。

**换 AI 工具也行**：项目核心资产与工具无关。Codex / OpenCode / Claude Code / Aider / Cursor / Windsurf / ChatGPT 都能用；Codex 见 `CODEX.md`，OpenCode 见 `OPENCODE.md`，其他工具配法见 [`docs/AI协作/工具适配指南.md`](docs/AI协作/工具适配指南.md)。

**用户级 skill `ai-indie-game-framework`**：装在 `~/.codebuddy/skills/`，与本仓库**无关**——它是为「以后开新游戏项目」准备的方法论。继续做本项目**不需要**它；想在新机器另起炉灶才需要手动复制该目录。

---

## 一、动手前必读

按优先级顺序阅读：

1. [`AGENTS.md`](AGENTS.md) —— **所有 AI agent 的通用开工入口**
2. [`docs/AI协作/快速开工.md`](docs/AI协作/快速开工.md) + [`docs/AI记忆/current_state.json`](docs/AI记忆/current_state.json) —— 低 token 热路径与机器当前状态
3. 当前平台编码规则入口 —— CodeBuddy 读 [`.codebuddy/rules/game-coding-rules.md`](.codebuddy/rules/game-coding-rules.md)，Codex 读 [`.codex/rules/game-coding-rules.md`](.codex/rules/game-coding-rules.md)，OpenCode 读 [`.opencode/rules/game-coding-rules.md`](.opencode/rules/game-coding-rules.md)，其他 agent 无专属入口时读 `.codebuddy/rules/game-coding-rules.md`
4. [`docs/AI导航.md`](docs/AI导航.md) —— 项目地图与扩展点速查
5. 按任务补读：[`docs/词表与契约.md`](docs/词表与契约.md)、[`docs/游戏设计文档.md`](docs/游戏设计文档.md)、[`docs/代码文档规范.md`](docs/代码文档规范.md)、[`docs/决策记录.md`](docs/决策记录.md)、[`docs/修改建议.md`](docs/修改建议.md)、[`docs/AI记忆/项目记忆.md`](docs/AI记忆/项目记忆.md)

> AI agent 工作前请按 `docs/AI导航.md` 定位，避免盲目全仓搜索；在新环境续接对话前，先读快速开工与 `current_state.json`，长期背景按需读取 `项目记忆.md`。

---

## 二、开发流程

### 1. 选定任务类型，按对应扩展点修改
参见 `docs/AI导航.md` 第 4 节「扩展点速查」。常见入口（数据/资源路径基于 `client/`，对应 Godot `res://`）：

| 任务 | 入口 |
|------|------|
| 加敌人 / 遗物 / 道具 | 改 `client/data/*.json`（即 `res://data/`），**不改逻辑** |
| 改数值 | 只改 `client/data/`，**绝不改代码常量** |
| 加面向玩家文本 | 加 `client/locale/strings.csv` 的 key + 译文 |
| 加设置项 | `Settings` 加配置 + UI 控件 |
| 加埋点 | 调用 `Analytics.track_event(name, params)` |
| 加效果原语 | **先在 `docs/词表与契约.md` 登记**，再实现，最后在数据中使用 |

### 2. 红线入口（不重复正文）

红线权威在 `AGENTS.md` 与当前平台编码规则入口；本文件不复制完整规则，避免多处漂移。贡献前确认：数据 / 文案 / 输入 / 约定字符串走权威通道，横向能力走统一 autoload，`draft/` / `DRAFT/` 不碰。

完整自检清单见当前平台编码规则入口末尾。

### 3. 文档同步（元规则 19/20/24）
**新规则 / 决策 / 设计变更必须按 `docs/AI协作/文档维护指南.md` 同步到对应权威文档**。代码模块 / 公共 API / 数据 schema / 依赖方向变化优先同步 `docs/代码文档规范.md` 与对应 `docs/代码/` 模块文档；重要对话 / 决策结束后同步 AI 记忆与当日会话日志。

文档不同步等同于未完成。

---

## 三、Git 约定

### 1. Commit 信息风格（Conventional Commits）

```
<type>(<scope>): <subject>
```

**type**：`feat` / `fix` / `docs` / `data` / `locale` / `refactor` / `perf` / `style` / `chore` / `ci` / `test` / `revert`

> Commit 模板已在第零节启用（`git config --local commit.template .gitmessage`），无需重复配置。

示例：
```
feat(weapon): 添加 split 效果原语
data(relics): 新增锋利弹头与急速射击
docs(adr): 记录暂停功能实现约定
```

### 2. 分支策略
- `main`：可运行的稳定分支
- 功能开发用 `feat/xxx` / `fix/xxx` / `docs/xxx` 分支，PR 合入 `main`

### 3. 行尾符 / 编码
仓库已通过 `.gitattributes` 与 `.editorconfig` 锁定行尾符（统一 LF）与编码（UTF-8），**无需在本地另行配置 `core.autocrlf`**。

### 4. 中文文件名显示
已在第零节配置 `core.quotepath=false`。如未做或显示转义码，回看本文件第零节。

### 5. AI 自动提交策略

- AI 完成大更改后默认自动 commit：跨多文件功能 / 工具 / CI / 规则 / ADR / 数据 schema / 代码模块 / 重要文档同步等可独立回滚的变更。
- 细微改动不自动 commit：拼写、单行措辞、小范围说明、只读诊断、临时验证或用户明确说“先别提交”的改动。
- 大型代码改动提交前必须追加事实型 code review；细微改动不触发正式 review。
- 自动 commit 前必须执行 `git status --short`、`git diff`、`git log --oneline -10`，跑对应验证，只 stage 本次任务明确修改的文件。
- 禁止提交用户已有脏改动、其他 agent 改动、`draft/` / `DRAFT/` 内容、未确认临时文件或本机私有配置；无法干净拆分时先问用户。
- commit message 使用 Conventional Commits；禁止 `--no-verify`，除非用户明确批准且 message 写明原因。

---

## 四、PR Checklist（提交前自检）

当前 GitHub Actions 已启用 Stage 1 `docs-check`：PR / `main` push 会自动检查契约同步、数据 / locale、文档健康和 whitespace diff。它暂不跑 Godot、GUT、黄金回放或平衡 sim。

本地提交前建议先跑：

```bash
python tools/sync_contracts.py --check
python tools/validate_data.py
python tools/docs_health_check.py
```

- [ ] 没有硬编码可调数值（都在 `res://data/`）？
- [ ] 没有硬编码玩家可见文本（都用 `tr()` 文本键）？
- [ ] 玩家偏好都走 `Settings` 单例？
- [ ] 新遗物/道具是加数据而非加逻辑分支？
- [ ] 高频实体用了对象池？
- [ ] 约定字符串都来自 `docs/词表与契约.md` 且以常量引用？
- [ ] 改词表后是否已运行 `python tools/sync_contracts.py` 并确认 `--check` 通过？
- [ ] 改数据 / 文案后是否已运行 `python tools/validate_data.py`？
- [ ] 新代码使用类型化 GDScript？
- [ ] 已更新 `docs/AI导航.md` / `docs/决策记录.md` 等相关文档？
- [ ] 本次新规则 / 设计变更已同步到对应文档？

---

## 五、报告问题 / 提议

- **bug / 功能请求**：使用 GitHub Issue（`.github/ISSUE_TEMPLATE/` 内有模板）。
- **设计建议**：先在 `docs/修改建议.md` 起草（当前待决策为 A~D；J~R 已归档），由维护者评审后转为决策（写入 `docs/决策记录.md`）或采纳实施。

---

感谢贡献 🎮
