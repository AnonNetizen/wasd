# Enemy AI 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/代码文档规范.md`、`docs/游戏设计文档.md` 与 `client/data/README.md`。
> 本文档是敌人 AI 的代码契约；改敌人感知、效用评分、动作状态机、敌方友伤护栏、AI profile schema 或 run 快照字段时，必须同步本文档、`docs/代码/gameplay_runtime.md`、`client/data/README.md`、`docs/AI导航.md`、GDD 和测试策略。

## 职责

- 让共享 `Enemy` 脚本 / `EnemyBase` 节点契约通过数据 profile 组合接近、环绕、爆炸、方向近战、冲撞和远程攻击；每种敌人的静态外观由专属继承场景保存。
- 感知与战斗目标固定为玩家；身体重叠、推挤、贴身移动和中心分离永远不造成伤害。
- 通过 Utility 评分选择动作，以显式阶段状态机执行前摇、释放和冷却；模块模式消费局部共享流场、全图地形视线与 AStar waypoint。
- 所有伤害通过 `Combat.apply_damage()`；`Enemy.receive_damage()` 默认拒绝 `team_enemy`，只允许已提交爆猎者的爆炸伤害。
- 以 `runtime_spawn_serial` 固定连锁爆炸的目标结算与奖励 RNG 顺序，并保持模块墙体、全图边界、对象池、Run v8 续局和 Replay v3 可控。
- 持续状态由 `StatusEffectComponent` 承担，不把沉默、减速、DoT 等状态硬写进 AI profile。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 调某类敌人的对玩家行为 | `client/data/enemy_ai_profiles.json` |
| 调敌人基础数值 / profile / 场景 / 对象池绑定 | `client/data/enemies.csv` |
| 调敌人静态颜色 / 轮廓 / 子节点 | `client/scenes/gameplay/actors/enemies/enemy_*.tscn` |
| 改感知、评分、动作执行、分离或友伤 | `client/scripts/gameplay/enemy.gd` |
| 排查刷怪 / 恢复 | `client/scripts/gameplay/gameplay_run_loop.gd` |
| 排查模块墙体、导航或出生合法性 | `client/scripts/gameplay/module_navigation_field.gd`、`module_world_manager.gd`、`module_chunk.gd` |
| 排查状态效果 | `docs/代码/status_effect_component.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/enemy.gd` | profile 解释、目标感知、动作评分 / 显式攻击、连锁爆炸、伤害、中心分离、快照 |
| `client/scenes/gameplay/actors/enemy_base.tscn` | 共享敌人基础场景；根节点为 `CharacterBody2D`，挂 `Enemy` 脚本与必需组件 |
| `client/scenes/gameplay/actors/enemies/enemy_*.tscn` | 五种敌人的专属继承场景；保存 `fill_color`、归一化轮廓与未来静态表现覆盖 |
| `client/scripts/gameplay/module_navigation_field.gd` | 99×99 静态 mask、半径由最大视觉范围推导的局部共享 Dijkstra 流场、全图 AStar 与视线 / 走廊查询 |
| `client/data/enemy_ai_profiles.json` | schema v5 对玩家 AI profile、显式攻击与远程点射参数 |
| `client/data/enemies.csv` | 基础数值、通用内容 tag、对象池和 profile 引用 |
| `client/scripts/contracts/enemy_ai_actions.gd` | 由词表生成的 action 常量 |
| `client/tools/runtime_smoke.gd` | 五种显式攻击、远程锁向点射、连锁、视线、墙体、击退、暂停与 Run v8 恢复 |
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
| 配置 | `GameplayRunLoop` 合并敌人基础数据与 profile 后调用 `configure(enemy_data, player, navigation_provider)` | 模块模式注入 `ModuleWorldManager`，开放战区传空并使用直线兜底 |
| 感知 | 决策 tick 依次判断地形视线 + 直线距离、局部共享流场路径距离、最后已知位置记忆 | 当前半径 8 覆盖最大视觉 / 路径感知并加两格缓冲；记忆期间不读取玩家实时位置，不扫描其他敌人 |
| 评分 | profile 的 `actions[]` 对合法动作评分 | 行为差异来自数据，不按 enemy id 分支 |
| 执行 | 畅通时直追，受阻时读共享流场；爆炸 / 近战 / 冲撞 / 远程点射进入显式阶段 FSM | 爆炸 / 近战要求地形视线；冲撞要求清晰走廊；远程只在起手检查视线并锁定方向 |
| 提交 | 近战提交时做扇区判定；冲撞释放逐帧线段扫掠；爆炸冻结目标快照后按生成序结算；远程每发独立提交 | 每次冲撞最多命中一次；突击枪手一次 windup、四次 commit，中途不追踪 |
| 爆猎者锁定 | 进入前摇即 `armed`、生命伤害入口关闭、CollisionShape 禁用、停止移动与分离 | 之后必然爆炸；离开范围、状态伤害或普通攻击都不能取消 |
| 连锁 | 爆炸致死未 armed 爆猎者时，目标生命归零并进入完整新一代前摇 | 同代同时前摇，不同代不在同帧递归，每只最多爆炸一次 |
| 分离 | 收集近邻敌人中心并施加非伤害分离 | 不改变 focus target 或动作评分 |
| 边界 | 普通移动、冲锋、分离和快照恢复后统一 clamp 到有限地图边界 | 模块模式还必须通过 walkable / 物理墙体约束 |
| 受伤 / 退场 | `receive_damage()` 区分玩家、爆炸与其他来源；`defeated` 显式携带计杀 / 掉落标记和 cause | 实际爆炸者无奖励；普通敌人被炸死仍计杀并掉落 |
| 保存 | 保存位置、生命、动作 / 阶段 / 剩余时间、锁向、点射剩余弹数、命中位、armed、生成序号、倍率和状态效果 | 不保存节点引用或临时感知缓存；恢复后不得重复或遗漏提交 |

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
| `targeting.player_weight` | `>= 0` | 玩家候选权重；玩家仍是唯一候选 |
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
| `enemy_ai_ranged_spitter` | 突击枪手：保持距离 / 环绕，锁向并以枪口局部蓄光前摇后沿固定方向完成四发池化点射 |

突击枪手当前固定口径为：射程 600 px、保持距离 280 px、首次延迟 0.65 秒、枪口局部蓄光前摇 0.32 秒、4 发、间隔 0.12 秒、冷却 0.95 秒；不提前显示弹道线，每弹 18 伤害、280 px/s、720 px 射程、5 px 半径、2.6 秒寿命。起手要求玩家视线；一旦提交便完成整轮，玩家移动或失去视线都不改变 `_locked_direction`，Bullet 地形阻挡继续有效。难度只乘每弹 `damage`。

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(enemy_data, target, navigation_provider = null)` | 合并数据、玩家节点、可选模块导航门面 | `void` | 对象池取得后的唯一配置入口；无门面时直线兜底 |
| `set_movement_bounds(half_extents)` | 地图半尺寸 | `void` | 所有移动路径统一使用 |
| `set_runtime_spawn_serial(serial)` / `runtime_spawn_serial()` | 正整数 / 无 | `void` / `int` | RunLoop 生成时分配；连锁目标和奖励 RNG 稳定排序 |
| `is_armed()` / `is_committed_exploder()` | 无 | `bool` | 只读爆炸锁定 / 合法爆炸来源能力 |
| `ai_debug_summary()` | 无 | `Dictionary` | 额外报告 attack action / 阶段、剩余时间、`burst_shots_remaining`、armed、锁向、倍率后伤害、范围和本次命中 |
| `combat_team_id()` | 无 | `String` | 返回 `team_enemy` |
| `apply_status_effect(effect)` | `StatusEffect` | `bool` | 由统一状态系统调用 |
| `snapshot()` / `restore_snapshot(data)` | 无 / `Dictionary` | `Dictionary` / `void` | Run v8 攻击阶段、锁向、点射剩余弹数、命中、armed、生成序号与倍率恢复；导航派生状态不保存 |
| `receive_damage(info)` | `DamageInfo` | result dictionary | armed 一律拒绝；普通 `team_enemy` 拒绝，已提交爆炸例外 |

无对外 `content_tags()` 接口；其他敌人不是感知候选。

## Signal / Event

- `attack_windup_started(enemy, action_id, context)`：前摇开始或续局重建时触发；context 提供世界位置、旋转和剩余 duration，需要空间范围的爆炸 / 近战 / 冲撞另提供二维缩放。突击枪手每轮只触发一次，不提供轨迹 `scale`，由表现 profile 在枪口播放局部红色蓄光。
- `attack_committed(enemy, action_id, context)`：近战 / 冲撞 / 爆炸提交时触发；爆炸 impact 使用 detached 世界 context；突击枪手每发触发一次，用于枪口闪光。
- `defeated(enemy, gold_reward, counts_as_kill, drops_rewards, cause_id)`：退场语义一次性传给 RunLoop。玩家前摇前击杀为 `true/true/player_damage`，实际爆炸者为 `false/false/exploder_detonation`，普通敌人被炸死为 `true/true/enemy_explosion`。

## 依赖

- 上游：`DataLoader`、`GameClock`、`GameState`、`PoolManager`、`Combat`、`DamageInfo`、`StatusEffectComponent`、`ModuleWorldManager` 可选导航门面、地图边界和生成契约常量。
- 下游：`GameplayRunLoop`、runtime / module-world / save smoke、回放工具。
- 禁止依赖：原始输入、原始时间、裸随机、运行时网络模型；不得绕过 `Combat` 扣血，不得按 enemy id 写行为分支，不得恢复通用接触伤害。

## 扩展点

- 新敌人优先复用现有 profile；确需新行为时新增通用 action / 字段并同步词表、双端 schema、快照和 smoke。
- 新敌人可复用已有专属 TSCN，但仍需独立池；需要不同静态外观时，从 `enemy_base.tscn` 新建继承场景，不复制完整基础节点树。
- 远程敌人复用 `ai_action_ranged_attack`、`windup/burst_count/shot_interval` 与 `actions[].attack.projectile`；投射物必须池化并只命中玩家队伍。若未来需要追踪、扩散或弹数缩放，应新增通用声明字段和快照契约，不能按敌人 id 特判。
- 新攻击 action 必须声明独立空间判定、提交点和快照字段；仅接近 / 环绕 action 不得携带 `attack`。
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
| 隔墙无限追踪 | `perception_state`、路径距离阈值和 `memory_remaining`；记忆期间 `last_known_position` 不得跟随玩家更新 |
| 爆炸 / 近战隔墙命中 | 提交时的 `has_terrain_line_of_sight()` 是否仍在 |
| 冲锋 / 远程穿墙起手 | `has_clear_corridor()` / `has_terrain_line_of_sight()` 门禁是否仍在候选与开火路径中 |
| 突击枪手中途转向或少发 / 多发 | ranged windup / burst 状态是否只读 `_locked_direction`；`burst_shots_remaining` 是否逐发减一，最后一发后才进入冷却 |
| 冲锋穿过玩家 | 上一位置→当前位置的线段扫掠是否包含双方命中半径 |
| 冲锋沿墙继续 | `_move_with_collision(..., false)` 是否仍在释放段使用，碰撞后是否立即结束 |
| 爆猎者前摇能被打断 | `_arm_explosion()` 是否在同一帧设置 armed、禁用碰撞并让 `receive_damage()` 早退 |
| 连锁同帧递归或奖励乱序 | 目标是否先冻结并按 `runtime_spawn_serial` 排序；连锁目标是否只 armed 而不立即 detonate |
| 敌人错误锁定其他敌人 | `_sense_context()` 是否只构造玩家候选；debug `focus_target` 是否仅为玩家或守家时为空 |
| 敌人互相扣血 | `Enemy.receive_damage()` 的 `team_enemy` 早期拒绝是否仍存在 |
| 敌人中心重叠 | separation radius / strength 和物理帧更新是否执行 |
| 穿过或出生在封锁格 | `CharacterBody2D` shape、模块墙体碰撞、placement footprint 与 walkable 校验 |
| 续局保留已删除动作 | `restore_snapshot()` 是否校验 action 仍在当前 profile；非法动作应清空并在下一决策 tick 重选 |
| 池化敌人残留状态 | `configure()`、`_pool_release()`、`_pool_reset()` 是否清理组件与计时器 |

## 测试义务

- 改 profile / enemies 数据：`validate_data.py`、`test_data_loader_schema.py`、`sync_contracts.py --check`。
- 改 `enemy.gd`：GDScript / semantic lint、headless boot、runtime smoke；模块墙体 / 出生相关追加 module-world smoke。
- 改基础 / 专属敌人场景或池绑定：追加 `actor-scene-smoke`，验证继承、必需节点、场景颜色 / 几何不被 `configure()` 覆盖，以及五个独立池生成 / 复用不串场景。
- 改稳定行为、数据指纹或刷怪：重录并回放四条 checked-in golden replay。
- 改实体状态或 run 快照：追加 L1、runtime 与 save smoke，验证 Run v8 阶段 / 击退 roundtrip；远程点射覆盖前摇与点射中途的计时 / 剩余弹数一致、旧 v8 缺字段回空闲、非法快照清空并冷却。
- 性能 probe 只在用户明确要求性能测试时运行。

## 迁移 / 兼容

- Run schema 为 v8；v7→v8 只标记 `legacy_run_incompatible`，正式启动删除旧 run 并保留 Meta v2。
- Run v8 恢复当前 profile 已删除的 action 时清空阶段并在下一决策 tick 重选；合法攻击阶段按剩余时间继续，不得重复提交。
- `burst_shots_remaining` 是 Run v8 的兼容性增量：旧 v8 缺字段时清空远程阶段并以空闲恢复；字段存在但点射阶段、计时、方向或剩余弹数非法时，清空攻击并应用一次当前远程冷却，防止重复发弹。
- schema v1–v4 profile、旧 `sense_radius`、旧 movement 攻击字段与旧 contact CSV 表头必须被双端 validator 拒绝，不做静默忽略。

## 相关文档

- `docs/游戏设计文档.md` §5.3
- `docs/决策记录.md` ADR #144 / #145 / #170 / #171 / #172
- `docs/AI协作/工作包/F14-EnemyNavigationAndPerception.md`
- `docs/词表与契约.md`
- `docs/代码/gameplay_runtime.md`
- `docs/测试策略.md`
