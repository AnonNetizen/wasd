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
| 查看 / 维护未来任务 | `docs/TODO.md`、`docs/AI记忆/current_state.json`、`docs/修改建议.md` | `docs/TODO.md`、必要时 current_state / 会话日志 / 修改建议 | `python tools/docs_health_check.py`；若改 JSON 同步跑 `python -m json.tool` |
| 启动 / 推进正式项目 | 当前阶段工作包；F3 默认 `docs/AI协作/工作包/F3-DataLoader.md`、`docs/AI记忆/current_state.json`、目标模块文档 | `client/`、模块文档、必要时 TODO / GDD / ADR / 词表 / 测试策略 | 按工作包验收命令运行；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；项目规则变化跑 `python tools/lint_project_rules.py`；语义风险检查跑 `python tools/lint_semantic_rules.py`；文档变化跑 `python tools/docs_health_check.py`；JSON 变化跑 `python -m json.tool` |
| 维护正式客户端启动骨架 | `client/README.md`、`docs/代码/formal_client_boot.md`、`docs/正式项目工作规划.md` F1 | `client/project.godot`、`client/scenes/boot/main.tscn`、`client/scripts/boot/formal_client_boot.gd`、AI导航、代码文档索引 | `python tools/godot_bridge.py headless-boot`、`python tools/godot_bridge.py export-tree`、`python tools/docs_health_check.py` |
| 维护 F2 autoload 骨架 | GDD §9.3~§9.19、`docs/代码/data_loader.md`、`docs/代码/rng.md`、`docs/代码/game_state.md`、`docs/代码/game_clock.md`、`docs/代码/settings.md`、`docs/代码/analytics.md`、`docs/代码/replay.md`、`docs/代码/pool_manager.md`、`docs/代码/save_manager.md`、`docs/代码/audio_manager.md`、`docs/代码/localization.md`、`docs/代码/ui_manager.md` | `client/scripts/autoload/`、`client/project.godot`、AI导航、代码文档索引、current_state | `python tools/godot_bridge.py headless-boot`、`python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/docs_health_check.py` |
| 加 / 改角色 | GDD §3.4、`client/data/README.md`、`docs/词表与契约.md` §12、`docs/AI导航.md` | `client/data/characters.json`、`client/locale/strings.csv`、必要时词表和模块文档 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py` |
| 加 / 改武器 | `client/data/README.md`、`docs/词表与契约.md` §8 / §9 / §10、`docs/AI导航.md` | `client/data/weapons.json`、`client/locale/strings.csv`、必要时角色 / 模式引用 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加 / 改游戏模式 | GDD §6.6、`client/data/README.md`、`docs/AI导航.md` | `client/data/game_modes.json`、资源池 / 权重 / 禁用列表、必要时词表和模块文档 | `python tools/docs_health_check.py`；`python tools/validate_data.py` |
| 加遗物 / 道具 | `client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §1 / §2 / §3 / §12、`docs/AI协作/任务模板/加遗物.md` | `client/data/relics.json`、`client/locale/strings.csv`、必要时词表、模式引用和效果原语 | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；schema 变化跑 `python tools/test_data_loader_schema.py` |
| 加敌人 | `docs/AI协作/任务模板/加敌人.md`、`client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §8/9/12、GDD 敌人章节 | `client/data/enemies.csv`、`client/locale/strings.csv`、`game_modes` 敌人池、必要时行为 primitive | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 加 / 改机关 | `client/data/README.md`、`client/locale/README.md`、`docs/词表与契约.md` §8/9/12、`docs/AI导航.md` | `client/data/hazards.csv`、`client/locale/strings.csv`、`game_modes` 机关池、必要时地图 / 机关 primitive | `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 加 / 改刷怪波次 | `client/data/README.md`、GDD §5.3 / §9.3、`docs/AI导航.md` | `client/data/spawn_waves.csv`、DataLoader schema、必要时 Spawner 模块文档 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 改输入 / 手柄 | `docs/游戏设计文档.md`、`docs/词表与契约.md` 第 7 节、`docs/测试策略.md` | GDD、词表、规则、Settings/InputMap 代码、AI导航 | `python tools/docs_health_check.py`；代码落地后跑 headless + 手动输入回归 |
| 改经验 / 升级系统 | `docs/游戏设计文档.md` §7.1、`docs/词表与契约.md`、`docs/测试策略.md` | `GrowthSystem`、升级 UI、GDD、词表、AI导航、必要时 `docs/修改建议.md` | `python tools/docs_health_check.py`；代码落地后固定 seed 验证默认 3 选 1 与 `luck` 概率 4 选 1 |
| 改局外成长 / 元进度 | `docs/游戏设计文档.md` §7.2、`client/data/README.md`、`docs/词表与契约.md` §13、`docs/测试策略.md` | `client/data/meta_progression.json`、locale、GDD、词表、AI导航、必要时 SaveManager / MetaProgressionSystem 模块文档 | `python tools/sync_contracts.py --check` + `python tools/validate_data.py`；代码落地后跑 MetaProgressionSystem 单测和存档 roundtrip |
| 改存档 / 暂停退出续局 | `docs/游戏设计文档.md` §9.16、`docs/词表与契约.md` §14、`docs/测试策略.md` | SaveManager、GameState、暂停菜单、主菜单、GDD、词表、AI导航、模块文档 | SaveManager 单测、run roundtrip、损坏 / 迁移测试；代码落地后跑 headless 和手动存档 checklist |
| 调完整项目数值 | `client/data/README.md`、目标 `client/data/*.csv` / `client/data/*.json`、`docs/词表与契约.md` | 数据 CSV / JSON、数值手册、必要时 GDD / 模块文档 / 黄金回放 | `python tools/validate_data.py`；大改动跑回放 / 平衡验证 |
| 加完整项目文案 / 语言 | `client/locale/README.md`、`client/locale/strings.csv`、`docs/词表与契约.md` §6 | 文案 CSV、语言设置、相关 UI / 数据模块文档；AI 自动补齐 `zh_CN` / `en` 另一语言首版译文 | `python tools/validate_data.py`；人工切语言回归 |
| 改致谢 / 第三方来源 | `CREDITS.md`、`client/data/README.md`、`client/locale/README.md` | `client/data/credits.json`、`client/locale/strings.csv`、DataLoader schema、AI导航、必要时 ADR / 记忆 | `python tools/validate_data.py`；DataLoader schema 变化跑 `python tools/test_data_loader_schema.py`；文档变化跑 `python tools/docs_health_check.py` |
| 改规则 / 红线 | `AGENTS.md`、当前平台规则入口、`docs/决策记录.md`、`docs/AI协作/文档维护指南.md` | `AGENTS.md`、三平台规则、`CODEX.md`、`OPENCODE.md`、AI导航、项目记忆 | `python tools/docs_health_check.py`、`git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"` |
| 改约定字符串 | `docs/词表与契约.md`、`docs/AI协作/文档健康检查.md` | 词表、生成常量、相关数据 / 代码、AI导航 | `python tools/sync_contracts.py` + `python tools/sync_contracts.py --check`；`python tools/validate_data.py`；`python tools/docs_health_check.py` |
| 写/改代码模块 | `docs/代码文档规范.md`、对应 `docs/代码/<module_id>.md`、目标源码；触碰 `.gd` 时遵循 [Godot 官方 GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)；测试相关时读 `docs/测试策略.md` 相关段 | 代码、模块文档、AI导航依赖图、必要时 GDD / ADR | 对应测试义务 + `python tools/docs_health_check.py` |
| 写/改测试 | `docs/测试策略.md`、对应模块文档 | 测试文件、测试策略、必要时 CI 规划 | 对应测试命令；`python tools/docs_health_check.py` |
| 加 GM 指令 / 调试工具 | `docs/游戏设计文档.md` §9.20、`docs/词表与契约.md` §7、`docs/测试策略.md` §5.10 | DebugConsole / GMCommandRegistry、InputMap action、导出 preset、AI导航、ADR、测试策略 | debug/dev_tools 构建验证命令可用；release 构建确认无入口 / 无调试资源；`python tools/sync_contracts.py --check`、`python tools/docs_health_check.py` |
| 更新 AI 工具入口 | `AGENTS.md`、`docs/AI协作/工具适配指南.md`、`docs/AI协作/角色分工.md` | `CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、`.codebuddy/`、`.codex/`、`.opencode/` | `python tools/docs_health_check.py`；改 `.opencode/` 后验证 JSON |
| 健康检查 / CI | `docs/AI协作/文档健康检查.md`、`docs/CICD规划.md` | `tools/docs_health_check.py`、`tools/validate_data.py`、`tools/test_data_loader_schema.py`、`tools/lint_gdscript_rules.py`、`tools/lint_project_rules.py`、`tools/lint_semantic_rules.py`、`tools/sync_contracts.py`、健康检查命令、CI / pre-commit 规划 | `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/lint_project_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/docs_health_check.py`、`python -m json.tool docs/_kb_index.json` |
| 评估 / 安装 AI skills / MCP / agent-harness 资源 | `docs/AI协作/AI技能资源评估.md`、`docs/AI协作/上下文预算.md`、`CODEX.md`、`OPENCODE.md`、`.opencode/opencode.json`；ECC 类大仓追加 `docs/AI协作/ECC工具吸收清单.md` | `.codebuddy/skills/`、`.codex/skills/`、`.opencode/skills/`、`.opencode/opencode.json`、工具适配指南、AI导航、AI记忆、CREDITS、来源专属吸收清单 | `python -m json.tool .opencode/opencode.json`、`python tools/docs_health_check.py`、`git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`；新增或吸收资源时确认三平台同步、不重复、不引入外部 hooks / plugin / vendor reference 层，并运行 `ai-resource-curator` 的 AI surface audit |
| 调整 AI 开工 / 上下文预算 | `docs/AI协作/快速开工.md`、`AGENTS.md`、平台入口、`docs/AI协作/上下文预算.md`、`docs/AI协作/文档维护指南.md` | `CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、三平台规则、AI导航、工具适配指南、知识库索引、AI记忆 | `python -m json.tool docs/_kb_index.json`、`python -m json.tool docs/AI记忆/current_state.json`、`python tools/docs_health_check.py`、`git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"` |
| 新增 / 维护阶段工作包 | `docs/AI协作/工作包/<阶段>.md`、`docs/AI协作/上下文预算.md`、目标模块文档 | AI协作 README、AI导航、知识库索引、current_state、会话日志 | `python tools/docs_health_check.py`、`python -m json.tool docs/_kb_index.json` |

## 5. ADR 追踪矩阵

| ADR 范围 | 主题 | 主要同步文件 |
|----------|------|--------------|
| #1~#12 | 基础玩法、数据驱动、AI 友好工程 | GDD、规则、AI导航、README |
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
| #69 | 大型代码改动提交前自动事实 review | AGENTS、CLAUDE、CODEX、OPENCODE、三平台规则、角色分工、工具适配指南、AI技能资源评估、README、CONTRIBUTING、AI导航、AI记忆 |
| #70 | DataLoader schema 回归测试进入 Stage 1 CI | `tools/test_data_loader_schema.py`、`.github/workflows/docs-check.yml`、`docs/CICD规划.md`、`docs/AI协作/实时验证回路.md`、`docs/测试策略.md`、`docs/代码/data_loader.md`、F3 工作包、AI导航、AI记忆 |
| #71 | 双致谢清单 / 游戏内 Credits 数据源 | `CREDITS.md`、`client/data/credits.json`、`client/data/README.md`、`client/locale/strings.csv`、`docs/代码/data_loader.md`、AI导航、AI记忆 |
| #72 | ECC 外部 agent-harness 资源吸收边界 | `docs/AI协作/AI技能资源评估.md`、三平台 `ai-resource-curator` skill、CLAUDE、CODEX、OPENCODE、AI导航、AI协作 README、CREDITS、AI记忆 |
| #73 | ECC README 与全工具面吸收清单 | `docs/AI协作/ECC工具吸收清单.md`、`docs/AI协作/AI技能资源评估.md`、三平台 `ai-resource-curator` skill、上下文预算、AI导航、知识库索引、AI记忆 |
| #74 | Godot 4.6 官方 GDScript style guide 成为项目代码风格基线 | 三平台规则、三平台 `godot-gdscript` skill、AI导航、代码文档规范、CREDITS、AI记忆 |
| #75 | MVP 隔离目录移除 | README、GDD、AI导航、知识库索引、三平台规则 / skills / commands、工具脚本、AI记忆 |
| #76 | 第一档 GDScript 项目 lint 进入 Stage 1 CI | `tools/lint_gdscript_rules.py`、`.github/workflows/docs-check.yml`、三平台规则 / commands、CICD规划、测试策略、实时验证回路、AI导航、AI记忆 |
| #77 | 第二档项目规则 lint 进入 Stage 1 CI | `tools/lint_project_rules.py`、`tools/test_project_rules_lint.py`、`.github/workflows/docs-check.yml`、三平台规则 / commands、CICD规划、测试策略、实时验证回路、AI导航、AI记忆 |
| #78 | 第三档语义 advisory lint 进入 Stage 1 CI | `tools/lint_semantic_rules.py`、`tools/test_semantic_rules_lint.py`、`.github/workflows/docs-check.yml`、三平台规则 / commands、CICD规划、测试策略、实时验证回路、AI导航、AI记忆 |

新增 ADR 时必须判断是否要扩展本矩阵。

## 6. 示例与反例

| 类型 | 路径 | 用途 |
|------|------|------|
| 正式项目启动模块文档 | `docs/代码/formal_client_boot.md` | 展示 F1 最小启动骨架的职责边界、场景结构与验证方式 |
| 正式项目 autoload 模块文档 | `docs/代码/data_loader.md` / `rng.md` / `game_state.md` / `game_clock.md` / `settings.md` / `analytics.md` / `replay.md` / `pool_manager.md` / `save_manager.md` / `audio_manager.md` / `localization.md` / `ui_manager.md` | 展示 F2 基础设施模块的 API、依赖与测试义务 |
| 规则反例 | 当前平台规则入口的红线与自检清单 | 防止硬编码、裸字符串、绕过 autoload |

## 7. 维护规则

- 新增长期文档时，同时登记到 `docs/_kb_index.json`；可用目录条目覆盖一组同类长期文档。
- 删除或重命名长期文档时，同步本索引、机器索引、AI 导航和所有引用路径。
- 文档权威范围变化时，更新 `authority`、`owner_scope`、`canonical_for`、`must_read_for`、`related_docs`、`update_triggers`。
- 每次知识库结构变化后运行 `python tools/docs_health_check.py`。
