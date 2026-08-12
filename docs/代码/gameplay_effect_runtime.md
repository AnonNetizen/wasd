# GameplayEffectRuntime 模块文档

> 权威范围：本页只记录该模块的公共契约、可观察行为、schema、所有权与依赖边界；私有实现和逐测试记录不进入本文档。

## 职责

- `GameplayEffectRuntime` 每局管理技能与 Gear Mod 效果来源、FIFO 事件队列、程序内部冷却、周期累计、动作状态、确定性顺序、快照与诊断。
- `EffectPrimitiveRegistry` 把已登记 trigger / condition / action 映射到通用 handler，并在来源注册前按原语执行参数级校验；新增原语不修改内容 id 分支。
- `EffectExecutionGateway` 是效果动作访问 `Combat`、`StatusEffectComponent`、临时 modifier、金币、投射物、敌人、屏障及后续 `AudioManager` 的唯一出口。
- 本模块不负责技能冷却 / 消耗 / 目标选择、Gear Mod 棋盘合法性、内容解锁、数据加载或存档 envelope。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 加 trigger / condition / action | `docs/词表与契约.md`、`effect_primitive_registry.gd`、`effect_execution_gateway.gd` |
| 改事件顺序 / 概率 / 冷却 / 周期 | `gameplay_effect_runtime.gd` |
| 让技能执行程序 | `client/scripts/gameplay/skill_system.gd` |
| 让 Gear Mod 注册组件 | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/autoload/gear_mod_system.gd` |
| 改快照 / 回放指纹 | Save / Replay 模块文档与 `client/tools/effect_runtime_smoke.gd` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/effects/gameplay_effect_runtime.gd` | 来源注册、稳定事件队列、周期 / 冷却、预算、快照 |
| `client/scripts/gameplay/effects/effect_primitive_registry.gd` | trigger 白名单、condition handler、action handler |
| `client/scripts/gameplay/effects/effect_execution_gateway.gd` | 受控调用 Combat / Status / modifier / gameplay delegates |
| `client/scripts/contracts/effect_triggers.gd` | 自动生成 trigger 常量 |
| `client/scripts/contracts/effect_conditions.gd` | 自动生成 condition 常量 |
| `client/scripts/contracts/effect_actions.gd` | 自动生成 action 常量 |
| `client/data/skills.json` | skills v3 通用效果程序 |
| `client/data/gear_mods.json` | gear_mods v6 `program` 组件 |
| `client/tools/effect_runtime_smoke.gd` | 稳定顺序、概率、预算、快照和动作专项 smoke |

## 场景 / 节点结构

无独立场景。Runtime、Registry 与 Gateway 都是 `RefCounted`；正式每局由 `GameplayRunLoop` 创建唯一 Runtime，并把同一实例注入 `SkillSystem`。测试可创建隔离实例并注入受控 Gateway callback。

## 运行流程

| 阶段 | 行为 | 确定性约束 |
|------|------|------------|
| 配置 | `configure(registry, gateway)` 清空来源、队列、诊断和预算 | 每局新建；不复用上一局状态 |
| 注册来源 | 技能按 skill id / slot，Gear Mod 按 mod id / instance id / 组件顺序注册非空 programs；Runtime 先校验 program 顶层精确字段、类型、trigger 专属字段与非空 actions，Registry 再校验每个 condition / action 的参数 | 来源按 type → content id → instance id → component order 排序；program 按数据顺序；非法 envelope / 参数在进入队列、预算和 cooldown 前拒绝 |
| 触发事件 | `emit_event()` 深拷贝 context 并加入 FIFO；嵌套触发追加到队尾 | 最大链深 8；超限记录诊断并拒绝该链 |
| 条件 / 概率 | 依次检查全部 conditions，再判定 `proc_chance` | 概率只走 `RNG.combat`；`1.0` 不消费 roll |
| 执行动作 | actions 按数组顺序经 Registry → Gateway 执行 | 每 gameplay tick 最多 256 个动作；超限清空剩余队列并记录诊断 |
| 时间推进 | `tick(delta, context)` 用 `GameClock.delta_scaled()` 更新内部冷却和 interval | 暂停 / 时间缩放语义与正式游戏一致 |
| 快照 | `snapshot()` 保存所有已注册来源的 program states；恢复前必须先按当前内容重建相同来源 | 缺来源、重复来源、未知 program、非法数值或状态形状全部拒绝 |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(registry, gateway)` | `EffectPrimitiveRegistry`, `EffectExecutionGateway` | `void` | 两者必须是本局受控实例 |
| `register_source(source_type, content_id, instance_id, component_order, programs, metadata)` | 稳定来源字段与非空程序数组 | `bool` | program id 为 snake_case 且来源内唯一；顶层只允许必需字段和 interval / reset 可选字段，数值 / bool 类型精确；trigger / conditions / actions 全部已登记且每个 primitive 参数通过 Registry 校验；失败来源不会进入运行态或消耗预算 / cooldown |
| `unregister_source(source_key)` | 稳定来源 key | `void` | 移除定义与运行态 |
| `unregister_source_type(source_type)` | 来源类型 | `void` | 技能重新配置时批量替换来源 |
| `source_key(...)` | 与注册来源相同的标识字段 | `String` | 供定向事件和快照对齐，不由内容作者手写 |
| `source_keys_for_type(source_type)` | 来源类型 | `Array[String]` | 返回稳定排序深层结果 |
| `emit_event(trigger_id, context, chain_depth)` | 已登记 trigger 与事件上下文 | `Dictionary` | 返回执行 / 排队结果；非法 Runtime 或链深失败不执行 |
| `tick(delta, context)` | 物理帧 delta 与当前模块等上下文 | `void` | 时间只经 `GameClock`；自动发出 `interval` 事件 |
| `snapshot()` | 无 | `Dictionary` | 保存 cooldown、interval_elapsed 与 action_state |
| `restore_snapshot(saved)` | Runtime 子快照 | `bool` | 必须与当前已注册来源全集精确匹配 |
| `diagnostics()` | 无 | `Array[Dictionary]` | 返回链深 / 动作预算等诊断副本 |

## 原语契约

首版 trigger：`skill_activated`、`damage_dealt`、`kill`、`damage_taken`、`dash`、`module_entered`、`interval`。

首版 condition：`team`、`element`、`damage_flag`、`actor_tag`、`health_ratio`、`board_cell_relation`、`module_relation`。条件项固定为 `{condition,params}`。

首版 action：`damage`、`apply_status`、`temporary_modifier`、`heal`、`grant_shield`、`grant_overshield`、`grant_gold`、`spawn_projectile`、`spawn_enemy`、`spawn_barrier`。动作项固定为 `{action,params}`；伤害必须走 `Combat.apply_damage()`，状态走 `StatusEffectComponent`，生成与金币通过 GameplayRunLoop 注入的 Gateway delegate。

Registry 的参数校验是 Runtime 公共扩展边界，不依赖调用方先经过 DataLoader。它与 DataLoader 的正式内容 schema 保持同一核心约束：必需 / 可选 key、有限正数、stat 对应的整数 / 比例 / 正数 / 非负范围、生成契约 id、exact-key 的 modifier 结构、投射物目标组和生成策略必须在 `register_source()` 时合法。`apply_status.modifiers` 是可选附加项并允许空数组，必填的 `temporary_modifier.modifiers` 必须非空。modifier 当前唯一可选缩放模式 `inverse_from_magnitude` 只允许出现在携带 `magnitude` 的 `apply_status`，且对应 modifier 必须是 `mult`；其他 action、缺失 magnitude 或加法 modifier 都在注册阶段拒绝。`apply_status` 在 `magnitude` 与 `tick_interval` 都为正时必须提供已登记 `element_id`，避免执行期才得到无效 DoT。`temporary_modifier` 还必须保证 `actor` 只携带 Player 消费的 hero stat、`weapon` 只携带 WeaponSystem 消费的 weapon stat，`both` 可使用两者并集；不允许注册后静默丢弃不属于目标 slot 的 stat。其 `stack_rule` 当前只允许省略或 `REFRESH`，因为 Player / Weapon 的来源语义是同 source 替换并刷新时长；其余状态叠层策略不得静默映射成 refresh。Gateway 仍保留执行期目标 / callback 检查，但不得承担静态参数兜底。

通用程序固定为：

```json
{
  "program_id": "heal_on_damage",
  "trigger": "damage_taken",
  "conditions": [],
  "actions": [{"action": "heal", "params": {"amount": 5.0}}],
  "proc_chance": 0.25,
  "internal_cooldown": 2.0
}
```

`interval` 额外要求正 `interval_seconds`；只有该 trigger 可选用 `reset_on_condition_fail` 控制条件失败时是否清空累计时间与动作状态，其他 trigger 携带任一周期专属字段都会在注册阶段被拒绝。

## 依赖

- 上游：DataLoader 已校验的 skills v3 / gear_mods v6、生成契约、`RNG.combat`、`GameClock`。
- 下游：`GameplayRunLoop`、`SkillSystem`、Gear Mod 程序组件、Run v19 快照、Replay v9 指纹 / 回归。
- 受控出口：`Combat`、`StatusEffectComponent`、Player / Weapon 临时修正 API、`PoolManager` / 金币 / 生成 callback、`AudioManager`。
- 禁止依赖：内容 id 特判、玩家脚本、原始随机 / 时间 API、业务系统绕过 Gateway 直接执行 program action。

## 扩展点

- 新原语先登记 `docs/词表与契约.md`，生成常量，再在 Registry 增加独立 handler / 参数校验与 Gateway 出口，最后补描述格式化、schema 和专项测试。
- 新内容只组合已登记原语；不得为了一个技能或 Gear Mod 修改 Runtime 的内容 id 分支。
- 新来源类型必须定义稳定 `source_type/content_id/instance_id/component_order`，并把完整程序状态纳入 Run / Replay 决定性边界。
- 本地 Mod 只能组合已有原语；manifest v2 不能扩展 trigger、condition、action、status、enemy、pool、RNG 或 stat。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证 |
|------------|----------|----------|------|
| 加原语 | 词表、Registry、Gateway、DataLoader | 本文档、数据手册、测试策略 | contracts + data/schema + effect-runtime smoke |
| 改队列 / 上限 | Runtime | 本文档、GDD、Save / Replay | effect-runtime + runtime + save + replay |
| 改技能程序 | `skills.json`、SkillSystem | 数据手册、Skill 文档 | data/schema + L1/runtime |
| 改 Gear Mod 程序 | `gear_mods.json`、GearModSystem、RunLoop | 数据手册、Gear Mod 文档 | gear-mod + module-world + save/replay |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 来源注册失败 | program id 是否重复、trigger / condition / action 是否登记、primitive params 是否缺字段 / 类型越界 / 引用未知生成契约、actions 是否为空、概率 / 冷却是否越界 |
| 周期程序不触发 | `interval_seconds`、条件、当前模块 context、`reset_on_condition_fail` 与 Runtime tick 是否推进 |
| 读档失败 | 是否在 restore 前重建相同来源；source / program id、组件顺序和 action_state 是否与当前数据一致 |
| 动作没有效果 | Gateway 是否配置对应 callback；目标 context、team、element / status / pool 引用是否有效 |
| 诊断出现 `effect_limit` | 检查递归触发链或单帧动作爆炸；不得提高上限掩盖循环 |

## 测试义务

- 必跑 `py -3 tools/godot_bridge.py --project client effect-runtime-smoke`。
- 改原语或程序 schema：追加 contracts、`validate_data`、DataLoader schema、L1、runtime、Gear Mod、module-world、save、replay 与 headless boot。
- 改确定性行为：验证 FIFO、来源 / 组件顺序、`RNG.combat` 消费、内部冷却、链深 8、动作预算 256、周期计划不重抽和快照 roundtrip；专项 smoke 还必须逐类覆盖非法 primitive params 在注册阶段拒绝，且不消耗动作预算或写入 cooldown。有意改变 gameplay 指纹时重录并逐条复跑四条 Replay v9 golden。
- 性能 probe 不属于默认验收；只在用户当次明确要求时运行。

## 迁移 / 兼容

本框架随 gear_mods v6、skills v3、Run v19、Replay v9 和游戏 v1.18 一次断代。旧 Gear Mod v5 / skills v2 数据不兼容；旧 Run v18 与 Replay v8 文件保持原样但不继续 / 不播放，也不迁移。

## 相关文档

- `docs/游戏设计文档.md` §6.3 / §9.8 / §9.9 / §9.16 / §9.21
- `docs/词表与契约.md`
- `client/data/README.md`
- `docs/代码/skill_system.md`
- `docs/代码/gear_mod_system.md`
- `docs/代码/save_manager.md`
- `docs/代码/replay.md`
- `docs/测试策略.md`
