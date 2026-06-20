# F9 ContentDemoPolish 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F9 内容扩展与 Demo 打磨的低 token 工作包；改 F9 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/AI记忆/current_state.json`。

---

## 目标

在 F4~F8 已经具备可玩闭环、暂停 / 存档 / 续局、局外成长、设置 / 本地化 / UI 栈和回放 / 性能基线后，F9 开始把项目从“工程闭环可跑”推进到“可演示、可试玩、内容稍厚且不脆”：

- 建立首批 Demo 内容切片：新增少量角色、武器、敌人、成长选项或局外升级，优先复用已有数据 schema 和运行时能力。
- 打磨当前核心手感：移动、射击、碰撞反馈、经验拾取、升级节奏、失败 / 重开 / 回标题路径和基础可读性。
- 补齐音频 / 美术占位规范，让新增内容有一致的临时表现，不把占位资产写死进逻辑。
- 以 F8 golden replay、smoke、perf-probe 和手动 checklist 保护内容扩展，避免内容变多后回归问题变隐蔽。
- 只在内容确实需要时新增可复用 primitive / runtime 能力；不要为某个 id 写特殊分支。

F9 的核心是“可试玩 Demo 的第一层内容和体验打磨”，不是无限堆数据、重做美术风格、做完整平衡平台、做商店页、做完整遗物协同系统或提前发版。

## 必读

1. `docs/AI协作/快速开工.md`
2. `docs/AI记忆/current_state.json`
3. 当前平台编码规则入口
4. `docs/正式项目工作规划.md` F9 段
5. `docs/AI导航.md` 第 4 节扩展点速查
6. `docs/测试策略.md` 中 L3 / L4 / L5、回放和性能预算相关段落
7. `docs/代码文档规范.md`
8. `docs/代码/gameplay_runtime.md`
9. `client/data/README.md`
10. `client/locale/README.md`
11. `docs/词表与契约.md` 与目标内容类型相关章节
12. 目标数据文件：`characters.json`、`weapons.json`、`enemies.csv`、`growth.csv`、`growth_pools.json`、`meta_progression.json`、`relics.json`、`active_items.json`、`consumables.json`、`hazards.csv`、`spawn_waves.csv`、`game_modes.json` 中本次会改的最小集合

只在新增 stat / effect / event / action / pool / audio id、修改运行时行为、改变回放 schema、改变存档 schema 或新增长期模块时，补读对应 GDD、ADR、模块文档和目标源码。不要为了“准备 F9”默认整篇加载 GDD 或批量扫全仓。

## 建议拆分

1. **F9.0 范围盘点与 Demo 内容清单**：先列出当前可复用内容、运行时已支持能力、不能做的内容类型和首批 Demo 目标。输出应是短清单，不直接改大量数据。
2. **F9.1 小内容首片**：优先新增 1 个低风险内容包，例如 1 个敌人变体 + 1 条刷怪波次 + 1~2 个成长候选，或 1 个武器数据变体 + 对应文案。只走数据 / locale / 验证；除非现有 runtime 无法表达，否则不改逻辑。
3. **F9.2 手感与可读性打磨**：围绕一次真实试玩修移动 / 射击 / 命中反馈 / 拾取节奏 / 升级提示 / 失败反馈。改动要小，能被 runtime-smoke、golden replay 或手动 checklist 描述。
4. **F9.3 Demo 表现占位规范**：为新增敌人、武器、拾取、UI 提示、SFX / BGM 等建立一致占位策略。若新增音频 id，先登记词表并走 `AudioManager`，不在业务脚本直接播放。
5. **F9.4 回归与性能守门**：每个内容切片至少跑数据 / locale 校验、相关 smoke、一条或四条 golden replay runtime rerun、`perf-probe`。有意改变核心运行时语义时才重录 golden，并说明行为差异。
6. **F9.5 Demo 手动 checklist**：形成可重复试玩清单，覆盖启动、语言切换、设置、开始游戏、升级、暂停保存、继续游戏、死亡结算、局外升级、回标题、重开和性能感受。

## 可改文件

- `client/data/characters.json`
- `client/data/weapons.json`
- `client/data/enemies.csv`
- `client/data/spawn_waves.csv`
- `client/data/growth.csv`
- `client/data/growth_pools.json`
- `client/data/meta_progression.json`
- `client/data/relics.json`
- `client/data/active_items.json`
- `client/data/consumables.json`
- `client/data/hazards.csv`
- `client/data/game_modes.json`
- `client/locale/strings.csv`
- `client/data/README.md`
- `client/locale/README.md`
- `docs/词表与契约.md` 与生成契约产物（仅新增白名单 id 时）
- `client/scripts/gameplay/` 中与手感、反馈、内容 primitive 直接相关的最小脚本
- `client/scripts/autoload/audio_manager.gd` 与音频注册相关文件（仅新增音频播放能力时）
- `client/assets/` 中占位资源或资源说明（需要资源时）
- `client/tests/replays/` 与 `client/tools/golden_replay_capture.gd`（只有行为语义改变或新增可复现场景时）
- `docs/代码/` 中被触碰模块的文档
- `docs/测试策略.md`、`docs/CICD规划.md`（只有门禁 / checklist 变化时）
- `docs/AI导航.md`、`docs/AI记忆/current_state.json`、当日会话日志

## 禁止事项

- 不批量新增几十条内容；每个切片必须能独立验证、独立回滚、独立说明玩家可感知价值。
- 不为具体角色 / 武器 / 敌人 / 遗物 id 写特殊分支；需要新能力时先抽象为 stat、effect、behavior、capability、tag、strategy 或 runtime primitive。
- 不新增玩家可见文本而漏 `zh_CN` / `en`；不把显示名写死在代码或数据外。
- 不新增可调数值字段而漏 `client/data/README.md`、DataLoader schema 和校验。
- 不复活历史 MVP 临时代码；只能迁移已经被正式文档 / ADR 吸收的经验。
- 不绕过 `RNG`、`GameClock`、`GameState`、`PoolManager`、`Combat`、`SaveManager`、`AudioManager`、`UIManager` 等既有系统边界。
- 不把内容扩展作为修测试快照的借口；golden replay 只有在行为有意改变并已说明时才重录。
- 不在 F9 第一轮就做完整 AIPlayer、完整商店、完整遗物协同、完整手柄重绑定、正式美术替换或发版工程。
- 不读取、整理、引用或修改 `draft/` / `DRAFT/`。

## 验收命令

基础门禁：

- `python tools/sync_contracts.py --check`
- `python tools/validate_data.py`
- `python tools/test_data_loader_schema.py`
- `python tools/lint_gdscript_rules.py`
- `python tools/lint_project_rules.py`
- `python tools/test_project_rules_lint.py`
- `python tools/lint_semantic_rules.py`
- `python tools/test_semantic_rules_lint.py`
- `python tools/godot_bridge.py --project client headless-boot`
- `python tools/godot_bridge.py --project client runtime-smoke`
- `python tools/godot_bridge.py --project client settings-smoke`
- `python tools/godot_bridge.py --project client meta-smoke`
- `python tools/godot_bridge.py --project client save-smoke`
- `python -m json.tool docs/AI记忆/current_state.json`
- `python -m json.tool docs/_kb_index.json`
- `python tools/docs_health_check.py`
- `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`

F8 基线守门（按改动风险选择，内容 / 手感变更建议至少跑四条 checked-in rerun 与 perf）：

- `python tools/godot_bridge.py --project client l1-smoke`
- `python tools/godot_bridge.py --project client replay-smoke`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_basic_run.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_pause_resume.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_full_death.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_level_up_choice.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client perf-probe`

手动 Demo checklist（每个 F9 可玩切片至少更新 / 复核一次）：

- 标题进入游戏，移动、瞄准、射击、拾取经验、升级选择正常。
- 暂停、设置、语言切换、返回游戏、保存退出、继续游戏正常。
- 死亡结算、局外成长摘要、标题局外升级入口、重开 / 回标题正常。
- 新内容可见、可理解、无裸 key、无明显重叠 / 遮挡 / 无法点击。
- 试玩 3~5 分钟无明显性能尖峰、对象池泄漏、卡死或无法退出状态。

## 完成定义

- F9 工作包、TODO、AI 导航、知识库索引、当前状态和会话日志都指向 F9，后续 AI 能低 token 接手。
- 首批 Demo 内容清单明确：哪些内容先做、哪些需要新 primitive、哪些明确延后。
- 第一批内容扩展仍遵守数据驱动、locale 双语、词表白名单、对象池、统一伤害、确定性和存档边界。
- F8 四条 golden replay、核心 smoke、数据 / 文档校验和 perf-probe 继续作为 F9 内容扩展的回归护栏。
- 手动 Demo checklist 有可执行条目，并在每次重要 F9 切片后记录结果。
