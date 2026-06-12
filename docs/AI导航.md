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
| `AI导航.md`（本文件） | 项目地图与扩展点定位 |
| `词表与契约.md` | 所有约定字符串白名单（stat/effect/event/key），**禁止编造** |
| `游戏设计文档.md` | 完整设计 |
| `决策记录.md` | 既定决策与原因，勿误改 |
| `修改建议.md` | 待决策的开放问题（A~D） |

## 3. 目录结构与定位
| 路径 | 内容 |
|------|------|
| `res://scenes/` | 场景 `.tscn`（Player / Bullet / Enemy / Item / Hazard 等） |
| `res://scripts/` | 脚本 `.gd`，按系统单一职责拆分 |
| `res://data/` | 可调数值配置（JSON）+ 字段说明 |
| `res://locale/` | 本地化翻译表（CSV → `.translation`） |
| `res://templates/` | 新内容脚手架模板（enemy/relic 等） |
| `res://assets/` | 美术 / 音效 |
| `user://settings.cfg` | 玩家设置存档；`user://` 下另存元进度存档 |

> 注：当前仓库尚处文档阶段，落地代码后此表即为实际结构，新增文件务必归位。

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
| **加暂停/游戏状态控制** | 用 `get_tree().paused` 切换；暂停菜单节点设 `process_mode=ALWAYS`；暂停键用 InputMap action `pause`（走设置）；菜单文本用 `tr()` |

## 5. 核心系统模块
`InputController` / `Player` / `WeaponSystem` / `BulletPool` / `Enemy(EnemyAI)` / `Spawner` / `HazardSystem` / `ItemSystem` / `ModifierEngine` / `MapManager` / `Camera2D` / `DataLoader` / `PauseMenu`（暂停与游戏状态）
三个 autoload 横向基础设施：`Localization`（本地化）/ `Settings`（设置）/ `Analytics`（埋点）。

## 6. 红线（最易踩坑）
- ❌ 硬编码可调数值、玩家可见文本、按键、约定字符串
- ❌ 为每个遗物/道具写独立硬编码分支
- ❌ 相机开启 `limit` / `drag margin`（必须玩家恒居中）
- ❌ 高频实体频繁 `instantiate`/`queue_free`（必须对象池）
- ✅ 改完同步更新规则文件与相关文档（元规则）
