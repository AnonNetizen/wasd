# AI 导航

> **权威范围**：本文件只提供项目地图与通用任务路由；模块细节由 `docs/代码/` 和代码文件头 `# Doc:` 指针负责。

## 1. 项目概览

`WASD` 是 Godot 4.7.1 + 类型化 GDScript 的俯视角射击 Roguelike。默认对局为 7×7 无缝模块意识层，围绕手动射击、金币成长、Gear Mod 棋盘、事件、传送与意识核终点构筑单局体验。

核心工程原则：数据驱动、双语、确定性、统一运行时边界、未来内容扩展友好和最小文档维护面。

## 2. 权威来源

| 问题 | 权威来源 |
|------|----------|
| 开工顺序 | `AGENTS.md` |
| 项目共同规则 | `docs/AI协作/项目规则.md` |
| 当前阶段 | `docs/AI记忆/current_state.json` |
| 当前任务 / 待决策 | `docs/TODO.md` |
| 玩家规则与系统设计 | `docs/游戏设计文档.md` |
| 重大长期决策 | `docs/决策记录.md` |
| 约定字符串与生成常量 | `docs/词表与契约.md` |
| 测试政策 | `docs/测试策略.md` |
| 公共代码契约 | `docs/代码/<module_id>.md` |
| 数据字段 / locale | `client/data/README.md` / `client/locale/README.md` |
| 未来候选 | `docs/功能建议池.md` |

Git / PR / CI 是完成和验证历史，不另建项目记忆、会话日志或验证报告。

## 3. 目录地图

| 路径 | 作用 |
|------|------|
| `client/` | 正式 Godot 项目根 |
| `client/scripts/` | autoload、gameplay、combat、UI、数据解析与编辑器脚本 |
| `client/scenes/` | 正式场景与生成场景 |
| `client/data/` | JSON / CSV 配置和数据手册 |
| `client/locale/` | `strings.csv` 与双语手册 |
| `client/tools/` | Godot smoke、baker 与正式测试入口 |
| `docs/代码/` | 长期模块公共契约 |
| `docs/AI协作/` | 规则、任务模板、工具和验证流程 |
| `tools/` | 契约、schema、lint、文档健康与 Godot Bridge |
| `output/test_lab/` | 未接入正式客户端的 UI / 素材实验 |
| `output/steamworks_lab/` | 独立 Steamworks 实验项目，不等于正式平台接入 |
| `draft/` / `DRAFT/` | 人工草稿禁区 |

## 4. 通用任务路由

| 任务 | 先看 | 常见入口 |
|------|------|----------|
| 内部重构 / bugfix | 目标代码 + 父模块文档 | 公共契约不变时不改文档 |
| 公共 API / signal / 生命周期 | 目标 `# Doc:` | 模块代码 + 模块文档 |
| 加 / 改数据内容 | 数据手册 + 目标文件 | `client/data/` |
| 加 / 改玩家文本 | locale 手册 | `strings.csv` + `tr()` / key 引用 |
| 加约定 id | 词表 | `sync_contracts.py` 生成产物 |
| 加 Gear Mod / 敌人 / 设置 / 埋点 | 对应任务模板 | 数据优先，禁止内容 id 特判 |
| 改输入 / 重绑定 | `docs/代码/input_service.md` | InputService + GUIDE 资源 |
| 改伤害 / 状态 / 效果 | Combat / Status / Effect 模块文档 | 统一运行时入口 |
| 改存档 / 回放 | Save / Replay 模块文档 | 明确迁移或拒绝策略 |
| 改 UI 弹窗 | UIManager 模块文档 | 受管 UI 栈 |
| 改模块世界 / 敌人 AI | 对应模块文档 | ModuleWorld / EnemyAI |
| 改测试政策 | 测试策略 | 具体测试实现不改策略文档 |
| 改 AI 工作流 | 项目规则 / 文档维护指南 | 平台文件只做适配 |
| 选择未来功能 | TODO / 功能建议池 | 用户点名后再读取对应权威 |

## 5. 核心边界速查

- 数据 → `DataLoader`；locale → `Localization`；输入 → `InputService`。
- 随机 → `RNG`；玩法时间 → `GameClock`；流程 → `GameState`。
- UI → `UIManager`；高频实体 → `PoolManager`；伤害 → `Combat`。
- 状态 → `StatusEffectComponent`；存档 → `SaveManager`；音频 → `AudioManager`。
- 本地 Mod → `ModLoader + DataLoader`；平台 → `PlatformServices`。
- 模块世界由 `GameplayRunLoop` 创建和驱动，不是 autoload。
- 具体依赖、扩展点、测试入口和兼容策略只在所属模块文档维护。

## 6. 验证入口

- 契约：`python tools/sync_contracts.py --check`
- 数据 / locale：`python tools/validate_data.py`
- GDScript：`python tools/lint_gdscript_rules.py`
- 项目规则：`python tools/lint_project_rules.py`
- 语义 advisory：`python tools/lint_semantic_rules.py`
- 文档：`python tools/docs_health_check.py`
- Godot：`python tools/godot_bridge.py --project client <command>`

按当前差异选择命令；性能 probe 和 L5 人工验收不自动执行。
