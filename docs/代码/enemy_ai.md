# Enemy AI 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/代码文档规范.md`、`docs/游戏设计文档.md` 与 `client/data/README.md`。
> 本文档是敌人生态 AI 的代码契约；改敌人感知、效用评分、动作状态机、怪物互相伤害、AI profile schema 或 run 快照字段时，必须同步本文档、`docs/代码/gameplay_runtime.md`、`client/data/README.md`、`docs/AI导航.md`、GDD 和测试策略。

## 职责

- 让同一 `Enemy` 场景通过数据 profile 表现追击、逃跑、狩猎、巡守、冲锋等行为。
- 支持敌人感知玩家、其他敌人和出生点 / 领地，不再只写死“朝玩家直线前进”。
- 用 Utility AI 做动作选择，用小型 FSM 执行有阶段的动作（当前是冲锋蓄力 / 释放），用 Steering 负责移动方向。
- 所有伤害仍走 `Combat.apply_damage()`；敌人打死敌人不会计入玩家击杀，也不会掉经验。
- 保持对象池、保存续局和回放可控：节点来自 `PoolManager`，可恢复 AI 状态只保存 JSON 友好字段，不保存节点引用。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 调敌人行为倾向 | `client/data/enemy_ai_profiles.json` |
| 加新敌人但复用行为 | `client/data/enemies.csv` 的 `ai_profile_id` |
| 加新 AI 动作 | `docs/词表与契约.md` §12-B、`enemy.gd` 的 `_action_candidate()` / `_apply_current_action()` |
| 调怪物互相克制 | `enemy_ai_profiles.json.targeting.hunt_tags` / `flee_tags` 与 `enemies.csv.tags` |
| 排查保存续局 | `Enemy.snapshot()` / `restore_snapshot()` 与 `docs/代码/save_manager.md` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/enemy.gd` | 敌人占位表现、感知、Utility 评分、动作执行、接触伤害、受伤死亡和快照 |
| `client/data/enemy_ai_profiles.json` | 复杂 AI profile：感知半径、目标权重、动作列表和动作参数 |
| `client/data/enemies.csv` | 敌人基础数值、内容 tag、对象池 id 与 `ai_profile_id` |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 读取 profile、把 profile 合并进 enemy_data、刷怪和死亡归因 |
| `client/scripts/contracts/enemy_ai_actions.gd` | 由词表生成的 AI action 常量 |
| `client/tools/runtime_smoke.gd` | 覆盖猎物逃离掠食者、掠食者锁定猎物的生态 smoke |
| `tools/validate_data.py` / `tools/test_data_loader_schema.py` | 数据 schema 和坏数据回归 |

## 运行流程

| 阶段 | 发生什么 | 关键点 |
|------|----------|--------|
| 数据加载 | `GameplayRunLoop` 先读取 `enemy_ai_profiles.json`，再把 `enemies.csv.ai_profile_id` 对应 profile 放入 `enemy_data.ai_profile` | profile id 不存在会被 DataLoader / validate_data 拦截 |
| 配置 | `Enemy.configure(enemy_data, player)` 记录基础数值、内容 tags、profile、动作列表和出生点 | 节点加入 `active_enemies` 组供其他敌人感知 |
| 感知 | 决策 tick 内扫描玩家与 `active_enemies`，按 `player_weight`、`hunt_tags`、`flee_tags` 和距离计算候选目标 / 威胁 | 只看带 `content_tags()` 且 `is_alive()` 的敌人 |
| 选择 | 每个 action 由 `_action_candidate()` 得分；最高分成为 `_current_action` 和 `_focus_target` | 当前 action 包括接近、逃离、环绕、冲锋、守家 |
| 执行 | 无阶段动作直接 Steering 移动；冲锋进入 `charge_windup` / `charge_release` FSM | 冲锋结束后进入 cooldown，避免连续锁死 |
| 接触 | 根据当前 action 选择可接触目标；逃跑和无目标守家不造成接触伤害 | 玩家 / 敌人都通过 `Combat.apply_damage()` |
| 死亡 | `Enemy.receive_damage()` 记录最后伤害来源队伍；`GameplayRunLoop._on_enemy_defeated()` 只把玩家击杀计入 kills / XP | 怪物生态可以互相击杀但不刷玩家收益 |
| 保存 | run 快照保存敌人 id、位置、生命、home、当前 action、FSM、冲锋 cooldown 和最后伤害来源队伍 | 恢复后重新 `configure()` 再 `restore_snapshot()` |

## 数据契约

### `enemies.csv`

- `tags` 必须含 `tag_enemy`；生态关系通过额外 tag 表达，例如 `tag_enemy_prey`、`tag_enemy_predator`、`tag_enemy_territorial`。
- `ai_profile_id` 必填，必须存在于 `enemy_ai_profiles.json.profiles[].id`。
- `pool_id` 仍只决定对象池；多个敌人可以复用同一池和同一 `Enemy` 场景。

### `enemy_ai_profiles.json`

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | profile id；由 `enemies.csv.ai_profile_id` 引用 |
| `sense_radius` | float | 感知玩家和其他敌人的最大距离，单位 px |
| `decision_interval` | float | Utility 重新评分间隔，单位秒 |
| `contact_interval` | float | 同一敌人目标之间的接触伤害冷却，避免怪物互咬瞬间清屏 |
| `targeting.player_weight` | float | 追玩家的基础权重；`0` 表示不主动追玩家 |
| `targeting.hunt_tags[]` | array | 可狩猎的敌人 tag 与权重 |
| `targeting.flee_tags[]` | array | 需要逃离的敌人 tag 与权重 |
| `targeting.territory_radius` / `territory_weight` | float | 离出生点过远时守家动作的加分 |
| `movement.*` | object | 动作参数，如环绕半径、冲锋范围、蓄力、释放时长、冷却和速度倍率 |
| `actions[]` | array | 可参与评分的动作；`id` 必须来自词表 §12-B，`base_score` 控制倾向，`speed_scale` 控制该动作移动倍率 |

## 当前 Profiles

| profile | 用途 |
|---------|------|
| `enemy_ai_chase_contact` | 经典直线接近玩家，兼容早期追猎者 |
| `enemy_ai_prey_swarm` | 群集弱怪；会靠近玩家，但遇到掠食者 / 领地怪优先逃跑 |
| `enemy_ai_predator_stalker` | 掠食者；优先狩猎 `tag_enemy_prey`，近距离进入冲锋 |
| `enemy_ai_territorial_guard` | 领地怪；会回到出生点附近，也会攻击玩家或掠食者 |

## 公共 API

| 名称 | 输入 | 输出 | 用途 |
|------|------|------|------|
| `configure(enemy_data, target)` | 敌人数据、玩家节点 | `void` | 对象池取得节点后的唯一配置入口 |
| `content_tags()` | 无 | `Array[String]` | 供其他敌人感知生态关系 |
| `ai_debug_summary()` | 无 | `Dictionary` | smoke / 调试读取 profile、动作、状态、目标和上次评分 |
| `was_defeated_by_player()` | 无 | `bool` | GameplayRunLoop 判断是否发放 kills / XP |
| `snapshot()` / `restore_snapshot(data)` | 无 / Dictionary | Dictionary / void | run 存档恢复 |
| `receive_damage(info)` | `DamageInfo` | result dictionary | 只能经 `Combat.apply_damage()` 调用 |

## 依赖

- 上游依赖：`DataLoader`、`GameClock`、`GameState`、`PoolManager`、`Combat`、`DamageInfo`、生成契约 `EnemyAiActions`、`content_tags`。
- 下游调用方：`GameplayRunLoop`、`runtime-smoke`、未来 debug / 可视化工具。
- 禁止依赖：不得直接读物理输入、原始时间、裸随机或绕过 `Combat` 扣血；不得在 `enemy.gd` 写 `if enemy_id == ...` 的内容分支。

## 扩展点

- 新敌人：先决定是否复用现有 profile；能复用就只改 `enemies.csv`、`game_modes.json`、`spawn_waves.csv` 和 locale。
- 新生态关系：优先加 / 复用 `content_tags`，再调 `hunt_tags` / `flee_tags` 权重。
- 新动作：先在词表 §12-B 登记 action id 并生成常量，再实现评分、执行、必要的快照字段和 smoke。
- 新复杂状态：只把可恢复、JSON 友好的状态写入 snapshot；节点引用、临时感知缓存和 cooldown 字典不进存档。
- 后续如引入导航 / 地形感知，先把环境查询抽成小接口或感知层数据，不把地图规则散落到每个 action。

## 常见改动入口

| 你想改什么 | 主要文件 | 验证 |
|------------|----------|------|
| 调猎物更胆小 | `enemy_ai_profiles.json` 中 `flee_tags.weight` / flee `base_score` | `validate_data` + `runtime-smoke` |
| 调掠食者冲锋频率 | `charge_range`、`charge_cooldown`、`ai_action_charge_target.base_score` | `runtime-smoke` + golden replay |
| 加新生态 tag | `docs/词表与契约.md`、`enemies.csv.tags`、profile 的 hunt/flee tags | `sync_contracts --check` + schema test |
| 新增 AI profile | `enemy_ai_profiles.json`、`enemies.csv.ai_profile_id` | `validate_data` + schema test |
| 改敌人互相击杀收益 | `gameplay_run_loop.gd` 的 `_on_enemy_defeated()` | `runtime-smoke` + 相关 replay |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 敌人不动 | profile 是否有 `actions[]`；`move_speed` 是否大于 0；`GameState` 是否为 `PLAYING` |
| 敌人只追玩家 | `enemies.csv.tags` 是否含生态 tag；profile 的 `hunt_tags` / `flee_tags` 是否有权重；目标是否在 `sense_radius` 内 |
| 掠食者不冲锋 | `charge_range`、`charge_cooldown_remaining`、当前目标距离和 action base_score |
| 怪物互咬太快 | 提高 `contact_interval` 或降低 `contact_damage` / 速度 |
| 怪物互杀给玩家经验 | `was_defeated_by_player()` 与 `_on_enemy_defeated()` 是否仍按最后伤害来源判定 |
| 续局后敌人行为突变 | 快照是否保存 / 恢复了 `home_position`、`current_action`、`action_state`、`action_timer` 和冲锋 cooldown |

## 测试义务

- 改 profile / enemies 数据：跑 `python tools/validate_data.py`、`python tools/test_data_loader_schema.py`、`python tools/sync_contracts.py --check`。
- 改 `enemy.gd`：跑 `python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`、`python tools/godot_bridge.py --project client runtime-smoke`。
- 改 AI 决策、怪物死亡归因、刷怪数据或影响稳定帧样本：重录并回放四条 checked-in golden replay，必要时跑 `perf-probe` 看敌人峰值和帧时间。
- 改 run 快照字段：追加 `save-smoke`，并检查旧 run payload 的迁移 / fallback。

## 迁移 / 兼容

现有 `Enemy` 场景仍是单一 `Node2D` 占位形状；行为差异来自数据而不是新场景。旧敌人数据现在必须补 `ai_profile_id`，否则 DataLoader fail-fast。旧 run 存档如果缺少新增 AI 快照字段，会按当前位置、空动作和默认 cooldown 恢复，保持可加载但不保证回放逐帧一致。

## 相关文档

- `docs/代码/gameplay_runtime.md`
- `docs/代码/combat.md`
- `docs/代码/save_manager.md`
- `client/data/README.md`
- `docs/游戏设计文档.md` §5.3
- `docs/词表与契约.md` §12-B
