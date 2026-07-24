# SkillSystem / 轻量 GAS 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是局内主动技能与项目版轻量 GAS 运行时契约；改技能释放、ability tag、目标筛选、资源消耗、效果解释、run 快照或 `skills.json` schema 时，必须同步 Gameplay Runtime、DataLoader、GDD、AI 导航、测试策略和词表。

## 职责

- 提供项目版轻量 GAS 首片：技能定义不绑定英雄，角色、主动道具、局外奖励或未来其他系统都应通过 skill id 引用同一份 ability 数据。
- 从 `client/data/skills.json` 读取技能定义，解释 `ability_tags`、`activation`、`costs`、`targeting` 和 `effects`；当前内置 `skill_overdrive_rounds`，定位为射击强化技能。
- 管理技能冷却、角色声明的技能资源池、资源自然回复、owned ability tags、释放结果和 run 快照。
- 目标筛选使用统一 target primitive，伤害效果统一走 `Combat.apply_damage(DamageInfo)`，武器强化效果通过目标 `WeaponSystem.apply_temporary_modifiers()` 临时修改射击属性。
- 当前首片只接默认角色的起始技能列表，用 `use_active_item` action 触发列表第一个主技能；默认主键释放 `skill_overdrive_rounds`，短时提高主武器射速与弹速。主动道具栏、技能 UI、GameplayCue 表现层、技能音效 / 特效、指向点选、队友实体、长通道技能、多技能轮盘和网络预测 / 复制尚未实现。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 加 / 调一个技能 | `client/data/skills.json`、`client/data/README.md` 的 `skills.json` 段 |
| 改技能 id、资源、目标类型、效果原语或 ability tag | `docs/词表与契约.md` §12-C~12-G、`tools/sync_contracts.py` |
| 改释放逻辑或资源消耗 | `client/scripts/gameplay/skill_system.gd` |
| 改默认角色起始技能 / 资源池 | `client/data/characters.json` |
| 改模式可用技能池 | `client/data/game_modes.json` |
| 改运行时挂载、快照、debug smoke | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/tools/runtime_smoke.gd` |
| 改 schema 校验 | `client/scripts/autoload/data_loader.gd`、`tools/validate_data.py`、`tools/test_data_loader_schema.py` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/skill_system.gd` | 技能运行时，负责配置、释放、冷却、资源、目标筛选、效果解释和快照 |
| `client/scripts/combat/status_effect.gd` / `status_effect_component.gd` | 状态效果 Resource 与组件；SkillSystem 自身、Player 和 Enemy 都可作为状态宿主承载 ability tag 生命周期 |
| `client/data/skills.json` | 技能定义表：成本、目标、效果、冷却和本地化 key |
| `client/data/characters.json` | 角色起始携带 `starting_loadout.skill_ids` 与 `skill_resources` |
| `client/data/game_modes.json` | 模式资源池 `resource_pools.skills` |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 开局挂载 SkillSystem，存 / 读 run 快照，暴露 smoke 用 debug API |
| `client/scripts/contracts/skill_ids.gd` / `skill_resources.gd` / `skill_targeting.gd` / `skill_effects.gd` / `ability_tags.gd` / `status_effects.gd` / `status_stack_rules.gd` | 由词表生成的技能 / 状态 / ability 常量 |
| `client/tools/l1_smoke.gd` | L1 临时 runner，覆盖技能 AOE primitive、Combat 路由、魔法消耗、冷却阻断、`ability_tag_silenced` 阻断、沉默状态过期与恢复，以及非燃烧 DoT 状态组件回归 |
| `client/tools/runtime_smoke.gd` | 正式运行时 smoke，覆盖默认角色释放过载弹流、消耗资源并临时强化武器 |

## 运行流程

| 阶段 | 发生什么 | 关键 API |
|------|----------|----------|
| 开局配置 | `GameplayRunLoop` 读取默认角色 `starting_loadout.skill_ids`，从 `skills.json` 找到技能定义，并把角色 `skill_resources` 传入 SkillSystem | `configure(caster, active_parent, skills, resources)` |
| 常规 tick | `PLAYING` 状态下用 `GameClock.delta_scaled()` 推进冷却与资源回复；暂停、升级选择和 game over 不推进 | `_physics_process()` |
| 输入释放 | `use_active_item` action 在 `PLAYING` 中触发主技能；事件写入 Replay 的输入事件首片 | `_unhandled_input()`、`cast_primary_skill()` |
| 释放判定 | 依次校验技能存在、施法者有效、冷却、activation required / blocked tags、资源是否足够、目标是否存在 | `cast_skill(skill_id)` |
| 资源与冷却 | 命中释放前不消耗资源；找到目标后先扣成本，授予激活期临时 tags，应用效果，移除临时 tags，最后写入冷却 | `_pay_costs()`、`_add_transient_tags()`、`_cooldowns` |
| 目标筛选 | `aoe_enemies_around_caster` 选择施法者半径内 `active_enemies`，按距离和 instance id 稳定排序；`target_enemy` 取最近敌人；`target_ally` 当前返回施法者 | `_targets_for_skill()` |
| 效果解释 | `skill_effect_damage` 为每个目标创建 `DamageInfo` 并交给 Combat；`skill_effect_apply_status` 构造 `StatusEffect` 并交给目标实体的 `apply_status_effect()`；`skill_effect_weapon_modifiers` 将临时 modifiers 交给目标 `WeaponSystem` | `_apply_damage_effect()`、`_apply_status_effect()`、`_apply_weapon_modifiers_effect()` |
| 状态 tick | SkillSystem 自带 `StatusEffectComponent` 处理释放者自身状态；Player / Enemy 目标由各自状态组件在 `PLAYING` 下随 `GameClock` 过期并释放状态授予的 tags | `apply_status_effect()`、`Player.apply_status_effect()`、`Enemy.apply_status_effect()`、`StatusEffectComponent._physics_process()` |
| 快照恢复 | run payload 保存 `cooldowns`、`resources.current`、owned ability tag 计数与状态效果快照，续局后只恢复已配置资源、技能、状态和已登记 tag 的合法字段 | `snapshot()`、`restore_snapshot()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(caster, active_parent, skills, resources)` | 施法者、活跃世界父节点、技能定义数组、资源定义数组 | `void` | 外部可传普通 `Array`，内部会复制并规范化字典；技能和资源必须已通过 DataLoader schema |
| `cast_primary_skill()` | 无 | `Dictionary` | 释放配置列表第一个技能；无技能返回 `reason=no_skill` |
| `cast_skill(skill_id)` | 技能 id | `Dictionary` | 返回 `ok`、`reason`、`target_count`、`applied_targets`、`resources`、`cooldown`；失败不扣资源 |
| `cooldown_remaining(skill_id)` | 技能 id | `float` | smoke / UI 只读诊断 |
| `resource_amount(resource_id)` | 资源 id | `float` | 用于 UI / 调试读取当前资源 |
| `resource_snapshot()` | 无 | `Dictionary` | 深拷贝；调用方不得修改内部缓存 |
| `add_owned_tag(tag_id)` / `remove_owned_tag(tag_id)` | ability tag id | `bool` | 只接受词表 §12-G 已登记 tag；当前 StatusEffect / smoke 可用来授予沉默，未来遗物 / GM 可复用 |
| `has_owned_tag(tag_id)` / `owned_tags()` | ability tag id / 无 | `bool` / `Array[String]` | 查询当前释放者拥有的 ability tags；`owned_tags()` 稳定排序，便于调试和快照 |
| `apply_status_effect(status_effect)` | `StatusEffect` 兼容对象 | `Dictionary` | 交给内部 `StatusEffectComponent`；当前用于释放者自身的 `silence` 授予 / 过期 `ability_tag_silenced` |
| `snapshot()` / `restore_snapshot(snapshot_data)` | run 快照 | `Dictionary` / `void` | 保存冷却、资源当前值、owned tag 计数和状态效果；不保存节点引用、目标列表或临时输入事件 |
| `debug_summary()` | 无 | `Dictionary` | 运行时 smoke / GM 诊断入口，正式 UI 不应依赖字段布局 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `skill_cast` | `skill_id: String`、`result: Dictionary` | `cast_skill()` 完成一次有效效果解释后触发 |
| `skill_failed` | `skill_id: String`、`result: Dictionary` | 未知技能、状态 / tag / 资源 / 冷却 / 目标等任一释放失败路径；供表现层做失败反馈，不改变失败原因 |

## 数据与契约

- 技能 id 来自 `docs/词表与契约.md` §12-C，当前内置 id 为 `skill_overdrive_rounds`。
- 技能资源来自 §12-D，当前首个内置资源为 `mana`。资源是角色声明的池，不是技能系统硬编码；后续可加怒气、能量、弹药等资源。
- 目标类型来自 §12-E：`aoe_enemies_around_caster`、`target_enemy`、`target_ally`。
- 状态效果来自 §9-A，状态叠加规则来自 §9-B；当前 `silence` 可通过 `StatusEffectComponent` 授予 `ability_tag_silenced`。
- 效果原语来自 §12-F，当前运行时效果包含 `skill_effect_damage`、`skill_effect_apply_status` 与 `skill_effect_weapon_modifiers`。
- `skill_effect_apply_status.params` 必须包含：`status`、`duration`、`stack_rule`、`granted_ability_tags`；可选 `magnitude`、`tick_interval` 与 `damage_type` 用于 DoT。`magnitude` 是单 tick 伤害，`tick_interval` 是 tick 间隔；两者都为正时必须提供已登记 `damage_type`。
- Ability tag 来自 §12-G：当前 `ability_tag_skill` / `ability_tag_primary` 标记过载弹流的主动技能语义，`ability_tag_damage` 可用于伤害型技能，`ability_tag_silenced` 可阻断释放，`ability_tag_activating` 在激活 / commit 期间临时授予。
- `activation.required_tags` 全部满足才可释放；`activation.blocked_tags` 命中任一 owned tag 时返回 `blocked_by_tag`；`activation.granted_tags` 是即时激活期临时 tag，效果解释完成后移除。
- 玩家可见技能名 / 描述使用 `skill_*` locale key，译文在 `client/locale/strings.csv`。
- 技能效果不得按 skill id 写分支；新增行为先登记 ability tag、effect / targeting primitive，再在 SkillSystem 或拆分后的 strategy 中解释。

## 依赖

- 上游依赖：`DataLoader` 提供 schema 过的技能 / 角色 / 模式数据，生成常量提供 ability tag / skill / status primitive 白名单，`GameClock` 提供可暂停时间，`GameState` 提供流程状态，`Replay` 记录输入事件，`Combat` 统一伤害，`StatusEffectComponent` 管理状态生命周期，目标实体通过 `apply_status_effect()` 暴露状态宿主能力，玩家主武器通过 `WeaponSystem.apply_temporary_modifiers()` 暴露射击强化入口。
- 下游调用方：当前为 `GameplayRunLoop`；后续主动道具、成长奖励、GM 指令或 AIPlayer 可复用同一技能 API。
- 禁止依赖：不得在技能系统中直接扣敌人生命、直接读物理按键以外的业务输入、按英雄 id / 技能 id 写特殊分支、保存目标节点引用或使用裸时间。

## 扩展点

- 加 AOE 技能：优先加 `skills.json` 条目，目标类型用 `aoe_enemies_around_caster`，效果复用 `skill_effect_damage` 或新增 effect primitive。
- 加指向敌人技能：用 `target_enemy`；后续若需要鼠标点选 / 锁定 UI，应新增 targeting strategy，不改技能本体 id 语义。
- 加指向队友技能：用 `target_ally`；当前只返回施法者，真正队友实体出现时扩展队友组和阵营过滤。
- 加射击强化技能：优先使用 `skill_effect_weapon_modifiers`，`params.modifiers[]` 复用词表 §1 modifier 格式，目标通常用 `target_ally` 指向玩家主武器；不要在 SkillSystem 里按具体技能 id 写武器分支。
- 加新资源：先登记 `skill_resources`，角色在 `skill_resources` 中声明上限、初始值和回复；技能 `costs` 引用资源 id。
- 加新 ability tag：先登记词表 §12-G，跑 `tools/sync_contracts.py`，再在 `skills.json.activation`、StatusEffect 或未来遗物 / 主动道具中引用；不要把运行时状态塞进 content tag。
- 加沉默 / 姿态 / 解锁条件：优先用 owned ability tags 表达 required / blocked 关系；持续型来源通过 `skill_effect_apply_status` 注入到目标实体的 `StatusEffectComponent`，由 Player / Enemy / SkillSystem 自身授予和移除 tag。
- 加 poison / bleed 等 DoT：仍使用 `skill_effect_apply_status`，传入 `status`、`duration`、`stack_rule`、空或需要的 `granted_ability_tags`、`magnitude`、`tick_interval` 和 `damage_type`；tick 伤害由状态组件走 `Combat.apply_damage()`，不要在 SkillSystem 里按 status id 写分支。首批玩家技能不使用燃烧 / 点燃包装。
- 主动道具复用技能：主动道具数据后续应引用 skill id 或 release-skill effect，让道具只管充能 / 栏位 / 触发来源，不复制目标筛选和效果解释。
- 扩展 run 快照：新增资源状态或技能状态时保证 JSON 友好，更新 `GameplayRunLoop`、SaveManager 文档和 smoke。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调过载弹流的持续时间 / 射速倍率 / 弹速倍率 / 魔法消耗 / 冷却 | `client/data/skills.json` | `client/data/README.md` | `python tools/validate_data.py` + `runtime-smoke` |
| 给默认角色换起始技能 | `client/data/characters.json` | `client/data/README.md`、Gameplay Runtime | `validate_data` + `runtime-smoke` |
| 加新技能资源 | `docs/词表与契约.md`、`characters.json`、`skills.json` | 词表、数据手册、测试策略 | `sync_contracts.py` + `validate_data.py` + L1 smoke |
| 加新 ability tag / activation 条件 | `docs/词表与契约.md`、`skills.json`、`skill_system.gd` | 词表、数据手册、本文档、GDD / ADR | `sync_contracts.py` + `validate_data.py` + `test_data_loader_schema.py` + L1 smoke |
| 加状态技能效果 | `docs/词表与契约.md` §9-A~§9-B / §12-F、`skills.json`、`status_effect_component.gd`、`skill_system.gd`、目标实体状态 API | 状态组件文档、数据手册、GDD、测试策略 | `sync_contracts.py` + `validate_data.py` + schema test + `l1-smoke` + `save-smoke` |
| 加 DoT 参数 | `skills.json.effects[].params`、DataLoader schema、`status_effect_component.gd` | 数据手册、Combat、状态组件文档 | schema test + `l1-smoke`；影响默认技能时追加 golden replay |
| 加新 targeting / effect primitive | `docs/词表与契约.md`、`skill_system.gd`、`tools/validate_data.py` | GDD、ADR 或模块文档、测试策略 | `l1-smoke` + `runtime-smoke`，影响整局时评估 golden |
| 改技能快照恢复 | `skill_system.gd`、`gameplay_run_loop.gd` | 本文档、Gameplay Runtime、SaveManager 文档 | `save-smoke` + `runtime-smoke` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 按主动键无效果 | 是否处于 `GameState.PLAYING`；InputService gameplay context 是否有 `use_active_item`；默认角色是否有 `starting_loadout.skill_ids` |
| 返回 `unknown_skill` | `skills.json` 是否包含该 id；DataLoader 是否通过 schema；词表是否同步生成 |
| 返回 `insufficient_resource` | 角色 `skill_resources` 是否声明对应资源；当前值是否足够；资源 id 是否来自生成常量 |
| 返回 `blocked_by_tag` / `missing_required_tag` | `skills.json.activation` 是否引用了正确 ability tag；释放者 `owned_tags()` 是否被 StatusEffect、GM 或调试代码授予了阻断 / 需求 tag |
| 返回 `no_targets` | 目标是否在 `active_enemies` 组；是否位于 `active_parent` 下；半径是否足够；目标 `is_alive()` 是否返回 true |
| 伤害没生效 | effect 是否为 `skill_effect_damage`；`damage_type` 是否登记；目标是否实现 `receive_damage()` 并由 `Combat.apply_damage()` 结算 |
| 状态没生效 / 返回 `status_target_unavailable` | effect 是否为 `skill_effect_apply_status`；目标是否是施法者、Player、Enemy 或其他实现 `apply_status_effect()` 的状态宿主；状态 id / stack rule / ability tag 是否登记 |
| DoT 不造成 tick 伤害 | `skill_effect_apply_status.params` 是否包含 `damage_type`、正 `magnitude`、正 `tick_interval`；目标是否实现 `receive_damage()`；状态组件 smoke 是否通过 |
| 武器强化没生效 | effect 是否为 `skill_effect_weapon_modifiers`；目标是否有 `WeaponSystem` 子节点；`params.duration` 是否为正；`params.modifiers[]` 是否使用已登记 stat |
| 沉默过期后仍阻断释放 | `StatusEffectComponent` 是否在树内且处于 `PLAYING` tick；是否有其他来源仍持有同一个 owned tag 计数 |
| 暂停时冷却 / 魔法还在动 | `GameState` 是否仍是 `PLAYING`；是否绕过 `GameClock.delta_scaled()` |
| 续局后资源 / 状态异常 | run payload `skills.resources` / `skills.status_effects` 是否存在；`restore_snapshot()` 是否在 `configure()` 后调用；`owned_tag_counts` 是否与状态恢复避免双计数 |

## 测试义务

- 技能数据 / locale / ability tag 改动必跑：`python tools/validate_data.py`、`python tools/lint_project_rules.py`、`python tools/sync_contracts.py --check`。
- 技能运行时改动必跑：`python tools/lint_gdscript_rules.py`、`python tools/godot_bridge.py --project client l1-smoke`、`python tools/godot_bridge.py --project client runtime-smoke`、`python tools/godot_bridge.py --project client headless-boot`。
- 改 DataLoader schema 时追加 `python tools/test_data_loader_schema.py`。
- 改 run 快照或恢复路径时追加 `python tools/godot_bridge.py --project client save-smoke`。
- 改 `skill_effect_apply_status`、状态叠加或 ability tag 状态来源时，确保 L1 覆盖真实目标实体施加、阻断、DoT tick、快照恢复、对象池复用清理和过期释放。
- 改确定性输入 / 回放语义时追加 `python tools/godot_bridge.py --project client replay-input-smoke`，并按 `docs/测试策略.md` 判断是否需要 golden replay。

## 迁移 / 兼容

当前 gameplay runtime payload schema version 为 2，`skills` 字段是可选结构；旧 run payload 缺失时按空技能快照处理。SkillSystem 保存 `owned_tag_counts` 以恢复轻量 GAS 运行时标签，旧 payload 缺失该字段时按空 tag 处理；若遇到早期 `owned_tags` 数组格式也会兼容恢复。`status_effects` 缺失时按空状态处理；当快照已有 `owned_tag_counts` 时，状态组件恢复不重复授予 tags，只负责后续过期释放，避免沉默等状态双计数。SkillSystem 不保存目标节点引用、施法请求队列或运行时 NodePath，避免对象池恢复和未来多人 / AIPlayer 接入时出现不可迁移状态。若后续把技能栏、主动道具栏、长通道技能、队友目标系统或更多 tag 来源组件持久化，应先决定是否提升 runtime payload schema 或 SaveManager `run` kind 版本，并补迁移测试。

## 相关文档

- `docs/代码/gameplay_runtime.md`
- `docs/代码/data_loader.md`
- `docs/代码/combat.md`
- `docs/代码/status_effect_component.md`
- `client/data/README.md`
- `docs/词表与契约.md` §9-A~§9-B、§12-C~12-G
- `docs/测试策略.md`
