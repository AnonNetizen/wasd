# AI 导航（项目索引）

> 本文件是给 AI agent（以及人）的**项目地图**：开始任何任务前先读这里，按指引快速定位，避免盲目全仓搜索。
> 配套：编码规则见 `AGENTS.md` 第 3 步的当前平台规则入口；完整设计见 `游戏设计文档.md`。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是项目索引权威；新增系统、目录、扩展点、AI 工具入口或依赖图变化时，必须同步 GDD / 词表 / 规则 / 测试策略 / 项目记忆中的对应入口。

---

## 1. 项目是什么
俯视角 Roguelike 弹幕生存游戏（灵感：以撒的结合 + 吸血鬼幸存者）。
- 引擎：**Godot 4.6.3 + GDScript**
- 核心理念：**数据驱动 + 扩展优先 + 框架级基础设施（本地化 / 设置 / 数据埋点）+ AI 易扩展**

## 2. 必读文档（按优先级）
| 文档 | 作用 |
|------|------|
| `AGENTS.md` | **AI agent 通用开工入口**，每次开始任务前必读 |
| `.codebuddy/rules/game-coding-rules.md` / `.codex/rules/game-coding-rules.md` / `.opencode/rules/game-coding-rules.md` | **强制编码规则入口**，按当前平台选读 |
| `docs/AI导航.md`（本文件） | 项目地图与扩展点定位 |
| `docs/AI知识库索引.md` | AI 知识库总索引、权威层级、任务入口和 ADR 追踪矩阵 |
| `docs/术语表.md` | 中英文术语、别名和检索词 |
| `docs/词表与契约.md` | 所有约定字符串白名单（stat/effect/event/key），**禁止编造** |
| `docs/游戏设计文档.md` | 完整设计 |
| `docs/代码文档规范.md` | 代码变更与对应文档的同步规范 |
| `docs/决策记录.md` | 既定决策与原因，勿误改 |
| `docs/修改建议.md` | 待决策的开放问题（A~E；J~R 已归档） |
| `docs/AI记忆/项目记忆.md` | AI 协作长期索引（**跨会话/跨机器续接必读**） |
| `docs/AI记忆/current_state.json` | 机器可读当前阶段、下一步、最近验证 |
| `docs/TODO.md` | 人工可读未来任务清单 |

## 3. 目录结构与定位

仓库根主要目录：

| 路径 | 内容 |
|------|------|
| `docs/` | 项目文档（设计文档、AI 导航、词表契约、决策记录、AI 记忆等） |
| `client/` | **Godot 4.6.3 项目根**（即 Godot 中的 `res://`） |
| `server/` | 服务器端预留（当前为单机项目，暂占位） |
| `MinimumViableProduct/` | MVP 隔离实验区；文档与独立客户端代码都放此处，不污染完整项目 `client/` |
| `tools/` | 本地校验与桥接工具：`sync_contracts.py`、`validate_data.py`、`docs_health_check.py`、`godot_bridge.py` |
| `.github/` | GitHub Issue / PR 模板与 Actions workflows；当前启用 Stage 1 基础 `docs-check` CI |
| `draft/` / `DRAFT/` | 用户人工草稿，AI 禁止读取 / 搜索 / 修改 / 整理 / 引用，除非用户明确点名授权 |

`client/` 下（落地代码后）：

| 路径 | 内容 |
|------|------|
| `client/scenes/`（即 `res://scenes/`） | 场景 `.tscn`（Player / Bullet / Enemy / Item / Hazard 等） |
| `client/scripts/`（即 `res://scripts/`） | 脚本 `.gd`，按系统单一职责拆分 |
| `client/data/`（即 `res://data/`） | 可调数值配置（JSON）+ `README.md` 人工调参手册 |
| `client/locale/`（即 `res://locale/`） | 本地化翻译表（CSV → `.translation`）+ `README.md` 多语言文案手册 |
| `client/templates/`（即 `res://templates/`） | 新内容脚手架模板（enemy/relic 等） |
| `client/assets/`（即 `res://assets/`） | 美术 / 音效 |
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
| `docs/词表与契约.md` | 约定字符串白名单 |
| `docs/决策记录.md` | ADR |
| `docs/修改建议.md` | 待决策项（A~E；J~R 已归档） |
| `docs/TODO.md` | 未来任务清单（P0 当前优先级 / P1 下一批 / P2 中期 / P3 长期积压） |
| `docs/简单设计思路.md` | 项目原点 |
| `docs/CICD规划.md` | CI/CD 路线图 |
| `docs/AI记忆/项目记忆.md` | **AI 协作长期索引（跨会话/跨机器续接必读）** |
| `docs/AI记忆/current_state.json` | **机器可读当前状态（下一步与最近验证）** |
| `docs/AI记忆/会话日志/` | 按日期归档的对话摘要 |
| `docs/AI协作/README.md` | AI 协作工程目录索引 |
| `docs/AI协作/任务模板/` | 高频任务的标准 prompt + 文件操作清单 |
| `docs/AI协作/上下文预算.md` | 不同任务该读哪些文件 |
| `docs/AI协作/角色分工.md` | 设计/实现/评审/平衡 四角色协作 |
| `docs/AI协作/引擎集成.md` | Godot MCP / Bridge 接入指南 |
| `docs/AI协作/实时验证回路.md` | pre-commit hook + 本地秒级反馈设计 |
| `docs/AI协作/文档健康检查.md` | 文档健康检查范围、命令和失败解释 |
| `docs/AI协作/工具适配指南.md` | 各 AI 工具（Codex / OpenCode / Claude Code / Aider / Cursor / Windsurf / ChatGPT 等）的接入配法 |
| `docs/测试策略.md` | **5 层测试金字塔 + 里程碑要求 + 性能预算 + 手动回归 checklist（测试唯一权威）** |
| `AGENTS.md` / `CODEX.md` / `OPENCODE.md` | 通用入口与 Codex / OpenCode 轻量入口适配 |
| `CLAUDE.md` | Claude Code 轻量入口适配；不安装活跃 `.claude/` 外部工具，可按需读取 `.codebuddy/skills/`、`.codex/skills/` 或 `.opencode/skills/` 项目级 skill |
| `.codebuddy/agents/` | 项目级 subagents：执行类 `balancer` / `contract-validator` / `data-author`，创意类 `game-designer` / `numeric-designer` / `ip-designer` / `copywriter-packager` / `ui-art-designer` / `game-art-designer` / `marketing-strategist` |
| `.codebuddy/commands/` | 项目级 slash commands：`/sync-contracts` / `/new-relic` / `/run-replay-regression` / `/health-check` / `/update-memory` |
| `.codex/` | Codex CLI 平台配置；核心规则语义与 `.codebuddy/` 一致，但允许按 Codex 优化 agents / commands / rules |
| `.opencode/` | OpenCode 平台配置；含 `opencode.json`、agents、commands、skills、rules；核心规则语义与 `.codebuddy/` / `.codex/` 一致 |

> 注：当前仓库尚处文档阶段，落地代码后 `client/` 即 Godot 项目根（`project.godot` 在此），新增文件务必归位。

## 4. 扩展点速查（"我要加 X，该改哪？"）

| 我想… | 怎么做（数据驱动，尽量不改逻辑） |
|-------|-------------------------------|
| **加一个敌人** | 复制 `templates/enemy_template`，在 `data/enemies.json` 加一条；行为复用既有 AI 类型，新行为才碰逻辑 |
| **加一个角色** | 在 `data/characters.json`（落地后）加一条：基础属性 / 起始武器或遗物 / tags / capabilities / 控制配置；新 capability 先登记词表 §12 再实现 |
| **加一个遗物/道具** | 在 `data/relics.json` 加一条，用 `modifiers` + `behaviors` 描述；**只用 `词表与契约.md` 已登记的 effect/stat**，新原语先登记再实现 |
| **改经验/升级系统** | 查 GDD §7.1；`GrowthSystem` 负责经验累计、默认 3 选 1、`luck` 概率 4 选 1；候选数量和选项抽取走 `RNG.ui_choice`，升级 UI 走 `UIManager`，流程走 `GameState.LEVEL_UP` |
| **改局外成长 / 元进度** | 查 GDD §7.2；配置改 `client/data/meta_progression.json`，字段说明同步 `client/data/README.md`，文案同步 `client/locale/strings.csv`；存档走 `SaveManager` 的 `meta` kind，新增 currency / upgrade / unlock id 先登记词表 §13 |
| **加破限角色/道具** | 先判断是否能用 `capabilities` + `modifiers` + `behaviors` 表达；表达不了则新增可复用 primitive / strategy 并登记词表 §12，禁止按 id 写特殊分支 |
| **写/改代码模块** | 先查 `docs/代码文档规范.md`；长期模块 / autoload / 公共 API / signal / 数据 schema / 依赖方向变化必须同步详细的 `docs/代码/<module_id>.md` 与本导航依赖图，不能只写自动摘要 |
| **查知识库 / 找文档关系 / 任务路由** | 先看 `docs/AI知识库索引.md` 的任务路由表，需要机器可读元数据时看 `docs/_kb_index.json`，搜索同义词先看 `docs/术语表.md` |
| **续接当前状态 / 下一步** | 先看 `docs/AI记忆/项目记忆.md` 的长期事实，再看 `docs/AI记忆/current_state.json` 的机器当前状态；上下文压缩后先以用户最后明确指令对齐，`Next Steps` 只作候选参考；需要历史细节才看当日会话日志 |
| **查看 / 维护未来任务** | 看 `docs/TODO.md`；短期机器状态仍同步 `docs/AI记忆/current_state.json`，设计待决策仍进 `docs/修改建议.md` |
| **改词表 / 生成常量** | 改 `docs/词表与契约.md` 后跑 `python tools/sync_contracts.py` 和 `python tools/sync_contracts.py --check`，生成 `_contracts.json` 与 `client/scripts/contracts/*.gd` |
| **校验数据 / 文案** | 跑 `python tools/validate_data.py`，覆盖 `client/data/*.json`、`client/locale/strings.csv` 与 MVP config 的 schema / 词表 / locale key 校验 |
| **查 Godot 场景树 / headless 启动** | 跑 `python tools/godot_bridge.py export-tree` 或 `python tools/godot_bridge.py headless-boot`；默认项目为 `MinimumViableProduct/client` |
| **用项目级 AI skill** | CodeBuddy / Codex / OpenCode 分别读取 `.codebuddy/skills/<name>/SKILL.md`、`.codex/skills/<name>/SKILL.md`、`.opencode/skills/<name>/SKILL.md`；当前覆盖 Godot 实现、场景验证、Godot 测试诊断、试玩复盘、文档同步、安全提交、事实 review、AI 资源筛选和 MCP 评估；外部 GodotPrompter / headless-godot / CCGS 的有用流程已吸收进项目 skill，不再保留 vendor 来源或 reference 跳转；资源筛选与安装清单见 `docs/AI协作/AI技能资源评估.md` |
| **做 MVP 实验** | 只改 `MinimumViableProduct/`；MVP 文档见 `MinimumViableProduct/README.md`，MVP 客户端代码放 `MinimumViableProduct/client/`，不要混入完整项目 `client/` |
| **加一种子弹效果原语** | 先在 `词表与契约.md` 登记 `effect` id → 在效果原语层实现方法/Node → 数据中引用 |
| **改数值（血/伤害/刷怪/掉落）** | 先读 `client/data/README.md`，只改 `res://data/` 对应 JSON，**绝不改代码常量**；新增 / 改字段必须同步数值手册 |
| **加面向玩家的文本** | 先读 `client/locale/README.md`，在 `res://locale/strings.csv` 加 key + `zh_CN` / `en` 译文，代码 / 数据用 `tr("key")` 或 `name_key` |
| **加一个设置项** | `Settings` 加一条配置（键/类型/默认/范围）+ 一个 UI 控件，订阅 `setting_changed` 生效 |
| **加一个埋点** | 用 `词表与契约.md` 登记的 `event_name`，调用 `Analytics.track_event(name, params)` |
| **改输入/按键/手柄** | 走 `Settings` 重绑定与 InputMap action，不硬编码键盘按键、手柄按钮或手柄轴；默认手柄为左摇杆移动、右摇杆 / D-pad 瞄准 |
| **加暂停/切换游戏状态** | `GameState.change_state(PAUSED)` 等；UI 通过 `UIManager.push(modal_pause_menu)` 自动联动暂停；不直接读写 `get_tree().paused`（见 GDD 9.12 / 9.14） |
| **加录制回放/确定性需求** | 走 `Replay`（autoload）；随机走 `RNG.<stream>`、时间走 `GameClock`；不读非确定时间源（见 GDD 9.9 / 9.18） |
| **加平衡测试 / Headless 模拟** | 通过 `AIPlayer` 接口接入；`Spawner` / `MapManager` / `RNG` 都接受外部 seed（见 GDD 9.10） |
| **加 UI 弹窗** | `UIManager.push(scene)`；场景根节点 `@export modal/pauses_game/music_duck` 元数据；不 `add_child` UI（见 GDD 9.14） |
| **加新敌人/子弹/特效**（高频实体） | `PoolManager.acquire(pool_id)` / `release(node)`；新池 id 在词表 §8 登记；实现 `_pool_reset()`（见 GDD 9.13） |
| **加伤害逻辑** | 走 `Combat.apply_damage(target, DamageInfo)`；`damage_type` 在词表 §9；不 `target.hp -= n`（见 GDD 9.15.1） |
| **加持续效果（DoT/控制/debuff）** | 用 `StatusEffect` Resource + `StatusEffectComponent.apply()`；id 在词表 §9-A；明确 `stack_rule`（见 GDD 9.15.2） |
| **加存档/读档** | 走 `SaveManager.save/load`；必须支持 `meta` 局外成长和 `run` 暂停退出续局；schema 必带 `version` / `kind` / `slot` / `created_at` / `updated_at` / `game_version` / `data_hash`；写入用 `*.tmp` 原子替换、保留 `.bak`、坏档进 `.broken/`；save kind 先登记词表 §14；与 `Settings` 职责分开（见 GDD 9.16） |
| **加音效/BGM** | `AudioManager.play_sfx/play_music`；id 在词表 §10；不直接 `AudioStreamPlayer.play()`（见 GDD 9.17） |
| **执行 AI 高频任务** | 先查 `docs/AI协作/任务模板/`；任务不在模板里 → 按 `docs/AI协作/上下文预算.md` 决定读取范围 |
| **提交 / 收尾大更改** | 按 `AGENTS.md` 的 AI Git 提交策略：大更改默认自动 commit，细微改动不提交；提交前看 `git status --short` / `git diff` / `git log --oneline -10`，只 stage 本次任务文件 |
| **写/改测试** | 看 `docs/测试策略.md`：L0~L5 金字塔 + 各层必测清单 + 里程碑要求 + 测试义务表 |

## 5. 核心系统模块

### 5.1 模块清单
**业务模块**：`InputController` / `Player` / `WeaponSystem` / `Enemy(EnemyAI)` / `Spawner` / `HazardSystem` / `ItemSystem` / `GrowthSystem`（经验/升级选择）/ `MetaProgressionSystem`（局外成长）/ `ModifierEngine` / `MapManager` / `Camera2D` / `DataLoader` / `PauseMenu`（UI）/ `Combat`（伤害结算）/ `StatusEffectComponent`（状态效果）。

**Autoload 单例（横向基础设施 + 协调中枢）**：
- 三条**协作基础设施**：`Localization` / `Settings` / `Analytics`
- 两条**确定性基础设施**：`RNG`（种子化随机，子流分流）/ `GameClock`（暂停冻结时间源）
- 一条**回放基础设施**：`Replay`
- 一条**AI 协作基础设施**：见 `docs/AI协作/`（非 autoload）
- 三个**协调中枢**：`GameState`（流程状态机）/ `UIManager`（界面栈）/ `PoolManager`（通用对象池）
- 两个**资源管理**：`SaveManager`（存档 + 迁移）/ `AudioManager`（音频统一接口）

### 5.2 系统依赖图（Mermaid，AI 改动前先看影响范围）

```mermaid
flowchart LR
  subgraph Infra[基础设施]
    Loc[Localization]
    Set[Settings]
    Ana[Analytics]
    RNG[RNG]
    Rep[Replay]
    Clk[GameClock]
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

  Data[(client/data/<br/>JSON)]
  Loader[DataLoader]
  ME[ModifierEngine]
  Combat[Combat<br/>伤害结算]
  SE[StatusEffectComponent]

  Input[InputController]
  Player[Player]
  Weapon[WeaponSystem]

  Spawner[Spawner]
  Enemy[Enemy / EnemyAI]
  Hazard[HazardSystem]
  Item[ItemSystem]
  Growth[GrowthSystem]
  Meta[MetaProgressionSystem]

  Map[MapManager]
  Cam[Camera2D]
  UI[UI/HUD<br/>PauseMenu/...]

  Data --> Loader --> Player & Enemy & Item & Growth & Meta & Spawner & Hazard
  Set --> Player & Weapon & Input & UIM & Aud
  Loc --> UIM & Item
  Ana <-- 埋点 --- Player & Enemy & Item & Growth & Meta & Spawner & GS & Save
  RNG --> Spawner & Item & Growth & Meta & Enemy & Combat
  Clk --> Spawner & Hazard & Weapon & SE
  Rep -. 录制/重放 .-> Input & RNG & Clk & GS

  GS --> UIM
  GS --> Growth
  GS --> Meta
  GS -.- Rep
  UIM --> UI
  Pool --> Weapon & Spawner & Item & Aud

  Input --> Player --> Weapon
  Weapon --> Combat
  Combat --> Player & Enemy
  Combat -.- SE
  Spawner --> Enemy
  Enemy -. 掉落经验 .-> Growth
  Player -.- Cam
  ME -. 修正器叠加 .- Player & Weapon
  Item -. 注册 modifiers/behaviors .- ME
  Growth -. 升级奖励 .- ME
  Meta -. 永久升级 .- ME
  SE -. 注入 modifier .- ME

  Save -. meta/run kind .- GS
  Save -. meta kind .- Meta
  Aud -. play_sfx/music .- Combat & UI & Item

  classDef infra fill:#eef,stroke:#88a;
  classDef hub fill:#fee,stroke:#a88;
  classDef res fill:#efe,stroke:#8a8;
  class Loc,Set,Ana,RNG,Rep,Clk infra;
  class GS,UIM,Pool hub;
  class Save,Aud res;
```

> 改某个模块前先在图中追踪上下游箭头，避免遗漏影响。新增系统模块时**同步更新此图**（规则 14）。
> 三类节点：**基础设施**（蓝） / **协调中枢**（红） / **资源管理**（绿）。

## 6. 红线（最易踩坑）
- ❌ 硬编码可调数值、玩家可见文本、键盘按键 / 手柄按钮 / 手柄轴、约定字符串；❌ 新增数值 / 文案字段却不更新 `client/data/README.md` / `client/locale/README.md`
- ❌ 为每个遗物/道具写独立硬编码分支
- ❌ 为某个角色 / 遗物 / 道具写 `if id == ...` 的一次性破限分支（必须 capability / primitive / strategy 化）
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
- ❌ 手改 `client/scripts/contracts/*.gd`（自动生成，改 `docs/词表与契约.md` + 跑 `tools/sync_contracts.py`）
- ❌ 改了数据 / 文案 / 词表却不跑 `tools/validate_data.py` 或 `tools/sync_contracts.py --check`
- ❌ 新增 / 修改长期代码模块却没有对应详细 `docs/代码/` 模块文档、或用简短自动摘要替代维护文档
- ❌ 面向用户的回复默认使用英文或其他语言（除非用户明确要求、引用原文或目标文件语言要求）
- ❌ 用户问有没有问题 / 风险时，为了显得有用而硬找问题、过度优化或提出无必要改动（没发现问题就明确说没有问题）
- ❌ 用户提出需求后不先评估落地前景、性价比、复杂度和主要风险，闷声做到最后才暴露重大隐患
- ❌ 上下文总结 / 压缩 / 恢复后，把摘要、`Next Steps`、`current_state.json` 或历史待办当成当前授权执行，而不先对齐用户最后明确指令
- ❌ 大更改后不按 AI Git 提交策略自动 commit，或提交前不查 status / diff / log、误 stage 用户脏改动 / `draft/` / `DRAFT/`
- ❌ 读取、搜索、整理、格式化、总结或引用 `draft/` / `DRAFT/` 人工草稿（除非用户明确点名授权）
- ❌ 把 MVP 临时代码 / 文档混入完整项目 `client/` 或根目录正式文档而不经过 ADR 决策
- ✅ 改完同步更新规则文件与相关文档（元规则）
- ✅ 重要决策同步进 `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与当日会话日志
- ✅ 知识库结构变化后运行 `python tools/docs_health_check.py`
