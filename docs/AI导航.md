# AI 导航（项目索引）

> 本文件是给 AI agent（以及人）的**项目地图**：开始任何任务前先读这里，按指引快速定位，避免盲目全仓搜索。
> 配套：编码规则见 `AGENTS.md` 第 3 步的当前平台规则入口；完整设计见 `游戏设计文档.md`。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是项目索引权威；新增系统、目录、扩展点、AI 工具入口或依赖图变化时，必须同步 GDD / 词表 / 规则 / 测试策略 / 项目记忆中的对应入口。

---

## 1. 项目是什么
俯视角射击刷宝生存游戏（灵感：手动按住开火的俯视射击身份 + 《星际战甲》与《暗黑》的刷装备 / 刷词条长期追求 + 9×9 无缝模块短刷图 + 《以撒的结合》的道具 / 机关 / 构筑组合）。玩法判定与显示以 2D 矩形格平面为准；F13 默认世界由 81 个 11×11 模块按 seed 组合，模块 `.tscn` 在编辑期烘焙 JSON/TRES，AI candidate 经人工批准后入池；F14 的 EnemyAI 在完整 99×99 静态地形上使用局部有界共享流场、全图 AStar 与视线 / 路径 / 记忆混合感知。
- 引擎：**Godot 4.7.1 stable + GDScript**
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
| `docs/修改建议.md` | 待决策的开放问题（D~E；A/B/C 与 J~R 已归档） |
| `docs/功能建议池.md` | F9 第一轮 Demo 收口后的可选新功能菜单；不是已采纳路线图，用户点名后才推进 |
| `docs/局内刷取参考研究.md` | F12 局内刷取、兴趣点、撤离结算、射击构筑可参考的外部游戏研究；不是已采纳路线图 |
| `docs/AI辅助开发机会清单.md` | 不在运行时接 LLM、只利用 AI 辅助写代码 / 数据 / 工具时的玩法与内容管线机会清单；不是已采纳路线图 |
| `docs/在线服务规划.md` | ADR #150 后未来 GodotSteam + Talo 供应商分层、托管决策门禁、离线 / 安全 / 升级边界；当前不安装、不批准具体在线功能 |
| `docs/小服务器玩法备忘.md` | 低成本异步在线 / 敌巢进化玩法参考；供应商路线已定，但具体玩法不是已采纳路线图 |
| `docs/AI记忆/项目记忆.md` | AI 协作长期索引（长期冷存储；需要背景 / ADR 摘要 / 历史脉络时读） |
| `docs/AI记忆/current_state.json` | 机器可读当前阶段、下一步、最近验证 |
| `docs/TODO.md` | 人工可读未来任务清单 |

## 3. 目录结构与定位

仓库根主要目录：

| 路径 | 内容 |
|------|------|
| `docs/` | 项目文档（设计文档、AI 导航、词表契约、决策记录、AI 记忆等） |
| `client/` | **Godot 4.7.1 项目根**（即 Godot 中的 `res://`） |
| `server/` | 服务器端预留（当前为单机项目，暂占位） |
| `output/steamworks_lab/` | 长期维护的独立 Godot 4.7.1 Steam 应用，专属 App ID `4955670`；ADR #135 后玩家本地多人是单进程同屏（P1 键鼠 + P2–P4 独立手柄），Steam 仍是一设备一玩家，ENet 仅保留内部协议回归。Windows 当前开发 / 发布验证标准为 Godot 4.7.1 + GodotSteam 4.20 GDExtension + Steamworks 1.64，工具锁仍按 4.7 minor 系列保持补丁兼容；插件进忽略的 `addons/godotsteam/`，editor 直接走 `--godot` / `GODOT_PATH`，templates 按 editor 模式走 Godot 标准用户目录或 self-contained `editor_data/`，不再创建 `.toolchain/`；完整边界见其 `README.md`，不等同于正式 `client/PlatformServices` 接入 |
| `tools/` | 本地校验与桥接工具：`sync_contracts.py`、`validate_data.py`、`test_data_loader_schema.py`、`lint_gdscript_rules.py`、`lint_project_rules.py`、`lint_semantic_rules.py`、`docs_health_check.py`、`godot_bridge.py`、`steamworks_lab_toolchain.py` |
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
| `client/addons/`（即 `res://addons/`） | 固定版本 Godot 插件；当前为 `@icons 1.4.0`、`Script-IDE 2.2.3`、运行时摄像机框架 `Phantom Camera 0.11.0.3` 与输入引擎 `G.U.I.D.E 0.14.0`。来源 / 许可 / 版本 / 升级见 `client/addons/README.md`；GUIDE 内部与项目输入边界分别见 `docs/代码/guide.md`、`docs/代码/input_service.md` |
| `client/scenes/boot/main.tscn` | F1 最小启动场景，详见 `docs/代码/formal_client_boot.md` |
| `client/scripts/autoload/` | F2+ 横向 autoload 骨架，已含 `ModLoader` / `DataLoader` / `RNG` / `GameState` / `GameClock` / `PlatformServices` / `Settings` / `InputService` / `Analytics` / `Replay` / `PoolManager` / `SaveManager` / `GearModSystem` / `AudioManager` / `Localization` / `UIManager`；另由 addon 路径稳定注册 `GUIDE` 与 `PhantomCameraManager` |
| `client/scripts/combat/` | F4 起的 `Combat` 统一伤害入口、`DamageInfo`、`StatusEffect` 与 `StatusEffectComponent` |
| `client/scripts/gameplay/` | Gameplay 主循环、玩家 / 武器 / 技能 / 敌人 / 机关 / HUD，F13 `module_world_manager` / `module_chunk` / `module_minimap`，以及 F14 `module_navigation_field`；世界 / 导航 API 见 `docs/代码/module_world_manager.md`，Enemy 感知见 `docs/代码/enemy_ai.md` |
| `client/scripts/ui/` | 阶段性 UI：`title_menu` / `pause_menu` / `game_over_panel` / `gear_mod_panel` |
| `client/scripts/debug/` | debug/dev_tools 专用 `DebugConsole` 与 `GMCommandRegistry`；正式 release 不应加载或导出 |
| `client/tools/` | Godot 项目内 headless smoke 脚本；当前含 gameplay runtime、GearMod、SaveManager、Settings、Replay、RNG 和 DebugTools smoke，并保留仅由用户明确触发的性能 probe |
| `user://settings.cfg` / `user://input_bindings.tres` | 普通设置 schema v2 / GUIDE 输入绑定 schema v1；游戏进度存档仍走 `user://saves/<slot>/<kind>.save`（`meta` / `run` / `replay_index`） |

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
| `docs/修改建议.md` | 待决策项（D~E；A/B/C 与 J~R 已归档） |
| `docs/功能建议池.md` | F9 第一轮 Demo 收口后的可选新功能建议池；只作为人工选择菜单 |
| `docs/局内刷取参考研究.md` | F12 局内刷取、射击构筑、兴趣点路线和撤离带回的外部参考研究；只作为设计参考 |
| `docs/AI辅助开发机会清单.md` | AI 只辅助开发、不进入运行时的玩法机会、内容生产管线、DSL / 编辑器 / 模拟器 / lint 工具候选；只作为人工选择菜单 |
| `docs/在线服务规划.md` | GodotSteam + Talo 未来正式接入的供应商、职责、托管、离线、安全和阶段门禁权威；不代表插件已安装 |
| `docs/小服务器玩法备忘.md` | Talo 可承载的异步在线、敌巢进化、死亡残响、星域污染图等玩法参考；具体功能仍只作为人工选择菜单 |
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
| `docs/AI协作/工作包/` | F13 默认关卡工作包是 `F13-ModularGridWorld.md`；当前后续 EnemyAI 里程碑读 `F14-EnemyNavigationAndPerception.md`。`F13-HandcraftedRooms.md` 仅作 superseded 历史 |
| `docs/AI协作/上下文预算.md` | 不同复杂度 / 任务类型该读哪些文件 |
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
| **加一个敌人** | 在 `client/data/enemies.csv` 加一行基础数值、中心间距、通用 `tag_enemy`、`ai_profile_id` 与 `enemy_*_name` 文案；优先复用 `client/data/enemy_ai_profiles.json` 现有对玩家 profile；远程怪可复用 `ai_action_ranged_attack` 与 `movement.ranged_*` 字段；全新行为先加 / 调 profile 和词表 §12-B action，最后才改 `enemy.gd`。敌人不得把其他敌人设为战斗目标或造成敌方伤害，中心分离只负责防重叠 |
| **改敌人寻路 / 感知** | 先读 `F14-EnemyNavigationAndPerception.md`、`docs/代码/enemy_ai.md`、`docs/代码/module_world_manager.md` 与 ADR #145 / #146；profile 感知参数改 `enemy_ai_profiles.json.perception`，局部活动流场 / 全图静态路径 / 视线改 `module_navigation_field.gd`，半径由最大视觉范围自动推导，门面改 `module_world_manager.gd`，行为消费改 `enemy.gd`。导航 / 感知派生状态不进 run，开放战区保留无 provider 直线兜底 |
| **加一个角色** | 在 `client/data/characters.json` 加一条：基础属性 / tags / capabilities / 控制配置 / `starting_loadout`；角色 id 先登记词表 §12.1，文案用 `character_*` key；起始武器 / 主动道具 / 消耗品必须存在于对应数据文件；新 capability 先登记词表 §12 再实现 |
| **加 / 改武器** | 在 `client/data/weapons.json` 加一条：武器基础属性、子弹池、伤害类型、命中半径和音频 id；文案用 `weapon_*` key；`pool_id` / `damage_type` / `audio_id` 前缀必须来自词表，不实现 WeaponSystem 运行时 |
| **改子弹墙体阻挡 / 穿墙能力** | 先读 GDD §4、ADR #149、`docs/代码/gameplay_runtime.md` 与 `docs/代码/module_world_manager.md`；运行时改 `bullet.gd`，模块墙体层改 `module_chunk.gd`，数值契约改词表 / `weapons.json` / 双端 DataLoader。保持玩家与敌弹默认阻挡、地形 bit 1、圆形首帧重叠 + 本帧扫掠、`PoolManager.release()`、`pierce_count` 与 `wall_pierce` 独立、发射时快照及旧字段默认 false；验证完整 / 技术切片 module-world、runtime/save/L1、headless 和四条黄金回放 |
| **加 / 改技能** | 在 `client/data/skills.json` 加技能定义：`ability_tags`、`activation`、`costs`、`targeting`、`effects`、冷却和 `skill_*` 文案；角色只在 `characters.json.starting_loadout.skill_ids` 引用技能并声明 `skill_resources`，模式池走 `game_modes.resource_pools.skills`；新资源、目标类型、效果原语或 ability tag 先登记词表 §12-C~12-G，状态效果 / 叠加规则先登记 §9-A~§9-B，再扩展 `docs/代码/skill_system.md` / `docs/代码/status_effect_component.md` |
| **加 / 改状态效果** | 先看 `docs/代码/status_effect_component.md`；状态 id 登记 `docs/词表与契约.md` §9-A，叠加规则登记 §9-B，通过 `skill_effect_apply_status` 或未来 on-hit primitive 注入；当前 Player / Enemy / SkillSystem 自身已实现 `apply_status_effect()` 和 owned ability tag 查询，DoT 由状态组件按 `GameClock` tick 并经 `Combat.apply_damage()` 结算；新可受状态影响实体应照此接入；状态存在期间要授予 / 移除 ability tag 时引用 §12-G，不在业务脚本手动计时 |
| **加 / 改机关** | 在 `client/data/hazards.csv` 加一行：伤害、伤害类型、触发间隔、`radius_tiles` 占格尺寸、持续时间和 `hazard_*_name` 文案；`tag_hazard`、`pool_id`、`damage_type` 必须来自词表；初始摆放改 `client/data/map_layouts.json`，普通矩形范围机关复用 `docs/代码/hazard_system.md` 的通用 `Hazard` 运行时 |
| **改地图边界 / 矩形格 / PCG / 人工摆点** | 查 `docs/代码/map_manager.md`；地图尺寸、`grid.cell_width/cell_height`、玩家出生点、安全半径、刷怪边距、PCG 机关数量 / 间距和人工固定摆点都改 `client/data/map_layouts.json`；bounds 是轴对齐矩形，必须分别是 `grid.cell_width/cell_height` 的整数倍；玩家出生点必须在格心，出生安全区可见提示必须是贴住矩形格的矩形，机关按 `radius_tiles` 奇偶吸附到合法锚点（奇数格心、偶数网格顶点），可见和逻辑地图边界必须是同一个矩形，刷怪位置仍用 `RNG.spawn`；玩家和敌人中心移动都应保持在矩形边界内；改完跑 `validate_data`、`runtime-smoke`，机关相关追加 `f9-demo-smoke` |
| **改玩家相机 / 受伤震屏** | 先读 GDD §5.2、ADR #148、`docs/代码/phantom_camera.md` 的项目接入段和 `docs/代码/gameplay_runtime.md`；节点 / 跟随规则改 `gameplay_camera_controller.tscn/.gd`，只调震幅、频率和时间则改 `camera_feedback.json`。保持 Phantom Camera GLUED 严格居中、等比缩放、无滚转，噪声走 `RNG.camera_fx`；改完跑 schema、`settings-smoke`、`runtime-smoke`、headless boot 和 headless editor 加载 |
| **维护 / 升级 Phantom Camera 内部** | 先读 `docs/代码/phantom_camera.md`、`client/addons/README.md`、ADR #148 与目标源码；按 Runtime Core / Resource / Editor / C# wrapper 边界定位，升级只用官方固定版本发布包并逐项重放本地补丁。保持项目固定 Manager autoload、Updater Off、`physics_jitter_fix=0.5`、`RNG.camera_fx` 和 lint 零豁免；完成后跑完整 pre-commit、headless boot、headless editor 与相机回归 |
| **加 / 改模块内容** | 查 `docs/代码/module_authoring_pipeline.md`、`module_world_manager.md`、F13 工作包和数据手册；在 Godot 编辑 `client/scenes/modules/<id>.tscn` 的三层 TileMap + marker，运行 `module-bake`，通过 bake/schema/可达/预算校验后用 `Approve Current` 明确批准；禁止手改生成的 `modules/*.json` / `resources/modules/*.tres` |
| **改模块角色 / 地形 / 摆放 / 边缘 / 审核状态** | 先改 `docs/词表与契约.md` §15，运行 `python tools/sync_contracts.py` 生成对应 `module_*` 常量，再由 DataLoader、ModuleWorldManager 和 JSON 引用；禁止在运行时代码裸写白名单 id |
| **改 AI 模块生产流程** | AI 只在编辑期生成 JSON candidate，不接运行时模型 / 网络生成 / 自动批准；首版人工通过 JSON 审核和修改，不做可视化编辑器。未来工具仍必须读写同一 schema，并保留人工 `approved` 门禁 |
| **加 / 改刷怪波次** | 在 `client/data/spawn_waves.csv` 加一行：模式 id、时间窗、敌人 id / 权重、刷怪间隔、同时存活上限、预算和可选机关权重；敌人 / 机关 / 模式引用必须存在，不实现 Spawner 运行时 |
| **加 / 改战区导演** | 查 `docs/代码/warzone_director.md` 和 F10 工作包；在 `client/data/warzone_directors.json` 改固定 phase、巢变异主题、兴趣点和阶段启用 wave；运行时只按 `GameClock` 时间 gating `spawn_waves.csv`，匹配当前 layout 的兴趣点会通过 `MapManager` 生成 `source="director"` 初始机关；禁止恢复已删除的导演敌人组合元数据、读取玩家状态、隐藏动态调难或运行时接 LLM；改完跑 `validate_data`、`test_data_loader_schema`、`runtime-smoke` 和 `f9-demo-smoke` |
| **加一个遗物/道具** | 在 `client/data/relics.json` 加一条，用 `modifiers` + `behaviors` 描述；文案用 `relic_*` key；**只用 `docs/词表与契约.md` 已登记的 effect / event / stat / tag**，新原语先登记再实现，不实现遗物运行时 |
| **加 / 改主动道具** | 在 `client/data/active_items.json` 加一条：`charge` 声明冷却 / 充能，`use_effects` 引用已登记 effect，文案用 `item_*` key；模式引用走 `game_modes.resource_pools.active_items`，不实现主动道具栏 / 冷却 / 使用效果运行时 |
| **加 / 改消耗品** | 在 `client/data/consumables.json` 加一条：`stack` 声明最大堆叠 / 初始数量 / 单次拾取数量，`use_effects` 引用已登记 effect，文案用 `item_*` key；模式引用走 `game_modes.resource_pools.consumables`，不实现拾取物 / 背包 / 使用输入 / 数量扣减 / 效果运行时 |
| **加 / 改游戏模式** | 在 `client/data/game_modes.json` 声明可用角色 / 武器 / 敌人 / 机关 / 遗物 / 主动道具 / 消耗品 / 成长资源池、权重、禁用列表、参与者 / 队伍预留和轻量覆盖；mode id 先登记 `docs/词表与契约.md` §12-A；资源本体保持模式无关，禁止为模式复制一套资源或在代码写 `if mode_id == ...` |
| **改经验/升级系统** | 查 GDD §7.1 与 `docs/代码/gameplay_runtime.md`；ADR #120 后默认标准模式不启用局内 3 选 1，`mode_standard_survival` 不挂 `growth_pools`，运行时没有候选池时不生成经验球 / 不进入 `GameState.LEVEL_UP`；F4 的池化经验球、`growth.csv`、`growth_pools.json`、`LevelUpPanel` 和 `RNG.ui_choice` 候选抽取保留给未来非默认模式，目标模式必须在 `game_modes.json.resource_pools.growth_pools` 显式引用候选池 |
| **改短刷图默认循环** | 默认标准模式是 F13 9×9 无缝模块世界：中心起点 → 目标 → 独立撤离，主路线约 8–12 模块，不要求清空 81 模块；F12 开放战区仅通过 `--open-warzone` 保留为非默认回归路径。奖励仍先入 `run.pending_loot`，撤离成功才提交 `meta` |
| **改装备 Mod / 局外装配** | 查 GDD §7.2、`docs/AI协作/工作包/F11-GearModLoadout.md` 与 `docs/代码/gear_mod_system.md`；数据 / 契约、运行时首片和最小 UI 已建立：`gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv`、一张提高武器 `damage` 的测试武器 Mod、`enemy_chaser` 玩家击杀 1% 掉落、升级消耗 `gear_mod_dust`、分解返还资源、英雄 / 武器两套 loadout、capacity / drain、开局 modifier snapshot、标题 `GearModPanel`、HUD 暂存提示和 `gear-mod-smoke` 面板按钮流；后续优先补更多 Mod 内容。新增 Mod id / slot / rarity / resource / stack rule 前先登记词表契约，并同步 `client/data/README.md`、locale、DataLoader schema、SaveManager / Gameplay Runtime 文档和 smoke |
| **维护旧局外成长历史** | 旧 `MetaProgressionSystem` 运行时和 UI 已按 ADR #117 删除；项目尚未上线，ADR #118 后旧测试档迁移、`meta_progression.json`、旧 meta 契约常量和旧 `purchased_upgrades` 补偿路径也已删除。需要查历史时看 F6 工作包与 ADR 记录；不要恢复旧永久升级树作为当前成长方向 |
| **改致谢 / 第三方来源** | 同步根目录 `CREDITS.md` 与 `client/data/credits.json`；Godot 编辑器插件同时维护 `client/addons/README.md` 的版本、哈希、本地补丁和升级流程；新增分组标题、角色或用途标签时补 `client/locale/strings.csv` 的 `ui_credits_*` key；发行前复核许可证和 notice |
| **加 / 改美术资产 / 占位表现** | 先看 `docs/IP美术风格.md`、GDD §8.2-A、`docs/代码/gameplay_runtime.md` 的占位表现规则和当前 F9 工作包。敌巢 / 虫族使用骨白、蜡黄、干肉粉、深红、黑紫和少量毒蓝；青、红、白归属虫族 / 敌巢，玩家和玩家子弹默认避开青、红、白，敌方远程攻击可用红色，宝箱与地图兴趣点按功能色区分。贴地范围（机关、AOE、地面符号、房间边界）优先用矩形 / 方形或与矩形地图格对齐；角色、敌人、拾取物、子弹、障碍物和特效不强制矩形，asset brief 必须说明色彩归属、`footprint_shape`、`anchor_point`、`orientation_read`、`sort_layer`、`collision_or_trigger_shape` |
| **加破限角色/道具** | 先判断是否能用 `capabilities` + `modifiers` + `behaviors` 表达；表达不了则新增可复用 primitive / strategy 并登记词表 §12，禁止按 id 写特殊分支 |
| **写/改代码模块** | 先查 `docs/代码文档规范.md` + 对应 `docs/代码/<module_id>.md` + 目标源码；触碰 `.gd` 时按 Godot 4.7 官方 GDScript style guide 整理本次改动，并跑 `python tools/lint_gdscript_rules.py`；GDD / ADR 只在设计冲突、语义不明或新增决策时补读，不能默认整篇加载 |
| **查知识库 / 找文档关系 / 任务路由** | 先看 `docs/AI知识库索引.md` 的任务路由表，需要机器可读元数据时看 `docs/_kb_index.json`，搜索同义词先看 `docs/术语表.md` |
| **续接当前状态 / 下一步** | 先看 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`；上下文压缩后先以用户最后明确指令对齐，`Next Steps` 只作候选参考；需要长期事实 / ADR 摘要 / 历史细节时再看 `docs/AI记忆/项目记忆.md` 和当日会话日志 |
| **查看 / 维护未来任务** | 看 `docs/TODO.md`；F9 第一轮 Demo 收口后的可选新功能菜单看 `docs/功能建议池.md`；F12 局内刷取、兴趣点、撤离带回和射击构筑参考看 `docs/局内刷取参考研究.md`；AI 只辅助开发的玩法 / 内容管线 / 工具机会看 `docs/AI辅助开发机会清单.md`；在线供应商与实施门禁看 `docs/在线服务规划.md`，具体异步玩法候选再看 `docs/小服务器玩法备忘.md`；短期机器状态仍同步 `docs/AI记忆/current_state.json`，设计待决策仍进 `docs/修改建议.md` |
| **改 IP / 世界观 / 英雄包装 / 宣传语** | 先看 `docs/IP设定.md`；涉及视觉风格、色板、阵营色、兴趣点颜色或资产 brief 时追加 `docs/IP美术风格.md`；若改变玩法承诺或系统边界，再同步 GDD / ADR / 术语表 / AI导航 / AI记忆 |
| **选择下一项新功能** | 先看 `docs/功能建议池.md`、`docs/局内刷取参考研究.md`、`docs/AI辅助开发机会清单.md`、`docs/TODO.md` 与 `docs/AI记忆/current_state.json`；用户明确点名功能后，再建立 / 更新工作包、GDD / ADR / 模块文档并实现，不从建议文档自行挑选推进 |
| **评估 / 规划在线服务** | 先看 `docs/在线服务规划.md`、ADR #150、GDD §9.22 / §9.23、`docs/代码/platform_services.md` 与测试策略；供应商路线是 `PlatformServices → GodotSteam`、`OnlineServices → Talo`，不开发自有通用后端。当前不安装；首个功能被用户点名后才重查官方版本、决定 Talo Cloud / 官方自托管并建立工作包 |
| **评估小服务器在线玩法** | 先看 `docs/小服务器玩法备忘.md`，再看 `docs/在线服务规划.md`、GDD §6.7 / §9.23、`docs/代码/replay.md`；GodotSteam + Talo 路线已采纳，但每日挑战、排行榜、死亡残响等具体玩法仍需用户点名，实时多人 / PvP / 强竞技排行榜默认暂缓 |
| **启动 / 推进正式项目** | F13 模块世界已完成；当前 F14 入口为 `F14-EnemyNavigationAndPerception.md`、GDD §5.3、EnemyAI / ModuleWorldManager 文档、数据手册与测试策略。F14.1 活动流场当前半径 8、单次最多访问 289 格；导航 / 感知变更跑 contracts/data/schema/module-world/runtime/save 与黄金回放；性能 probe 仅在用户当次明确要求时运行 |
| **维护正式客户端启动骨架 / 默认分辨率** | 看 `client/README.md`、`docs/代码/formal_client_boot.md`、`docs/代码/gameplay_runtime.md` 与 GDD §9.5-A；当前只设计 / 验收固定 16:9 分辨率，默认 viewport 为 1920×1080，窗口不允许任意拖拽缩放，`canvas_items + keep` 在非 16:9 屏幕上等比缩放并加黑边；其他宽高比是 P3 优化，未来也必须按独立固定预设接入，不做连续响应式适配 |
| **改词表 / 生成常量** | 改 `docs/词表与契约.md` 后跑 `python tools/sync_contracts.py` 和 `python tools/sync_contracts.py --check`，生成 `_contracts.json` 与 `client/scripts/contracts/*.gd` |
| **校验数据 / 文案** | 跑 `python tools/validate_data.py` 与 `python tools/lint_project_rules.py`；改 DataLoader schema 时追加 `python tools/test_data_loader_schema.py`，改项目规则 lint 时追加 `python tools/test_project_rules_lint.py` |
| **校验 GDScript 项目规则** | 跑 `python tools/lint_gdscript_rules.py`；当前第一档覆盖代码段顺序、危险 `:=`、中文硬编码字符串、裸随机 / 时间 / 暂停 API |
| **校验项目规则** | 跑 `python tools/lint_project_rules.py`；当前第二档覆盖数据字段手册登记、locale `zh_CN` / `en` 双语和 release preset debug/dev_tools 禁入 |
| **校验语义风险** | 跑 `python tools/lint_semantic_rules.py`；当前第三档默认非阻塞，提示特殊 id 分支、业务脚本绕过 autoload、正式 gameplay/UI 的长期 Node/Control `.new()` 挂树、缺类型签名、长期脚本缺 `# Doc:` 与未知 contract 常量；已注册对象池 factory 与行模板实例化不报 `runtime-node-construction`；改语义 lint 时追加 `python tools/test_semantic_rules_lint.py` |
| **本地提交前验证** | 已提供 `.pre-commit-config.yaml`；安装后跑 `pre-commit run --all-files` 或提交时自动跑 Stage 1 hook；未安装时按 `docs/AI协作/实时验证回路.md` 的等价命令 |
| **运行 Windows / PowerShell 命令** | 先读当前平台编码规则第 29 节与 `docs/AI协作/工具适配指南.md` 的「Windows PowerShell 稳定执行」；固定字符串优先 `rg -F`，全部 `rg` 选项放在 `--` 前，cmdlet 路径走 `-LiteralPath`，原生程序立即检查 `$LASTEXITCODE`，合法非零码先归一化再进入并行或 fail-fast；`git diff --no-index=1` 仅在输入已校验为文件后表示差异；不混用 Bash 转义、`cmd` 或 `Invoke-Expression` |
| **查 Godot 场景树 / headless 启动** | 跑 `python tools/godot_bridge.py export-tree`、`python tools/godot_bridge.py headless-boot`、gameplay runtime 专用 `python tools/godot_bridge.py --project client runtime-smoke`、F9 Demo / 机关专用 `python tools/godot_bridge.py --project client f9-demo-smoke`、F7 设置 / 设置面板专用 `python tools/godot_bridge.py --project client settings-smoke`、F11 装备 Mod 专用 `python tools/godot_bridge.py --project client gear-mod-smoke`、SaveManager 专用 `python tools/godot_bridge.py --project client save-smoke`、DebugTools 专用 `python tools/godot_bridge.py --project client debug-tools-smoke` / `debug-tools-release-smoke`，以及 F8 `l1-smoke` / `replay-smoke` / `replay-runner` / `replay-runner --rerun-runtime-summary` / `replay-input-smoke` / `capture-golden-replay` / `rng-audit`；默认项目为正式 `client/`。`startup-probe` / `perf-probe` 只在用户当次明确要求性能测试时运行 |
| **用项目级 AI skill** | CodeBuddy / Codex / OpenCode / Claude 分别读取 `.codebuddy/skills/<name>/SKILL.md`、`.codex/skills/<name>/SKILL.md`、`.opencode/skills/<name>/SKILL.md`、`.claude/skills/<name>/SKILL.md`；当前覆盖 Godot 实现、场景验证、Godot 测试诊断、试玩复盘、文档同步、安全提交、事实 review、AI 资源筛选与协作面审计、MCP 评估；外部 GodotPrompter / headless-godot / CCGS / ECC 的有用流程已吸收进项目 skill，不再保留 vendor 来源或 reference 跳转；资源筛选与安装清单见 `docs/AI协作/AI技能资源评估.md` |
| **加一种子弹效果原语** | 先在 `词表与契约.md` 登记 `effect` id → 在效果原语层实现方法/Node → 数据中引用 |
| **改数值（血/伤害/刷怪/掉落）** | 先读 `client/data/README.md`，只改 `res://data/` 对应 CSV / JSON，**绝不改代码常量**；平表数值优先 CSV，复杂配置优先 JSON；新增 / 改字段必须同步数值手册 |
| **预留 / 维护玩家 mod 接口** | 看 `docs/代码/mod_loader.md`、`docs/代码/data_loader.md` 与 GDD §9.21；当前只支持 `user://mods/<mod_id>/mod.json` 声明式 JSON / CSV append，不接创意工坊、不执行玩家脚本、不绕过 `DataLoader` schema；未来创意工坊只作为分发层 |
| **加面向玩家的文本** | 先读 `client/locale/README.md`，在 `res://locale/strings.csv` 加 key + `zh_CN` / `en` 译文；若用户只给一种语言，AI 自动补齐另一语言首版译文，人工复核后代码 / 数据用 `tr("key")` 或 `name_key`；涉及 UI 按钮、面板或 HUD 时以英文 `en` 长度验收尺寸，跑对应 smoke，当前按钮类英文适配由 `settings-smoke` 覆盖 |
| **加一个设置项** | 先在 `Settings` 加配置（键/类型/默认/范围）并接入下游 `setting_changed` 即时生效；只有完成生效链路后才在设置面板显示 UI 控件，暂未接线的预留 key 保留为隐藏 / 禁用 |
| **加一个埋点** | 用 `词表与契约.md` 登记的 `event_name`，调用 `Analytics.track_event(name, params)` |
| **改输入 / 按键 / 手柄 / 重绑定** | 先读 `docs/代码/input_service.md`、词表 §7、ADR #151、Settings / Replay 文档和目标调用方；action 先登记并生成常量，默认映射改 `client/resources/input/`，业务只消费 `InputService` 的 `move` / `aim` Vector2 或 bool intent。GUIDE 只允许由 InputService 访问，InputMap 只允许在 UI bridge / 插件 / 测试边界；绑定保存为 `user://input_bindings.tres`，改完跑 `input-smoke`、`settings-smoke`、`replay-input-smoke`、runtime 与黄金回放 |
| **维护 / 升级 GUIDE 内部** | 先读 `docs/代码/guide.md`、`client/addons/README.md`、ADR #151 与目标源码；升级只比较固定版本官方发布包，重放 autoload、类型、context 单调序号、detector 负轴 / 取消清理和源码头补丁。不得启用自动更新、加 lint 豁免或把插件类型泄露给业务；完成后跑三档 lint、input/settings/replay smoke、headless boot、headless editor 和真实手柄验收 |
| **加 GM 指令 / 调试工具** | 查 GDD 9.20 与 `docs/代码/debug_tools.md`；调试入口只在 debug/dev_tools 构建启用，action 用 `debug_*` 并登记词表 §7；命令必须通过正式系统 API 或受控 `debug_*` API 改状态；release preset 不启用 `dev_tools` 且排除调试脚本 / GM 命令表；改完跑 `python tools/godot_bridge.py --project client debug-tools-smoke` 和 `debug-tools-release-smoke` |
| **加暂停/切换游戏状态** | `GameState.change_state(PAUSED)` 等；UI 通过 `UIManager.push(modal_pause_menu)` 自动联动暂停；F5 首片的 `PauseMenu` 已覆盖继续、保存并退出、重开和回标题，也支持从升级面板上方叠出并恢复回 `LEVEL_UP`；不直接读写 `get_tree().paused`（见 GDD 9.12 / 9.14） |
| **加录制回放/确定性需求** | 走 `Replay`（autoload）；输入只由 `InputService` 记录 / 注入 v2 bool 或 Vector2 intent，播放时隔离 GUIDE 物理输入；随机走 `RNG.<stream>`、时间走 `GameClock`。v1 只在加载时迁移，不重写源文件；改输入 wire 追加 input/replay smoke 和四条黄金回放，改 RNG seed 派生 / 子流集合追加 `rng-audit`（见 GDD 9.9 / 9.18） |
| **接 Steam API / 平台服务** | 先读 `docs/在线服务规划.md`、ADR #150 与 `docs/代码/platform_services.md`；未来固定官方 GodotSteam 版本，只在 `PlatformServices` adapter 内初始化 / 驱动 callback，并承接 Steam 身份票据、成就、Steam-only 统计、富状态、overlay、Lobby / 邀请。当前正式客户端不安装，业务不得直调 Steamworks / GodotSteam |
| **接 Talo / 在线后端** | 当前只规划、不安装。用户点名首个功能后，先在 `output/test_lab` 验证并决定 Talo Cloud / 官方自托管，再新增 `OnlineServices → Talo` adapter；跨平台排行榜 / 统计、Live Config、事件与轻量社交只走该门面，Analytics 可把它作为 sink，SaveManager 仍是本地存档权威。禁止业务直调 `Talo.*`、双写同一排行榜 / 统计或自研通用后端 |
| **维护 Steamworks Slime Lab / 单人 AI 大招与自主游击 / 本地同屏 / 纪录 / App ID / Windows 导出** | 先读 `output/steamworks_lab/README.md` 与 ADR #129 / #132 / #133 / #134 / #135 / #136 / #137 / #138 / #139 / #140 / #141；自动回归只使用 `py -3 tools\steamworks_lab_toolchain.py smoke --suite <目标>`，先目标 suite、交付前 `--suite all`，禁止手写 Godot / PowerShell 双进程命令。ADR #139 的 AI 大招仅在 `PlayMode.SINGLE`：P1 子弹命中 / 普通击杀 / Boss 击杀按 `+1 / +6 / +21` 累积至 100，按 `E` 召唤不可受伤、不吸引火力且自动射击的 10 秒 AI。ADR #140 已把 AI 改为确定性自主游击 / 预判闪避：避开敌弹、普通敌人、Boss 和障碍物，常规距 P1 使用 210 px 硬限、超过 220 px 复位；须松开再按住 `E` 发起合体，AI 高速归队到 92 px 内并停靠 0.8 秒后自动同意，持续时间不重置且每次召唤最多一次。目标 battle 1/1、local-couch 与权威 `smoke --suite all` 已通过；all 含 battle 5/5、动态端口 ENet、最大分片仍不超过 900 字节且受保护文件未改变。AI 不进入真人 roster、强化、纪录、玩家卡或快照；同屏 / Steam、wire、存档与正式 `client` 不变。runner 隔离每个 `user://`、验证精确 `ALL PASS` / 致命日志、动态分配 ENet 端口并保护玩家真实设置 / 存档与源码 `steam_appid.txt=4955670`；测试 fixture 必须在 `_ready()` 前注入。源码 App ID 文件永久保留，只从 release 排除。本地同屏由 `local_input_router.gd` 分配 P1 键鼠与 P2–P4 手柄；Steam Lobby 不混入同屏玩家，ENet 只守协议。纪录按单人 / 多人分开，未来 schema 保持写保护，Steam Client 必测权威 Game Over 完整链路。快照应用层仍是 `Dictionary`，wire 层为 FastLZ + 900 字节分片，Lobby `lab_version=2`。Windows 当前开发 / 发布验证标准为普通 Godot 4.7.1 + GodotSteam 4.20 GDExtension + Steamworks 1.64；工具锁继续接受 Godot 4.7 minor 系列，setup / verify / export-release 直接走 `--godot` / `GODOT_PATH`；export-release 按 editor 模式校验标准用户目录或 self-contained `editor_data/` 的精确版本 templates，禁止重建 `.toolchain/`。真实手柄、SteamPipe、Depot 和双账号 Steam smoke 仍需外部验证；不能把 Lab 直连 SDK 当成正式 `client/PlatformServices` 已接入 |
| **加 / 验证回放测试** | `Replay` 负责 `.replay` envelope 与 `user://replays/` 文件；F8 基线用 `python tools/godot_bridge.py --project client replay-smoke` 验证最小录制、保存 / 读取、摘要和 data fingerprint roundtrip，用 `python tools/godot_bridge.py --project client replay-runner` 读取 `.replay` 并比较 summary / expectation，用 `python tools/godot_bridge.py --project client replay-runner --rerun-runtime-summary` 生成临时输入播放 smoke replay 并播放 `input_events`，用 `python tools/godot_bridge.py --project client replay-input-smoke` 验证 gameplay 输入录制首片；`golden_basic_run.replay` 可用 `capture-golden-replay` 重录，`golden_pause_resume.replay` 可用 `capture-golden-replay --golden-scenario golden_pause_resume` 重录，`golden_full_death.replay` 可用 `capture-golden-replay --golden-scenario golden_full_death` 重录，`golden_level_up_choice.replay` 可用 `capture-golden-replay --golden-scenario golden_level_up_choice` 重录，四者都用 `replay-runner --replay-file ... --rerun-runtime-summary` 重跑真实运行时摘要与 `run_summary.frame_samples` / 场景语义字段 diff。ADR #120 后 `golden_level_up_choice` 由测试 harness 显式启用成长池，默认标准模式仍由 `runtime-smoke` 断言不进入 `LEVEL_UP`。后续遗物协同 golden 仍等对应运行时存在后再补。 |
| **加平衡测试 / Headless 模拟** | 通过 `AIPlayer` 接口接入；`Spawner` / `MapManager` / `RNG` 都接受外部 seed（见 GDD 9.10）。用户明确要求性能测试时，可用 `python tools/godot_bridge.py --project client perf-probe` 输出 schema v2 可比较基线 JSON，包含 30 帧 warmup 后 180 帧 avg / p95 / p99 / max 帧时间、active / peak entity counts、pool final stats / peak active、等级、击杀、状态和预算状态 |
| **修 Steamworks Lab AI 归队 / 合体** | `SteamLabSlimePlayer.set_input_drive_scale()` 必须与 AI 模式 `max_speed` 同步，保证 `TACTICAL / DODGE / RECALL` 的 `1.18× / 1.45× / 1.75×` 是真实软体速度；归队进入 92 px 后要跟随移动中的 P1，单人离线 `_update_gameplay()` 必须驱动权威 0.8 秒合体进度，并在合体后继续把 P1 输入路由给 driver。回归须走真实 E 按下 / 释放、移动 P1 和真实 `SlimeBody` 物理，禁止在归队后瞬移 AI 或直接调用内部合体函数代替主循环。最新目标 battle 1/1、local-couch 与权威 all-suite 已通过，all 含 battle 5/5、动态端口 ENet 和 635 字节最大快照分片；玩法仍以 ADR #140 为准，不新增 wire / 存档边界。 |
| **加 UI 弹窗** | `UIManager.push(scene)`；场景根节点 `@export modal/pauses_game/music_duck` 元数据；不 `add_child` UI（见 GDD 9.14）；按钮、标题和说明布局以英文 `en` 文案长度验收，不按中文短文本定窄宽 |
| **加新敌人/子弹/特效**（高频实体） | `PoolManager.acquire(pool_id)` / `release(node)`；新池 id 在词表 §8 登记；实现 `_pool_reset()`（见 GDD 9.13） |
| **加伤害逻辑** | 走 `Combat.apply_damage(target, DamageInfo)`；`damage_type` 在词表 §9；保留 source / target / team / friendly_fire 模式规则边界；不 `target.hp -= n`（见 GDD 9.15.1） |
| **加持续效果（DoT/控制/debuff）** | 用 `StatusEffect` Resource + 目标实体的 `StatusEffectComponent.apply()`；id 在词表 §9-A；明确 `stack_rule`；DoT 用 `damage_type`、`magnitude`、`tick_interval`，tick 伤害仍走 `Combat.apply_damage()`（见 GDD 9.15.2） |
| **加存档/读档** | 走 `SaveManager.save/load`；必须支持 `meta` 局外成长和 `run` 暂停退出续局；schema 必带 `version` / `kind` / `slot` / `created_at` / `updated_at` / `game_version` / `data_hash`；写入用 `*.tmp` 原子替换、保留 `.bak`、坏档进 `.broken/`，payload 写入前会 JSON 归一化再算 hash；F5+ 已把 run payload 接到暂停保存 / 标题继续，`ui_restore` 可恢复普通游玩、暂停菜单、升级选择面板和升级面板上方暂停菜单叠层，run payload 当前包含地图 / 机关 / 玩家 / 敌人 / 子弹 / 掉落 / RNG / GameClock，坏档续局失败会回标题提示重置，并新增 `save-smoke` 覆盖 run roundtrip、`.bak` 回退、双坏档隔离、高精度浮点 hash 与 v1 -> v2 迁移；扩展字段时同步 `docs/代码/gameplay_runtime.md` 与 `docs/代码/save_manager.md`；save kind 先登记词表 §14；与 `Settings` 职责分开（见 GDD 9.16） |
| **加音效/BGM** | `AudioManager.play_sfx/play_music`；id 在词表 §10；不直接 `AudioStreamPlayer.play()`（见 GDD 9.17） |
| **执行 AI 高频任务** | 先查 `docs/AI协作/任务模板/`；任务不在模板里 → 按 `docs/AI协作/上下文预算.md` 先判 S/M/L/XL 复杂度，再决定读取范围 |
| **拆分复杂 / 专业任务给 subagent** | 项目默认授权支持 subagent 的平台主动调度 `.codebuddy/agents/` / `.codex/agents/` / `.opencode/agents/` / `.claude/agents/` 下对应角色；只读小任务或直接实现更高效时不必强行拆分；平台不支持或外层工具策略限制时，把同名 `.md` 当 prompt 模板读 |
| **评估 / 吸收外部 AI 工具仓库** | 先用 `ai-resource-curator`，读 `docs/AI协作/AI技能资源评估.md` 与 `docs/AI协作/上下文预算.md`；ECC 这类大仓按 `docs/AI协作/ECC工具吸收清单.md` 的 README / 全工具面清单 / 候选全文读取流程执行；默认不安装外部 hooks、MCP、CLI、dashboard、plugin 或 vendor tree |
| **提交 / 收尾大更改** | 按 `AGENTS.md` 的 AI Git 提交策略：大更改默认自动 commit，细微改动不提交；大型代码改动提交前按 `docs/AI协作/代码审核流程.md` 追加工具先行的事实型 code review；提交前看 `git status --short` / `git diff` / `git log --oneline -10`，只 stage 本次任务文件 |
| **写/改测试** | 看 `docs/测试策略.md`：L0~L5 金字塔 + 各层必测清单 + 里程碑要求 + 测试义务表 |

## 5. 核心系统模块

### 5.1 模块清单
**业务模块**：`Player` / `WeaponSystem` / `Bullet` / `SkillSystem` / `Enemy(EnemyAI)` / `Spawner` / `ModuleWorldManager`（F13 世界门面）/ `ModuleNavigationField`（F14 共享静态导航）/ `WarzoneDirector`（仅 F12 非默认开放战区）/ `HazardSystem` / `ItemSystem` / `GrowthSystem` / `GearModSystem` / `ModifierEngine` / `MapManager` / `GameplayCameraController` / `PhantomCamera2D` / `PhantomCameraHost` / `Camera2D` / `DataLoader` / `PauseMenu` / `Combat` / `StatusEffectComponent`。

**Autoload 单例（横向基础设施 + 协调中枢）**：
- 一条**本地 mod 基础设施**：`ModLoader`（扫描 `user://mods/<mod_id>/mod.json`，给 `DataLoader` 提供声明式数据 patch 与允许的动态契约扩展；创意工坊未来只作为分发层）
- 一条**平台服务基础设施**：`PlatformServices`（Steam 优先预留成就、统计、富状态 / 状态显示、overlay、Lobby / 联机入口和用户身份；其他平台后续走 provider adapter）
- 一条**未来在线服务规划**：`OnlineServices` 尚未实现；ADR #150 只锁定未来以 Talo provider 承接跨平台身份、排行榜 / 统计、Live Config、事件和轻量社交，不计入当前 autoload 矩阵
- 三条**协作基础设施**：`Localization` / `Settings` / `Analytics`
- 一条**输入基础设施**：vendored `GUIDE` 只解释物理设备与资源图；项目 `InputService` 是生成 action、归一化 intent、context、重绑定、提示和回放覆盖的唯一业务门面
- 两条**确定性基础设施**：`RNG`（种子化随机，子流分流）/ `GameClock`（暂停冻结时间源）
- 一条**回放基础设施**：`Replay`
- 一条**vendored 相机协调基础设施**：`PhantomCameraManager`（项目固定 autoload；节点注册、priority / layer 选机与噪声广播）
- 一条**AI 协作基础设施**：见 `docs/AI协作/`（非 autoload）
- 三个**协调中枢**：`GameState`（流程状态机）/ `UIManager`（界面栈）/ `PoolManager`（通用对象池）
- 两个**资源管理**：`SaveManager`（存档 + 迁移）/ `AudioManager`（音频统一接口）

当前正式客户端以 F13 模块世界作为 `mode_standard_survival` 默认关卡 carrier：`ModuleWorldManager` 按 run seed 组合 81 槽、管理内容敏感 map hash、模块迷雾和最多 3×3 活跃 chunk；F14 的 `ModuleNavigationField` 从完整 assignment 构建静态 99×99 mask，玩家跨格时只在按最大视觉范围推导的半径 8 窗口内更新确定性共享流场，单次最多访问 289 格，并为 Enemy 提供路径距离、全图 AStar、地形视线和敌人半径走廊。EnemyAI schema v3 按视线、路径和 1.5 秒最后已知位置感知，畅通直追、受阻绕行；冲锋 / 远程受墙体门禁，玩家唯一目标、敌方友伤拒绝与中心分离边界不变。`--module-world-technical-slice` 保留中心 3×3 / 外圈 72 槽封锁入口，F12 开放战区通过 `--open-warzone` 保留并使用无导航 provider 的直线兜底。run 保持 v4，导航 / 感知缓存不保存。常规验收入口是 contracts/data/schema、`module-world-smoke`、`module-world-technical-slice-smoke`、`save-smoke`、`runtime-smoke`、headless 与四条黄金回放；ADR #143 后性能测试仅由用户当次明确触发。

> 普通开始新局 / 重开会生成新的 `RNG` run seed；继续游戏恢复 run snapshot；回放、smoke、golden 和调试复现仍应显式固定 seed 或走工具启动路径。

> 有限地图可见边界和逻辑边界当前都由 `MapManager.bounds()` / `boundary_points()` / `boundary_half_extents()` 定义为贴住格线的轴对齐矩形；玩家和敌人中心点由 `set_movement_bounds()` 约束。排查敌人越界时先看 `GameplayRunLoop._apply_enemy_movement_bounds()`、`Enemy.set_movement_bounds()` 与 `runtime-smoke` 的敌人边界断言。

> F9 起默认键鼠瞄准已从 4 方向改为鼠标相对玩家 / 视口中心方向；子弹可任意角度发射。ADR #124 后当前正式视角改回俯视角 2D；ADR #148 后 `CenteredCamera` 由 Player 子场景内的 Phantom Camera GLUED PCam 驱动，仍保持屏幕水平、玩家居中和等比缩放，不滚转、不平滑、不压缩某个轴。玩家有效受伤可按 `camera_feedback.json` 触发可关闭的位移震屏；鼠标瞄准会把屏幕偏移按当前 canvas transform 换算回世界方向。`Player` 仍是 `CharacterBody2D` 并按 2D 平面移动，正式玩家场景不再挂 `Player3DVisual`，默认 2D 占位按完整 `aim_direction` 绘制朝向标记。方向键、手柄右摇杆和 D-pad 继续作为无鼠标动作时的兜底输入。

> ADR #151 / #152 后不再由 gameplay 动态创建 InputMap action。GUIDE 0.14.0 维护物理映射，`InputService` 将 `move` / `aim` 统一成 Vector2、锁存短按到物理 tick、跟踪最近设备并管理 gameplay / ui / debug context；Replay 只记录并读取 v2 最终 intent。旧 `move_*` / `aim_*` action 与 Settings 输入迁移已删除，同名 `input.*` 仅是当前 GUIDE binding id。

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
    Guide[GUIDE]
    Input[InputService]
    Clk[GameClock]
    Plat[PlatformServices]
    Online[OnlineServices<br/>规划中]
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

  Player[Player]
  Weapon[WeaponSystem]
  Bullet[Bullet]
  Skill[SkillSystem]

  Spawner[Spawner]
  ModuleWorld[ModuleWorldManager]
  ModuleNav[ModuleNavigationField]
  Director[WarzoneDirector]
  Enemy[Enemy / EnemyAI]
  Hazard[HazardSystem]
  Item[ItemSystem]
  Growth[GrowthSystem]
  GearMod[GearModSystem]

  Map[MapManager]
  CamCtl[GameplayCameraController]
  PCam[PhantomCamera2D]
  PCHost[PhantomCameraHost]
  PCamMgr[PhantomCameraManager]
  Cam[Camera2D]
  UI[UI/HUD<br/>PauseMenu/...]
  GodotSteam[GodotSteam<br/>未来官方 adapter]
  Talo[Talo<br/>未来在线后端]

  Mod -. 本地 mod 数据 patch .-> Loader
  Data --> Loader --> Player & Weapon & Skill & Enemy & Item & Growth & GearMod & Spawner & ModuleWorld & Director & Hazard & Map & CamCtl
  Set --> Input & UIM & Aud & CamCtl
  Guide -. 物理 action / context / remapping .-> Input
  Loc --> UIM & Item
  Ana <-- 埋点 --- Player & Enemy & Item & Growth & GearMod & Spawner & GS & Save
  RNG --> Map & Spawner & Item & Growth & GearMod & Enemy & Combat & PCam
  Clk --> Spawner & Director & Hazard & Weapon & Skill & SE
  Input -. 录制 v2 intent .-> Rep
  Rep -. playback override .-> Input
  Rep -. seed/tick/state .-> RNG & Clk & GS
  Plat -. 成就/状态/overlay/Lobby .-> UI & GearMod & GS
  Plat -. Steam Web API Ticket .-> Online
  Plat -. 未来 provider .-> GodotSteam
  Online -. 未来 provider .-> Talo
  Ana -. 可选在线 sink .-> Online
  Save -. 仅受控同步载荷 .-> Online

  GS --> UIM
  GS --> Growth
  GS --> GearMod
  GS -.- Rep
  UIM --> UI
  Pool --> Weapon & Bullet & Spawner & Hazard & Item & Aud

  Input --> Player --> Weapon
  Input --> Skill & UIM & UI
  Weapon --> Bullet --> Combat
  Skill --> Combat
  Skill --> SE
  SE -. 状态宿主 .- Player & Enemy & Skill
  Save -. run 快照 .- Player & Enemy & Skill
  Enemy --> Combat
  Combat --> Player & Enemy
  Combat -. 玩家有效伤害 .-> CamCtl
  Combat -.- SE
  GS -. 默认模块世界创建/驱动 .-> ModuleWorld
  ModuleWorld --> Map
  ModuleWorld --> ModuleNav
  ModuleWorld -. ModuleChunk 地形 bit 1 .-> Bullet
  ModuleNav -. 共享流场/视线/AStar .-> Enemy
  ModuleWorld -. JSON placement（经 RunLoop 对象池/Combat） .-> Spawner & Hazard
  ModuleWorld -. assignment/hash/fog/slot snapshot .- Save
  Bullet -. wall_pierce 发射快照 .- Save
  Director --> Spawner
  Map --> Player & Spawner & Hazard
  Spawner --> Enemy
  Enemy -. 掉落经验 .-> Growth
  Player --> CamCtl --> PCam --> PCHost --> Cam
  PCamMgr -. 注册 / priority / layer / noise .-> PCam & PCHost
  ME -. 修正器叠加 .- Player & Weapon
  Item -. 注册 modifiers/behaviors .- ME
  Growth -. 升级奖励 .- ME
  GearMod -. loadout modifiers .- ME
  GearMod -. 武器 Mod .- Weapon
  GearMod -. 英雄 Mod .- Player
  SE -. 注入 modifier .- ME

  Save -. meta/run kind .- GS
  Save -. run skill snapshot .- Skill
  Save -. meta kind .- GearMod
  Aud -. play_sfx/music .- Combat & UI & Item

  classDef infra fill:#eef,stroke:#88a;
  classDef hub fill:#fee,stroke:#a88;
  classDef res fill:#efe,stroke:#8a8;
  class Mod,Loc,Set,Ana,RNG,Rep,Clk,Plat,Online,GodotSteam,Talo,Guide,Input,PCamMgr infra;
  class GS,UIM,Pool hub;
  class Save,Aud res;
```

> 改某个模块前先在图中追踪上下游箭头，避免遗漏影响。新增系统模块时**同步更新此图**（规则 14）。
> 三类节点：**基础设施**（蓝） / **协调中枢**（红） / **资源管理**（绿）。
> `ModuleWorldManager` 不是 autoload：由 `GameplayRunLoop` 在 `ActiveWorld` 下创建并驱动，依赖世界 / 注册表 / 模块 JSON。它组图、转坐标、管迷雾、复用最多 9 个 `ModuleChunk`、保存槽位状态，并持有不创建 Node 的 `ModuleNavigationField`；Enemy 只经 Manager 门面查询导航。对象池生成、击杀归因、目标 / 撤离和战利品仍由 `GameplayRunLoop` 负责。
> `OnlineServices`、GodotSteam 与 Talo 节点是 ADR #150 的未来规划，不表示当前 autoload、插件或网络依赖已经存在；正式 `client` 当前仍由 `PlatformServices` 的 `none` 后端离线退化。

## 6. 红线（最易踩坑）
- ❌ 硬编码可调数值、玩家可见文本、键盘按键 / 手柄按钮 / 手柄轴、约定字符串；❌ 新增数值 / 文案字段却不更新 `client/data/README.md` / `client/locale/README.md`
- ❌ 业务代码直接访问 GUIDE / `Input` / `InputMap`、按物理设备写分支或自己维护 context / 重绑定；必须走生成 action 与 `InputService`，InputMap 仅限 GUIDE / InputService UI bridge / 测试
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
- ❌ 业务系统直接调用 Talo / 在线 HTTP API、同时由客户端和 Talo 双写同一排行榜 / 统计、或绕过 ADR #150 自研通用后端（未来必须走 `OnlineServices`；当前不安装）
- ❌ 手改 `client/scripts/contracts/*.gd`（自动生成，改 `docs/词表与契约.md` + 跑 `tools/sync_contracts.py`）
- ❌ 用菱形 / 等距地图格继续模拟斜俯视；当前地图格、边界、机关危险区、兴趣点 footprint 和撤离区默认都是水平 / 垂直矩形俯视格，角色 / 敌人 / 拾取 / 子弹 / 障碍 / 特效靠俯视轮廓、方向标记、功能色和真实判定形状保持读法
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
- ❌ 在 PowerShell 中套用 Bash 的引号转义、把 `rg` 选项写到 `--` 后、误判工具退出码、未校验输入就把 `git diff --no-index=1` 当作差异，或把未归一化的预期非零码直接放进并行 / fail-fast 调度
- ❌ 大更改后不按 AI Git 提交策略自动 commit，大型代码改动提交前不做事实型 review，或提交前不查 status / diff / log、误 stage 用户脏改动 / `draft/` / `DRAFT/`
- ❌ 读取、搜索、整理、格式化、总结或引用 `draft/` / `DRAFT/` 人工草稿（除非用户明确点名授权）
- ❌ 复活或搬运历史 MVP 临时代码到完整项目 `client/`；MVP 验证经验只能经复盘、设计和 ADR 迁移
- ✅ 改完同步更新规则文件与相关文档（元规则）
- ✅ 重要决策同步进 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与当日会话日志
- ✅ 知识库结构变化后运行 `python tools/docs_health_check.py`
