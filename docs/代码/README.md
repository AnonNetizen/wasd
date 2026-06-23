# 代码文档索引

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `docs/代码/` 模块文档索引；新增、删除、重命名模块文档时，必须同步 `docs/AI导航.md` 和对应模块文档中的代码路径。

---

本目录存放与 `client/` 代码对应的长期模块文档。正式项目 F1 已建立最小 Godot 启动骨架；F2 开始创建 autoload 与核心系统时，继续按 `docs/代码文档规范.md` 为每个长期维护模块补详细模块文档。

## 文档形态

- 文档由 AI / 人在写代码时同步维护，可以用模板自动起草，但不能只保留自动抽取的简短摘要。
- 每个长期模块文档都应覆盖职责、代码地图、场景 / 节点结构、运行流程、API、signal、数据、依赖、扩展点、常见改动入口、故障排查、测试义务和迁移 / 兼容说明。
- 代码文件头的 `# Doc:` 必须指向这里的模块文档；多个小脚本可由一个上级模块文档覆盖。

| 模块 | 文档 | 对应代码 | 状态 |
|------|------|----------|------|
| FormalClientBoot | `docs/代码/formal_client_boot.md` | `client/project.godot`、`client/scenes/boot/main.tscn`、`client/scripts/boot/formal_client_boot.gd` | F1 已建立 |
| ModLoader | `docs/代码/mod_loader.md` | `client/scripts/autoload/mod_loader.gd` | 本地 mod 接口首片已建立 |
| DataLoader | `docs/代码/data_loader.md` | `client/scripts/autoload/data_loader.gd` | F2 第一片已建立 |
| RNG | `docs/代码/rng.md` | `client/scripts/autoload/rng.gd` | F2 第一片已建立 |
| GameState | `docs/代码/game_state.md` | `client/scripts/autoload/game_state.gd` | F2 第一片已建立 |
| GameClock | `docs/代码/game_clock.md` | `client/scripts/autoload/game_clock.gd` | F2 第一片已建立 |
| PlatformServices | `docs/代码/platform_services.md` | `client/scripts/autoload/platform_services.gd` | Steam 优先的平台服务接口首片已建立 |
| Settings | `docs/代码/settings.md` | `client/scripts/autoload/settings.gd` | F2 第二片已建立 |
| Analytics | `docs/代码/analytics.md` | `client/scripts/autoload/analytics.gd` | F2 第三片已建立 |
| Replay | `docs/代码/replay.md` | `client/scripts/autoload/replay.gd` | F2 第四片已建立 |
| PoolManager | `docs/代码/pool_manager.md` | `client/scripts/autoload/pool_manager.gd` | F2 第五片已建立 |
| SaveManager | `docs/代码/save_manager.md` | `client/scripts/autoload/save_manager.gd` | F2 第六片已建立 |
| MetaProgressionSystem | `docs/代码/meta_progression_system.md` | `client/scripts/autoload/meta_progression_system.gd` | F6 首切片已建立 |
| AudioManager | `docs/代码/audio_manager.md` | `client/scripts/autoload/audio_manager.gd` | F2 第七片已建立 |
| Localization | `docs/代码/localization.md` | `client/scripts/autoload/localization.gd` | F2 第二片已建立 |
| UIManager | `docs/代码/ui_manager.md` | `client/scripts/autoload/ui_manager.gd` | F2 第二片已建立 |
| Combat | `docs/代码/combat.md` | `client/scripts/combat/combat.gd`、`client/scripts/combat/damage_info.gd` | F4 首切片已建立 |
| Gameplay Runtime | `docs/代码/gameplay_runtime.md` | `client/scripts/gameplay/*.gd`、`client/scripts/ui/title_menu.gd`、`client/scripts/ui/pause_menu.gd`、`client/scripts/ui/game_over_panel.gd`、`client/scripts/boot/formal_client_boot.gd` | F4 首切片已正式命名收口 |
| SkillSystem | `docs/代码/skill_system.md` | `client/scripts/gameplay/skill_system.gd`、`client/data/skills.json`、`client/scripts/gameplay/gameplay_run_loop.gd` | 可复用主动技能 / 轻量 GAS 首片已建立 |
| Enemy AI | `docs/代码/enemy_ai.md` | `client/scripts/gameplay/enemy.gd`、`client/data/enemy_ai_profiles.json` | 数据驱动生态 AI 首片已建立 |
| MapManager | `docs/代码/map_manager.md` | `client/scripts/gameplay/map_manager.gd`、`client/data/map_layouts.json`、`client/scripts/gameplay/gameplay_run_loop.gd` | 有限地图 + 可调 PCG 首片已建立 |
| HazardSystem | `docs/代码/hazard_system.md` | `client/scripts/gameplay/hazard.gd`、`client/scenes/gameplay/hazard.tscn`、`client/data/hazards.csv` | 机关运行时 + FEA-12 测试机关已建立 |
| DebugTools | `docs/代码/debug_tools.md` | `client/scripts/debug/*.gd`、`client/tools/debug_tools_smoke.gd` | debug/dev_tools 专用控制台与 GM 指令首片已建立 |
| 其余核心系统 | 待创建 | `client/scripts/` | F4+ 后续补齐 |

> 约定：模块文档命名使用 lower_snake_case，例如 `rng.md`、`game_state.md`、`weapon_system.md`、`data_loader.md`。文档质量以 `docs/代码文档规范.md` 的“详细模块文档质量标准”为准。
