# AI 知识库索引

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是 `docs/` 作为 AI 知识库的人工可读总索引；新增、删除、重命名长期文档时，必须同步 `docs/_kb_index.json`、`docs/AI导航.md`、必要时 `docs/AI协作/文档健康检查.md`、`docs/AI记忆/项目记忆.md` 与 `docs/AI记忆/current_state.json`。

---

## 1. 目标

让 `docs/` 不只是文档集合，而是可检索、可校验、可追踪的 AI 知识库。

本索引解决四个问题：

| 问题 | 解决方式 |
|------|----------|
| AI 不知道先读哪篇 | 按任务和权威范围列出入口 |
| 文档冲突时不知道谁说了算 | 明确权威层级 |
| 改文档容易漏同步 | 用 `update_triggers` 和健康检查约束 |
| 搜索同义词容易漏 | 配合 `docs/术语表.md` 管理关键词别名 |

## 2. 机器索引

机器可读索引位于 `docs/_kb_index.json`。

每个条目至少包含：

| 字段 | 含义 |
|------|------|
| `path` | 文档或目录路径 |
| `type` | 文档类型，如 `authority` / `index` / `workflow` / `template` / `memory` |
| `authority` | 本文档的权威范围 |
| `status` | `active` / `planned` / `archive` |
| `owner_scope` | 维护责任范围，如 `design` / `code-docs` / `ai-workflow` / `ci` |
| `last_reviewed` | 最近一次结构性审查日期 |
| `canonical_for` | 本文档是哪些主题的唯一或主要权威 |
| `must_read_for` | 哪些任务必须读本文档 |
| `related_docs` | 需要联动阅读或同步的文档 |
| `related_code` | 相关代码路径或目录 |
| `update_triggers` | 哪些改动必须同步本文档 |
| `keywords` | 检索关键词和别名 |

## 3. 权威层级

文档冲突时按下列顺序判断：

| 层级 | 权威来源 | 管什么 |
|------|----------|--------|
| 1 | `AGENTS.md` + 当前平台规则入口 | AI 开工流程、强制编码红线 |
| 2 | `docs/决策记录.md` | 已采纳决策与不可逆约束 |
| 3 | `docs/游戏设计文档.md` | 玩法、系统、长期设计 |
| 3-A | `docs/IP设定.md` | 《破巢者》IP、世界观包装、命名体系和宣发基调 |
| 3-B | `docs/IP美术风格.md` | 《破巢者》IP 美术风格、敌巢色板、阵营色、地图兴趣点功能色和资产 brief 色彩规则 |
| 4 | `docs/词表与契约.md` | 约定字符串、id 白名单、InputService / GUIDE action |
| 5 | `docs/测试策略.md` | 测试层级、覆盖率、回放、手动回归 |
| 6 | `docs/代码文档规范.md` + `docs/代码/` | 代码模块文档要求和模块契约 |
| 7 | `docs/AI导航.md` | 项目地图、扩展点、依赖图 |
| 8 | `docs/AI协作/快速开工.md` + `docs/AI记忆/current_state.json` + `docs/AI记忆/项目记忆.md` | 快速开工热路径、当前状态、长期记忆冷存储 |
若低层文档与高层文档冲突，应先同步高层权威，再更新引用方。

## 4. 任务路由表

| 任务 | 必读 | 常改文件 | 必跑检查 |
|------|------|----------|----------|
| 新会话接入 | `AGENTS.md`、`docs/AI协作/快速开工.md`、`docs/AI记忆/current_state.json`、`docs/AI导航.md` 相关段、当前平台规则入口 | 通常不改文件 | 无；若发现文档漂移跑 `python tools/docs_health_check.py` |
| 续接当前任务 | `docs/AI协作/快速开工.md`、`docs/AI记忆/current_state.json`、当日会话日志；需要长期背景时再读 `项目记忆.md` 相关节 | 通常不改文件 | 无；需要确认状态时跑 `python tools/docs_health_check.py` |
| 查看 / 维护未来任务 | `docs/TODO.md`、`docs/功能建议池.md`、`docs/局内刷取参考研究.md`、`docs/AI辅助开发机会清单.md`、`docs/在线服务规划.md`、`docs/小服务器玩法备忘.md`、`docs/AI记忆/current_state.json`、`docs/修改建议.md` | `docs/TODO.md`、必要时 current_state / 会话日志 / 修改建议 / 功能建议池 / 研究与规划文档 | `python tools/docs_health_check.py`；若改 JSON 同步跑 `python -m json.tool` |
| 改 IP / 世界观 / 英雄包装 / 宣传语 | `docs/IP设定.md`、涉及视觉时追加 `docs/IP美术风格.md`、`docs/游戏设计文档.md` §1.2、`docs/术语表.md` | IP 设定、IP 美术风格、GDD 摘要、术语表、AI导航、必要时 ADR / AI记忆 / locale 文案 | `python tools/docs_health_check.py`；若改 JSON 同步跑 `python -m json.tool` |
| 选择下一项新功能 / 功能菜单 | `docs/功能建议池.md`、`docs/局内刷取参考研究.md`、`docs/AI辅助开发机会清单.md`、`docs/TODO.md`、`docs/AI记忆/current_state.json`；若用户点名具体系统，再读对应工作包 / 模块文档 / GDD 章节 | 用户点名后再改 TODO / current_state / 工作包 / GDD / ADR / 模块文档；未点名前不实现功能 | `python tools/docs_health_check.py`；若改 JSON 同步跑 `python -m json.tool`；进入实现后按目标工作包验收命令运行 |
| 规划 / 接入在线服务 | `docs/在线服务规划.md`、ADR #150、GDD §9.22 / §9.23、`docs/代码/platform_services.md`、`docs/测试策略.md` | 当前只维护供应商与门禁；用户点名首个功能后才建立工作包、决定 Talo Cloud / 官方自托管并实施 GodotSteam / Talo adapter；不开发自有通用后端 | 纯规划跑 docs health + JSON；实施时按在线服务规划和测试策略追加隔离验证、headless、平台 / 在线 smoke |
| 评估小服务器在线玩法 | `docs/小服务器玩法备忘.md`、`docs/在线服务规划.md`、GDD §6.7 / §9.23、`docs/代码/replay.md` | GodotSteam + Talo 供应商路线已采纳，但具体玩法仍需用户点名；未点名前只做评估，不安装、不实现 | `python tools/docs_health_check.py`；若新增在线服务 schema 或 JSON 索引，同步跑 `python -m json.tool` |
| 加 / 改美术资产 / 占位表现 | `docs/IP美术风格.md`、GDD §8.2-A、`docs/代码/gameplay_runtime.md`、`docs/AI协作/工作包/F9-ContentDemoPolish.md`、`docs/术语表.md` 的“俯视资产落地规则” | `client/assets/`、目标 gameplay / UI 场景、相关模块文档；新增正式资源 brief 时写清色彩归属、asset_type、footprint、anchor、orientation_read、sort layer、collision / trigger shape | 纯文档 / brief 跑 `python tools/docs_health_check.py`；触碰资源引用或运行时表现时按目标模块跑 smoke / lint；改 JSON 同步跑 `python -m json.tool` |
| 启动 / 推进正式项目 | 当前 F14 读 `docs/AI协作/工作包/F14-EnemyNavigationAndPerception.md`、EnemyAI / ModuleWorldManager 文档、GDD §5.3、ADR #145 / #146、数据手册与测试策略；F13 模块大地图保持完成，旧 `F13-HandcraftedRooms.md` 只作历史；F12 开放战区仅作非默认回归 | `client/`、模块文档、必要时 TODO / GDD / ADR / 测试策略 | 按 F14 工作包跑 contracts/data/schema、module-world、technical-slice、runtime、save、headless 与 golden；局部流场需验证半径 / 边界 / 访问格数；项目规则变化跑 project lint；文档变化跑 docs health；性能仅用户明确要求时运行 |
| 维护正式客户端启动骨架 | `client/README.md`、`docs/代码/formal_client_boot.md`、`docs/代码/gameplay_runtime.md`、`docs/正式项目工作规划.md` F1/F4 | `client/project.godot`、`client/scenes/boot/main.tscn`、`client/scripts/boot/formal_client_boot.gd`、AI导航、代码文档索引 | `python tools/godot_bridge.py headless-boot`、`python tools/godot_bridge.py export-tree`、`python tools/docs_health_check.py` |
| 维护 F2+ autoload 骨架 | GDD §9.3~§9.23、`docs/代码/mod_loader.md`、`docs/代码/data_loader.md`、`docs/代码/rng.md`、`docs/代码/game_state.md`、`docs/代码/game_clock.md`、`docs/代码/platform_services.md`、`docs/代码/settings.md`、`docs/代码/guide.md`、`docs/代码/input_service.md`、`docs/代码/analytics.md`、`docs/代码/replay.md`、`docs/代码/pool_manager.md`、`docs/代码/save_manager.md`、`docs/代码/audio_manager.md`、`docs/代码/localization.md`、`docs/代码/ui_manager.md` | `client/scripts/autoload/`、GUIDE autoload、`client/project.godot`、AI导航、代码文档索引、current_state | `python tools/godot_bridge.py headless-boot`、`python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/docs_health_check.py`；输入顺序变化追加 input smoke |
| 加 / 改角色 | GDD §3.4、`client/data/README.md`、`docs/词表与契约.md` §12、`docs/AI导航.md` | `client/data/characters.json`、`client/locale/strings.csv`、起始携带引用、必要时词表和模块文档 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加 / 改武器 | `client/data/README.md`、`docs/词表与契约.md` §1 / §8 / §9 / §10、`docs/AI导航.md` | `client/data/weapons.json`、`client/locale/strings.csv`、必要时角色 / 模式引用 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 改子弹墙体阻挡 / 穿墙能力 | GDD §4、ADR #149、`docs/代码/gameplay_runtime.md`、`docs/代码/module_world_manager.md`、`client/data/README.md` | `client/scripts/gameplay/bullet.gd`、`module_chunk.gd`、`weapons.json`、stat 契约 / 生成常量、双端 DataLoader、`module_world_smoke.gd` | contracts/data/schema + GDScript/project/strict semantic lint + 完整 / 技术切片 module-world + runtime/save/L1 + headless + 四条黄金回放；不跑性能 probe |
| 加 / 改技能 | `docs/代码/skill_system.md`、`client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §12-C~12-G、涉及状态时追加 §9-A~§9-B 与 `docs/代码/status_effect_component.md`、`docs/AI导航.md` | `client/data/skills.json`、`client/data/characters.json`、`client/data/game_modes.json`、`client/locale/strings.csv`、必要时词表 / DataLoader schema / runtime smoke | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；`python tools/lint_project_rules.py`；schema 变化跑 `python tools/test_data_loader_schema.py`；运行时行为变化跑 `l1-smoke` + `runtime-smoke` |
| 加 / 改状态效果 | `docs/代码/status_effect_component.md`、`docs/代码/skill_system.md`、GDD §9.15.2、`docs/词表与契约.md` §9-A~§9-B / §12-F~§12-G、`docs/测试策略.md` | `client/scripts/combat/status_effect.gd`、`client/scripts/combat/status_effect_component.gd`、`client/scripts/gameplay/skill_system.gd`、`client/scripts/gameplay/player.gd`、`client/scripts/gameplay/enemy.gd`、`client/data/skills.json`、DataLoader schema、必要时 run 快照 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；`python tools/test_data_loader_schema.py`；`python tools/godot_bridge.py --project client l1-smoke`；影响续局时追加 `save-smoke`；影响整局时评估 golden |
| 加 / 改游戏模式 | GDD §6.6、`client/data/README.md`、`docs/AI导航.md` | `client/data/game_modes.json`、资源池 / 权重 / 禁用列表、必要时词表和模块文档 | `python tools/docs_health_check.py`；`python tools/validate_data.py` |
| 加遗物 / 道具 | `client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §1 / §2 / §3 / §12、`docs/AI协作/任务模板/加遗物.md` | `client/data/relics.json`、`client/locale/strings.csv`、必要时词表、模式引用和效果原语 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加 / 改主动道具 | `client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §2 / §6 / §7 / §12、`docs/AI导航.md` | `client/data/active_items.json`、`client/data/game_modes.json` 主动道具池、`client/locale/strings.csv`、必要时词表和效果原语 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加 / 改消耗品 | `client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §2 / §6 / §12、`docs/AI导航.md` | `client/data/consumables.json`、`client/data/game_modes.json` 消耗品池、`client/locale/strings.csv`、必要时词表和效果原语 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加敌人 | `docs/AI协作/任务模板/加敌人.md`、`client/data/README.md`、`client/locale/README.md`、`docs/代码/enemy_ai.md`、`docs/词表与契约.md` §8/9/12、GDD 敌人章节 | `client/data/enemies.csv`、`client/data/enemy_ai_profiles.json`、`client/locale/strings.csv`、`game_modes` 敌人池、必要时 AI action / content tag 词表 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 改 EnemyAI 对玩家行为 / 导航 / 感知 | F14 工作包、`docs/代码/enemy_ai.md`、`docs/代码/module_world_manager.md`、GDD §5.3、数据手册、词表 §12-B、ADR #144 / #145 / #146 | `enemy.gd`、`module_navigation_field.gd`、`module_world_manager.gd`、`gameplay_run_loop.gd`、`enemy_ai_profiles.json`、DataLoader 双端 schema、module-world / runtime smoke、必要时 golden | 跑 contracts/data/schema、GDScript/project/semantic lint、headless、module-world、runtime、save 与 golden；活动流场保持感知范围驱动的局部上限，全图 AStar 不截断；保持玩家唯一目标、友伤拒绝和中心分离；性能仅用户明确要求时运行 |
| 改地图 / 矩形格 / PCG / 人工摆点 | `docs/代码/map_manager.md`、`client/data/README.md` 的 `map_layouts.json` 段、GDD §5、ADR #93 / #125 / #106 | `client/data/map_layouts.json`、`client/scripts/gameplay/map_manager.gd`、`client/tools/runtime_smoke.gd`、必要时 `docs/代码/hazard_system.md`；bounds 需分别整除 `grid.cell_width/cell_height`，出生安全区视觉必须贴矩形格，机关摆点按 `radius_tiles` 奇偶吸附到合法锚点 | `python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/godot_bridge.py --project client runtime-smoke`；机关相关追加 `f9-demo-smoke` / `save-smoke`；性能 probe 仅在用户明确要求时运行 |
| 改模块大地图 / AI 模块内容 | `docs/AI协作/工作包/F13-ModularGridWorld.md`、`docs/代码/module_world_manager.md`、GDD §5、`client/data/README.md`、词表 §15 | `module_worlds.json`、`module_templates.json`、`modules/*.json`、ModuleWorldManager / ModuleChunk / minimap、GameplayRunLoop、run v4；AI 新模块默认 candidate，人工 approved 后才入池 | `sync_contracts --check` + `validate_data` + schema test + `module-world-smoke` + `save-smoke` + headless；稳定行为变化重录并跑四条 golden replay |
| 加 / 改机关 | `docs/代码/hazard_system.md`、`client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §8/9/12、`docs/AI导航.md` | `client/data/hazards.csv`、`client/data/map_layouts.json`、`client/locale/strings.csv`、`game_modes` 机关池、必要时地图 / 机关 primitive；当前通用机关是矩形危险地块，`radius_tiles` 为占用地图矩形格的整数倍 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；运行时机关变化跑 `runtime-smoke` / `f9-demo-smoke`；文档变化跑 `python tools/docs_health_check.py` |
| 加 / 改刷怪波次 | `client/data/README.md`、GDD §5.3 / §9.3、`docs/AI导航.md` | `client/data/spawn_waves.csv`、DataLoader schema、必要时 Spawner 模块文档 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 加 / 改战区导演 | `docs/AI协作/工作包/F10-WarzoneDirector.md`、`docs/代码/warzone_director.md`、`client/data/README.md`、GDD §7.3、ADR #112 / #113 | `client/data/warzone_directors.json`、`client/scripts/gameplay/warzone_director.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/gameplay/map_manager.gd`、DataLoader schema、必要时 EnemyAI 文档 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；运行时变化跑 `runtime-smoke` / `f9-demo-smoke` / `save-smoke`，地图 placement 变化评估 golden；文档变化跑 `python tools/docs_health_check.py` |
| 改输入 / 手柄 / 重绑定 | `docs/代码/input_service.md`、`docs/词表与契约.md` §7、ADR #151、`docs/测试策略.md`；维护插件内部再读 `docs/代码/guide.md` | 生成 action、GUIDE 资源、InputService、Settings / Replay / UI / gameplay 调用方、规则与 AI 导航；不默认扫描整个 addon | `input-smoke`、`settings-smoke`、`replay-input-smoke`、runtime / replay runner、headless；真实手柄与提示人工回归；文档跑 docs health |
| 改经验 / 升级系统 | `docs/游戏设计文档.md` §7.1、`docs/代码/gameplay_runtime.md`、`client/data/README.md` | `GrowthSystem`、升级 UI、GDD、AI导航、必要时 `docs/修改建议.md`；ADR #120 后默认标准模式不启用局内 3 选 1，未来模式需在 `game_modes.json.resource_pools.growth_pools` 显式挂接 | `python tools/docs_health_check.py`；默认模式代码落地后验证不进 `LEVEL_UP`；未来模式启用时固定 seed 验证 3 选 1 与 `luck` 概率 4 选 1 |
| 改短刷图默认循环 | `docs/AI协作/工作包/F12-ShortLootRuns.md`、`docs/局内刷取参考研究.md`、GDD §2 / §5 / §7、`docs/代码/gameplay_runtime.md`、`docs/代码/warzone_director.md`、`docs/代码/map_manager.md` | `client/data/game_modes.json`、`warzone_directors.json`、`spawn_waves.csv`、`map_layouts.json`、Gear Mod 掉落 / 结算相关代码与文档 | `validate_data`、`test_data_loader_schema`、`runtime-smoke`、`f9-demo-smoke`、`gear-mod-smoke`；性能 probe 仅在用户明确要求时运行 |
| 改装备 Mod / 局外装配 | `docs/游戏设计文档.md` §7.2、`docs/AI协作/工作包/F11-GearModLoadout.md`、`docs/代码/gear_mod_system.md`、`client/data/README.md`、`docs/词表与契约.md`、`docs/测试策略.md` | `client/scripts/autoload/gear_mod_system.gd`、`client/tools/gear_mod_smoke.gd`、`client/scripts/ui/gear_mod_panel.gd`、`client/data/gear_mods.json`、`client/data/gear_mod_drop_tables.csv`、`client/data/gear_mod_fusion_costs.csv`、locale、GDD、词表、AI导航、SaveManager / gameplay runtime 模块文档 | F11 数据 / 契约首片已纳入 `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`；运行时与最小 UI 首片已纳入 `python tools/godot_bridge.py --project client gear-mod-smoke`；影响开局属性 snapshot 或敌人击杀归因时追加 `runtime-smoke` 并评估 golden replay |
| 查旧局外成长历史 | `docs/AI协作/工作包/F6-MetaProgression.md`、GDD §7.2 / §9.16、ADR #46 / #115 / #117 / #118 | 历史 F6 结算、账号等级、永久升级轨道和退役决策 | 旧运行时和 UI 已按 ADR #117 删除；项目尚未上线，ADR #118 后旧测试档迁移 / 补偿、`meta_progression.json` 和旧 meta 契约也已删除；不要把旧迁移作为当前任务入口 |
| 改存档 / 暂停退出续局 | `docs/游戏设计文档.md` §9.16、`docs/词表与契约.md` §14、`docs/测试策略.md` | SaveManager、GameState、暂停菜单、主菜单、GDD、词表、AI导航、模块文档 | SaveManager 单测、run roundtrip、损坏 / 迁移测试；代码落地后跑 headless 和手动存档 checklist |
| 调完整项目数值 | `client/data/README.md`、目标 `client/data/*.csv` / `client/data/*.json`、`docs/词表与契约.md` | 数据 CSV / JSON、数值手册、必要时 GDD / 模块文档 / 黄金回放 | `python tools/validate_data.py`；大改动跑回放 / 平衡验证 |
| 加完整项目文案 / 语言 | `client/locale/README.md`、`client/locale/strings.csv`、`docs/词表与契约.md` §6 | 文案 CSV、语言设置、相关 UI / 数据模块文档；AI 自动补齐 `zh_CN` / `en` 另一语言首版译文；涉及 UI 布局时按英文 `en` 长度验收 | `python tools/validate_data.py`；UI 文案 / 布局变化跑 `settings-smoke` 或对应 smoke；人工切语言回归 |
| 改致谢 / 第三方来源 | `CREDITS.md`、`client/data/README.md`、`client/locale/README.md` | `client/data/credits.json`、`client/locale/strings.csv`、DataLoader schema、AI导航、必要时 ADR / 记忆 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 安装 / 升级 Godot 编辑器插件 | `client/addons/README.md`、`client/README.md`、`CREDITS.md`、对应官方发布包 / LICENSE | `client/addons/<plugin>/`、`client/project.godot`、Credits 数据与 locale、ADR、AI导航、AI记忆；固定版本入库、记录 SHA-256、保留许可、人工迁移本地补丁，不设 lint 豁免 | `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/validate_data.py`、`python tools/godot_bridge.py headless-boot`、Godot `--headless --editor` 加载、交互验收、完整 pre-commit |
| 维护 Phantom Camera 内部 / 玩家相机接入 | `docs/代码/phantom_camera.md`、`client/addons/README.md`、ADR #148；改项目行为时追加 `docs/代码/gameplay_runtime.md`、GDD §5.2 与测试策略 | addon Runtime Core / Resource / Editor / C# wrapper 目标源码，或 `gameplay_camera_controller.gd/.tscn`、`camera_feedback.json`；保持 Manager 固定 autoload、Updater Off、`physics_jitter_fix=0.5`、`RNG.camera_fx` 和插件 / 项目适配层边界 | 纯文档 / 源码头跑 docs health、JSON、GDScript lint、完整 pre-commit 与 headless boot；行为变化按测试策略追加 data/schema、settings/runtime smoke、headless editor 和人工相机验收 |
| 维护 / 升级 GUIDE 内部 | `docs/代码/guide.md`、`client/addons/README.md`、ADR #151；改项目适配再读 `docs/代码/input_service.md` | 只读目标 runtime / input / remapping / formatter / editor 源码；保持显式 autoload、单调 context 序号、detector 负轴 / 取消清理、无自动更新、无 lint 豁免和插件 / 适配层边界 | 三档 lint、input/settings/replay smoke、runtime、headless boot、headless editor；输入语义变化追加四条黄金回放和真实手柄验收 |
| 维护本地 mod 接口 / 未来创意工坊边界 | GDD §9.21、`docs/代码/mod_loader.md`、`docs/代码/data_loader.md`、`client/data/README.md`、`docs/测试策略.md` | `client/scripts/autoload/mod_loader.gd`、`client/scripts/autoload/data_loader.gd`、`client/project.godot`、`client/tools/l1_smoke.gd`、三平台规则、AI导航、ADR、AI记忆 | `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client l1-smoke`、`python tools/godot_bridge.py --project client headless-boot`、文档变化跑 `python tools/docs_health_check.py` |
| 维护 Steam API / 平台服务接口 | GDD §9.22、`docs/代码/platform_services.md`、`docs/测试策略.md`、`docs/AI导航.md` | `client/scripts/autoload/platform_services.gd`、`client/project.godot`、`client/scripts/boot/formal_client_boot.gd`、`client/tools/l1_smoke.gd`、三平台规则、ADR、AI记忆 | `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client l1-smoke`、`python tools/godot_bridge.py --project client headless-boot`；真实 Steam 接入追加平台手动 smoke |
| 维护 Steamworks Slime Lab / 单人 AI 大招与自主游击 / 本地同屏 / 纪录 / App ID | `output/steamworks_lab/README.md`、ADR #129 / #135 / #136 / #137 / #138 / #139 / #140、`docs/测试策略.md`、`docs/AI导航.md` | `tools/steamworks_lab_toolchain.py`、`tools/test_steamworks_lab_toolchain.py`、`scripts/ai_teammate.gd`、`scripts/local_input_router.gd`、`scripts/steamworks_lab.gd`、`project.godot`、`steam_appid.txt`、transport / network / save / Records / HUD 脚本与 Lab tests；Lab 与正式 `client/PlatformServices` 边界、必要时 AI 记忆 | 单人 AI 大招只允许 `PlayMode.SINGLE`，保持 100 点充能、10 秒 AI、释放后再按住 `E` 与单次合体边界；ADR #140 追加确定性敌弹预判、敌人 / Boss / 障碍避让、210 px 常规硬限、超过 220 px 复位、按 `E` 后高速归队至 92 px 并停靠 0.8 秒再合体。AI 仍不可受伤、不吸引火力；网络 / 存档 / 正式 `client` 不变。`battle_smoke` 覆盖充能 / 游击闪避 / 距离边界 / 归队合体 / HUD / 排除项，`local_couch_smoke` 证明多人无该能力；目标 battle 1/1、local-couch 与权威 `smoke --suite all` 已通过，all 含 battle 5/5、动态端口 ENet、最大分片仍不超过 900 字节且受保护文件未改变。自动回归一律先跑目标 suite，完成前跑 `--suite all`；runner 隔离 `user://`、保护真实设置 / 存档和源码 App ID、验证精确标志、动态 ENet 端口、900 字节 wire 统计与 MTU 日志。改 runner 追加 Python 单元测试；真实发布追加 1–3 手柄同屏、runtime App ID、双账号 overlay / Lobby / invite / cold-start / offline 与 Depot 内容检查 |
| 改规则 / 红线 | `AGENTS.md`、当前平台规则入口、`docs/决策记录.md`、`docs/AI协作/文档维护指南.md` | `AGENTS.md`、三平台规则、`CODEX.md`、`OPENCODE.md`、AI导航、项目记忆 | `python tools/docs_health_check.py`、`git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"` |
| 改约定字符串 | `docs/词表与契约.md`、`docs/AI协作/文档健康检查.md` | 词表、生成常量、相关数据 / 代码、AI导航 | `python tools/sync_contracts.py` + `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；`python tools/docs_health_check.py` |
| 写/改 F4 最小可玩闭环 | `docs/AI协作/工作包/F4-MinPlayableLoop.md`、`docs/代码/gameplay_runtime.md`、`docs/代码/combat.md`、相关 autoload 模块文档 | `client/scripts/gameplay/`、`client/scripts/combat/`、`formal_client_boot.gd`、locale、模块文档、AI导航 | `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、数据 / 文案变化时跑 `validate_data` 和 `lint_project_rules` |
| 查 F6 旧局外成长历史 | `docs/AI协作/工作包/F6-MetaProgression.md`、`docs/游戏设计文档.md` §7.2 / §9.16、`docs/代码/save_manager.md`、ADR #46 / #115 / #117 / #118 | 历史 `MetaProgressionSystem`、历史旧局外成长设计、SaveManager meta 边界、AI导航 | 旧运行时 / UI / smoke 已删除；旧测试档迁移 / 补偿变化不再是活跃任务，若未来重新引入必须新增 ADR |
| 写/改 F7 设置 / 本地化 / UI 栈 | `docs/AI协作/工作包/F7-SettingsLocalizationUI.md`、`docs/代码/settings.md`、`docs/代码/input_service.md`、`docs/代码/localization.md`、`docs/代码/ui_manager.md`、`client/locale/README.md`、GDD §9.4 / §9.5 / §9.14 | `Settings`、`InputService`、`Localization`、`UIManager`、设置面板、GUIDE binding / prompt、标题 / 暂停 / HUD / locale、AI导航；UI 尺寸以英文 `en` 验收 | contracts/data、headless、runtime / save；输入变化追加 input/settings/replay-input smoke，Gear Mod UI 变化追加 gear-mod smoke；文档跑 docs health |
| 写/改 F8 回放 / 测试 / 平衡基线 | `docs/AI协作/工作包/F8-ReplayTestingBalance.md`、`docs/测试策略.md`、`docs/CICD规划.md`、`docs/代码/replay.md`、`docs/代码/rng.md`、`docs/代码/game_clock.md`、`docs/代码/game_state.md`、`docs/代码/save_manager.md`、`docs/代码/gameplay_runtime.md` | `Replay`、`RNG`、`client/tools/l1_smoke.gd`、`client/tools/replay_smoke.gd`、`client/tools/replay_runner.gd`、`client/tools/replay_input_smoke.gd`、`client/tools/golden_replay_capture.gd`、`client/tools/rng_audit.gd`、`client/tools/perf_probe.gd`、`client/tests/replays/`、基础平衡采样、必要时 `tools/godot_bridge.py` | 既有 Stage 1 + `headless-boot`、`runtime-smoke`、`settings-smoke`、`save-smoke`；F8 追加 `python tools/godot_bridge.py --project client l1-smoke`、`replay-smoke`、`replay-runner`、`replay-runner --rerun-runtime-summary`、`replay-input-smoke`、`capture-golden-replay`、`capture-golden-replay --golden-scenario golden_pause_resume`、`capture-golden-replay --golden-scenario golden_full_death`、`capture-golden-replay --golden-scenario golden_level_up_choice`、`rng-audit` 和四条 checked-in replay 的 `replay-runner --replay-file ... --rerun-runtime-summary`；帧样本字段变化需重录 golden，RNG seed 派生 / 子流变化需先跑 `rng-audit` 再评估 golden；`perf-probe` 仅在用户明确要求时运行；文档变化跑 `python tools/docs_health_check.py` |
| 写/改 F9 内容扩展 / Demo 打磨 | `docs/AI协作/工作包/F9-ContentDemoPolish.md`、`docs/AI导航.md` 第 4 节、`client/data/README.md`、`client/locale/README.md`、目标数据文件 | `docs/测试策略.md`、`docs/代码/gameplay_runtime.md`、`docs/词表与契约.md` 相关章节、必要时目标源码、F8 golden replay / 按需性能入口 | `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/lint_project_rules.py`、相关 smoke、四条 checked-in replay runner；性能 probe 仅在用户明确要求时运行；文档变化跑 `python tools/docs_health_check.py` |
| 写/改 F11 装备 Mod / 局外装配 | `docs/AI协作/工作包/F11-GearModLoadout.md`、`docs/代码/gear_mod_system.md`、GDD §7.2 / §9.16、`client/data/README.md`、`docs/测试策略.md` | `GearModSystem`、`gear_mod_smoke.gd`、Gear Mod UI、Gear Mod HUD 暂存提示、`gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv`、SaveManager meta payload、locale、词表、AI导航 | 数据 / 契约变化跑 `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`；运行时变化跑 `python tools/godot_bridge.py --project client gear-mod-smoke`；改击杀归因或开局应用追加 `runtime-smoke`；改 SaveManager envelope 追加 `save-smoke`，影响稳定行为时评估 golden |
| 写/改代码模块 | `docs/代码文档规范.md`、对应 `docs/代码/<module_id>.md`、目标源码；触碰 `.gd` 时遵循 [Godot 4.7 官方 GDScript style guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html)；测试相关时读 `docs/测试策略.md` 相关段；大型代码改动 review 读 `docs/AI协作/代码审核流程.md` | 代码、模块文档、AI导航依赖图、必要时 GDD / ADR | 对应测试义务 + `pre-commit run --all-files` 或等价 lint/test/docs 命令 + `python tools/docs_health_check.py` |
| 写/改测试 | `docs/测试策略.md`、对应模块文档 | 测试文件、测试策略、必要时 CI 规划 | 对应测试命令；`python tools/docs_health_check.py` |
| 加 GM 指令 / 调试工具 | `docs/游戏设计文档.md` §9.20、`docs/代码/debug_tools.md`、`docs/代码/input_service.md`、`docs/词表与契约.md` §7、`docs/测试策略.md` §5.10 | debug context / action、DebugConsole / GM registry、导出 preset、AI导航、测试策略 | debug-tools / debug-tools-release smoke、input-smoke、contracts、docs health；命令影响战斗时追加 runtime-smoke |
| 更新 AI 工具入口 | `AGENTS.md`、`docs/AI协作/工具适配指南.md`、`docs/AI协作/角色分工.md` | `CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、`.codebuddy/`、`.codex/`、`.opencode/`、`.claude/` | `python tools/docs_health_check.py`；改 `.opencode/` 后验证 JSON |
| 运行 Windows / PowerShell 命令 | `AGENTS.md`、当前平台规则第 29 节、`docs/AI协作/工具适配指南.md` 的「Windows PowerShell 稳定执行」 | PowerShell 命令、`rg` pattern / 参数顺序、cmdlet `-LiteralPath`、原生 `$LASTEXITCODE`、并行 / fail-fast 调度边界 | 实测 `rg` 有匹配 / 无匹配 / 语法错误、`git diff --no-index` 相同 / 有差异 / 缺失输入拒绝、中文路径读取；文档变化跑 `python tools/docs_health_check.py` |
| 健康检查 / CI | `docs/AI协作/文档健康检查.md`、`docs/CICD规划.md`、`docs/AI协作/实时验证回路.md`、`docs/AI协作/代码审核流程.md` | `.pre-commit-config.yaml`、`tools/docs_health_check.py`、`tools/validate_data.py`、`tools/test_data_loader_schema.py`、`tools/lint_gdscript_rules.py`、`tools/lint_project_rules.py`、`tools/lint_semantic_rules.py`、`tools/check_staged_whitespace.py`、`tools/sync_contracts.py`、健康检查命令、CI / pre-commit 规划 | `pre-commit run --all-files`；无 pre-commit 时等价跑 `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/lint_gdscript_rules.py`、`python tools/lint_project_rules.py`、`python tools/test_project_rules_lint.py`、`python tools/lint_semantic_rules.py`、`python tools/test_semantic_rules_lint.py`、`python tools/docs_health_check.py`、`python -m json.tool docs/_kb_index.json` |
| 评估 / 安装 AI skills / MCP / agent-harness 资源 | `docs/AI协作/AI技能资源评估.md`、`docs/AI协作/上下文预算.md`、`CODEX.md`、`OPENCODE.md`、`.opencode/opencode.json`；ECC 类大仓追加 `docs/AI协作/ECC工具吸收清单.md` | `.codebuddy/skills/`、`.codex/skills/`、`.opencode/skills/`、`.opencode/opencode.json`、工具适配指南、AI导航、AI记忆、CREDITS、来源专属吸收清单 | `python -m json.tool .opencode/opencode.json`、`python tools/docs_health_check.py`、`git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`；新增或吸收资源时确认三平台同步、不重复、不引入外部 hooks / plugin / vendor reference 层，并运行 `ai-resource-curator` 的 AI surface audit |
| 调整 AI 开工 / 上下文预算 | `docs/AI协作/快速开工.md`、`AGENTS.md`、平台入口、`docs/AI协作/上下文预算.md`、`docs/AI协作/文档维护指南.md` | `CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、三平台规则、AI导航、工具适配指南、知识库索引、AI记忆 | `python -m json.tool docs/_kb_index.json`、`python -m json.tool docs/AI记忆/current_state.json`、`python tools/docs_health_check.py`、`git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"` |
| 新增 / 维护阶段工作包 | `docs/AI协作/工作包/<阶段>.md`、`docs/AI协作/上下文预算.md`、目标模块文档 | AI协作 README、AI导航、知识库索引、current_state、会话日志 | `python tools/docs_health_check.py`、`python -m json.tool docs/_kb_index.json` |

## 5. ADR 追踪矩阵

| ADR 范围 | 主题 | 主要同步文件 |
|----------|------|--------------|
| #1~#12 | 基础玩法初始定位、数据驱动、AI 友好工程 | GDD、规则、AI导航、README |
| #13~#19 | 暂停、仓库结构、记忆、回放、协作工程 | GDD、测试策略、AI记忆、AI协作 |
| #20~#28 | RNG、GameState、PoolManager、UIManager、Combat、Save、Clock、Audio、Contracts | GDD、词表、规则、测试策略、代码模块文档 |
| #29 | 测试金字塔 | `docs/测试策略.md`、规则、CI 规划 |
| #30~#33 | agents / commands / 多平台入口 | AGENTS、CLAUDE、CODEX、OPENCODE、`.codebuddy/`、`.codex/`、`.opencode/`、工具适配指南 |
| #34 | 扩展优先 / 破限能力 | GDD、词表、规则、AI导航、测试策略 |
| #35 / #40 | 代码文档同步 / 详细模块文档 | `docs/代码文档规范.md`、`docs/代码/`、规则、AI导航 |
| #36 | 默认中文沟通 | AGENTS、平台规则、工具适配指南 |
| #37 | `draft/` 禁区 | AGENTS、平台规则、README、AI导航、上下文预算 |
| #38 | MVP 隔离实验区（历史决策，目录已在验证完成后移除） | 规则、AI导航、项目记忆 |
| #39 | 手柄支持 | GDD、词表、规则、测试策略、AI导航 |
| #41~#42 | AI 知识库、索引 schema、健康检查和任务路由 | `docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/AI协作/文档健康检查.md`、`tools/docs_health_check.py`、三平台 `/health-check` 命令 |
| #43 | 经验与升级选择系统；ADR #120 后默认模式暂不启用，保留为未来非默认模式能力 | GDD §7.1、测试策略、AI导航、术语表、修改建议 E |
| #44 | AI 记忆三层结构 | `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`、`docs/AI记忆/README.md`、`tools/docs_health_check.py` |
| #45 | 完整项目数值 / 文案配置手册 | `client/data/README.md`、`client/locale/README.md`、GDD §9.3 / §9.4、词表、AI导航、任务模板 |
| #46 | 深局外成长历史决策；当前已由 #115/#117/#118 改为装备 Mod 路线并删除旧数据 / 迁移 | GDD §7.2、ADR #115 / #117 / #118、测试策略、AI导航 |
| #47 | 最小 Stage 1 CI | `.github/workflows/docs-check.yml`、`docs/CICD规划.md`、`docs/AI协作/实时验证回路.md`、`CONTRIBUTING.md`、AI记忆 |
| #48 | 强玩家存档 / 暂停退出续局 | GDD §9.16、词表 §14、测试策略、AI导航、TODO、`docs/代码/save_manager.md` |
| #49 | 创意 / 策略 subagents | `AGENTS.md`、`.codebuddy/agents/`、`.codex/agents/`、`.opencode/agents/`、`docs/AI协作/README.md`、`docs/AI协作/角色分工.md`、工具适配指南 |
| #50 | 沟通审查不过度优化 / 需求前置评估 | AGENTS、CODEX、OPENCODE、平台规则、AI导航、工具适配指南、AI记忆 |
| #51 | 数据校验 / 契约同步 / 轻量 Godot Bridge | `tools/sync_contracts.py`、`tools/validate_data.py`、`tools/godot_bridge.py`、CI、AI协作、数据/locale 手册、AI导航 |
| #52 | AI Git 提交策略 | AGENTS、CODEX、OPENCODE、三平台规则、三平台命令、CONTRIBUTING、AI导航、工具适配指南、AI记忆 |
| #53 | 项目级 skills / AI 资源评估 | `.opencode/skills/`、`.opencode/opencode.json`、OPENCODE、AGENTS、工具适配指南、AI协作 README、`docs/AI协作/AI技能资源评估.md`、AI记忆；已由 #60 扩展为三平台同步 |
| #54 | 上下文压缩后的任务恢复 | AGENTS、CODEX、OPENCODE、三平台规则、AI导航、工具适配指南、AI记忆 |
| #55 | 外部 AI 资源整包隔离安装（历史安装口径，已由 #59 / #60 取代） | 历史 vendor 与 `.gitmodules` 已删除；当前以 #59 的 vendor 删除和 #60 的三平台 skills 同步口径为准 |
| #56 | 外部 AI 工具正式安装但排除模板（历史安装口径，已由 #58 / #59 / #60 取代） | 历史涉及的外部活跃工具文件已删除；当前以 #59 的 vendor 删除和 #60 的三平台 skills 同步口径为准 |
| #57 | CCGS 跨 agent 复用适配层（历史安装口径，已由 #58 / #59 / #60 取代） | 历史适配层已删除；当前以 #59 的 vendor 删除和 #60 的三平台 skills 同步口径为准 |
| #58 | 外部 AI 三库活跃层收敛为 `game-ai-reference`（历史口径，已由 #59 / #60 取代） | 历史 reference 层与 vendor 来源已删除；当前以 #59 的 vendor 删除和 #60 的三平台 skills 同步口径为准 |
| #59 | 项目级 skills 删除 vendor/reference 层 | `.opencode/skills/`、`.opencode/opencode.json`、AGENTS、CLAUDE、CODEX、OPENCODE、三平台规则、AI技能资源评估、AI协作 README、AI导航、工具适配指南、AI记忆、`.gitmodules`；已由 #60 扩展为三平台同步 |
| #60 | 项目级 skills 三平台同步安装 | `.codebuddy/skills/`、`.codex/skills/`、`.opencode/skills/`、AGENTS、CLAUDE、CODEX、OPENCODE、三平台规则、AI技能资源评估、AI协作 README、AI导航、工具适配指南、AI记忆 |
| #61 | GM 指令与调试工具构建隔离 | GDD 9.20、词表 action、测试策略、AI导航、AI记忆 |
| #62 | 正式项目阶段工作规划 | `docs/正式项目工作规划.md`、`docs/TODO.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` |
| #63 | 数值配置格式分流 | `client/data/README.md`、`docs/游戏设计文档.md`、三平台规则、`AGENTS.md`、`docs/AI导航.md`、`docs/正式项目工作规划.md`、`docs/_kb_index.json`、AI记忆 |
| #64 | 中英文首批本地化与 AI 自动翻译 | `client/locale/README.md`、GDD §9.4、词表 §6、三平台规则、locale 任务模板、data-author / copywriter-packager agents、AI导航、AI记忆 |
| #65 | 多模式资源复用原则 | GDD §6.6、`client/data/README.md`、三平台规则、AI导航、AI记忆、`game_modes.json` / DataLoader schema |
| #66 | 未来多人 PvE / PvP 预留边界 | GDD §6.7、`client/data/README.md`、三平台规则、AI导航、AI记忆；后续输入 / Combat / Replay / SaveManager 模块文档 |
| #67 | 快速开工 + 按需读取上下文分层 | AGENTS、CLAUDE、CODEX、OPENCODE、三平台规则、`docs/AI协作/快速开工.md`、上下文预算、AI导航、工具适配指南、AI记忆、知识库索引 |
| #68 | 阶段工作包 / 规则去重 / 模块文档优先 | `docs/AI协作/工作包/`、README、CONTRIBUTING、工具适配指南、快速开工、上下文预算、AI导航、AI记忆、知识库索引 |
| #69 | 大型代码改动提交前自动事实 review | AGENTS、CLAUDE、CODEX、OPENCODE、三平台规则、角色分工、工具适配指南、AI技能资源评估、README、CONTRIBUTING、AI导航、AI记忆、`docs/AI协作/代码审核流程.md` |
| #70 | DataLoader schema 回归测试进入 Stage 1 CI | `tools/test_data_loader_schema.py`、`.github/workflows/docs-check.yml`、`docs/CICD规划.md`、`docs/AI协作/实时验证回路.md`、`docs/测试策略.md`、`docs/代码/data_loader.md`、F3 工作包、AI导航、AI记忆 |
| #71 | 双致谢清单 / 游戏内 Credits 数据源 | `CREDITS.md`、`client/data/credits.json`、`client/data/README.md`、`client/locale/strings.csv`、`docs/代码/data_loader.md`、AI导航、AI记忆 |
| #72 | ECC 外部 agent-harness 资源吸收边界 | `docs/AI协作/AI技能资源评估.md`、三平台 `ai-resource-curator` skill、CLAUDE、CODEX、OPENCODE、AI导航、AI协作 README、CREDITS、AI记忆 |
| #73 | ECC README 与全工具面吸收清单 | `docs/AI协作/ECC工具吸收清单.md`、`docs/AI协作/AI技能资源评估.md`、三平台 `ai-resource-curator` skill、上下文预算、AI导航、知识库索引、AI记忆 |
| #74 | Godot 官方 GDScript style guide 成为项目代码风格基线 | 三平台规则、三平台 `godot-gdscript` skill、AI导航、代码文档规范、CREDITS、AI记忆 |
| #75 | MVP 隔离目录移除 | README、GDD、AI导航、知识库索引、三平台规则 / skills / commands、工具脚本、AI记忆 |
| #76 | 第一档 GDScript 项目 lint 进入 Stage 1 CI | `tools/lint_gdscript_rules.py`、`.github/workflows/docs-check.yml`、三平台规则 / commands、CICD规划、测试策略、实时验证回路、AI导航、AI记忆 |
| #77 | 第二档项目规则 lint 进入 Stage 1 CI | `tools/lint_project_rules.py`、`tools/test_project_rules_lint.py`、`.github/workflows/docs-check.yml`、三平台规则 / commands、CICD规划、测试策略、实时验证回路、AI导航、AI记忆 |
| #78 | 第三档语义 advisory lint 进入 Stage 1 CI | `tools/lint_semantic_rules.py`、`tools/test_semantic_rules_lint.py`、`.github/workflows/docs-check.yml`、三平台规则 / commands、CICD规划、测试策略、实时验证回路、AI导航、AI记忆 |
| #79 | 本地 pre-commit 与工具先行代码审核流程 | `.pre-commit-config.yaml`、`tools/check_staged_whitespace.py`、`docs/AI协作/代码审核流程.md`、三平台 `code-review-factual` skill、三平台规则 / commands、CICD规划、实时验证回路、文档健康检查、CONTRIBUTING、AI导航、AI记忆 |
| #80 | F5 run 存档 version 2 + SaveManager smoke | `client/scripts/autoload/save_manager.gd`、`client/tools/save_manager_smoke.gd`、`tools/godot_bridge.py`、`docs/代码/save_manager.md`、`docs/代码/gameplay_runtime.md`、`docs/测试策略.md`、AI导航、AI记忆 |
| #81 | F8 回放确定性基线：稳定 RNG 子流 seed + 升级选择 golden | `client/scripts/autoload/rng.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`client/tools/golden_replay_capture.gd`、`client/tools/replay_runner.gd`、`tools/godot_bridge.py`、`client/tests/replays/`、`docs/代码/rng.md`、`docs/代码/replay.md`、`docs/代码/gameplay_runtime.md`、测试策略、AI导航、AI记忆 |
| #82 | 默认鼠标瞄准 + 左右朝向 | `client/scripts/gameplay/player.gd`、`client/scripts/gameplay/enemy.gd`、`client/scripts/gameplay/weapon_system.gd`、`client/data/characters.json`、`client/data/weapons.json`、`client/locale/strings.csv`、GDD、词表、规则、Gameplay Runtime / Replay / Settings 文档、测试策略、AI导航、AI记忆 |
| #83 | 本地数据包式 Mod 接口 | `client/scripts/autoload/mod_loader.gd`、`client/scripts/autoload/data_loader.gd`、`client/project.godot`、`client/tools/l1_smoke.gd`、`docs/代码/mod_loader.md`、`docs/代码/data_loader.md`、GDD §9.21、数据手册、测试策略、三平台规则、AI导航、AI记忆 |
| #84 | Steam 优先的平台服务接口 | `client/scripts/autoload/platform_services.gd`、`client/project.godot`、`client/scripts/boot/formal_client_boot.gd`、`client/tools/l1_smoke.gd`、`docs/代码/platform_services.md`、GDD §9.22、测试策略、三平台规则、AI导航、AI记忆 |
| #85 | Godot 4.7 引擎基线迁移 | `client/project.godot`、README / client README、GDD、三平台规则、三平台 `godot-gdscript` / `godot-scene-validation` skills、AI导航、代码文档规范、CICD规划、AI技能资源评估、AI记忆 |
| #86 | RNG 子流 SHA-256 mixer 与相关性审计 | `client/scripts/autoload/rng.gd`、`client/tools/rng_audit.gd`、`client/scripts/boot/formal_client_boot.gd`、`tools/godot_bridge.py`、`docs/代码/rng.md`、GDD §9.18.1、测试策略、CICD规划、F8 工作包、AI导航、AI记忆 |
| #87 | Claude Code 平台原生 `.claude/` 配置 | `.claude/agents/`、`.claude/commands/`、`.claude/skills/`、`.claude/rules/game-coding-rules.md`、`.claude/settings.json`、`CLAUDE.md`、四平台 `game-coding-rules.md`、工具适配指南、AI技能资源评估、AI导航、AGENTS.md、AI记忆 |
| #88 | 《破巢者》IP 方向；跨宇宙通道、银河系星际文明残局、首都星域反击与敌巢突入包装 | `docs/IP设定.md`、GDD §1.2、术语表、AI导航、AI记忆 |
| #89 | 数据驱动生态 EnemyAI；profile + Utility/FSM/Steering 分工、怪物互相狩猎 / 逃跑和非玩家击杀归因 | `docs/代码/enemy_ai.md`、`client/data/enemy_ai_profiles.json`、`client/data/enemies.csv`、`client/scripts/gameplay/enemy.gd`、GDD §5.3、词表 §12-B、测试策略、AI导航、AI记忆 |
| #90 | 可复用主动技能系统；技能定义与英雄解耦、可扩展资源池、targeting/effect primitive 和旋风斩首片 | `docs/代码/skill_system.md`、`client/data/skills.json`、`client/data/characters.json`、`client/data/game_modes.json`、`client/scripts/gameplay/skill_system.gd`、GDD §6.1-A、词表 §12-C~12-F、测试策略、AI导航、AI记忆 |
| #91 | 多语言 UI 英文长度基准；玩家可见 UI 文案和布局以英文 `en` 长度验收，按钮类控件由 `settings-smoke` 覆盖 | `client/locale/README.md`、GDD §9.4 / §9.14、测试策略、四平台规则、AI导航、AI记忆 |
| #92 | 详细数值面板；`show_stats_panel` action 默认 Tab，按住显示、松开隐藏，不暂停 | `docs/代码/gameplay_runtime.md`、`docs/代码/settings.md`、词表 §5 / §7、`client/scenes/gameplay/gameplay_hud.tscn`、`client/scripts/gameplay/gameplay_hud.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、测试策略、AI导航、AI记忆 |
| #93 | 有限地图 + 可人工调参 PCG；`map_layouts.json` 声明 bounds、出生点、安全半径、刷怪边距、PCG 机关和人工摆点，`MapManager` / `HazardSystem` 保存并恢复 FEA-12 等机关 | `docs/代码/map_manager.md`、`docs/代码/hazard_system.md`、`client/data/map_layouts.json`、`client/data/hazards.csv`、`client/scripts/gameplay/map_manager.gd`、`client/scripts/gameplay/hazard.gd`、GDD §5 / §9.16、测试策略、AI导航、AI记忆；地图格量化历史由 #105 引入，当前由 #125 修正为矩形格 |
| #94 | 项目版轻量 GAS 首片；`skills.json` 增加 ability tags 和 activation tag gating，SkillSystem 保存 owned tag 计数并保留现有主技能 API | `docs/代码/skill_system.md`、`client/data/skills.json`、`client/scripts/gameplay/skill_system.gd`、`client/scripts/autoload/data_loader.gd`、`tools/validate_data.py`、词表 §12-G、GDD §6.1-A、测试策略、AI导航、AI记忆 |
| #95 | 状态效果首片接入轻量 GAS；`StatusEffect` / `StatusEffectComponent` 管理状态叠加、ability tag 生命周期和 SkillSystem 状态快照，`skill_effect_apply_status` 支撑沉默 | `docs/代码/status_effect_component.md`、`docs/代码/skill_system.md`、`client/scripts/combat/status_effect.gd`、`client/scripts/combat/status_effect_component.gd`、`client/scripts/gameplay/skill_system.gd`、`client/tools/l1_smoke.gd`、词表 §9-A~§9-B / §12-F、GDD §9.15.2、测试策略、AI导航、AI记忆 |
| #96 | Player / Enemy 正式接入 StatusEffectComponent；实体暴露 `apply_status_effect()` 与 owned ability tag 查询，run 快照保存状态效果并在对象池复用时清理 | `client/scripts/gameplay/player.gd`、`client/scripts/gameplay/enemy.gd`、`client/tools/l1_smoke.gd`、`docs/代码/status_effect_component.md`、`docs/代码/gameplay_runtime.md`、`docs/代码/enemy_ai.md`、GDD §6.1-A / §9.15.2、测试策略、AI导航、AI记忆 |
| #97 | burn 首个真实 DoT 状态；StatusEffect 保存 `damage_type` / `tick_remaining` / 队伍归因，StatusEffectComponent 按 GameClock tick 并经 Combat 结算 `fire + is_dot` | `client/scripts/combat/status_effect.gd`、`client/scripts/combat/status_effect_component.gd`、`client/scripts/gameplay/player.gd`、`client/scripts/gameplay/enemy.gd`、`client/scripts/autoload/data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py`、`client/tools/l1_smoke.gd`、`docs/代码/status_effect_component.md`、`docs/代码/skill_system.md`、`docs/代码/combat.md`、GDD §9.15.2、测试策略、AI导航、AI记忆 |
| #98 | 类型定位改为刷宝动作生存；参考星际战甲 / 暗黑的装备、词条、长期养成与刷战利品循环（当前视角已由 #124 改回俯视角 2D；地图格 / 机关度量由 #125 修正为矩形俯视格） | README、GDD、IP设定、术语表、AI导航、CICD规划、功能建议池、AI记忆、平台规则 / skills |
| #99 | 历史：玩家 2.5D 视觉层首片；`Player3DVisual` 用 SubViewport 渲染低模 3D 胶囊并贴回 2D 世界。当前已由 #124 删除正式玩家 3D 正交视觉层 | 历史记录；当前实现看 ADR #124、Gameplay runtime 文档、`client/scenes/gameplay/player.tscn`、`client/scripts/gameplay/player.gd`、`client/tools/runtime_smoke.gd` |
| #100 | 历史：当前正式视角曾改为固定斜俯视 2.5D；当前已由 #124 改回俯视角 2D | 历史记录；当前口径看 README、GDD、IP设定、术语表、AI导航、Gameplay runtime 文档、AI记忆、平台规则 |
| #101 | 历史：修正固定斜俯视相机实现为不滚转屏幕；当前仍保留 `CenteredCamera` 水平、居中、等比缩放，但不再配合 3D 正交视觉层 | README、GDD、术语表、AI导航、Gameplay runtime 文档、`client/scripts/gameplay/player.gd`、`client/tools/runtime_smoke.gd`、AI记忆 |
| #102 | 历史：固定斜俯视显示曾改为等比屏幕尺度；当前由 #124 规定为俯视角 2D，仍禁止旋转 / 非等比缩放相机 | README、GDD、规则入口、术语表、AI导航、Gameplay runtime 文档、`client/scripts/gameplay/player.gd`、`client/tools/runtime_smoke.gd`、AI记忆 |
| #103 | 历史：通用机关曾使用菱形危险地块；当前已由 #125 修正为矩形危险地块，`Hazard` 占位表现和触发判定均按矩形俯视 footprint | GDD、`client/data/README.md`、AI导航、Gameplay runtime 文档、HazardSystem 文档、`client/scripts/gameplay/hazard.gd`、AI记忆 |
| #104 | 历史：固定斜俯视资产处理规则；当前已由 #124 / #125 改为俯视资产落地规则，地面范围默认使用矩形 / 方形俯视格，正式资源 brief 字段仍保留 | GDD §8.2-A、AI导航、F9 工作包、Gameplay runtime 文档、术语表、AI记忆 |
| #105 | 历史：地图曾采用量化菱形格度量；当前已由 #125 修正为量化矩形格，`map_layouts.json.grid.cell_width/cell_height` 表示水平 / 垂直格宽高 | GDD §5 / §8.2-A、`client/data/README.md`、MapManager / HazardSystem / Gameplay runtime 文档、`client/scripts/gameplay/map_manager.gd`、`client/scripts/gameplay/hazard.gd`、`client/scripts/gameplay/world_background.gd`、AI记忆 |
| #106 | 机关锚点按 `radius_tiles` 奇偶吸附；当前矩形格口径下奇数尺寸中心落在矩形格心，偶数尺寸中心落在网格顶点，人工摆点和 PCG 共用同一规则 | GDD §5、`client/data/README.md`、MapManager / HazardSystem 文档、`client/scripts/gameplay/map_manager.gd`、`client/scripts/autoload/data_loader.gd`、`tools/validate_data.py`、`client/tools/runtime_smoke.gd`、AI记忆 |
| #107 | 历史：玩家出生安全区可见标记曾改为贴格菱形；当前已由 #125 修正为贴矩形格的出生安全矩形，`safe_radius` 仍是 PCG 避让距离下限 | GDD §5、`client/data/README.md`、MapManager 文档、`client/scripts/gameplay/map_manager.gd`、`client/tools/runtime_smoke.gd`、AI记忆 |
| #108 | subagent 默认主动调度授权；复杂、专业或可并行任务可直接启用对应项目 subagent，不支持原生调度时读取同名 agent `.md` 作为 prompt 模板 | `AGENTS.md`、`CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、四平台规则入口、`.codebuddy/agents/`、`.codex/agents/`、`.opencode/agents/`、`.claude/agents/`、工具适配指南、AI协作 README、AI导航、AI记忆 |
| #109 | 核心玩法改为射击刷宝生存；默认武器按住 `fire` action（左键 / 右扳机）持续射击，技能首批内容服务射击强化，默认移除旋风斩 / 点燃斩 / 燃烧法术包装；当前视角口径由 #124 改回俯视角 2D | GDD、词表、DataLoader schema、`WeaponSystem`、`SkillSystem`、数据手册、locale、Gameplay Runtime、SkillSystem 文档、AI导航、AI记忆 |
| #110 | AI 协作需求不明先问；需求、术语、验收标准、授权边界或上下文无法可靠确认时先澄清，不自行脑补高风险假设 | `AGENTS.md`、`CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、四平台规则入口、快速开工、AI协作 README、工具适配指南、AI导航、AI记忆 |
| #111 | 《破巢者》IP 美术风格采用钙化活体建筑 + 阵营色隔离；敌巢 / 虫族使用骨白、蜡黄、干肉粉、深红、黑紫和少量毒蓝，玩家和玩家子弹默认避开青 / 红 / 白，敌方远程攻击可用红色，宝箱与地图兴趣点按功能色区分 | `docs/IP美术风格.md`、IP设定、GDD §8、术语表、AI导航、AI记忆 |
| #112 | 敌巢战区导演首片；历史首片曾用固定 phase / mutation / encounter / interest point 组织 wave，当前 encounter 部分已被 ADR #144 废止；仍只按时间 gating 刷怪，不读玩家状态、不做隐藏动态难度、不接运行时 LLM | F10 工作包、`docs/代码/warzone_director.md`、`client/data/warzone_directors.json`、Gameplay Runtime、DataLoader schema、GDD §7.3、AI导航、AI记忆 |
| #113 | F10 兴趣点接入 MapManager 初始机关生成；`WarzoneDirector` 过滤当前 layout 的 interest points，`MapManager` 用通用 PCG / 锚点规则生成 `source=director` hazards；不读玩家状态、不按 id 特判、不提升 run schema；当前锚点网格由 #125 修正为矩形格 | F10 工作包、`docs/代码/warzone_director.md`、`docs/代码/map_manager.md`、Gameplay Runtime、DataLoader schema、`client/data/README.md`、GDD §7.3、AI导航、AI记忆 |
| #114 | 普通新局 / 重开生成新的 run seed；继续游戏恢复 run snapshot，replay / smoke / golden 工具保持固定 seed | `client/scripts/autoload/rng.gd`、`client/scripts/boot/formal_client_boot.gd`、`client/tools/l1_smoke.gd`、RNG / FormalClientBoot / Gameplay Runtime 文档、GDD §9.18.1、AI导航、AI记忆 |
| #115 | 跨局成长改为参考《星际战甲》的装备 Mod 系统，玩家配置英雄 / 武器两套 Mod；旧 `MetaProgressionSystem` 不再作为未来下一局属性来源 | GDD §7.2 / §9.16、F11 工作包、`docs/代码/gear_mod_system.md`、`client/data/README.md`、测试策略、AI导航、AI记忆 |
| #116 | 历史决策：旧 `purchased_upgrades` 曾计划按历史花费补偿为 `gear_mod_dust`；已由 #118 取消 | ADR #118、F11 工作包、GDD §7.2 / §9.16、AI导航、AI记忆 |
| #117 | 旧局外成长运行时退役；删除旧 autoload / UI / 死亡结算 / `meta-smoke` | `docs/代码/gear_mod_system.md`、`docs/代码/save_manager.md`、F11 工作包、GDD §7.2 / §9.16、测试策略、AI导航、AI记忆 |
| #118 | 旧局外成长测试档不再迁移；删除旧 `meta_progression.json`、旧 meta 契约常量、旧文案、旧 `purchased_upgrades` 补偿逻辑和相关 schema / smoke 覆盖 | `docs/代码/gear_mod_system.md`、`docs/代码/save_manager.md`、F11 工作包、GDD §7.2 / §9.16、测试策略、AI导航、AI记忆 |
| #119 | 本地 staged whitespace hook 自动修复 EOF 多空行后再检查；其他 whitespace 错误仍失败 | `.pre-commit-config.yaml`、`tools/check_staged_whitespace.py`、实时验证回路、CICD规划、测试策略、文档健康检查、AI记忆 |
| #120 | 默认标准模式改为 8-12 分钟短刷图循环，局内经验升级 3 选 1 暂不在默认模式启用 | F12 工作包、GDD、AI导航、Gameplay Runtime 文档、Data README、测试策略、current_state、AI记忆 |
| #121 | AI 上下文预算新增 S / M / L / XL 任务复杂度分级，先判流程深度再按任务类型读取文件 | `docs/AI协作/上下文预算.md`、AI协作 README、AI导航、决策记录、AI记忆、current_state |
| #122 | 默认短刷图战利品采用暂存后结算：本局 Gear Mod / dust 先进入 `run.pending_loot`，完成小巢核或未来撤离成功才写入 `meta.gear_mods`，死亡 / 放弃丢失 | F12 工作包、GDD、Gameplay Runtime 文档、SaveManager / GearModSystem 边界、测试策略、current_state、AI记忆 |
| #123 | 默认短刷图小巢核击破后开启贴格撤离区，玩家完成撤离读条后才提交 `run.pending_loot`、删除 `run` 并显示完成面板 | F12 工作包、GDD、Gameplay Runtime 文档、WarzoneDirector / MapManager 文档、测试策略、current_state、AI记忆 |
| #124 | 当前正式视角改回俯视角 2D；删除正式玩家场景的 `Player3DVisual` / `SubViewport + Camera3D` 正交视觉层，玩家由 `Player._draw()` 按完整 `aim_direction` 绘制方向标记；地图格 / 机关口径随后由 #125 修正为矩形俯视格 | README、GDD、IP设定、IP美术风格、术语表、AI导航、Gameplay Runtime 文档、四平台规则入口、`client/scenes/gameplay/player.tscn`、`client/scripts/gameplay/player.gd`、`client/tools/runtime_smoke.gd`、current_state、AI记忆 |
| #125 | 俯视角地面语言改为矩形 / 方形 2D 网格；`map_layouts.json.grid.cell_width/cell_height` 表示水平 / 垂直格宽高，`MapManager` 使用矩形边界、矩形出生安全区和矩形 clamp，`Hazard` / POI target / cache / extraction 都用矩形俯视 footprint | GDD、AI导航、术语表、IP美术风格、F9 / F12 工作包、MapManager / HazardSystem / Gameplay Runtime / WarzoneDirector 文档、Data README、测试策略、四平台规则入口、current_state、AI记忆 |
| #126 | 敌人 AI 新增通用远程攻击 action；`enemy_ai_profiles.json.movement.ranged_*` 配置距离、冷却和投射物参数，默认短刷图 5:00 引入 `enemy_spitter` 喷棘者，敌弹复用池化子弹并通过 `Combat.apply_damage()` 伤害玩家 | GDD、AI导航、AI记忆、Gameplay Runtime / EnemyAI 文档、Data README、词表与契约、`client/data/enemy_ai_profiles.json`、`client/data/enemies.csv`、`client/data/spawn_waves.csv`、`client/scripts/gameplay/enemy.gd`、`client/scripts/gameplay/bullet.gd`、`client/tools/runtime_smoke.gd` |
| #127 | 默认短刷图下一阶段转向手工房间串联；每个房间用 Godot `.tscn` + marker 手工制作，首片只做线性房间序列、清房开门和进入下一房间，暂不自研完整关卡编辑器 UI | F13 工作包、GDD、AI导航、测试策略、正式项目工作规划、TODO、current_state、AI记忆；实现后追加 RoomManager / Gameplay Runtime / MapManager / SaveManager 文档和房间数据手册 |
| #128 | F13 手工房间制短刷图首片运行时落地；`RoomManager`（Node2D，房间 carrier 下由 `GameplayRunLoop` 在 `ActiveWorld` 创建 / 驱动）、`rooms.json` / `room_sequences.json`、`RoomRoot` + 四类房间 marker、两个演示房间 `.tscn`、词表 §15-A/B/C 门 / 清房契约、run payload v2→v3 + 迁移、`room-switch-smoke`；房间 carrier 首片 opt-in，默认 open-warzone 不变；四条黄金回放因 data_fingerprint 变化重录、行为 summary 未变 | `docs/代码/room_manager.md`、F13 工作包、Gameplay Runtime / MapManager / SaveManager 文档、词表、`client/data/README.md`、GDD、AI导航、测试策略、引擎集成、AI记忆 |
| #129 | Steamworks Slime Lab 使用专属 App ID `4955670`，收口初始化 / runtime App ID / Lobby 协议校验与失败后的 offline 退化；Lab 仍是独立应用，不代表正式 `client/PlatformServices` provider 已接入 | `output/steamworks_lab/README.md`、`project.godot`、`steam_appid.txt`、`scripts/transport_adapter.gd`、`scripts/network_session.gd`、`tests/steam_config_smoke.gd`、AI导航、测试策略、AI记忆 |
| #130 | Windows / PowerShell 环境统一稳定执行：字面搜索优先 `rg -F`，`rg` 选项置于 `--` 前，路径走 `-LiteralPath`，cmdlet / 原生错误分开处理，合法非零退出码先归一化再并行；采用规则 + 模板，不新增包装器 | `AGENTS.md`、四平台规则 / 入口、`docs/AI协作/工具适配指南.md`、`docs/AI协作/快速开工.md`、AI导航、AI记忆 |
| #131 | 正式客户端当前只适配固定 16:9 分辨率；默认逻辑画布 1920×1080，非 16:9 屏幕等比加黑边，不拉伸 / 裁切 / 扩大玩法视野；其他比例作为未来按独立固定预设接入的 P3 优化 | GDD §9.5-A、`client/README.md`、FormalClientBoot / Gameplay Runtime 文档、测试策略、TODO、AI导航、current_state、AI记忆 |
| #132 | Steamworks Slime Lab Windows 工具链锁定 Godot 4.7 + GodotSteam 4.20 + Steamworks SDK 1.64 官方 module editor / templates；二进制本地安装，仓库跟踪版本锁、SHA-256、setup / verify / export-release 与 Windows preset；SteamPipe / Depot / 双账号验证仍属外部步骤 | `output/steamworks_lab/README.md`、`steam_toolchain.lock.json`、`tools/steamworks_lab_toolchain.py`、测试策略、AI导航、current_state、AI记忆 |
| #133 | Steamworks Slime Lab 废止 #132 的 module 选型，改用 GodotSteam 4.20 官方 GDExtension；4.20 插件已包含 `SteamMultiplayerPeer`，普通 Godot 4.7 + 标准 templates 即可开发 / 导出，setup 负责插件安装和 Steam 商店版 Godot 的同名 DLL 冲突隔离 | `output/steamworks_lab/README.md`、`steam_toolchain.lock.json`、`tools/steamworks_lab_toolchain.py`、测试策略、AI导航、current_state、AI记忆 |
| #134 | Steamworks Slime Lab 停止创建 `.toolchain/`；setup 在系统临时目录处理锁定插件，editor 直接走 `--godot` / `GODOT_PATH`，export templates 走 Godot 标准用户目录并与 editor 精确匹配 | `output/steamworks_lab/README.md`、`tools/steamworks_lab_toolchain.py`、测试策略、AI导航、current_state、AI记忆 |
| #135 | Steamworks Slime Lab 玩家可见本地多人改为单进程同屏：P1 键鼠、P2–P4 独立手柄；Steam 维持一设备一玩家，ENet Host/Join 仅保留内部协议回归 | `output/steamworks_lab/README.md`、`scripts/local_input_router.gd`、`scripts/steamworks_lab.gd`、HUD / Buff / Pause / Expression UI、`tests/local_couch_smoke.gd`、`tests/battle_smoke.gd`、测试策略、AI导航、current_state、AI记忆 |
| #136 | Steamworks Slime Lab 清理动态世界矩形 / 最长纪录落盘残留 smoke，快照 wire 改为 FastLZ + 900 字节 unreliable 分片并升级 `lab_version=2` | `output/steamworks_lab/README.md`、`scripts/lab_save.gd`、`scripts/network_session.gd`、`scripts/transport_adapter.gd`、`tests/battle_smoke.gd`、`tests/net_host_smoke.gd`、测试策略、AI导航、current_state、AI记忆 |
| #137 | Steamworks Slime Lab 将最长存活纪录拆为单人和多人；多人合并同屏与 Steam，各设备本地落盘，旧混合纪录清空，Records 同时显示两行 | `output/steamworks_lab/README.md`、`scripts/lab_save.gd`、`scripts/steamworks_lab.gd`、`scripts/records_panel.gd`、`scripts/lab_locale.gd`、`tests/battle_smoke.gd`、`tests/local_couch_smoke.gd`、测试策略、AI导航、current_state、AI记忆 |
| #138 | Steamworks Lab 自动回归统一由 Python runner 编排；每进程隔离 `user://`，用精确成功协议、动态 ENet 端口、超时清理和源码 App ID 门禁防止跨对话复发 | `tools/steamworks_lab_toolchain.py`、`tools/test_steamworks_lab_toolchain.py`、Lab settings / main / smoke tests、pre-commit、四平台 `godot-test-diagnostics`、README、测试策略、工具适配、AI导航、current_state、AI记忆 |
| #139 | Steamworks Slime Lab 仅在单人模式增加战斗充能的 10 秒 AI 队友大招；AI 自动跟随 / 射击并同意一次合体，不进入真人 roster、纪录或网络快照，多人 / wire / 存档 / 正式 `client` 不变 | `output/steamworks_lab/README.md`、`scripts/ai_teammate.gd`、`scripts/battle_director.gd`、`scripts/steamworks_lab.gd`、HUD / locale、`tests/battle_smoke.gd`、`tests/local_couch_smoke.gd`、测试策略、AI导航、current_state、AI记忆 |
| #140 | Steamworks Slime Lab 单人 AI 改为确定性自主游击 / 预判闪避；避开敌弹、普通敌人、Boss 与障碍物，使用 210 px 常规硬限 / 超过 220 px 复位，并在合体输入后高速归队至 92 px、停靠 0.8 秒再合体；不可受伤 / 不吸引火力及网络 / 存档 / 正式 `client` 边界不变；目标 battle、local-couch 与权威 all-suite 已通过 | `output/steamworks_lab/README.md`、`scripts/ai_teammate.gd`、`scripts/battle_director.gd`、`scripts/steamworks_lab.gd`、敌人 / Boss / 障碍物脚本、`tests/battle_smoke.gd`、`tests/local_couch_smoke.gd`、测试策略、AI导航、current_state、AI记忆 |
| #141 | 项目当前开发、验证和推荐编辑器基线精确到 Godot 4.7.1 stable；`project.godot` 的 4.7 特性标识、官方 4.7 文档路径与 Steam 工具的 4.7 minor 系列兼容检查保持不变，不修改代码或数据 schema | README、client / Test Lab / Steamworks Lab README、GDD v1.19、三平台完整规则、五份 `godot-gdscript` skill、AI导航、CI 规划、FormalClientBoot 文档、current_state、AI记忆 |
| #142 | F13 默认关卡改为 9×9 模块连续大地图，每模块 11×11 格；编辑期 AI 生成候选 JSON、人工批准后入池，运行时按 seed 组合并仅激活 3×3 邻域；run 升 v4，旧 v3 明确重置；RoomManager 线性房间方向被取代并删除，开放战区只留非默认回归 | F13 模块世界工作包、GDD、词表、数据手册、ModuleWorldManager / Gameplay Runtime / SaveManager / MapManager 文档、测试策略、AI导航、current_state、AI记忆 |
| #143 | 性能测试只由用户当次明确触发；`startup-probe`、`perf-probe` 和 Profiler 不进入日常修改、提交前、常规回归、默认 CI 或 AI 交付义务，现有 probe 作为按需工具保留 | 测试策略、CICD 规划、AI 导航、相关工作包 / 模块文档、current_state、项目记忆 |
| #144 | 删除敌人种间交互生态；EnemyAI 只选择玩家，拒绝敌方友伤，保留五类对玩家 profile 与无伤害中心分离；敌人 AI / 战区导演数据升 schema v2，删除旧关系与导演敌人组合元数据，run 保持 v4 并清空旧快照非法动作 | GDD §5.3、EnemyAI / WarzoneDirector / Gameplay Runtime / DataLoader 文档、F10 工作包、数据手册、词表、测试策略、AI导航、current_state、AI记忆 |
| #145 | F14 敌人导航与感知采用完整 99×99 静态 mask 上的确定性共享流场 + 混合感知；畅通直追、受阻绕行，感知依次使用地形视线、路径距离和 1.5 秒最后已知位置；守家 / 记忆使用 AStar waypoint，冲锋 / 远程受墙体门禁；profile 升 schema v3，run 保持 v4，F13 保持完成 | F14 工作包、GDD §5.3、EnemyAI / ModuleWorldManager / Gameplay Runtime 文档、数据手册、测试策略、AI导航、current_state、AI记忆 |
| #146 | F14 活动目标流场从完整 99×99 Dijkstra 修正为最大视觉范围驱动的局部有界重建；当前半径 8、最多 289 格，只清理上次触达索引并使用并行数值堆；完整 mask、视线和守家 / 记忆 AStar 保持全图，run v4 与 profile schema v3 不变 | F14 工作包、GDD v1.24 §5.3、EnemyAI / ModuleWorldManager / Gameplay Runtime 文档、测试策略、AI导航、current_state、AI记忆 |
| #147 | 正式客户端固定版本入库并共享启用 `@icons 1.4.0` 与 `Script-IDE 2.2.3`；只保留官方发布包 addon 子目录和 MIT 许可，仓库内作为不设 lint 豁免的维护型 fork，升级必须人工核对 SHA-256、审查差异并迁移本地补丁 | `client/addons/README.md`、`client/project.godot`、`client/README.md`、CREDITS / locale、AI导航、current_state、AI记忆 |
| #148 | 正式玩家摄像机迁移到 `Phantom Camera 0.11.0.3` 固定版本维护型 fork；Player 子场景内用 GLUED PCam 保持严格居中 / 水平 / 等比缩放，有效玩家伤害按 `camera_feedback.json` 触发可关闭位移震屏，噪声走 `RNG.camera_fx`；项目固定 autoload 并保持 `physics_jitter_fix=0.5` | GDD v1.24 §5.2、`client/addons/README.md`、`docs/代码/phantom_camera.md`、Gameplay Runtime / Settings 文档、数据手册、测试策略、AI导航、current_state、AI记忆 |
| #149 | 玩家和敌方子弹默认受地形阻挡；Bullet 以命中半径圆形做首帧重叠与本帧扫掠，命中后由对象池回收。`pierce_count` 只控制伤害目标穿透，`wall_pierce` 以 `0` / `>0` 独立控制全地形阻挡 / 忽略并在发射时快照；旧快照缺字段默认不能穿墙，run 保持 v4 | GDD v1.25 §4、词表、数据手册、Gameplay Runtime / ModuleWorldManager 文档、双端 DataLoader、module-world smoke、AI导航、current_state、AI记忆 |
| #150 | 正式客户端未来采用 GodotSteam + Talo 且不开发自有通用后端：`PlatformServices → GodotSteam` 负责 Steam 平台能力，规划中的 `OnlineServices → Talo` 负责跨平台身份、排行榜 / 统计、Live Config、事件与轻量社交；当前不安装、不批准具体功能，Talo Cloud / 官方自托管实施前另行决策 | `docs/在线服务规划.md`、GDD v1.26 §6.7 / §9.22 / §9.23、PlatformServices 文档、测试策略、正式工作规划、TODO、AI导航、current_state、AI记忆 |
| #151 | 正式输入迁移到固定版本 GUIDE 0.14.0 维护型 fork，项目 `InputService` 成为唯一业务边界；`move` / `aim` 使用 Vector2 intent，Settings 升 v2、绑定独立为 GUIDE config，Replay file / recording 升 v2 并兼容读取 v1；业务不得直调 GUIDE / Input / InputMap | GDD v1.27、词表、GUIDE / InputService / Settings / Replay / Gameplay Runtime / UIManager 文档、插件清单与 Credits、测试策略、四平台规则、AI导航、current_state、AI记忆 |
| #152 | 在公开兼容窗口前关闭旧输入格式兼容：Settings v1 只保留普通偏好并忽略旧 `input.*`，Replay 只接受 v2，八个旧方向 action 删除；同名 GUIDE binding id 保持稳定。本条只取代 #151 的 v1 兼容条款 | GDD v1.28、词表、InputService / Settings / Replay 文档、测试策略、AI导航、current_state、AI记忆 |

F14 交付时的四条黄金回放重录与运行时摘要证据见 [2026-07-21 F14 黄金回放回归报告](reports/2026-07-21-f14-replay-regression.md)。

新增 ADR 时必须判断是否要扩展本矩阵。

## 6. 示例与反例

| 类型 | 路径 | 用途 |
|------|------|------|
| 正式项目启动模块文档 | `docs/代码/formal_client_boot.md` | 展示 F1 最小启动骨架与 gameplay runtime 挂载的职责边界、场景结构与验证方式 |
| Gameplay Runtime 模块文档 | `docs/代码/gameplay_runtime.md` / `docs/代码/combat.md` / `docs/代码/skill_system.md` / `docs/代码/status_effect_component.md` / `docs/代码/map_manager.md` / `docs/代码/module_world_manager.md` / `docs/代码/hazard_system.md` / `docs/代码/warzone_director.md` | 展示最小可玩闭环、统一伤害入口、F13 模块世界与 F14 局部有界共享导航 / 全图 AStar / 感知、开放战区回归、对象池实体、HUD 与验证方式 |
| Phantom Camera 模块文档 | `docs/代码/phantom_camera.md` | 展示 vendored 插件 Runtime / Resource / Editor / C# 边界、Manager / Host / PCam 生命周期、正式 2D 项目接入、本地补丁和升级验证 |
| GUIDE / InputService 模块文档 | `docs/代码/guide.md` / `docs/代码/input_service.md` | 展示 vendored 输入引擎内部、维护补丁与升级，以及项目 action / context / intent / 重绑定 / 提示 / 回放唯一业务边界 |
| 在线服务规划 | `docs/在线服务规划.md` | 展示未来 GodotSteam + Talo 的供应商分层、单一写入权威、托管决策、离线 / 安全边界和触发式实施阶段；不代表当前已安装 |
| EnemyAI 模块文档 | `docs/代码/enemy_ai.md` | 展示 schema v3 对玩家 profile、视线 / 路径 / 记忆感知、Utility/FSM/Steering、共享流场、攻击墙体门禁、友伤护栏与旧快照兼容 |
| ADR #144 黄金回放报告 | [2026-07-21 ADR #144 黄金回放回归报告](reports/2026-07-21-replay-regression.md) | 记录四条 golden 的重录数据指纹、逐条真实运行时复跑结果和未运行性能测试的边界 |
| 正式项目 autoload 模块文档 | `docs/代码/mod_loader.md` / `data_loader.md` / `rng.md` / `game_state.md` / `game_clock.md` / `platform_services.md` / `settings.md` / `guide.md` / `input_service.md` / `analytics.md` / `replay.md` / `pool_manager.md` / `save_manager.md` / `audio_manager.md` / `localization.md` / `ui_manager.md` | 展示基础设施模块的 API、依赖与测试义务；输入 autoload 顺序固定为 Settings → GUIDE → InputService → Replay |
| 功能建议池 | `docs/功能建议池.md` | 展示 F9 第一轮 Demo 收口后可人工点名的新功能菜单；不是已采纳路线图 |
| 局内刷取参考研究 | `docs/局内刷取参考研究.md` | 展示 F12 局内刷取、兴趣点、撤离结算、射击构筑和 Gear Mod 循环的外部游戏参考；不是已采纳路线图 |
| AI 辅助开发机会清单 | `docs/AI辅助开发机会清单.md` | 展示不在运行时接 LLM、只利用 AI 辅助写代码 / 数据 / 工具时可参考的玩法、内容管线和开发工具机会；不是已采纳路线图 |
| 小服务器玩法备忘 | `docs/小服务器玩法备忘.md` | 展示 Talo 可承载的异步在线、敌巢进化、死亡残响、星域污染图等玩法；供应商路线已采纳，但具体玩法不是已采纳路线图 |
| 规则反例 | 当前平台规则入口的红线与自检清单 | 防止硬编码、裸字符串、绕过 autoload |

## 7. 维护规则

- 新增长期文档时，同时登记到 `docs/_kb_index.json`；可用目录条目覆盖一组同类长期文档。
- 删除或重命名长期文档时，同步本索引、机器索引、AI 导航和所有引用路径。
- 文档权威范围变化时，更新 `authority`、`owner_scope`、`canonical_for`、`must_read_for`、`related_docs`、`update_triggers`。
- 每次知识库结构变化后运行 `python tools/docs_health_check.py`。
