# MVP Client 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/代码文档规范.md`、`MinimumViableProduct/README.md` 与 `MinimumViableProduct/docs/MVP设计说明.md`。
> 本文档是 MVP 客户端代码契约权威；改公共 API、signal、场景结构、输入绑定、失败流程、刷怪规则或测试义务时必须同步本文档。

---

## 职责

- 在 `MinimumViableProduct/client/` 内提供一个独立 Godot 4.6.3 原型客户端。
- 验证固定玩家、四方向瞄准、自动射击、四方向刷怪、HP / 计时 / 击杀 HUD、失败重开和手柄输入。
- 保持 MVP 与正式项目 `client/` 隔离；MVP 代码可以采用轻量折中，但折中必须记录在 MVP 文档中。

本模块不负责完整项目的长期架构，不实现正式 `Settings`、`GameState`、`PoolManager`、`Combat`、本地化、存档、回放或完整数据驱动管线。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 快速了解有哪些脚本 | `代码位置` 与 `场景树` |
| 理解一局如何跑起来 | `运行流程` |
| 改键盘 / 手柄输入 | `输入契约` 与 `输入映射细表` |
| 改 HP、射速、子弹速度、刷怪速度 | `数据与契约` 与 `常见改动入口` |
| 判断什么能迁移正式项目 | `已知限制` 与 `迁移到正式项目` |
| 改完怎么验证 | `人工验证清单` 与 `测试义务` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `MinimumViableProduct/client/project.godot` | MVP 独立 Godot 项目入口 |
| `MinimumViableProduct/client/scenes/main.tscn` | 主场景，组装背景、玩家、刷怪器、HUD、失败面板 |
| `MinimumViableProduct/client/scenes/player.tscn` | 固定玩家场景，包含 `AimInput` 与 `Weapon` 子节点 |
| `MinimumViableProduct/client/scenes/bullet.tscn` | 子弹碰撞与视觉场景 |
| `MinimumViableProduct/client/scenes/enemy.tscn` | 敌人碰撞与视觉场景 |
| `MinimumViableProduct/client/data/mvp_config.json` | MVP 轻量配置：玩家、输入、武器 / 子弹、敌人、刷怪、背景关键数值 |
| `MinimumViableProduct/client/data/README.md` | `mvp_config.json` 字段说明 |
| `MinimumViableProduct/client/scripts/main.gd` | 轻量 GameSession：HP、时间、击杀、失败、重开、HUD |
| `MinimumViableProduct/client/scripts/aim_input.gd` | 四方向输入，运行时补键盘 / 手柄 InputMap 绑定 |
| `MinimumViableProduct/client/scripts/player.gd` | 固定玩家、瞄准方向同步、受伤 signal、玩家占位绘制 |
| `MinimumViableProduct/client/scripts/weapon.gd` | 自动开火，按当前方向实例化子弹 |
| `MinimumViableProduct/client/scripts/bullet.gd` | 子弹移动、寿命、命中敌人、子弹占位绘制 |
| `MinimumViableProduct/client/scripts/enemy.gd` | 敌人朝玩家推进、接触伤害、被击杀 signal、敌人占位绘制 |
| `MinimumViableProduct/client/scripts/spawner.gd` | 上、右、下、左固定顺序循环刷怪 |
| `MinimumViableProduct/client/scripts/debug_tools.gd` | debug/dev_tools 构建专用 GM 指令控制台；正式 release 不创建入口 |
| `MinimumViableProduct/client/scripts/background.gd` | 深色网格背景、四方向通道、中心准星绘制 |

## 场景树

### `main.tscn`

```text
Main (Node2D, main.gd)
├── Background (Node2D, background.gd)
├── Player (player.tscn instance)
├── Enemies (Node2D)
├── Spawner (Node2D, spawner.gd)
└── HUD (CanvasLayer)
    ├── HudPanel (ColorRect)
    ├── StatusLabel (Label)
    └── GameOverPanel (ColorRect)
        └── GameOverLabel (Label)

DebugTools (CanvasLayer, debug_tools.gd)  # 仅 debug/dev_tools 构建由 main.gd 动态创建
└── DebugConsolePanel (ColorRect)
    ├── Output (Label)
    └── CommandInput (LineEdit)
```

| 节点 | 被谁引用 | 维护注意 |
|------|----------|----------|
| `Player` | `main.gd`、`Spawner.target_path` | 改名会影响 `$Player` 与 `NodePath("../Player")` |
| `Enemies` | `main.gd`、`Spawner.spawn_parent_path` | 存放运行时刷出的敌人，失败时会被清空 |
| `Spawner` | `main.gd` | 发出 `enemy_spawned`，失败后被停用 |
| `HUD/StatusLabel` | `main.gd` | 显示 HP、时间、击杀数、当前瞄准方向 |
| `HUD/GameOverPanel/GameOverLabel` | `main.gd` | 显示失败结算与重开提示 |

### `player.tscn`

```text
Player (Node2D, player.gd)
├── AimInput (Node, aim_input.gd)
└── Weapon (Node2D, weapon.gd)
```

| 节点 | 被谁引用 | 维护注意 |
|------|----------|----------|
| `AimInput` | `player.gd` | 提供当前方向和 `aim_changed` signal |
| `Weapon` | `player.gd` | 接收瞄准方向，按间隔生成子弹 |

### `bullet.tscn` 与 `enemy.tscn`

| 场景 | 根节点 | 碰撞层 | 碰撞目标 | 维护注意 |
|------|--------|--------|----------|----------|
| `bullet.tscn` | `Area2D` | 2 | mask 4 | 只响应有 `take_hit()` 的 Area |
| `enemy.tscn` | `Area2D` | 4 | mask 0 | 通过距离检测接触玩家，不依赖物理碰撞回调 |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `MvpAimInput.get_current_direction()` | 无 | `Vector2` | 返回当前四方向瞄准向量，默认 `Vector2.UP` |
| `MvpAimInput.get_current_direction_name()` | 无 | `String` | 返回 HUD 用配置方向名，默认配置为 `上` / `下` / `左` / `右` |
| `MvpAimInput.apply_config(config)` | `Dictionary` | 无 | 应用 `input.gamepad_deadzone` 与 `input.direction_names`，并同步 InputMap action 死区 |
| `MvpPlayer.get_aim_direction_name()` | 无 | `String` | 供 `main.gd` 初始化 HUD |
| `MvpPlayer.set_active(active)` | `bool` | 无 | 失败后停用玩家与武器 |
| `MvpPlayer.apply_config(player_config, weapon_config, input_config)` | `Dictionary`, `Dictionary`, `Dictionary` | 无 | 应用玩家受伤反馈，并把武器 / 输入配置转发给子节点 |
| `MvpPlayer.take_damage(amount)` | `int` | 无 | 玩家非 active 时忽略伤害 |
| `MvpWeapon.apply_config(config)` | `Dictionary` | 无 | 应用射速、子弹速度 / 寿命 / 伤害 / 碰撞半径和枪口距离 |
| `MvpWeapon.set_aim_direction(direction)` | `Vector2` | 无 | 忽略 `Vector2.ZERO`，内部归一化 |
| `MvpWeapon.set_active(active)` | `bool` | 无 | 停用后不再自动开火 |
| `MvpBullet.setup(direction, speed, life_seconds, damage_amount, collision_radius)` | `Vector2`, `float`, `float`, `int`, `float` | 无 | 设置速度、寿命、伤害、碰撞半径与旋转；调用方需传非零方向 |
| `Enemy.setup(target_node, speed, config)` | `Node2D`, `float`, `Dictionary` | 无 | 目标必须是玩家节点或兼容 `Node2D`；配置来自 `enemy` section |
| `Enemy.apply_config(config)` | `Dictionary` | 无 | 应用敌人速度、HP、接触伤害、接触半径和碰撞半径 |
| `Enemy.take_hit(damage)` | `int` | 无 | HP 归零触发 `killed` 后销毁 |
| `Spawner.apply_config(spawner_config, enemy_config)` | `Dictionary`, `Dictionary` | 无 | 应用刷怪节奏，并保存敌人配置供后续 spawn 使用 |
| `Spawner.set_spawning_enabled(enabled)` | `bool` | 无 | 失败后由 `main.gd` 调用以停止刷怪 |
| `Spawner.spawn_enemy_now(count)` | `int` | `int` | GM / 调试入口立即按现有刷怪规则生成敌人，返回成功生成数量 |
| `Background.apply_config(config)` | `Dictionary` | 无 | 应用背景网格、通道宽度和中心标记尺寸后重绘 |
| `main.gd.get_debug_stats()` | 无 | `Dictionary` | debug/dev_tools 构建读取 HP、时间、击杀、敌人数量和刷怪状态 |
| `main.gd.debug_set_hp(new_hp)` | `int` | 无 | GM 设置 HP；归零会走正常失败流程 |
| `main.gd.debug_damage_player(amount)` | `int` | 无 | GM 伤害玩家；走主场景扣血流程 |
| `main.gd.debug_heal_player(amount)` | `int` | 无 | GM 治疗玩家；不超过 `max_hp` |
| `main.gd.debug_spawn_enemies(count)` | `int` | `int` | GM 通过 `Spawner.spawn_enemy_now()` 刷怪 |
| `main.gd.debug_clear_enemies(count_as_kills)` | `bool` | `int` | GM 清怪；`kill` 命令会把清除数计入击杀 |
| `main.gd.debug_set_spawning_enabled(enabled)` | `bool` | 无 | GM 开关刷怪；失败状态下不重新启用 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `MvpAimInput.aim_changed` | `direction: Vector2`, `direction_name: String` | 四方向瞄准方向变化 |
| `MvpPlayer.aim_changed` | `direction_name: String` | 玩家接受新的瞄准方向并同步武器后 |
| `MvpPlayer.damage_taken` | `amount: int` | 玩家受到敌人接触伤害 |
| `Enemy.killed` | 无 | 敌人 HP 归零 |
| `Spawner.enemy_spawned` | `enemy: Node` | 刷怪器生成敌人并完成 setup 后 |

## 运行流程

### 启动流程

| 顺序 | 发生什么 | 关键代码 |
|------|----------|----------|
| 1 | Godot 加载 `main.tscn` | `project.godot` 的 `run/main_scene` |
| 2 | `main.gd` 读取 `res://data/mvp_config.json` | `_load_config()` |
| 3 | `main.gd` 分发玩家、武器、输入、敌人、刷怪和背景配置 | `_apply_config()`、各节点 `apply_config()` |
| 4 | `main.gd` 把玩家放到 viewport 中心 | `player.global_position = get_viewport_rect().size * 0.5` |
| 5 | `main.gd` 连接玩家、刷怪器和 HUD | `aim_changed`、`damage_taken`、`enemy_spawned` |
| 6 | debug/dev_tools 构建动态加载调试控制台 | `_setup_debug_tools()`、`OS.is_debug_build()`、`OS.has_feature("dev_tools")` |
| 7 | `aim_input.gd` 确保键盘 / 手柄 action 绑定存在 | `_ensure_default_input_map()` |
| 8 | `player.gd` 读取初始瞄准方向并同步武器 | `weapon.call("set_aim_direction", aim_direction)` |
| 9 | `spawner.gd` 找到玩家目标和敌人父节点 | `target_path`、`spawn_parent_path` |

### 每帧战斗流程

| 顺序 | 发生什么 | 关键代码 |
|------|----------|----------|
| 1 | `AimInput` 读取 InputMap action 并吸附到四方向 | `Input.get_vector()`、`_snap_to_cardinal()` |
| 2 | 玩家收到方向变化并更新武器 | `_on_aim_changed()` |
| 3 | 武器冷却结束后实例化子弹 | `_fire()` |
| 4 | 子弹沿方向移动并递减寿命 | `MvpBullet._physics_process()` |
| 5 | 刷怪器按固定顺序生成敌人 | `_next_spawn_position()` |
| 6 | 敌人朝玩家位置推进 | `global_position.direction_to(target.global_position)` |
| 7 | 子弹命中敌人后按配置伤害调用 `take_hit()` | `MvpBullet._on_area_entered()`、`weapon.bullet_damage` |
| 8 | 敌人死亡发出 `killed`，主场景增加击杀数 | `Enemy.killed`、`_on_enemy_killed()` |

### 失败与重开流程

| 顺序 | 发生什么 | 关键代码 |
|------|----------|----------|
| 1 | 敌人进入玩家半径内 | `distance_to(target.global_position) <= hit_radius` |
| 2 | 敌人按配置接触伤害调用玩家 `take_damage()` 后销毁自己 | `target.call("take_damage", contact_damage)` |
| 3 | 玩家发出 `damage_taken` | `damage_taken.emit(amount)` |
| 4 | `main.gd` 扣 HP 并判断是否失败 | `_on_player_damage_taken()` |
| 5 | 失败时停用玩家和刷怪器，清空敌人 | `_trigger_game_over()` |
| 6 | Game Over 面板显示时间与击杀数 | `game_over_label.text = ...` |
| 7 | 失败后按 `ui_accept` 重载当前场景 | `get_tree().reload_current_scene()` |

## 输入契约

- MVP 玩法代码只消费 Godot InputMap action，不直接读取物理键位或设备差异。
- `aim_input.gd` 在运行时确保 `ui_up` / `ui_down` / `ui_left` / `ui_right` 有方向键、手柄 D-pad、左摇杆、右摇杆绑定。
- `ui_accept` 在 MVP 中用于失败后重开，默认覆盖 Enter、Space 与手柄 A。
- `debug_tools.gd` 在 debug/dev_tools 构建中运行时确保 `debug_toggle_console` / `debug_submit_command` / `debug_close_console` 存在；正式 release 不创建该节点。
- MVP 与正式项目差异：MVP 玩家不能移动，所以左摇杆临时也用于瞄准；正式项目左摇杆应留给移动，右摇杆 / D-pad 用于瞄准。

## 输入映射细表

| MVP action | 键盘 | 手柄按钮 | 手柄轴 | 用途 |
|------------|------|----------|--------|------|
| `ui_up` | `KEY_UP` | `JOY_BUTTON_DPAD_UP` | `JOY_AXIS_LEFT_Y = -1`、`JOY_AXIS_RIGHT_Y = -1` | 向上瞄准 |
| `ui_down` | `KEY_DOWN` | `JOY_BUTTON_DPAD_DOWN` | `JOY_AXIS_LEFT_Y = 1`、`JOY_AXIS_RIGHT_Y = 1` | 向下瞄准 |
| `ui_left` | `KEY_LEFT` | `JOY_BUTTON_DPAD_LEFT` | `JOY_AXIS_LEFT_X = -1`、`JOY_AXIS_RIGHT_X = -1` | 向左瞄准 |
| `ui_right` | `KEY_RIGHT` | `JOY_BUTTON_DPAD_RIGHT` | `JOY_AXIS_LEFT_X = 1`、`JOY_AXIS_RIGHT_X = 1` | 向右瞄准 |
| `ui_accept` | `KEY_ENTER`、`KEY_SPACE` | `JOY_BUTTON_A` | 无 | 失败后重开 |
| `debug_toggle_console` | `KEY_F1`、`` ` `` | 无 | 无 | debug/dev_tools 构建切换 GM 控制台 |
| `debug_submit_command` | `KEY_ENTER` | 无 | 无 | debug/dev_tools 构建提交 GM 指令 |
| `debug_close_console` | `KEY_ESCAPE` | 无 | 无 | debug/dev_tools 构建关闭 GM 控制台 |

| 参数 | 当前值 | 说明 |
|------|--------|------|
| `input.gamepad_deadzone` | `0.35` | 低于该强度的摇杆输入不改变方向，来自 `mvp_config.json` |
| 四方向吸附规则 | 最大轴优先 | `abs(x) > abs(y)` 时左右优先，否则上下优先 |
| 松开输入行为 | 保持上次方向 | `Input.get_vector()` 返回零向量时不触发变化 |

## 数据与契约

MVP 只使用一个轻量 JSON：`MinimumViableProduct/client/data/mvp_config.json`，字段说明见 `MinimumViableProduct/client/data/README.md`。

| Section | 读取方 | 覆盖内容 |
|---------|--------|----------|
| `player` | `main.gd`、`player.gd` | `max_hp`、`damage_flash_seconds` |
| `input` | `aim_input.gd` | `gamepad_deadzone`、四方向 HUD 显示文本 |
| `weapon` | `weapon.gd`、`bullet.gd` | 射速、子弹速度、寿命、伤害、碰撞半径、枪口距离 |
| `enemy` | `spawner.gd`、`enemy.gd` | 敌人速度、HP、接触伤害、接触半径、碰撞半径 |
| `spawner` | `spawner.gd` | 刷怪间隔、刷怪边距、开局冷却 |
| `background` | `background.gd` | 网格尺寸、四方向通道宽度、中心标记尺寸 |
| `ui` | `main.gd` | HUD 状态文本、HUD 模板和失败面板模板 |

约束：

- 调玩法节奏优先改 `mvp_config.json`，不要改脚本默认值或场景导出值。
- 脚本默认值只作为配置缺失 / 字段缺失时的兜底。
- MVP 暂不做正式 `DataLoader`、JSON Schema、热重载、词表常量或 fail-fast 数据管线；这些仍属于完整项目 `client/` 的长期要求。

## 调试工具 / GM 指令

MVP 的 GM 指令控制台只在 `OS.is_debug_build()` 或自定义 feature `dev_tools` 存在时由 `main.gd` 动态加载 `res://scripts/debug_tools.gd`。正式 release 构建不创建 `DebugTools` 节点；后续导出 preset 应排除 `scripts/debug_tools.gd`。

| 命令 | 作用 | 约束 |
|------|------|------|
| `help` | 输出命令列表 | 无 |
| `stats` | 显示 HP、时间、击杀、敌人数量和刷怪状态 | 只读 |
| `heal [n]` | 治疗玩家 | 不超过 `max_hp` |
| `hp <n>` | 设置玩家 HP | 归零走正常 Game Over 流程 |
| `damage [n]` | 对玩家造成伤害 | 走 `main.gd` 扣血流程 |
| `spawn [n]` | 立即刷出 n 个敌人 | 通过 `Spawner.spawn_enemy_now()`，沿用现有刷怪规则 |
| `clear` | 清除当前敌人 | 不增加击杀数 |
| `kill` | 清除当前敌人并计入击杀 | 用于复盘击杀节奏，不代表正式伤害管线 |
| `spawner on/off` | 开关自动刷怪 | 失败状态下不重新启用 |
| `reset` | 重载当前场景 | 等同重新开始 MVP |

## 依赖

| 模块 | 上游依赖 | 下游调用方 |
|------|----------|------------|
| `main.gd` | `mvp_config.json`、`Player`、`Spawner`、`Background`、HUD 节点、`Enemies` 容器 | Godot 主场景 |
| `player.gd` | `AimInput`、`Weapon` 子节点 | `main.gd`、`Enemy` |
| `aim_input.gd` | Godot `InputMap` / `Input` | `player.gd` |
| `weapon.gd` | `weapon` 配置、`bullet_scene`、当前场景树 | `player.gd` |
| `bullet.gd` | `weapon` 配置、`Enemy.take_hit()` 约定 | `weapon.gd` |
| `enemy.gd` | `enemy` 配置、`target.take_damage()` 约定 | `spawner.gd`、`bullet.gd`、`main.gd` |
| `spawner.gd` | `spawner` / `enemy` 配置、`enemy_scene`、`target_path`、`spawn_parent_path` | `main.gd` |
| `background.gd` | `background` 配置、当前 viewport size | `main.tscn` |
| `debug_tools.gd` | `main.gd` 暴露的 debug API、InputMap debug action | debug/dev_tools 构建的 `DebugTools` 节点 |

禁止依赖：MVP 代码不得依赖根目录正式 `client/`，不得把 MVP 临时逻辑迁入正式项目，除非先经过复盘与 ADR。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 改玩家初始 HP | `mvp_config.json` 的 `player.max_hp` | `MinimumViableProduct/client/data/README.md` | 试玩到受伤和失败 |
| 改 HUD 文案 | `mvp_config.json` 的 `ui.*` | `MinimumViableProduct/client/data/README.md` | 启动并观察 HUD、失败面板 |
| 改 HUD 布局 | `main.tscn`、`main.gd` | 本文档 `场景树`、`运行流程` | 启动并观察 HUD、失败面板 |
| 改射速 | `mvp_config.json` 的 `weapon.fire_interval` | `MinimumViableProduct/client/data/README.md` | 试玩 30 秒观察发射频率 |
| 改子弹速度 / 寿命 / 伤害 | `mvp_config.json` 的 `weapon.bullet_*` | `MinimumViableProduct/client/data/README.md` | 试玩确认子弹射程、命中和击杀次数 |
| 改敌人速度 / HP / 接触伤害 | `mvp_config.json` 的 `enemy.*` | `MinimumViableProduct/client/data/README.md` | 试玩确认压力节奏、击杀次数和受伤 |
| 改刷怪间隔 | `mvp_config.json` 的 `spawner.spawn_interval` | `MinimumViableProduct/client/data/README.md` | 试玩 60 秒观察刷怪密度 |
| 改刷怪顺序或位置 | `spawner.gd` 的 `_next_spawn_position()` | 本文档 `运行流程`、`扩展点` | 观察上、右、下、左是否符合预期 |
| 改手柄绑定 | `aim_input.gd` 的 `_ensure_default_input_map()` | 本文档 `输入契约`、`输入映射细表` | 实体手柄试玩 D-pad、左右摇杆、A 键 |
| 改方向显示文本 | `mvp_config.json` 的 `input.direction_names` | `MinimumViableProduct/client/data/README.md` | 启动观察 HUD Aim 文本 |
| 改手柄死区 | `mvp_config.json` 的 `input.gamepad_deadzone` | `MinimumViableProduct/client/data/README.md` | 实体手柄试玩斜向 / 小幅摇杆输入 |
| 改背景网格或中心标记尺寸 | `mvp_config.json` 的 `background.*` | `MinimumViableProduct/client/data/README.md` | 启动观察背景可读性 |
| 改失败条件 | `enemy.gd`、`player.gd`、`main.gd` | 本文档 `失败与重开流程`、`Signal / Event` | 试玩到 Game Over 并重开 |
| 改 GM 指令 | `debug_tools.gd`、`main.gd`、必要时 `spawner.gd` | 本文档 `调试工具 / GM 指令`、根目录 GDD 9.20 | debug/dev_tools 构建手动验证；release 构建确认无入口 |
| 拆出 `game_session.gd` | 新脚本、`main.tscn`、`main.gd` | 本文档所有涉及 `main.gd` 的表格 | Headless 启动 + 完整人工试玩 |

## 扩展点

- 调整玩法节奏：优先改 `mvp_config.json`，不要散落脚本常量。
- 增加失败 / 结算信息：改 `main.gd` 与 HUD 节点，并同步本文档 Signal / API。
- 继续扩展手柄输入：保留 InputMap action 抽象，设备差异只放绑定层。
- 增加敌人或子弹变体：MVP 可先复制场景验证，但若准备迁移完整项目，必须改为正式数据驱动内容。
- 扩展 GM 指令：优先通过 `main.gd` 暴露少量 debug API，再由 `debug_tools.gd` 调用；不要在 GM 指令里直接越过现有玩法流程。

## 人工验证清单

| 场景 | 检查项 |
|------|--------|
| 启动 | 主场景能打开，玩家在屏幕中心，HUD 显示 HP、Time、Kills、Aim |
| 键盘瞄准 | 方向键上下左右都能切换瞄准方向，松开后保持最后方向 |
| 手柄 D-pad | D-pad 上下左右都能切换瞄准方向 |
| 手柄摇杆 | 左摇杆和右摇杆都能切换四方向，斜向输入按最大轴吸附 |
| 自动射击 | 不按开火键也会持续按 `mvp_config.json` 配置间隔发射子弹 |
| 子弹命中 | 子弹碰到敌人后按配置伤害扣 HP，敌人死亡后 Kills 增加 |
| 敌人接触 | 敌人接触玩家后 HP 减少，敌人消失，玩家有受伤描边反馈 |
| Game Over | HP 归零后停止刷怪和射击，敌人清空，失败面板显示生存时间和击杀数 |
| 重开 | Enter、Space、手柄 A 都能重载当前场景 |
| 无手柄 | 没插手柄时键盘操作正常，不报错 |
| GM 控制台 | debug/dev_tools 构建按 F1 或反引号可打开；`stats`、`spawn 4`、`heal 1`、`spawner off`、`clear`、`reset` 能生效 |
| 正式隔离 | release 构建不显示 GM 控制台，`debug_*` 输入无可见效果，导出资源不包含 `debug_tools.gd` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 玩家不显示在中心 | `main.gd` 是否仍设置 `player.global_position`，viewport 尺寸是否正常 |
| HUD 不更新方向 | `AimInput.aim_changed` 是否连接到 `player.gd`，`MvpPlayer.aim_changed` 是否连接到 `main.gd` |
| 子弹不出现 | `player.tscn` 的 `Weapon.bullet_scene` 是否指向 `bullet.tscn` |
| 子弹不打敌人 | `bullet.tscn` collision mask 是否包含敌人层，敌人是否暴露 `take_hit()` |
| 敌人不生成 | `Spawner.enemy_scene`、`target_path`、`spawn_parent_path` 是否正确 |
| 击杀数不增加 | `Spawner.enemy_spawned` 是否连接，`Enemy.killed` 是否被 `main.gd` 连接 |
| 玩家不会受伤 | `enemy.gd` 的 `hit_radius` 是否太小，玩家是否暴露 `take_damage()` |
| Game Over 后仍刷怪 | `_trigger_game_over()` 是否调用 `spawner.set_spawning_enabled(false)` |
| 手柄无响应 | `aim_input.gd` 是否执行 `_ensure_default_input_map()`，设备是否被 Godot 识别 |
| 调配置没生效 | `mvp_config.json` 是否是合法 JSON，字段是否在正确 section，是否重启了 MVP 场景 |
| GM 控制台打不开 | 是否处于 debug 构建，或导出 preset 是否带 `dev_tools` feature；release 构建打不开是预期行为 |

## 已知限制

- MVP 当前直接 `instantiate()` / `queue_free()` 高频实体，属于隔离原型折中；正式项目必须改为 `PoolManager`。
- MVP 当前 HUD 文案和方向名集中在 `mvp_config.json`，但仍不接完整项目 `Localization`；正式项目必须走本地化键。
- MVP 当前使用轻量 `mvp_config.json` 集中核心调参值，但没有正式 `DataLoader`、schema 校验或热重载；正式项目必须走 `client/data/*.json` + `DataLoader`。
- MVP 当前失败状态由 `main.gd` 管理，属于轻量 GameSession；正式项目必须走 `GameState` / `UIManager`。
- MVP 当前 GM 指令控制台是轻量单脚本实现；正式项目必须拆成 `DebugConsole` / `GMCommandRegistry` 等独立模块，并在 release preset 排除资源。

## 迁移到正式项目

| MVP 经验 | 正式项目落点 | 迁移要求 |
|----------|--------------|----------|
| 四方向瞄准输入 | `InputController` + `Settings` + `docs/词表与契约.md` action | 使用生成常量，不直接写 `ui_*` 或物理输入 |
| 手柄支持 | InputMap action 默认绑定 | 左摇杆移动，右摇杆 / D-pad 瞄准，支持重绑定 |
| 自动射击 / 原型配置化 | `WeaponSystem` + `DataLoader` | 射速、伤害、子弹速度来自 `client/data/*.json`，并有 schema / 词表校验 |
| 击杀上报 | `Enemy` / `Combat` / `Analytics` | 伤害走 `Combat.apply_damage`，埋点走 `Analytics` |
| 失败流程 | `GameState` + `UIManager` | 不由业务脚本直接管理全局状态或 UI 弹窗 |
| 敌人和子弹生命周期 | `PoolManager` | 高频实体必须池化，不能直接复制 MVP 的 `queue_free()` 模式 |
| HUD 文案 | `Localization` | 玩家可见文本必须走 `tr("key")` |
| GM 指令控制台 | `DebugConsole` / `GMCommandRegistry` | 仅 debug/dev_tools 构建启用；命令通过正式系统 API 改状态，release preset 排除调试资源 |

## 测试义务

- 每次修改 MVP 客户端脚本后，至少运行 `godot --headless --path MinimumViableProduct/client --quit`。
- 每次修改 `mvp_config.json` 后，至少运行 `py -3 -m json.tool MinimumViableProduct/client/data/mvp_config.json > $null`。
- 改输入时，需要人工试玩键盘方向键、手柄 D-pad、左摇杆、右摇杆和 `ui_accept` 重开。
- 改刷怪、伤害、重开、HUD 或核心配置时，需要人工试玩一轮从开局到失败再重开。
- 改 GM 指令或调试入口时，需要验证 debug/dev_tools 构建可用，并确认 release 构建无入口、无调试资源。
- 改文档时运行 `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`，并额外检查未跟踪 MVP 文档的尾随空白。

## 相关文档

- `MinimumViableProduct/README.md`
- `MinimumViableProduct/docs/MVP设计说明.md`
- `MinimumViableProduct/docs/开发计划.md`
- `MinimumViableProduct/docs/MVP决策记录.md`
- `MinimumViableProduct/docs/经验记录.md`
- `MinimumViableProduct/client/README.md`
- `MinimumViableProduct/client/data/README.md`
- `docs/代码文档规范.md`
