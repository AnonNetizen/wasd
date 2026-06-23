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
| 4 | `docs/词表与契约.md` | 约定字符串、id 白名单、InputMap action |
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
| 查看 / 维护未来任务 | `docs/TODO.md`、`docs/功能建议池.md`、`docs/AI辅助开发机会清单.md`、`docs/小服务器玩法备忘.md`、`docs/AI记忆/current_state.json`、`docs/修改建议.md` | `docs/TODO.md`、必要时 current_state / 会话日志 / 修改建议 / 功能建议池 / AI辅助开发机会清单 / 小服务器玩法备忘 | `python tools/docs_health_check.py`；若改 JSON 同步跑 `python -m json.tool` |
| 改 IP / 世界观 / 英雄包装 / 宣传语 | `docs/IP设定.md`、`docs/游戏设计文档.md` §1.2、`docs/术语表.md` | IP 设定、GDD 摘要、术语表、AI导航、必要时 ADR / AI记忆 / locale 文案 | `python tools/docs_health_check.py`；若改 JSON 同步跑 `python -m json.tool` |
| 选择下一项新功能 / 功能菜单 | `docs/功能建议池.md`、`docs/AI辅助开发机会清单.md`、`docs/TODO.md`、`docs/AI记忆/current_state.json`；若用户点名具体系统，再读对应工作包 / 模块文档 / GDD 章节 | 用户点名后再改 TODO / current_state / 工作包 / GDD / ADR / 模块文档；未点名前不实现功能 | `python tools/docs_health_check.py`；若改 JSON 同步跑 `python -m json.tool`；进入实现后按目标工作包验收命令运行 |
| 评估小服务器在线玩法 | `docs/小服务器玩法备忘.md`、GDD §6.7 / §9.21 / §9.22、`docs/代码/platform_services.md`、`docs/代码/replay.md` | 用户点名采纳后再改 GDD / ADR / 功能建议池 / 工作包 / 相关模块文档；未点名前只做评估 | `python tools/docs_health_check.py`；若新增在线服务 schema 或 JSON 索引，同步跑 `python -m json.tool` |
| 启动 / 推进正式项目 | 当前阶段工作包；F9 默认 `docs/AI协作/工作包/F9-ContentDemoPolish.md`、`docs/AI记忆/current_state.json`、目标模块文档；F8 回放 / 测试 / 平衡维护看 `docs/AI协作/工作包/F8-ReplayTestingBalance.md`；F7 设置 / 本地化 / UI 栈维护看 `docs/AI协作/工作包/F7-SettingsLocalizationUI.md`；F6 局外成长看 `docs/AI协作/工作包/F6-MetaProgression.md`；F4 最小可玩闭环看 `docs/AI协作/工作包/F4-MinPlayableLoop.md`；历史 F3 数据闭环看 `docs/AI协作/工作包/F3-DataLoader.md` | `client/`、模块文档、必要时 TODO / GDD / ADR / 词表 / 测试策略 | 按工作包验收命令运行；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；项目规则变化跑 `python tools/lint_project_rules.py`；语义风险检查跑 `python tools/lint_semantic_rules.py`；文档变化跑 `python tools/docs_health_check.py`；JSON 变化跑 `python -m json.tool` |
| 维护正式客户端启动骨架 | `client/README.md`、`docs/代码/formal_client_boot.md`、`docs/代码/gameplay_runtime.md`、`docs/正式项目工作规划.md` F1/F4 | `client/project.godot`、`client/scenes/boot/main.tscn`、`client/scripts/boot/formal_client_boot.gd`、AI导航、代码文档索引 | `python tools/godot_bridge.py headless-boot`、`python tools/godot_bridge.py export-tree`、`python tools/docs_health_check.py` |
| 维护 F2+ autoload 骨架 | GDD §9.3~§9.22、`docs/代码/mod_loader.md`、`docs/代码/data_loader.md`、`docs/代码/rng.md`、`docs/代码/game_state.md`、`docs/代码/game_clock.md`、`docs/代码/platform_services.md`、`docs/代码/settings.md`、`docs/代码/analytics.md`、`docs/代码/replay.md`、`docs/代码/pool_manager.md`、`docs/代码/save_manager.md`、`docs/代码/audio_manager.md`、`docs/代码/localization.md`、`docs/代码/ui_manager.md` | `client/scripts/autoload/`、`client/project.godot`、AI导航、代码文档索引、current_state | `python tools/godot_bridge.py headless-boot`、`python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/docs_health_check.py` |
| 加 / 改角色 | GDD §3.4、`client/data/README.md`、`docs/词表与契约.md` §12、`docs/AI导航.md` | `client/data/characters.json`、`client/locale/strings.csv`、起始携带引用、必要时词表和模块文档 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加 / 改武器 | `client/data/README.md`、`docs/词表与契约.md` §8 / §9 / §10、`docs/AI导航.md` | `client/data/weapons.json`、`client/locale/strings.csv`、必要时角色 / 模式引用 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加 / 改技能 | `docs/代码/skill_system.md`、`client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §12-C~12-G、涉及状态时追加 §9-A~§9-B 与 `docs/代码/status_effect_component.md`、`docs/AI导航.md` | `client/data/skills.json`、`client/data/characters.json`、`client/data/game_modes.json`、`client/locale/strings.csv`、必要时词表 / DataLoader schema / runtime smoke | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；`python tools/lint_project_rules.py`；schema 变化跑 `python tools/test_data_loader_schema.py`；运行时行为变化跑 `l1-smoke` + `runtime-smoke` |
| 加 / 改状态效果 | `docs/代码/status_effect_component.md`、`docs/代码/skill_system.md`、GDD §9.15.2、`docs/词表与契约.md` §9-A~§9-B / §12-F~§12-G、`docs/测试策略.md` | `client/scripts/combat/status_effect.gd`、`client/scripts/combat/status_effect_component.gd`、`client/scripts/gameplay/skill_system.gd`、`client/scripts/gameplay/player.gd`、`client/scripts/gameplay/enemy.gd`、`client/data/skills.json`、DataLoader schema、必要时 run 快照 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；`python tools/test_data_loader_schema.py`；`python tools/godot_bridge.py --project client l1-smoke`；影响续局时追加 `save-smoke`；影响整局时评估 golden |
| 加 / 改游戏模式 | GDD §6.6、`client/data/README.md`、`docs/AI导航.md` | `client/data/game_modes.json`、资源池 / 权重 / 禁用列表、必要时词表和模块文档 | `python tools/docs_health_check.py`；`python tools/validate_data.py` |
| 加遗物 / 道具 | `client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §1 / §2 / §3 / §12、`docs/AI协作/任务模板/加遗物.md` | `client/data/relics.json`、`client/locale/strings.csv`、必要时词表、模式引用和效果原语 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加 / 改主动道具 | `client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §2 / §6 / §7 / §12、`docs/AI导航.md` | `client/data/active_items.json`、`client/data/game_modes.json` 主动道具池、`client/locale/strings.csv`、必要时词表和效果原语 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加 / 改消耗品 | `client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §2 / §6 / §12、`docs/AI导航.md` | `client/data/consumables.json`、`client/data/game_modes.json` 消耗品池、`client/locale/strings.csv`、必要时词表和效果原语 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加敌人 | `docs/AI协作/任务模板/加敌人.md`、`client/data/README.md`、`client/locale/README.md`、`docs/代码/enemy_ai.md`、`docs/词表与契约.md` §8/9/12、GDD 敌人章节 | `client/data/enemies.csv`、`client/data/enemy_ai_profiles.json`、`client/locale/strings.csv`、`game_modes` 敌人池、必要时 AI action / content tag 词表 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 改 EnemyAI / 怪物生态 | `docs/代码/enemy_ai.md`、GDD §5.3、`client/data/README.md` 的 `enemy_ai_profiles.json` 段、`docs/词表与契约.md` §12-B | `client/scripts/gameplay/enemy.gd`、`client/data/enemy_ai_profiles.json`、`client/data/enemies.csv`、`client/tools/runtime_smoke.gd`、必要时 golden replay / perf 基线 | `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/godot_bridge.py --project client runtime-smoke`；改变稳定行为时重录 / 重跑四条 golden replay 和 `perf-probe` |
| 改地图 / PCG / 人工摆点 | `docs/代码/map_manager.md`、`client/data/README.md` 的 `map_layouts.json` 段、GDD §5、ADR #93 | `client/data/map_layouts.json`、`client/scripts/gameplay/map_manager.gd`、`client/tools/runtime_smoke.gd`、必要时 `docs/代码/hazard_system.md` | `python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/godot_bridge.py --project client runtime-smoke`；机关相关追加 `f9-demo-smoke` / `save-smoke` / `perf-probe` |
| 加 / 改机关 | `docs/代码/hazard_system.md`、`client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §8/9/12、`docs/AI导航.md` | `client/data/hazards.csv`、`client/data/map_layouts.json`、`client/locale/strings.csv`、`game_modes` 机关池、必要时地图 / 机关 primitive | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；运行时机关变化跑 `runtime-smoke` / `f9-demo-smoke`；文档变化跑 `python tools/docs_health_check.py` |
| 加 / 改刷怪波次 | `client/data/README.md`、GDD §5.3 / §9.3、`docs/AI导航.md` | `client/data/spawn_waves.csv`、DataLoader schema、必要时 Spawner 模块文档 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 改输入 / 手柄 | `docs/游戏设计文档.md`、`docs/词表与契约.md` 第 7 节、`docs/测试策略.md` | GDD、词表、规则、Settings/InputMap 代码、AI导航 | `python tools/docs_health_check.py`；代码落地后跑 headless + 手动输入回归 |
| 改经验 / 升级系统 | `docs/游戏设计文档.md` §7.1、`docs/词表与契约.md`、`docs/测试策略.md` | `GrowthSystem`、升级 UI、GDD、词表、AI导航、必要时 `docs/修改建议.md` | `python tools/docs_health_check.py`；代码落地后固定 seed 验证默认 3 选 1 与 `luck` 概率 4 选 1 |
| 改局外成长 / 元进度 | `docs/游戏设计文档.md` §7.2、`docs/代码/meta_progression_system.md`、`client/data/README.md`、`docs/词表与契约.md` §13、`docs/测试策略.md` | `client/scripts/autoload/meta_progression_system.gd`、`client/scripts/ui/meta_progression_panel.gd`、`client/data/meta_progression.json`、locale、GDD、词表、AI导航、SaveManager / gameplay runtime 模块文档 | `python tools/sync_contracts.py --check` + `python tools/validate_data.py`；代码落地后跑 `python tools/godot_bridge.py --project client meta-smoke`，改死亡结算接入时追加 `runtime-smoke` |
| 改存档 / 暂停退出续局 | `docs/游戏设计文档.md` §9.16、`docs/词表与契约.md` §14、`docs/测试策略.md` | SaveManager、GameState、暂停菜单、主菜单、GDD、词表、AI导航、模块文档 | SaveManager 单测、run roundtrip、损坏 / 迁移测试；代码落地后跑 headless 和手动存档 checklist |
| 调完整项目数值 | `client/data/README.md`、目标 `client/data/*.csv` / `client/data/*.json`、`docs/词表与契约.md` | 数据 CSV / JSON、数值手册、必要时 GDD / 模块文档 / 黄金回放 | `python tools/validate_data.py`；大改动跑回放 / 平衡验证 |
| 加完整项目文案 / 语言 | `client/locale/README.md`、`client/locale/strings.csv`、`docs/词表与契约.md` §6 | 文案 CSV、语言设置、相关 UI / 数据模块文档；AI 自动补齐 `zh_CN` / `en` 另一语言首版译文；涉及 UI 布局时按英文 `en` 长度验收 | `python tools/validate_data.py`；UI 文案 / 布局变化跑 `settings-smoke` 或对应 smoke；人工切语言回归 |
| 改致谢 / 第三方来源 | `CREDITS.md`、`client/data/README.md`、`client/locale/README.md` | `client/data/credits.json`、`client/locale/strings.csv`、DataLoader schema、AI导航、必要时 ADR / 记忆 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 维护本地 mod 接口 / 未来创意工坊边界 | GDD §9.21、`docs/代码/mod_loader.md`、`docs/代码/data_loader.md`、`client/data/README.md`、`docs/测试策略.md` | `client/scripts/autoload/mod_loader.gd`、`client/scripts/autoload/data_loader.gd`、`client/project.godot`、`client/tools/l1_smoke.gd`、三平台规则、AI导航、ADR、AI记忆 | `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client l1-smoke`、`python tools/godot_bridge.py --project client headless-boot`、文档变化跑 `python tools/docs_health_check.py` |
| 维护 Steam API / 平台服务接口 | GDD §9.22、`docs/代码/platform_services.md`、`docs/测试策略.md`、`docs/AI导航.md` | `client/scripts/autoload/platform_services.gd`、`client/project.godot`、`client/scripts/boot/formal_client_boot.gd`、`client/tools/l1_smoke.gd`、三平台规则、ADR、AI记忆 | `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client l1-smoke`、`python tools/godot_bridge.py --project client headless-boot`；真实 Steam 接入追加平台手动 smoke |
| 改规则 / 红线 | `AGENTS.md`、当前平台规则入口、`docs/决策记录.md`、`docs/AI协作/文档维护指南.md` | `AGENTS.md`、三平台规则、`CODEX.md`、`OPENCODE.md`、AI导航、项目记忆 | `python tools/docs_health_check.py`、`git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"` |
| 改约定字符串 | `docs/词表与契约.md`、`docs/AI协作/文档健康检查.md` | 词表、生成常量、相关数据 / 代码、AI导航 | `python tools/sync_contracts.py` + `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；`python tools/docs_health_check.py` |
| 写/改 F4 最小可玩闭环 | `docs/AI协作/工作包/F4-MinPlayableLoop.md`、`docs/代码/gameplay_runtime.md`、`docs/代码/combat.md`、相关 autoload 模块文档 | `client/scripts/gameplay/`、`client/scripts/combat/`、`formal_client_boot.gd`、locale、模块文档、AI导航 | `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、数据 / 文案变化时跑 `validate_data` 和 `lint_project_rules` |
| 写/改 F6 局外成长闭环 | `docs/AI协作/工作包/F6-MetaProgression.md`、`docs/代码/meta_progression_system.md`、`docs/游戏设计文档.md` §7.2 / §9.16、`docs/代码/save_manager.md`、`client/data/README.md` 的 `meta_progression.json` 段 | `MetaProgressionSystem`、`MetaProgressionPanel`、结算流程、`client/data/meta_progression.json`、locale、SaveManager / gameplay runtime 模块文档、AI导航 | `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/godot_bridge.py --project client meta-smoke`；改 run / SaveManager envelope 时追加 `save-smoke`，改死亡结算接入时追加 `runtime-smoke` |
| 写/改 F7 设置 / 本地化 / UI 栈 | `docs/AI协作/工作包/F7-SettingsLocalizationUI.md`、`docs/代码/settings.md`、`docs/代码/localization.md`、`docs/代码/ui_manager.md`、`client/locale/README.md`、`docs/游戏设计文档.md` §9.4 / §9.5 / §9.14 | `Settings`、`Localization`、`UIManager`、设置面板场景、标题 / 暂停 / HUD / 升级 / 结算 / 局外成长 UI、locale、InputMap、AI导航；UI 尺寸以英文 `en` 文案长度验收 | `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/godot_bridge.py --project client headless-boot`、`runtime-smoke`、`meta-smoke`、`save-smoke`；新增 F7 smoke 后追加 `settings-smoke`；文档变化跑 `python tools/docs_health_check.py` |
| 写/改 F8 回放 / 测试 / 平衡基线 | `docs/AI协作/工作包/F8-ReplayTestingBalance.md`、`docs/测试策略.md`、`docs/CICD规划.md`、`docs/代码/replay.md`、`docs/代码/rng.md`、`docs/代码/game_clock.md`、`docs/代码/game_state.md`、`docs/代码/save_manager.md`、`docs/代码/gameplay_runtime.md` | `Replay`、`RNG`、`client/tools/l1_smoke.gd`、`client/tools/replay_smoke.gd`、`client/tools/replay_runner.gd`、`client/tools/replay_input_smoke.gd`、`client/tools/golden_replay_capture.gd`、`client/tools/rng_audit.gd`、`client/tools/perf_probe.gd`、`client/tests/replays/`、基础平衡采样、必要时 `tools/godot_bridge.py` | 既有 Stage 1 + `headless-boot`、`runtime-smoke`、`settings-smoke`、`meta-smoke`、`save-smoke`；F8 追加 `python tools/godot_bridge.py --project client l1-smoke`、`replay-smoke`、`replay-runner`、`replay-runner --rerun-runtime-summary`、`replay-input-smoke`、`capture-golden-replay`、`capture-golden-replay --golden-scenario golden_pause_resume`、`capture-golden-replay --golden-scenario golden_full_death`、`capture-golden-replay --golden-scenario golden_level_up_choice`、`rng-audit`、四条 checked-in replay 的 `replay-runner --replay-file ... --rerun-runtime-summary`、`perf-probe`；帧样本字段变化需重录 golden，RNG seed 派生 / 子流变化需先跑 `rng-audit` 再评估 golden；文档变化跑 `python tools/docs_health_check.py` |
| 写/改 F9 内容扩展 / Demo 打磨 | `docs/AI协作/工作包/F9-ContentDemoPolish.md`、`docs/AI导航.md` 第 4 节、`client/data/README.md`、`client/locale/README.md`、目标数据文件 | `docs/测试策略.md`、`docs/代码/gameplay_runtime.md`、`docs/词表与契约.md` 相关章节、必要时目标源码、F8 golden replay / perf 入口 | `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/lint_project_rules.py`、相关 smoke、四条 checked-in replay runner、`python tools/godot_bridge.py --project client perf-probe`；文档变化跑 `python tools/docs_health_check.py` |
| 写/改代码模块 | `docs/代码文档规范.md`、对应 `docs/代码/<module_id>.md`、目标源码；触碰 `.gd` 时遵循 [Godot 4.7 官方 GDScript style guide](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_styleguide.html)；测试相关时读 `docs/测试策略.md` 相关段；大型代码改动 review 读 `docs/AI协作/代码审核流程.md` | 代码、模块文档、AI导航依赖图、必要时 GDD / ADR | 对应测试义务 + `pre-commit run --all-files` 或等价 lint/test/docs 命令 + `python tools/docs_health_check.py` |
| 写/改测试 | `docs/测试策略.md`、对应模块文档 | 测试文件、测试策略、必要时 CI 规划 | 对应测试命令；`python tools/docs_health_check.py` |
| 加 GM 指令 / 调试工具 | `docs/游戏设计文档.md` §9.20、`docs/代码/debug_tools.md`、`docs/词表与契约.md` §7、`docs/测试策略.md` §5.10 | `client/scripts/debug/debug_console.gd`、`client/scripts/debug/gm_command_registry.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`client/tools/debug_tools_smoke.gd`、InputMap action、导出 preset、AI导航、测试策略 | `python tools/godot_bridge.py --project client debug-tools-smoke`、`python tools/godot_bridge.py --project client debug-tools-release-smoke`、`python tools/sync_contracts.py --check`、`python tools/docs_health_check.py`；命令影响局内战斗时追加 `runtime-smoke` |
| 更新 AI 工具入口 | `AGENTS.md`、`docs/AI协作/工具适配指南.md`、`docs/AI协作/角色分工.md` | `CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、`.codebuddy/`、`.codex/`、`.opencode/` | `python tools/docs_health_check.py`；改 `.opencode/` 后验证 JSON |
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
| #43 | 经验与升级选择系统 | GDD §7.1、词表、测试策略、AI导航、术语表、修改建议 E |
| #44 | AI 记忆三层结构 | `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json`、`docs/AI记忆/README.md`、`tools/docs_health_check.py` |
| #45 | 完整项目数值 / 文案配置手册 | `client/data/README.md`、`client/locale/README.md`、GDD §9.3 / §9.4、词表、AI导航、任务模板 |
| #46 | 深局外成长 | GDD §7.2、`client/data/meta_progression.json`、`client/data/README.md`、`client/locale/strings.csv`、词表 §13、测试策略、AI导航 |
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
| #93 | 有限地图 + 可人工调参 PCG；`map_layouts.json` 声明 bounds、出生点、安全半径、刷怪边距、PCG 机关和人工摆点，`MapManager` / `HazardSystem` 保存并恢复 FEA-12 等机关 | `docs/代码/map_manager.md`、`docs/代码/hazard_system.md`、`client/data/map_layouts.json`、`client/data/hazards.csv`、`client/scripts/gameplay/map_manager.gd`、`client/scripts/gameplay/hazard.gd`、GDD §5 / §9.16、测试策略、AI导航、AI记忆 |
| #94 | 项目版轻量 GAS 首片；`skills.json` 增加 ability tags 和 activation tag gating，SkillSystem 保存 owned tag 计数并保留现有主技能 API | `docs/代码/skill_system.md`、`client/data/skills.json`、`client/scripts/gameplay/skill_system.gd`、`client/scripts/autoload/data_loader.gd`、`tools/validate_data.py`、词表 §12-G、GDD §6.1-A、测试策略、AI导航、AI记忆 |
| #95 | 状态效果首片接入轻量 GAS；`StatusEffect` / `StatusEffectComponent` 管理状态叠加、ability tag 生命周期和 SkillSystem 状态快照，`skill_effect_apply_status` 支撑沉默 | `docs/代码/status_effect_component.md`、`docs/代码/skill_system.md`、`client/scripts/combat/status_effect.gd`、`client/scripts/combat/status_effect_component.gd`、`client/scripts/gameplay/skill_system.gd`、`client/tools/l1_smoke.gd`、词表 §9-A~§9-B / §12-F、GDD §9.15.2、测试策略、AI导航、AI记忆 |
| #96 | Player / Enemy 正式接入 StatusEffectComponent；实体暴露 `apply_status_effect()` 与 owned ability tag 查询，run 快照保存状态效果并在对象池复用时清理 | `client/scripts/gameplay/player.gd`、`client/scripts/gameplay/enemy.gd`、`client/tools/l1_smoke.gd`、`docs/代码/status_effect_component.md`、`docs/代码/gameplay_runtime.md`、`docs/代码/enemy_ai.md`、GDD §6.1-A / §9.15.2、测试策略、AI导航、AI记忆 |
| #97 | burn 首个真实 DoT 状态；StatusEffect 保存 `damage_type` / `tick_remaining` / 队伍归因，StatusEffectComponent 按 GameClock tick 并经 Combat 结算 `fire + is_dot` | `client/scripts/combat/status_effect.gd`、`client/scripts/combat/status_effect_component.gd`、`client/scripts/gameplay/player.gd`、`client/scripts/gameplay/enemy.gd`、`client/scripts/autoload/data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py`、`client/tools/l1_smoke.gd`、`docs/代码/status_effect_component.md`、`docs/代码/skill_system.md`、`docs/代码/combat.md`、GDD §9.15.2、测试策略、AI导航、AI记忆 |
| #98 | 类型定位改为刷宝动作生存；参考星际战甲 / 暗黑的装备、词条、长期养成与刷战利品循环（当前视角口径已由 #100 / #101 更新为固定斜俯视 2.5D） | README、GDD、IP设定、术语表、AI导航、CICD规划、功能建议池、AI记忆、平台规则 / skills |
| #99 | 玩家 2.5D 视觉层首片；玩法实体保持 `CharacterBody2D` / `Camera2D` / 2D 平面移动，`Player3DVisual` 用 SubViewport 渲染低模 3D 胶囊并贴回 2D 世界 | GDD、AI导航、Gameplay runtime 文档、`client/scenes/gameplay/player.tscn`、`client/scenes/gameplay/player_3d_visual.tscn`、`client/scripts/gameplay/player.gd`、`client/scripts/gameplay/player_3d_visual.gd`、`client/tools/runtime_smoke.gd`、AI记忆 |
| #100 | 当前正式视角口径改为固定斜俯视 2.5D 刷宝动作生存；显示层向暗黑式 3/4 可读性靠拢，玩法仍是 2D 平面，具体相机实现由 #101 修正 | README、GDD、IP设定、术语表、AI导航、Gameplay runtime 文档、`client/scripts/gameplay/player.gd`、`client/tools/runtime_smoke.gd`、AI记忆、平台规则 |
| #101 | 修正固定斜俯视相机实现：`CenteredCamera` 不滚转屏幕，保持玩家居中和屏幕水平，只做纵深轴压缩；`Player3DVisual` 用更明显的 3/4 俯看 `Camera3D` 角度 | README、GDD、术语表、AI导航、Gameplay runtime 文档、`client/scripts/gameplay/player.gd`、`client/scripts/gameplay/player_3d_visual.gd`、`client/tools/runtime_smoke.gd`、AI记忆 |

新增 ADR 时必须判断是否要扩展本矩阵。

## 6. 示例与反例

| 类型 | 路径 | 用途 |
|------|------|------|
| 正式项目启动模块文档 | `docs/代码/formal_client_boot.md` | 展示 F1 最小启动骨架与 gameplay runtime 挂载的职责边界、场景结构与验证方式 |
| Gameplay Runtime 模块文档 | `docs/代码/gameplay_runtime.md` / `docs/代码/combat.md` / `docs/代码/skill_system.md` / `docs/代码/status_effect_component.md` / `docs/代码/map_manager.md` / `docs/代码/hazard_system.md` | 展示最小可玩闭环、统一伤害入口、可复用主动技能、状态效果生命周期、有限地图、PCG 机关、对象池实体、HUD 与验证方式 |
| EnemyAI 模块文档 | `docs/代码/enemy_ai.md` | 展示怪物生态 profile、Utility/FSM/Steering 分工、怪物互相伤害归因与验证方式 |
| 正式项目 autoload 模块文档 | `docs/代码/mod_loader.md` / `data_loader.md` / `rng.md` / `game_state.md` / `game_clock.md` / `platform_services.md` / `settings.md` / `analytics.md` / `replay.md` / `pool_manager.md` / `save_manager.md` / `audio_manager.md` / `localization.md` / `ui_manager.md` | 展示基础设施模块的 API、依赖与测试义务 |
| 功能建议池 | `docs/功能建议池.md` | 展示 F9 第一轮 Demo 收口后可人工点名的新功能菜单；不是已采纳路线图 |
| AI 辅助开发机会清单 | `docs/AI辅助开发机会清单.md` | 展示不在运行时接 LLM、只利用 AI 辅助写代码 / 数据 / 工具时可参考的玩法、内容管线和开发工具机会；不是已采纳路线图 |
| 小服务器玩法备忘 | `docs/小服务器玩法备忘.md` | 展示小服务器条件下可参考的异步在线、敌巢进化、死亡残响、星域污染图等玩法；不是已采纳路线图 |
| 规则反例 | 当前平台规则入口的红线与自检清单 | 防止硬编码、裸字符串、绕过 autoload |

## 7. 维护规则

- 新增长期文档时，同时登记到 `docs/_kb_index.json`；可用目录条目覆盖一组同类长期文档。
- 删除或重命名长期文档时，同步本索引、机器索引、AI 导航和所有引用路径。
- 文档权威范围变化时，更新 `authority`、`owner_scope`、`canonical_for`、`must_read_for`、`related_docs`、`update_triggers`。
- 每次知识库结构变化后运行 `python tools/docs_health_check.py`。
