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
| GUIDE | `docs/代码/guide.md` | `client/addons/guide/` | ADR #151 固定 0.14.0 维护型 fork；物理输入 / remapping / prompt 引擎 |
| InputService | `docs/代码/input_service.md` | `client/scripts/autoload/input_service.gd`、`client/resources/input/` | ADR #151 项目唯一输入业务边界；Vector2 intent、context、绑定与回放适配 |
| Analytics | `docs/代码/analytics.md` | `client/scripts/autoload/analytics.gd` | F2 第三片已建立 |
| Replay | `docs/代码/replay.md` | `client/scripts/autoload/replay.gd` | Replay v5：局内 Gear Mod 与意识核直接完成语义；旧 v4 明确拒绝 |
| PoolManager | `docs/代码/pool_manager.md` | `client/scripts/autoload/pool_manager.gd` | F2 第五片已建立 |
| SaveManager | `docs/代码/save_manager.md` | `client/scripts/autoload/save_manager.gd` | Meta v3 / Run v13、局内 Gear Mod ranks 与旧 Run v12 明确拒绝 |
| GearModSystem | `docs/代码/gear_mod_system.md` | `client/scripts/autoload/gear_mod_system.gd`、`client/data/gear_mods.json`、`client/data/gear_mod_drop_tables.csv`、`client/tools/gear_mod_smoke.gd` | 无状态规则服务；局内授予、升阶、满阶溢出和替换式 modifier 由 RunLoop 权威编排 |
| AudioManager | `docs/代码/audio_manager.md` | `client/scripts/autoload/audio_manager.gd` | F2 第七片已建立 |
| Localization | `docs/代码/localization.md` | `client/scripts/autoload/localization.gd` | F2 第二片已建立 |
| UIManager | `docs/代码/ui_manager.md` | `client/scripts/autoload/ui_manager.gd` | F2 第二片已建立 |
| UI Effects | `docs/代码/ui_effects.md` | `client/scripts/ui/effects/`、`client/scenes/ui/effects/` | ADR #158 共享 UI 动效已建立；ADR #168 后统一采用正常动态表现 |
| Visual Effects | `docs/代码/visual_effects.md` | `client/scripts/autoload/visual_effects.gd`、`client/scripts/vfx/`、`client/scripts/gameplay/presentation/`、`client/addons/vfx_library/` | ADR #158 数据目录、运行时 Host、全量接线与编辑器库已建立 |
| Gameplay Loading | `docs/代码/gameplay_loading.md` | `client/scenes/ui/loading_screen.tscn`、`client/scripts/ui/loading_screen.gd`、`client/scripts/boot/formal_client_boot.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`client/tools/loading_smoke.gd` | ADR #157 开始 / 继续 / 重开统一加载流程已建立 |
| Combat | `docs/代码/combat.md` | `client/scripts/combat/combat.gd`、`client/scripts/combat/damage_info.gd`、`client/data/elements.json` | 七元素、三层防御、护盾门与来源过滤已建立 |
| Gameplay Runtime | `docs/代码/gameplay_runtime.md` | `client/scripts/gameplay/*.gd`、`client/scripts/ui/title_menu.gd`、`client/scripts/ui/pause_menu.gd`、`client/scripts/ui/game_over_panel.gd`、`client/scripts/boot/formal_client_boot.gd` | Run v13 Roguelike 对局编排、局内 Gear Mod、模块世界、世界事件与意识核直接完成已建立 |
| DifficultyProgression | `docs/代码/difficulty_progression.md` | `client/scripts/data/difficulty_progression.gd`、`client/data/difficulty_profiles.json`、`client/scripts/gameplay/gameplay_run_loop.gd` | ADR #166 / #175 模式级威胁时间、难度系数、出生倍率与起点门禁 |
| EnemyRewardResolver | `docs/代码/enemy_reward_resolver.md` | `client/scripts/data/enemy_reward_resolver.gd`、`client/data/enemy_rewards.json`、`client/data/enemies.csv` | ADR #175 敌人生成时金币公式、饱和取整与计算明细 |
| DifficultyMarker | `docs/代码/difficulty_marker.md` | `client/scripts/ui/difficulty_marker.gd`、`client/scenes/ui/difficulty_marker.tscn`、Gameplay HUD | ADR #166 右上角威胁等级标记器 |
| Phantom Camera | `docs/代码/phantom_camera.md` | `client/addons/phantom_camera/`、`client/scripts/gameplay/gameplay_camera_controller.gd`、`client/scenes/gameplay/gameplay_camera_controller.tscn` | ADR #148 固定版本维护型 fork 与正式 2D 玩家相机接入已建立 |
| SkillSystem | `docs/代码/skill_system.md` | `client/scripts/data/hero_composition_resolver.gd`、`client/scripts/gameplay/skill_system.gd`、`client/data/characters.json`、`client/data/skills.json` | 主／子英雄四槽、能量、能力缩放与部署物已建立 |
| StatusEffectComponent | `docs/代码/status_effect_component.md` | `client/scripts/combat/status_effect.gd`、`client/scripts/combat/status_effect_component.gd`、`client/scripts/gameplay/skill_system.gd` | 减速、加速、易伤、DoT 与快照已建立 |
| Enemy AI | `docs/代码/enemy_ai.md` | `client/scripts/gameplay/enemy.gd`、`client/data/enemy_ai_profiles.json` | 数据驱动对玩家 AI、敌方友伤护栏与中心分离已建立 |
| MapManager | `docs/代码/map_manager.md` | `client/scripts/gameplay/map_manager.gd`、`client/data/map_layouts.json`、`client/scripts/gameplay/gameplay_run_loop.gd` | 有限地图 + 可调 PCG 首片已建立 |
| ModuleWorldManager | `docs/代码/module_world_manager.md` | `client/scripts/gameplay/module_world_manager.gd`、`client/scripts/gameplay/module_chunk.gd`、`client/data/module_worlds.json`、`client/data/module_templates.json`、`client/data/modules/*.json` | schema v4 无撤离模块世界、12 chunk 与 Run v13 固定模块快照 |
| Module Authoring Pipeline | [`module_authoring_pipeline.md`](module_authoring_pipeline.md) | `client/data/modules/*.json`、`client/data/module_tile_catalog.json`、`client/addons/module_authoring/`、`client/scenes/generated/modules/`、`client/tools/module_bake_*.gd` | ADR #154 JSON 制作主源、可视化 Dock、单向 TSCN 烘焙与审核门禁已建立 |
| Data Table Editor | [`data_table_editor.md`](data_table_editor.md) | `client/addons/data_table_editor/`、`client/scripts/editor/data_table_*.gd`、`tools/sync_contracts.py` | ADR #180 普通 JSON / 全部数据 CSV / strings.csv 一站式编辑、全局搜索、草稿与事务保存已建立 |
| WorldEventSystem | `docs/代码/world_event_system.md` | `client/scripts/gameplay/world_events/`、`client/scenes/gameplay/world_events/`、`client/data/world_events.json` | ADR #173 / #175 / #188 五类交互事件、固定局内 Mod 奖励与 Run v13 幂等恢复 |
| HazardSystem | `docs/代码/hazard_system.md` | `client/scripts/gameplay/hazard.gd`、`client/scenes/gameplay/hazard.tscn`、`client/data/hazards.csv` | 机关运行时 + FEA-12 测试机关已建立 |
| WarzoneDirector | `docs/代码/warzone_director.md` | `client/scripts/gameplay/warzone_director.gd`、`client/data/warzone_directors.json`、`client/scripts/gameplay/gameplay_run_loop.gd` | F10 敌巢战区导演首片已建立 |
| DebugTools | `docs/代码/debug_tools.md` | `client/scripts/debug/*.gd`、`client/tools/debug_tools_smoke.gd` | debug/dev_tools 专用控制台与 GM 指令首片已建立 |
| Developer Test Arena | `docs/代码/debug_test_arena.md` | `client/scenes/debug/`、`client/scripts/debug/debug_test_arena_*.gd`、`client/tools/debug_test_arena_smoke.gd` | ADR #159 / #160 独立 debug scene、standalone host、配装、训练靶、控制面板、伤害统计与 release / 存档隔离 |
| 其余核心系统 | 待创建 | `client/scripts/` | F4+ 后续补齐 |

> 约定：模块文档命名使用 lower_snake_case，例如 `rng.md`、`game_state.md`、`weapon_system.md`、`data_loader.md`。文档质量以 `docs/代码文档规范.md` 的“详细模块文档质量标准”为准。
