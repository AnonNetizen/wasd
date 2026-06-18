# F4 最小可玩闭环模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 F4 最小可玩闭环首批运行时代码的阶段性模块契约；拆分 Player、WeaponSystem、Enemy、Spawner、HUD 等长期模块或改变公共行为时必须同步本文档、AI 导航、代码索引和 `docs/AI协作/工作包/F4-MinPlayableLoop.md`。

## 职责

- 在正式 `client/` 内提供一局最小战斗：玩家移动、相机居中、起始武器、池化子弹、池化敌人、波次刷怪、HUD、失败后重开。
- 复用 F3 已建立的数据边界：`player.json`、`characters.json`、`weapons.json`、`enemies.csv`、`spawn_waves.csv` 和 `game_modes.json`。
- 第一版只做标准生存模式、默认角色和默认起始武器的竖切，不实现角色选择、升级选择、局外成长、暂停保存续局、机关运行时、掉落经验球、音频、美术资产或平衡 sim。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改 F4 启动 / 重开 | `client/scripts/gameplay/f4_run_loop.gd` |
| 改玩家移动 / 相机 | `client/scripts/gameplay/f4_player.gd` |
| 改自动开火 / 子弹生成 | `client/scripts/gameplay/f4_weapon_system.gd`、`f4_bullet.gd` |
| 改敌人追击 / 接触伤害 | `client/scripts/gameplay/f4_enemy.gd` |
| 改 HUD 文案 | `client/scripts/gameplay/f4_hud.gd`、`client/locale/strings.csv` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/boot/formal_client_boot.gd` | 数据校验通过后挂载 F4 runtime |
| `client/scripts/gameplay/f4_run_loop.gd` | F4 阶段运行时编排、输入 action 默认注册、对象池注册、刷怪和重开 |
| `client/scripts/gameplay/f4_player.gd` | 玩家移动、四方向瞄准、相机居中、受伤 / 死亡 |
| `client/scripts/gameplay/f4_weapon_system.gd` | 起始武器自动开火和子弹池获取 |
| `client/scripts/gameplay/f4_bullet.gd` | 子弹飞行、射程 / 生命周期裁剪、敌人命中 |
| `client/scripts/gameplay/f4_enemy.gd` | 追击敌人、接触伤害、受伤 / 死亡 |
| `client/scripts/gameplay/f4_hud.gd` | 最小 HUD：生命、击杀、时间、失败提示 |
| `client/tools/f4_runtime_smoke.gd` | F4 headless runtime smoke，覆盖启动、输入、池化、伤害和失败状态 |
| `tools/godot_bridge.py` | `f4-smoke` 命令入口 |
| `docs/代码/combat.md` | 伤害统一入口文档 |

## 场景 / 节点结构

F4 暂时用脚本动态组装，避免提前固化复杂场景：

```text
FormalClientBoot
└── F4RunLoop (Node2D)
    ├── F4ActiveWorld (Node2D)
    │   ├── Player (CharacterBody2D)
    │   │   ├── CenteredCamera (Camera2D)
    │   │   └── WeaponSystem (Node)
    │   ├── bullet_basic_* (pooled F4Bullet, active only)
    │   └── enemy_chaser_* (pooled F4Enemy, active only)
    └── F4Hud (CanvasLayer)
```

闲置子弹和敌人节点归 `PoolManager` autoload 管理。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `FormalClientBoot` 跑数据 schema smoke，成功后创建 `F4RunLoop` | `DataLoader.validate_project_data()` |
| 开局 | 重置 `GameClock`，注册 / 预热子弹和敌人对象池，读取默认模式 / 角色 / 起始武器 | `PoolManager.register_pool()`、`DataLoader.load_json()` |
| 输入 | 运行时确保 InputMap action 有键盘和手柄默认事件；业务读取 action，不读物理键 | `InputMap`、`Input.get_vector()` |
| 移动 / 瞄准 | 玩家按数据移速移动，瞄准吸附到上下左右，松开保持上一方向 | `F4Player.aim_direction` |
| 自动开火 | WeaponSystem 按 `fire_rate` 从子弹池取节点并配置 | `PoolManager.acquire()` |
| 子弹命中 | 子弹用距离检测命中 `f4_enemies` 组，伤害走 `Combat.apply_damage()` | `DamageInfo` |
| 刷怪 | Spawner 读取 `spawn_waves.csv` 的时间窗、间隔、上限和预算，在视野外围刷敌人 | `GameClock.now()`、`RNG.spawn` |
| 敌人行为 | 敌人追向玩家，接触时通过 `Combat` 对玩家造成数据化伤害 | `F4Enemy.defeated` |
| 失败 / 重开 | 玩家生命归零进入 `GameState.GAME_OVER`，HUD 显示本地化提示；按 `pause` 重载当前场景 | `GameState.change_state()` |
| 自动 smoke | `godot_bridge.py f4-smoke` 以 `--f4-smoke` 用户参数启动正式主场景，并挂载 smoke runner 做关键断言 | `client/tools/f4_runtime_smoke.gd` |

## 公共 API

F4 脚本当前是阶段性内部模块，主要公共面向为 signal 和实体生命周期：

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `F4Player.configure(base_stats)` | 合并后的玩家属性 | `void` | `move_speed` / `max_hp` 来自数据 |
| `F4Player.receive_damage(info)` | `DamageInfo` | result dictionary | 只能由 `Combat.apply_damage()` 间接调用 |
| `F4WeaponSystem.configure(player, active_parent, weapon_data)` | 玩家、活跃父节点、武器数据 | `void` | 武器数据来自 `weapons.json` |
| `F4Bullet.configure(stats, projectile, direction, source)` | 武器属性、弹体数据、方向、来源 | `void` | 节点必须来自 `PoolManager` |
| `F4Enemy.configure(enemy_data, target)` | 敌人 CSV 行、目标玩家 | `void` | 节点必须来自 `PoolManager` |
| `F4Hud.set_life()` / `set_kills()` / `show_game_over()` | HUD 状态 | `void` | 文案使用 `tr()` |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `F4Player.life_changed` | `current_life`, `max_life` | 玩家生命初始化或变化 |
| `F4Player.died` | 无 | 玩家生命归零 |
| `F4Enemy.defeated` | `enemy`, `exp_reward` | 敌人生命归零 |

## 数据与契约

- 角色：默认读取 `character_default`，其 id 来自生成常量 `CharacterIds`。
- 模式：默认读取 `mode_standard_survival`，其 id 来自生成常量 `GameModes`。
- 武器：从 `characters[].starting_loadout.weapon_id` 读取，不在代码写武器 id 分支。
- 子弹池：从 `weapons[].projectile.pool_id` 读取；当前样例为已登记 `bullet_basic`。
- 敌人池：从 `enemies.csv.pool_id` 读取；当前样例为已登记 `enemy_chaser`。
- 伤害类型：从 `weapons.json` / `enemies.csv` 读取，交给 `Combat` 校验。
- HUD 文案：`ui_hud_life`、`ui_hud_kills`、`ui_hud_time`、`ui_game_over`、`ui_restart_hint`。

## 依赖

- 上游依赖：`DataLoader`、`GameState`、`GameClock`、`RNG.spawn`、`PoolManager`、`Combat`、InputMap action 常量、locale。
- 下游调用方：当前无；后续可拆分为正式 Player / WeaponSystem / Spawner / HUD 模块。
- 禁止依赖：不得复制历史 MVP 代码；不得直接 `instantiate()` 高频实体；不得直接扣生命；不得绕过 InputMap 读物理输入；不得用裸随机或原始时间。

## 扩展点

- 加武器：优先改 `weapons.json`，运行时继续解释 `base_stats` 和 `projectile`。
- 加敌人：优先改 `enemies.csv` 和后续可复用 AI strategy；不要在 F4 enemy 里按 id 分支。
- 加刷怪：改 `spawn_waves.csv`；多个波次可复用当前时间窗 / 预算解释。
- 拆正式模块：当 F4 稳定后，将 `f4_*` 阶段脚本拆为长期 `Player`、`WeaponSystem`、`Bullet`、`Enemy`、`Spawner`、`Hud` 模块，并保留本文档迁移说明。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调玩家速度 / 生命 | `player.json` / `characters.json` | `client/data/README.md` | `python tools/validate_data.py` |
| 调武器伤害 / 射速 / 弹速 | `weapons.json` | `client/data/README.md` | `validate_data` + headless |
| 调敌人血量 / 速度 / 接触伤害 | `enemies.csv` | `client/data/README.md` | `validate_data` + 手动跑一局 |
| 调刷怪节奏 | `spawn_waves.csv` | `client/data/README.md` | `validate_data` + 手动 1 分钟 |
| 改 HUD 文案 | `strings.csv` | `client/locale/README.md` | `validate_data` |
| 改运行时行为 | `client/scripts/gameplay/*.gd` | 本文档、必要时 GDD / ADR | L0 + L2 + `f4-smoke`，必要时补 L1 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动没有进入 F4 | `DataLoader.validate_project_data()` 是否通过；`FormalClientBoot` 日志 |
| 无法移动 | InputMap action 是否存在；`F4RunLoop._ensure_input_actions()` 是否执行 |
| 不开火 | `starting_loadout.weapon_id` 是否存在；`fire_rate` 是否大于 0；子弹池是否注册 |
| 不刷怪 | `spawn_waves.csv` 时间窗、预算、`max_alive` 是否允许；敌人池是否注册 |
| 子弹打不到 | `hit_radius`、敌人位置、`bullet_range` / `lifetime` 是否合理 |
| 失败后无法重开 | 是否处于 `GameState.GAME_OVER`；`pause` action 是否触发 |

## 测试义务

- F4 运行时代码改动必跑：`python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`。
- 涉及启动、输入、WeaponSystem、子弹、敌人、Spawner、Combat 或失败状态时追加 `python tools/godot_bridge.py --project client f4-smoke`。
- 数据 / locale 变化还要跑 `python tools/validate_data.py`、`python tools/lint_project_rules.py`。
- 当前没有 GUT runner，F4 首切片用 L0 + L2 + `f4-smoke` + 手动 1 分钟跑通作为阶段门槛；后续接入 Godot 测试时补 Player / Combat / Pool / Spawner 的 L1。

## 迁移 / 兼容

当前不写存档、不写回放文件，不影响 save schema。进入 F5 run 续局时，需要把玩家、敌人、子弹、Spawner 波次、`GameClock` 和 RNG 状态纳入 `SaveManager` run payload，而不是保存对象池内部状态。

## 相关文档

- `docs/AI协作/工作包/F4-MinPlayableLoop.md`
- `docs/正式项目工作规划.md` F4
- `docs/游戏设计文档.md` §3 / §4 / §5.3 / §9.13 / §9.15.1
- `docs/代码/combat.md`
