# wasd —— 俯视角 Roguelike 弹幕生存

> 一款受《以撒的结合》与《吸血鬼幸存者》启发的俯视角 Roguelike 弹幕生存游戏。
> **当前状态：文档/框架设计阶段（尚无代码）。** 本仓库目前是完整的设计文档与编码规则集合，供后续落地实现参考。

---

## 一句话定位
WASD 移动、方向键控制射击方向、**全自动开火**；在开放大地图中靠收集**主动道具 / 消耗品 / 被动遗物**滚雪球式变强，在敌群与机关中尽可能久地存活。

## 技术栈
- **引擎**：Godot 4.6.3
- **语言**：GDScript（强制类型化）
- **平台**：PC（键盘）

## 设计支柱
- **数据驱动**：所有可调数值集中在 `res://data/` 下的 JSON，零代码调参 + 热重载。
- **遗物 = 数据**：用「修正器 modifiers + 行为 behaviors」描述，新增遗物 = 加一条数据，不改逻辑。
- **三条横向基础设施**（框架阶段就内建）：
  - `Localization` —— 多语言本地化，所有玩家可见文本走 `tr("key")`。
  - `Settings` —— 统一玩家偏好管理，信号驱动即时生效，持久化到 `user://settings.cfg`。
  - `Analytics` —— 数据埋点统一接口 `track_event()`，关键节点全留钩子。
- **AI 友好工程**：项目索引、词表白名单、数据校验、黄金样例、ADR、模板，让 AI agent 易读、易写、易扩展。

---

## 必读文档（按优先级）
| 文档 | 作用 | 何时读 |
|------|------|--------|
| [`.codebuddy/rules/game-coding-rules.md`](.codebuddy/rules/game-coding-rules.md) | **强制编码规则** | 每次写代码前 |
| [`AI导航.md`](AI导航.md) | 项目地图与扩展点速查 | 开始任何任务前 |
| [`词表与契约.md`](词表与契约.md) | 约定字符串白名单（stat/effect/event/key/action） | 写数据或常量时 |
| [`游戏设计文档.md`](游戏设计文档.md) | 完整 GDD（v1.3） | 了解整体设计 |
| [`决策记录.md`](决策记录.md) | 既定决策与原因（ADR） | 改动既定约束前 |
| [`修改建议.md`](修改建议.md) | 待决策的开放问题（A~D、J~R） | 评估扩展方向时 |
| [`简单设计思路.md`](简单设计思路.md) | 最初的 10 条核心需求 | 了解项目原点 |

> **AI agent 工作前请先读 `AI导航.md` + 编码规则**，按指引定位后再动手，避免盲目全仓搜索。

---

## 目录约定（代码落地后）
```
res://scenes/      # 场景 .tscn（Player / Bullet / Enemy / Item / Hazard ...）
res://scripts/     # 脚本 .gd（按系统单一职责拆分）
res://data/        # 可调数值配置（JSON）+ 字段说明
res://locale/      # 本地化翻译表（CSV → .translation）
res://templates/   # 新内容脚手架模板（enemy / relic ...）
res://assets/      # 美术 / 音效
user://settings.cfg # 玩家设置存档；user:// 下另存元进度存档
```

## 核心红线（最易踩坑）
- 不硬编码可调数值（全部走 `res://data/`）。
- 不硬编码玩家可见文本（全部走 `tr("key")`）。
- 不硬编码按键（全部走 InputMap action + `Settings` 重绑定）。
- 不为每个遗物/道具写独立分支（用 modifiers + behaviors 数据描述）。
- 不裸字符串（stat / effect / event / 设置 key 必须来自 `词表与契约.md` 并以常量引用）。
- 相机不开 `limit` / `drag margin`（玩家恒居屏幕中央）。
- 高频实体不裸 `instantiate` / `queue_free`（必须对象池）。
- 暂停统一用 `get_tree().paused`，暂停菜单节点设 `process_mode = PROCESS_MODE_ALWAYS`。

> 完整自检清单见编码规则文件末尾。

---

## 如何运行 / 调试
> **当前为文档阶段，无可运行代码。** 落地代码后此处将补充：
> - 用 Godot 4.6.3 打开 `project.godot`；
> - 主场景与启动流程；
> - 调试快捷键（数值热重载、调试面板等）。

## 参与方式（贡献约定）
1. 动手前先读 `AI导航.md` 与 `.codebuddy/rules/game-coding-rules.md`。
2. 新增内容优先**加数据**而非加逻辑；新原语先在 `词表与契约.md` 登记再实现再使用。
3. 新确立的规则/决策/设计变更**必须同步**到对应文档（规则 19/20）：
   - 新规则 → `.codebuddy/rules/game-coding-rules.md`
   - 新决策 → `决策记录.md`
   - 设计变更 → `游戏设计文档.md` + `AI导航.md` + `词表与契约.md`
4. 提交前过一遍编码规则文件末尾的「自检清单」。

---

## 许可证
本项目采用 [MIT License](LICENSE)。

## 版本
- 设计文档：**v1.3**（2026-06）
- 代码：尚未启动
