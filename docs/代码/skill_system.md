# SkillSystem / 四槽英雄技能模块

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是主／子英雄四技能、能量、能力属性缩放、通用效果原语、部署物和技能快照的权威运行时契约。

## 职责与边界

- `HeroCompositionResolver` 把主英雄的两个 `hero_skill_ids` 放入 `skill_1` / `skill_2`，把子英雄的两个技能放入 `skill_3` / `skill_4`；主英雄提供能力属性、被动和外观主体，子英雄不提供属性或被动。
- `SkillSystem.cast_slot(slot_id)` 管理四槽独立冷却、共享能量、目标筛选、效果解释和 Run v18 快照。冷却键永远是槽位，不是 skill id；技能与被动随所属英雄整包解锁，不建立独立资格。
- ADR #166 后 RunLoop 通过 `configure_combat_gate()` 注入起点房门禁；锁定时释放返回 `reason=combat_locked`，不消耗能量、不进入冷却，且技能必须松开后重新按键。
- 主英雄 `ability_strength` / `ability_range` / `ability_efficiency` / `ability_duration` 作用于全部四槽，但只缩放技能数据明确声明的参数。
- 技能行为只能由 `skill_effect_*` 通用原语、状态和按来源覆盖的属性修饰器表达；禁止按 hero id 或 skill id 写分支。
- 当前实现能量、屏障、范围状态、玩家／武器临时修饰器、伤害和状态原语；不实现局内换子英雄、技能轮盘、网络预测或组合专属技能。

## 代码与数据

| 路径 | 作用 |
|------|------|
| `client/scripts/data/hero_composition_resolver.gd` | 纯数据组合解析；局外拒绝同英雄，预留重复技能后槽成本与冷却 `1.5×` |
| `client/scripts/data/skill_value_resolver.gd` | 技能成本、目标范围、效果参数与能力属性缩放的纯数据单一实现；运行时和描述共用 |
| `client/scripts/data/skill_description_formatter.gd` | 把本地化命名占位符解析为配置与主英雄属性缩放后的显示值，不按技能 id 特判 |
| `client/scripts/gameplay/skill_system.gd` | 四槽、能量、缩放、目标、效果、部署物和快照 |
| `client/data/characters.json` | 英雄场景、配色、主属性、`passive_id`、两个 `hero_skill_ids` |
| `client/data/skills.json` | 成本、冷却、目标、效果、缩放声明和本地化 key |
| `client/scripts/gameplay/projectile_barrier.gd` | 可池化圆形投射物屏障 |
| `client/scripts/combat/status_effect*.gd` | 减速、加速、易伤、持续伤害和状态快照 |
| `client/scripts/contracts/skill_slots.gd` | 固定槽位 `skill_1`～`skill_4` |

## 运行流程

| 阶段 | 行为 |
|------|------|
| 组合解析 | `resolve(main_hero_id, sub_hero_id, allow_duplicate)` 返回场景、组合名参数、主／副色、主属性、被动和四个带槽位的技能定义 |
| 配置 | `configure(caster, active_parent, slot_definitions, resources)` 复制合法数据，能量以最大值开局且不自动回复 |
| 战斗门禁 | `configure_combat_gate(gate)` 保存返回 bool 的 Callable；门禁在资源、冷却和效果之前检查 |
| 输入 | `InputService` 的 `skill_1`～`skill_4` intent 分别调用同名槽位；Replay v8 记录相同归一化 intent |
| 释放 | 先校验 combat gate，再校验槽位、施法者、冷却、ability tag、能量和目标；成功后扣能量、解释效果，再设置该槽冷却 |
| tick | 仅 `GameState.PLAYING` 时通过 `GameClock.delta_scaled()` 推进冷却、临时修饰和状态 |
| 快照 | 保存四槽 skill id／冷却、能量、owned tags、状态和部署物；恢复前必须先完成组合配置 |
| 描述 | 英雄组合卡将 `tr(desc_key)` 交给 `SkillDescriptionFormatter`；技能数值按当前主英雄能力属性解析，被动参数直接读取 `hero_passives.json` |

## 公共 API

| API | 约束 |
|-----|------|
| `cast_slot(slot_id) -> Dictionary` | 正式释放入口；只接受生成的四个槽位 id，失败不消耗能量 |
| `configure_combat_gate(gate) -> void` | `false` 时所有槽位返回 `combat_locked`，不消耗资源或冷却；空 Callable 表示允许 |
| `cast_skill(skill_id) -> Dictionary` | 兼容／测试入口；正式业务应使用槽位 |
| `cooldown_remaining(slot_or_skill_id) -> float` | UI 使用槽位查询；skill id 查询只为兼容诊断 |
| `resource_amount()` / `resource_maximum()` / `add_resource()` | 共享资源门面；当前正式资源为 `energy` |
| `snapshot()` / `restore_snapshot()` | Run v18 的技能子快照；不保存 Node 引用，combat gate 由当前 RunLoop 重新注入 |
| `debug_set_free_casts()` / `debug_refresh()` / `debug_summary()` | Developer Test Arena 与 smoke 使用，不得成为正式玩法依赖 |
| `SkillValueResolver.scaled_*()` | 纯数据缩放 API；新增缩放规则时先改此处，`SkillSystem` 与描述自动共享 |
| `SkillDescriptionFormatter.format_skill()` / `format_passive()` | 接受译文模板与数据定义并返回完整描述；不负责 `tr()` 或语言选择 |
| `ProjectileBarrier.projectile_boundary_hit_fraction()` | 返回敌方投射物线段第一次跨越圆周边界的比例；同在圆内或同在圆外且不穿圆时返回 `-1` |

## 能力属性与能量

- 内部均用倍率，UI 显示百分比：强度 `0.25～4.0`、范围 `0.25～2.5`、持续 `0.25～3.0`、效率 `0.25～1.75`。
- `energy_cost_multiplier = clamp(2.0 - ability_efficiency, 0.25, 1.75)`；冷却不受效率影响。
- 重复组合本期不允许。解析器预留未来规则：相同 skill id 的后出现槽位成本和冷却都乘 `1.5`，两槽冷却仍独立。
- 敌人被玩家归因击杀后由 `RNG.drop` 以数据概率生成池化能量球；每球恢复 `25`。满能量不吸附、不拾取。

## 初始技能

| 槽位来源 | 技能 | 原语与缩放 |
|----------|------|------------|
| 冷静 1 | 静域屏障 | 脚下部署屏障；生命×强度、半径×范围；同槽仅一个，重施替换 |
| 冷静 2 | 镇静脉冲 | 范围×范围、减速幅度×强度且封顶 70%、时间×持续；最强减速生效并刷新 |
| 愤怒 1 | 怒意超频 | 玩家移速与武器射速幅度×强度、时间×持续；按来源／槽位覆盖并刷新 |
| 愤怒 2 | 激怒标记 | 范围×范围、时间×持续、成本受效率影响；敌人移速 +10% 刷新不叠加，易伤每次 +1 层、最多 5 层并刷新全层 |

减速和敌方移速强化同时存在时最终倍率相乘。易伤每层只放大 `team_player` 造成的直接或持续伤害 10%，不放大敌方、环境或友军伤害。

## 屏障契约

- `skill_effect_deploy_barrier` 取得 `projectile_barrier` 池对象；无自然持续时间，死亡、重施或世界清理时回池。
- 敌方投射物只在跨越屏障圆周时命中：外→内与内→外均扣屏障生命并销毁，内→内可正常命中盾内目标，外→外且不穿圆时不受影响。首个物理帧从射手开火位置而不是枪口位置开始扫掠，避免枪口偏移越过边界；玩家投射物完全忽略屏障。
- 不阻挡角色移动、敌人近战 / 冲撞 / 爆炸、环境伤害或范围伤害。快照保存位置、剩余／最大生命、半径和所属槽位。

## 数据与契约

- hero、passive、skill、slot、resource、targeting、effect、status、stack rule、ability tag、element 和 pool id 全部来自生成常量。
- DoT 使用 `element_id`、正 `magnitude` 与正 `tick_interval`；tick 仍走 `Combat.apply_damage()`。
- 临时修饰器必须带稳定 source key（通常为槽位），重施覆盖／刷新，禁止向数组重复追加。
- 玩家可见名称、说明和组合名模板全部走 `client/locale/strings.csv`。描述中的可调数值使用配置命名占位符；支持的 token 约定见 `client/locale/README.md`，`validate_data.py` 会拒绝配置无法解析的 token。

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 某技能键无效果 | gameplay context、`Actions.SKILL_1`～`SKILL_4`、槽位是否有 skill definition、GameState 是否为 PLAYING |
| `insufficient_resource` | 当前能量、主英雄效率、技能成本和重复槽倍率 |
| 冷却互相覆盖 | 快照与 `_cooldowns` 是否以 `skill_1`～`skill_4` 为键 |
| 范围／持续不缩放 | 技能 effect 参数是否显式声明对应 scaling |
| 描述显示 `{effect_...}` | `desc_key` token 是否对应实际 effect / modifier 参数，是否通过 `validate_data.py` |
| 描述数值与实际效果不一致 | 是否绕过 `SkillValueResolver` 另写了一套缩放；新增规则必须由运行时与描述共用 |
| 重施叠出多个 buff | 修饰器 source key 是否包含槽位，目标系统是否按来源覆盖 |
| 屏障跨界规则错误 | 屏障是否在 `active_deployables`，子弹是否为 `team_enemy`，首帧是否保留射手开火位置，圆内／圆外端点与线段求交是否一致 |
| 续局丢失技能／屏障 | Run v18 是否保存组合和 `skills` 快照；恢复是否先解析组合再恢复槽位 |
| 起点房技能仍消耗能量 | `configure_combat_gate()` 是否在技能初始化后接入；门禁是否在资源 / 冷却校验之前 |

## 测试义务

- 数据／契约：`sync_contracts.py --check`、`validate_data.py`、`test_data_loader_schema.py`、`lint_project_rules.py`；描述 token 必须覆盖无法解析的负例。
- 运行时：`lint_gdscript_rules.py`、`l1-smoke`、`runtime-smoke`、`loading-smoke`、`headless-boot`；L1 覆盖能力缩放后的格式化值，以及屏障内→内放行、内→外／外→内／外→外穿圆拦截、外→外同侧放行和枪口越界，Loading 覆盖组合卡不泄漏未解析 token。
- 输入／回放：`input-smoke`、`replay-input-smoke`、`replay-smoke` 与四条 Replay v8 黄金回放。
- 存档／世界重建：`save-smoke`、`module-world-smoke`；调试入口变更追加 `debug-test-arena-smoke` 和 release smoke。

## 迁移边界

当前 Meta v4、Run v18、Replay v8。ADR #194 后旧 Run v17 及更早版本与旧 Replay v7 明确不兼容；只删除旧 Run 并保留 Meta v4，不推断 Gear Mod 棋盘坐标。技能 `default_unlocked=false` 在本阶段为非法配置；局内换子英雄尚未实现，不得从预留的重复槽倍率推导出可用的切换入口。

## 相关文档

- `docs/代码/gameplay_runtime.md`
- `docs/代码/combat.md`
- `docs/代码/status_effect_component.md`
- `docs/代码/input_service.md`
- `docs/代码/save_manager.md`
- `docs/代码/replay.md`
- `client/data/README.md`
- `docs/词表与契约.md`
