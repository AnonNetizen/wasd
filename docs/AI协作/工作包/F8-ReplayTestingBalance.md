# F8 ReplayTestingBalance 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F8 回放 / 测试 / 平衡基线的低 token 工作包；改 F8 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/AI记忆/current_state.json`。

---

## 目标

在 F4/F5/F6/F7 的可玩闭环、存档续局、局外成长、设置 / 本地化 / UI 栈稳定化已经形成 smoke 覆盖后，把项目从“能跑、能回归 smoke”推进到“能用自动化测试和确定性回放保护后续内容扩展”：

- 建立 L1 单元测试落地路径，优先覆盖 `RNG`、`GameClock`、`GameState`、`SaveManager`、`Combat`、`ModifierEngine` 等高风险基础模块。
- 将现有 `Replay` autoload 从内存记录骨架推进到可用于黄金回放的文件格式、录制入口、重放 runner 和 diff 输出。
- 录制首批最小黄金回放：`golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_level_up_choice`，`golden_relic_synergy` 可等遗物运行时落地后再补。
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
2. **L1 单测入口首片**：已先建立可在 headless 下执行的临时 L1 runner：`python tools/godot_bridge.py --project client l1-smoke`，覆盖 `RNG` 同 seed / snapshot、`GameClock` 暂停冻结、`GameState` 状态登记、`SaveManager` run roundtrip 和 `Combat` 单入口。后续接入 GUT 时再迁移 / 扩展为正式 L1。
3. **Replay 文件格式与录制开关**：已补 `.replay` envelope schema、版本、game/data 指纹、seed、输入 action 序列、关键 decision 记录和结束摘要；`python tools/godot_bridge.py --project client replay-smoke` 覆盖最小录制、保存 / 读取和摘要 roundtrip。
4. **Replay 重放 runner 首片**：已建立 `python tools/godot_bridge.py --project client replay-runner`，当前先读取 `.replay` envelope、校验 `recording_hash` / data fingerprint，并比较稳定 summary；失败时输出首个字段级 diff。带 `--rerun-runtime-summary` 时可按 replay seed 启动真实 `GameplayRunLoop`、按 tick 播放 `input_events`，并比较 `run_summary` 与 `run_summary.frame_samples` 稳定帧样本；未传 replay 文件时会生成临时输入播放 smoke replay。它仍是 L3 runner 外壳，不声称已完成全量逐帧复现。
5. **Gameplay 输入录制首片**：已建立 `python tools/godot_bridge.py --project client replay-input-smoke`，当前启动真实 `GameplayRunLoop`，确认移动 / 瞄准状态变化和 `pause` / `ui_back` 离散输入能进入 `Replay.input_events`。它只证明录制路径已接入；输入播放与稳定帧样本 diff 首片由 `replay-runner --rerun-runtime-summary` 覆盖。
6. **首批黄金回放**：已入库 `client/tests/replays/golden_basic_run.replay`、`client/tests/replays/golden_pause_resume.replay`、`client/tests/replays/golden_full_death.replay` 与 `client/tests/replays/golden_level_up_choice.replay`，由 `python tools/godot_bridge.py --project client capture-golden-replay` 通过真实 `GameplayRunLoop` 生成。`golden_basic_run` 覆盖固定 seed 180 帧的运行时摘要与 30 帧间隔稳定帧样本；`golden_pause_resume` 覆盖 pause 输入打开暂停菜单、`ui_back` 恢复运行、`ui_stack` 清空和帧样本状态变化；`golden_full_death` 通过 replay `runtime_events` 在工具层调用正式 `Combat` 路径，覆盖玩家死亡、GameOverPanel、run 存档删除与 meta 结算存档；`golden_level_up_choice` 通过真实经验球收集与 `LevelUpPanel.choose_index()` 覆盖升级候选 decision 记录、稳定候选顺序、选择 id 和修正应用。当前帧样本已扩展到玩家生命、右移语义、武器冷却是否就绪、敌人类型和掉落存在性；精确玩家坐标仍因帧时机敏感而不纳入稳定样本。`golden_relic_synergy` 等遗物运行时 / 协同原语落地后再录，不为空造假。
7. **RNG 子流相关性审计**：已建立 `python tools/godot_bridge.py --project client rng-audit`，用 10,000 个 run seed 检查默认 6 个 RNG 子流前 4 次 `randf()` 的 Pearson 相关性，最大绝对相关阈值为 0.06；改 seed mixer、子流集合或 Godot RNG 基线时必须跑。
8. **Perf / 平衡采样首片**：已建立 `python tools/godot_bridge.py --project client perf-probe`，当前输出 schema v2 可比较基线 JSON：`baseline_id`、固定场景 / seed、30 帧 warmup 后 180 帧采样、avg / p95 / p99 / max 帧时间、active / peak entity counts、pool final stats / peak active 和 `budget_status`。F8 只要求可比较的 CSV / JSON，不要求完整 AIPlayer 胜率平台。
9. **门禁整合**：把新 L1 / replay / RNG audit / perf 命令接入本地验证说明；是否进入 pre-commit / CI 要分阶段，不把分钟级以上检查塞进秒级 hook。

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
- `client/tools/rng_audit.gd`
- `tools/godot_bridge.py`（新增 F8 命令入口）
- `client/tests/replays/` 黄金回放目录
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
- 历史 `meta-smoke` 已按 ADR #117 退役；涉及当前跨局成长 / legacy 补偿时跑 `python tools/godot_bridge.py --project client gear-mod-smoke`
- `python tools/godot_bridge.py --project client save-smoke`
- `python -m json.tool docs/AI记忆/current_state.json`
- `python -m json.tool docs/_kb_index.json`
- `python tools/docs_health_check.py`
- `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`

F8 新增后追加：

- `python tools/godot_bridge.py --project client l1-smoke`
- `python tools/godot_bridge.py --project client replay-smoke`
- `python tools/godot_bridge.py --project client replay-runner`
- `python tools/godot_bridge.py --project client replay-runner --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client replay-input-smoke`
- `python tools/godot_bridge.py --project client capture-golden-replay`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_basic_run.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario golden_pause_resume`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_pause_resume.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario golden_full_death`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_full_death.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client capture-golden-replay --golden-scenario golden_level_up_choice`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_level_up_choice.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client rng-audit`
- `python tools/godot_bridge.py --project client perf-probe`

## 完成定义

- 项目有明确的 L1 测试执行入口，且至少覆盖 F8 首片指定的基础设施模块；文档说明本地如何跑。
- `Replay` 能保存 / 读取一条最小 `.replay`，并能在 headless runner 中对照稳定摘要；失败时输出可定位的首个差异。当前还可对 `golden_basic_run.replay`、`golden_pause_resume.replay`、`golden_full_death.replay` 与 `golden_level_up_choice.replay` 重跑真实运行时摘要与扩展稳定帧样本 / 场景语义字段，已录制首批 gameplay 输入事件，并能在 runner 内播放输入事件和工具层 runtime 事件；后续再扩更多场景。
- 至少 `golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_level_up_choice` 中的一条进入版本库并能稳定通过；当前四条均已入库并通过 runner runtime rerun，更多输入场景和遗物协同等后续场景仍待补。
- `rng-audit` 能在 headless 下检查默认 RNG 子流之间的早期 roll 相关性，防止 seed 派生改动引入可预测跨流关联。
- perf / 平衡采样能输出可比较指标，当前 `perf-probe` schema v2 已覆盖 warmup 后帧时间分布、池终态 / 峰值水位、实体峰值、运行时长、击杀、等级和预算状态。
- F4/F5/F7/F11 既有 `runtime-smoke`、`save-smoke`、`settings-smoke`、`gear-mod-smoke` 继续通过。
- `docs/测试策略.md`、`docs/CICD规划.md`、`docs/代码/` 模块文档、`docs/AI导航.md` 与 AI 记忆同步。
