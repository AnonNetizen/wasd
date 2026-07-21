# Enemy AI 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/代码文档规范.md`、`docs/游戏设计文档.md` 与 `client/data/README.md`。
> 本文档是敌人 AI 的代码契约；改敌人感知、效用评分、动作状态机、敌方友伤护栏、AI profile schema 或 run 快照字段时，必须同步本文档、`docs/代码/gameplay_runtime.md`、`client/data/README.md`、`docs/AI导航.md`、GDD 和测试策略。

## 职责

- 让同一 `Enemy` 场景通过数据 profile 表现追击、快速近战、冲锋、守家、环绕和远程攻击等对玩家行为。
- 感知与战斗目标固定为玩家；出生点只服务守家与回位，不扫描、猎食、逃离或攻击其他敌人。
- 通过 Utility 评分选择动作、FSM 执行蓄力 / 冲锋、Steering 处理移动与无伤害中心分离；模块模式消费共享流场、地形视线与局部 AStar waypoint。
- 所有伤害通过 `Combat.apply_damage()`；`Enemy.receive_damage()` 拒绝 `team_enemy` 来源，避免敌方互伤。
- 保持模块封锁格碰撞、全图边界、对象池、保存续局和回放可控。
- 持续状态由 `StatusEffectComponent` 承担，不把沉默、减速、DoT 等状态硬写进 AI profile。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 调某类敌人的对玩家行为 | `client/data/enemy_ai_profiles.json` |
| 调敌人基础数值 / profile 绑定 | `client/data/enemies.csv` |
| 改感知、评分、动作执行、分离或友伤 | `client/scripts/gameplay/enemy.gd` |
| 排查刷怪 / 恢复 | `client/scripts/gameplay/gameplay_run_loop.gd` |
| 排查模块墙体、导航或出生合法性 | `client/scripts/gameplay/module_navigation_field.gd`、`module_world_manager.gd`、`module_chunk.gd` |
| 排查状态效果 | `docs/代码/status_effect_component.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/enemy.gd` | profile 解释、目标感知、动作评分 / 执行、伤害、中心分离、快照 |
| `client/scenes/entities/enemy.tscn` | 单一池化敌人场景；根节点为 `CharacterBody2D` |
| `client/scripts/gameplay/module_navigation_field.gd` | 99×99 静态 mask、共享 Dijkstra 流场、局部 AStar 与视线 / 走廊查询 |
| `client/data/enemy_ai_profiles.json` | schema v3 对玩家 AI profile |
| `client/data/enemies.csv` | 基础数值、通用内容 tag、对象池和 profile 引用 |
| `client/scripts/contracts/enemy_ai_actions.gd` | 由词表生成的 action 常量 |
| `client/tools/runtime_smoke.gd` | 五种敌人对玩家行为、友伤护栏、中心分离和旧动作恢复 |
| `tools/validate_data.py` / `tools/test_data_loader_schema.py` | schema v3、旧 `sense_radius` 与旧生态字段负例门禁 |

## 场景 / 节点结构

```text
Enemy (CharacterBody2D)
├── CollisionShape2D
└── StatusEffectComponent
```

- `CollisionShape2D` 负责敌人与模块墙体的物理碰撞；模块 JSON 的封锁格会合并为静态碰撞。
- 敌人中心分离在物理帧内施加轻量位移，只防止中心完全重合，不产生伤害或目标关系。

## 运行流程

| 阶段 | 发生什么 | 关键点 |
|------|----------|--------|
| 配置 | `GameplayRunLoop` 合并敌人基础数据与 profile 后调用 `configure(enemy_data, player, navigation_provider)` | 模块模式注入 `ModuleWorldManager`，开放战区传空并使用直线兜底 |
| 感知 | 决策 tick 依次判断地形视线 + 直线距离、共享流场路径距离、最后已知位置记忆 | 记忆期间不读取玩家实时位置；不扫描其他敌人 |
| 评分 | profile 的 `actions[]` 对合法动作评分 | 行为差异来自数据，不按 enemy id 分支 |
| 执行 | 畅通时直追，受阻时读共享流场；守家 / 记忆读决策 tick 缓存的 AStar waypoint；冲锋经 FSM | 冲锋要求清晰走廊，远程开火要求当前地形视线 |
| 分离 | 收集近邻敌人中心并施加非伤害分离 | 不改变 focus target 或动作评分 |
| 边界 | 普通移动、冲锋、分离和快照恢复后统一 clamp 到有限地图边界 | 模块模式还必须通过 walkable / 物理墙体约束 |
| 受伤 | `receive_damage()` 先拒绝 `team_enemy`，再处理环境或玩家伤害 | 保留最后来源队伍用于玩家击杀归因 |
| 保存 | 保存位置、生命、home、动作 / FSM、cooldown、状态效果和来源队伍 | 不保存节点引用或临时感知缓存 |

## 数据与契约

### `enemies.csv`

- `tags` 必须含且只使用当前已登记的通用敌人内容 tag；正式五种敌人均使用 `tag_enemy`。
- `ai_profile_id` 必填，且必须存在于 `enemy_ai_profiles.json.profiles[].id`。
- `pool_id` 只决定对象池；多个敌人可以复用同一场景或 profile。

### `enemy_ai_profiles.json` schema v3

| 字段 | 约束 | 说明 |
|------|------|------|
| `schema_version` | 必须为 `3` | v2 的单一 `sense_radius` 与 v1 生态字段不得继续加载 |
| `profiles[].id` | 唯一非空字符串 | 由敌人数据引用 |
| `perception.sight_radius` | `> 0` | 360° 地形视线畅通时的视觉半径 |
| `perception.path_awareness_radius` | `>= 0` 且 `<= sight_radius` | 隔墙但可达时按流场路径距离感知玩家 |
| `perception.memory_duration` | `>= 0` | 失去当前感知后追最后已知位置的时间 |
| `decision_interval` | `> 0` | Utility 重算间隔 |
| `targeting.player_weight` | `>= 0` | 玩家候选权重；玩家仍是唯一候选 |
| `movement.*` | 按动作字段校验 | 接近、环绕、冲锋、守家、远程参数 |
| `actions[]` | 非空、id 来自词表 | 可参与评分的对玩家动作 |

schema v3 明确拒绝 `sense_radius`；旧的接触间隔、猎食 / 逃跑目标数组和逃跑距离字段仍按 schema v2 删除规则拒绝。词表也不再登记旧逃跑 action 与三个生态 tag，后续不得以兼容名义重新接受。

当前 profiles：

| profile | 对玩家行为 |
|---------|------------|
| `enemy_ai_chase_contact` | 基础追击 |
| `enemy_ai_fast_chase` | 快速接近与近战 |
| `enemy_ai_charge_stalker` | 接近、环绕并蓄力冲锋 |
| `enemy_ai_home_guard` | 以出生点为活动中心，范围内攻击玩家 |
| `enemy_ai_ranged_spitter` | 保持距离、环绕并发射池化投射物 |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(enemy_data, target, navigation_provider = null)` | 合并数据、玩家节点、可选模块导航门面 | `void` | 对象池取得后的唯一配置入口；无门面时直线兜底 |
| `set_movement_bounds(half_extents)` | 地图半尺寸 | `void` | 所有移动路径统一使用 |
| `ai_debug_summary()` | 无 | `Dictionary` | 读取 profile、动作、目标、感知状态、路径距离、最后已知位置、记忆余量与导航模式 |
| `was_defeated_by_player()` | 无 | `bool` | 仅玩家来源击杀发放收益 |
| `combat_team_id()` | 无 | `String` | 返回 `team_enemy` |
| `apply_status_effect(effect)` | `StatusEffect` | `bool` | 由统一状态系统调用 |
| `snapshot()` / `restore_snapshot(data)` | 无 / `Dictionary` | `Dictionary` / `void` | run v4 兼容恢复 |
| `receive_damage(info)` | `DamageInfo` | result dictionary | `team_enemy` 返回未应用且生命不变 |

无对外 `content_tags()` 接口；其他敌人不是感知候选。

## Signal / Event

- `defeated(enemy)`：生命降至零后触发；调用方通过 `was_defeated_by_player()` 决定是否发放玩家收益。

## 依赖

- 上游：`DataLoader`、`GameClock`、`GameState`、`PoolManager`、`Combat`、`DamageInfo`、`StatusEffectComponent`、`ModuleWorldManager` 可选导航门面、地图边界和生成契约常量。
- 下游：`GameplayRunLoop`、runtime / module-world / save smoke、回放工具。
- 禁止依赖：原始输入、原始时间、裸随机、运行时网络模型；不得绕过 `Combat` 扣血，不得按 enemy id 写行为分支，不得恢复敌人种间目标选择或伤害。

## 扩展点

- 新敌人优先复用现有 profile；确需新行为时新增通用 action / 字段并同步词表、双端 schema、快照和 smoke。
- 远程敌人复用 `ai_action_ranged_attack` 与 `movement.ranged_*`；投射物必须池化并只命中玩家队伍。
- 新复杂状态只保存 JSON 友好的可恢复字段；节点引用和临时感知结果不进存档。
- 新导航或地形感知通过 `ModuleWorldManager` 查询门面扩展，不得让 Enemy 依赖活动 chunk，也不得借机引入其他敌人作为 focus target。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调快速怪接近速度 | `enemy_ai_profiles.json`、`enemies.csv` | 数据手册 | data/schema + runtime smoke |
| 调冲锋频率 | `charge_range`、`charge_cooldown`、动作分数 | 数据手册 | runtime smoke + golden replay |
| 调守家半径 | `movement.home_radius` / `leash_distance` | 数据手册 | runtime smoke |
| 调远程压力 | `movement.ranged_*` | 数据手册 | data/schema + runtime smoke |
| 新增 AI profile | profile JSON、敌人引用 | 本文、数据手册 | data/schema + runtime smoke |
| 改快照恢复 | `enemy.gd`、`gameplay_run_loop.gd` | 本文、Save 文档 | runtime + L1 + save smoke |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 敌人不动 | profile 是否有合法 action、`move_speed`、`GameState` 和玩家引用 |
| 敌人持续顶墙 | `navigation_mode` 是否切到 `flow_field`；Manager 是否已在 assignment / restore 后重建 mask；玩家格是否可走 |
| 隔墙无限追踪 | `perception_state`、路径距离阈值和 `memory_remaining`；记忆期间 `last_known_position` 不得跟随玩家更新 |
| 冲锋 / 远程穿墙起手 | `has_clear_corridor()` / `has_terrain_line_of_sight()` 门禁是否仍在候选与开火路径中 |
| 敌人错误锁定其他敌人 | `_sense_context()` 是否只构造玩家候选；debug `focus_target` 是否仅为玩家或守家时为空 |
| 敌人互相扣血 | `Enemy.receive_damage()` 的 `team_enemy` 早期拒绝是否仍存在 |
| 敌人中心重叠 | separation radius / strength 和物理帧更新是否执行 |
| 穿过或出生在封锁格 | `CharacterBody2D` shape、模块墙体碰撞、placement footprint 与 walkable 校验 |
| 续局保留已删除动作 | `restore_snapshot()` 是否校验 action 仍在当前 profile；非法动作应清空并在下一决策 tick 重选 |
| 池化敌人残留状态 | `configure()`、`_pool_release()`、`_pool_reset()` 是否清理组件与计时器 |

## 测试义务

- 改 profile / enemies 数据：`validate_data.py`、`test_data_loader_schema.py`、`sync_contracts.py --check`。
- 改 `enemy.gd`：GDScript / semantic lint、headless boot、runtime smoke；模块墙体 / 出生相关追加 module-world smoke。
- 改稳定行为、数据指纹或刷怪：重录并回放四条 checked-in golden replay。
- 改实体状态或 run 快照：追加 L1 与 save smoke，验证旧 v4 payload fallback。
- 性能 probe 只在用户明确要求性能测试时运行。

## 迁移 / 兼容

- run schema 保持 v4；`last_damage_source_team`、`was_defeated_by_player()` 和原有快照字段继续保留。
- 旧 v4 快照若携带当前 profile 不再允许的 action，恢复时清空 action / FSM / timer，下一次决策 tick 选择合法动作。
- schema v2 profile、旧 `sense_radius` 与旧生态 profile 必须被 DataLoader 和 Python validator 拒绝；不做静默字段忽略。
- 旧快照缺少 AI、状态或来源字段时沿用现有默认恢复规则。

## 相关文档

- `docs/游戏设计文档.md` §5.3
- `docs/决策记录.md` ADR #144 / #145
- `docs/AI协作/工作包/F14-EnemyNavigationAndPerception.md`
- `docs/词表与契约.md`
- `docs/代码/gameplay_runtime.md`
- `docs/测试策略.md`
