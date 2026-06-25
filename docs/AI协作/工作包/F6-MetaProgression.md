# F6 MetaProgression 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F6 成长与局外循环的低 token 工作包；改 F6 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/AI记忆/current_state.json`。

---

## 目标

在 F4/F5 已有最小战斗、升级选择和暂停保存续局基础上，补齐第一版局外成长闭环：

- 一局结束进入结算，按 `client/data/meta_progression.json.run_rewards` 计算局外货币与账号经验。
- 建立 `MetaProgressionSystem`，负责读取局外成长配置、初始化新 `meta` 档案、应用结算奖励、购买永久升级和授予解锁。
- `meta` 状态通过 `SaveManager` 的 `meta` kind 可靠 roundtrip；`run` 存档在死亡 / 结算 / 放弃后删除或标记 consumed，不能重复结算刷奖励。
- 已购永久升级通过 `ModifierEngine` 或本阶段可复用的修正器入口影响下一局属性，禁止直接改 `player.json` / `characters.json` 基础值。
- 最小结算 / 局外成长 UI 只显示和操作 F6 验证必需信息；完整设置、本地化 UI 打磨、多页面成长树和商店式表现留给 F7+。

F6 的核心是“结算奖励 -> meta 存档 -> 下一局生效”的闭环，不是批量扩内容。

## 必读

1. `docs/AI协作/快速开工.md`
2. `docs/AI记忆/current_state.json`
3. 当前平台编码规则入口
4. `docs/正式项目工作规划.md` F6 段
5. `docs/游戏设计文档.md` §7.1 / §7.2 / §9.16
6. `docs/测试策略.md` §5.5 / §5.5-A / §7
7. `docs/代码文档规范.md`
8. `docs/代码/save_manager.md`
9. `docs/代码/gameplay_runtime.md`
10. `client/data/README.md` 的 `meta_progression.json` 与相关属性字段说明
11. `client/locale/README.md` 的 `meta_*` 文案规则
12. `client/data/meta_progression.json`
13. `docs/词表与契约.md` §1 / §6 / §13 / §14

只在新增公共 API、状态机语义不清、测试义务变化或需要新增约定字符串时，补读对应 ADR、`docs/修改建议.md` 和更完整的 GDD 段落。不要默认整篇加载。

## 建议拆分

1. **结算数据快照**：在 F4 runtime 收口一局结果字段，至少包含 `mode_id`、存活时间、击杀数、账号经验来源字段、局外货币来源字段和是否已结算标记。
2. **最小 `MetaProgressionSystem`**：新增 autoload 或明确挂载点，提供 `load_or_create_profile()`、`apply_run_settlement()`、`purchase_upgrade()`、`grant_unlocks()`、`current_modifiers()` 这类小而稳定的 API。
3. **`meta` 存档 roundtrip**：用 `SaveManager.save(slot_0, meta, payload)` / `load()` 保存货币余额、账号经验、账号等级、已购升级等级、已解锁 id 和累计统计；必要时注册 `meta` migration。
4. **结算 UI / 流程**：死亡后先进入结算面板，展示本局获得的局外货币 / 账号经验，再允许重开或回标题；结算完成后删除或 consume 对应 `run` 存档。
5. **永久升级最小入口**：先支持购买已有 `meta_progression.json.upgrade_tracks` 中的基础轨道，校验成本、等级上限和解锁条件；购买后立即保存并刷新显示。
6. **下一局属性注入**：开局时把已购升级转换为修正器并应用到运行时属性；如果正式 `ModifierEngine` 尚未落地，先做可替换的薄适配层并在模块文档标明后续迁移点。
7. **自动验证**：优先新增 headless smoke 或轻量测试，覆盖固定结算输入、单局奖励上限、购买扣款、重启后保留、下一局属性生效和 run 防重复结算。

## 可改文件

- `client/scripts/autoload/` 中的 `MetaProgressionSystem` 及必要 autoload 注册
- `client/scripts/gameplay/` 中 F4/F6 运行时结算、死亡流程、下一局属性注入和最小 UI
- `client/scenes/` 中 F6 必需的结算 / 局外成长场景
- `client/tools/` 与 `tools/godot_bridge.py`（新增 F6 smoke / meta smoke 入口）
- `client/data/meta_progression.json`（只改 F6 必需配置；字段变更同步 schema / 手册）
- `client/locale/strings.csv`
- `client/data/README.md`
- `client/locale/README.md`
- `docs/代码/save_manager.md`
- `docs/代码/gameplay_runtime.md`
- 历史落地时新增过 `docs/代码/meta_progression_system.md`；ADR #117 后该模块文档随旧运行时删除。后续只查 `docs/代码/gear_mod_system.md` / `docs/代码/save_manager.md` 处理 legacy 补偿。
- `docs/代码/README.md`
- `docs/AI导航.md`、`docs/AI记忆/current_state.json`、当日会话日志（收尾同步）

## 禁止事项

- 不把局外货币当作局内金币 / 商店资源；除非另有 ADR，局内资源和局外货币保持分离。
- 不在结算前的暂停保存退出路径发放局外奖励；“保存并退出”只写 `run`，不写 `meta` 奖励。
- 不允许同一个 `run` 存档重复结算；死亡、结算或放弃后必须清理或标记 consumed。
- 不直接修改 `player.json`、`characters.json` 或其他基础配置来表达永久升级；升级必须通过修正器 / runtime profile 注入。
- 不按 `upgrade_id` / `unlock_id` 写一次性硬编码分支；购买、解锁和修正器都从 `meta_progression.json` 与词表常量驱动。
- 不新增未登记的 `meta_currency` / `meta_upgrade` / `meta_unlock` / save kind；新增 id 先改 `docs/词表与契约.md` 并跑契约同步。
- 不把玩家偏好写进 `SaveManager` 的 `meta` kind；设置仍归 `Settings`。
- 不提前实现完整成长树、多页 UI、赛季、退款、挑战成就、云存档、反作弊或复杂商店表现。
- 不复活历史 MVP 临时代码；只能按正式项目模块边界重新实现可迁移经验。

## 验收命令

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
- `python tools/godot_bridge.py --project client save-smoke`
- F6 新增 smoke 命令（落地后补入本清单，例如 `python tools/godot_bridge.py --project client meta-smoke`）
- `python -m json.tool docs/AI记忆/current_state.json`
- `python -m json.tool docs/_kb_index.json`
- `python tools/docs_health_check.py`
- `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`

## 完成定义

- 正式 `client/` 能从一局死亡进入结算，并显示 / 保存本局获得的局外货币和账号经验。
- `MetaProgressionSystem` 能创建新 meta 档案、读取旧档案、应用结算、购买已有升级轨道并授予符合条件的 unlock。
- `SaveManager` 的 `meta` kind 能可靠保存 / 读取 F6 payload；若 schema 变化，迁移和测试同步到位。
- `run` 存档不会因死亡、结算或放弃被重复消费；暂停保存退出仍不会发放局外奖励。
- 已购永久升级能影响下一局运行时属性，且实现路径不修改基础数据文件。
- `client/data/README.md`、`client/locale/README.md`、`docs/代码/` 模块文档、`docs/AI导航.md` 与 AI 记忆同步。
- L0 / L2 / SaveManager smoke / F6 smoke 通过；若新增 `MetaProgressionSystem` 逻辑测试框架可用，则补对应 L1 测试。
