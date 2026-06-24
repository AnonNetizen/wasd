# 游戏项目编码规则（OpenCode 入口）

> 本文件是 OpenCode 平台的规则入口，随 `.opencode/opencode.json` 的 `instructions` 加载。
> 完整项目规则正文与 CodeBuddy / Codex 保持同一核心语义：`.codebuddy/rules/game-coding-rules.md`、`.codex/rules/game-coding-rules.md`。
> 修改任一平台规则时，必须同步检查 `.codebuddy/rules/game-coding-rules.md`、`.codex/rules/game-coding-rules.md`、本文件、`AGENTS.md`、`CLAUDE.md`、`OPENCODE.md`、`docs/AI协作/工具适配指南.md`、`docs/代码文档规范.md`。

## OpenCode 必守入口

1. 先读 `AGENTS.md` 的快速开工 5 步。
2. 再读 `.codebuddy/rules/game-coding-rules.md` 的完整规则正文；该文件通过 `.opencode/opencode.json` 一并加载，是 OpenCode 当前完整规则源。
3. 若 OpenCode 专属格式需要额外约束，只能在本文件追加“平台加载/工具使用”说明，不能放宽项目核心规则。

## OpenCode 平台约束

- `.opencode/agents/*.md` 是 OpenCode subagent 入口；角色语义必须与 `.codebuddy/agents/`、`.codex/agents/` 同名文件一致。
- 项目维护者已授权支持 subagent 的平台在复杂、专业或可并行任务中主动启用对应项目 subagent；只读小任务或直接实现更高效时不必强行拆分；平台不支持或外层工具策略限制时，读取同名 agent `.md` 作为 prompt 模板执行角色流程。
- `.opencode/commands/*.md` 是 OpenCode 命令步骤手册；命令注册在 `.opencode/opencode.json` 的 `command` 字段。
- `.codebuddy/skills/*/SKILL.md`、`.codex/skills/*/SKILL.md`、`.opencode/skills/*/SKILL.md` 与 `.claude/skills/*/SKILL.md` 是四平台同步的项目级 skills；用于按需加载可复用流程，不得放宽项目核心规则；新增或调整时同步 `docs/AI协作/AI技能资源评估.md`、`CLAUDE.md`、`CODEX.md`、`OPENCODE.md` 与工具适配指南。
- Claude Code 入口是 `CLAUDE.md`，并配套项目自有的活跃 `.claude/`（agents / commands / skills / rules / settings.json，与三平台同源）；此处的活跃 `.claude/` 是项目自建配置，不是 ADR #56~#59 / #72 拒绝的外部 `.claude/` 整包（CCGS / ECC hooks / settings / vendor）。
- 外部 AI 库的有用经验必须吸收到三平台项目级 skills 或项目自有 subagent 中；不再保留 vendor submodule、外部 hooks / plugin、整包 skills 或 `.agents/skills` reference 层。外部工具若与本项目规则冲突，以 `AGENTS.md`、平台规则和 ADR 为准；游戏设计冲突以本项目 GDD / ADR 为准。
- `.opencode/opencode.json` 必须保留 `$schema: https://opencode.ai/config.json`，避免 OpenCode 启动时因配置字段错误失败。
- 改 `.opencode/` 后需要重启 OpenCode；运行中的 session 不会热重载配置。

## 核心红线速记

- 可调数值进 `client/data/`，平表数值优先 CSV、复杂配置优先 JSON，字段说明同步 `client/data/README.md`；玩家可见文本走 `tr("key")` / `client/locale/strings.csv`，当前首批语言为 `zh_CN` 与 `en`，AI 自动补齐另一语言首版译文并交人工复核，多语言与占位符说明同步 `client/locale/README.md`；UI 布局、按钮、面板和 HUD 以英文 `en` 文案长度作为尺寸验收基准，新增 / 修改玩家可见 UI 文案或布局时必须切英文确认无截断、溢出或遮挡；键盘按键、手柄按钮与手柄轴都走 InputMap action + `Settings` 重绑定；约定字符串来自 `docs/词表与契约.md` 且以生成常量引用。
- 固定斜俯视 / 哈迪斯式显示不得通过旋转 `Camera2D` 或 `Camera2D.zoom` 非等比缩放来模拟透视；相机保持玩家居中、屏幕水平和等比缩放，斜俯视观感由地面美术、障碍物、角色 / 敌人视觉层、Y-sort / 遮挡和房间 / 舞台构图承担，避免横向与纵向屏幕移动速度失真。
- 随机走 `RNG.<stream>`，时间走 `GameClock`，流程走 `GameState`，UI 走 `UIManager`，池化走 `PoolManager`，伤害走 `Combat.apply_damage`，持续效果走 `StatusEffect`，存档走 `SaveManager`；`SaveManager` 必须支持 `meta` 局外成长与 `run` 暂停退出续局，并具备标准头字段（含 `data_hash`）、版本迁移、原子写入、备份回退和损坏隔离；音频走 `AudioManager`；本地玩家 mod 走 `ModLoader` + `DataLoader` 声明式 JSON / CSV patch；Steam / 其他平台 API 走 `PlatformServices`。
- 未来角色 / 道具 / 遗物可以突破默认玩法限制，但必须通过词表登记的 `capability`、content tag、effect / behavior primitive 或可复用 strategy 表达；后续多种游戏模式只能通过数据化资源池、权重、禁用列表、tags / availability、capability / strategy 和轻量覆盖组合资源；当前不做多人，但业务逻辑不得写死唯一玩家、唯一队伍或“玩家只打敌人 / 敌人只打玩家”，输入走归一化 intent / InputMap action，伤害走 `Combat` 的 source / target / team / friendly_fire 模式规则边界，回放 / 存档 / 埋点可预留 participant / team 概念；禁止按 `character_id` / `relic_id` / `mode_id` 写一次性特殊分支，也禁止为某个模式复制一套角色 / 遗物 / 敌人资源或提前实现网络协议。
- 玩家 mod 当前只支持 `user://mods/<mod_id>/mod.json` 本地数据包；未来创意工坊只作为分发层。禁止业务系统直接读取 `user://mods`、执行玩家 GDScript / 动态库 / 可执行文件、或让 mod 扩展 `stats` / `effects` / `events` / `damage_types` / `pool_ids` / `audio_prefixes` / `rng_streams` / `save_kinds` 等核心契约。允许的动态契约扩展只限 manifest 声明的 `character_ids`、`game_modes`、`content_tags`、`locale_prefixes`，且必须以 `mod_<mod_id>_` 开头；合并后的数据仍由 `DataLoader` fail-fast 校验。
- Steam 是优先平台能力，但当前只预留 `PlatformServices` 接口，不接 Steamworks SDK、不联网、不创建真实大厅、不解锁真实成就。成就、统计、富状态 / 状态显示、overlay、好友邀请、Lobby / 联机入口和平台用户身份都必须通过 `PlatformServices`；禁止业务代码直接调用 Steamworks / GodotSteam / Epic / GOG / 主机平台 SDK。平台不可用、离线或非 Steam 构建时游戏必须仍可启动、游玩、保存和回放；平台大厅 / 邀请不等于游戏同步协议，未来云存档也不得绕过 `SaveManager`。
- 代码变更必须按 `docs/代码文档规范.md` 判断对应文档；长期模块、公共 API、数据 schema、依赖方向或测试义务变化时同步详细的 `docs/代码/` 模块文档与相关权威文档，禁止用自动抽取的简短摘要替代。
- 新写 / 修改的 GDScript 必须遵循 [Godot 4.7 官方 GDScript style guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html) 作为基础风格：`snake_case` / `PascalCase` / `CONSTANT_CASE` 命名、官方代码顺序、英文布尔操作符 `and` / `or` / `not`、标准空白 / 注释 / 字符串 / 数字格式，以及类型化 GDScript 的显式类型要求；项目更严格的数据驱动、autoload、词表常量和文档同步规则优先；只整理本次触碰脚本，禁止批量重排无关旧代码；修改正式 `client/**/*.gd` 后跑 `python tools/lint_gdscript_rules.py`，它只覆盖第一档低误报规则，不能替代人工 review、headless boot 或后续 gdtoolkit；修改正式 `client/**/*.gd` 后建议跑 `python tools/lint_semantic_rules.py` 收集第三档语义 advisory warning，它默认非阻塞，用于提示特殊 id 分支、autoload 绕过、缺类型签名、缺 `# Doc:` 和未知 contract 常量；修改 `client/data/`、`client/locale/strings.csv` 或 Godot export preset 后跑 `python tools/lint_project_rules.py`，它覆盖第二档项目规则，不能替代 DataLoader schema 回归或发行前人工许可复核。
- 面向用户的回复默认中文；仅在用户明确要求、引用代码 / API / 命令 / 日志原文、目标文件语言要求或对外发布文本需要时使用其他语言。
- 用户问有没有问题 / 风险时，基于事实回答；没发现问题就明确说没有问题，不硬找问题或过度优化。用户提出新需求后，先简短反馈落地前景、性价比、复杂度和主要风险；有重大隐患时先说清楚，再决定是否实现。
- 发生上下文总结 / 压缩 / 恢复后，必须先以用户最后一条明确指令重新对齐当前任务；摘要、`Next Steps`、`current_state.json` 或历史待办只作候选参考，不能被当作授权执行；授权边界不清时先问一句。
- 大更改完成后 AI 默认自动 commit，细微改动不 commit；大型代码改动提交前必须追加一次事实型 code review（优先用 `code-review-factual` skill 或 Reviewer 角色），并按 `docs/AI协作/代码审核流程.md` 先检查 pre-commit / lint / test / docs 输出，再审当前 diff 的 bug、回归风险和缺测试；自动 commit 前必须看 `git status --short` / `git diff` / `git log --oneline -10`，跑对应验证，只 stage 本次任务文件，禁止带入用户已有脏改动、`draft/` / `DRAFT/`、未确认临时文件或本机私有配置。
- `draft/` / `DRAFT/` 是用户人工草稿禁区；除非用户明确点名授权，AI 不得读取、搜索、修改、整理、格式化、总结或引用其中内容，仓库级批量操作需排除该目录；这是默认行为，不需要每次主动汇报。
- 历史 MVP 实验区已在验证完成后移除；MVP 经验只能经设计 / ADR 迁移，不得复活或搬运临时代码到正式 `client/`。
- 改完同步文档：新规则进三个平台规则入口；新决策进 ADR；重要对话进 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与会话日志。
