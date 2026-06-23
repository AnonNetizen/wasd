# StatusEffectComponent 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是状态效果运行时首片的代码契约权威；改 `StatusEffect` 字段、叠加规则、ability tag 授予 / 移除、tick / 过期、run 快照或技能状态注入时，必须同步 SkillSystem、Gameplay Runtime、DataLoader、GDD、词表、测试策略和 AI 导航。

## 职责

- `StatusEffect` 是运行时状态效果的轻量 `Resource`，承载状态 id、持续时间、剩余时间、叠加规则、来源、强度、DoT 伤害类型 / tick 计时和授予的 ability tags。
- `StatusEffectComponent` 是挂在可受状态影响实体上的 `Node`，负责按 `GameClock` 推进剩余时间、按叠加规则合并状态、通过 `Combat.apply_damage()` 结算 DoT、过期清理和释放由状态授予的 ability tags。
- 当前首片服务项目版轻量 GAS 与真实实体状态：`SkillSystem`、`Player` 和 `Enemy` 都可挂载 `StatusEffectComponent`，`skill_effect_apply_status` 可对真实敌人施加 `silence` 或 `burn`；`silence` 授予 `ability_tag_silenced`，`burn` 用 `fire` 伤害类型按 tick 造成 DoT。
- 本模块暂不实现视觉表现、抗性、免疫、驱散或 `ModifierEngine` 属性修正；这些后续应复用同一个状态生命周期，不在各效果原语里各自实现。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 加新状态 id | `docs/词表与契约.md` §9-A，再跑契约同步 |
| 加新叠加规则 | `docs/词表与契约.md` §9-B、`status_effect_component.gd` 的 `_merge_effect()` |
| 让技能施加状态 | `docs/代码/skill_system.md` 的 `skill_effect_apply_status` |
| 让新实体受状态影响 | 对应实体脚本的 `apply_status_effect()` / owned tag API，参考 `player.gd` 与 `enemy.gd` |
| 调查沉默没有移除 | `StatusEffectComponent._tick_effects()`、`_expire_effect()` 与 tag owner 的 `remove_owned_tag()` |
| 调查 burn 不掉血 | `StatusEffect.damage_type` / `magnitude` / `tick_interval`、`StatusEffectComponent._tick_damage()` 与 `Combat.damage_applied` |
| 改状态快照 | `snapshot()` / `restore_snapshot()`，同时看 `SkillSystem.snapshot()`、`Player.snapshot()` 与 `Enemy.snapshot()` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/combat/status_effect.gd` | `StatusEffect` Resource，负责参数规范化、DoT 字段合法性、复制和快照 |
| `client/scripts/combat/status_effect_component.gd` | 状态容器 Node，负责 apply、叠加、DoT tick、过期和 ability tag 生命周期 |
| `client/scripts/gameplay/skill_system.gd` | 技能运行时状态宿主；自带一个 `StatusEffectComponent` 并可接受 `skill_effect_apply_status` |
| `client/scripts/gameplay/player.gd` | 玩家实体状态宿主；保存 / 恢复状态效果与状态授予 tags，新开局 `configure()` 清空状态 |
| `client/scripts/gameplay/enemy.gd` | 敌人实体状态宿主；保存 / 恢复状态效果与状态授予 tags，对象池复用时清空状态 |
| `client/scripts/contracts/status_effects.gd` / `status_stack_rules.gd` / `ability_tags.gd` | 由词表生成的状态、叠加规则和 ability tag 常量 |
| `client/tools/l1_smoke.gd` | 覆盖自我沉默、真实 Enemy 目标施加状态、burn DoT、Player / Enemy 快照恢复、过期清理和复用清空 |

## 场景 / 节点结构

当前没有独立 `.tscn`。`SkillSystem`、`Player` 与 `Enemy` 都在运行时通过 `_ensure_status_effect_component()` 动态添加子节点 `StatusEffectComponent`，并把自身注册为 ability tag owner。

`Enemy` 是对象池实体，`configure()`、`_pool_release()` 与 `_pool_reset()` 都会清空状态效果和 owned tag 计数；不要让池化节点在非活跃期保留状态。后续召唤物、机关或其他可受状态实体应复用同一个组件，并实现或转发 `apply_status_effect(status_effect)`；不要为每个实体重写一套状态计时。

## 运行流程

| 阶段 | 发生什么 | 关键 API |
|------|----------|----------|
| 构造状态 | 调用方创建 `StatusEffect`，用 `setup(status_id, params, source)` 规范化持续时间、叠加规则、magnitude、tick interval、damage_type 和 granted ability tags | `StatusEffect.setup()` |
| 施加状态 | 组件复制运行时状态，按 `status_id` 或独立实例 key 找到当前状态，并按 `stack_rule` 合并或替换 | `StatusEffectComponent.apply()` |
| 授予标签 | 新状态生效时调用 ability tag owner 的 `add_owned_tag(tag_id)`；替换、过期和清空时调用 `remove_owned_tag(tag_id)` | `_register_effect_tags()`、`_release_effect_tags()` |
| 推进时间 | 仅在 `GameState.PLAYING` 下用 `GameClock.delta_scaled(delta)` 扣减剩余时间；暂停、升级选择和 game over 不推进 | `_physics_process()` |
| DoT tick | 当状态同时具备正 `magnitude`、正 `tick_interval` 和已登记 `damage_type` 时，按 `tick_remaining` 触发 `Combat.apply_damage()`，并在 `DamageInfo.flags` 写入 `is_dot` | `_tick_damage()`、`_apply_tick_damage()` |
| 过期清理 | 剩余时间归零后释放该状态授予的 tags，删除状态，并发出 `effect_expired` | `_expire_effect()` |
| 快照恢复 | 保存状态数组、key、剩余时间、tick 计时、DoT 伤害类型、队伍归因和授予 tags；恢复时可选择是否重新授予 tags，避免和实体 `owned_tag_counts` 双计数 | `snapshot()`、`restore_snapshot()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `StatusEffect.setup(effect_id, params, source_node)` | 状态 id、参数、来源节点 | `Resource` | `duration > 0`；`stack_rule` / `damage_type` / `granted_ability_tags` 必须来自生成常量；DoT 必须同时有正 `magnitude`、正 `tick_interval` 和 `damage_type` |
| `StatusEffect.copy_runtime()` | 无 | `Resource` | 复制运行时字段，避免调用方复用同一个 Resource 实例导致状态串扰 |
| `StatusEffect.is_valid()` | 无 | `bool` | 只接受已登记 status、已登记 stack rule、正持续时间和正剩余时间 |
| `StatusEffect.snapshot()` / `restore_from_snapshot(snapshot_data)` | JSON 友好字典 | `Dictionary` / `Resource` | 不保存 NodePath；`source` 不进入快照 |
| `StatusEffectComponent.configure_ability_tag_owner(owner)` | 拥有 `add_owned_tag` / `remove_owned_tag` 的节点 | `void` | owner 可为空；为空时状态仍计时，但不会授予 tags |
| `StatusEffectComponent.apply(effect)` | `StatusEffect` 兼容对象 | `Dictionary` | 返回 `applied`、`reason`、`status`、`active_statuses` |
| `StatusEffectComponent.clear(remove_granted_tags := true)` | 是否释放已授予 tags | `void` | 无论参数如何都会清空 active effects；`SkillSystem`、`Player`、`Enemy` 在重新配置时会传 `false`，因为随后会清空 owned tag 计数 |
| `StatusEffectComponent.active_statuses()` | 无 | `Array[String]` | 去重并排序，供调试和 smoke 使用 |
| `StatusEffectComponent.snapshot()` / `restore_snapshot(snapshot_data, grant_existing_tags := true)` | run 快照 | `Dictionary` / `void` | 恢复旧 `owned_tag_counts` 时应传 `false`，避免状态 tags 双倍计数 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `effect_applied` | `status_id: String`、`snapshot: Dictionary` | 一次状态施加或叠加合并后 |
| `effect_expired` | `status_id: String`、`snapshot: Dictionary` | 状态剩余时间归零并完成清理后 |

## 数据与契约

- 状态 id 来自 `docs/词表与契约.md` §9-A；当前内置包含 `burn`、`poison`、`bleed`、`freeze`、`slow`、`mark`、`silence`。
- 叠加规则来自 §9-B：`REPLACE`、`REFRESH`、`ADD_DURATION`、`INDEPENDENT`、`MAX_MAGNITUDE`。
- DoT 伤害类型来自 §9 `damage_type`；`burn` 当前使用 `fire`，并通过 `DamageInfo.flags=["is_dot"]` 标记持续伤害。
- 状态授予的 ability tags 来自 §12-G；当前 `silence` 通过 `ability_tag_silenced` 阻断技能释放。
- `skill_effect_apply_status` 的 `params` 至少包含 `status`、`duration`、`stack_rule`、`granted_ability_tags`；可选 `magnitude`、`tick_interval`、`damage_type`。当 `magnitude` 与 `tick_interval` 都为正时，DataLoader 和 `tools/validate_data.py` 要求 `damage_type` 已登记。
- 状态快照只保存 JSON 友好标量和数组，不保存源节点、目标节点、计时器对象或信号连接；DoT 会保存 `tick_remaining`、`source_team` 和 `target_team`，避免续局后 tick 节奏或击杀归因漂移。

## 依赖

- 上游依赖：生成常量、`GameState`、`GameClock`、`Combat`、ability tag owner。
- 当前下游调用方：`SkillSystem`、`Player`、`Enemy`；后续主动道具、遗物行为、机关和 `Combat` on-hit 注入都应复用该组件。
- 禁止依赖：不得用裸 `Time` 或自建 `Timer` 推进 gameplay 状态；不得绕过实体的 owned ability tag API 直接改 tag 字典；不得在单个 effect primitive 内私自实现一套 DoT / debuff 生命周期。

## 扩展点

- 加 DoT：新增状态 id 与 effect primitive 后，数据传入 `damage_type`、`magnitude` 和 `tick_interval`；状态组件 tick 触发 `Combat.apply_damage()`，并在 `DamageInfo.flags` 标记 `is_dot`。不要为 `burn`、`poison` 等各写一套计时器。
- 加减速 / 增伤标记：状态组件后续应接 `ModifierEngine` 或统一 modifier 注入层，不直接改实体属性字段。
- 加免疫 / 抵抗：优先新增可复用查询接口或 tag / capability，不在某个状态 id 上写特判。
- 加视觉表现：通过状态 id 映射到特效池、颜色叠加或 cue，不让业务状态逻辑直接管理长生命周期视觉节点。
- 加新实体受状态：参考 `Player` / `Enemy`，给实体挂组件并暴露 `apply_status_effect()`、`has_owned_tag()`、`owned_tags()` 与快照字段，不要复制 `StatusEffectComponent` 的 merge / tick 逻辑。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增状态 id | `docs/词表与契约.md` §9-A | GDD、本文档、AI 导航 | `sync_contracts.py` + `validate_data.py` |
| 新增叠加规则 | `docs/词表与契约.md` §9-B、`status_effect_component.gd` | GDD、测试策略、AI 记忆 | L1 smoke / 单测 + 必要 golden |
| 新增技能施加状态效果 | `skills.json`、`skill_system.gd`、DataLoader schema | SkillSystem、数据手册、本文档 | `test_data_loader_schema.py` + `l1-smoke` + `runtime-smoke` |
| 新增 DoT 状态 | `skills.json` / future on-hit primitive、`status_effect_component.gd` | GDD、Combat、SkillSystem、数据手册、测试策略 | `l1-smoke` + `save-smoke` + 必要 golden replay |
| 改实体状态快照 | `status_effect_component.gd`、`skill_system.gd`、`player.gd`、`enemy.gd` | Gameplay Runtime、EnemyAI、SaveManager 相关说明 | `l1-smoke` + `save-smoke` + `runtime-smoke` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 返回 `invalid_status_effect` | `status` / `stack_rule` 是否登记；`duration` / `remaining` 是否大于 0 |
| 沉默后技能仍可释放 | `granted_ability_tags` 是否包含 `ability_tag_silenced`；owner 是否已配置；`SkillSystem.activation.blocked_tags` 是否包含该 tag |
| 技能命中敌人但状态没生效 | 目标是否在 `active_enemies`、是否位于 `active_parent` 下，目标是否实现 `apply_status_effect()`；`l1-smoke` 的真实 Enemy 状态用例是否通过 |
| burn 已施加但不掉血 | `params.damage_type` 是否登记且非空、`magnitude` / `tick_interval` 是否为正、目标是否实现 `receive_damage(info)`，`Combat.damage_applied` 是否出现 `is_dot` flag |
| 状态过期但 tag 还在 | `_release_effect_tags()` 是否被调用；是否存在多个来源同时持有同一 tag 计数 |
| Enemy 复用后仍带旧状态 | `Enemy.configure()`、`_pool_release()` 与 `_pool_reset()` 是否调用状态清理；是否绕过 `PoolManager.acquire()` / `release()` |
| 续局后 tag 双倍计数 | 对应实体 `restore_snapshot()` 是否在已有 `owned_tag_counts` 时用 `grant_existing_tags=false` 恢复状态 |
| 暂停时状态还在掉时间 | `GameState` 是否仍是 `PLAYING`；是否绕过 `GameClock.delta_scaled()` |

## 测试义务

- 状态 / 叠加规则 / ability tag 契约改动必跑：`python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`。
- 状态组件、SkillSystem 状态注入或实体状态宿主改动必跑：`python tools/lint_gdscript_rules.py`、`python tools/godot_bridge.py --project client l1-smoke`、`python tools/godot_bridge.py --project client runtime-smoke`。
- 改 run 快照或恢复路径追加：`python tools/godot_bridge.py --project client save-smoke`。
- 改整局数值、DoT 伤害、控制时长或确定性语义时，按 `docs/测试策略.md` 判断是否重录 / 重跑 golden replay。

## 迁移 / 兼容

当前 `StatusEffectComponent` 的快照挂在 `SkillSystem.snapshot().status_effects`、`Player.snapshot().status_effects` 与 `Enemy.snapshot().status_effects` 下；旧 run payload 没有 `status_effects` 时按空状态处理。`SkillSystem`、`Player` 与 `Enemy` 都保存 `owned_tag_counts`；恢复新计数格式时状态组件不重复授予 tags，只负责未来过期时释放对应计数。早期只含 `owned_tags` 数组的快照仍按 legacy tag 列表兼容恢复。

`Player` / `Enemy` 状态字段是 runtime payload schema version 2 下的向后兼容可选字段；旧档缺失时默认为无状态，不需要 SaveManager kind 迁移。后续若状态效果进入机关、召唤物或更复杂的 modifier 注入，应明确旧档缺失时的默认空状态行为，并按风险决定是否提升 runtime payload schema 或 SaveManager kind version。

## 相关文档

- `docs/代码/skill_system.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/combat.md`
- `docs/代码/data_loader.md`
- `docs/游戏设计文档.md` §9.15.2
- `docs/词表与契约.md` §9-A~§9-B、§12-F~§12-G
- `client/data/README.md`
- `docs/测试策略.md`
