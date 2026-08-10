# AI 导航（项目索引）

> 本文件是给 AI agent（以及人）的**项目地图**：开始任何任务前先读这里，按指引快速定位，避免盲目全仓搜索。
> 配套：编码规则见 `AGENTS.md` 第 3 步的当前平台规则入口；完整设计见 `游戏设计文档.md`。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是项目索引权威；新增系统、目录、扩展点、AI 工具入口或依赖图变化时，必须同步 GDD / 词表 / 规则 / 测试策略 / 项目记忆中的对应入口。

---

## 1. 项目是什么
俯视角射击 Roguelike（灵感：手动按住开火的俯视射击身份 + 《雨中冒险 2》《以撒的结合》的单局掉落、叠加成长与构筑组合 + 7×7 无缝模块探索）。玩法判定与显示以 2D 矩形格平面为准；默认世界由 49 个 11×11 模块组成。Gear Mod 棋盘与世界同为 7×7 坐标：中心核心派生主英雄被动，初始解锁 13 格；地面 Mod 只有在拾取事务中确认到合法四邻格后才生效，清理意识核或死亡后整盘清空。
- 引擎：**Godot 4.7.1 stable + GDScript**
- IP 方向：项目代号 **`WASD`**，正式标题待定且标题页暂不显示副标题。完整清理智能由冷静、愤怒等主 / 副智能碎片组合，以清理集体无意识为行动目标，进入一张 7×7 意识层，清理万物形成的心象，并以清理意识核直接完成本局；意识层来源、AI 立场和清理结果均不解释。
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
| `docs/IP设定.md` | `WASD` 集体无意识 IP、清理智能 / 智能碎片 / 意识层 / 心象 / 意识核定义和叙事留白边界 |
| `docs/IP美术风格.md` | 意识层抽象美术、环境代表色、稳定敌我 / 警示 / 交互功能色、心象可读性和资产 brief 规则 |
| `docs/词表与契约.md` | 所有约定字符串白名单（stat/effect/event/key），**禁止编造** |
| `docs/游戏设计文档.md` | 完整设计 |
| `docs/代码文档规范.md` | 代码变更与对应文档的同步规范 |
| `docs/决策记录.md` | 既定决策与原因，勿误改 |
| `docs/修改建议.md` | 待决策的开放问题（D~E；A/B/C 与 J~R 已归档） |
| `docs/功能建议池.md` | F9 第一轮 Demo 收口后的可选新功能菜单；不是已采纳路线图，用户点名后才推进 |
| `docs/局内刷取参考研究.md` | 历史 F12 刷取 / 撤离参考研究；ADR #188 后不代表当前 Roguelike 路线 |
| `docs/AI辅助开发机会清单.md` | 不在运行时接 LLM、只利用 AI 辅助写代码 / 数据 / 工具时的玩法与内容管线机会清单；不是已采纳路线图 |
| `docs/在线服务规划.md` | ADR #150 后未来 GodotSteam + Talo 供应商分层、托管决策门禁、离线 / 安全 / 升级边界；当前不安装、不批准具体在线功能 |
| `docs/小服务器玩法备忘.md` | 历史旧 IP 下的低成本异步在线玩法参考；供应商路线已定，但具体玩法和敌巢包装均不是当前路线图 |
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
| `.github/` | GitHub Issue / PR 模板与 Actions workflows；当前启用 Stage 1 静态 `docs-check` 与固定 Godot 4.7.1 的 `godot-runtime`（正式 boot、GUT/JUnit、隔离 L1 smoke） |
| `CREDITS.md` | 代码库级致谢与第三方来源清单；游戏内 Credits 数据源为 `client/data/credits.json` |
| `draft/` / `DRAFT/` | 用户人工草稿，AI 禁止读取 / 搜索 / 修改 / 整理 / 引用，除非用户明确点名授权 |

`client/` 下：

| 路径 | 内容 |
|------|------|
| `client/scenes/`（即 `res://scenes/`） | 场景 `.tscn`（Player / Bullet / Enemy / Item / Hazard 等） |
| `client/scripts/`（即 `res://scripts/`） | 脚本 `.gd`，按系统单一职责拆分 |
| `client/scripts/data/` | 不创建 Node 的纯数据解析器；智能碎片组合（内部 hero 字段）、元素组合、技能缩放与配置描述格式化在此共享，禁止按内容 id 特判 |
| `client/data/`（即 `res://data/`） | 可调数值配置（平表 CSV + 复杂 JSON）+ `README.md` 人工调参手册 |
| `client/locale/`（即 `res://locale/`） | 本地化翻译表（CSV → `.translation`）+ `README.md` 多语言文案手册 |
| `client/templates/`（即 `res://templates/`） | 模块等文件脚手架模板；Gear Mod 组件模板在数据配表目录中声明 |
| `client/assets/`（即 `res://assets/`） | 美术 / 音效 |
| `client/addons/`（即 `res://addons/`） | 固定版本插件及 editor-only 工具；GUT 9.7.1 仅供 CLI / CI 且默认不启用 EditorPlugin，GUT、项目 tests 与自有“数据配表”“Module JSON”“VFX 效果库”均由 release preset 排除，契约见 `client/addons/README.md`、`docs/代码/data_table_editor.md`、`module_authoring_pipeline.md`、`visual_effects.md` |
| `client/scenes/boot/main.tscn` | F1 最小启动场景，详见 `docs/代码/formal_client_boot.md` |
| `client/scripts/autoload/` | F2+ 横向 autoload 骨架，已含 `ModLoader` / `DataLoader` / `VisualEffects` / `RNG` / `GameState` / `GameClock` / `PlatformServices` / `Settings` / `InputService` / `Analytics` / `Replay` / `PoolManager` / `SaveManager` / `ContentUnlockSystem` / `GearModSystem` / `AudioManager` / `Localization` / `UIManager`；另由 addon 路径稳定注册 `GUIDE` 与 `PhantomCameraManager` |
| `client/scripts/combat/` | F4 起的 `Combat` 统一伤害入口、`DamageInfo`、`StatusEffect` 与 `StatusEffectComponent` |
| `client/scripts/gameplay/` | Gameplay 主循环、玩家 / 武器 / 技能 / 敌人 / 机关 / HUD，以及 `presentation/` 的 VfxHost / Feedback / ActorPresentation |
| `client/scripts/ui/` | 正式 UI 与 `effects/` 共享动效组件；UI 栈 / UI Effects 分别见对应模块文档 |
| `client/scripts/debug/` / `client/scenes/debug/` | debug/dev_tools 专用 `DebugConsole`、`GMCommandRegistry` 与 ADR #159 / #160 独立开发者测试岛 / 配装 / 控制面板；正式 release 不应加载或导出 |
| `client/tools/` | Godot 项目内 headless smoke / baker；ADR #158 新增 VFX resource baker、`vfx-smoke`、`ui-manager-smoke`，ADR #159 / #160 维护直启独立 scene 的 `debug_test_arena_smoke.gd`，并保留仅由用户明确触发的性能 probe |
| `user://settings.cfg` / `user://input_bindings.tres` | 普通设置 schema v4 / GUIDE 输入绑定 schema v3；旧 binding v1 / v2 隔离并恢复不含换弹的新默认。游戏进度存档仍走 `user://saves/<slot>/<kind>.save`（`meta` / `run` / `replay_index`） |

`docs/` 下：

| 路径 | 内容 |
|------|------|
| `docs/游戏设计文档.md` | 完整 GDD |
| `docs/代码文档规范.md` | 代码变更需要同步哪些文档的权威规范 |
| `docs/代码/` | `client/` 长期模块文档索引与模块文档 |
| `docs/AI导航.md`（本文件） | 项目地图 |
| `docs/AI知识库索引.md` / `docs/_kb_index.json` | 人工 / 机器可读 AI 知识库索引 |
| `docs/术语表.md` | 术语、别名、英文检索词 |
| `docs/IP设定.md` | `WASD` 集体无意识 IP 与内容包装权威 |
| `docs/IP美术风格.md` | 意识层抽象美术、环境代表色和稳定功能色权威 |
| `docs/词表与契约.md` | 约定字符串白名单 |
| `docs/决策记录.md` | ADR |
| `docs/修改建议.md` | 待决策项（D~E；A/B/C 与 J~R 已归档） |
| `docs/功能建议池.md` | F9 第一轮 Demo 收口后的可选新功能建议池；只作为人工选择菜单 |
| `docs/局内刷取参考研究.md` | 历史 F12 外部参考研究；其中撤离 / 带回结论已被 ADR #188 取代 |
| `docs/AI辅助开发机会清单.md` | AI 只辅助开发、不进入运行时的玩法机会、内容生产管线、DSL / 编辑器 / 模拟器 / lint 工具候选；只作为人工选择菜单 |
| `docs/在线服务规划.md` | GodotSteam + Talo 未来正式接入的供应商、职责、托管、离线、安全和阶段门禁权威；不代表插件已安装 |
| `docs/小服务器玩法备忘.md` | Talo 可承载的异步在线玩法历史参考；其中敌巢进化、星域污染图等旧 IP 包装已被 ADR #178 取代，具体功能仍只作为人工选择菜单 |
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
| `docs/AI协作/实时验证回路.md` | 目标秒级快检 + 分钟级完整 pre-commit + Godot 串行 / 超时收尾设计 |
| `docs/AI协作/文档健康检查.md` | 文档健康检查范围、命令和失败解释 |
| `docs/AI协作/工具适配指南.md` | 各 AI 工具（Codex / OpenCode / Claude Code / Aider / Cursor / Windsurf / ChatGPT 等）的接入配法 |
| `docs/AI协作/ECC工具吸收清单.md` | ECC 全工具面逐项筛选、吸收和拒绝结论；同类外部 agent-harness 大仓扫库参考 |
| `docs/测试策略.md` | **5 层测试金字塔 + 里程碑要求 + 性能预算 + 手动回归 checklist（测试唯一权威）** |
| `AGENTS.md` / `CODEX.md` / `OPENCODE.md` | 通用入口与 Codex / OpenCode 轻量入口适配 |
| `CLAUDE.md` | Claude Code 入口适配；配套项目自有的活跃 `.claude/`（ADR #87，与三平台同源），不接外部 vendor / hooks 整包 |
| `.claude/` | Claude Code 平台原生配置：`agents/`（10）、`commands/`（5）、`skills/`（9，四平台同步）、`rules/game-coding-rules.md`、`settings.json`（仅 `draft/` deny）；核心语义与 `.codebuddy/` / `.codex/` / `.opencode/` 一致 |
| `.codebuddy/agents/` | 项目级 subagents：执行类 `balancer` / `contract-validator` / `data-author`，创意类 `game-designer` / `numeric-designer` / `ip-designer` / `copywriter-packager` / `ui-art-designer` / `game-art-designer` / `marketing-strategist` |
| `.codebuddy/commands/` | 项目级 slash commands：`/sync-contracts` / `/new-gear-mod` / `/run-replay-regression` / `/health-check` / `/update-memory` |
| `.codex/` | Codex CLI 平台配置；核心规则语义与 `.codebuddy/` 一致，但允许按 Codex 优化 agents / commands / rules |
| `.opencode/` | OpenCode 平台配置；含 `opencode.json`、agents、commands、skills、rules；核心规则语义与 `.codebuddy/` / `.codex/` 一致 |
| `.claude/` | Claude Code 平台配置；含 `agents`、`commands`、`skills`、`rules`、`settings.json`；核心规则语义与 `.codebuddy/` / `.codex/` / `.opencode/` 一致（ADR #87） |

> 注：`client/` 已是正式 Godot 项目根（`project.godot` 在此）。F1 只建立最小启动骨架；autoload 与玩法按 `docs/正式项目工作规划.md` F2+ 继续落地，新增文件务必归位。

## 4. 扩展点速查（"我要加 X，该改哪？"）

| 我想… | 怎么做（数据驱动，尽量不改逻辑） |
|-------|-------------------------------|
| **配普通 JSON / CSV / 中英文文案或全局搜索** | 打开 Godot 中央主界面“数据配表”；普通 `client/data` JSON、全部数据 CSV 与 `strings.csv` 可统一编辑，JSON 层级不同由递归属性树处理。未保存内容只进 `user://data_table_editor`，保存通过 hash + 备份 + headless DataLoader 验证事务。模块 JSON/注册表/图块目录和 VFX/profile 使用各自专用编辑器且不进入全局搜索；`module_worlds.json` 仍属于普通配表。新增数据源必须同步 `data_table_catalog.json`，详见 ADR #180 与 `docs/代码/data_table_editor.md` |
| **加一个敌人** | 在 `client/data/enemies.csv` 加一行基础数值、中心间距、通用 `tag_enemy`、独立且与敌人 id 相同的 `pool_id`、`pool_prewarm`、专属 `scene_path`、`ai_profile_id` 与 `enemy_*_name` 文案；静态外观需要区分时从 `scenes/gameplay/actors/enemy_base.tscn` 新建继承场景，不复制基础树。不同敌人 id 可复用同一 TSCN，但不能复用对象池。优先复用现有对玩家 profile；攻击参数只能写入 schema v5 对应 action 的必填 `attack` 字典，远程 action 还必须声明 `windup/burst_count/shot_interval`，普通身体重叠永不造成伤害。改完跑 contracts、data/schema、`actor-scene-smoke`、runtime、save 与黄金回放 |
| **改敌人生成 / 对象池材化 / 续局恢复顺序** | 先读 ADR #197、`docs/代码/enemy_spawn_service.md`、Gameplay Runtime / EnemyAI / PoolManager / ModuleWorld / WorldEvent 文档与测试策略。资格、walkability、奖励和随机位置策略留在 RunLoop；`EnemySpawnService` 只统一 fresh / fixed / debug / restore 的 reparent、metadata、configure、难度 / 导航、serial、bounds 与 lifecycle。Run v19 的 `next_enemy_spawn_serial` 和敌人 snapshot 字典不得改变，restore 必须保持 `bounds → lifecycle/VFX → Enemy.restore_snapshot()`。必跑专项 GUT、actor/runtime/world-event/save、完整 / technical module-world、headless boot 与四条 Replay v9 golden；只重跑不重录，pool / reward 失败不得消费位置 RNG 或 serial，不运行性能 probe |
| **改 Run v19 捕获字段或跨域恢复顺序** | 先读 ADR #197、`docs/代码/run_snapshot_coordinator.md`、Gameplay Runtime / SaveManager / Loading 文档与测试策略。`RunSnapshotCoordinator` 只拥有 30 个 gameplay payload 顶层字段及验证 / 恢复端口顺序；RunLoop 继续持有生命周期、节点、signals、领域 leaf 与激活后 `ui_restore`，`mod_environment` 继续由 SaveManager 注入。必跑 coordinator unit、save/runtime/loading、完整 / technical module-world、world-event/effect-runtime、headless boot 与四条 Replay v9 golden；保持 Meta v4 / Run v19 / Replay v9 / game v1.18，不重录、不运行性能 probe |
| **改敌人寻路 / 感知** | 先读 `F14-EnemyNavigationAndPerception.md`、`docs/代码/enemy_ai.md`、`docs/代码/module_world_manager.md` 与 ADR #145 / #146；profile 感知参数改 `enemy_ai_profiles.json.perception`，局部活动流场 / 全图静态路径 / 视线改 `module_navigation_field.gd`，半径由最大视觉范围自动推导，门面改 `module_world_manager.gd`，行为消费改 `enemy.gd`。导航 / 感知派生状态不进 run，开放战区保留无 provider 直线兜底 |
| **改敌人显式攻击 / 连锁爆炸** | 先读 ADR #170 / #173 / #175 / #188 / #189 / #191 / #193 / #194 / #196、GDD §5.3、EnemyAI / EnemyRewardResolver / WorldEvent / Combat / SaveManager / ContentUnlockSystem 文档。普通敌人仍只以玩家为目标；防御事件目标只能由受控 spawn context 注入。Run v19 保存事件归属、攻击阶段、序号、锁定奖励、冻结内容池、Gear Mod 棋盘、效果程序状态与带 ID 未拾取 Mod；按测试策略整行验证并重录四条 Replay v9 黄金回放，不运行性能 probe |
| **改突击枪手 / 远程点射** | 先读 ADR #171 / #172 / #173 / #175 / #181 / #184 / #188 / #189 / #191 / #193 / #194 / #196、GDD §5.3、EnemyAI / EnemyRewardResolver / Gameplay Runtime / PoolManager / VFX 文档。保留内部 id 与场景；当前静默前摇 0.32 秒、4 发、0.12 秒间隔、350 px/s、720 px、12 px 半径、2.1 秒寿命与 24 px 枪口距离；玩家归因击杀以 2.5% 生成扩散 Mod 拾取物。验证 Run v19 点射、奖励、事件 target mode、冻结内容池、效果程序状态、棋盘与带 ID 未拾取物恢复，不运行性能 probe |
| **加 / 改世界事件** | 先读 ADR #173 / #175 / #188 / #189 / #191 / #194 / #196 / #197、GDD §5.3-A、WorldEvent / Gameplay / ModuleWorld / Save 文档。持续事件固定掉落 1 个可用公共池 Mod，金币坛最多两个不重复 Mod；Controller 只在同步 `{ok, reason}` 投放回执成功后提交奖励、成功次数和终态，失败保持 pending，Run v19 恢复后重试且不重抽、不重复扣费；不运行性能 probe |
| **加一个智能碎片** | 在 `client/data/characters.json` schema v4 加一条：稳定 hero id、`scene_path`、名称 / 描述、只含一个 `primary` 的 palette、主碎片基础属性、`passive_id` 与两个 `hero_skill_ids`。主碎片提供场景、属性、被动、主色和技能 1/2；副碎片提供副色和技能 3/4，不提供属性或被动。当前内置英雄的 `base_stats.max_shield` 均为 0，普通护盾从局内属性增长获得；超量护盾上限为最大生命与最大护盾之和。组合由遗留内部接口 `HeroCompositionResolver.resolve(main_hero_id, sub_hero_id, allow_duplicate)` 解析，运行时 palette 精确为 `main_primary` / `sub_primary`，局外禁止重复。多个 hero id 可复用同一 TSCN；hero / passive / skill id 先登记词表，文案用 `character_*` key。改完跑 contracts、data/schema、`actor-scene-smoke`、runtime/L1/save 与四条黄金回放 |
| **改正式玩家史莱姆 / 半径 / 枪口** | 先读 ADR #183、GDD §3.5、Gameplay Runtime / VFX / DataLoader 与测试策略。`player.json.body.radius`、碰撞、`hit_radius()`、地图边界和敌人分离当前统一 25 px；玩家基础武器、`Muzzle` 与朝向短束统一 38 px，敌人枪口保持 24 px。`PlayerSlimeVisual` 固定 20/100 拓扑和 scene-authored 实例资源，软体不得改玩法 / RNG / 存档或在运行中创建节点 / 材质。必跑计划列出的 actor/VFX/runtime/L1/module/save/loading/replay/headless 与四条 golden；正式游戏视觉、子弹区分和手感只交用户人工验收，不运行性能 probe |
| **加 / 改武器** | 在 `client/data/weapons.json` schema v5 加一条：武器基础属性、子弹池、`element_id`、命中半径、音频 id 和表现 profile；玩家 WeaponSystem 按基础射速无限射击，schema 精确拒绝遗留 `ammo`。文案用 `weapon_*` key；`pool_id` / `element_id` / `audio_id` 必须来自词表 |
| **改共享子弹视觉 / 尺寸 / 基础速度** | 先读 ADR #181、GDD §4、Gameplay Runtime / PoolManager / VFX / EnemyAI 文档。正式 `bullet_basic` 只允许一个四节点 `BulletSlimeVisual`，双方同形 12 px、350 px/s，只按队伍切换白 / 红内外色；不得补回 Shader、高光、黑边、外发光、拖尾或敌方视觉副本。数值改 `weapons.json` 与 `enemy_ai_profiles.json`，保持 `Bullet.configure()` / 快照 / PoolManager 外部接口兼容；验证 runtime/actor/world-event/module-world/save/loading/replay/VFX/headless 和四条 golden，不运行性能 probe |
| **改无限射击 / 重新设计弹药** | 先读 ADR #186、GDD §3.2、Gameplay Runtime / InputService / RNG / PoolManager / SaveManager / Replay 与测试策略。当前弹药系统已完全删除：无旧框架、`ammo` 数据、`reload` action、弹匣池、`RNG.ammo`、HUD 或世界提示；R / 手柄 East 无 gameplay intent。未来若重做必须先新增 ADR 与全新 schema，不能复活 ADR #177 的字段或迁移路径 |
| **改子弹墙体阻挡 / 穿墙能力** | 先读 GDD §4、ADR #149、`docs/代码/gameplay_runtime.md` 与 `docs/代码/module_world_manager.md`；运行时改 `bullet.gd`，模块墙体层改 `module_chunk.gd`，数值契约改词表 / `weapons.json` / 双端 DataLoader。保持玩家与敌弹默认阻挡、地形 bit 1、圆形首帧重叠 + 本帧扫掠、`PoolManager.release()`、`pierce_count` 与 `wall_pierce` 独立、发射时快照及旧字段默认 false；验证完整 / 技术切片 module-world、runtime/save/L1、headless 和四条黄金回放 |
| **加 / 改技能** | 在 `client/data/skills.json` 加技能定义：`ability_tags`、`activation`、能量消耗、目标、通用效果原语、缩放声明、冷却和 `skill_*` 文案；智能碎片只通过遗留字段 `characters.json.hero_skill_ids` 引用两个技能，组合解析后固定进入 `skill_1`～`skill_4`，冷却按槽位保存。主碎片能力强度 / 范围 / 效率 / 持续作用于四槽；新资源、目标类型、效果原语或 ability tag 先登记词表，状态效果 / 叠加规则先登记 §9-A~§9-B，再扩展 SkillSystem / StatusEffectComponent 文档。静域屏障按 ADR #163 只拦截敌弹跨越圆周，内→内与不穿圆的外→外放行，首帧从射手开火位置扫掠 |
| **加 / 选择视觉效果** | 先读 `docs/代码/visual_effects.md`；优先在 Godot“VFX 效果库”用向导创建组合场景、自动登记效果目录，并在 Inspector / 内容绑定页选择 effect 或 profile。内容数据只写 `presentation_profile_id`；固定 cue / anchor / domain / space / lifecycle 先登记词表 §16。程序几何只能使用精选复合模板，不得生成任意 `_draw()` 或引用 addon / `output/test_lab` |
| **改角色 profile / cue / Player 内部表现门面** | 先读 ADR #197、Gameplay Runtime / Visual Effects 文档与测试策略；RunLoop 只通过无状态 `GameplayFeedbackController` 解析 actor `Presentation`、fallback 与 cue context，并只通过 Player 公共门面配置 palette / 开火视觉冲击，不直接查找 `"Presentation"` / `"Visual"`。保持 combat gameplay effect 先于表现 cue、武器 Visual impulse → gameplay recoil → cue 顺序；必跑 feedback integration、VFX、actor、runtime/settings/loading/save/headless 与四条 Replay v9 golden，不运行性能 probe |
| **加 / 改状态效果** | 先看 `docs/代码/status_effect_component.md` 与 `gameplay_effect_runtime.md`；状态 id 登记 `docs/词表与契约.md` §9-A，叠加规则登记 §9-B，只通过统一效果程序的 `apply_status` action 与 `EffectExecutionGateway` 注入；当前 Player / Enemy / SkillSystem 自身已实现 `apply_status_effect()` 和 owned ability tag 查询，DoT 由状态组件按 `GameClock` tick 并经 `Combat.apply_damage()` 结算；新可受状态影响实体应照此接入；状态存在期间要授予 / 移除 ability tag 时引用 §12-G，不在业务脚本手动计时 |
| **调武器后坐 / 扩散** | 数值改 `client/data/weapons.json` 的武器 stats 或根级 `recoil_model`，震屏 profile 改 `camera_feedback.json`，装备控制改 `gear_mods.json` / 掉落 CSV；公式入口是 `weapon_recoil_resolver.gd`，发射 / 后移 / 相机分别见 WeaponSystem、Player、GameplayCameraController。每颗弹固定消耗 `RNG.combat`，零扩散也不能跳过 |
| **改 Player / Weapon 属性层、临时 modifier 或实体快照 wire** | 先读 ADR #197、Gameplay Runtime 与测试策略；纯 `ModifierStack` 只计算 persistent → gear → temporary 的 `(base + add) × mult`，Player / WeaponSystem 继续分别拥有生命 / 护盾副作用、缓存、timer、来源 wire 与 signal。Player 空来源是 `anonymous`，Weapon 是 `legacy:<modifier-list>`；Gear 不进入实体快照，StatusEffect 倍率不进入 Stack。必跑三组 GUT、L1、Gear Mod / pickup、effect-runtime、VFX、runtime/save/headless 与四条 Replay v9 golden，只重跑不重录，不运行性能 probe |
| **改局内威胁时间 / 难度系数 / 敌人出生强化 / 难度标记器** | 先读 ADR #166 / #170 / #173 / #175 / #188 / #189 / #191 / #193 / #194 / #196、GDD §7.3、Difficulty / EnemyRewardResolver 文档。`difficulty_profiles.json` schema v2 的系数缩放威胁时间并参与生成金币；事件波次在激活时固定生命 / 伤害语义，金币按实际生成阶段。Run v19 保存 profile / 系数、固定计划、每敌出生倍率 / 奖励、攻击提交状态、冻结内容池、效果程序状态、棋盘与带 ID 未拾取 Mod。范围、时序、移速、AI 和数量仍不随难度缩放；按测试策略整套验证，不运行性能 probe |
| **加 / 改机关** | 在 `client/data/hazards.csv` 加一行：伤害、`element_id`、触发间隔、`radius_tiles` 占格尺寸、持续时间和 `hazard_*_name` 文案；`tag_hazard`、`pool_id`、`element_id` 必须来自词表；初始摆放改 `client/data/map_layouts.json`，普通矩形范围机关复用 `docs/代码/hazard_system.md` 的通用 `Hazard` 运行时 |
| **改地图边界 / 矩形格 / PCG / 人工摆点** | 查 `docs/代码/map_manager.md`；地图尺寸、`grid.cell_width/cell_height`、玩家出生点、安全半径、刷怪边距、PCG 机关数量 / 间距和人工固定摆点都改 `client/data/map_layouts.json`；bounds 是轴对齐矩形，必须分别是 `grid.cell_width/cell_height` 的整数倍；玩家出生点必须在格心，出生安全区可见提示必须是贴住矩形格的矩形，机关按 `radius_tiles` 奇偶吸附到合法锚点（奇数格心、偶数网格顶点），可见和逻辑地图边界必须是同一个矩形，刷怪位置仍用 `RNG.spawn`；玩家和敌人中心移动都应保持在矩形边界内；改完跑 `validate_data`、`runtime-smoke`，机关相关追加 `f9-demo-smoke` |
| **改玩家相机 / 瞄准引导 / 震屏** | 先读 GDD §5.2、ADR #148 / #156 / #165 / #167、`docs/代码/phantom_camera.md` 的项目接入段和 `docs/代码/gameplay_runtime.md`；节点 / 跟随规则改 `gameplay_camera_controller.tscn/.gd`，瞄准换算改 `player.gd`，数值改 `camera_feedback.json`。保持 Phantom Camera GLUED 跟随、瞄准方向平滑偏移、等比缩放、无滚转 / 边界 / drag，稳定引导与 `RNG.camera_fx` 噪声分离；改完按测试策略相机整行义务验证 |
| **维护 / 升级 Phantom Camera 内部** | 先读 `docs/代码/phantom_camera.md`、`client/addons/README.md`、ADR #148 与目标源码；按 Runtime Core / Resource / Editor / C# wrapper 边界定位，升级只用官方固定版本发布包并逐项重放本地补丁。保持项目固定 Manager autoload、Updater Off、`physics_jitter_fix=0.5`、`RNG.camera_fx` 和 lint 零豁免；完成后跑完整 pre-commit、headless boot、headless editor 与相机回归 |
| **加 / 改模块内容** | 查 ADR #190、Module Authoring、ModuleWorldManager、F13 与数据手册；在 `Module JSON` 编辑 `modules/<id>.json` schema v4 并 Save / Validate / Bake / Approve。世界事件 placement 用登记 id 下拉，payload 只有 `{world_event_id}`；模块不保存敌人出生点，禁止手改生成 TSCN |
| **改 ModuleWorld slot state / pins / Run v19 wire** | 先读 ADR #197、`docs/代码/module_world_manager.md` 与测试策略；`ModuleSlotStateCodec` 只拥有合法坐标、row-major wire、完整 slot payload 深拷贝与 pins 校验，Manager 继续作为 `Node2D` 门面并保留现有字典 API、49 槽与最多三 pin。必跑 codec unit、完整 / technical module-world、runtime 与 save；保持 Run v19 顶层结构、未知嵌套字段、map hash 和 Replay v9 不变，不运行性能 probe |
| **改 ModuleWorld current / revealed / visited / pins 动态状态或恢复候选** | 先读 ADR #197、`docs/代码/module_world_manager.md` 与测试策略；纯 `ModuleWorldState` 组合 Codec，拥有当前槽、迷雾访问、pins、slot payload 与事务式动态恢复候选。Manager 保留 configured / assignment 资格、hash/RNG/navigation/streaming 与 Run v19 九字段显式组装；restore 在 cache/hash 通过前不得污染 live state。必跑 state + codec + streaming unit、完整 / technical module-world、runtime/save/headless 与四条 Replay v9 golden，不运行性能 probe |
| **改 ModuleWorld chunk 流式 / 生成场景缓存** | 先读 ADR #197、`docs/代码/module_world_manager.md` 与测试策略；纯 `ModuleChunkStreamingController` 只持有生成场景路径 / 已提交 cache、12 chunk 池和 active mapping，Manager 保留 assignment、hash、导航、pins 规则与 Run v19 facade。显式 rebuild 先清 active/cache，restore 使用候选 cache 并只在 hash 通过后提交；按 `y→x` 挂载 3×3 + pins。必跑 streaming unit、完整 / technical module-world、runtime/save/headless 与四条 Replay v9 golden，不运行性能 probe |
| **改模块角色 / 地形 / 摆放 / 边缘 / 审核状态** | 先改 `docs/词表与契约.md` §15，运行 `python tools/sync_contracts.py` 生成对应 `module_*` 常量，再由 DataLoader、ModuleWorldManager 和 JSON 引用；禁止在运行时代码裸写白名单 id |
| **改模块首次进入刷怪** | 改 `client/data/module_worlds.json.first_visit_enemy_spawn` 的数量、预警时长与按 `DifficultyProgression.elapsed` 解锁的敌种权重；位置只能由 `ModuleWorldManager.empty_floor_positions_at()` 返回旋转 / 封边后的 floor 且排除 placement footprint，再由 `GameplayRunLoop` 用 `RNG.spawn` 无放回抽取并立即保存计划。敌人在预警结束真正生成时取得当前生命 / 伤害倍率，并按实际生成阶段消费一次 `RNG.economy` 锁定金币。不要恢复 spawn marker、动态占位避让或安全半径；改完跑 data/schema、VFX、完整 / 技术首片 module-world、runtime/save 和黄金回放 |
| **改 AI 模块生产流程** | AI 只在编辑期生成 JSON candidate，不接运行时模型 / 网络生成 / 自动批准；人工使用 Godot `Module JSON` 中央主编辑区编辑同一 JSON schema。工具必须保持 JSON→生成 TSCN 单向、磁盘 hash 冲突门禁和人工 `approved` 门禁，不得增加 TSCN 反向导入 |
| **加 / 改刷怪波次** | 在 `client/data/spawn_waves.csv` 加一行：模式 id、时间窗、敌人 id / 权重、刷怪间隔、同时存活上限、预算和可选机关权重；敌人 / 机关 / 模式引用必须存在，不实现 Spawner 运行时 |
| **加 / 改战区导演** | 查 `docs/代码/warzone_director.md` 和 F10 工作包；在遗留内部文件 `client/data/warzone_directors.json` 改固定 phase、意识层主题、兴趣点和阶段启用 wave；phase / wave gating 只按 `DifficultyProgression.elapsed`，兴趣点领取内部时间仍走 `GameClock`。匹配当前 layout 的兴趣点会通过 `MapManager` 生成 `source="director"` 初始机关；禁止恢复已删除的导演敌人组合元数据、读取玩家状态、隐藏动态调难或运行时接 LLM；改完跑 `validate_data`、`test_data_loader_schema`、`runtime-smoke` 和 `f9-demo-smoke` |
| **加一个 Gear Mod** | 用 `/new-gear-mod` 或 `docs/AI协作/任务模板/加GearMod.md`；在 `gear_mods v6` 用带唯一 `component_id` 的 `modifier` / `program` / `board_rule` 任意组合。`modifier` 必须通过 `hero` / `weapon` 槽位-stat 矩阵；效果程序只用已登记 trigger / condition / action。官方 id 用 `gear_mod_*`，本地包 id 用 `mod_<package_id>_*` |
| **加 / 改主动道具** | 在 `client/data/active_items.json` 加一条：`charge` 声明冷却 / 充能，`use_effects` 引用已登记 effect，文案用 `item_*` key；模式引用走 `game_modes.resource_pools.active_items`，不实现主动道具栏 / 冷却 / 使用效果运行时 |
| **加 / 改消耗品** | 在 `client/data/consumables.json` 加一条：`stack` 声明最大堆叠 / 初始数量 / 单次拾取数量，`use_effects` 引用已登记 effect，文案用 `item_*` key；模式引用走 `game_modes.resource_pools.consumables`，不实现拾取物 / 背包 / 使用输入 / 数量扣减 / 效果运行时 |
| **加 / 改游戏模式** | 在 `client/data/game_modes.json` schema v3 声明 `difficulty_profile_id`、可用角色 / 武器 / 敌人 / 机关 / 主动道具 / 技能 / 消耗品、权重、禁用列表、参与者 / 队伍预留和轻量覆盖；Gear Mod 由专用奖励池 / 掉落表贡献，不挂在 mode 资源池。mode id 先登记 `docs/词表与契约.md`，difficulty profile 必须存在；资源本体保持模式无关，禁止为模式复制资源或在代码写 `if mode_id == ...` |
| **改敌人金币 / 金币等级 / 通用奖励选择** | 查 ADR #169 / #170 / #173 / #175 / #188 / #189 / #191 / #194 / #196、GDD §7.1、EnemyRewardResolver / Gameplay Runtime 与数据手册。金币余额可消费、累计金币只增；Gear Mod 确认放置后作为独立实例生效，不转金币。Run v19 保存金币、祭坛事务、效果程序状态、棋盘 / 未拾取 Mod 与未完成选择 |
| **改 Roguelike 默认循环** | 默认标准模式是 7×7 无缝模块世界：左下角起点 → 意识核等概率位于其余三个角落 → 6–12 次跨越 → 直接完成，不要求清空 49 模块；开放战区通过 `--open-warzone` 保留为回归路径。局内 Gear Mod 不写 Meta，不存在撤离或 pending loot |
| **改局内 Gear Mod / 通用效果** | 查 GDD §7.2、最新 ADR、`docs/代码/gear_mod_system.md` 与效果运行时文档；`gear_mods.json` schema v6 定义 7×7 棋盘和可组合组件，`GameplayEffectRuntime` 管稳定事件队列、触发状态 / 冷却 / 周期 / 快照，Registry 为每个 condition / action 同时注册 handler 与参数 validator，Gateway 是 Combat / StatusEffect / PoolManager / 金币 / 生成 / Audio 唯一出口。非法来源必须在注册阶段拒绝且不得消耗预算 / cooldown。Run v19 按来源实例与 component/program id 保存状态；本地包只组合内置原语。改组件 / trigger / condition / action / pool 前先登记契约并同步数据、locale、schema、指纹与 smoke |
| **加 / 改内容解锁或图鉴** | 先读 ADR #189 / #191 / #194 / #196、GDD §7.4、ContentUnlock / DataLoader / Save / Replay / Gameplay / UI 文档。锁定内容只登记在稀疏规则；英雄 / Gear Mod / 敌池在 RNG 前与 Run v19 / Replay v9 快照求交，锁定 Mod 的地面 / placement 快照必须拒绝，核心不进图鉴；本地 Gear Mod 安装即开放且不写 Meta；不运行性能 probe |
| **维护旧局外成长历史** | 旧 `MetaProgressionSystem` 运行时和 UI 已按 ADR #117 删除；项目尚未上线，ADR #118 后旧测试档迁移、`meta_progression.json`、旧 meta 契约常量和旧 `purchased_upgrades` 补偿路径也已删除。需要查历史时看 F6 工作包与 ADR 记录；不要恢复旧永久升级树作为当前成长方向 |
| **改致谢 / 第三方来源** | 同步根目录 `CREDITS.md` 与 `client/data/credits.json`；Godot 编辑器插件同时维护 `client/addons/README.md` 的版本、哈希、本地补丁和升级流程；新增分组标题、角色或用途标签时补 `client/locale/strings.csv` 的 `ui_credits_*` key；发行前复核许可证和 notice |
| **加 / 改美术资产 / 占位表现** | 先看 `docs/IP美术风格.md`、GDD §8.2-A / §9.24、`docs/代码/visual_effects.md`。静态色彩 / 锚点 / 朝向继续遵守意识层代表色和稳定功能色规则；动态效果通过“VFX 效果库”/ profile 接入，程序几何必须与 Shader、动画或粒子形成精选模板 |
| **提交图片 / 音频 / 字体等二进制资产** | 默认作为普通 Git blob 提交，`.gitattributes` 只保留 `binary` 防止文本 diff；禁止按常见扩展名全局启用 Git LFS。只有经单独决策的明确大型资产路径才可使用 LFS；旧提交中的 LFS 指针不重写，检出历史提交时可能仍需 Git LFS（ADR #182） |
| **加破限角色/道具** | 先判断是否能用 `capabilities` + `modifiers` + `behaviors` 表达；表达不了则新增可复用 primitive / strategy 并登记词表 §12，禁止按 id 写特殊分支 |
| **写/改代码模块** | 先查 `docs/代码文档规范.md` + 对应 `docs/代码/<module_id>.md` + 目标源码；触碰 `.gd` 时按 Godot 4.7 官方 GDScript style guide 整理本次改动，并跑 `python tools/lint_gdscript_rules.py`；GDD / ADR 只在设计冲突、语义不明或新增决策时补读，不能默认整篇加载 |
| **查知识库 / 找文档关系 / 任务路由** | 先看 `docs/AI知识库索引.md` 的任务路由表，需要机器可读元数据时看 `docs/_kb_index.json`，搜索同义词先看 `docs/术语表.md` |
| **续接当前状态 / 下一步** | 先看 `docs/AI协作/快速开工.md` 与 `docs/AI记忆/current_state.json`；上下文压缩后先以用户最后明确指令对齐，`Next Steps` 只作候选参考；需要长期事实 / ADR 摘要 / 历史细节时再看 `docs/AI记忆/项目记忆.md` 和当日会话日志 |
| **查看 / 维护未来任务** | 看 `docs/TODO.md`；F9 第一轮 Demo 收口后的可选新功能菜单看 `docs/功能建议池.md`；F12 历史外部参考看 `docs/局内刷取参考研究.md`，其中撤离 / 带回结论已由 ADR #188 取代，只可继续参考兴趣点与射击构筑；AI 只辅助开发的玩法 / 内容管线 / 工具机会看 `docs/AI辅助开发机会清单.md`；在线供应商与实施门禁看 `docs/在线服务规划.md`，具体异步玩法候选再看 `docs/小服务器玩法备忘.md`；短期机器状态仍同步 `docs/AI记忆/current_state.json`，设计待决策仍进 `docs/修改建议.md` |
| **改 IP / 世界观 / 智能碎片包装 / 宣传语** | 先看 `docs/IP设定.md`；涉及视觉风格、层代表色、敌我 / 警示 / 交互功能色或资产 brief 时追加 `docs/IP美术风格.md`；若改变玩法承诺或系统边界，再同步 GDD / ADR / 术语表 / AI导航 / AI记忆 |
| **选择下一项新功能** | 先看 `docs/功能建议池.md`、`docs/局内刷取参考研究.md`、`docs/AI辅助开发机会清单.md`、`docs/TODO.md` 与 `docs/AI记忆/current_state.json`；用户明确点名功能后，再建立 / 更新工作包、GDD / ADR / 模块文档并实现，不从建议文档自行挑选推进 |
| **评估 / 规划在线服务** | 先看 `docs/在线服务规划.md`、ADR #150、GDD §9.22 / §9.23、`docs/代码/platform_services.md` 与测试策略；供应商路线是 `PlatformServices → GodotSteam`、`OnlineServices → Talo`，不开发自有通用后端。当前不安装；首个功能被用户点名后才重查官方版本、决定 Talo Cloud / 官方自托管并建立工作包 |
| **评估小服务器在线玩法** | 先看 `docs/小服务器玩法备忘.md`，再看 `docs/在线服务规划.md`、GDD §6.7 / §9.23、`docs/代码/replay.md`；GodotSteam + Talo 路线已采纳，但每日挑战、排行榜、死亡残响等具体玩法仍需用户点名，实时多人 / PvP / 强竞技排行榜默认暂缓 |
| **启动 / 推进正式项目** | F13 模块世界已完成；当前 F14 入口为 `F14-EnemyNavigationAndPerception.md`、GDD §5.3、EnemyAI / ModuleWorldManager 文档、数据手册与测试策略。F14.1 活动流场当前半径 8、单次最多访问 289 格；导航 / 感知变更跑 contracts/data/schema/module-world/runtime/save 与黄金回放；性能 probe 仅在用户当次明确要求时运行 |
| **维护正式客户端启动骨架 / 默认分辨率** | 看 `client/README.md`、`docs/代码/formal_client_boot.md`、`docs/代码/gameplay_runtime.md` 与 GDD §9.5-A；当前只设计 / 验收固定 16:9 分辨率，默认 viewport 为 1920×1080，窗口不允许任意拖拽缩放，`canvas_items + keep` 在非 16:9 屏幕上等比缩放并加黑边；其他宽高比是 P3 优化，未来也必须按独立固定预设接入，不做连续响应式适配 |
| **改开始 / 继续 / 重开加载流程** | 先读 ADR #157、`docs/代码/gameplay_loading.md`、FormalClientBoot / Gameplay Runtime / GameState / UIManager 文档和测试策略；玩家入口统一显示 `LoadingScreen` 并保持 `LOADING`，用 Godot `ResourceLoader` 线程读取 `PackedScene`，主线程分帧构建，加载界面移除后才激活。不得创建自管 `Thread`、阶段 / 百分比 / 取消按钮或最低展示时长；改完必跑 `loading-smoke` 及文档规定的完整回归 |
| **改词表 / 生成常量** | 改 `docs/词表与契约.md` 后跑 `python tools/sync_contracts.py` 和 `python tools/sync_contracts.py --check`，生成 `_contracts.json` 与 `client/scripts/contracts/*.gd` |
| **校验数据 / 文案** | 跑 `python tools/validate_data.py` 与 `python tools/lint_project_rules.py`；改 DataLoader schema 时追加 `python tools/test_data_loader_schema.py`，改项目规则 lint 时追加 `python tools/test_project_rules_lint.py` |
| **改 DataLoader 跨文件引用索引** | 先读 ADR #197、`docs/代码/data_loader.md` 与测试策略；纯 `DataReferenceIndexBuilder` 只接收 DataLoader 已加载 / 合并的数据，按旧 source order 构建 18 类索引，不读文件 / Mod、不缓存、不排序、不报告 schema 错误。DataLoader 保留校验和读取顺序，Gear Mod 索引必须在坏玩法包隔离后重新加载。必跑 builder unit、validate/schema、ModLoader、L1、Replay、headless 与四条 Replay v9 golden；保持 data hash 与错误时序不变，不运行性能 probe |
| **改 Gear Mod 掉落校验 / 坏包隔离** | 先读 ADR #197、`docs/代码/data_loader.md` 与测试策略；纯 `GearModDropTableValidator` 只接收现成 rows、ID 索引和错误 sink，包内入口保留旧静默边界，合并入口保留 enemy→mod→chance→min→max→range→duplicate 顺序。DataLoader 必须先隔离坏包，再重读 Gear Mod / 世界事件 / 掉落 CSV 并记录最终 count。必跑 validator unit、validate/schema、`mod-loader-smoke` 与 headless boot；不缓存、不排序、不运行性能 probe |
| **校验 GDScript 项目规则** | 跑 `python tools/lint_gdscript_rules.py`；当前第一档覆盖代码段顺序、危险 `:=`、中文硬编码字符串、裸随机 / 时间 / 暂停 API |
| **校验项目规则** | 跑 `python tools/lint_project_rules.py`；当前第二档覆盖数据字段手册登记、locale `zh_CN` / `en` 双语、release preset debug/dev_tools 禁入，以及 InputService→UIManager 单向边界、RunLoop 不直访 `Visual` / `Presentation`、smoke / GUT / runtime CI 必须隔离用户环境；改 lint 时追加 `python tools/test_project_rules_lint.py`，改 Bridge / smoke catalog / 正式测试路由时追加 `python tools/test_godot_bridge.py` |
| **校验语义风险** | 跑 `python tools/lint_semantic_rules.py`；当前第三档默认非阻塞，提示特殊 id 分支、业务脚本绕过 autoload、正式 gameplay/UI 的长期 Node/Control `.new()` 挂树、缺类型签名、长期脚本缺 `# Doc:` 与未知 contract 常量；已注册对象池 factory 与行模板实例化不报 `runtime-node-construction`；改语义 lint 时追加 `python tools/test_semantic_rules_lint.py` |
| **本地提交前验证** | 已提供路径感知 `.pre-commit-config.yaml`；日常先跑目标 smoke，再对本次文件只跑一次 `pre-commit run --files ...`。schema / lint / Steamworks 工具自测只在相关路径变化时触发；改 hook / validator / linter、大型全仓交付或发版前才跑一次 `--all-files`。未暂存文件另用路径限定 `git diff --check`，不能把 staged whitespace 的 no-op 当作已覆盖 |
| **运行 Windows / PowerShell 命令** | 先读当前平台编码规则第 29 节与 `docs/AI协作/工具适配指南.md` 的「Windows PowerShell 稳定执行」；固定字符串优先 `rg -F`，全部 `rg` 选项放在 `--` 前，cmdlet 路径走 `-LiteralPath`，原生程序立即检查 `$LASTEXITCODE`，合法非零码先归一化再进入并行或 fail-fast；`git diff --no-index=1` 仅在输入已校验为文件后表示差异；不混用 Bash 转义、`cmd` 或 `Invoke-Expression` |
| **查 Godot 场景树 / headless 启动** | 跑 `python tools/godot_bridge.py export-tree`、`python tools/godot_bridge.py headless-boot` 及命中当前风险的专项 smoke；`client/tools/smoke_commands.json` 是 smoke parser / runner / policy 的单一描述表。headless smoke 默认隔离 `user://`，必须命中精确成功标记；逐命令整行 allowlist 过滤后仍拒绝任何标准 fatal，不能以进程退出码 0 代替测试通过。F8 全量 golden 使用单进程、隔离用户目录的 `replay-regression`，单文件 `replay-runner --replay-file ... --rerun-runtime-summary` 仅用于定位。FormalClientBoot 只接受 `--test-command <id>` 动态加载被请求 runner；其他 replay / capture / perf / bake 专用入口保持独立。`startup-probe` / `perf-probe` 只在用户当次明确要求性能测试时运行 |
| **用项目级 AI skill** | CodeBuddy / Codex / OpenCode / Claude 分别读取 `.codebuddy/skills/<name>/SKILL.md`、`.codex/skills/<name>/SKILL.md`、`.opencode/skills/<name>/SKILL.md`、`.claude/skills/<name>/SKILL.md`；当前覆盖 Godot 实现、场景验证、Godot 测试诊断、试玩复盘、文档同步、安全提交、事实 review、AI 资源筛选与协作面审计、MCP 评估；外部 GodotPrompter / headless-godot / CCGS / ECC 的有用流程已吸收进项目 skill，不再保留 vendor 来源或 reference 跳转；资源筛选与安装清单见 `docs/AI协作/AI技能资源评估.md` |
| **加 / 改效果原语** | 先在 `词表与契约.md` 登记 trigger / condition / action id；在 `EffectPrimitiveRegistry` 同时实现 handler 与精确参数 validator，经 `EffectExecutionGateway` 接正式系统，再由数据引用。必须补合法样例、非法参数注册拒绝与“不消耗预算 / cooldown”测试，禁止内容 id 分支 |
| **改数值（血/伤害/刷怪/掉落）** | 先读 `client/data/README.md`，只改 `res://data/` 对应 CSV / JSON，**绝不改代码常量**；平表数值优先 CSV，复杂配置优先 JSON；新增 / 改字段必须同步数值手册 |
| **预留 / 维护玩家 mod 接口** | 看 `docs/代码/mod_loader.md`、`docs/代码/data_loader.md` 与 GDD §9.21；当前只支持 `user://mods/<mod_id>/mod.json` 声明式 JSON / CSV append，不接创意工坊、不执行玩家脚本、不绕过 `DataLoader` schema。ModLoader 在解析前限制 manifest / 单 patch / 包总字节、JSON 深度与节点、CSV 行列，任一超限走整包 invalid 隔离；未来创意工坊只作为分发层 |
| **加面向玩家的文本** | 先读 `client/locale/README.md`，在 `res://locale/strings.csv` 加 key + `zh_CN` / `en` 译文；若用户只给一种语言，AI 自动补齐另一语言首版译文，人工复核后代码 / 数据用 `tr("key")` 或 `name_key`；涉及 UI 按钮、面板或 HUD 时以英文 `en` 长度验收尺寸，跑对应 smoke，当前按钮类英文适配由 `settings-smoke` 覆盖 |
| **加一个设置项** | 先在 `Settings` 加配置（键/类型/默认/范围）并接入下游 `setting_changed` 即时生效；只有完成生效链路后才在设置面板显示 UI 控件，暂未接线的预留 key 保留为隐藏 / 禁用 |
| **加一个埋点** | 用 `词表与契约.md` 登记的 `event_name`，调用 `Analytics.track_event(name, params)` |
| **改输入 / 按键 / 手柄 / 重绑定** | 先读 `docs/代码/input_service.md`、词表 §7、ADR #151 / #197、Settings / Replay 文档和目标调用方；action 先登记并生成常量，默认映射改 `client/resources/input/`，业务只消费 `InputService` 的 `move` / `aim` Vector2 或 bool intent。GUIDE 只允许由 InputService 访问，InputMap 只允许在 UI bridge / 插件 / 测试边界；UIManager 通过 `set_ui_stack_active()` 单向推送栈事实，InputService 禁止反向引用 / 订阅 UIManager；绑定保存为 `user://input_bindings.tres`，改完跑 `input-smoke`、`settings-smoke`、`replay-input-smoke`、runtime 与黄金回放 |
| **维护 / 升级 GUIDE 内部** | 先读 `docs/代码/guide.md`、`client/addons/README.md`、ADR #151 与目标源码；升级只比较固定版本官方发布包，重放 autoload、类型、context 单调序号、detector 负轴 / 取消清理和源码头补丁。不得启用自动更新、加 lint 豁免或把插件类型泄露给业务；完成后跑三档 lint、input/settings/replay smoke、headless boot、headless editor 和真实手柄验收 |
| **加 GM 指令 / 调试工具** | 查 GDD 9.20 与 `docs/代码/debug_tools.md`；调试入口只在 debug/dev_tools 构建启用，action 用 `debug_*` 并登记词表 §7；命令必须通过正式系统 API 或受控 `debug_*` API 改状态；release preset 不启用 `dev_tools` 且排除调试脚本 / GM 命令表；改完跑 `python tools/godot_bridge.py --project client debug-tools-smoke` 和 `debug-tools-release-smoke` |
| **改开发者测试岛** | 先读 ADR #159 / #160、`docs/代码/debug_test_arena.md`、DebugTools / Gameplay Runtime / FormalClientBoot / GearModSystem 文档与测试策略；它是直接运行的独立 debug scene，内部复用 RunLoop 用途，不是正式 game mode，标题 / boot / 正式 CLI 必须零耦合。配置只写 `user://debug_test_arena.cfg`，正式 run/meta、Replay/Analytics 与 release 资源必须隔离；改完必跑 `debug-test-arena-smoke`、release smoke 和模块文档规定的完整回归，不自动跑性能 probe |
| **加暂停/切换游戏状态** | `GameState.change_state(PAUSED)` 等；UI 通过 `UIManager.push(modal_pause_menu)` 自动联动暂停；`PauseMenu` 已覆盖继续、保存并退出、重开和回标题，也支持从奖励选择面板上方叠出并恢复回 `REWARD_CHOICE`；不直接读写 `get_tree().paused`（见 GDD 9.12 / 9.14） |
| **加录制回放/确定性需求** | 走 `Replay`（autoload）；当前 schema v8 记录最终 intent、组合、冻结池与严格 `gear_mod_placement` 语义决策，旧 v7 拒绝。玩法指纹包含 Gear Mod 棋盘 / kind / behavior / modifier / 奖励池 / 拾取 / 掉落，排除展示字段。放置播放按决策时间调用正式 pending transaction，不记录鼠标轨迹；改 wire 或内容池追加 input/replay/content smoke 和四条黄金回放 |
| **接 Steam API / 平台服务** | 先读 `docs/在线服务规划.md`、ADR #150 与 `docs/代码/platform_services.md`；未来固定官方 GodotSteam 版本，只在 `PlatformServices` adapter 内初始化 / 驱动 callback，并承接 Steam 身份票据、成就、Steam-only 统计、富状态、overlay、Lobby / 邀请。当前正式客户端不安装，业务不得直调 Steamworks / GodotSteam |
| **接 Talo / 在线后端** | 当前只规划、不安装。用户点名首个功能后，先在 `output/test_lab` 验证并决定 Talo Cloud / 官方自托管，再新增 `OnlineServices → Talo` adapter；跨平台排行榜 / 统计、Live Config、事件与轻量社交只走该门面，Analytics 可把它作为 sink，SaveManager 仍是本地存档权威。禁止业务直调 `Talo.*`、双写同一排行榜 / 统计或自研通用后端 |
| **维护 Steamworks Slime Lab / 单人 AI 大招与自主游击 / 本地同屏 / 纪录 / App ID / Windows 导出** | 先读 `output/steamworks_lab/README.md` 与 ADR #129 / #132 / #133 / #134 / #135 / #136 / #137 / #138 / #139 / #140 / #141；自动回归只使用 `py -3 tools\steamworks_lab_toolchain.py smoke --suite <目标>`，先目标 suite、交付前 `--suite all`，禁止手写 Godot / PowerShell 双进程命令。ADR #139 的 AI 大招仅在 `PlayMode.SINGLE`：P1 子弹命中 / 普通击杀 / Boss 击杀按 `+1 / +6 / +21` 累积至 100，按 `E` 召唤不可受伤、不吸引火力且自动射击的 10 秒 AI。ADR #140 已把 AI 改为确定性自主游击 / 预判闪避：避开敌弹、普通敌人、Boss 和障碍物，常规距 P1 使用 210 px 硬限、超过 220 px 复位；须松开再按住 `E` 发起合体，AI 高速归队到 92 px 内并停靠 0.8 秒后自动同意，持续时间不重置且每次召唤最多一次。目标 battle 1/1、local-couch 与权威 `smoke --suite all` 已通过；all 含 battle 5/5、动态端口 ENet、最大分片仍不超过 900 字节且受保护文件未改变。AI 不进入真人 roster、强化、纪录、玩家卡或快照；同屏 / Steam、wire、存档与正式 `client` 不变。runner 隔离每个 `user://`、验证精确 `ALL PASS` / 致命日志、动态分配 ENet 端口并保护玩家真实设置 / 存档与源码 `steam_appid.txt=4955670`；测试 fixture 必须在 `_ready()` 前注入。源码 App ID 文件永久保留，只从 release 排除。本地同屏由 `local_input_router.gd` 分配 P1 键鼠与 P2–P4 手柄；Steam Lobby 不混入同屏玩家，ENet 只守协议。纪录按单人 / 多人分开，未来 schema 保持写保护，Steam Client 必测权威 Game Over 完整链路。快照应用层仍是 `Dictionary`，wire 层为 FastLZ + 900 字节分片，Lobby `lab_version=2`。Windows 当前开发 / 发布验证标准为普通 Godot 4.7.1 + GodotSteam 4.20 GDExtension + Steamworks 1.64；工具锁继续接受 Godot 4.7 minor 系列，setup / verify / export-release 直接走 `--godot` / `GODOT_PATH`；export-release 按 editor 模式校验标准用户目录或 self-contained `editor_data/` 的精确版本 templates，禁止重建 `.toolchain/`。真实手柄、SteamPipe、Depot 和双账号 Steam smoke 仍需外部验证；不能把 Lab 直连 SDK 当成正式 `client/PlatformServices` 已接入 |
| **加 / 验证回放测试** | `Replay` 负责 `.replay` envelope 与 `user://replays/` 文件；输入或决策丢弃计数非零的 Replay v9 属于不完整记录，只保留停止录制诊断，不得保存或加载。`replay-smoke` 验证 roundtrip / 两类容量边界与 `MAX + 1`，`replay-input-smoke` 验证 gameplay 输入录制。四条 checked-in golden 的权威全量入口是 `python tools/godot_bridge.py --project client replay-regression`：稳定排序、单个隔离 Godot 进程、逐条 reset、默认 fail-fast；`--keep-going` 只用于收集全部失败，`--allow-data-fingerprint-mismatch` 只用于非权威诊断。重录仍使用四种 `capture-golden-replay` 场景，确认稳定语义前不得更新基线；纯 Godot Control 鼠标命中不在回放输入中 |
| **加平衡测试 / Headless 模拟** | 通过 `AIPlayer` 接口接入；`Spawner` / `MapManager` / `RNG` 都接受外部 seed（见 GDD 9.10）。用户明确要求性能测试时，可用 `python tools/godot_bridge.py --project client perf-probe` 输出 schema v2 可比较基线 JSON，包含 30 帧 warmup 后 180 帧 avg / p95 / p99 / max 帧时间、active / peak entity counts、pool final stats / peak active、等级、击杀、状态和预算状态 |
| **修 Steamworks Lab AI 归队 / 合体** | `SteamLabSlimePlayer.set_input_drive_scale()` 必须与 AI 模式 `max_speed` 同步，保证 `TACTICAL / DODGE / RECALL` 的 `1.18× / 1.45× / 1.75×` 是真实软体速度；归队进入 92 px 后要跟随移动中的 P1，单人离线 `_update_gameplay()` 必须驱动权威 0.8 秒合体进度，并在合体后继续把 P1 输入路由给 driver。回归须走真实 E 按下 / 释放、移动 P1 和真实 `SlimeBody` 物理，禁止在归队后瞬移 AI 或直接调用内部合体函数代替主循环。最新目标 battle 1/1、local-couch 与权威 all-suite 已通过，all 含 battle 5/5、动态端口 ENet 和 635 字节最大快照分片；玩法仍以 ADR #140 为准，不新增 wire / 存档边界。 |
| **加 UI 弹窗** | `UIManager.push(scene)`；场景根节点 `@export modal/pauses_game/music_duck` 元数据；不 `add_child` UI（见 GDD 9.14）；按钮、标题和说明布局以英文 `en` 文案长度验收，不按中文短文本定窄宽 |
| **加新敌人/子弹/特效**（高频实体） | `PoolManager.acquire(pool_id)` / `release(node)`；新池 id 在词表 §8 登记；实现 `_pool_reset()`（见 GDD 9.13） |
| **改角色 / 敌人基础或专属场景** | 查 ADR #155 / #156、`docs/代码/gameplay_runtime.md`、`pool_manager.md` 与 `enemy_ai.md`；基础树只改 `actors/player_base.tscn` / `enemy_base.tscn`，内容场景必须保持真实继承。静态颜色 / 轮廓留在场景，玩法数值留在 JSON / CSV；数据 `scene_path` 允许复用，敌人 `pool_id` 不允许复用，角色场景不得携带对局级相机 Rig。必跑 data/schema、`actor-scene-smoke`、runtime、save、module-world、headless 与黄金回放 |
| **加伤害逻辑** | 走 `Combat.apply_damage(target, DamageInfo)`；`element_id` 在词表 §9，默认中性。保留 source / target / team / friendly_fire 模式规则边界；不 `target.hp -= n`。物理 / 真实伤害、穿甲与 `pierce_armor` 已删除（见 GDD 9.15.1） |
| **加持续效果（DoT/控制/debuff）** | 用 `StatusEffect` Resource + 目标实体的 `StatusEffectComponent.apply()`；id 在词表 §9-A；明确 `stack_rule`；DoT 用 `element_id`、`magnitude`、`tick_interval`，tick 伤害仍走 `Combat.apply_damage()`。易伤只放大玩家阵营造成的直接 / 持续伤害（见 GDD 9.15.2） |
| **加存档/读档** | 走 `SaveManager.save/load`；当前 Meta v4、Run v19、Replay v9、游戏 v1.18。Run 保存精确 `mod_environment`、效果 Runtime 快照、Gear Mod next ID、行优先解锁格 / placements、地图计时 / 锁定计划和全部带 ID 地面物，核心与未提交 placement 不保存。旧 Run v18 与环境不匹配文件保留原样但不显示继续入口，不迁移、不按坏档隔离；主档存在且判定为需保留不兼容时必须立即返回该错误，只有主档缺失或可隔离损坏时才尝试 `.bak`；schema 仍使用标准 envelope、原子写入、备份回退和坏档隔离 |
| **加音效/BGM** | `AudioManager.play_sfx/play_music`；id 在词表 §10；不直接 `AudioStreamPlayer.play()`（见 GDD 9.17） |
| **执行 AI 高频任务** | 先查 `docs/AI协作/任务模板/`；任务不在模板里 → 按 `docs/AI协作/上下文预算.md` 先判 S/M/L/XL 复杂度，再决定读取范围 |
| **拆分复杂 / 专业任务给 subagent** | 项目默认授权支持 subagent 的平台主动调度 `.codebuddy/agents/` / `.codex/agents/` / `.opencode/agents/` / `.claude/agents/` 下对应角色；只读小任务或直接实现更高效时不必强行拆分；平台不支持或外层工具策略限制时，把同名 `.md` 当 prompt 模板读 |
| **评估 / 吸收外部 AI 工具仓库** | 先用 `ai-resource-curator`，读 `docs/AI协作/AI技能资源评估.md` 与 `docs/AI协作/上下文预算.md`；ECC 这类大仓按 `docs/AI协作/ECC工具吸收清单.md` 的 README / 全工具面清单 / 候选全文读取流程执行；默认不安装外部 hooks、MCP、CLI、dashboard、plugin 或 vendor tree |
| **提交 / 收尾大更改** | 按 `AGENTS.md` 的 AI Git 提交策略：大更改默认自动 commit，细微改动不提交；大型代码改动提交前按 `docs/AI协作/代码审核流程.md` 追加工具先行的事实型 code review；提交前看 `git status --short` / `git diff` / `git log --oneline -10`，只 stage 本次任务文件 |
| **调整已有数值字段** | 读 `docs/AI协作/任务模板/调数值.md` 与 `docs/测试策略.md` §7。按当前任务重新分级：不改 schema / 契约 / 加载 / 存档时先跑 `validate_data`，交付前只跑一次本次文件的 pre-commit；只有现有专项 / replay 确实覆盖目标变量时才追加，移速等手感留给用户 L5，不自动跑 Godot boot、runtime、性能或无语义 golden 重录 |
| **写/改测试** | 看 `docs/测试策略.md`：L0~L5 金字塔 + 各层必测清单 + 里程碑要求 + 测试义务表 |

## 5. 核心系统模块

### 5.1 模块清单
**业务模块**：`FormalClientBoot` / `LoadingScreen` / `CodexPanel` / `GameplayRunLoop` / `RunSnapshotCoordinator` / `GameplayEffectRuntime` / `EffectPrimitiveRegistry` / `EffectExecutionGateway` / `DeveloperTestArena(debug/dev_tools)` / `Player` / `WeaponSystem` / `Bullet` / `SkillSystem` / `Enemy(EnemyAI)` / `Spawner` / `ModuleWorldManager` / `ModuleSlotStateCodec` / `ModuleChunkStreamingController` / `ModuleNavigationField` / `WorldEventController` / `WarzoneDirector` / `HazardSystem` / `ItemSystem` / `GoldProgression` / `RewardChoiceController` / `GearModSystem` / `ContentUnlockSystem` / `ModifierStack` / `MapManager` / `GameplayCameraController` / `VfxHost` / `GameplayFeedbackController` / `ActorPresentationController` / `PlayerSlimeVisual` / `EnemyPresentationVisual` / `PauseMenu` / `Combat` / `StatusEffectComponent`。统一效果模块见 `docs/代码/gameplay_effect_runtime.md`。

**Autoload 单例（横向基础设施 + 协调中枢）**：
- 一条**本地 mod 基础设施**：`ModLoader`（扫描 `user://mods/<mod_id>/mod.json`，给 `DataLoader` 提供声明式数据 patch 与允许的动态契约扩展；创意工坊未来只作为分发层）
- 一条**平台服务基础设施**：`PlatformServices`（Steam 优先预留成就、统计、富状态 / 状态显示、overlay、Lobby / 联机入口和用户身份；其他平台后续走 provider adapter）
- 一条**未来在线服务规划**：`OnlineServices` 尚未实现；ADR #150 只锁定未来以 Talo provider 承接跨平台身份、排行榜 / 统计、Live Config、事件和轻量社交，不计入当前 autoload 矩阵
- 三条**协作基础设施**：`Localization` / `Settings` / `Analytics`
- 一条**表现注册基础设施**：`VisualEffects`（catalog/profile 与闪屏 / 震屏许可策略；不持有当前世界）
- 一条**输入基础设施**：vendored `GUIDE` 只解释物理设备与资源图；项目 `InputService` 是生成 action、归一化 intent、context、重绑定、提示和回放覆盖的唯一业务门面
- 两条**确定性基础设施**：`RNG`（种子化随机，子流分流）/ `GameClock`（移动、冷却、状态、Replay tick，以及玩家加载 / 暂停 / 结算冻结的底层时间源）
- 一条**模式级威胁进度**：`DifficultyProgression`（非 autoload；由 mode / 启动前 profile 配置，难度系数缩放推进；起点房暂停，驱动敌人出生倍率、金币时间项、解锁、导演 gating、HUD、结算与埋点）
- 一条**回放基础设施**：`Replay`
- 一条**vendored 相机协调基础设施**：`PhantomCameraManager`（项目固定 autoload；节点注册、priority / layer 选机与噪声广播）
- 一条**AI 协作基础设施**：见 `docs/AI协作/`（非 autoload）
- 三个**协调中枢**：`GameState`（流程状态机）/ `UIManager`（界面栈）/ `PoolManager`（通用对象池）
- 两个**资源管理**：`SaveManager`（存档 + 迁移）/ `AudioManager`（音频统一接口）

当前正式客户端以模块世界作为默认 carrier：Manager 管 49 槽、3×3 邻域和事件 pin；Gear ModBoard 用同向 7×7 坐标承载 v6 可组合组件。当前 Meta v4、Run v19、Replay v9、游戏 v1.18；常规验收入口追加 effect-runtime 与 mod-loader-v2 smoke，性能测试仅由用户当次明确触发。

> 普通开始新局 / 重开会生成新的 `RNG` run seed；继续游戏恢复 run snapshot；回放、smoke、golden 和调试复现仍应显式固定 seed 或走工具启动路径。

> ADR #157 后开始、继续和重开都先由 `FormalClientBoot` 进入 `LOADING` 并通过 `UIManager` 显示唯一 `LoadingScreen`；RunLoop 在玩家加载模式下用 `ResourceLoader` 线程读取 actor / 模块 `PackedScene`，对象池预热、初始模块挂载与续局恢复在主线程分批让帧。`run_prepared` 后先移除遮罩再激活；失败清理半成品并回标题。应用冷启动、阶段 / 百分比、取消和人为最低时长不在当前范围。

> ADR #158 后 `VisualEffects` 解析数据，RunLoop 内 `VfxHost` / `GameplayFeedbackController` 执行 cue；Player / Enemy 基类固定 Presentation 和六个挂点。`UIManager` 使用四态异步生命周期并自动装共享 UI effects；Loading 正常路径等待 `ui_removed`。“VFX 效果库”是 editor-only，release 排除；性能检查仍只由用户明确触发。

> ADR #159 / #160 / #194 后“开发者测试岛”只能直接运行独立 `debug_test_arena.tscn`；配置 v4 使用显式 `{mod_id,x,y}` 和正式棋盘校验，同一 Mod ID 只有一个勾选入口，map Mod 因没有 ModuleWorld 而不激活。它不进入正式标题、boot、CLI、模式或存档，Replay / Analytics 仅在独立场景生命周期关闭并在退出恢复。

> 有限地图可见边界和逻辑边界当前都由 `MapManager.bounds()` / `boundary_points()` / `boundary_half_extents()` 定义为贴住格线的轴对齐矩形；玩家和敌人中心点由 `set_movement_bounds()` 约束。排查敌人越界时先看 `GameplayRunLoop._apply_enemy_movement_bounds()`、`Enemy.set_movement_bounds()` 与 `runtime-smoke` 的敌人边界断言。

> F9 起默认键鼠瞄准已从 4 方向改为鼠标方向；子弹可任意角度发射。ADR #124 后当前正式视角改回俯视角 2D；ADR #148 引入 Phantom Camera，ADR #156 将唯一 Rig 固定在 `GameplayRunLoop/ActiveWorld`，通过 `follow_target` 绑定当前 Player。ADR #167 后 GLUED PCam 保持屏幕水平与等比缩放，但不再严格居中：首次有效瞄准后，鼠标按光标相对玩家实际屏幕位置应用死区 / 比例 / 上限，方向输入与 Replay 使用最大偏移，控制器平滑引导且暂停冻结。ADR #165 的玩家受击与武器开火独立震屏仍保留，噪声 `Camera2D.offset` 不参与瞄准或稳定引导；关闭震屏只停止表现。`Player` 仍是 `CharacterBody2D` 并按 2D 平面移动和承受碰撞安全反冲，正式玩家场景不挂 `Player3DVisual`，默认 2D 占位按完整 `aim_direction` 绘制朝向标记。方向键、手柄右摇杆和 D-pad 继续作为无鼠标动作时的兜底输入。

> ADR #151 / #152 / #194 / #196 后不再由 gameplay 动态创建 InputMap action。GUIDE 0.14.0 维护物理映射；`InputService` 统一 intent、context 与非暂停 UI capture，保留 Tab 真实按住同时屏蔽角色操作；Replay v9 读取最终 intent、冻结池、placement 决策与精确本地玩法环境。

### 5.2 系统依赖图（Mermaid，AI 改动前先看影响范围）

```mermaid
flowchart LR
  subgraph Infra[基础设施]
    Mod[ModLoader]
    Loc[Localization]
    Set[Settings]
    Ana[Analytics]
    VfxReg[VisualEffects]
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
    Unlock[ContentUnlockSystem]
    Aud[AudioManager]
  end

  Data[(client/data/<br/>CSV / JSON)]
  Loader[DataLoader]
  ResLoader[ResourceLoader]
  Boot[FormalClientBoot]
  Loading[LoadingScreen]
  ME[ModifierStack]
  Combat[Combat<br/>伤害结算]
  SE[StatusEffectComponent]
  VfxHost[VfxHost]
  Feedback[GameplayFeedbackController]

  Player[Player]
  RunLoop[GameplayRunLoop]
  RunSnapshot[RunSnapshotCoordinator]
  Weapon[WeaponSystem]
  Bullet[Bullet]
  Skill[SkillSystem]
  Difficulty[DifficultyProgression]

  Spawner[Spawner]
  ModuleWorld[ModuleWorldManager]
  ModuleNav[ModuleNavigationField]
  Director[WarzoneDirector]
  Enemy[Enemy / EnemyAI]
  Hazard[HazardSystem]
  Item[ItemSystem]
  Gold[GoldProgression]
  Reward[RewardChoiceController]
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
  Data --> Loader --> Player & Weapon & Skill & Enemy & Item & Gold & Reward & GearMod & Unlock & Spawner & ModuleWorld & Director & Difficulty & Hazard & Map & CamCtl & VfxReg
  Set --> Input & UIM & Aud & CamCtl & VfxReg
  Guide -. 物理 action / context / remapping .-> Input
  Loc --> UIM & Item
  Loc --> Loading
  Ana <-- 埋点 --- Player & Enemy & Item & Gold & Reward & GearMod & Spawner & GS & Save
  RNG --> Map & Spawner & Item & Reward & GearMod & Enemy & Combat & PCam & VfxHost
  Clk --> Hazard & Weapon & Skill & SE
  Clk -. RunLoop delta / 冻结状态 .-> Difficulty
  Input -. 录制 v9 intent .-> Rep
  Rep -. playback override .-> Input
  Rep -. seed/tick/state .-> RNG & Clk & GS
  Plat -. 成就/状态/overlay/Lobby .-> UI & GearMod & GS
  Plat -. Steam Web API Ticket .-> Online
  Plat -. 未来 provider .-> GodotSteam
  Online -. 未来 provider .-> Talo
  Ana -. 可选在线 sink .-> Online
  Save -. 仅受控同步载荷 .-> Online

  GS --> UIM
  GS --> Reward
  GS --> GearMod
  GS -.- Rep
  UIM --> UI
  UIM --> Loading
  Pool --> Weapon & Bullet & Spawner & Hazard & Item & Aud & VfxHost

  Input --> Player --> Weapon
  Input --> CamCtl
  Input --> Skill & UIM & UI
  RunLoop --> RunSnapshot
  RunSnapshot -. Run v19 payload / restore order .- Save
  RunLoop --> Difficulty & Gold & Reward
  Difficulty --> Spawner & Director & Enemy & UI
  Difficulty -. Run v19 snapshot .- Save
  Weapon --> Bullet --> Combat
  Skill --> Combat
  Skill --> SE
  SE -. 状态宿主 .- Player & Enemy & Skill
  Save -. run 快照 .- Player & Enemy & Skill
  Enemy --> Combat
  Combat --> Player & Enemy
  Combat -. semantic cue .-> Feedback --> VfxHost
  VfxReg --> Feedback & VfxHost
  VfxHost -. attached/world/ground/screen .-> Player & Enemy & UI
  Combat -. 玩家有效伤害 .-> CamCtl
  Combat -.- SE
  GS -. 默认模块世界创建/驱动 .-> ModuleWorld
  ModuleWorld --> Map
  ModuleWorld --> ModuleNav
  ModuleWorld --> WorldEvent
  WorldEvent --> Enemy & Gold & UI
  WorldEvent -. Run v19 snapshot / pin .- Save
  ModuleWorld -. ModuleChunk 地形 bit 1 .-> Bullet
  ModuleNav -. 共享流场/视线/AStar .-> Enemy
  ModuleWorld -. JSON placement（经 RunLoop 对象池/Combat） .-> Spawner & Hazard
  ModuleWorld -. assignment/hash/fog/slot snapshot .- Save
  Bullet -. wall_pierce 发射快照 .- Save
  Director --> Spawner
  Map --> Player & Spawner & Hazard
  Spawner --> Enemy
  Difficulty -. coefficient / tier .-> Enemy
  Enemy -. 生成时锁定奖励 / 玩家归因掉落 .-> Gold
  RunLoop --> CamCtl --> PCam --> PCHost --> Cam
  Player -. follow target .-> PCam
  CamCtl -. stable aim look offset .-> Player
  CamCtl -. GLUED compatibility position .-> Cam
  PCamMgr -. 注册 / priority / layer / noise .-> PCam & PCHost
  ME -. persistent / gear / temporary .- Player & Weapon
  Item -. 注册 modifiers/behaviors .- ME
  Gold -. 累计金币推导等级 .-> RunLoop
  Reward -. 通用奖励 modifier .- ME
  GearMod -. 固定实例 modifiers .- ME
  GearMod -. 武器 Mod .- Weapon
  GearMod -. 智能碎片 Mod（内部 hero） .- Player

  Unlock -. 开局冻结英雄/Mod/敌池 .-> RunLoop
  Unlock -. 图鉴查询/要求进度 .-> UI
  Unlock -. Meta v4 稀疏进度 .- Save
  RunLoop -. 局终原子提交 .-> Unlock
  Rep -. v7 内容池快照 .-> RunLoop

  Save -. meta/run kind .- GS
  Save -. run skill snapshot .- Skill
  Save -. meta kind .- GearMod
  Aud -. play_sfx/music .- Combat & UI & Item
  Boot --> UIM
  Boot --> RunLoop
  Save -. continue envelope .-> Boot
  ResLoader -. threaded PackedScene .-> RunLoop
  RunLoop -. run_prepared / run_prepare_failed .-> Boot

  classDef infra fill:#eef,stroke:#88a;
  classDef hub fill:#fee,stroke:#a88;
  classDef res fill:#efe,stroke:#8a8;
  class Mod,Loc,Set,Ana,RNG,Rep,Clk,Plat,Online,GodotSteam,Talo,Guide,Input,PCamMgr infra;
  class GS,UIM,Pool hub;
  class Save,Unlock,Aud res;
```

> 改某个模块前先在图中追踪上下游箭头，避免遗漏影响。新增系统模块时**同步更新此图**（规则 14）。
> 三类节点：**基础设施**（蓝） / **协调中枢**（红） / **资源管理**（绿）。
> `ModuleWorldManager` 不是 autoload：由 `GameplayRunLoop` 在 `ActiveWorld` 下创建并驱动，依赖世界 / 注册表 / 模块 JSON 与每模块一份的单向生成规范 TSCN。它组图、管迷雾并保留公开 facade；纯 `ModuleSlotStateCodec` 保持坐标、slot state 与 pins wire，纯 `ModuleChunkStreamingController` 管候选 / 已提交场景 cache、12 chunk 池与 3×3 + pins active mapping。Enemy 只经 Manager 门面查询导航。首次进入计划、预警、对象池生成、击杀归因、目标和局内奖励仍由 `GameplayRunLoop` 负责。
> `OnlineServices`、GodotSteam 与 Talo 节点是 ADR #150 的未来规划，不表示当前 autoload、插件或网络依赖已经存在；正式 `client` 当前仍由 `PlatformServices` 的 `none` 后端离线退化。

## 6. 红线（最易踩坑）
- ❌ 硬编码可调数值、玩家可见文本、键盘按键 / 手柄按钮 / 手柄轴、约定字符串；❌ 在技能 / 被动 / 道具等 `*_desc` 译文中重复写死可能调整的数值（必须用配置命名占位符与统一格式化器）；❌ 新增数值 / 文案字段却不更新 `client/data/README.md` / `client/locale/README.md`
- ❌ 业务代码直接访问 GUIDE / `Input` / `InputMap`、按物理设备写分支或自己维护 context / 重绑定；必须走生成 action 与 `InputService`，InputMap 仅限 GUIDE / InputService UI bridge / 测试
- ❌ 用中文短文本密度决定 UI 尺寸；新增 / 修改玩家可见 UI 文案或布局时必须切到英文 `en` 验收按钮、面板、HUD、奖励选择和结算不截断、不溢出、不遮挡
- ❌ 为每个 Gear Mod / 技能 / 道具写独立硬编码分支
- ❌ 为某个角色 / 技能 / Gear Mod / 道具写 `if id == ...` 的一次性破限分支（必须 capability / primitive / strategy 化）
- ❌ 为某个游戏模式复制一套角色 / Gear Mod / 敌人资源，或用 `if mode_id == ...` 写模式专属内容分支（模式应通过资源池、权重、tags、availability、capability / strategy 组合）
- ❌ 写死唯一玩家、唯一队伍或“玩家只打敌人 / 敌人只打玩家”的关系（未来多人 PvE / PvP 预留要求使用 actor / participant / team / intent / Combat 统一边界）
- ❌ 相机开启 `limit` / `drag margin` / 内建 position smoothing，或把稳定瞄准引导与震屏噪声混在同一 offset
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
- ❌ 用菱形 / 等距地图格继续模拟斜俯视；当前地图格、边界、机关危险区和兴趣点 footprint 都是水平 / 垂直矩形俯视格，角色 / 敌人 / 拾取 / 子弹 / 障碍 / 特效靠俯视轮廓、方向标记、功能色和真实判定形状保持读法
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
- ❌ 执行文档或任务明确标为人工检查 / 人工验收 / 手动验收 / L5 / 真实设备 / 视觉、听觉或手感验收的项目，或用 GUI 自动化、截图、录屏、模拟输入替代人工并自行宣称通过；AI 只能完成其余自动化验证，交付 checklist，并标记“待人工验收”
- ❌ 在 PowerShell 中套用 Bash 的引号转义、把 `rg` 选项写到 `--` 后、误判工具退出码、未校验输入就把 `git diff --no-index=1` 当作差异，或把未归一化的预期非零码直接放进并行 / fail-fast 调度
- ❌ 大更改后不按 AI Git 提交策略自动 commit，大型代码改动提交前不做事实型 review，或提交前不查 status / diff / log、误 stage 用户脏改动 / `draft/` / `DRAFT/`
- ❌ 读取、搜索、整理、格式化、总结或引用 `draft/` / `DRAFT/` 人工草稿（除非用户明确点名授权）
- ❌ 复活或搬运历史 MVP 临时代码到完整项目 `client/`；MVP 验证经验只能经复盘、设计和 ADR 迁移
- ✅ 改完同步更新规则文件与相关文档（元规则）
- ✅ 重要决策同步进 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与当日会话日志
- ✅ 知识库结构变化后运行 `python tools/docs_health_check.py`
