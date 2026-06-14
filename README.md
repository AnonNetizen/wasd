# wasd —— 俯视角 Roguelike 弹幕生存

> 一款受《以撒的结合》与《吸血鬼幸存者》启发的俯视角 Roguelike 弹幕生存游戏。
> **当前状态：文档/框架设计阶段 + MVP 隔离实验区。** 完整项目 `client/` 已建立数值 / 文案配置入口，主要玩法代码仍在 `MinimumViableProduct/` 中试验。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。README 是仓库入口摘要；改项目状态、运行方式、目录结构或 AI 开工入口时，必须同步 `CONTRIBUTING.md`、`AGENTS.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

---

> ## 🤖 AI agent 开工提示
>
> **动手前请先读 [`AGENTS.md`](AGENTS.md) → [`docs/AI记忆/项目记忆.md`](docs/AI记忆/项目记忆.md) → [`docs/AI记忆/current_state.json`](docs/AI记忆/current_state.json)**。
> 项目有完整的跨会话/跨机器长时记忆系统，5 份文件读完就能接续之前的工作，无需翻历史聊天。

> ## 🧑‍💻 给用户：换 AI 工具完全 OK
>
> 项目文档与规则**与具体 AI 工具无关**——CodeBuddy / Codex / OpenCode / Claude Code / Aider / Cursor / Windsurf / ChatGPT 都能用。
> 换工具时看 [`docs/AI协作/工具适配指南.md`](docs/AI协作/工具适配指南.md)，里面针对每种工具都有现成的"复制粘贴"配法（一次性，5 分钟搞定）。
> 万能兜底：让 AI **先读 `AGENTS.md`** 即可。

---

## 一句话定位
WASD / 手柄左摇杆移动，方向键 / 手柄右摇杆或 D-pad 控制射击方向，**全自动开火**；在开放大地图中靠收集**主动道具 / 消耗品 / 被动遗物**滚雪球式变强，在敌群与机关中尽可能久地存活。

## 技术栈
- **引擎**：Godot 4.6.3
- **语言**：GDScript（强制类型化）
- **平台**：PC（键盘 + 手柄）

## 设计支柱
- **数据驱动**：所有可调数值集中在 `res://data/` 下的 JSON，字段说明见 `client/data/README.md`，零代码调参 + 热重载。
- **遗物 = 数据**：用「修正器 modifiers + 行为 behaviors」描述，新增遗物 = 加一条数据，不改逻辑。
- **扩展优先**：默认玩法规则不是硬编码上限；破限角色 / 道具走 capability、tag、primitive 或 strategy，不写一次性 id 分支。
- **代码-文档同源**：长期代码模块、公共 API、数据 schema 与扩展点变化必须同步 `docs/代码/` 模块文档。
- **三条横向基础设施**（框架阶段就内建）：
  - `Localization` —— 多语言本地化，所有玩家可见文本走 `tr("key")`，文案手册见 `client/locale/README.md`。
  - `Settings` —— 统一玩家偏好管理，信号驱动即时生效，持久化到 `user://settings.cfg`。
  - `Analytics` —— 数据埋点统一接口 `track_event()`，关键节点全留钩子。
- **AI 友好工程**：项目索引、词表白名单、数据校验、黄金样例、ADR、模板，让 AI agent 易读、易写、易扩展。

---

## 必读文档（按优先级）
| 文档 | 作用 | 何时读 |
|------|------|--------|
| [`AGENTS.md`](AGENTS.md) | **AI agent 通用开工入口** | 每次开始任务前 |
| [`.codebuddy/rules/game-coding-rules.md`](.codebuddy/rules/game-coding-rules.md) / [`.codex/rules/game-coding-rules.md`](.codex/rules/game-coding-rules.md) / [`.opencode/rules/game-coding-rules.md`](.opencode/rules/game-coding-rules.md) | **强制编码规则入口** | 每次写代码前，按当前平台选读 |
| [`docs/AI导航.md`](docs/AI导航.md) | 项目地图与扩展点速查 | 开始任何任务前 |
| [`docs/AI知识库索引.md`](docs/AI知识库索引.md) | AI 知识库总索引与权威层级 | 查文档关系或同步范围时 |
| [`docs/词表与契约.md`](docs/词表与契约.md) | 约定字符串白名单（stat/effect/event/key/action） | 写数据或常量时 |
| [`client/data/README.md`](client/data/README.md) | 完整项目数值配置手册 | 调数值或新增数据字段时 |
| [`client/locale/README.md`](client/locale/README.md) | 完整项目多语言文案配置手册 | 加文案、改翻译或新增语言时 |
| [`docs/游戏设计文档.md`](docs/游戏设计文档.md) | 完整 GDD（v1.5） | 了解整体设计 |
| [`docs/代码文档规范.md`](docs/代码文档规范.md) | 代码变更与对应文档的同步规范 | 写/改代码前 |
| [`docs/决策记录.md`](docs/决策记录.md) | 既定决策与原因（ADR） | 改动既定约束前 |
| [`docs/修改建议.md`](docs/修改建议.md) | 待决策的开放问题（A~E） | 评估扩展方向时 |
| [`docs/简单设计思路.md`](docs/简单设计思路.md) | 最初的 10 条核心需求 | 了解项目原点 |
| [`docs/术语表.md`](docs/术语表.md) | 中英文术语、别名、检索词 | 搜索文档或代码前 |
| [`docs/CICD规划.md`](docs/CICD规划.md) | CI/CD 路线图与候选项 | 配置 CI 时 |
| [`docs/AI记忆/项目记忆.md`](docs/AI记忆/项目记忆.md) + [`docs/AI记忆/current_state.json`](docs/AI记忆/current_state.json) | AI 协作长期记忆 + 机器当前状态 | 在新环境续接对话前 |

> **AI agent 工作前请先读 `AGENTS.md` + `docs/AI导航.md` + 当前平台编码规则入口**，按指引定位后再动手，避免盲目全仓搜索。

---

## 仓库结构
```
wasd/
├── docs/             # 1. 项目文档（设计文档、代码文档规范、AI 导航、词表契约、决策记录、AI 记忆 ...）
│   └── AI记忆/       #    跨会话/跨机器的 AI 协作记忆
├── client/           # 2. 客户端（Godot 4.6.3 项目根，落地代码后含 project.godot 与 res:// ...）
├── server/           # 3. 服务器端（当前单机项目暂为占位，详见决策记录）
├── MinimumViableProduct/ # MVP 隔离实验区，含 MVP 文档与独立客户端代码
├── draft/ 或 DRAFT/  # 人工草稿；AI 禁止读取/搜索/修改/整理/引用，除非用户明确授权
├── AGENTS.md         # AI agent 通用开工入口
├── CLAUDE.md         # Claude Code 入口适配
├── CODEX.md          # Codex CLI 入口适配
├── OPENCODE.md       # OpenCode 入口适配
├── .codebuddy/       # CodeBuddy 平台配置（规则 / agents / commands）
├── .codex/           # Codex CLI 平台配置（核心规则一致，允许平台优化）
├── .opencode/        # OpenCode 平台配置（opencode.json / agents / commands / rules）
├── .agents/skills/   # Agent Skills（外部 AI 库按需引用适配）
├── .github/          # PR / Issue 模板，未来 workflows
└── 杂项配置          # README / CONTRIBUTING / LICENSE / .gitignore / .gitattributes / .editorconfig / .gitmessage
```

## 客户端（`client/`）目录约定（代码落地后）
```
client/
├── project.godot
├── scenes/     # 场景 .tscn（Player / Bullet / Enemy / Item / Hazard ...）
├── scripts/    # 脚本 .gd（按系统单一职责拆分）
├── data/       # 可调数值配置（JSON）+ README.md 人工调参手册
├── locale/     # 本地化翻译表（CSV → .translation）+ README.md 多语言文案手册
├── templates/  # 新内容脚手架模板（enemy / relic ...）
└── assets/     # 美术 / 音效
# 玩家设置存档：user://settings.cfg；user:// 下另存元进度存档
```

## 核心红线（最易踩坑）
- 不硬编码可调数值（全部走 `client/data/` 即 `res://data/`）。
- 不硬编码玩家可见文本（全部走 `tr("key")`）。
- 新增 / 修改数值字段必须同步 `client/data/README.md`；新增 / 修改文案 key、语言列或占位符约定必须同步 `client/locale/README.md`。
- 不硬编码按键、手柄按钮或手柄轴（全部走 InputMap action + `Settings` 重绑定）。
- 不为每个遗物/道具写独立分支（用 modifiers + behaviors 数据描述）。
- 不裸字符串（stat / effect / event / 设置 key 必须来自 `docs/词表与契约.md` 并以常量引用）。
- 相机不开 `limit` / `drag margin`（玩家恒居屏幕中央）。
- 高频实体不裸 `instantiate` / `queue_free`（必须对象池）。
- 暂停统一用 `get_tree().paused`，暂停菜单节点设 `process_mode = PROCESS_MODE_ALWAYS`。

> 完整自检清单见编码规则文件末尾。

---

## 如何运行 / 调试
> **当前为文档阶段，无可运行代码。** 落地代码后此处将补充：
> - 用 Godot 4.6.3 打开 `client/project.godot`；
> - 主场景与启动流程；
> - 调试快捷键（数值热重载、调试面板等）。

## 参与方式（贡献约定）
1. 动手前先读 `AGENTS.md`、`docs/AI导航.md` 与当前平台编码规则入口。
2. 新增内容优先**加数据**而非加逻辑；新原语先在 `docs/词表与契约.md` 登记再实现再使用。
3. 新确立的规则/决策/设计/代码契约变更**必须同步**到对应文档（规则 19/20/24）：
   - 新规则 → 当前平台编码规则入口（核心语义在 `.codebuddy/`、`.codex/`、`.opencode/` 中保持一致）
   - 新决策 → `docs/决策记录.md`
   - 设计变更 → `docs/游戏设计文档.md` + `docs/AI导航.md` + `docs/词表与契约.md`
   - 代码模块 / 公共 API / 数据 schema 变化 → `docs/代码文档规范.md` + `docs/代码/`
4. 提交前过一遍编码规则文件末尾的「自检清单」。

---

## 许可证
本项目采用 [MIT License](LICENSE)。

## 版本
- 设计文档：**v1.5**（2026-06）
- 代码：尚未启动
