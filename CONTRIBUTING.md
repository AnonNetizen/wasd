# 贡献指南

> 欢迎参与 **wasd**！本项目以「数据驱动 + AI 友好工程」为核心，所有贡献者（包括 AI agent）都需遵守本指南。

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
| **Godot 4.6.3** | 真正运行 / 调试 `client/`（M1 起）|
| **Python 3.10+** | 跑 `tools/sync_contracts.py` 等同步脚本（脚本将随 M1 落地）|
| **gdtoolkit / GUT** | M1 之后的 lint 与单测（详见 `docs/测试策略.md`）|

**AI agent 第一件事**：读 `AGENTS.md` → `docs/AI记忆/项目记忆.md`，无需翻历史聊天即可续接。

**不用 CodeBuddy 也行**：项目核心资产与工具无关。Claude Code / Aider / Cursor / Windsurf / ChatGPT 都能用，每种工具的现成配法见 [`docs/AI协作/工具适配指南.md`](docs/AI协作/工具适配指南.md)（一次性，5 分钟搞定）。

**用户级 skill `ai-indie-game-framework`**：装在 `~/.codebuddy/skills/`，与本仓库**无关**——它是为「以后开新游戏项目」准备的方法论。继续做本项目**不需要**它；想在新机器另起炉灶才需要手动复制该目录。

---

## 一、动手前必读

按优先级顺序阅读：

1. [`.codebuddy/rules/game-coding-rules.md`](.codebuddy/rules/game-coding-rules.md) —— **强制编码规则**
2. [`docs/AI导航.md`](docs/AI导航.md) —— 项目地图与扩展点速查
3. [`docs/词表与契约.md`](docs/词表与契约.md) —— 约定字符串白名单
4. [`docs/游戏设计文档.md`](docs/游戏设计文档.md) —— 完整设计
5. [`docs/决策记录.md`](docs/决策记录.md) —— 既定决策
6. [`docs/修改建议.md`](docs/修改建议.md) —— 待决策项
7. [`docs/AI记忆/项目记忆.md`](docs/AI记忆/项目记忆.md) —— 跨会话/跨机器的 AI 协作记忆

> AI agent 工作前请按 `docs/AI导航.md` 定位，避免盲目全仓搜索；在新环境续接对话前，先读 `docs/AI记忆/项目记忆.md`。

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

### 2. 三大红线（最易踩坑，必查）
- ❌ 硬编码可调数值、玩家可见文本、按键、约定字符串
- ❌ 为每个遗物/道具写独立分支
- ✅ 高频实体用对象池；相机不开 limit / drag margin

完整自检清单见 `.codebuddy/rules/game-coding-rules.md` 末尾。

### 3. 文档同步（元规则 19/20）
**新规则 / 决策 / 设计变更必须同步到对应文档**：
- 新规则 → `.codebuddy/rules/game-coding-rules.md`
- 新决策 → `docs/决策记录.md`
- 设计变更 → `docs/游戏设计文档.md` + `docs/AI导航.md` + `docs/词表与契约.md`
- 重要对话/决策结束后 → `docs/AI记忆/项目记忆.md`（跨机器续接对话用）

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

---

## 四、PR Checklist（提交前自检）

- [ ] 没有硬编码可调数值（都在 `res://data/`）？
- [ ] 没有硬编码玩家可见文本（都用 `tr()` 文本键）？
- [ ] 玩家偏好都走 `Settings` 单例？
- [ ] 新遗物/道具是加数据而非加逻辑分支？
- [ ] 高频实体用了对象池？
- [ ] 约定字符串都来自 `docs/词表与契约.md` 且以常量引用？
- [ ] 新代码使用类型化 GDScript？
- [ ] 已更新 `docs/AI导航.md` / `docs/决策记录.md` 等相关文档？
- [ ] 本次新规则 / 设计变更已同步到对应文档？

---

## 五、报告问题 / 提议

- **bug / 功能请求**：使用 GitHub Issue（`.github/ISSUE_TEMPLATE/` 内有模板）。
- **设计建议**：先在 `docs/修改建议.md` 起草（按现有 A~D / J~R 风格编号），由维护者评审后转为决策（写入 `docs/决策记录.md`）或采纳实施。

---

感谢贡献 🎮
