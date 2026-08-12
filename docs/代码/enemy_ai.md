# Enemy AI 模块文档

> 权威范围：本页只记录该模块的公共契约、可观察行为、schema、所有权与依赖边界；私有实现和逐测试记录不进入本文档。

## 职责

- 让共享 `Enemy` Actor / `EnemyBase` 节点契约通过数据 profile 组合接近、环绕、爆炸、方向近战、冲撞和远程攻击；每种敌人的静态外观由专属继承场景保存。
- 纯 `EnemyBrain` 持有 profile / action source order、决策计时、四级感知与记忆、Utility 分数和移动意图；纯 `EnemyNavigationRuntime` 单一持有可选导航 provider、当前导航模式与 waypoint flag / value，编排 direct / flow-field / local-AStar 方向、路径距离带、LOS / corridor 查询和派生缓存；纯 `EnemyActionRuntime` 单一持有当前 action、阶段、计时、命中位、锁向、点射与 armed / exploded 状态，并负责 Run v19 action 字段的 typed 恢复归一化。
- 纯 `EnemyStatusHostRuntime` 单一持有借用的 `StatusEffectComponent` 引用与 owned ability tag 计数，统一状态施加 / 查询 / 摘要转发、tag 计数和状态 payload 恢复；它不发现场景节点、不读取 SceneTree / autoload，也不拥有组件生命周期。
- 无状态 `EnemyMeleeAttackHandler` 只编排近战锁向、windup、扇区目标顺序、commit 与 cooldown transition；无状态 `EnemyChargeAttackHandler` 只编排冲撞 windup / release、逐帧扫掠、一次性命中与停止 / cooldown transition；无状态 `EnemyExplosionAttackHandler` 只编排爆炸 arm / detonate / armed restore、两类目标结算和自身退场；无状态 `EnemyRangedAttackHandler` 只编排远程 windup / burst / scheduled shot / cooldown transition；无状态 `EnemyProjectileMaterializer` 只把 typed projectile request 按既有顺序交给共享池和 `Bullet.configure()`；无状态 `EnemyDamageHandler` 只按 typed Actor 状态和延迟 source / amount ports 解析受伤短路、友伤、生命结果、归因与后续动作，六者都不持有 Run v19 字段。
- `Enemy` Actor 编排 movement target 上下文、CharacterBody 实际位移 / velocity / facing / bounds / separation、节点目标、近战 target / Combat adapter、冲撞移动 / 边界 / Combat / 击退 adapter、爆炸 target / Combat / defeat adapter、伤害 source facts / amount adapter、生命写入与 typed follow-up、远程起手顺序、状态组件场景发现 / 缺失诊断、Pool / GameClock adapter、signal 与 23-key Run v19 顶层字典；目标节点只在单次调用中借给导航上下文且不进入 Runtime 缓存，Brain、三个 Runtime 和无状态 handlers / materializer 都不持有 Actor 目标节点。
- 普通环境敌人的感知与战斗目标固定为玩家；只有防御世界事件生成上下文可注入专用主目标，且仍把玩家作为可受击附带目标。身体重叠、推挤、贴身移动和中心分离永远不造成伤害。
- 通过 Utility 评分选择动作，以显式阶段状态机执行前摇、释放和冷却；模块模式消费局部共享流场、全图地形视线与 AStar waypoint。
- 所有伤害通过 `Combat.apply_damage()`；`Enemy.receive_damage()` 默认拒绝 `team_enemy`，只允许已提交爆猎者的爆炸伤害。
- 以 `runtime_spawn_serial` 固定连锁爆炸目标结算；敌人金币只在实际生成时由 `RNG.economy` 锁定，Gear Mod 只在玩家归因击杀时由 `RNG.drop` 对本局可用掉落表判定并生成已锁定 `instance_id + mod_id` 的手动配置拾取实体，保持模块墙体、全图边界、对象池、Run v19 续局和 Replay v9 可控。
- 持续状态由 `StatusEffectComponent` 承担，不把沉默、减速、DoT 等状态硬写进 AI profile。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 调某类敌人的对玩家行为 | `client/data/enemy_ai_profiles.json` |
| 调敌人基础数值 / profile / 场景 / 对象池绑定 | `client/data/enemies.csv` |
| 调敌人静态颜色 / 轮廓 / 子节点 | `client/scenes/gameplay/actors/enemies/enemy_*.tscn` |
| 改感知、评分或移动意图 | `client/scripts/gameplay/enemy_brain.gd` |
| 改 provider 查询、导航模式、orbit / path-band 方向或 waypoint 缓存 | `client/scripts/gameplay/enemy_navigation_runtime.gd` |
| 改 action 状态、计时或恢复归一化 | `client/scripts/gameplay/enemy_action_runtime.gd` |
| 改状态宿主转发、ability tag 计数或状态 payload 恢复 | `client/scripts/gameplay/enemy_status_host_runtime.gd` |
| 改近战 windup / 扇区提交顺序 | `client/scripts/gameplay/enemy_melee_attack_handler.gd` |
| 改冲撞 windup / 扫掠 / 停止与击退顺序 | `client/scripts/gameplay/enemy_charge_attack_handler.gd` |
| 改爆炸 arm / direct + enemy 结算 / armed restore 顺序 | `client/scripts/gameplay/enemy_explosion_attack_handler.gd` |
| 改受伤短路 / 友伤 / 击杀归因与 typed follow-up | `client/scripts/gameplay/enemy_damage_handler.gd` / `enemy.gd` |
| 改远程点射 schedule / 池化子弹材化 | `client/scripts/gameplay/enemy_ranged_attack_handler.gd` / `enemy_projectile_materializer.gd` |
| 改节点感知输入、近战 adapter、远程起手 / 移动、其他动作执行、分离或友伤 | `client/scripts/gameplay/enemy.gd` |
| 排查刷怪 / 恢复 | `client/scripts/gameplay/gameplay_run_loop.gd` |
| 排查模块墙体、导航或出生合法性 | `client/scripts/gameplay/module_navigation_field.gd`、`module_world_manager.gd`、`module_chunk.gd` |
| 排查状态效果 | `docs/代码/status_effect_component.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/enemy_brain.gd` | 纯 `RefCounted` profile / action 解释、四级感知、Utility 评分、决策计时与移动意图；只接收 typed 值输入，不持有节点 |
| `client/scripts/gameplay/enemy_navigation_runtime.gd` | 纯 `RefCounted` 导航意图 / 查询 / 缓存边界；单一持有 provider、mode 与 cached waypoint，固定邻居顺序、tangent 权重和 epsilon tie，不执行 CharacterBody 位移 |
| `client/scripts/gameplay/enemy_action_runtime.gd` | 纯 `RefCounted` action 状态与计时所有者；提供 typed snapshot / restore 值对象，复现非法 action、旧缺失 burst 与非法 ranged 阶段的既有 fail-closed 语义 |
| `client/scripts/gameplay/enemy_status_host_runtime.gd` | 纯 `RefCounted` 状态宿主边界；持有借用组件与 tag counts，转发状态 API，并保持 current / legacy tag payload、grant flag、summary source order 和复用清理语义 |
| `client/scripts/gameplay/enemy_melee_attack_handler.gd` | 无状态 typed 近战 transition 编排；借用 `EnemyActionRuntime` 与同步 target ports，保持 primary → distinct player、damage → committed signal、cooldown / clear → focus restore 顺序 |
| `client/scripts/gameplay/enemy_charge_attack_handler.gd` | 无状态 typed 冲撞 transition 编排；借用 `EnemyActionRuntime` 与同步 movement / target ports，保持 timer → full-delta 无滑动移动 → 边界 → primary / distinct player 扫掠 → clear / cooldown / focus restore 顺序 |
| `client/scripts/gameplay/enemy_explosion_attack_handler.gd` | 无状态 typed 爆炸 transition 编排；借用 `EnemyActionRuntime` 与同步 target ports，保持 committed signal → live source direct targets → frozen origin active enemies、跨类别不去重、serial-only 排序与 self-finish 顺序 |
| `client/scripts/gameplay/enemy_damage_handler.gd` | 无状态 typed 受伤决策；按 armed → dead / feedback → 延迟 source facts → 友伤 → 延迟 amount 顺序返回生命结果、公开四键结果与 follow-up，不持有 Node、Presentation、Pool 或 Runtime |
| `client/scripts/gameplay/enemy_ranged_attack_handler.gd` | 无状态 typed 点射 transition 编排；借用 `EnemyActionRuntime` 和同步 ports，保持 materialize → committed signal → 扣 scheduled shot → interval / cooldown 顺序 |
| `client/scripts/gameplay/enemy_projectile_materializer.gd` | 无状态 typed 子弹材化；保持 acquire、方向 / 枪口、世界位置、重挂父节点与 configure 的既有顺序，返回诊断结果但不决定 shot 是否提交 |
| `client/scripts/gameplay/enemy.gd` | Actor 节点目标 / movement target 上下文、导航 Runtime 桥接、CharacterBody 实际位移、近战 target / Combat ports、冲撞 movement / target / damage / knockback ports、伤害 source / amount ports 与 life / follow-up、远程起手与 typed ports、爆炸 handler、连锁爆炸、中心分离、signal 与 23-key 快照 façade |
| `client/scenes/gameplay/actors/enemy_base.tscn` | 共享敌人基础场景；根节点为 `CharacterBody2D`，挂 `Enemy` 脚本与必需组件 |
| `client/scenes/gameplay/actors/enemies/enemy_*.tscn` | 五种敌人的专属继承场景；保存 `fill_color`、归一化轮廓与未来静态表现覆盖 |
| `client/scripts/gameplay/module_navigation_field.gd` | 77×77 静态 mask、半径由最大视觉范围推导的局部共享 Dijkstra 流场、全图 AStar 与视线 / 走廊查询 |
| `client/data/enemy_ai_profiles.json` | schema v5 对玩家 AI profile、显式攻击与远程点射参数 |
| `client/data/enemies.csv` | 基础数值、金币价值倍率、通用内容 tag、对象池和 profile 引用 |
| `client/scripts/data/enemy_reward_resolver.gd` / `client/data/enemy_rewards.json` | 生成时金币公式、全局系数和计算明细；详见 `docs/代码/enemy_reward_resolver.md` |
| `client/scripts/contracts/enemy_ai_actions.gd` | 由词表生成的 action 常量 |
| `client/tools/runtime_smoke.gd` | 五种显式攻击、事件防御目标、远程锁向点射、连锁、金币快照、玩家归因 Mod 实体掉落 / 手动配置、无弹药掉落、视线、墙体、击退、暂停与 Run v19 恢复 |
| `client/tests/unit/test_enemy_brain.gd` | 四级感知 / 记忆过期、source-order + epsilon tie、cooldown / 走廊 / 视线 / 射程门禁、移动意图、深拷贝与纯 `RefCounted` 边界 |
| `client/tests/unit/test_enemy_navigation_runtime.gd` | direct fallback、provider 惰性调用、corridor → query 顺序、flow / local / none mode、waypoint reset、固定邻居与 epsilon tie、orbit 方向 |
| `client/tests/integration/test_enemy_brain_actor.gd` | Actor 配置桥接、sense route → LOS → corridor、零玩家权重不查询 provider、decision action → focus → waypoint refresh、Brain / Navigation 派生状态不入 Run v19 及敌人 23-key 快照 wire 不变 |
| `client/tests/unit/test_enemy_action_runtime.gd` | 11 字段 reset / 初始 cooldown / 计时边界、typed snapshot / restore、非法 action 与 ranged fallback、无 alias / signal |
| `client/tests/integration/test_enemy_action_runtime_actor.gd` | Enemy 23-key wire、池生命周期 reset；ranged windup / armed 恢复在状态和节点生命周期提交后各 emit 一次，ranged burst 不 emit，且合法 ranged 两阶段都先停速并按锁向更新朝向 |
| `client/tests/unit/test_enemy_status_host_runtime.gd` | 缺组件 fallback、bind / refresh / rebind、tag 计数 / 排序 / 无 alias、summary、current / legacy / malformed restore、grant flag 与复用清理 |
| `client/tests/integration/test_enemy_status_host_actor.gd` | 真实 Enemy 场景公共状态门面、PoolManager acquire / release / reuse、23-key 深拷贝 roundtrip、legacy tags 与伤害来源队伍转发 |
| `client/tests/unit/test_enemy_melee_attack_handler.gd` | 缺失目标 / 零方向、windup timer boundary、primary → collateral、range / arc / LOS 短路、零距离命中、damage / signal / cooldown / focus 回调顺序与无 alias |
| `client/tests/unit/test_enemy_charge_attack_handler.gd` | 缺失目标 / 零方向、正 / 零 windup、commit-before-movement、完整 delta、primary → distinct player、命中 flag-before-damage、击退 capability、stop / collision / timeout 与 cooldown / focus 顺序 |
| `client/tests/integration/test_enemy_charge_attack_actor.gd` | 真实 Enemy Actor 的移动 / 边界 / Combat / signal / 击退 typed ports、主目标 → 玩家附带目标顺序和精确 23-key Run v19 façade |
| `client/tests/unit/test_enemy_explosion_attack_handler.gd` | fresh arm 拒绝 / 时序、timer boundary、signal 后 live direct 与 frozen enemy origin、跨类别不去重、active enemy 延迟收集 / serial-only 排序、self-finish 状态保留和 armed restore 不复用 fresh arm |
| `client/tests/unit/test_enemy_damage_handler.gd` | armed / dead / feedback / 友伤短路的 port 次数、非致命 / overkill、三种归因、连锁、direct 零 / 负值遗留语义、四键顺序与无状态结果 |
| `client/tests/integration/test_enemy_damage_actor.gd` | 真实 Combat 下 life 先写、defeated → damage_applied、延迟 / 零前摇连锁、Presentation → Pool 退场和精确 23-key façade |
| `client/tests/integration/test_enemy_explosion_attack_actor.gd` | 真实 Enemy Actor 的 Combat / LOS / signal / defeat typed ports、live direct + frozen enemy 双路径、延迟连锁世代和精确 23-key Run v19 façade |
| `client/tests/integration/test_enemy_melee_attack_actor.gd` | Enemy typed melee debug seam、真实 Combat、事件主目标 → 玩家附带目标、出生伤害倍率、signal 时 Runtime 状态及 23-key wire 不变 |
| `client/tests/unit/test_enemy_ranged_attack_handler.gd` | 起手、timer boundary、零 windup、空 burst，以及 pool / configure 失败仍 emit / 扣 scheduled shot / 进入 interval 或 cooldown 的精确顺序 |
| `client/tests/unit/test_enemy_projectile_materializer.gd` | acquire → direction / muzzle → global position → reparent → configure 顺序、typed config、无 alias 与失败诊断 |
| `client/tests/integration/test_enemy_ranged_attack_actor.gd` | Enemy typed debug seam、真实共享 Bullet、倍率 / target groups、signal 时 action state / 剩余弹数及 23-key wire 不变 |
| `tools/validate_data.py` / `tools/test_data_loader_schema.py` | schema v5、精确 attack 字段、远程点射字段与旧 contact / movement 攻击字段负例门禁 |

## 场景 / 节点结构

```text
Enemy (CharacterBody2D)
├── CollisionShape2D
├── Visual
│   ├── scene-authored body / outline / direction markers
│   ├── ExploderCore / ExploderCoreOutline
│   ├── BulwarkArmor / BulwarkArmorOutline
│   └── enemy_spitter 专属 RifleBody / RifleOutline
├── Presentation / AnimationPlayer
├── VfxAnchors
└── StatusEffectComponent
```

- `CollisionShape2D` 负责敌人与模块墙体的物理碰撞；模块 JSON 的封锁格会合并为静态碰撞。
- `Enemy.configure()` 从数据应用 `hit_radius`、生命、速度、金币、表现 profile 和 AI profile，但不得覆盖专属场景的 `fill_color` 或归一化视觉几何。
- 是否显示爆裂核心或正面装甲由 profile 中的通用 action / attack 能力推导，不按敌人 id 写运行时分支。
- 敌人中心分离在物理帧内施加轻量位移，只防止中心完全重合，不产生伤害或目标关系。

## 运行流程

| 阶段 | 发生什么 | 关键点 |
|------|----------|--------|
| 配置 | `GameplayRunLoop` 合并敌人基础数据与 profile 后调用 `configure(enemy_data, player, navigation_provider, difficulty, spawn_context)` | `velocity = ZERO` 后立即让 StatusHost 清复用状态，再配置 Presentation / targets / Brain / stats；首次配置不会为了清理而提前发现组件。默认主目标为玩家；防御事件额外注入 `event_instance_id/primary_target/damage_target_groups` |
| 感知输入 | `Enemy` 验证主目标节点并单次借用其位置；玩家权重为零时先返回，否则通过 NavigationRuntime 按旧顺序查询 route、地形视线和冲锋走廊，构造 `EnemyBrain.SenseInput` | Brain 不持有 `Node2D` / navigation provider；provider 保持按需调用，目标节点不缓存 |
| 感知 | Brain 在决策 tick 依次判断地形视线 + 直线距离、局部共享流场路径距离、最后已知位置记忆 | 当前半径 8 覆盖最大视觉 / 路径感知并加两格缓冲；记忆期间不读取玩家实时位置，不扫描其他敌人 |
| 评分 | Brain 按 profile `actions[]` source order 对合法动作评分，只在 `score > best + 0.001` 时替换，返回 typed `Decision` | `Enemy` 先提交当前 action、再提交 focus，随后才让 NavigationRuntime 刷新记忆 / 守家 waypoint；行为差异来自数据，不按 enemy id 分支 |
| 执行 | NavigationRuntime 产生 direct / flow-field / local-AStar 方向，Actor 才通过 `_move_in_direction()` 执行 CharacterBody 位移；近战起手后交由 `EnemyMeleeAttackHandler` 推进 windup，冲撞交由 `EnemyChargeAttackHandler` 先减 timer 再通过 Actor port 做完整 delta 的无滑动移动 / 边界，爆炸交由 `EnemyExplosionAttackHandler` 推进 armed timer / detonate，远程起手后交由 `EnemyRangedAttackHandler` 推进点射 schedule | 爆炸 / 近战要求地形视线；冲撞要求清晰走廊；远程每帧保持导航处理 → 原始直线距离 → cooldown → LOS 的起手顺序并锁定方向；两个 Runtime 都不执行 Combat、CharacterBody movement 或 projectile |
| 提交 | 近战 handler 通过 Actor typed ports 按主目标 → 不同玩家顺序做 alive / 扇区 / 地形视线与 Combat；冲撞 handler 在 release signal 后按主目标 → 不同玩家逐帧线段扫掠，先写一次性 flag 再经 Actor port 伤害，并只对真实玩家的有效正伤害调用击退 capability；爆炸先冻结敌方结算原点并发 committed signal，再以 signal 后 live source 结算 direct targets，direct 完成后才收 active enemies 并以冻结原点、`runtime_spawn_serial` 结算，两类目标不做全局去重；远程每发先让 `EnemyProjectileMaterializer` 尝试材化，再同步发 committed signal，之后才扣 scheduled shot 并推进 interval / cooldown | 近战全部 damage 返回后才发 committed，随后设置 cooldown、清 action / phase 并恢复主目标；每次冲撞对每个目标最多命中一次，几何命中即满足 stop_on_hit；爆炸者 self-finish 前不清 armed / exploded / action 状态，留到 pool release；突击枪手一次 windup、四次 commit，中途不追踪；pool / configure 失败也沿用旧的 committed / 消耗本发语义 |
| 爆猎者锁定 | 进入前摇即 `armed`、生命伤害入口关闭、CollisionShape 禁用、停止移动与分离 | 之后必然爆炸；离开范围、状态伤害或普通攻击都不能取消 |
| 连锁 | 爆炸致死未 armed 爆猎者时，目标生命归零并进入完整新一代前摇 | 同代同时前摇，不同代不在同帧递归，每只最多爆炸一次 |
| 分离 | 收集近邻敌人中心并施加非伤害分离 | 不改变 focus target 或动作评分 |
| 边界 | 普通移动、冲锋、分离和快照恢复后统一 clamp 到有限地图边界 | 模块模式还必须通过 walkable / 物理墙体约束 |
| 受伤 / 退场 | `receive_damage()` 即时构造 typed request 与延迟 source / amount ports；Handler 决定公开四键结果、下一生命、归因和 follow-up，Actor 先写生命，再执行 hit flash、chain arm 或 `finish_defeat` | armed / dead / feedback / 友伤短路不读后续伤害字段；`defeated` 仍早于 `Combat.damage_applied`，实际爆炸者无奖励，普通敌人被炸死仍计杀并掉落 |
| 保存 | 保存位置、生命、动作 / 阶段 / 剩余时间、锁向、点射剩余弹数、命中位、armed、生成序号、倍率和状态效果 | StatusHost 深拷贝第 22 项 `owned_tag_counts` 并生成第 23 项 `status_effects`；恢复先发现并 `clear(false)`，再按 Actor 既有字段顺序提交，最后恢复 tags / effects。不保存节点引用或临时感知缓存；恢复后不得重复或遗漏提交 |

## 数据与契约

### `enemies.csv`

- `tags` 必须含且只使用当前已登记的通用敌人内容 tag；正式五种敌人均使用 `tag_enemy`。
- `ai_profile_id` 必填，且必须存在于 `enemy_ai_profiles.json.profiles[].id`。
- `scene_path` 必须绑定正式敌人专属继承场景；多个敌人内容 id 可以复用同一场景或 profile。
- `pool_id` 必须为每个敌人独立且等于敌人 id，当前五池为 `enemy_chaser` / `enemy_swarm` / `enemy_stalker` / `enemy_bulwark` / `enemy_spitter`；`pool_prewarm` 数据化控制预热，旧 `enemy_ranged` 不再合法。
- 精确表头不再包含 `contact_damage`、`contact_interval` 或敌人级 `element_id`；这些遗留列由 Python 与 GDScript DataLoader 明确拒绝。

### `enemy_ai_profiles.json` schema v5

| 字段 | 约束 | 说明 |
|------|------|------|
| `schema_version` | 必须为 `5` | v4 远程 attack 缺少点射必填字段；旧 `movement` 攻击参数、旧接触字段和更早 schema 不得继续加载 |
| `profiles[].id` | 唯一非空字符串 | 由敌人数据引用 |
| `perception.sight_radius` | `> 0` | 360° 地形视线畅通时的视觉半径 |
| `perception.path_awareness_radius` | `>= 0` 且 `<= sight_radius` | 隔墙但可达时按流场路径距离感知玩家 |
| `perception.memory_duration` | `>= 0` | 失去当前感知后追最后已知位置的时间 |
| `decision_interval` | `> 0` | Utility 重算间隔 |
| `targeting.player_weight` | `>= 0` | 普通敌人的玩家候选权重；事件主目标由受控生成上下文覆盖，不参与 Utility 重选 |
| `movement.orbit_radius` | `>= 0` | 唯一当前通用移动参数；攻击参数不得放在 `movement` |
| `actions[]` | 非空、id 来自词表 | 可参与评分的对玩家动作 |
| `actions[].attack` | 攻击 action 必填、非攻击 action 禁止 | 按 action id 使用精确字段集合 |
| 爆炸 attack | `trigger_range/windup/damage/element_id/radius` | 全部正数，元素登记 |
| 近战 attack | 上述触发 / 前摇 / 伤害，加 `cooldown/range/arc_degrees` | 角度 `(0, 360]` |
| 冲撞 attack | 触发、前摇、释放、冷却、伤害、速度、停止与击退 | 击退距离 / 时长同时为零或同时为正 |
| 远程 attack | `attack_range/keep_distance/windup/burst_count/shot_interval/cooldown/initial_cooldown/damage/element_id/projectile` | `windup/shot_interval > 0`、`burst_count` 为正整数；projectile 精确声明池、速度、射程、半径、寿命和枪口偏移 |

schema v5 明确拒绝 v4、远程点射字段缺失 / 多余 / 非法值、旧 `movement.charge_*`、`movement.ranged_*`、`contact_interval` 和旧 CSV contact 表头；`sense_radius`、猎食 / 逃跑目标数组与逃跑距离同样继续拒绝。

当前 profiles：

| profile | 对玩家行为 |
|---------|------------|
| `enemy_ai_exploder` | 接近后进入不可逆圆形爆炸前摇 |
| `enemy_ai_melee_swarm` | 接近后锁定方向并提交扇区近战 |
| `enemy_ai_charge_stalker` | 接近、环绕并执行命中后继续的冲刺 |
| `enemy_ai_ram_bulwark` | 接近并执行命中停止、带击退的冲撞 |
| `enemy_ai_ranged_spitter` | 突击枪手：保持距离 / 环绕，锁向并静默前摇后沿固定方向完成四发池化点射 |

突击枪手当前固定口径为：射程 600 px、保持距离 280 px、首次延迟 0.65 秒、静默前摇 0.32 秒、4 发、间隔 0.12 秒、冷却 0.95 秒；不显示提前弹道线、枪口蓄光或逐发枪口闪光，每弹 18 伤害、350 px/s、720 px 射程、12 px 半径、2.1 秒寿命，枪口距离 24 px。起手要求玩家视线；一旦提交便完成整轮，玩家移动或失去视线都不改变 `_locked_direction`，Bullet 地形阻挡继续有效。难度只乘每弹 `damage`。ADR #181 取代 ADR #172 的投射物速度、半径、寿命和枪口距离口径，ADR #184 再取代其枪口视觉口径，点射玩法不变。

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(enemy_data, target, navigation_provider = null, difficulty = {}, spawn_context = {})` | 合并数据、玩家、导航、出生倍率、锁定奖励与可选事件上下文 | `void` | 对象池取得后的唯一配置入口；release/reset 必须清空事件 id、主目标、目标组和奖励快照 |
| `set_movement_bounds(half_extents)` | 地图半尺寸 | `void` | 所有移动路径统一使用 |
| `set_runtime_spawn_serial(serial)` / `runtime_spawn_serial()` | 正整数 / 无 | `void` / `int` | RunLoop 生成时分配；连锁目标和奖励 RNG 稳定排序 |
| `is_armed()` / `is_committed_exploder()` | 无 | `bool` | 只读爆炸锁定 / 合法爆炸来源能力 |
| `ai_debug_summary()` | 无 | `Dictionary` | 额外报告 attack action / 阶段、剩余时间、`burst_shots_remaining`、armed、锁向、倍率后伤害、范围、本次命中和锁定奖励 |
| `combat_team_id()` | 无 | `String` | 返回 `team_enemy` |
| `apply_status_effect(effect)` | `StatusEffect` | `Dictionary` | 由统一状态系统调用；缺组件保持 `{applied=false, reason=status_component_unavailable}` |
| `add_owned_tag(tag)` / `remove_owned_tag(tag)` / `has_owned_tag(tag)` / `owned_tags()` | 已登记 ability tag / 无 | `bool` / `Array[String]` | 计数式所有权；列表排序，未知 tag 拒绝；状态组件仍以 Enemy public facade 作为 owner |
| `active_statuses()` / `status_summary()` / `status_stat_multiplier(stat)` / `status_stack_count(status)` | 无或登记 id | typed 值 | 缺组件分别退化为空、`1.0` 或 `0`；summary 保持组件 effects source order 并钳制 stacks / remaining |
| `incoming_damage_multiplier(info)` | 已由 Combat 构造的 damage info | `float` | Enemy 先提取 `source_team` 值，再借给 StatusHost 转发；Runtime 不持有 DamageInfo / Combat |
| `snapshot()` / `restore_snapshot(data)` | 无 / `Dictionary` | `Dictionary` / `void` | Run v19 攻击阶段、锁向、点射剩余弹数、事件归属 / target mode、命中、armed、生成序号、出生倍率与完整奖励明细恢复；导航派生状态不保存 |
| `convert_to_player_target(player)` | 玩家节点 | `void` | 事件终止后让残敌成为普通敌人；保留事件 id 直到 pin 清理 |
| `receive_damage(info)` | `DamageInfo` | 四键 result dictionary | 保持 `applied → amount → defeated → reason` 顺序；armed 一律拒绝，普通 `team_enemy` 拒绝，已提交爆炸例外；Actor 仍接受公共 dynamic `RefCounted` 输入 |
| `debug_force_action_for_test(action_id)` | 已配置 action id | `bool` | 仅 debug build 的确定性 handler smoke 门面；先由 Brain 校验 action，不开放字段写入或 release 使用 |
| `debug_start_melee_attack_for_test()` / `debug_advance_melee_attack_for_test(delta)` | 无 / 非负推进量 | `bool` | 仅 debug build 且当前为已配置 melee action；给 smoke 提供 typed transition 门面，不开放 Runtime 字段写入 |
| `debug_arm_explosion_for_test(from_chain = false)` / `debug_advance_explosion_for_test(delta)` | chain 标记 / 非负推进量 | `bool` | 仅 debug build 且已配置 explode action；给 smoke 提供 typed arm / armed-phase 门面，不开放 Runtime 字段写入 |
| `debug_materialize_ranged_projectile_for_test(direction)` | 非零方向 | `bool` | 仅 debug build 且当前为已配置 ranged action；只走真实材化 adapter，不发 committed、不改 scheduled shot |
| `debug_start_ranged_burst_for_test(direction)` / `debug_advance_ranged_attack_for_test(delta)` | 非零锁向 / 非负推进量 | `bool` | 仅 debug build 且当前为已配置 ranged action；给 smoke 提供 typed transition 门面，不开放 Runtime 字段写入 |

无对外 `content_tags()` 接口；其他敌人不是感知候选。

### `EnemyBrain` 内部 typed 边界

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(profile_id, profile)` / `reset()` | profile id + 已校验 profile / 无 | `void` | 深拷贝 profile 与 `actions[]`；保持 source order；空 action 使用旧 approach fallback |
| `advance_memory(delta)` / `advance_decision(delta)` / `request_decision_now()` | 缩放后 delta / 无 | `void` | Actor 保留原 physics gate 与计时顺序；Brain 不直读 `GameClock` |
| `decide(input, attack_cooldown)` | typed `SenseInput` + Actor 拥有的 cooldown | typed `Decision` | 候选不用 Dictionary / Node；近战、爆炸、冲锋在候选期受 cooldown 门禁，远程仍可被选中并在执行期才检查 cooldown |
| `action(id)` / `action_speed_scale(id)` / `movement_value(key)` | action / profile key | 深拷贝 action / 数值 | 仅供 Actor 执行已选 action，返回值不能反向污染 Brain |
| `debug_state()` 及 typed getters | 无 | 值快照 | 感知、记忆、决策和移动意图是派生状态，不进 Run v19 |

### `EnemyActionRuntime` 内部 typed 边界

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(initial_attack_cooldown)` / `reset()` | 已校验初始 cooldown / 无 | `void` | 配置、池 acquire / release 均从同一默认态开始；Enemy 不保留镜像字段 |
| `advance_action_timer(delta)` / `advance_attack_cooldown(delta)` | physics gate 后的缩放 delta | `void` | 两条时钟独立推进；armed、无目标、debug disabled 与非 PLAYING 的 Actor 提前返回顺序不变 |
| typed getters / setters | 标量或 `Vector2` | 值 | 仅 Actor handler 路由既有 FSM transition；不接收 Node、Dictionary、Combat、Pool、RNG 或 clock |
| `snapshot_values()` | 无 | `SnapshotValues` | 返回 11 个 action 字段的值快照；输出修改不能反向污染 Runtime |
| `restore(input, rules)` | `RestoreInput` + `RestoreRules` | `RestoreResult` | 原子校验并提交；非法 action 清空，旧缺失 burst 清空但不加 cooldown，非法 ranged phase / count / direction / timer 清空并应用一次当前 ranged cooldown |
| `force_armed_restore(explode_action_id)` | 已登记爆炸 action | `void` | 只做恢复后的 action / phase 收口；碰撞生命周期与唯一 windup signal 仍由 Enemy 在提交后执行 |

### `EnemyNavigationRuntime` 内部 typed 边界

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(provider)` / `reset()` | 可选导航 Node / 无 | `void` | 单一设置或清空 provider、mode 与 waypoint flag / value；Enemy 的 configure、pool reset / release 调用，restore 不额外 reset |
| `active_navigation_query(...)` / `navigation_query(...)` | 当前 / 目标位置与是否活动目标 | route `Dictionary` | 活动目标优先共享流场，其他目标走全图 query；缺 provider / method 时保持直线可达 fallback，provider 只在需要时调用 |
| `has_terrain_line_of_sight(...)` / `has_clear_corridor(...)` | 起止点与 clearance | `bool` | 缺 provider / method 时保持 `true` fallback；sense 由 Actor 固定按 route → LOS → corridor 调用 |
| `movement_direction_to(...)` / `direction_to_cached_target(...)` / `path_band_direction(...)` / `orbit_direction(...)` | 值类型位置、半径、目标身份与 orbit sign | `Vector2` 导航意图 | 不写 Actor position / velocity；path-band 固定八邻 source order，每个候选严格 corridor → query → score，只有 `score > best + 0.001` 才替换 |
| `refresh_cached_waypoint(...)` | 当前点、是否存在派生目标及目标位置 | `void` | 每次先清旧缓存；只在 guard / memory 决策提交后由 Actor 传入目标，不持有目标 Node，缓存不进 Run v19 |

### `EnemyStatusHostRuntime` 内部 typed 边界

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `bind(component, owner)` / `refresh(owner)` | Actor 已发现的组件 / Enemy owner | `bool` | Runtime 只借用引用并配置 tag owner；节点发现与缺失诊断保留在 Enemy，Runtime 不读 tree / autoload |
| `clear_for_reuse()` / `clear_effects_before_restore()` | 无 | `void` | 两者都只调用 `component.clear(false)`；前者随后清 counts，后者保留 counts 直到 restore 最后阶段；不得改成 `clear(true)` 或首次配置 eager bind |
| tag methods / `owned_tag_counts_snapshot()` | 已登记 tag | typed 值 / 深拷贝字典 | 正数计数、移除到零删除、排序列表；Runtime 单一持有 counts，Actor 不保留镜像字段 |
| status forwards / `status_effect_snapshot()` | 状态、stat / status / source-team 值 | typed 值 | 缺组件 fallback 与旧 max-zero 归一化保持；summary 按 effects source order；Enemy 仅在 Runtime 确认可查询后才提取 source-team，Runtime 不读取 DamageInfo |
| `restore_from_actor_snapshot(data)` | Run v19 Enemy payload | `void` | 先清 counts；优先合法正数 `owned_tag_counts`，否则 legacy `owned_tags` 累加；缺 `owned_tags` 的默认空数组仍视为已有 tag snapshot，最后以 `not has_owned_tag_snapshot` 传入组件 restore |

### 伤害 / 近战 / 冲撞 / 爆炸 / 远程 handler 与 projectile materializer 内部 typed 边界

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `EnemyDamageHandler.resolve(request, ports)` | `armed/defeat_feedback_active/current_life/can_chain_explode` 与延迟 source facts / amount ports | typed `Result` + 固定四键公开字典 | 严格按 armed → dead / feedback → source team / source capability → friendly fire → amount 短路；沿用 `min(amount, life)` / `max(life - amount, 0)`，不新增 direct `<= 0` 归一化；Result 只声明 hit / finish / chain follow-up，Actor 先写 life 再执行 |
| `EnemyMeleeAttackHandler.start(runtime, config, request, ports)` | 借用 Runtime、typed config / focus request 与同步 ports | typed `Result` | 无 focus 不变；先写 normalized lock，零方向在 hit flags 重置前返回；合法起手先写完整 windup 状态再发 signal，零 windup 同调用提交 |
| `EnemyMeleeAttackHandler.advance(runtime, config, delta, ports)` | melee windup 的缩放后 delta | typed `Result` | commit 时才从 Actor 取得稳定顺序 target ports；零距离绕过 range / arc / LOS，其余按 range → arc → terrain LOS 短路；全部 damage 后发 committed，再 cooldown / clear / focus restore |
| `EnemyChargeAttackHandler.start(runtime, config, request, ports)` | 借用 Runtime、typed config / focus request 与同步 ports | typed `Result` | 无 focus 不变；先写 normalized lock，零方向在 hit flags 重置前返回；正 windup 发 signal，零 windup 同步进入 release 并先发 committed |
| `EnemyChargeAttackHandler.advance(runtime, config, step, ports)` | charge windup / release 的缩放后 delta、移动速度与状态倍率 | typed `Result` | 先减 timer，再以完整 delta 通过 Actor port 朝锁向无滑动移动并应用边界；按 primary → distinct player 扫掠，先写 flag 再伤害；collision / timeout / stop 后 clear → cooldown → focus restore |
| `EnemyExplosionAttackHandler.arm(runtime, config, request, ports)` / `advance(...)` | 借用 Runtime、typed config / action availability / chain 标记与同步 ports | typed `Result` | fresh arm 依次写 action、清 focus、armed / chain / hit flags / lock / phase / timer，再停速、禁碰撞、发 windup、刷视觉；零 windup 同调用 detonate；detonate 先写 exploded / hit、冻结 enemy origin、发 signal，再取 live direct，direct 完成后才取 active enemies，跨类别不去重且 enemy 仅按 serial `<` 排序，self-finish 不清状态 |
| `EnemyExplosionAttackHandler.restore_armed(runtime, explode_action_id, ports)` | 已恢复 Runtime、爆炸 action 与同步 ports | typed `Result` | 只强制 action / armed phase、禁碰撞并发一次剩余 windup；保留 timer / flags / chain / cooldown / burst，不复用 fresh arm，timer 为零也不立即 detonate |
| `EnemyRangedAttackHandler.start_burst(runtime, config, direction, ports)` | 借用 Runtime、typed config、锁向和同步 ports | typed `Result` | 非零方向才锁向；先写完整 burst / windup 状态再发 windup；零 windup 同调用进入首发 |
| `EnemyRangedAttackHandler.advance(runtime, config, delta, ports)` | ranged phase 的缩放后 delta | typed `Result` | 每次调用最多提交一发；材化结果不决定 scheduled shot，committed signal 时 Runtime 仍保留扣减前弹数和 ranged action |
| `EnemyProjectileMaterializer.materialize(request, ports)` | typed pool / source / parent / projectile 数值和 acquire / configure ports | typed `Result` | 零方向不 acquire；合法请求严格按 `acquire → capability → direction/muzzle → global_position → reparent → configure`，失败不擅自 release |

五个 Handler 与 Materializer 都不缓存 `Config` / `Request` / `Result`，不拥有 Node 生命周期或 signal；DamageHandler 不拥有 Runtime / Presentation / Pool，四个 attack Handler 只借用 Runtime 且不拥有 cooldown 之外的计时。Enemy 每次调用即时构造 damage request / ports，或从当前 profile、出生伤害倍率和当前 target groups 构造 attack config，因此近战 / 冲撞 / 爆炸提交读取当前 Actor target 顺序，事件结束后的剩余点射会使用新的玩家目标组。

## Signal / Event

- `attack_windup_started(enemy, action_id, context)`：前摇开始或续局重建时触发；context 提供世界位置、旋转和剩余 duration，需要空间范围的爆炸 / 近战 / 冲撞另提供二维缩放。突击枪手每轮只触发一次、不提供轨迹 `scale`，其 profile 不绑定该 cue。
- `attack_committed(enemy, action_id, context)`：近战 / 冲撞 / 爆炸提交时触发；爆炸 impact 使用 detached 世界 context；突击枪手每发仍触发一次以保留统一玩法语义，但其 profile 不绑定该 cue。
- `defeated(enemy, gold_reward, counts_as_kill, drops_rewards, cause_id)`：退场语义与生成时锁定的最终整数金币一次性传给 RunLoop；死亡时不重算、不抽随机。玩家前摇前击杀为 `true/true/player_damage`，实际爆炸者为 `false/false/exploder_detonation`，普通敌人被炸死为 `true/true/enemy_explosion`。

## 依赖

- 上游：`EnemyBrain` 只依赖已验证 profile 和生成 action 常量；`EnemyNavigationRuntime` 只长期持有可选 `ModuleWorldManager` 导航门面并接收 Actor 的值类型位置 / 目标上下文；`EnemyActionRuntime` 只依赖 typed 值与 Actor 提供的已验证 restore rules；`EnemyStatusHostRuntime` 只依赖 ability tag 常量、Actor 借入的组件和 owner；`EnemyDamageHandler` 只依赖 typed 值、延迟 ports 与生成的 defeat cause 常量；`EnemyMeleeAttackHandler` / `EnemyChargeAttackHandler` / `EnemyExplosionAttackHandler` / `EnemyRangedAttackHandler` 只借用 ActionRuntime 与 typed ports；`EnemyProjectileMaterializer` 只借用 typed request 和 acquire / configure ports；`Enemy` Actor 依赖 `DataLoader`、`GameClock`、`GameState`、`PoolManager`、`Combat`、`DamageInfo`、`StatusEffectComponent`、地图边界和生成契约常量。
- 下游：`GameplayRunLoop`、runtime / module-world / save smoke、回放工具。
- 禁止依赖：`EnemyBrain`、`EnemyActionRuntime`、`EnemyDamageHandler` 与四个 attack Handler 不得依赖 Node / SceneTree、导航 provider、`GameClock`、RNG 或 autoload；NavigationRuntime 不得缓存目标 Node 或接管 CharacterBody、velocity、facing、bounds、separation、Combat、attack order、signal、Pool 或 snapshot；StatusHostRuntime 不得发现节点、读取 SceneTree / autoload、接管组件生命周期或保留 DamageInfo；ActionRuntime 不得接管具体 handler、movement、projectile 或 signal，Handler / Materializer 不得新增镜像 action 字段。整个模块不得依赖原始输入、原始时间、裸随机或运行时网络模型，不得绕过 `Combat` 扣血，不得按 enemy id 写行为分支，不得恢复通用接触伤害。

## 扩展点

- 新敌人优先复用现有 profile；确需新行为时新增通用 action / 字段并同步词表、双端 schema、快照和 smoke。
- 新敌人可复用已有专属 TSCN，但仍需独立池；需要不同静态外观时，从 `enemy_base.tscn` 新建继承场景，不复制完整基础节点树。
- 远程敌人复用 `ai_action_ranged_attack`、`windup/burst_count/shot_interval` 与 `actions[].attack.projectile`；普通投射物只命中玩家，防御事件投射物由上下文额外包含防御目标组。`Bullet` 必须跨全部组选择空间最近的扫掠命中，不能按数组顺序结算。若未来需要追踪、扩散或弹数缩放，应新增通用声明字段和快照契约，不能按敌人 id 特判。
- 新攻击 action 必须在 Brain 声明通用候选门禁，并在 Actor 声明独立空间判定、提交点和快照字段；仅接近 / 环绕 action 不得携带 `attack`。
- 新复杂状态只保存 JSON 友好的可恢复字段；节点引用和临时感知结果不进存档。
- 新导航或地形感知通过 `ModuleWorldManager` 查询门面扩展，不得让 Enemy 依赖活动 chunk，也不得借机引入其他敌人作为 focus target。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调爆炸 / 近战危险窗口 | 对应 action 的 `attack.windup/radius/range/arc_degrees` | 数据手册、VFX | data/schema + runtime/VFX smoke |
| 调冲锋频率 | `attack.trigger_range/cooldown`、动作分数 | 数据手册 | runtime smoke + golden replay |
| 调远程压力 | 远程 `attack.windup/burst_count/shot_interval/cooldown/keep_distance/projectile.*` | 数据手册 | data/schema + runtime / save smoke |
| 新增 AI profile | profile JSON、敌人引用 | 本文、数据手册 | data/schema + runtime smoke |
| 新增敌人专属场景 | `enemy_base.tscn` 的继承场景、`enemies.csv.scene_path` / 独立池 | Gameplay Runtime、PoolManager、数据手册 | data/schema + `actor-scene-smoke` + runtime smoke |
| 改快照恢复 | `enemy.gd`、`gameplay_run_loop.gd` | 本文、Save 文档 | runtime + L1 + save smoke |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 敌人不动 | profile 是否有合法 action、`move_speed`、`GameState` 和玩家引用 |
| 敌人持续顶墙 | `navigation_mode` 是否切到 `flow_field`；Manager 是否已在 assignment / restore 后重建 mask；玩家格是否可走 |
| 池复用后沿用旧路径或 provider | `Enemy.configure()`、`_pool_reset()`、`_pool_release()` 是否都调用 `EnemyNavigationRuntime.configure/reset`；restore 不应另行 reset |
| 隔墙无限追踪 | `perception_state`、路径距离阈值和 `memory_remaining`；记忆期间 `last_known_position` 不得跟随玩家更新 |
| 爆炸 / 近战隔墙命中 | 提交时的 `has_terrain_line_of_sight()` 是否仍在 |
| 冲锋 / 远程穿墙起手 | `has_clear_corridor()` / `has_terrain_line_of_sight()` 门禁是否仍在候选与开火路径中 |
| 突击枪手中途转向或少发 / 多发 | ranged windup / burst 状态是否只读 `_locked_direction`；`burst_shots_remaining` 是否逐发减一，最后一发后才进入冷却 |
| 冲锋穿过玩家 | 上一位置→当前位置的线段扫掠是否包含双方命中半径 |
| 冲锋沿墙继续 | `_move_with_collision(..., false)` 是否仍在释放段使用，碰撞后是否立即结束 |
| 爆猎者前摇能被打断 | `_arm_explosion()` 是否在同一帧设置 armed、禁用碰撞并让 `receive_damage()` 早退 |
| 连锁同帧递归或奖励乱序 | 是否在 direct damage 完成后才收 active enemies，并以冻结爆炸原点按 `runtime_spawn_serial` 排序；连锁目标是否只 armed 而不立即 detonate |
| 敌人错误锁定其他敌人 | 普通 `_sense_context()` 是否只构造玩家候选；防御事件是否只通过可信 spawn context 注入专用目标 |
| 环境敌人伤害防御目标 | 普通 spawn context 是否为空；投射物目标组是否错误包含 `active_world_event_defense_targets` |
| 敌人互相扣血 | `EnemyDamageHandler` 的 source facts → `team_enemy` 早期拒绝，以及 Actor 的 committed exploder capability adapter 是否仍存在 |
| 敌人中心重叠 | separation radius / strength 和物理帧更新是否执行 |
| 穿过或出生在封锁格 | `CharacterBody2D` shape、模块墙体碰撞、placement footprint 与 walkable 校验 |
| 续局保留已删除动作 | `restore_snapshot()` 是否校验 action 仍在当前 profile；非法动作应清空并在下一决策 tick 重选 |
| 池化敌人残留状态 | `configure()`、PoolManager release / acquire 是否依次调用 StatusHost 的 `clear_for_reuse()`；组件清理必须为 `clear(false)` 后 counts 清空，且首次 configure 不提前 bind |

## 测试义务

- 改 profile / enemies 数据：`validate_data.py`、`test_data_loader_schema.py`、`sync_contracts.py --check`。
- 改 `enemy_brain.gd`：必跑 Brain unit，锁定四级感知 / 记忆过期、source-order + epsilon tie、近战 / 爆炸 / 冲锋 cooldown gate 与 ranged 例外、charge corridor、ranged LOS / range、approach / orbit / guard、configure / reset / 深拷贝与无 Node / RNG / clock 依赖；追加 Actor integration 确认 23-key wire 不变。
- 改 `enemy_navigation_runtime.gd`：必跑 NavigationRuntime unit 与 Brain Actor integration，锁定 provider 惰性、sense route → LOS → corridor、零玩家权重不查询、decision action → focus → waypoint refresh、direct / flow / local / none mode、固定邻居 corridor → query → score / epsilon tie、ranged 导航 → 原始距离 → cooldown → LOS、pool reset / release 清理和 23-key wire 不变。
- 改 `enemy_status_host_runtime.gd` / Enemy 状态宿主接线：必跑 StatusHost unit 与 Actor integration，锁定缺组件 fallback、bind / rebind、tag 计数 / 排序 / 无 alias、summary source order、current / legacy / malformed restore 与 grant flag、PoolManager public reuse 和 23-key roundtrip；追加 L1 / runtime / save / headless 与四条 checked-in Replay v9 golden，只重跑不重录。
- 改 `enemy_action_runtime.gd` / damage、melee、charge、explosion 或 ranged handler / materializer / `enemy.gd`：GDScript / semantic lint、EnemyActionRuntime / StatusHost / damage / melee / charge / explosion / ranged handler / materializer / EnemyBrain unit、八套 Actor integration、L1 / actor-scene / runtime / save / loading smoke、完整 / technical module-world、headless boot 与四条 checked-in Replay v9 golden。
- 改基础 / 专属敌人场景或池绑定：追加 `actor-scene-smoke`，验证继承、必需节点、场景颜色 / 几何不被 `configure()` 覆盖，以及五个独立池生成 / 复用不串场景。
- 改稳定行为、数据指纹或刷怪：重录并回放四条 checked-in golden replay。
- 改实体状态、金币、Gear Mod 掉落或 run 快照：追加 L1、runtime、effect-runtime、gear-mod-pickup、content-progression 与 save / module-world smoke，验证 Run v19 阶段、奖励明细、内容可用池、棋盘、效果状态、带 ID 未拾取实体、事件归属、主目标解析和击退 roundtrip；远程点射覆盖前摇与点射中途的计时 / 剩余弹数一致。
- 性能 probe 只在用户明确要求性能测试时运行。

## 迁移 / 兼容

- 当前 Run schema 为 v19；旧 Run v18 保持源文件但不显示继续入口，不迁移。
- Run v19 恢复当前 profile 已删除的 action 时清空阶段并在下一决策 tick 重选；合法攻击阶段按剩余时间继续，不得重复提交。
- Brain 的感知、记忆、决策计时、分数和移动意图，以及 NavigationRuntime 的 provider / mode / waypoint flag / value，仍是不进快照的派生状态；ActionRuntime 继续单一拥有原 11 个 action 字段，StatusHostRuntime 单一拥有借用组件与 tag counts，五个 Handler / Materializer 不持有可恢复状态；Enemy restore 不新增 NavigationRuntime reset，StatusHost 恢复仍位于 serial / event 之后、ranged / armed / group / visual 提交之前。Enemy 23-key 字典顺序、字段值 / 恢复时序、Run v19、Replay v9 与 game v1.18 均不变。
- `burst_shots_remaining` 继续随 Run v19 保存；字段存在但点射阶段、计时、方向或剩余弹数非法时，清空攻击并应用一次当前远程冷却，防止重复发弹。Replay v9 明确拒绝 v8。
- schema v1–v4 profile、旧 `sense_radius`、旧 movement 攻击字段与旧 contact CSV 表头必须被双端 validator 拒绝，不做静默忽略。

## 相关文档

- `docs/游戏设计文档.md` §5.3
- `docs/决策记录.md` ADR #144 / #145 / #170 / #171 / #172
- `docs/游戏设计文档.md`
- `docs/词表与契约.md`
- `docs/代码/gameplay_runtime.md`
- `docs/测试策略.md`
