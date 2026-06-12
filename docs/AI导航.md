# AI 导航（项目索引）

> 本文件是给 AI agent（以及人）的**项目地图**：开始任何任务前先读这里，按指引快速定位，避免盲目全仓搜索。
> 配套：编码规则见 `.codebuddy/rules/game-coding-rules.md`；完整设计见 `游戏设计文档.md`。

---

## 1. 项目是什么
俯视角 Roguelike 弹幕生存游戏（灵感：以撒的结合 + 吸血鬼幸存者）。
- 引擎：**Godot 4.6.3 + GDScript**
- 核心理念：**数据驱动 + 框架级基础设施（本地化 / 设置 / 数据埋点）+ AI 易扩展**

## 2. 必读文档（按优先级）
| 文档 | 作用 |
|------|------|
| `.codebuddy/rules/game-coding-rules.md` | **强制编码规则**，每次写代码前必读 |
| `docs/AI导航.md`（本文件） | 项目地图与扩展点定位 |
| `docs/词表与契约.md` | 所有约定字符串白名单（stat/effect/event/key），**禁止编造** |
| `docs/游戏设计文档.md` | 完整设计 |
| `docs/决策记录.md` | 既定决策与原因，勿误改 |
| `docs/修改建议.md` | 待决策的开放问题（A~D / J~R） |
| `docs/AI记忆/项目记忆.md` | AI 协作主索引（**跨会话/跨机器续接必读**） |

## 3. 目录结构与定位

仓库根三段：

| 路径 | 内容 |
|------|------|
| `docs/` | 项目文档（设计文档、AI 导航、词表契约、决策记录、AI 记忆等） |
| `client/` | **Godot 4.6.3 项目根**（即 Godot 中的 `res://`） |
| `server/` | 服务器端预留（当前为单机项目，暂占位） |

`client/` 下（落地代码后）：

| 路径 | 内容 |
|------|------|
| `client/scenes/`（即 `res://scenes/`） | 场景 `.tscn`（Player / Bullet / Enemy / Item / Hazard 等） |
| `client/scripts/`（即 `res://scripts/`） | 脚本 `.gd`，按系统单一职责拆分 |
| `client/data/`（即 `res://data/`） | 可调数值配置（JSON）+ 字段说明 |
| `client/locale/`（即 `res://locale/`） | 本地化翻译表（CSV → `.translation`） |
| `client/templates/`（即 `res://templates/`） | 新内容脚手架模板（enemy/relic 等） |
| `client/assets/`（即 `res://assets/`） | 美术 / 音效 |
| `user://settings.cfg` | 玩家设置存档；`user://` 下另存元进度存档 |

`docs/` 下：

| 路径 | 内容 |
|------|------|
| `docs/游戏设计文档.md` | 完整 GDD |
| `docs/AI导航.md`（本文件） | 项目地图 |
| `docs/词表与契约.md` | 约定字符串白名单 |
| `docs/决策记录.md` | ADR |
| `docs/修改建议.md` | 待决策项 |
| `docs/简单设计思路.md` | 项目原点 |
| `docs/CICD规划.md` | CI/CD 路线图 |
| `docs/AI记忆/项目记忆.md` | **AI 协作主索引（跨会话/跨机器续接必读）** |
| `docs/AI记忆/会话日志/` | 按日期归档的对话摘要 |
| `docs/AI协作/README.md` | AI 协作工程目录索引 |
| `docs/AI协作/任务模板/` | 高频任务的标准 prompt + 文件操作清单 |
| `docs/AI协作/上下文预算.md` | 不同任务该读哪些文件 |
| `docs/AI协作/角色分工.md` | 设计/实现/评审/平衡 四角色协作 |
| `docs/AI协作/引擎集成.md` | Godot MCP / Bridge 接入指南 |
| `docs/AI协作/实时验证回路.md` | pre-commit hook + 本地秒级反馈设计 |
| `docs/测试策略.md` | **5 层测试金字塔 + 里程碑要求 + 性能预算 + 手动回归 checklist（测试唯一权威）** |
| `.codebuddy/agents/` | 项目级 subagents：`balancer` / `contract-validator` / `data-author` |
| `.codebuddy/commands/` | 项目级 slash commands：`/sync-contracts` / `/new-relic` / `/run-replay-regression` / `/health-check` / `/update-memory` |

> 注：当前仓库尚处文档阶段，落地代码后 `client/` 即 Godot 项目根（`project.godot` 在此），新增文件务必归位。

## 4. 扩展点速查（"我要加 X，该改哪？"）

| 我想… | 怎么做（数据驱动，尽量不改逻辑） |
|-------|-------------------------------|
| **加一个敌人** | 复制 `templates/enemy_template`，在 `data/enemies.json` 加一条；行为复用既有 AI 类型，新行为才碰逻辑 |
| **加一个遗物/道具** | 在 `data/relics.json` 加一条，用 `modifiers` + `behaviors` 描述；**只用 `词表与契约.md` 已登记的 effect/stat**，新原语先登记再实现 |
| **加一种子弹效果原语** | 先在 `词表与契约.md` 登记 `effect` id → 在效果原语层实现方法/Node → 数据中引用 |
| **改数值（血/伤害/刷怪/掉落）** | 只改 `res://data/` 对应 JSON，**绝不改代码常量** |
| **加面向玩家的文本** | 在 `res://locale/strings.csv` 加 key + 译文，代码/数据用 `tr("key")` 或 `name_key` |
| **加一个设置项** | `Settings` 加一条配置（键/类型/默认/范围）+ 一个 UI 控件，订阅 `setting_changed` 生效 |
| **加一个埋点** | 用 `词表与契约.md` 登记的 `event_name`，调用 `Analytics.track_event(name, params)` |
| **改输入/按键** | 走 `Settings` 重绑定，不硬编码按键 |
| **加暂停/切换游戏状态** | `GameState.change_state(PAUSED)` 等；UI 通过 `UIManager.push(modal_pause_menu)` 自动联动暂停；不直接读写 `get_tree().paused`（见 GDD 9.12 / 9.14） |
| **加录制回放/确定性需求** | 走 `Replay`（autoload）；随机走 `RNG.<stream>`、时间走 `GameClock`；不读非确定时间源（见 GDD 9.9 / 9.18） |
| **加平衡测试 / Headless 模拟** | 通过 `AIPlayer` 接口接入；`Spawner` / `MapManager` / `RNG` 都接受外部 seed（见 GDD 9.10） |
| **加 UI 弹窗** | `UIManager.push(scene)`；场景根节点 `@export modal/pauses_game/music_duck` 元数据；不 `add_child` UI（见 GDD 9.14） |
| **加新敌人/子弹/特效**（高频实体） | `PoolManager.acquire(pool_id)` / `release(node)`；新池 id 在词表 §8 登记；实现 `_pool_reset()`（见 GDD 9.13） |
| **加伤害逻辑** | 走 `Combat.apply_damage(target, DamageInfo)`；`damage_type` 在词表 §9；不 `target.hp -= n`（见 GDD 9.15.1） |
| **加持续效果（DoT/控制/debuff）** | 用 `StatusEffect` Resource + `StatusEffectComponent.apply()`；id 在词表 §9-A；明确 `stack_rule`（见 GDD 9.15.2） |
| **加存档/读档** | 走 `SaveManager.save/load`；schema 必带 `version` + 迁移；与 `Settings` 职责分开（见 GDD 9.16） |
| **加音效/BGM** | `AudioManager.play_sfx/play_music`；id 在词表 §10；不直接 `AudioStreamPlayer.play()`（见 GDD 9.17） |
| **执行 AI 高频任务** | 先查 `docs/AI协作/任务模板/`；任务不在模板里 → 按 `docs/AI协作/上下文预算.md` 决定读取范围 |
| **写/改测试** | 看 `docs/测试策略.md`：L0~L5 金字塔 + 各层必测清单 + 里程碑要求 + 测试义务表 |

## 5. 核心系统模块

### 5.1 模块清单
**业务模块**：`InputController` / `Player` / `WeaponSystem` / `Enemy(EnemyAI)` / `Spawner` / `HazardSystem` / `ItemSystem` / `ModifierEngine` / `MapManager` / `Camera2D` / `DataLoader` / `PauseMenu`（UI）/ `Combat`（伤害结算）/ `StatusEffectComponent`（状态效果）。

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

  Map[MapManager]
  Cam[Camera2D]
  UI[UI/HUD<br/>PauseMenu/...]

  Data --> Loader --> Player & Enemy & Item & Spawner & Hazard
  Set --> Player & Weapon & Input & UIM & Aud
  Loc --> UIM & Item
  Ana <-- 埋点 --- Player & Enemy & Item & Spawner & GS & Save
  RNG --> Spawner & Item & Enemy & Combat
  Clk --> Spawner & Hazard & Weapon & SE
  Rep -. 录制/重放 .-> Input & RNG & Clk & GS

  GS --> UIM
  GS -.- Rep
  UIM --> UI
  Pool --> Weapon & Spawner & Item & Aud

  Input --> Player --> Weapon
  Weapon --> Combat
  Combat --> Player & Enemy
  Combat -.- SE
  Spawner --> Enemy
  Player -.- Cam
  ME -. 修正器叠加 .- Player & Weapon
  Item -. 注册 modifiers/behaviors .- ME
  SE -. 注入 modifier .- ME

  Save -. meta/run kind .- GS
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
- ❌ 硬编码可调数值、玩家可见文本、按键、约定字符串
- ❌ 为每个遗物/道具写独立硬编码分支
- ❌ 相机开启 `limit` / `drag margin`（必须玩家恒居中）
- ❌ 直接 `instantiate`/`queue_free` 高频实体（必须 `PoolManager.acquire/release`）
- ❌ 直接读 `Time.get_ticks_msec()` 等非确定时间源（必须 `GameClock`）
- ❌ 直接调用 `randi()` / `randf()` / `randi_range()`（必须 `RNG.<stream>`）
- ❌ 直接读写 `get_tree().paused` 或自管"in_game"布尔变量（必须 `GameState`）
- ❌ 直接 `add_child` UI 弹窗（必须 `UIManager.push/pop`）
- ❌ `target.hp -= n` 直接扣血（必须 `Combat.apply_damage(DamageInfo)`）
- ❌ 各自实现 DoT/debuff 叠加逻辑（必须 `StatusEffect` Resource + Component）
- ❌ 存档无 `version` 字段（必须 `SaveManager` 标准头）
- ❌ 业务代码 `AudioStreamPlayer.play()`（必须 `AudioManager.play_sfx/music`）
- ❌ 手改 `client/scripts/contracts/*.gd`（自动生成，改 `docs/词表与契约.md` + 跑 `tools/sync_contracts.py`）
- ✅ 改完同步更新规则文件与相关文档（元规则）
- ✅ 重要决策同步进 `docs/AI记忆/项目记忆.md`
