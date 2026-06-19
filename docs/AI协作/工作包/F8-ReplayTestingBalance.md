# F8 ReplayTestingBalance 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F8 回放 / 测试 / 平衡基线的低 token 工作包；改 F8 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/AI记忆/current_state.json`。

---

## 目标

在 F4/F5/F6/F7 的可玩闭环、存档续局、局外成长、设置 / 本地化 / UI 栈稳定化已经形成 smoke 覆盖后，把项目从“能跑、能回归 smoke”推进到“能用自动化测试和确定性回放保护后续内容扩展”：

- 建立 L1 单元测试落地路径，优先覆盖 `RNG`、`GameClock`、`GameState`、`SaveManager`、`Combat`、`ModifierEngine` 等高风险基础模块。
- 将现有 `Replay` autoload 从内存记录骨架推进到可用于黄金回放的文件格式、录制入口、重放 runner 和 diff 输出。
- 录制首批最小黄金回放：`golden_basic_run`、`golden_pause_resume`、`golden_full_death`，`golden_relic_synergy` 可等遗物运行时落地后再补。
- 建立基础 perf / 平衡采样入口，先输出可比较的指标，不急着实现完整 AIPlayer 或大规模 sim。
- 把 F4/F5/F6/F7 既有 headless smoke 纳入 F8 门禁，避免测试基线建设时破坏已验证路径。

F8 的核心是“回归安全网”，不是扩内容、调手感、重做 UI 或一次性实现完整平衡平台。

## 必读

1. `docs/AI协作/快速开工.md`
2. `docs/AI记忆/current_state.json`
3. 当前平台编码规则入口
4. `docs/正式项目工作规划.md` F8 段
5. `docs/测试策略.md`
6. `docs/CICD规划.md`
7. `docs/游戏设计文档.md` §9.9 / §9.10 / §9.18
8. `docs/代码文档规范.md`
9. `docs/代码/replay.md`
10. `docs/代码/rng.md`
11. `docs/代码/game_clock.md`
12. `docs/代码/game_state.md`
13. `docs/代码/save_manager.md`
14. `docs/代码/gameplay_runtime.md`
15. `docs/代码/combat.md`
16. `docs/词表与契约.md` 第 7 / 11 / 14 节

只在新增 action、RNG 子流、save kind、回放 schema、测试目录结构或 CI 门禁变化时，补读对应 ADR、词表完整段落和相关源码。不要默认整篇加载。

## 建议拆分

1. **F8 现状审计与测试目录定型**：盘点现有 `client/tools/` smoke、`Replay` / `RNG` / `GameClock` / `SaveManager` 能力和测试缺口；先确定 L1 测试目录、replay runner、perf probe 等命名是否沿用 `docs/测试策略.md`。
2. **L1 单测入口首片**：选择并接入 Godot 测试 runner；先用最小测试覆盖 `RNG` 同 seed 稳定、`GameClock` 暂停冻结、`GameState` 状态切换、`SaveManager` envelope / 迁移 / 坏档路径。若 runner 接入成本过高，先建立可在 headless 下执行的项目内测试脚本，但文档要标注它是临时 L1 runner。
3. **Replay 文件格式与录制开关**：明确 `.replay` schema、版本、game/data 指纹、seed、输入 action 序列、关键 decision 记录和结束摘要；受 `gameplay.record_replays` 控制，默认不污染存档。
4. **Replay 重放 runner 首片**：实现 `Replay` 重放入口和 `replay_runner`，先跑固定 seed 的短局，输出首个 diff 帧 / 字段；初期可只比较关键摘要（状态、等级、击杀、死亡 / 结算路径），再逐步收紧到帧级字段。
5. **首批黄金回放**：先录 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`；`golden_relic_synergy` 等遗物运行时 / 协同原语落地后再录，不为空造假。
6. **Perf / 平衡采样首片**：建立 `perf_probe` 或轻量 sim 输出：运行时长、帧时间、敌人 / 子弹 / pickup 池水位、击杀、等级、结算结果。F8 只要求可比较的 CSV / JSON，不要求完整 AIPlayer 胜率平台。
7. **门禁整合**：把新 L1 / replay / perf 命令接入本地验证说明；是否进入 pre-commit / CI 要分阶段，不把分钟级以上检查塞进秒级 hook。

## 可改文件

- `client/scripts/autoload/replay.gd`
- `client/scripts/autoload/rng.gd`
- `client/scripts/autoload/game_clock.gd`
- `client/scripts/autoload/game_state.gd`
- `client/scripts/autoload/save_manager.gd`
- `client/scripts/gameplay/` 中输入采样、快照摘要和测试钩子相关脚本
- `client/scripts/combat/` 与 `client/scripts/autoload/combat.gd`
- L1 测试目录（首片落地时再登记具体路径）
- `client/tools/` 中新增的 F8 smoke / test runner
- `tools/godot_bridge.py`（新增 F8 命令入口）
- 黄金回放目录（按最终目录决策创建并登记具体路径）
- `docs/代码/replay.md`
- `docs/代码/rng.md`
- `docs/代码/game_clock.md`
- `docs/代码/game_state.md`
- `docs/代码/save_manager.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/combat.md`
- `docs/测试策略.md`、`docs/CICD规划.md`
- `docs/AI导航.md`、`docs/AI记忆/current_state.json`、当日会话日志

## 禁止事项

- 不用回放系统绕过 `RNG` / `GameClock` / `GameState`；重放必须复用正式系统边界。
- 不在业务脚本里硬编码测试专用分支；需要测试钩子时用明确的 debug/headless-only 入口，并避免影响 release 行为。
- 不把玩家设置写入 `SaveManager`，也不把回放文件混进 `meta` / `run` 存档 kind。
- 不把黄金回放当作“有 diff 就自动覆盖”的快照；只有有意改变行为时才重录，并在提交说明中写明影响。
- 不提前做完整 AIPlayer / 千局平衡平台；先建立可验证的小 runner 和指标格式。
- 不把长耗时 replay / sim 检查塞进秒级 pre-commit；pre-commit 保持 Stage 1 快速门禁，重型检查进显式命令或后续 CI 阶段。
- 不扩展内容量来制造测试样例；测试样例应覆盖现有已落地玩法，遗物协同黄金回放等到对应运行时存在后再补。

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

F8 新增后追加：

- L1 单测 runner 命令（接入后写入本文）
- `python tools/godot_bridge.py --project client replay-smoke` 或等价 replay runner 命令
- `python tools/godot_bridge.py --project client perf-probe` 或等价 perf probe 命令

## 完成定义

- 项目有明确的 L1 测试执行入口，且至少覆盖 F8 首片指定的基础设施模块；文档说明本地如何跑。
- `Replay` 能保存 / 读取一条最小 `.replay`，并能在 headless runner 中重放到稳定摘要；失败时输出可定位的首个差异。
- 至少 `golden_basic_run`、`golden_pause_resume`、`golden_full_death` 中的一条进入版本库并能稳定通过；其余未完成项有明确原因和下一步。
- perf / 平衡采样能输出可比较指标，至少覆盖池水位、运行时长、击杀 / 等级 / 结算路径之一。
- F4/F5/F6/F7 既有 `runtime-smoke`、`save-smoke`、`meta-smoke`、`settings-smoke` 继续通过。
- `docs/测试策略.md`、`docs/CICD规划.md`、`docs/代码/` 模块文档、`docs/AI导航.md` 与 AI 记忆同步。
