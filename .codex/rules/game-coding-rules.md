---
description: Roguelike 游戏项目编码规则，所有代码的编写/修改/生成都必须遵循
alwaysApply: true
---

# 游戏项目编码规则（强制遵循）

> 本规则提炼自 `游戏设计文档.md`。在本项目中编写、修改或生成任何代码时，**必须**无条件遵循以下规则。
> 若某项需求与本规则冲突，应先提示用户，不要擅自破坏规则。

## 1. 引擎与语言
- 一律使用 **Godot 4.7 + GDScript**，不引入其他引擎/语言（除非用户明确要求）。
- 优先使用 Godot 内建机制：`Node2D` / `Area2D` / `Camera2D` / `TileMap`、`signal`、`Resource`、autoload 单例。

## 2. 目录结构（固定约定）
仓库根主要目录：

- `docs/`：项目文档（设计文档、AI 导航、词表契约、决策记录、AI 记忆等）
- `client/`：**Godot 4.7 项目根**（即 Godot 中的 `res://`）
- `server/`：服务器端预留（当前为单机项目，暂占位）
- `draft/` / `DRAFT/`：用户人工草稿禁区，AI 默认不得读取、搜索、修改、整理、格式化或引用
- `.codebuddy/skills/*/SKILL.md`、`.codex/skills/*/SKILL.md`、`.opencode/skills/*/SKILL.md` 与 `.claude/skills/*/SKILL.md`：四平台同步的项目级 skills；用于按需加载可复用流程，不得放宽项目核心规则；新增或调整时同步 `docs/AI协作/AI技能资源评估.md`、`CLAUDE.md`、`CODEX.md`、`OPENCODE.md` 与工具适配指南。
- 外部 AI 库的有用经验必须吸收到三平台项目级 skills 或项目自有 subagent 中；不再保留 vendor submodule、外部 hooks / plugin、整包 skills 或 `.agents/skills` reference 层。

`client/` 下的固定约定：
- `client/scenes/`（即 `res://scenes/`）：场景（`.tscn`）
- `client/scripts/`（即 `res://scripts/`）：脚本（`.gd`）
- `client/data/`（即 `res://data/`）：可调数值配置（平表 CSV + 复杂 JSON）
- `client/locale/`（即 `res://locale/`）：本地化翻译表（CSV → `.translation`）
- `client/templates/`（即 `res://templates/`）：脚手架模板（enemy/relic 等）
- `client/assets/`（即 `res://assets/`）：美术 / 音效
- `user://settings.cfg`：玩家设置存档；`user://` 下另存元进度存档

新增文件必须放入对应目录，不得随意散落。完整项目代码放根目录 `client/`；历史 MVP 验证经验只能经设计 / ADR 迁移，不得复活或搬运临时代码。工具链与平台入口文件（`AGENTS.md`、`CODEX.md`、`OPENCODE.md`、`.codebuddy/`、`.codex/`、`.opencode/`、`.github/`、`.git*`、`LICENSE`、`README.md`、`CONTRIBUTING.md` 等）保留在仓库根。

## 3. 数据与逻辑分离（核心需求）
- **严禁在代码中写死可调数值（魔法数字）**：生命、移速、射速、伤害、子弹速度、刷怪曲线、掉落概率等一律读取 `res://data/` 下的配置文件。
- 配置通过 `DataLoader` 统一加载：**平表数值优先 CSV**（如敌人基础数值、经验曲线、刷怪波次、掉落权重），**复杂配置优先 JSON**（如遗物行为、角色能力、局外成长树、嵌套参数）。Godot 读取 CSV 走 `FileAccess.get_csv_line()`，读取 JSON 走 `FileAccess.open()` / `JSON.parse_string()`。
- 支持**配置热重载**（运行时重读即时生效），新增 / 修改数值文件或字段需同步 `client/data/README.md`，写清含义、单位、默认值、取值范围和调参影响。

## 4. 多语言本地化（框架级，强制）
- **任何面向玩家的文本都不得硬编码**，一律使用文本键：`tr("some_key")`。
- 数据文件（道具/遗物等）只存 `name_key` / `desc_key`，译文放 `res://locale/` 翻译表。
- 动态数值用占位符（如 `"伤害 +{value}"`），禁止用字符串拼接组句。
- 通过 `Localization`（autoload）与 `TranslationServer` 管理与切换语言。
- 当前首批语言为 `zh_CN` 与 `en`；新增玩家可见文案时，AI 必须自动补齐另一语言首版译文，人工最终复核。
- UI 布局、按钮宽度、面板宽度、换行和 HUD 信息密度以英文 `en` 文案长度作为最小设计与验收基准；新增 / 修改玩家可见 UI 文案或 UI 布局时，必须切到英文检查不截断、不溢出、不遮挡，不能以中文短文本密度作为唯一尺寸依据。
- 新增 / 修改玩家可见文案、语言列、key 域前缀或占位符约定时，必须同步 `client/locale/README.md`，保证人工能直接按手册维护多语言文本。

## 5. 设置系统（框架级，强制）
- 所有玩家偏好走统一的 `Settings`（autoload 单例），不得各自为政。
- 设置项以「键 + 类型 + 默认值 + 取值范围」描述；新增设置 = 加一条配置 + 一个 UI 控件。
- 变更通过信号 `setting_changed(key, value)` 广播，相关系统订阅后**即时生效，无需重启**。
- 持久化到 `user://settings.cfg`（`ConfigFile`）。

## 6. 道具 / 遗物系统（数据驱动，最关键）
- **严禁为每个遗物/道具写独立硬编码分支**。
- 采用「**修正器 modifiers + 行为事件 behaviors**」数据驱动模型：
  - 数值类用 `modifiers`：`{ stat, type(add/mult), value }`。
  - 行为类用 `behaviors`：`{ event, effect, params }`。
- 逻辑层只实现有限的「效果原语」（加成 / 穿透 / 分裂 / 追踪 / 点燃……），实现为脚本方法或小型 `Node`/`Resource`，由数据中的 `effect` id 映射调用。
- **新增遗物/道具 = 新增一条数据**，不改逻辑层。
- 未来角色 / 道具 / 遗物允许突破默认玩法限制，但必须通过已登记的 `capability`、`effect`、`behavior`、`StatusEffect` 或可复用 strategy 表达；禁止写 `if relic_id == ...` / `if character_id == ...` 这类一次性特殊分支。

## 7. 属性计算模型
- 最终属性统一为：`最终值 = (基础值 + Σ加法修正) × Π乘法修正`。
- 所有加成通过向「修正器列表」注册修正项实现，便于动态增删，禁止直接改基础值。

## 8. 输入与操作
- 移动：键盘 WASD + 手柄左摇杆，8 方向。
- 射击瞄准：键鼠默认用鼠标相对玩家 / 视口中心方向瞄准，子弹可朝任意角度发射；键盘方向键、手柄右摇杆 / D-pad 保留为兜底瞄准输入；角色视觉只区分向左 / 向右两种朝向，不做向上 / 向下朝向。
- 开火：**全自动**，按 `fire_rate` 触发，玩家不能手动控制是否开火。
- 移动与瞄准**解耦**。
- 键盘按键、手柄按钮与手柄轴都应可通过设置系统重绑定，不得硬编码物理输入（统一用 InputMap action，见 `词表与契约.md` 第 7 节）。
- **暂停功能**：游戏暂停统一用 `get_tree().paused`，暂停时业务节点（移动/开火/子弹/刷怪/机关/计时）随之冻结；暂停菜单等需暂停时仍响应的节点设 `process_mode = PROCESS_MODE_ALWAYS`。暂停键用可重绑定的 action `pause`（默认 `Esc` / 手柄 Start 或 Menu），菜单文本走本地化键，**不硬编码**。

## 9. 摄像机（玩家恒居屏幕中央）
- `Camera2D` 挂在 `Player` 节点下，玩家**始终固定在屏幕正中央**，移动表现为世界滚动。
- **关闭** 相机 `limit`（边界限制）与 `drag margin`（拖拽边距），保证严格居中。

## 10. 性能
- 子弹、敌人等高频实体**必须使用对象池**复用，禁止频繁 `instantiate`/`queue_free`。
- 大地图按区块（Chunk）生成/卸载，视野外内容及时回收。

## 11. 代码风格（AI 友好）
- 模块**单一职责**，各系统独立场景与脚本：Player / Bullet / Enemy / Item / Hazard / Spawner / Map 等。
- 用 `signal` 解耦事件，避免强耦合直引用。
- 命名规范统一、函数短小、关键逻辑有注释，便于人和 AI 理解与续写。
- 新写 / 修改的 GDScript 必须遵循 [Godot 4.7 官方 GDScript style guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html) 作为基础风格；若官方规范与本项目更严格的类型化、数据驱动、autoload、词表常量或文档同步规则冲突，以本项目规则为准。
- 修改正式 `client/**/*.gd` 后必须跑 `python tools/lint_gdscript_rules.py`；该脚本只覆盖第一档低误报规则，不能替代人工 review、headless boot 或后续 gdtoolkit。
- 修改正式 `client/**/*.gd` 后建议跑 `python tools/lint_semantic_rules.py` 收集第三档语义 advisory warning；该脚本默认非阻塞，用于提示 id 特殊分支、autoload 绕过、缺类型签名、缺 `# Doc:` 与未知 contract 常量，warning 需人工判断。
- 修改 `client/data/`、`client/locale/strings.csv` 或 Godot export preset 后必须跑 `python tools/lint_project_rules.py`；该脚本覆盖第二档项目规则，不能替代 DataLoader schema 回归或发行前人工许可复核。
- 只整理本次触碰的脚本；不得借“接入官方规范”批量重排无关旧代码。
- 命名按 Godot 官方规则：文件 / 函数 / 变量 / signal 用 `snake_case`，`class_name` / 节点名 / enum 名用 `PascalCase`，常量与 enum 成员用 `CONSTANT_CASE`。
- 脚本内顺序按官方规范：`@tool` / `@icon` / `class_name` / `extends` / 文档注释 → signals → enums → constants → static vars → exports → 普通成员 → `@onready` → static methods → 生命周期回调（`_init` / `_enter_tree` / `_ready` / `_process` / `_physics_process` 等）→ 公共方法 → 私有方法 / 内部类。
- 格式按官方规范：优先英文布尔操作符 `and` / `or` / `not`；少用不必要括号；操作符两侧、逗号后保留空格；不要做竖向对齐；注释用 `# ` / `## ` 开头且优先独立成行；字符串默认双引号；浮点数保留前导 / 尾随 `0`；十六进制小写；大数字用 `_` 分组。
- 避免大文件重写；优先做小而精准的修改。

## 12. 美术
- 开发期一律使用**几何占位图**（圆=玩家、三角=敌人、点=子弹），玩法跑通后再替换。
- 素材遵循统一调色板与固定尺寸（如 32×32）。

## 12-E. 本地 Mod 接口（框架级，创意工坊前置边界）
- 玩家 mod 当前只支持本地数据包：`user://mods/<mod_id>/mod.json` + mod 自带数据 patch；未来创意工坊只作为分发层，不改变游戏内加载契约。
- 统一走 `ModLoader`（autoload）扫描 manifest、校验安全相对路径、排序、诊断，并向 `DataLoader` 提供声明式 JSON / CSV append patch；业务系统禁止直接读取 `user://mods`。
- mod 只允许通过 manifest 声明少量运行时动态契约扩展（当前为 `character_ids`、`game_modes`、`content_tags`、`locale_prefixes`），且值必须以 `mod_<mod_id>_` 开头；项目代码仍只引用内置生成常量。
- mod 禁止扩展 `stats`、`effects`、`events`、`damage_types`、`pool_ids`、`audio_prefixes`、`rng_streams`、`save_kinds` 等需要代码、资源、确定性或存档同步的核心契约。
- 禁止执行玩家 GDScript、动态库、可执行文件或远端资源；需要新 effect / behavior / strategy 时，先走正式项目词表、实现、测试和文档流程。
- `DataLoader` 必须校验合并后的数据；无效 mod 应 fail-fast 输出 `[ModLoader]` / `[DataLoader]` 诊断，不得静默吞掉。

## 12-F. 平台服务接口（框架级，Steam 优先）
- Steam API 是优先平台能力，但业务系统不得直接调用 Steamworks / GodotSteam / Epic / GOG / 主机平台 SDK；统一走 `PlatformServices`（autoload）。
- 当前只预留接口：`PlatformServices` 默认 `preferred_provider=steam`、`active_provider=none`，不联网、不创建真实大厅、不解锁真实成就、不接 Steamworks SDK。
- 成就、统计、富状态 / 状态显示、overlay、好友邀请、Lobby / 联机入口和平台用户身份都必须通过 `PlatformServices`；后续其他平台通过 provider adapter 接入，不改业务调用面。
- 平台大厅 / 邀请不是游戏同步协议；真正多人 PvE / PvP 仍需单独网络同步、服务器权威、断线恢复和反作弊设计。
- 平台不可用、离线或非 Steam 构建时，游戏必须仍能启动、游玩、保存和回放；平台调用应安全退化并给 diagnostics，不得崩溃。
- 未来云存档只能作为 `SaveManager` 的同步 / 分发层，不得绕过 `SaveManager` envelope、迁移、原子写入、备份回退和损坏隔离。

## 12-A. 录制回放与确定性（框架级，第四条横向基础设施）
- 项目需支持录制回放用于回归测试与平衡验证（详见 `游戏设计文档.md` 9.9 / 9.18）。
- 统一走 `Replay`（autoload）：开局录 `seed + 输入序列`，一局结束存到 `user://replays/`。
- **确定性硬约束**：
  - 所有随机走 `RNG`（autoload）的子流；**禁止直接调用 `randi()` / `randf()` / `randf_range()` / `randi_range()`** 等。
  - 子流调用形式 `RNG.<stream>.<api>()`，子流 id 必须在 `docs/词表与契约.md` 第 11 节登记（`spawn` / `drop` / `combat` / `ui_choice` / `world` 等）。
  - 所有玩法相关时间走 `GameClock`（autoload）；**禁止直接读 `Time.get_ticks_msec()` / `Time.get_ticks_usec()` / `OS.get_unix_time()`** 等参与玩法判定。
  - `_process(delta)` / `_physics_process(delta)` 中业务时间用 `GameClock.delta_scaled(delta)`（受暂停 / 时间缩放影响）；不是 `Engine.time_scale`。
  - 物理 / Tween / 动画涉及随机或时间的，必须经由 `RNG` 与 `GameClock`。
- `wall_now` 与原始 `Time.get_unix_time_from_system()` 仅允许出现在 `Analytics` / UI 计时器等非玩法路径。
- 维护一组**黄金回放样例**（`tests/replays/golden_*.replay`）作为回归基准；CI 跑回放对照（见 `docs/CICD规划.md` 4.M）。
- 调试用 action `debug_toggle_replay` 仅 debug build 启用（见 `docs/词表与契约.md` 第 7 节）。

## 12-C. 游戏状态、池化、UI 栈（K / L / M 落地约束）
- **游戏流程统一走 `GameState`（autoload）**：业务代码**禁止**自管"是否在游戏中"布尔变量、**禁止**直接读写 `get_tree().paused`；通过 `GameState.change_state(...)` 与 `state_changed` 信号订阅（详见 9.12）。
- **高频实体统一走 `PoolManager`（autoload）**：`acquire(pool_id)` / `release(node)`；池类型 id 在词表第 8 节登记；被池化节点必须实现 `_pool_reset()`（详见 9.13）。
- **UI 弹窗统一走 `UIManager`（autoload）**：`push/pop/replace/clear`；UI 场景根节点用 `@export modal/pauses_game/music_duck` 元数据声明行为；**禁止**业务代码直接 `add_child` UI 弹窗（详见 9.14）。

## 12-D. 伤害结算、状态效果、存档、音频（N / O / Q 落地约束）
- **伤害走单一入口 `Combat.apply_damage(target, DamageInfo)`**；`damage_type` 进词表第 9 节；**禁止**业务代码直接 `target.hp -= n`（详见 9.15）。
- **持续效果用 `StatusEffect` 资源 + `StatusEffectComponent`**；`id`（`burn` / `poison` 等）进词表；`stack_rule` 必须显式声明（`REPLACE` / `REFRESH` / `ADD_DURATION` / `INDEPENDENT` / `MAX_MAGNITUDE`）。effect 原语 `ignite` / `chain` 等改为薄包装。
- **存档走 `SaveManager`（autoload）**：必须同时支持 `meta` 局外成长长期档案与 `run` 局内暂停退出续局档案；所有存档**强制头字段** `version` + `kind` + `slot` + `created_at` + `updated_at` + `game_version` + `data_hash`；写入必须原子替换并保留 `.bak`；schema 变更必须配 `register_migration(kind, from, to, fn)`；加载失败时 fail-fast、尝试备份回退并隔离到 `user://saves/.broken/`（详见 9.16）。
- **音频走 `AudioManager`（autoload）**：`play_sfx(id, opts)` / `play_music(id, fade)`；音频 id 在词表第 10 节登记；**禁止**业务代码直接 `AudioStreamPlayer.play()`（详见 9.17）。
- **本地 mod 走 `ModLoader`（autoload）**：玩家数据包只通过 manifest + DataLoader patch 接入；**禁止**业务代码直接读取 `user://mods` 或执行玩家脚本（详见 9.21）。
- **平台服务走 `PlatformServices`（autoload）**：Steam 成就 / 状态显示 / overlay / Lobby / 邀请和后续其他平台 SDK 都通过统一门面；**禁止**业务代码直接调用平台 SDK（详见 9.22）。
- 设置中的音量项（`audio.master/music/sfx`）由 `AudioManager` 在启动时同步到 Bus 配置；缺 Bus 时 fail-fast。

## 12-B. 平衡测试接口预留（框架级）
- 输入解耦：`Player` 与所有可被 AI 替换的角色，输入必须走 InputMap action（不直接读 `Input.is_key_pressed` / `Input.is_joy_button_pressed` / 原始 joy axis）。
- `Spawner` / `MapManager` / `RNG` 都接受外部 seed 注入。
- `Analytics` 在 headless 模式下走同步落盘（不阻塞模拟批量跑）。
- 正式项目早期**只锁接口形态**，不实现 `AIPlayer`（详见 `游戏设计文档.md` 9.10）。

## 13. 数据埋点 / 玩家数据收集（框架级，强制）
- 项目需收集玩家数据用于后续分析，**必须从框架阶段预留统一的数据收集接口**，不得后期临时硬塞。
- 统一走 `Analytics`（autoload 单例）：对外暴露 `track_event(event_name, params)` 等接口，由它统一缓冲、批量上报或落盘。
- **埋点与业务逻辑解耦**：各系统通过 `signal` 或调用 `Analytics.track_event()` 上报，**禁止把上报细节散落进业务代码**；事件名与字段集中定义为常量/配置，避免裸字符串。
- 关键节点都要留好埋点接口（即使暂未接后端）：开局/结束、死亡（位置/时间/击杀数）、升级与遗物选择、道具使用、关键战斗与难度节点等。
- 数据收集需遵守隐私合规：可在 `Settings` 中提供「数据收集开关」，默认行为以用户约定为准；不收集敏感个人信息。
- 上报实现可插拔（本地落盘 / HTTP 上报等），通过接口隔离，便于切换后端而不改业务代码。

## 14. 项目索引与导航（AI 友好）
- 维护一份项目导航文件 `docs/AI导航.md`，告诉 agent：**每类改动该改哪些文件、复用哪些场景、扩展点在哪**。
- 开始任何任务前**优先阅读** `docs/AI导航.md` 与本规则文件，按其指引定位，避免盲目全仓搜索。
- 新增系统/模块/数据类型时，必须同步更新 `docs/AI导航.md` 的对应入口与扩展点说明（**含第 5.2 节系统依赖图**）。
- **跨会话 / 跨机器协作**：在新环境 clone 仓库后，先读 `AGENTS.md` 给出的快速开工 5 步（指向 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`），可直接续接对话；完整 `docs/AI记忆/项目记忆.md` 按任务需要再读。

## 14-B. AI 记忆维护（自动）
- `docs/AI记忆/项目记忆.md` 是 AI 协作长期索引，`docs/AI记忆/current_state.json` 是机器可读当前状态，必须按项目记忆第 9 节「更新约定」**自动维护**，无需用户提醒。
- 每次重要变更结束后：① 修订长期索引快照/决策/工具链节；② 覆盖更新 `current_state.json`（最新 ADR、待决策项、下一步、最近验证）；③ 第 6 节保留当日**一行**摘要 + 日志链接；④ 写当日 `会话日志/YYYY-MM-DD.md`。
- **自动瘦身**：写入前检查 `项目记忆.md` 行数，临近 200 行立即按"日 → 周 → 月"层级聚合旧条目；短期状态进入 `current_state.json` 并用**覆盖**不用追加。
- 瘦身本身不算重大变更，仅在会话日志记一笔，不再追加 ADR。

## 14-C. 测试义务（强制）
- 测试约定的**唯一权威来源**：`docs/测试策略.md`（5 层金字塔 + 里程碑要求 + 性能预算 + 手动回归 checklist）。
- 每次代码改动按 `docs/测试策略.md` 第 7 节「AI agent 改完的测试义务」表确定责任：
  - 改效果原语 / 伤害公式 / 状态效果 → 必新增 GUT 单测 + 必要时重录黄金回放
  - 改 autoload 接口 → 单测更新 + headless 启动必须过
  - 改存档 schema → 必须配迁移函数 + 迁移测试
  - 改性能敏感模块 → 跑 `perf_probe` 与上轮对比
- 横向 autoload + `Combat` + `ModifierEngine` 行覆盖率 **≥80%**；其他业务模块 **≥60%**。
- 测试代码**禁止裸 `randi()` / `Time`**，必须用 `RNG.set_run_seed` + 假 `GameClock`；命名 `test_<行为>_<期望>`。
- 黄金回放（`tests/replays/golden_*.replay`）**有意改变行为时才重录**，commit message 注明影响；修 bug 不应改变行为，黄金不动。
- 性能不达标（`docs/测试策略.md` §4 预算）视同测试失败。
- 里程碑结束前对应层测试必须就位（见 §3 测试矩阵），否则不进下一里程碑。

## 14-A. AI 协作工程（框架级，第五条横向基础设施）
- 高频任务套用 `docs/AI协作/任务模板/`（加遗物 / 加敌人 / 加效果原语 / 加设置项 / 加埋点 / 调数值 / 加本地化文本），不要每次重新摸索。
- 不在模板的任务，按 `docs/AI协作/上下文预算.md` 决定读取范围，**禁止盲目全仓搜索**。
- 复杂任务可参照 `docs/AI协作/角色分工.md` 切角色（设计 / 实现 / 评审 / 平衡）。
- 改完代码必须跑 `docs/AI协作/实时验证回路.md` 描述的 pre-commit hook（秒级反馈）；**禁止使用 `--no-verify` 跳过**（除非 commit message 写明原因）。
- 若已接入 Godot MCP / Bridge，按 `docs/AI协作/引擎集成.md` 优先用引擎 API 而非读写文件。

## 15. 词表与契约（消灭裸字符串）
- 所有"约定字符串"必须来自集中白名单 `docs/词表与契约.md`，并在代码中以**常量/枚举**引用，禁止散落裸字符串：
  - `stat` 名（如 `damage` / `move_speed` / `fire_rate`）
  - `effect` 与 `behavior.event` 的合法 id（如 `pierce` / `split` / `ignite`；`on_hit` / `on_kill`）
  - 埋点 `event_name`、设置 `key`、本地化 key 前缀
  - 输入 action id、池类型 id、伤害类型、状态效果 id、音频 id、RNG 子流 id、角色 id、capability id、content tag
- **只能使用白名单中已存在的 id**；需要新 id 时，先在 `docs/词表与契约.md` 登记，再在逻辑层实现对应原语，最后才在数据/代码中使用。
- **代码常量单一来源（详见 `游戏设计文档.md` 9.19）**：
  - 代码引用走 `client/scripts/contracts/` 下生成的常量类（`stats.gd` / `effects.gd` / `events.gd` / `analytics_events.gd` / `settings_keys.gd` / `actions.gd` / `pool_ids.gd` / `damage_types.gd` / `status_effects.gd` / `audio_ids.gd` / `rng_streams.gd` / `character_ids.gd` / `capabilities.gd` / `content_tags.gd` / `meta_currencies.gd` / `meta_upgrades.gd` / `meta_unlocks.gd` / `save_kinds.gd`）。
  - 这些文件**自动生成、禁止手改**；改约定改 `docs/词表与契约.md`，跑 `tools/sync_contracts.py` 重生成。
  - 中间产物 `client/data/_contracts.json` 也由脚本生成；`DataLoader` 读它做校验。
  - pre-commit hook 强制：md 改了未跑 sync → fail；手改了生成文件 → fail。
- 数据加载时应据此白名单校验，发现未登记 id 立即报错。

## 16. 数据校验与黄金样例
- `DataLoader` 加载配置时必须**校验字段、类型与取值范围**，并遵循 fail-fast：出错时打印**具体文件名 + 字段 + 期望值**，便于人和 AI 立即定位修正。
- 每类数据文件（`relics.json` / `enemies.csv` 等）保留**一条"黄金样例"条目**作为结构参照，新增内容照其结构填写。
- 数据字段含义、单位、取值范围记录在 `client/data/README.md` 中，与 `docs/词表与契约.md` 配合；本地化 key、语言列和占位符规则记录在 `client/locale/README.md` 中。

## 17. 类型化 GDScript 与脚手架模板
- 一律使用**类型化 GDScript**：变量、参数、返回值都标注类型（如 `var hp: int`、`func take_damage(amount: float) -> void`），利用静态检查并帮助 AI 推断用法。
- 仅当右侧表达式在同一行类型明确时使用 `:=`；`get_node()`、复杂函数返回值、外部数据或可能歧义的表达式必须显式标注类型。`as` 可能静默得到 `null`，不保证类型时先用 `is` 检查或在使用前校验。
- 新增同类内容优先复制 `res://templates/` 下的模板（如 `enemy_template.gd`、`relic_template.json`），保证结构统一、可被 AI 模仿。
- 显式 `class_name` / `@export` 标注，避免依赖隐式约定。

## 18. 决策记录、日志与运行说明
- 重要设计/技术决策记入 `docs/决策记录.md`（轻量 ADR）：一句话写清**做了什么 + 为什么**，让后续 agent 不误改既定约束。
- 统一日志规范：日志带**模块前缀**（如 `[Spawner]`），关键路径有可读输出，便于 AI 据 log 定位问题。
- 维护 `README.md`，写清如何运行/调试项目，让 agent 能自行启动验证改动。
- 控制单文件体积：脚本保持小而聚焦，避免超大文件，便于 AI 整体读入上下文。

## 19. 规则维护（元规则）
- 以后项目中**新确立的任何编码/设计规则、约定或决策，都必须及时补充进本文件**，保持本文件为唯一权威的规则来源。
- 当用户提出新规则、或某项设计决策确定下来时，应主动在此新增对应条目（并在需要时同步更新「自检清单」）。
- 不得让规则散落在聊天记录或其他文档而不归档到此处。

## 20. 文档维护（元规则）
- 项目文档（`docs/游戏设计文档.md`、`docs/修改建议.md`、`docs/AI导航.md`、`docs/词表与契约.md`、`docs/决策记录.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`、`client/data/README.md`、`client/locale/README.md` 等）必须与实际设计/代码**保持同步**，是与规则文件同等重要的权威来源。
- 当设计、玩法、数值结构或系统发生变更时，应**主动更新对应文档**，不得让文档与实现脱节、过时。
- 新增系统/模块/重要决策时，需在相应文档中补充说明；文档之间若有交叉引用应一并维护。
- 文档以中文撰写，结构清晰、便于人和 AI 检索续写。

## 21. 多平台 AI 入口与配置适配（强制）
- `AGENTS.md` 是所有 AI agent 的通用开工入口；`CODEX.md`、`OPENCODE.md` 只做平台加载适配，不能承载与通用入口冲突的核心规则。
- `.codebuddy/`（CodeBuddy 平台）、`CLAUDE.md` + `.claude/`（Claude Code 平台入口与原生配置）、`.codex/`（OpenAI Codex CLI 平台）与 `.opencode/`（OpenCode 平台，含项目级 skills）共享同一套**项目核心约束**，但不要求文件内容、目录结构或工具字段字节级一致。
- 允许针对不同 AI agent / 平台优化 frontmatter、工具名、提示词措辞、命令入口与 agent 拆分方式；优化不得改变项目红线、数据契约、测试义务、文档维护规则等核心语义。
- 修改任一平台入口或配置时，必须判断是否影响其他平台的能力可用性：
  - 核心规则变化（如本文件、红线、自检清单、快速开工 5 步）→ 通用入口与 `.codebuddy/` / `CLAUDE.md` / `.codex/` / `.opencode/` 都要表达同一语义，可用不同措辞或格式。
  - 平台专属能力变化（如某平台的工具名、agent prompt、command wrapper）→ 只改对应平台即可，并在必要时更新 `docs/AI协作/工具适配指南.md`。
  - 新增跨平台通用 agent / command → 至少在工具适配指南登记各平台入口；是否每个平台都创建文件取决于平台是否需要。
- pre-commit hook / `health-check` 不应校验平台配置内容哈希一致；应校验核心规则版本、关键能力清单与文档登记是否一致（含 `.opencode/opencode.json` 命令注册）。
- 禁止让某个平台的配置悄悄绕过项目核心规则；平台优化只能降低使用摩擦，不能降低约束强度。

## 22. 文档 AI 友好维护（强制）
- 长期维护文档必须在开头提供 **AI 修改说明**，说明本文档的权威范围、常见联动文件，以及修改前应先读的维护指南。
- 修改任何长期文档前，必须先读 `docs/AI协作/文档维护指南.md`，再按该指南的“文档联动清单”判断需要同步哪些文件。
- 新增长期文档时，必须同时写入 AI 修改说明；若发现既有长期文档缺少说明，应先补说明再继续改正文。
- 涉及规则、设计、词表、测试、AI 协作工具、CI、README/CONTRIBUTING 入口的修改，必须检查是否需要同步 `docs/AI导航.md`、`docs/决策记录.md`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与当日会话日志。
- 文档应面向 AI 检索与续写：标题稳定、路径真实、权威来源明确、联动关系用表格或短清单表达，禁止只在自然语言段落里暗藏必须遵守的规则。

## 23. 内容扩展与破限能力（强制）
- 项目长期目标是支持大量角色、遗物、道具和“突破默认限制”的内容；玩法限制（如默认鼠标瞄准、左右朝向、自动开火、主动栏数量、摄像机策略）是默认配置，不是硬编码上限。
- 新角色必须数据驱动：基础属性、起始携带、tags、capabilities、控制配置等来自 `client/data/characters.json` 或同类数据文件。
- 项目后续可能存在多种游戏模式；角色、遗物、道具、敌人、成长奖励等资源本体默认保持模式无关，模式配置只通过资源池、权重、禁用列表、tags / availability、capability / strategy 和轻量覆盖组合资源，禁止为某个模式复制一套资源或写 `if mode_id == ...` 的内容分支。
- 当前不做多人，但需预留未来多人 PvE / PvP 边界：业务逻辑禁止写死唯一玩家、唯一队伍或“玩家只打敌人 / 敌人只打玩家”；输入走归一化 intent / InputMap action，伤害走 `Combat` 的 source / target / team / friendly_fire 模式规则边界，回放 / 存档 / 埋点可预留 participant / team 概念；不得提前实现网络层、同步协议或服务器权威。
- 破限内容必须声明 `tag_limit_break` 与对应 `capability_id`，并在 `docs/词表与契约.md` 第 12 节登记；代码引用走生成常量，禁止裸字符串。
- 现有 primitive 表达不了时，先新增可复用 primitive / strategy（effect、behavior、StatusEffect、movement_model、aim_model、fire_model 等），再由数据引用；不得把特殊逻辑塞进某个系统的 id 判断。
- 工程红线不可被内容突破：随机仍走 `RNG`，时间仍走 `GameClock`，伤害仍走 `Combat`，UI 仍走 `UIManager`，存档仍走 `SaveManager`，音频仍走 `AudioManager`，本地 mod 仍走 `ModLoader` + `DataLoader`。
- 平台能力不可被内容突破：Steam / 其他平台成就、状态显示、overlay、联机大厅和邀请仍走 `PlatformServices`，不得从内容或业务脚本直接调用平台 SDK。
- 任何破限能力必须有测试责任：至少 L0 词表 / schema 校验；新增 primitive 或改变行为时按 `docs/测试策略.md` §7 补 L1 / L3。

## 24. 代码-文档同步（强制）
- 代码变更必须按 `docs/代码文档规范.md` 判断对应文档；新增 / 修改长期维护模块、autoload、公共 API、signal、数据 schema、依赖方向、扩展点或测试义务时，必须同步详细的 `docs/代码/<module_id>.md` 与相关权威文档。
- 不要求每个小 helper 单独成文档；内部重构且不改行为 / API / 依赖时可以不改长期文档，但最终回复或 PR 备注需要说明“无需文档更新”的理由。
- 长期维护脚本应在文件头用 `# Doc: docs/代码/<module_id>.md` 指向模块文档；自动生成文件、测试、一次性调试脚本或被上级模块文档覆盖的私有 helper 可例外。
- 模块文档必须是人类可维护的详细模块文档：职责边界、代码地图、场景 / 节点结构（如适用）、运行流程、公共 API、signal/event、数据与词表、依赖、扩展点、常见改动入口、故障排查、测试义务、迁移 / 兼容说明、相关 GDD/ADR；禁止逐行复述实现，也禁止只用自动抽取的简短摘要替代。
- 若代码改变玩家可见行为、架构边界、约定字符串或测试义务，不能只改 `docs/代码/`，还必须同步 GDD / ADR / 词表 / 测试策略中的对应权威来源。

## 25. 沟通语言（强制）
- AI 面向用户的回复、计划、总结、提问与变更说明默认使用中文。
- 仅在用户明确要求其他语言、引用代码 / API / 命令 / 日志 / 错误原文、编辑目标文件已有语言要求、或对外发布文本需要其他语言时，才使用对应语言。
- 代码标识符、文件路径、命令、错误日志与外部 API 名称保持原文，不为了中文化而改写。

## 26. 沟通与需求评估（强制）
- 用户问“有没有问题”“有没有风险”“review 一下”等时，必须基于事实和上下文判断；没有发现实际问题就明确说“没有问题”或“未发现问题”，禁止为了显得有用而硬找问题、过度优化或提出无必要改动。
- 用户提出新需求后，执行前应简短反馈该需求在本项目中的落地前景：价值、性价比、实现复杂度、维护 / 设计 / 测试风险；若需求明显有问题、与既定 ADR 冲突、性价比低或存在重大隐患，必须先直接说明并给出替代建议，不要闷声实现到最后。
- 发生上下文总结 / 压缩 / 恢复后，必须先以用户最后一条明确指令重新对齐当前任务；`docs/AI记忆/current_state.json`、会话摘要、`Next Steps` 或历史待办只作候选参考，不能被当作授权执行。若恢复摘要与用户最后指令冲突，或“研究 / 查找 / 看看”与“安装 / 落地 / 提交”等授权边界不清，先问一句再动手。

## 27. AI Git 提交策略（强制）
- 大更改完成后默认由 AI 自动创建一次 git commit：跨多文件功能 / 工具 / CI / 规则 / ADR / 数据 schema / 代码模块 / 重要文档同步等可独立回滚的变更，用户无需再次提醒。
- 细微改动不自动 commit：拼写、单行措辞、小范围说明、只读诊断、临时验证或用户明确说“先别提交”的改动；最终回复说明未提交原因。
- 大型代码改动完成后，提交前必须追加一次事实型 code review：适用于跨多文件功能、代码模块、数据 schema、工具、CI 或会改变运行行为的复杂实现；优先使用 `code-review-factual` skill 或 Reviewer 角色，并按 `docs/AI协作/代码审核流程.md` 先检查 pre-commit / lint / test / docs 输出，再审当前 diff 的 bug、回归风险和缺测试。拼写、单行措辞、小范围文档、只读诊断和临时验证不触发正式 review。
- 自动 commit 前必须执行 `git status --short`、`git diff`、`git log --oneline -10`，跑本次变更对应验证，只 stage AI 本次任务明确修改的文件。
- 禁止提交用户已有脏改动、其他 agent 改动、`draft/` / `DRAFT/` 内容、未确认临时文件或本机私有配置；无法干净拆分时停止并询问用户。
- commit message 使用 Conventional Commits；禁止 `--no-verify`，除非用户明确批准且 commit message 写明原因。

## 28. `draft/` 人工草稿禁区（强制）
- `draft/` 目录及其大小写变体（如 `DRAFT/`）存放用户人工草稿，不属于 AI 默认上下文、搜索范围、整理范围或任务输入。
- 除非用户在当前任务中明确点名授权处理该目录，AI 禁止读取、搜索、修改、格式化、归档、总结或引用其中任何内容。
- 仓库级搜索、批量格式化、文档整理、健康检查或自动化脚本建议必须显式排除 `draft/` / `DRAFT/`。
- 遵守该禁区是默认行为；除非与当前任务直接相关或需要解释异常，不要在最终回复中逐次声明该禁区的遵守情况。

---

### 自检清单（提交代码前）
- [ ] 没有硬编码可调数值（都在 `res://data/`）？
- [ ] 新增 / 修改数值字段是否同步 `client/data/README.md`，让人能直接上手调参？
- [ ] 没有硬编码玩家可见文本（都用 `tr()` 文本键）？
- [ ] 新增 / 修改文案 key、语言列或占位符是否同步 `client/locale/README.md`，且 `zh_CN` / `en` 已补齐，AI 自动补译未改变功能含义？
- [ ] 新增 / 修改玩家可见 UI 文案或 UI 布局是否已按英文 `en` 长度验收，确认无截断、溢出或遮挡？
- [ ] 没有硬编码键盘按键、手柄按钮或手柄轴（都走 InputMap action + `Settings` 重绑定）？
- [ ] 玩家偏好都走 `Settings` 单例并能即时生效？
- [ ] 新遗物/道具是加数据而非加逻辑分支？
- [ ] 新角色 / 破限道具是否通过 `capability` / primitive / strategy 表达，而不是按 id 写特殊分支？
- [ ] 高频实体用了对象池？
- [ ] 相机保证玩家居中（无 limit / drag margin）？
- [ ] 暂停是否用 `get_tree().paused`，暂停菜单节点设 `process_mode=ALWAYS`，暂停键走可重绑定 action（非硬编码键盘/手柄输入）？
- [ ] 关键节点是否通过 `Analytics` 统一接口留好了数据埋点（而非散落硬编码）？
- [ ] 随机数都走 `RNG.<stream>`（无裸 `randi()` / `randf()` / `randi_range()`）？时间都走 `GameClock`（无裸 `Time.get_ticks_msec()`）？
- [ ] 游戏流程走 `GameState`（无散落的 `get_tree().paused` / 自管 in_game 布尔变量）？
- [ ] 高频实体走 `PoolManager`（池 id 在词表）？
- [ ] UI 弹窗走 `UIManager.push/pop`（无散落 `add_child` UI）？
- [ ] 伤害走 `Combat.apply_damage(DamageInfo)`（无 `target.hp -= n`）？
- [ ] 持续效果用 `StatusEffect` 资源（明确 stack_rule）？
- [ ] 存档走 `SaveManager`，同时支持 `meta` 与 `run`，且有 `version/kind/slot/data_hash` 头字段、原子写入、备份回退、损坏隔离与迁移注册？
- [ ] 音频走 `AudioManager.play_sfx/play_music`（无裸 `AudioStreamPlayer.play()`）？
- [ ] 本地 mod 是否只走 `ModLoader` + `DataLoader` 声明式 patch（无业务代码直接读取 `user://mods`、无执行玩家脚本、无扩展核心契约）？
- [ ] Steam / 其他平台 API 是否只走 `PlatformServices`（无业务代码直接调用 Steamworks / GodotSteam / 平台 SDK，平台不可用时能安全退化）？
- [ ] 代码常量来自 `client/scripts/contracts/` 自动生成文件（未手改）？
- [ ] 约定字符串（stat/effect/event/设置/locale key / role / capability / tag 等）是否都来自 `docs/词表与契约.md` 且以常量引用（无裸字符串）？
- [ ] 角色 id、capability id、content tag 是否都来自词表第 12 节并以生成常量引用？
- [ ] 新增数据是否照「黄金样例」结构填写，并能通过 `DataLoader` 校验？
- [ ] 新代码是否使用类型化 GDScript？是否按 Godot 4.7 官方 GDScript style guide 整理了本次触碰的命名、代码顺序、空白、布尔操作符、注释和类型标注？是否跑过 `python tools/lint_gdscript_rules.py`？是否复用了模板？
- [ ] 若修改正式 `client/**/*.gd`，是否跑过 `python tools/lint_semantic_rules.py` 并人工判断第三档 advisory warning（特殊 id 分支、autoload 绕过、缺类型签名、缺 `# Doc:`、未知 contract 常量）？
- [ ] 新增 / 修改数据字段、locale 或 export preset 后，是否跑过 `python tools/lint_project_rules.py`？字段是否已写进 `client/data/README.md`，locale 是否保留 `zh_CN` / `en` 双语，release preset 是否排除 debug/dev_tools？
- [ ] 新增 / 修改长期代码模块、公共 API、signal、数据 schema 或依赖方向时，是否已同步详细的 `docs/代码/` 模块文档？若无需更新，是否说明原因？
- [ ] 面向用户的回复 / 总结是否默认使用中文（除非存在明确特殊场景）？
- [ ] 当用户问有没有问题 / 风险时，是否基于事实回答；没发现问题就明确说没有问题，未硬找问题或过度优化？
- [ ] 用户提出需求后，是否已反馈落地前景、性价比、复杂度和主要风险；有重大隐患时是否先说清楚？
- [ ] 若本轮经历上下文总结 / 压缩 / 恢复，是否已重新对齐用户最后明确指令，且没有把摘要里的 `Next Steps` 当作授权执行？
- [ ] 大更改是否已按 AI Git 提交策略自动 commit？细微改动是否已说明不提交原因？
- [ ] 若是大型代码改动，是否已按 `docs/AI协作/代码审核流程.md` 先看工具输出、再审 diff，并记录发现 / 未发现问题、semantic advisory 处理结果及测试缺口？若是细微改动，是否未触发正式 review？
- [ ] 自动 commit 前是否检查 `git status --short` / `git diff` / `git log --oneline -10`，且只 stage 本次任务文件？
- [ ] 是否已更新 `docs/AI导航.md`、`docs/决策记录.md` 等相关文档？
- [ ] 是否套用了 `docs/AI协作/任务模板/`（高频任务）或遵守了上下文预算？
- [ ] pre-commit hook 是否全过？（无 `--no-verify` 或已注明原因）
- [ ] 是否按 `docs/测试策略.md` §7 表履行了对应测试义务（新增/更新单测 / 黄金回放 / 性能采样）？
- [ ] 改了横向 autoload / `Combat` / `ModifierEngine` 后，行覆盖率仍 ≥80%？
- [ ] 改了存档 schema 是否注册了迁移函数？
- [ ] 改了行为的黄金回放是否已重录并在 commit 中注明？
- [ ] 若涉及重要决策/对话，是否已更新 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与当日会话日志（跨机器续接用）？
- [ ] 本次新确立的规则/约定是否已补充进本规则文件？
- [ ] 本次变更涉及的设计/数值是否已同步更新到相关文档？
- [ ] 改了 `AGENTS.md` / `CLAUDE.md` / `CODEX.md` / `OPENCODE.md` / `.codebuddy/` / `.codex/` / `.opencode/` 平台入口或配置后，核心规则语义是否仍一致？工具适配指南是否需要更新？
- [ ] 改了长期文档前是否阅读了 `docs/AI协作/文档维护指南.md`，并检查了目标文档的 AI 修改说明与联动清单？
