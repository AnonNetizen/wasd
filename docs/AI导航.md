# AI 导航（项目索引）

> 本文件是给 AI agent（以及人）的**项目地图**：开始任何任务前先读这里，按指引快速定位，避免盲目全仓搜索。
> 配套：编码规则见 `AGENTS.md` 第 3 步的当前平台规则入口；完整设计见 `游戏设计文档.md`。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是项目索引权威；新增系统、目录、扩展点、AI 工具入口或依赖图变化时，必须同步 GDD / 词表 / 规则 / 测试策略 / 项目记忆中的对应入口。

---

## 1. 项目是什么
固定斜俯视 2.5D 射击刷宝生存游戏（灵感：手动按住开火的俯视射击身份 + 《星际战甲》与《暗黑》的刷装备 / 刷词条长期追求 + 《哈迪斯》的斜俯视舞台可读性 + 开放有限大地图生存压力 + 《以撒的结合》的道具 / 机关 / 构筑组合）。项目保留局内随机奖励和单局构筑变化，但核心操作是移动、瞄准和按住 `fire` action 持续射击；玩法判定仍在 2D 平面内，当前 `Camera2D` 保持水平居中和等比缩放，斜俯视观感由舞台地面、资产落地点 / 阴影、障碍物、遮挡层级与 2.5D 角色视觉承担。
- 引擎：**Godot 4.7 + GDScript**
- IP 方向：**《破巢者》**（英文暂定 `Nestbreakers`）——未知原因导致其他宇宙与本宇宙的通道突然打开，银河系星际文明被打散，首都星域仍能组织反击；多英雄主动突入敌方“巢”，在怪潮中夺取遗物、升级构筑并尝试打穿巢核、切断通道或削弱敌方源头；“巢”泛指敌方核心据点 / 生产源头 / 通道锚点 / 意志中枢，不限定为虫巢。
- 核心理念：**数据驱动 + 扩展优先 + 模式友好资源复用 + 未来多人友好边界 + 框架级基础设施（本地化 / 设置 / 数据埋点）+ AI 易扩展**

## 2. 必读文档（按优先级）
| 文档 | 作用 |
|------|------|
| `AGENTS.md` | **AI agent 通用开工入口**，每次开始任务前必读 |
| `docs/AI协作/快速开工.md` | **低 token 热路径**，日常接手先读；完整长期文档按任务触发 |
| `.codebuddy/rules/game-coding-rules.md` / `.codex/rules/game-coding-rules.md` / `.opencode/rules/game-coding-rules.md` / `.claude/rules/game-coding-rules.md` | **强制编码规则入口**，按当前平台选读 |
| [Godot 官方 GDScript style guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html) | 新写 / 修改 `.gd` 的命名、代码顺序、格式与类型标注基线；项目规则更严格时以项目规则为准 |
| `docs/AI导航.md`（本文件） | 项目地图与扩展点定位 |
| `docs/AI知识库索引.md` | AI 知识库总索引、权威层级、任务入口和 ADR 追踪矩阵 |
| `docs/术语表.md` | 中英文术语、别名和检索词 |
| `docs/IP设定.md` | 《破巢者》IP、世界观包装、英雄 / 敌方势力 / 遗物命名和宣发基调 |
| `docs/IP美术风格.md` | 《破巢者》IP 美术风格、敌巢色板、阵营色、地图兴趣点功能色和资产 brief 色彩规则 |
| `docs/词表与契约.md` | 所有约定字符串白名单（stat/effect/event/key），**禁止编造** |
| `docs/游戏设计文档.md` | 完整设计 |
| `docs/代码文档规范.md` | 代码变更与对应文档的同步规范 |
| `docs/决策记录.md` | 既定决策与原因，勿误改 |
| `docs/修改建议.md` | 待决策的开放问题（C~E；A/B 与 J~R 已归档） |
| `docs/功能建议池.md` | F9 第一轮 Demo 收口后的可选新功能菜单；不是已采纳路线图，用户点名后才推进 |
| `docs/AI辅助开发机会清单.md` | 不在运行时接 LLM、只利用 AI 辅助写代码 / 数据 / 工具时的玩法与内容管线机会清单；不是已采纳路线图 |
| `docs/小服务器玩法备忘.md` | 小服务器条件下的异步在线 / 敌巢进化玩法参考；不是已采纳路线图 |
| `docs/AI记忆/项目记忆.md` | AI 协作长期索引（长期冷存储；需要背景 / ADR 摘要 / 历史脉络时读） |
| `docs/AI记忆/current_state.json` | 机器可读当前阶段、下一步、最近验证 |
| `docs/TODO.md` | 人工可读未来任务清单 |

## 3. 目录结构与定位

仓库根主要目录：

| 路径 | 内容 |
|------|------|
| `docs/` | 项目文档（设计文档、AI 导航、词表契约、决策记录、AI 记忆等） |
| `client/` | **Godot 4.7 项目根**（即 Godot 中的 `res://`） |
| `server/` | 服务器端预留（当前为单机项目，暂占位） |
| `tools/` | 本地校验与桥接工具：`sync_contracts.py`、`validate_data.py`、`test_data_loader_schema.py`、`lint_gdscript_rules.py`、`lint_project_rules.py`、`lint_semantic_rules.py`、`docs_health_check.py`、`godot_bridge.py` |
| `.github/` | GitHub Issue / PR 模板与 Actions workflows；当前启用 Stage 1 基础 `docs-check` CI |
| `CREDITS.md` | 代码库级致谢与第三方来源清单；游戏内 Credits 数据源为 `client/data/credits.json` |
| `draft/` / `DRAFT/` | 用户人工草稿，AI 禁止读取 / 搜索 / 修改 / 整理 / 引用，除非用户明确点名授权 |

`client/` 下：

| 路径 | 内容 |
|------|------|
| `client/scenes/`（即 `res://scenes/`） | 场景 `.tscn`（Player / Bullet / Enemy / Item / Hazard 等） |
| `client/scripts/`（即 `res://scripts/`） | 脚本 `.gd`，按系统单一职责拆分 |
| `client/data/`（即 `res://data/`） | 可调数值配置（平表 CSV + 复杂 JSON）+ `README.md` 人工调参手册 |
| `client/locale/`（即 `res://locale/`） | 本地化翻译表（CSV → `.translation`）+ `README.md` 多语言文案手册 |
| `client/templates/`（即 `res://templates/`） | 新内容脚手架模板（enemy/relic 等） |
| `client/assets/`（即 `res://assets/`） | 美术 / 音效 |
| `client/scenes/boot/main.tscn` | F1 最小启动场景，详见 `docs/代码/formal_client_boot.md` |
| `client/scripts/autoload/` | F2+ 横向 autoload 骨架，已含 `ModLoader` / `DataLoader` / `RNG` / `GameState` / `GameClock` / `PlatformServices` / `Settings` / `Analytics` / `Replay` / `PoolManager` / `SaveManager` / `AudioManager` / `Localization` / `UIManager` |
| `client/scripts/combat/` | F4 起的 `Combat` 统一伤害入口、`DamageInfo`、`StatusEffect` 与 `StatusEffectComponent` |
| `client/scripts/gameplay/` | F4/F5/F9 阶段脚本：`gameplay_run_loop` / `world_background` / `map_manager` / `player` / `weapon_system` / `skill_system` / `bullet` / `enemy` / `hazard` / `pickup_orb` / `level_up_panel` / `gameplay_hud`，当前还承载 F5+ run 快照生产 / 恢复 |
| `client/scripts/ui/` | 阶段性 UI：`title_menu` / `pause_menu` / `game_over_panel` / `meta_progression_panel` |
| `client/scripts/debug/` | debug/dev_tools 专用 `DebugConsole` 与 `GMCommandRegistry`；正式 release 不应加载或导出 |
| `client/tools/` | Godot 项目内 headless smoke 脚本；当前含 gameplay runtime、MetaProgression、SaveManager、Settings、Replay、RNG、perf 和 DebugTools smoke |
| `user://settings.cfg` | 玩家设置存档；游戏进度存档走 `user://saves/<slot>/<kind>.save`（`meta` / `run` / `replay_index`） |

`docs/` 下：

| 路径 | 内容 |
|------|------|
| `docs/游戏设计文档.md` | 完整 GDD |
| `docs/代码文档规范.md` | 代码变更需要同步哪些文档的权威规范 |
| `docs/代码/` | `client/` 长期模块文档索引与模块文档 |
| `docs/AI导航.md`（本文件） | 项目地图 |
| `docs/AI知识库索引.md` / `docs/_kb_index.json` | 人工 / 机器可读 AI 知识库索引 |
| `docs/术语表.md` | 术语、别名、英文检索词 |
| `docs/IP设定.md` | 《破巢者》IP 设定与内容包装权威 |
| `docs/IP美术风格.md` | 《破巢者》IP 美术风格、敌巢色板、阵营色与地图兴趣点功能色权威 |
| `docs/词表与契约.md` | 约定字符串白名单 |
| `docs/决策记录.md` | ADR |
| `docs/修改建议.md` | 待决策项（C~E；A/B 与 J~R 已归档） |
| `docs/功能建议池.md` | F9 第一轮 Demo 收口后的可选新功能建议池；只作为人工选择菜单 |
| `docs/AI辅助开发机会清单.md` | AI 只辅助开发、不进入运行时的玩法机会、内容生产管线、DSL / 编辑器 / 模拟器 / lint 工具候选；只作为人工选择菜单 |
| `docs/小服务器玩法备忘.md` | 小服务器可承载的异步在线、敌巢进化、死亡残响、星域污染图等玩法参考；只作为人工选择菜单 |
| `docs/TODO.md` | 未来任务清单（P0 当前优先级 / P1 下一批 / P2 中期 / P3 长期积压） |
| [`docs/正式项目工作规划.md`](正式项目工作规划.md) | MVP 验证完成后，完整项目 `client/` 的阶段路线、交付物、验证门槛和后续 AI 任务选择依据 |
| `docs/简单设计思路.md` | 项目原点 |
| `docs/CICD规划.md` | CI/CD 路线图 |
| `docs/AI记忆/项目记忆.md` | **AI 协作长期索引（冷存储；按需读取长期背景）** |
| `docs/AI记忆/current_state.json` | **机器可读当前状态（下一步与最近验证）** |
| `docs/AI记忆/会话日志/` | 按日期归档的对话摘要 |
| `docs/AI协作/README.md` | AI 协作工程目录索引 |
| `docs/AI协作/快速开工.md` | **AI 日常开工热路径**，降低默认上下文开销 |
| `docs/AI协作/任务模板/` | 高频任务的标准 prompt + 文件操作清单 |
| `docs/AI协作/工作包/` | 正式项目阶段任务的低 token 工作包；当前 F10 战区导演入口是 `F10-WarzoneDirector.md`，F9 Demo 内容 / 表现打磨入口是 `F9-ContentDemoPolish.md`，F8 回放 / 测试 / 平衡维护入口是 `F8-ReplayTestingBalance.md`，F7 设置 / 本地化 / UI 栈维护入口是 `F7-SettingsLocalizationUI.md`，F6 局外成长入口是 `F6-MetaProgression.md`，F4 最小可玩闭环入口是 `F4-MinPlayableLoop.md`，历史 F3 数据闭环入口是 `F3-DataLoader.md` |
| `docs/AI协作/上下文预算.md` | 不同任务该读哪些文件 |
| `docs/AI协作/角色分工.md` | 设计/实现/评审/平衡 四角色协作 |
| `docs/AI协作/引擎集成.md` | Godot MCP / Bridge 接入指南 |
| `docs/AI协作/实时验证回路.md` | pre-commit hook + 本地秒级反馈设计 |
| `docs/AI协作/文档健康检查.md` | 文档健康检查范围、命令和失败解释 |
| `docs/AI协作/工具适配指南.md` | 各 AI 工具（Codex / OpenCode / Claude Code / Aider / Cursor / Windsurf / ChatGPT 等）的接入配法 |
| `docs/AI协作/ECC工具吸收清单.md` | ECC 全工具面逐项筛选、吸收和拒绝结论；同类外部 agent-harness 大仓扫库参考 |
| `docs/测试策略.md` | **5 层测试金字塔 + 里程碑要求 + 性能预算 + 手动回归 checklist（测试唯一权威）** |
| `AGENTS.md` / `CODEX.md` / `OPENCODE.md` | 通用入口与 Codex / OpenCode 轻量入口适配 |
| `CLAUDE.md` | Claude Code 入口适配；配套项目自有的活跃 `.claude/`（ADR #87，与三平台同源），不接外部 vendor / hooks 整包 |
| `.claude/` | Claude Code 平台原生配置：`agents/`（10）、`commands/`（5）、`skills/`（9，四平台同步）、`rules/game-coding-rules.md`、`settings.json`（仅 `draft/` deny）；核心语义与 `.codebuddy/` / `.codex/` / `.opencode/` 一致 |
| `.codebuddy/agents/` | 项目级 subagents：执行类 `balancer` / `contract-validator` / `data-author`，创意类 `game-designer` / `numeric-designer` / `ip-designer` / `copywriter-packager` / `ui-art-designer` / `game-art-designer` / `marketing-strategist` |
| `.codebuddy/commands/` | 项目级 slash commands：`/sync-contracts` / `/new-relic` / `/run-replay-regression` / `/health-check` / `/update-memory` |
| `.codex/` | Codex CLI 平台配置；核心规则语义与 `.codebuddy/` 一致，但允许按 Codex 优化 agents / commands / rules |
| `.opencode/` | OpenCode 平台配置；含 `opencode.json`、agents、commands、skills、rules；核心规则语义与 `.codebuddy/` / `.codex/` 一致 |
| `.claude/` | Claude Code 平台配置；含 `agents`、`commands`、`skills`、`rules`、`settings.json`；核心规则语义与 `.codebuddy/` / `.codex/` / `.opencode/` 一致（ADR #87） |

> 注：`client/` 已是正式 Godot 项目根（`project.godot` 在此）。F1 只建立最小启动骨架；autoload 与玩法按 `docs/正式项目工作规划.md` F2+ 继续落地，新增文件务必归位。

## 4. 扩展点速查（"我要加 X，该改哪？"）

| 我想… | 怎么做（数据驱动，尽量不改逻辑） |
|-------|-------------------------------|
| **加一个敌人** | 在 `client/data/enemies.csv` 加一行基础数值、中心间距、生态 tags、`ai_profile_id` 与 `enemy_*_name` 文案；优先复用 `client/data/enemy_ai_profiles.json` 现有 profile，新行为先加 / 调 profile 和词表 §12-B action，最后才改 `enemy.gd` |
| **加一个角色** | 在 `client/data/characters.json` 加一条：基础属性 / tags / capabilities / 控制配置 / `starting_loadout`；角色 id 先登记词表 §12.1，文案用 `character_*` key；起始武器 / 主动道具 / 消耗品必须存在于对应数据文件；新 capability 先登记词表 §12 再实现 |
| **加 / 改武器** | 在 `client/data/weapons.json` 加一条：武器基础属性、子弹池、伤害类型、命中半径和音频 id；文案用 `weapon_*` key；`pool_id` / `damage_type` / `audio_id` 前缀必须来自词表，不实现 WeaponSystem 运行时 |
| **加 / 改技能** | 在 `client/data/skills.json` 加技能定义：`ability_tags`、`activation`、`costs`、`targeting`、`effects`、冷却和 `skill_*` 文案；角色只在 `characters.json.starting_loadout.skill_ids` 引用技能并声明 `skill_resources`，模式池走 `game_modes.resource_pools.skills`；新资源、目标类型、效果原语或 ability tag 先登记词表 §12-C~12-G，状态效果 / 叠加规则先登记 §9-A~§9-B，再扩展 `docs/代码/skill_system.md` / `docs/代码/status_effect_component.md` |
| **加 / 改状态效果** | 先看 `docs/代码/status_effect_component.md`；状态 id 登记 `docs/词表与契约.md` §9-A，叠加规则登记 §9-B，通过 `skill_effect_apply_status` 或未来 on-hit primitive 注入；当前 Player / Enemy / SkillSystem 自身已实现 `apply_status_effect()` 和 owned ability tag 查询，DoT 由状态组件按 `GameClock` tick 并经 `Combat.apply_damage()` 结算；新可受状态影响实体应照此接入；状态存在期间要授予 / 移除 ability tag 时引用 §12-G，不在业务脚本手动计时 |
| **加 / 改机关** | 在 `client/data/hazards.csv` 加一行：伤害、伤害类型、触发间隔、`radius_tiles` 占格尺寸、持续时间和 `hazard_*_name` 文案；`tag_hazard`、`pool_id`、`damage_type` 必须来自词表；初始摆放改 `client/data/map_layouts.json`，普通菱形范围机关复用 `docs/代码/hazard_system.md` 的通用 `Hazard` 运行时 |
| **改地图边界 / 菱形格 / PCG / 人工摆点** | 查 `docs/代码/map_manager.md`；地图尺寸、`grid.cell_width/cell_height`、玩家出生点、安全半径、刷怪边距、PCG 机关数量 / 间距和人工固定摆点都改 `client/data/map_layouts.json`；bounds 是菱形外接框，必须是格尺寸奇数倍并满足 `bounds.height == bounds.width * grid.cell_height / grid.cell_width`；玩家出生点必须在格心，出生安全区可见提示必须是贴住菱形格线的菱形，机关按 `radius_tiles` 奇偶吸附到合法锚点（奇数格心、偶数网格顶点），可见和逻辑地图边界必须是同一个贴格菱形，刷怪位置仍用 `RNG.spawn`；玩家和敌人中心移动都应保持在菱形边界内；改完跑 `validate_data`、`runtime-smoke`，机关相关追加 `f9-demo-smoke` |
| **加 / 改刷怪波次** | 在 `client/data/spawn_waves.csv` 加一行：模式 id、时间窗、敌人 id / 权重、刷怪间隔、同时存活上限、预算和可选机关权重；敌人 / 机关 / 模式引用必须存在，不实现 Spawner 运行时 |
| **加 / 改战区导演** | 查 `docs/代码/warzone_director.md` 和 F10 工作包；在 `client/data/warzone_directors.json` 改固定 phase、巢变异主题、生态 encounter、兴趣点和阶段启用 wave；运行时只按 `GameClock` 时间 gating `spawn_waves.csv`，匹配当前 layout 的兴趣点会通过 `MapManager` 生成 `source="director"` 初始机关；禁止读取玩家状态、隐藏动态调难或运行时接 LLM；改完跑 `validate_data`、`test_data_loader_schema`、`runtime-smoke` 和 `f9-demo-smoke` |
| **加一个遗物/道具** | 在 `client/data/relics.json` 加一条，用 `modifiers` + `behaviors` 描述；文案用 `relic_*` key；**只用 `docs/词表与契约.md` 已登记的 effect / event / stat / tag**，新原语先登记再实现，不实现遗物运行时 |
| **加 / 改主动道具** | 在 `client/data/active_items.json` 加一条：`charge` 声明冷却 / 充能，`use_effects` 引用已登记 effect，文案用 `item_*` key；模式引用走 `game_modes.resource_pools.active_items`，不实现主动道具栏 / 冷却 / 使用效果运行时 |
| **加 / 改消耗品** | 在 `client/data/consumables.json` 加一条：`stack` 声明最大堆叠 / 初始数量 / 单次拾取数量，`use_effects` 引用已登记 effect，文案用 `item_*` key；模式引用走 `game_modes.resource_pools.consumables`，不实现拾取物 / 背包 / 使用输入 / 数量扣减 / 效果运行时 |
| **加 / 改游戏模式** | 在 `client/data/game_modes.json` 声明可用角色 / 武器 / 敌人 / 机关 / 遗物 / 主动道具 / 消耗品 / 成长资源池、权重、禁用列表、参与者 / 队伍预留和轻量覆盖；mode id 先登记 `docs/词表与契约.md` §12-A；资源本体保持模式无关，禁止为模式复制一套资源或在代码写 `if mode_id == ...` |
| **改经验/升级系统** | 查 GDD §7.1 与 `docs/代码/gameplay_runtime.md`；F4 阶段已落地池化经验球、经验累计、默认 3 选 1、`luck` 概率 4 选 1、`stat_modifier` 奖励应用；经验阈值 / 候选概率在 `client/data/growth.csv`，候选池在 `client/data/growth_pools.json`；候选抽取走 `RNG.ui_choice`，升级面板通过 `UIManager` 挂载，流程走 `GameState.LEVEL_UP`；升级界面按 `pause` 会叠出暂停菜单并在关闭后回到升级选择 |
| **改局外成长 / 元进度** | 查 GDD §7.2；配置改 `client/data/meta_progression.json`，字段说明同步 `client/data/README.md`，文案同步 `client/locale/strings.csv`；存档走 `SaveManager` 的 `meta` kind，标题菜单显示账号等级 / 余额摘要并在有可购买升级时提示入口，购买入口集中在标题菜单的 `MetaProgressionPanel`，面板用状态行区分可购买 / 余额不足 / 锁定 / 满级，死亡结算页只展示收益和账号状态；当前首批升级已包含伤害与射速等数据驱动永久 modifier；新增 currency / upgrade / unlock id 先登记词表 §13 |
| **改致谢 / 第三方来源** | 同步根目录 `CREDITS.md` 与 `client/data/credits.json`；新增分组标题、角色或用途标签时补 `client/locale/strings.csv` 的 `ui_credits_*` key；发行前复核许可证和 notice |
| **加 / 改美术资产 / 占位表现** | 先看 `docs/IP美术风格.md`、GDD §8.2-A、`docs/代码/gameplay_runtime.md` 的占位表现规则和当前 F9 工作包。敌巢 / 虫族使用骨白、蜡黄、干肉粉、深红、黑紫和少量毒蓝；青、红、白归属虫族 / 敌巢，玩家和玩家子弹默认避开青、红、白，敌方远程攻击可用红色，宝箱与地图兴趣点按功能色区分。贴地范围（机关、AOE、地面符号、房间边界）优先用菱形或与菱形地图格对齐；角色、敌人、拾取物、子弹、障碍物和特效不强制菱形，asset brief 必须说明色彩归属、`footprint_shape`、`anchor_point`、`shadow`、`sort_layer`、`collision_or_trigger_shape` |
| **加破限角色/道具** | 先判断是否能用 `capabilities` + `modifiers` + `behaviors` 表达；表达不了则新增可复用 primitive / strategy 并登记词表 §12，禁止按 id 写特殊分支 |
| **写/改代码模块** | 先查 `docs/代码文档规范.md` + 对应 `docs/代码/<module_id>.md` + 目标源码；触碰 `.gd` 时按 Godot 4.7 官方 GDScript style guide 整理本次改动，并跑 `python tools/lint_gdscript_rules.py`；GDD / ADR 只在设计冲突、语义不明或新增决策时补读，不能默认整篇加载 |
| **查知识库 / 找文档关系 / 任务路由** | 先看 `docs/AI知识库索引.md` 的任务路由表，需要机器可读元数据时看 `docs/_kb_index.json`，搜索同义词先看 `docs/术语表.md` |
| **续接当前状态 / 下一步** | 先看 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`；上下文压缩后先以用户最后明确指令对齐，`Next Steps` 只作候选参考；需要长期事实 / ADR 摘要 / 历史细节时再看 `docs/AI记忆/项目记忆.md` 和当日会话日志 |
| **查看 / 维护未来任务** | 看 `docs/TODO.md`；F9 第一轮 Demo 收口后的可选新功能菜单看 `docs/功能建议池.md`；AI 只辅助开发的玩法 / 内容管线 / 工具机会看 `docs/AI辅助开发机会清单.md`；小服务器 / 异步在线玩法参考看 `docs/小服务器玩法备忘.md`；短期机器状态仍同步 `docs/AI记忆/current_state.json`，设计待决策仍进 `docs/修改建议.md` |
| **改 IP / 世界观 / 英雄包装 / 宣传语** | 先看 `docs/IP设定.md`；涉及视觉风格、色板、阵营色、兴趣点颜色或资产 brief 时追加 `docs/IP美术风格.md`；若改变玩法承诺或系统边界，再同步 GDD / ADR / 术语表 / AI导航 / AI记忆 |
| **选择下一项新功能** | 先看 `docs/功能建议池.md`、`docs/AI辅助开发机会清单.md`、`docs/TODO.md` 与 `docs/AI记忆/current_state.json`；用户明确点名功能后，再建立 / 更新工作包、GDD / ADR / 模块文档并实现，不从建议文档自行挑选推进 |
| **评估小服务器在线玩法** | 先看 `docs/小服务器玩法备忘.md`、GDD §6.7 / §9.21 / §9.22、`docs/代码/platform_services.md` 与 `docs/代码/replay.md`；短期优先异步玩法和离线可降级，实时多人 / PvP / 强竞技排行榜默认暂缓 |
| **启动 / 推进正式项目** | 优先读当前阶段工作包；当前 F9 入口为 `docs/AI协作/工作包/F9-ContentDemoPolish.md`，用于内容扩展与 Demo 打磨准备。F8 已落地临时 `l1-smoke`、Replay 文件 roundtrip 的 `replay-smoke`、摘要 diff / 运行时摘要重跑 / 输入播放首片 / runtime event 播放 / 扩展稳定帧样本 diff 的 `replay-runner`、gameplay 输入录制首片的 `replay-input-smoke`、跨 RNG 子流相关性审计 `rng-audit`、`client/tests/replays/golden_basic_run.replay`、`client/tests/replays/golden_pause_resume.replay`、`client/tests/replays/golden_full_death.replay`、`client/tests/replays/golden_level_up_choice.replay` 和轻量 `perf-probe`，现作为 F9 内容扩展的回归护栏；后续 `golden_relic_synergy` 等遗物协同 replay 等对应运行时存在后再补。F7 设置持久化、只显示已接线生效项的正式设置面板、核心 UI 运行时语言刷新、键盘主输入重绑定、输入绑定反馈 / 恢复默认和 UIManager 栈顶 `ui_back` / 默认焦点首片已落地并由 `settings-smoke` / `runtime-smoke` 覆盖；F9 已新增 debug/dev_tools 专用 `DebugConsole` / `GMCommandRegistry` 与 `debug-tools-smoke` / `debug-tools-release-smoke`。维护入口：DebugTools 看 `docs/代码/debug_tools.md`，F7 看 `docs/AI协作/工作包/F7-SettingsLocalizationUI.md`，F6 局外成长看 `docs/AI协作/工作包/F6-MetaProgression.md`，F4 历史入口为 `docs/AI协作/工作包/F4-MinPlayableLoop.md`，F3 数据闭环入口为 `docs/AI协作/工作包/F3-DataLoader.md` |
| **维护正式客户端启动骨架 / 默认分辨率** | 看 `client/README.md`、`docs/代码/formal_client_boot.md` 与 `docs/代码/gameplay_runtime.md`；默认 viewport 当前为 1920×1080，窗口不允许任意拖拽缩放，拉伸策略为 `canvas_items + keep`；改主场景、窗口配置或启动验证时同步本导航和 `docs/代码/README.md` |
| **改词表 / 生成常量** | 改 `docs/词表与契约.md` 后跑 `python tools/sync_contracts.py` 和 `python tools/sync_contracts.py --check`，生成 `_contracts.json` 与 `client/scripts/contracts/*.gd` |
| **校验数据 / 文案** | 跑 `python tools/validate_data.py` 与 `python tools/lint_project_rules.py`；改 DataLoader schema 时追加 `python tools/test_data_loader_schema.py`，改项目规则 lint 时追加 `python tools/test_project_rules_lint.py` |
| **校验 GDScript 项目规则** | 跑 `python tools/lint_gdscript_rules.py`；当前第一档覆盖代码段顺序、危险 `:=`、中文硬编码字符串、裸随机 / 时间 / 暂停 API |
| **校验项目规则** | 跑 `python tools/lint_project_rules.py`；当前第二档覆盖数据字段手册登记、locale `zh_CN` / `en` 双语和 release preset debug/dev_tools 禁入 |
| **校验语义风险** | 跑 `python tools/lint_semantic_rules.py`；当前第三档默认非阻塞，提示特殊 id 分支、业务脚本绕过 autoload、缺类型签名、长期脚本缺 `# Doc:` 与未知 contract 常量；改语义 lint 时追加 `python tools/test_semantic_rules_lint.py` |
| **本地提交前验证** | 已提供 `.pre-commit-config.yaml`；安装后跑 `pre-commit run --all-files` 或提交时自动跑 Stage 1 hook；未安装时按 `docs/AI协作/实时验证回路.md` 的等价命令 |
| **查 Godot 场景树 / headless 启动** | 跑 `python tools/godot_bridge.py export-tree`、`python tools/godot_bridge.py headless-boot`、gameplay runtime 专用 `python tools/godot_bridge.py --project client runtime-smoke`、F9 Demo / 机关专用 `python tools/godot_bridge.py --project client f9-demo-smoke`、F7 设置 / 设置面板专用 `python tools/godot_bridge.py --project client settings-smoke`、F6 局外成长专用 `python tools/godot_bridge.py --project client meta-smoke`、SaveManager 专用 `python tools/godot_bridge.py --project client save-smoke`、DebugTools 专用 `python tools/godot_bridge.py --project client debug-tools-smoke` / `debug-tools-release-smoke`，以及 F8 `l1-smoke` / `replay-smoke` / `replay-runner` / `replay-runner --rerun-runtime-summary` / `replay-input-smoke` / `capture-golden-replay` / `rng-audit` / `perf-probe`；默认项目为正式 `client/` |
| **用项目级 AI skill** | CodeBuddy / Codex / OpenCode / Claude 分别读取 `.codebuddy/skills/<name>/SKILL.md`、`.codex/skills/<name>/SKILL.md`、`.opencode/skills/<name>/SKILL.md`、`.claude/skills/<name>/SKILL.md`；当前覆盖 Godot 实现、场景验证、Godot 测试诊断、试玩复盘、文档同步、安全提交、事实 review、AI 资源筛选与协作面审计、MCP 评估；外部 GodotPrompter / headless-godot / CCGS / ECC 的有用流程已吸收进项目 skill，不再保留 vendor 来源或 reference 跳转；资源筛选与安装清单见 `docs/AI协作/AI技能资源评估.md` |
| **加一种子弹效果原语** | 先在 `词表与契约.md` 登记 `effect` id → 在效果原语层实现方法/Node → 数据中引用 |
| **改数值（血/伤害/刷怪/掉落）** | 先读 `client/data/README.md`，只改 `res://data/` 对应 CSV / JSON，**绝不改代码常量**；平表数值优先 CSV，复杂配置优先 JSON；新增 / 改字段必须同步数值手册 |
| **预留 / 维护玩家 mod 接口** | 看 `docs/代码/mod_loader.md`、`docs/代码/data_loader.md` 与 GDD §9.21；当前只支持 `user://mods/<mod_id>/mod.json` 声明式 JSON / CSV append，不接创意工坊、不执行玩家脚本、不绕过 `DataLoader` schema；未来创意工坊只作为分发层 |
| **加面向玩家的文本** | 先读 `client/locale/README.md`，在 `res://locale/strings.csv` 加 key + `zh_CN` / `en` 译文；若用户只给一种语言，AI 自动补齐另一语言首版译文，人工复核后代码 / 数据用 `tr("key")` 或 `name_key`；涉及 UI 按钮、面板或 HUD 时以英文 `en` 长度验收尺寸，跑对应 smoke，当前按钮类英文适配由 `settings-smoke` 覆盖 |
| **加一个设置项** | 先在 `Settings` 加配置（键/类型/默认/范围）并接入下游 `setting_changed` 即时生效；只有完成生效链路后才在设置面板显示 UI 控件，暂未接线的预留 key 保留为隐藏 / 禁用 |
| **加一个埋点** | 用 `词表与契约.md` 登记的 `event_name`，调用 `Analytics.track_event(name, params)` |
| **改输入/按键/手柄** | 走 `Settings` 重绑定与 InputMap action，不硬编码键盘按键、手柄按钮或手柄轴；当前 `Settings` 已负责键盘主绑定，runtime 只补手柄轴 / 按钮兜底；键鼠默认用鼠标相对玩家 / 视口中心方向瞄准，方向键 / 手柄右摇杆 / D-pad 作为兜底；详细数值面板用 `show_stats_panel` action（默认 Tab）按住显示、松开隐藏且不暂停；业务实体消费归一化 intent / action，避免直接依赖本地玩家输入；默认手柄为左摇杆移动、右摇杆 / D-pad 瞄准 |
| **加 GM 指令 / 调试工具** | 查 GDD 9.20 与 `docs/代码/debug_tools.md`；调试入口只在 debug/dev_tools 构建启用，action 用 `debug_*` 并登记词表 §7；命令必须通过正式系统 API 或受控 `debug_*` API 改状态；release preset 不启用 `dev_tools` 且排除调试脚本 / GM 命令表；改完跑 `python tools/godot_bridge.py --project client debug-tools-smoke` 和 `debug-tools-release-smoke` |
| **加暂停/切换游戏状态** | `GameState.change_state(PAUSED)` 等；UI 通过 `UIManager.push(modal_pause_menu)` 自动联动暂停；F5 首片的 `PauseMenu` 已覆盖继续、保存并退出、重开和回标题，也支持从升级面板上方叠出并恢复回 `LEVEL_UP`；不直接读写 `get_tree().paused`（见 GDD 9.12 / 9.14） |
| **加录制回放/确定性需求** | 走 `Replay`（autoload）；随机走 `RNG.<stream>`、时间走 `GameClock`；不读非确定时间源；改 RNG seed 派生 / 子流集合时追加 `python tools/godot_bridge.py --project client rng-audit`（见 GDD 9.9 / 9.18） |
| **接 Steam API / 平台服务** | 走 `PlatformServices`（autoload）；Steam 成就、统计、富状态 / 状态显示、overlay、Lobby / 邀请和用户身份都先接门面，不让业务直接调用 Steamworks / GodotSteam；其他平台后续走 provider adapter（见 GDD 9.22 / `docs/代码/platform_services.md`） |
| **加 / 验证回放测试** | `Replay` 负责 `.replay` envelope 与 `user://replays/` 文件；F8 基线用 `python tools/godot_bridge.py --project client replay-smoke` 验证最小录制、保存 / 读取、摘要和 data fingerprint roundtrip，用 `python tools/godot_bridge.py --project client replay-runner` 读取 `.replay` 并比较 summary / expectation，用 `python tools/godot_bridge.py --project client replay-runner --rerun-runtime-summary` 生成临时输入播放 smoke replay 并播放 `input_events`，用 `python tools/godot_bridge.py --project client replay-input-smoke` 验证 gameplay 输入录制首片；`golden_basic_run.replay` 可用 `capture-golden-replay` 重录，`golden_pause_resume.replay` 可用 `capture-golden-replay --golden-scenario golden_pause_resume` 重录，`golden_full_death.replay` 可用 `capture-golden-replay --golden-scenario golden_full_death` 重录，`golden_level_up_choice.replay` 可用 `capture-golden-replay --golden-scenario golden_level_up_choice` 重录，四者都用 `replay-runner --replay-file ... --rerun-runtime-summary` 重跑真实运行时摘要与 `run_summary.frame_samples` / 场景语义字段 diff。后续遗物协同 golden 仍等对应运行时存在后再补。 |
| **加平衡测试 / Headless 模拟** | 通过 `AIPlayer` 接口接入；`Spawner` / `MapManager` / `RNG` 都接受外部 seed（见 GDD 9.10）；F8 基线先用 `python tools/godot_bridge.py --project client perf-probe` 输出 schema v2 可比较基线 JSON，包含 30 帧 warmup 后 180 帧 avg / p95 / p99 / max 帧时间、active / peak entity counts、pool final stats / peak active、等级、击杀、状态和预算状态 |
| **加 UI 弹窗** | `UIManager.push(scene)`；场景根节点 `@export modal/pauses_game/music_duck` 元数据；不 `add_child` UI（见 GDD 9.14）；按钮、标题和说明布局以英文 `en` 文案长度验收，不按中文短文本定窄宽 |
| **加新敌人/子弹/特效**（高频实体） | `PoolManager.acquire(pool_id)` / `release(node)`；新池 id 在词表 §8 登记；实现 `_pool_reset()`（见 GDD 9.13） |
| **加伤害逻辑** | 走 `Combat.apply_damage(target, DamageInfo)`；`damage_type` 在词表 §9；保留 source / target / team / friendly_fire 模式规则边界；不 `target.hp -= n`（见 GDD 9.15.1） |
| **加持续效果（DoT/控制/debuff）** | 用 `StatusEffect` Resource + 目标实体的 `StatusEffectComponent.apply()`；id 在词表 §9-A；明确 `stack_rule`；DoT 用 `damage_type`、`magnitude`、`tick_interval`，tick 伤害仍走 `Combat.apply_damage()`（见 GDD 9.15.2） |
| **加存档/读档** | 走 `SaveManager.save/load`；必须支持 `meta` 局外成长和 `run` 暂停退出续局；schema 必带 `version` / `kind` / `slot` / `created_at` / `updated_at` / `game_version` / `data_hash`；写入用 `*.tmp` 原子替换、保留 `.bak`、坏档进 `.broken/`，payload 写入前会 JSON 归一化再算 hash；F5+ 已把 run payload 接到暂停保存 / 标题继续，`ui_restore` 可恢复普通游玩、暂停菜单、升级选择面板和升级面板上方暂停菜单叠层，run payload 当前包含地图 / 机关 / 玩家 / 敌人 / 子弹 / 掉落 / RNG / GameClock，坏档续局失败会回标题提示重置，并新增 `save-smoke` 覆盖 run roundtrip、`.bak` 回退、双坏档隔离、高精度浮点 hash 与 v1 -> v2 迁移；扩展字段时同步 `docs/代码/gameplay_runtime.md` 与 `docs/代码/save_manager.md`；save kind 先登记词表 §14；与 `Settings` 职责分开（见 GDD 9.16） |
| **加音效/BGM** | `AudioManager.play_sfx/play_music`；id 在词表 §10；不直接 `AudioStreamPlayer.play()`（见 GDD 9.17） |
| **执行 AI 高频任务** | 先查 `docs/AI协作/任务模板/`；任务不在模板里 → 按 `docs/AI协作/上下文预算.md` 决定读取范围 |
| **拆分复杂 / 专业任务给 subagent** | 项目默认授权支持 subagent 的平台主动调度 `.codebuddy/agents/` / `.codex/agents/` / `.opencode/agents/` / `.claude/agents/` 下对应角色；只读小任务或直接实现更高效时不必强行拆分；平台不支持或外层工具策略限制时，把同名 `.md` 当 prompt 模板读 |
| **评估 / 吸收外部 AI 工具仓库** | 先用 `ai-resource-curator`，读 `docs/AI协作/AI技能资源评估.md` 与 `docs/AI协作/上下文预算.md`；ECC 这类大仓按 `docs/AI协作/ECC工具吸收清单.md` 的 README / 全工具面清单 / 候选全文读取流程执行；默认不安装外部 hooks、MCP、CLI、dashboard、plugin 或 vendor tree |
| **提交 / 收尾大更改** | 按 `AGENTS.md` 的 AI Git 提交策略：大更改默认自动 commit，细微改动不提交；大型代码改动提交前按 `docs/AI协作/代码审核流程.md` 追加工具先行的事实型 code review；提交前看 `git status --short` / `git diff` / `git log --oneline -10`，只 stage 本次任务文件 |
| **写/改测试** | 看 `docs/测试策略.md`：L0~L5 金字塔 + 各层必测清单 + 里程碑要求 + 测试义务表 |

## 5. 核心系统模块

### 5.1 模块清单
**业务模块**：`InputController` / `Player` / `WeaponSystem` / `SkillSystem`（主动技能）/ `Enemy(EnemyAI)` / `Spawner` / `WarzoneDirector`（敌巢战区导演）/ `HazardSystem` / `ItemSystem` / `GrowthSystem`（经验/升级选择）/ `MetaProgressionSystem`（局外成长）/ `ModifierEngine` / `MapManager` / `Camera2D` / `DataLoader` / `PauseMenu`（UI）/ `Combat`（伤害结算）/ `StatusEffectComponent`（状态效果与 DoT tick）。

**Autoload 单例（横向基础设施 + 协调中枢）**：
- 一条**本地 mod 基础设施**：`ModLoader`（扫描 `user://mods/<mod_id>/mod.json`，给 `DataLoader` 提供声明式数据 patch 与允许的动态契约扩展；创意工坊未来只作为分发层）
- 一条**平台服务基础设施**：`PlatformServices`（Steam 优先预留成就、统计、富状态 / 状态显示、overlay、Lobby / 联机入口和用户身份；其他平台后续走 provider adapter）
- 三条**协作基础设施**：`Localization` / `Settings` / `Analytics`
- 两条**确定性基础设施**：`RNG`（种子化随机，子流分流）/ `GameClock`（暂停冻结时间源）
- 一条**回放基础设施**：`Replay`
- 一条**AI 协作基础设施**：见 `docs/AI协作/`（非 autoload）
- 三个**协调中枢**：`GameState`（流程状态机）/ `UIManager`（界面栈）/ `PoolManager`（通用对象池）
- 两个**资源管理**：`SaveManager`（存档 + 迁移）/ `AudioManager`（音频统一接口）

当前 F2 已落地 `DataLoader`、`RNG`、`GameState`、`GameClock`、`Settings`、`Analytics`、`Replay`、`PoolManager`、`SaveManager`、`MetaProgressionSystem`、`AudioManager`、`Localization`、`UIManager` 的 autoload 骨架；F3 数据 / 契约闭环已通过验收；F4 已落地 `Combat` autoload、`DamageInfo`、gameplay runtime、TitleMenu / WorldBackground / Player / WeaponSystem / Bullet / Enemy / Spawner / PickupOrb / LevelUpPanel / HUD / GameOverPanel 的最小闭环；F5 已新增 `PauseMenu`、暂停保存退出、标题继续游戏、暂停 / 升级 UI 恢复点、升级界面 Esc 叠出暂停菜单、坏档重置提示、run payload、`RNG.snapshot()` / `restore_snapshot()` 与 `GameClock.snapshot()` / `restore_snapshot()`，并用 `SaveManager` 的 `run` kind 保存 / 读取局内快照；F6 已新增 `MetaProgressionSystem`、死亡结算、`meta` profile roundtrip、标题 `MetaProgressionPanel` 局外升级入口、数据驱动伤害 / 射速等永久升级轨道和下一局永久 modifiers；F7 已落地设置持久化、只显示已接线设置的正式设置面板、核心 UI 运行时语言刷新、键盘主输入重绑定、输入绑定保存 / 共用键位反馈、一键恢复输入默认，以及 `UIManager` 栈顶 `ui_back` / 默认焦点首片。F8 已通过当前验收基线收口审计，包含临时 L1 runner、Replay `.replay` 文件 roundtrip、summary diff / 运行时摘要 runner、runner 输入播放首片、runtime event 播放首片、扩展稳定帧样本 diff、gameplay 输入录制首片、`client/tests/replays/golden_basic_run.replay`、`client/tests/replays/golden_pause_resume.replay`、`client/tests/replays/golden_full_death.replay`、`client/tests/replays/golden_level_up_choice.replay`、`rng-audit` 跨子流相关性审计和 schema v2 perf / balance baseline；升级选择已记录 `level_up` decision，RNG 子流 seed 派生已升级为域隔离 SHA-256 mixer 以同时保护跨进程回放确定性与跨子流防相关性。F9 已新增 `ModLoader` 本地 mod 接口首片、`PlatformServices` 平台服务接口首片、可复用 `SkillSystem` 主动技能首片并升级为项目版轻量 GAS 首片、有限地图 / 可调 PCG 的 `MapManager`、通用 `HazardSystem` 与 FEA-12 测试机关，以及 debug/dev_tools 专用 `DebugConsole` / `GMCommandRegistry`。F10 已新增 `WarzoneDirector` 敌巢战区导演首片：`warzone_directors.json` 用固定 phase、巢变异主题、生态 encounter 和兴趣点组合组织标准模式 wave，运行时只按 `GameClock` 时间 gating `spawn_waves.csv`，并把匹配当前 layout 的兴趣点通过 `MapManager` 生成 `source="director"` 初始机关；`debug_summary().map.hazard_sources` 可诊断 manual / pcg / director placement 数量；不读取玩家状态、不做隐藏 DDA、不接运行时 LLM、不提升 run 存档 schema。WeaponSystem 读取 `fire` action，默认按住左键 / 右扳机才按 `fire_rate` 出弹，松开停火；SkillSystem 读取 `skills.json`，默认角色通过 `starting_loadout.skill_ids` 引用 `skill_overdrive_rounds`，主动键释放后用 `skill_effect_weapon_modifiers` 临时提高主武器射速与弹速；技能用 `skill_resources` 的 `mana` 支付成本，activation 支持 required / blocked / granted ability tags，技能伤害仍走 `Combat`，状态效果通过目标实体的 `StatusEffectComponent` 授予 / 释放 ability tags 或造成 DoT，Player / Enemy 状态和 WeaponSystem 临时 modifiers 都进入 run 快照；MapManager 读取 `map_layouts.json`，用有限 bounds、玩家出生点、安全半径、刷怪边距、PCG 机关规则、人工摆点和导演兴趣点生成初始地图，FEA-12 通过通用菱形 `Hazard` 节点、`PoolManager` 和 `Combat` 验证机关伤害；ModLoader 扫描 `user://mods/<mod_id>/mod.json`，只接受声明式 JSON / CSV append patch 和少量动态契约扩展，暂不接创意工坊、不执行玩家脚本；PlatformServices Steam 优先预留成就、统计、富状态 / 状态显示、overlay、Lobby / 联机入口和用户身份，当前不接 Steamworks SDK、不联网，后续其他平台走 provider adapter；DebugTools 通过 F1 / 反引号打开控制台，当前命令覆盖 help/stats/spawn/xp/hp/damage/heal/meta/kill/clear/seed，release 路径由 runtime guard 与导出资源排除约束。当前 F10 入口是 `docs/AI协作/工作包/F10-WarzoneDirector.md`；F9 的 `docs/AI协作/工作包/F9-ContentDemoPolish.md` 用于首批 Demo 内容切片、手感 / 可读性打磨、固定斜俯视资产占位规范和手动 checklist；F8 的 `l1-smoke`、`replay-smoke`、`rng-audit`、四条 checked-in replay runner 和 `perf-probe` 是内容扩展的回归护栏。正式客户端默认 viewport 为 1920×1080，窗口禁止任意拖拽缩放并采用 `canvas_items + keep` 保比例黑边策略，GameplayHud / LevelUpPanel 已改为锚点与容器布局；GameplayHud 现在提供按住 `show_stats_panel` action（默认 Tab）的详细数值面板，显示期间不暂停；首轮手动试玩反馈已补朝向指示、受击闪白、背景参照、GAME_OVER 计时冻结和持续刷怪，玩家生命体系已改为 600.0 浮点血量并新增 `health_regen` 自动生命恢复，接触伤害已改为玩家侧 `damage_invulnerability_duration` 无敌窗口裁决，敌人中心已按 `enemies.csv.separation_radius` 做小范围排斥以避免完全重叠，玩家中心也通过 `player_separation_radius` 提供不可重叠区域并在碰到敌人分离圈时只推开敌人，经验球与升级三选一已接入 `growth.csv` / `growth_pools.json`，升级选择后有 HUD 获得反馈，`enemies.csv.visual_color` 支持数据化敌人占位色；敌人生态 AI 首片已接入 `enemy_ai_profiles.json`、`enemies.csv.ai_profile_id`、`tag_enemy_prey` / `tag_enemy_predator` / `tag_enemy_territorial` 和 `Enemy.ai_debug_summary()`，当前已有追猎者、疾行者、潜猎者与壁垒四种敌人，怪物可按 profile 接近玩家、逃离威胁、狩猎其他怪物、守出生点或冲锋。

> 有限地图可见边界和逻辑边界当前都由 `MapManager.boundary_points()` / `boundary_half_extents()` 定义为贴住格线的菱形；玩家和敌人中心点由 `set_movement_diamond_boundary()` 约束。排查敌人越界时先看 `GameplayRunLoop._apply_enemy_movement_bounds()`、`Enemy.set_movement_diamond_boundary()` 与 `runtime-smoke` 的敌人边界断言。

> F9 起默认键鼠瞄准已从 4 方向改为鼠标相对玩家 / 视口中心方向；子弹可任意角度发射。当前正式视角为固定斜俯视 2.5D：`CenteredCamera` 保持屏幕水平、玩家居中和等比缩放，不滚转整个 2D 画面，也不压缩某个轴；鼠标瞄准会把屏幕偏移按当前 canvas transform 换算回世界方向；`Player` 仍是 `CharacterBody2D` 并按 2D 平面移动，表现层通过 `Player3DVisual` 显示低模 3D 胶囊，斜俯视感后续由哈迪斯式舞台地面、障碍物、遮挡层级和敌人 / 场景视觉层承担。敌人占位表现和玩家 2.5D 视觉都只做左 / 右两种朝向。方向键、手柄右摇杆和 D-pad 继续作为无鼠标动作时的兜底输入。

### 5.2 系统依赖图（Mermaid，AI 改动前先看影响范围）

```mermaid
flowchart LR
  subgraph Infra[基础设施]
    Mod[ModLoader]
    Loc[Localization]
    Set[Settings]
    Ana[Analytics]
    RNG[RNG]
    Rep[Replay]
    Clk[GameClock]
    Plat[PlatformServices]
  end

  subgraph Hub[协调中枢]
    GS[GameState]
    UIM[UIManager]
    Pool[PoolManager]
  end

  subgraph Resource[资源管理]
    Save[SaveManager]
    Aud[AudioManager]
  end

  Data[(client/data/<br/>CSV / JSON)]
  Loader[DataLoader]
  ME[ModifierEngine]
  Combat[Combat<br/>伤害结算]
  SE[StatusEffectComponent]

  Input[InputController]
  Player[Player]
  Weapon[WeaponSystem]
  Skill[SkillSystem]

  Spawner[Spawner]
  Director[WarzoneDirector]
  Enemy[Enemy / EnemyAI]
  Hazard[HazardSystem]
  Item[ItemSystem]
  Growth[GrowthSystem]
  Meta[MetaProgressionSystem]

  Map[MapManager]
  Cam[Camera2D]
  UI[UI/HUD<br/>PauseMenu/...]

  Mod -. 本地 mod 数据 patch .-> Loader
  Data --> Loader --> Player & Weapon & Skill & Enemy & Item & Growth & Meta & Spawner & Director & Hazard & Map
  Set --> Player & Weapon & Input & UIM & Aud
  Loc --> UIM & Item
  Ana <-- 埋点 --- Player & Enemy & Item & Growth & Meta & Spawner & GS & Save
  RNG --> Map & Spawner & Item & Growth & Meta & Enemy & Combat
  Clk --> Spawner & Director & Hazard & Weapon & Skill & SE
  Rep -. 录制/重放 .-> Input & RNG & Clk & GS
  Plat -. 成就/状态/overlay/Lobby .-> UI & Meta & GS

  GS --> UIM
  GS --> Growth
  GS --> Meta
  GS -.- Rep
  UIM --> UI
  Pool --> Weapon & Spawner & Hazard & Item & Aud

  Input --> Player --> Weapon
  Input --> Skill
  Weapon --> Combat
  Skill --> Combat
  Skill --> SE
  SE -. 状态宿主 .- Player & Enemy & Skill
  Save -. run 快照 .- Player & Enemy & Skill
  Enemy --> Combat
  Combat --> Player & Enemy
  Combat -.- SE
  Director --> Spawner
  Map --> Player & Spawner & Hazard
  Spawner --> Enemy
  Enemy -. 掉落经验 .-> Growth
  Player -.- Cam
  ME -. 修正器叠加 .- Player & Weapon
  Item -. 注册 modifiers/behaviors .- ME
  Growth -. 升级奖励 .- ME
  Meta -. 永久升级 .- ME
  SE -. 注入 modifier .- ME

  Save -. meta/run kind .- GS
  Save -. run skill snapshot .- Skill
  Save -. meta kind .- Meta
  Aud -. play_sfx/music .- Combat & UI & Item

  classDef infra fill:#eef,stroke:#88a;
  classDef hub fill:#fee,stroke:#a88;
  classDef res fill:#efe,stroke:#8a8;
  class Mod,Loc,Set,Ana,RNG,Rep,Clk infra;
  class GS,UIM,Pool hub;
  class Save,Aud res;
```

> 改某个模块前先在图中追踪上下游箭头，避免遗漏影响。新增系统模块时**同步更新此图**（规则 14）。
> 三类节点：**基础设施**（蓝） / **协调中枢**（红） / **资源管理**（绿）。

## 6. 红线（最易踩坑）
- ❌ 硬编码可调数值、玩家可见文本、键盘按键 / 手柄按钮 / 手柄轴、约定字符串；❌ 新增数值 / 文案字段却不更新 `client/data/README.md` / `client/locale/README.md`
- ❌ 用中文短文本密度决定 UI 尺寸；新增 / 修改玩家可见 UI 文案或布局时必须切到英文 `en` 验收按钮、面板、HUD、升级选择和结算不截断、不溢出、不遮挡
- ❌ 为每个遗物/道具写独立硬编码分支
- ❌ 为某个角色 / 技能 / 遗物 / 道具写 `if id == ...` 的一次性破限分支（必须 capability / primitive / strategy 化）
- ❌ 为某个游戏模式复制一套角色 / 遗物 / 敌人资源，或用 `if mode_id == ...` 写模式专属内容分支（模式应通过资源池、权重、tags、availability、capability / strategy 组合）
- ❌ 写死唯一玩家、唯一队伍或“玩家只打敌人 / 敌人只打玩家”的关系（未来多人 PvE / PvP 预留要求使用 actor / participant / team / intent / Combat 统一边界）
- ❌ 相机开启 `limit` / `drag margin`（必须玩家恒居中）
- ❌ 直接 `instantiate`/`queue_free` 高频实体（必须 `PoolManager.acquire/release`）
- ❌ 直接读 `Time.get_ticks_msec()` 等非确定时间源（必须 `GameClock`）
- ❌ 直接调用 `randi()` / `randf()` / `randi_range()`（必须 `RNG.<stream>`）
- ❌ 直接读写 `get_tree().paused` 或自管"in_game"布尔变量（必须 `GameState`）
- ❌ 直接 `add_child` UI 弹窗（必须 `UIManager.push/pop`）
- ❌ `target.hp -= n` 直接扣血（必须 `Combat.apply_damage(DamageInfo)`）
- ❌ 各自实现 DoT/debuff 叠加逻辑（必须 `StatusEffect` Resource + Component）
- ❌ 存档缺标准头字段、迁移、原子写入、`.bak` 回退或 `.broken` 损坏隔离（必须走 `SaveManager`）
- ❌ 业务代码 `AudioStreamPlayer.play()`（必须 `AudioManager.play_sfx/music`）
- ❌ 业务系统直接读取 `user://mods`、执行玩家脚本或让 mod 扩展核心契约（mod 必须走 `ModLoader` + `DataLoader` 声明式数据 patch）
- ❌ 业务系统直接调用 Steamworks / GodotSteam / 平台 SDK（Steam 成就、状态显示、overlay、Lobby / 邀请和其他平台能力必须走 `PlatformServices`）
- ❌ 手改 `client/scripts/contracts/*.gd`（自动生成，改 `docs/词表与契约.md` + 跑 `tools/sync_contracts.py`）
- ❌ 把菱形机关误扩展成“所有美术资产都必须菱形”；只有贴地范围优先用菱形，角色 / 敌人 / 拾取 / 子弹 / 障碍 / 特效靠落地点、阴影、遮挡和排序统一斜俯视读法
- ❌ 改了数据 / 文案 / 词表却不跑 `tools/validate_data.py`、`tools/lint_project_rules.py` 或 `tools/sync_contracts.py --check`；改 DataLoader schema 却不跑 `tools/test_data_loader_schema.py`
- ⚠️ 改正式 GDScript 后忽略 `tools/lint_semantic_rules.py` 的 advisory warning；第三档不阻塞 CI，但提示需要人工判断的语义风险
- ❌ review 时跳过 lint / test / docs check 输出，直接让 LLM 全仓“感觉一下”规则是否符合；正式 review 必须先工具后 diff
- ❌ 新增 / 修改长期代码模块却没有对应详细 `docs/代码/` 模块文档、或用简短自动摘要替代维护文档
- ❌ 新写 / 修改 GDScript 却不遵守 Godot 4.7 官方 GDScript style guide 的命名、代码顺序、空白、布尔操作符、注释和类型标注，或触碰 `.gd` 后不跑 `tools/lint_gdscript_rules.py`；❌ 借代码规范名义批量重排无关旧脚本
- ❌ 面向用户的回复默认使用英文或其他语言（除非用户明确要求、引用原文或目标文件语言要求）
- ❌ 用户问有没有问题 / 风险时，为了显得有用而硬找问题、过度优化或提出无必要改动（没发现问题就明确说没有问题）
- ❌ 用户提出需求后不先评估落地前景、性价比、复杂度和主要风险，闷声做到最后才暴露重大隐患
- ❌ 需求、术语、验收标准、授权边界或上下文含义不清时，为了推进任务而自行脑补或替用户做高风险假设（必须先问一个简短澄清问题）
- ❌ 上下文总结 / 压缩 / 恢复后，把摘要、`Next Steps`、`current_state.json` 或历史待办当成当前授权执行，而不先对齐用户最后明确指令
- ❌ 大更改后不按 AI Git 提交策略自动 commit，大型代码改动提交前不做事实型 review，或提交前不查 status / diff / log、误 stage 用户脏改动 / `draft/` / `DRAFT/`
- ❌ 读取、搜索、整理、格式化、总结或引用 `draft/` / `DRAFT/` 人工草稿（除非用户明确点名授权）
- ❌ 复活或搬运历史 MVP 临时代码到完整项目 `client/`；MVP 验证经验只能经复盘、设计和 ADR 迁移
- ✅ 改完同步更新规则文件与相关文档（元规则）
- ✅ 重要决策同步进 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与当日会话日志
- ✅ 知识库结构变化后运行 `python tools/docs_health_check.py`
