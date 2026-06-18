# wasd —— 俯视角 Roguelike 弹幕生存

> 一款受《以撒的结合》与《吸血鬼幸存者》启发的俯视角 Roguelike 弹幕生存游戏。
> **当前状态：正式项目已推进到 F5 暂停 / 存档 / 续局。** 完整项目 `client/` 已可作为 Godot 4.6.3 项目启动；F2 autoload 矩阵、F3 数据 / 契约闭环和 F4 最小可玩闭环已完成阶段验证，F5 已支持暂停保存退出、标题继续游戏、坏档提示、run 存档 v1 -> v2 迁移和 `save-smoke` 存档可靠性验证。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。README 是仓库入口摘要；改项目状态、运行方式、目录结构或 AI 开工入口时，必须同步 `CONTRIBUTING.md`、`AGENTS.md`、`docs/AI导航.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`。

---

> ## 🤖 AI agent 开工提示
>
> **动手前请先读 [`AGENTS.md`](AGENTS.md) → [`docs/AI协作/快速开工.md`](docs/AI协作/快速开工.md) → [`docs/AI记忆/current_state.json`](docs/AI记忆/current_state.json)**。
> 项目有完整的跨会话/跨机器长时记忆系统；日常先走低 token 热路径，完整长期记忆按任务需要再读，无需翻历史聊天。

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
- **数据驱动**：所有可调数值集中在 `res://data/` 下，平表数值优先 CSV、复杂配置优先 JSON，字段说明见 `client/data/README.md`，零代码调参 + 热重载。
- **遗物 = 数据**：用「修正器 modifiers + 行为 behaviors」描述，新增遗物 = 加一条数据，不改逻辑。
- **扩展优先**：默认玩法规则不是硬编码上限；破限角色 / 道具走 capability、tag、primitive 或 strategy，不写一次性 id 分支。
- **代码-文档同源**：长期代码模块、公共 API、数据 schema 与扩展点变化必须同步 `docs/代码/` 模块文档。
- **三条横向基础设施**（框架阶段就内建）：
  - `Localization` —— 多语言本地化，所有玩家可见文本走 `tr("key")`，文案手册见 `client/locale/README.md`。
  - `Settings` —— 统一玩家偏好管理，信号驱动即时生效，持久化到 `user://settings.cfg`。
  - `Analytics` —— 数据埋点统一接口 `track_event()`，关键节点全留钩子。
- **AI 友好工程**：项目索引、词表白名单、数据校验、黄金样例、ADR、模板，让 AI agent 易读、易写、易扩展。
- **大改自动守门**：大型代码改动提交前追加事实型 code review，小改动不走正式 review。

---

## 必读文档（按优先级）
| 文档 | 作用 | 何时读 |
|------|------|--------|
| [`AGENTS.md`](AGENTS.md) | **AI agent 通用开工入口** | 每次开始任务前 |
| [`docs/AI协作/快速开工.md`](docs/AI协作/快速开工.md) | **低 token 热路径** | 日常接手 / 新会话 |
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
| [`docs/AI记忆/current_state.json`](docs/AI记忆/current_state.json) + [`docs/AI记忆/项目记忆.md`](docs/AI记忆/项目记忆.md) | 机器当前状态 + AI 协作长期冷存储 | 续接任务；长期背景按需 |

> **AI agent 工作前请先读 `AGENTS.md` + `docs/AI协作/快速开工.md` + `docs/AI记忆/current_state.json` + 当前平台编码规则入口**，再按 `docs/AI导航.md` 定位，避免盲目全仓搜索。

---

## 仓库结构
```
wasd/
├── docs/             # 1. 项目文档（设计文档、代码文档规范、AI 导航、词表契约、决策记录、AI 记忆 ...）
│   ├── AI协作/       #    AI 快速开工、任务模板、上下文预算、工具适配
│   └── AI记忆/       #    跨会话/跨机器的 AI 协作记忆
├── client/           # 2. 正式客户端（Godot 4.6.3 项目根，含 project.godot 与 res:// ...）
├── server/           # 3. 服务器端（当前单机项目暂为占位，详见决策记录）
├── draft/ 或 DRAFT/  # 人工草稿；AI 禁止读取/搜索/修改/整理/引用，除非用户明确授权
├── CREDITS.md        # 代码库级致谢 / 第三方来源清单；游戏内数据见 client/data/credits.json
├── AGENTS.md         # AI agent 通用开工入口
├── CLAUDE.md         # Claude Code 入口适配
├── CODEX.md          # Codex CLI 入口适配
├── OPENCODE.md       # OpenCode 入口适配
├── .codebuddy/       # CodeBuddy 平台配置（规则 / agents / commands）
├── .codex/           # Codex CLI 平台配置（核心规则一致，允许平台优化）
├── .opencode/        # OpenCode 平台配置（opencode.json / agents / commands / skills / rules）
├── .github/          # PR / Issue 模板，未来 workflows
└── 杂项配置          # README / CONTRIBUTING / LICENSE / .gitignore / .gitattributes / .editorconfig / .gitmessage
```

## 客户端（`client/`）目录约定
```
client/
├── project.godot
├── scenes/     # 场景 .tscn（Player / Bullet / Enemy / Item / Hazard ...）
├── scripts/    # 脚本 .gd（按系统单一职责拆分）
├── data/       # 可调数值配置（CSV / JSON）+ README.md 人工调参手册
├── locale/     # 本地化翻译表（CSV → .translation）+ README.md 多语言文案手册
├── templates/  # 新内容脚手架模板（enemy / relic ...）
└── assets/     # 美术 / 音效
# 玩家设置存档：user://settings.cfg；user:// 下另存元进度存档
```

## 核心红线（最易踩坑）
权威红线见 `AGENTS.md` 与当前平台编码规则入口；README 不复制完整规则正文，避免多处漂移。日常只记四件事：数据 / 文案 / 输入 / 约定字符串走权威通道，横向能力走统一 autoload，`draft/` / `DRAFT/` 不碰，代码和文档同步完成才算完成。

> 完整自检清单见当前平台编码规则文件末尾。

---

## 如何运行 / 调试
当前正式项目已有最小标题、F4/F5 运行时和 headless 验证命令。

- 用 Godot 4.6.3 打开 `client/project.godot`。
- 命令行启动：`godot --path client`。
- Headless 验证：`python tools/godot_bridge.py headless-boot`（若系统无 Python，可用 Codex 桌面内置 Python 路径执行）。
- F4 运行时 smoke：`python tools/godot_bridge.py --project client f4-smoke`。
- F5 存档 smoke：`python tools/godot_bridge.py --project client save-smoke`。

## 参与方式（贡献约定）
1. 动手前先读 `AGENTS.md`、`docs/AI协作/快速开工.md`、`docs/AI记忆/current_state.json` 与当前平台编码规则入口，再按 `docs/AI导航.md` 定位。
2. 新增内容优先**加数据**而非加逻辑；新原语先在 `docs/词表与契约.md` 登记再实现再使用。
3. 新确立的规则 / 决策 / 设计 / 代码契约变更按 `docs/AI协作/文档维护指南.md` 同步权威文档。
4. 写/改代码模块优先读 `docs/代码/<module_id>.md` 和目标源码，只有设计冲突或新增决策时再补读完整 GDD / ADR。
5. 提交前过一遍编码规则文件末尾的「自检清单」。

---

## 许可证
本项目采用 [MIT License](LICENSE)。

第三方来源、外部库和工作人员记录见 [CREDITS.md](CREDITS.md)；游戏内 Credits UI 数据源见 [client/data/credits.json](client/data/credits.json)。

## 版本
- 设计文档：**v1.5**（2026-06）
- 代码：正式项目推进到 F5 暂停 / 存档 / 续局
