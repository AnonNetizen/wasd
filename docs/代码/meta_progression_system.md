# MetaProgressionSystem 模块文档（Legacy）

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 F6 旧局外成长首切片的代码契约。ADR #115 后，未来跨局属性来源改为 `GearModSystem`；改旧 profile schema、迁移 / 补偿、结算兼容、购买规则或 `meta-smoke` 时必须同步本文档、AI 导航、SaveManager 文档、F6 工作包和 `docs/代码/gear_mod_system.md`。

> **Legacy 状态**：`MetaProgressionSystem` / `client/data/meta_progression.json` 不再作为未来下一局属性来源。F11 起，英雄 / 武器两套装备 Mod loadout、Mod 升级和分解资源由 `GearModSystem` 负责；本模块只保留旧档读取、迁移 / 补偿、回归诊断和必要的兼容 UI 参考。

## 职责

- `MetaProgressionSystem` 是旧局外成长运行时入口，负责读取 `client/data/meta_progression.json`，维护旧 `SaveManager` `meta` payload，并向玩法层输出旧永久升级 modifiers；ADR #115 后该输出路径应被替换为 `GearModSystem` 的 loadout modifier snapshot。
- F6 闭环“本局死亡结算 -> meta 存档 -> 标题菜单购买永久升级 -> 下一局应用 modifier”已经完成并通过手动验收；该闭环现在是 legacy 迁移来源，不再继续扩展为多页永久成长树。
- `SaveManager` 只负责 envelope、原子写入、备份和坏档隔离；`MetaProgressionSystem` 解释局外成长字段并做 profile 归一化。

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/meta_progression_system.gd` | `MetaProgressionSystem` autoload 脚本 |
| `client/data/meta_progression.json` | 局外货币、结算奖励、账号等级、升级轨道和解锁配置 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 玩家死亡时提交结算摘要；新开局时应用永久 modifiers |
| `client/scripts/ui/title_menu.gd` | 标题菜单账号等级 / 余额摘要，以及有可购买升级时的入口提示 |
| `client/scripts/ui/meta_progression_panel.gd` | 标题菜单进入的最小局外升级列表面板，显示可购买 / 余额不足 / 锁定 / 满级状态 |
| `client/scripts/ui/game_over_panel.gd` | F6 死亡结算展示、账号等级 / 余额、重开和回标题 |
| `client/tools/meta_progression_smoke.gd` | F6 headless smoke：meta roundtrip、结算、购买、modifier |
| `tools/godot_bridge.py` | `meta-smoke` 命令入口 |
| `docs/代码/gear_mod_system.md` | F11 装备 Mod 系统规划文档；新跨局成长入口 |

## 运行流程

| 阶段 | 发生什么 | 关键 API |
|------|----------|----------|
| 创建 / 读取 profile | 若 `slot_0/meta.save` 存在则加载并归一化；不存在则创建默认货币、默认解锁和统计字段并写入 `SaveManager` | `load_or_create_profile()` |
| 新局应用永久升级 | Legacy：F4 开局配置玩家和武器后读取已购买升级，转换为 `stat/type/value` modifiers 并传给玩家与武器；F11 实现后应改为读取 `GearModSystem` loadout snapshot | `current_modifiers()` |
| 死亡结算 | F4 玩家死亡时提交击杀数、存活时长和首领击杀标记；系统按数据配置计算局外货币与账号经验、更新等级奖励解锁并保存 meta | `apply_run_settlement()` |
| 清理 run | F4 在结算后删除 `run` 存档，避免死亡 / 结算后继续读旧局造成重复奖励 | `SaveManager.delete(slot_0, run)` |
| 购买升级 | 标题局外升级面板请求购买可负担升级；系统检查账号等级、当前等级、费用和余额，扣货币、提升等级、发放升级解锁并保存 meta | `purchase_upgrade()` |
| 标题摘要 | 标题菜单读取账号等级、主货币余额和首个可购买升级，用一行摘要解释当前局外成长状态；有可购买升级时入口按钮显示提示，关闭升级面板后刷新 | `profile_summary()` / `first_available_purchase()` |
| 标题局外升级 | 标题菜单打开 `MetaProgressionPanel`；面板显示账号等级、余额和所有升级轨道，用状态行 / 行颜色区分可购买、余额不足、锁定、满级，购买后刷新 profile、按钮状态和购买反馈 | `profile_summary()` / `upgrade_summaries()` / `purchase_upgrade()` |
| 死亡结算展示 | 死亡结算面板只展示本局获得货币 / 账号经验、账号等级、账号等级提升提示和余额，不显示购买或跳转局外成长入口 | `apply_run_settlement()` / `profile_summary()` |
| 自动验证 | `meta-smoke` 用合成结算验证货币公式、账号等级、解锁、购买扣费、modifier、标题升级面板和 SaveManager roundtrip；`runtime-smoke` 追加真实死亡结算断言 | `godot_bridge.py meta-smoke` / `runtime-smoke` |

## Profile Schema

`meta` payload 当前 schema version 为 1：

| 字段 | 类型 | 说明 |
|------|------|------|
| `schema_version` | `int` | `MetaProgressionSystem` 自身 payload schema，当前为 1 |
| `currencies` | `Dictionary` | currency id -> 数量；当前默认 `meta_essence` |
| `account_xp` | `int` | 累计账号经验 |
| `account_level` | `int` | 由 `account_level.thresholds` 推导，不由调用方手填 |
| `purchased_upgrades` | `Dictionary` | upgrade id -> 已购买等级 |
| `unlocked_ids` | `Array[String]` | 默认解锁、等级奖励和升级购买奖励的合集 |
| `stats` | `Dictionary` | `runs_settled`、`total_kills`、`total_run_time`、`total_currency_earned` |

归一化会补齐缺失字段、夹取货币上限、确保默认解锁存在，并按 XP 重新计算账号等级。首次创建 profile 会立即写入 `SaveManager`，使 `meta` kind 有真实 roundtrip。

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `load_or_create_profile(slot=slot_0)` | slot | profile `Dictionary` | 无存档时创建默认 profile；不会把“首次无文件”作为错误打印 |
| `save_profile(profile, slot=slot_0)` | profile、slot | `bool` | 写入前归一化；失败时通过 `SaveManager.last_error()` 诊断 |
| `apply_run_settlement(summary, slot=slot_0)` | `kills`、`run_time`、`first_boss_defeated` | 结算结果 `Dictionary` | 奖励公式完全来自 `meta_progression.json`；返回本局获得货币 / XP、结算前后账号等级和 profile；保存失败时 `ok=false` |
| `purchase_upgrade(upgrade_id, slot=slot_0)` | upgrade id | 购买结果 `Dictionary` | 只允许购买已解锁、未满级且余额足够的升级 |
| `current_modifiers(slot=slot_0)` | slot | `Array[Dictionary]` | 每条 modifier 只输出 `stat`、`type`、`value`，供 F4 玩家 / 武器复用现有成长管线 |
| `profile_summary(slot=slot_0)` | slot | profile 摘要 `Dictionary` | 供标题局外升级 UI 展示账号等级、账号经验和主货币余额，不暴露完整存档结构 |
| `debug_grant_currency(amount, slot=slot_0)` | amount、slot | 调试授予结果 `Dictionary` | 仅供 debug/dev_tools GM 指令使用；仍通过 profile 归一化和 `save_profile()` 写入 |
| `upgrade_summaries(slot=slot_0)` | slot | `Array[Dictionary]` | 供 UI 展示所有升级轨道的名称、描述、当前等级、费用、余额、解锁等级、可购买状态和不可购买原因 |
| `first_available_purchase(slot=slot_0)` | slot | 可购买项或空字典 | 供 smoke / 后续独立 UI 复用；当前失败结算面板不展示快捷购买 |
| `currency_name_key(currency_id)` | currency id | locale key | 供结算 UI 展示货币名 |

## 数据与契约

- currency / upgrade / unlock id 来自 `docs/词表与契约.md` §13 与生成常量；代码不得写未登记 id。
- 结算货币公式读取 `run_rewards.base_amount`、`per_minute_survived`、`per_50_kills`、`first_boss_bonus` 和 `max_amount_per_run`。
- 账号经验公式读取 `account_level.xp_per_minute_survived` 与 `xp_per_50_kills`；等级由 `thresholds` 推导，等级奖励读取 `level_rewards.unlock_ids`。
- 永久升级读取 `upgrade_tracks[].costs`、`max_level`、`unlock_condition.account_level`、`modifiers[].value_per_level` 和可选 `unlock_ids_by_level`。
- 当前配置已有 `damage` 与 `fire_rate` 等数据驱动永久属性轨道；ADR #115 后这类轨道进入 legacy，不再新增为未来成长内容。新跨局数值应做成 Gear Mod 定义。
- 玩家可见文案走 `client/locale/strings.csv`；F6 使用 `ui_meta_settlement`、`ui_meta_balance`、`ui_meta_account_level`、`ui_meta_account_level_up`、`ui_meta_title_summary`、`ui_meta_purchase_upgrade`、`ui_meta_purchase_unavailable`、`ui_meta_purchase_success`、`ui_meta_purchase_failed`、`ui_meta_progression`、`ui_meta_progression_available`、`ui_meta_progression_title`、`ui_meta_upgrade_level`、`ui_meta_upgrade_cost`、`ui_meta_upgrade_maxed`、`ui_meta_upgrade_locked`、`ui_meta_upgrade_insufficient`。

## 依赖

- 上游依赖：`DataLoader`、`SaveManager`、`meta_progression.json`、生成契约常量、locale。
- 下游调用方：`GameplayRunLoop`、`TitleMenu`、`GameOverPanel`、`MetaProgressionPanel`、`client/tools/meta_progression_smoke.gd`；`GameOverPanel` 只消费结算结果，不触发购买。
- 禁止依赖：不得直接写 `user://saves/`；不得绕过 `SaveManager`；不得修改 `player.json` 来表达永久成长；不得在 F4 里复制结算公式。

## 扩展点

- 旧档迁移 / 补偿：保留 `MetaProgressionSystem` 作为旧数据解释器，后续由迁移逻辑把已购买永久升级折算为 Gear Mod 升级资源、起始 Mod 或其他补偿。
- 新成长内容：不要再向 `meta_progression.json` 增加未来永久升级轨道；优先改 `gear_mods.json` / Gear Mod 数据与 `GearModSystem`。
- 新结算来源：向 `apply_run_settlement()` summary 增加 JSON 友好字段，并同步 GDD、测试策略和 smoke。
- profile 版本提升：更新 payload schema、添加迁移策略和 roundtrip 测试，同时评估是否需要提升 `SaveManager` 的 `meta` kind version。

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 死亡后没有 meta 存档 | `GameplayRunLoop._on_player_died()` 是否先调用 `apply_run_settlement()`；`SaveManager.last_error()` |
| 结算奖励异常 | `meta_progression.json.run_rewards` 数值；`meta-smoke` 期望公式是否同步 |
| 账号等级没提升 | `account_level.thresholds` 与合成 XP 是否匹配 |
| 死亡结算页没有等级提升提示 | `apply_run_settlement()` 是否返回 `previous_account_level` 与 `account_level`；`ui_meta_account_level_up` 是否已导入 `.translation`；`meta-smoke` 是否通过 GameOverPanel 账号进度断言 |
| 升级按钮不可用 | 余额、账号等级、`costs` 长度和 `max_level` |
| 购买后没有反馈或余额未刷新 | `MetaProgressionPanel._show_purchase_feedback()` 是否收到购买结果；`MetaProgressionSystem.purchase_upgrade()` 是否返回 `ok=true` 和新等级；`meta-smoke` 是否通过面板购买反馈断言 |
| 标题摘要或可购买提示不刷新 | `TitleMenu.refresh_meta_summary()` 是否调用 `profile_summary()` / `first_available_purchase()`；`FormalClientBoot._on_meta_progression_closed()` 是否在关闭升级面板后刷新标题菜单；`meta-smoke` 是否通过标题菜单摘要断言 |
| 升级行状态不清楚 | `MetaProgressionPanel` 是否生成 `MetaUpgradeStatus_<upgrade_id>` 状态行；`upgrade_summaries()` 是否提供 `reason`、`balance`、`cost` 和 `account_level_required`；`meta-smoke` 是否通过标题面板状态行断言 |
| 标题菜单看不到局外升级 | `TitleMenu` 是否有 `MetaProgressionButton`；`FormalClientBoot` 是否连接 `meta_progression_requested` 并 `UIManager.push()` `MetaProgressionPanel` |
| 死亡结算页出现购买或局外升级入口 | `GameOverPanel` 是否意外恢复购买 / 跳转按钮；`GameplayRunLoop` 是否重新连接失败页购买信号；`runtime-smoke` 是否通过失败页不显示局外成长入口断言 |
| 局外升级列表为空 | `MetaProgressionSystem.upgrade_summaries()` 是否返回配置轨道；`meta_progression.json.upgrade_tracks` 是否通过数据校验 |
| 下一局永久升级无效 | `current_modifiers()` 是否输出目标 stat；`GameplayRunLoop` 是否在玩家 / 武器 configure 后调用 `_apply_meta_modifiers()` |
| run 奖励可重复领取 | 死亡结算后是否删除 `run` 存档；`runtime-smoke` 是否通过“player death should consume the active run save”断言 |

## 测试义务

- 改本模块必跑：`python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/lint_gdscript_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、`python tools/godot_bridge.py --project client meta-smoke`。
- 改 `debug_grant_currency()` 或 GM 局外货币命令时，追加 `python tools/godot_bridge.py --project client debug-tools-smoke` 与 `python tools/godot_bridge.py --project client debug-tools-release-smoke`。
- 改标题入口、购买反馈或 `MetaProgressionPanel` 时追加 `meta-smoke`；当前 smoke 会检查标题面板升级列表、购买反馈、伤害升级状态行中的余额 / 下一档成本，以及新数据轨道购买后输出 `fire_rate` modifier。改死亡结算页展示时追加 `meta-smoke` 和 `runtime-smoke`，必要时手动从标题菜单点开“局外升级”确认按钮可见、购买后余额、等级和反馈刷新。
- 改 F4 结算接入、失败面板或新开局 modifier 应用时追加：`python tools/godot_bridge.py --project client runtime-smoke`。
- 改 SaveManager envelope / kind version 时追加：`python tools/godot_bridge.py --project client save-smoke` 和迁移测试。

## 迁移 / 兼容

当前 `meta` payload schema version 为 1，`SaveManager` 的 `meta` kind version 也为 1。`load_or_create_profile()` 会对缺字段旧档做温和归一化，但没有跨版本迁移；F11 删除或旁路旧字段时，必须新增显式迁移 / 补偿策略并更新 `SaveManager.CURRENT_KIND_VERSIONS` 或 `GearModSystem` 的 profile migration。

## 相关文档

- `docs/AI协作/工作包/F6-MetaProgression.md`
- `docs/AI协作/工作包/F11-GearModLoadout.md`
- `docs/游戏设计文档.md` §7.2 / §9.16
- `docs/代码/gear_mod_system.md`
- `docs/代码/save_manager.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/debug_tools.md`
- `docs/测试策略.md`
