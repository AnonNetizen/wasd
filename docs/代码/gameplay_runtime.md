# Gameplay Runtime 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式客户端 gameplay runtime 的聚合模块契约；拆分 Player、WeaponSystem、Enemy、Spawner、HUD 等长期模块或改变公共行为时必须同步本文档、AI 导航、代码索引和相关阶段工作包。

## 职责

- 在正式 `client/` 内提供一局最小战斗：最小标题入口、标题设置入口、标题局外成长摘要与升级入口、玩家移动、相机居中、基础背景参照、起始武器、池化子弹、池化敌人、波次刷怪、经验掉落、升级三选一、HUD、主动暂停、暂停设置入口、暂停保存退出、标题继续游戏、暂停 / 升级 UI 恢复点、失败后结算、重开 / 回标题。
- 复用 F3 已建立的数据边界：`player.json`、`characters.json`、`weapons.json`、`enemies.csv`、`spawn_waves.csv`、`growth.csv`、`growth_pools.json` 和 `game_modes.json`。
- 第一版只做标准生存模式、默认角色和默认起始武器的竖切；F5 首片已接入 gameplay runtime 的 `run` 续局快照，F6 首片已接入死亡结算、`meta` 存档、标题局外升级面板和下一局永久 modifiers；游戏结束页只展示结算收益、账号等级 / 余额、重开和回标题，不提供局外成长购买入口；角色选择、完整商店 / 局外包装、机关运行时、音频、美术资产或平衡 sim 仍未实现。升级内容只落地 `stat_modifier` 最小切片，后续遗物 / 主动强化 / 刷新等仍按数据与设计扩展。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改运行时启动 / 重开 | `client/scripts/gameplay/gameplay_run_loop.gd` |
| 改标题 / 失败面板 | `client/scripts/ui/title_menu.gd`、`client/scripts/ui/game_over_panel.gd` |
| 改标题局外升级面板 | `client/scripts/ui/meta_progression_panel.gd`、`client/scripts/autoload/meta_progression_system.gd`、`client/scripts/boot/formal_client_boot.gd` |
| 改暂停 / 保存退出 | `client/scripts/ui/pause_menu.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`docs/代码/save_manager.md` |
| 改死亡结算 / 永久升级应用 | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/autoload/meta_progression_system.gd`、`client/scripts/ui/game_over_panel.gd` |
| 改玩家移动 / 相机 | `client/scripts/gameplay/player.gd` |
| 改自动开火 / 子弹生成 | `client/scripts/gameplay/weapon_system.gd`、`bullet.gd` |
| 改敌人追击 / 接触伤害 | `client/scripts/gameplay/enemy.gd` |
| 改经验球 / 拾取 | `client/scripts/gameplay/pickup_orb.gd`、`player.json` |
| 改升级候选 / 奖励 | `growth.csv`、`growth_pools.json`、`client/scripts/gameplay/gameplay_run_loop.gd` |
| 改 HUD 文案 | `client/scripts/gameplay/gameplay_hud.gd`、`client/locale/strings.csv` |
| 改稳定节点结构 / UI 层级 | `client/scenes/gameplay/*.tscn`、`client/scenes/ui/*.tscn` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/boot/formal_client_boot.gd` | 数据校验通过后挂载 gameplay runtime |
| `client/scenes/gameplay/gameplay_run_loop.tscn` | 正式 gameplay runtime 场景；包含 `ActiveWorld`、`WorldBackground`、`Player` 和 `GameplayHud` |
| `client/scenes/gameplay/player.tscn` | 正式玩家场景；包含 `CenteredCamera` 与 `WeaponSystem` |
| `client/scenes/gameplay/bullet.tscn` / `enemy.tscn` / `pickup_orb.tscn` | 对象池实体场景；由 `PoolManager` 工厂实例化并复用 |
| `client/scenes/ui/title_menu.tscn` / `pause_menu.tscn` / `settings_panel.tscn` / `game_over_panel.tscn` / `level_up_panel.tscn` / `meta_progression_panel.tscn` | 正式 UI 场景；脚本只绑定稳定节点、连接 signal 和刷新数据 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 正式运行时编排、输入 action 手柄兜底注册、对象池注册、刷怪和重开 |
| `client/scripts/gameplay/world_background.gd` | 世界网格背景，让玩家移动具备空间参照 |
| `client/scripts/gameplay/player.gd` | 玩家移动、四方向瞄准、相机居中、受伤 / 死亡 |
| `client/scripts/gameplay/weapon_system.gd` | 起始武器自动开火和子弹池获取 |
| `client/scripts/gameplay/bullet.gd` | 子弹飞行、射程 / 生命周期裁剪、敌人命中 |
| `client/scripts/gameplay/enemy.gd` | 追击敌人、接触伤害、受伤 / 死亡 |
| `client/scripts/gameplay/pickup_orb.gd` | 池化经验球：进入玩家拾取范围后吸附并发放经验 |
| `client/scripts/gameplay/level_up_panel.gd` | 响应式升级三选一面板；通过 `UIManager.push()` 挂载；语言切换时用缓存候选重建按钮 |
| `client/scripts/gameplay/gameplay_hud.gd` | 响应式最小 HUD：生命、击杀、时间、等级、经验、升级获得反馈；语言切换时用当前 HUD 状态重画 |
| `client/scripts/ui/title_menu.gd` | 最小标题界面：账号等级 / 余额摘要、开始 / 继续 / 局外升级 / 设置 / 退出 |
| `client/scripts/ui/settings_panel.gd` | F7 设置面板：从标题或暂停菜单打开，读写 `Settings` 并响应语言切换 |
| `client/scripts/ui/meta_progression_panel.gd` | F6 阶段局外升级面板：从标题菜单打开，显示余额、账号等级、所有升级轨道、购买状态和购买反馈；语言切换时刷新标题、余额、升级列表和可见反馈 |
| `client/scripts/ui/pause_menu.gd` | F5 / F7 暂停菜单：继续、设置、保存并退出、重新开始、回标题；语言切换时刷新按钮 |
| `client/scripts/ui/game_over_panel.gd` | 失败面板：结算摘要、账号等级 / 余额、重开 / 回标题；语言切换时用缓存结算重画 |
| `client/tools/runtime_smoke.gd` | gameplay runtime headless smoke，覆盖启动、输入、池化、伤害、失败状态和真实死亡结算 |
| `client/tools/meta_progression_smoke.gd` | F6 MetaProgression smoke，覆盖 meta roundtrip、结算、购买和永久 modifier |
| `client/tools/save_manager_smoke.gd` | F5 SaveManager run 存档可靠性 smoke，覆盖 roundtrip、备份回退、坏档隔离和迁移 |
| `client/tools/perf_probe.gd` | F8 轻量 perf / 平衡采样入口，输出帧时间、池水位、等级和击杀等 JSON 指标 |
| `tools/godot_bridge.py` | `runtime-smoke` / `save-smoke` / `meta-smoke` / `settings-smoke` / F8 `l1-smoke`、`replay-smoke`、`perf-probe` 命令入口 |
| `docs/代码/combat.md` | 伤害统一入口文档 |

## 场景 / 节点结构

Gameplay runtime 的稳定节点结构已迁入正式 `.tscn` 场景资源。脚本职责是读取数据、绑定场景节点、连接 signal 和刷新运行时状态；不再在业务脚本中临时拼出长期 UI / runtime 层级。允许动态生成的范围限于对象池工厂实例化场景、升级候选按钮、局外升级列表这类数据驱动重复项。

```text
FormalClientBoot
└── GameplayRunLoop (Node2D)
    ├── ActiveWorld (Node2D)
    │   ├── WorldBackground (Node2D)
    │   ├── Player (CharacterBody2D)
    │   │   ├── CenteredCamera (Camera2D)
    │   │   └── WeaponSystem (Node)
    │   ├── bullet_basic_* (pooled Bullet scene, active only)
    │   ├── enemy_chaser_* (pooled Enemy scene, active only)
    │   └── enemy_swarm_* (pooled Enemy scene, active only)
    └── GameplayHud (CanvasLayer)
UIManager
    └── UIRoot
    ├── TitleMenu (normal boot before a run; includes MetaProfileSummaryLabel)
    ├── MetaProgressionPanel (opened from title menu)
    ├── SettingsPanel (opened from title menu or pause menu)
    ├── PauseMenu (only while GameState.PAUSED)
    ├── LevelUpPanel (only while GameState.LEVEL_UP)
    └── GameOverPanel (only while GameState.GAME_OVER)
```

闲置子弹、敌人和经验球节点归 `PoolManager` autoload 管理。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `FormalClientBoot` 跑数据 schema smoke，正常启动显示 `TitleMenu`；标题菜单显示账号等级 / 局外货币摘要，有可购买升级时局外升级按钮显示可购买提示；标题菜单可打开 `MetaProgressionPanel` 查看 / 购买局外升级，也可打开 `SettingsPanel` 修改设置；`--runtime-smoke` 模式跳过标题并直接创建 `GameplayRunLoop` | `DataLoader.validate_project_data()`、`UIManager.push()` |
| 开局 | `FormalClientBoot` 实例化 `gameplay_run_loop.tscn`；运行时重置 `GameClock`，注册 / 预热子弹、经验球和当前 F4 敌人对象池，读取默认模式 / 角色 / 起始武器，并在玩家 / 武器配置后应用 `MetaProgressionSystem.current_modifiers()` | `PackedScene.instantiate()`、`PoolManager.register_pool()`、`DataLoader.load_json()`、`MetaProgressionSystem.current_modifiers()` |
| 背景 | 在玩家附近绘制世界空间网格和原点十字，让相机移动有参照 | `WorldBackground.configure()` |
| 输入 | `Settings` 在启动 / 加载 / 修改时把键盘主绑定写入 InputMap；运行时只确保同一 action 有手柄轴 / 按钮兜底事件。业务读取 action，不读物理键 | `Settings`、`InputMap`、`Input.get_vector()` |
| 移动 / 瞄准 | 玩家按数据移速移动，瞄准吸附到上下左右，松开保持上一方向；角色用方向指示器显示当前瞄准方向 | `Player.aim_direction` |
| 自动开火 | WeaponSystem 按 `fire_rate` 从子弹池取节点并配置 | `PoolManager.acquire()` |
| 子弹命中 | 子弹用距离检测命中 `active_enemies` 组，伤害走 `Combat.apply_damage()` | `DamageInfo` |
| 刷怪 | Spawner 读取 `spawn_waves.csv` 的时间窗、间隔、上限和预算，在视野外围刷敌人；当前有追猎者与疾行者两种数据化敌人 | `GameClock.now()`、`RNG.spawn` |
| 受击 / 击杀反馈 | 玩家和敌人受伤时短暂闪白；敌人死亡后立即离开活敌组，短暂放大淡出后归池；玩家进入数据化受伤无敌窗口 | `_draw()` / `queue_redraw()` |
| 敌人行为 | 敌人追向玩家，重叠时持续通过 `Combat` 尝试接触伤害；敌人中心按 `separation_radius` 做小范围排斥，碰到玩家 `player_separation_radius` 时只推开敌人，是否伤害玩家由玩家无敌窗口判定 | `Enemy.defeated` |
| 经验掉落 | 敌人死亡时按 `exp_reward` 生成池化经验球；经验球进入玩家 `pickup_range` 后显示吸附反馈，贴近玩家时立即发放经验并短暂弹出淡出后归池 | `PoolManager.acquire(PICKUP_ORB)` |
| 升级选择 | 累计经验达到 `growth.csv` 阈值后进入 `GameState.LEVEL_UP`，玩法时间冻结；HUD 显示本级经验进度（升级后从 0 重新计入下一等级段）；候选从模式声明的 `growth_pools` 中按权重和 `RNG.ui_choice` 抽取；升级面板可在暂停态响应鼠标选择，也可按 `pause` action 把暂停菜单叠到升级面板上；选择后应用 `stat_modifier`、显示获得反馈并回到 `PLAYING` | `LevelUpPanel.choice_selected`、`LevelUpPanel.pause_requested` |
| 主动暂停 | `pause` action 在 `PLAYING` 中打开 `PauseMenu`，在 `LEVEL_UP` 中由升级面板请求把 `PauseMenu` 叠在升级面板上；菜单通过 `UIManager` 请求 `GameState.PAUSED`，玩法时间、敌人、子弹和刷怪冻结，菜单仍响应鼠标、`ui_back` 和再次 `pause` action；暂停菜单可打开 `SettingsPanel`，关闭后仍回到同一个暂停菜单；关闭升级态上方的暂停菜单后必须回到 `LEVEL_UP` | `UIManager.push()`、`GameState.PAUSED` |
| 保存退出 / 继续 | 暂停菜单“保存并退出”生成 `run` payload 并写入 `SaveManager`；标题菜单检测到 `run.save` 后显示“继续游戏”，加载 payload 后由 gameplay runtime 通过对象池重建活跃敌人、子弹和经验球，并按 `ui_restore` 回到普通游玩、暂停菜单或升级选择面板；若续局读取失败，坏档由 `SaveManager` 隔离，标题菜单显示重置提示并隐藏继续按钮 | `SaveManager.save()`、`SaveManager.load_envelope()`、`configure_restore_snapshot()` |
| UI 布局 | HUD 使用全屏锚点下的 `MarginContainer + VBoxContainer`；升级面板使用全屏遮罩、居中容器和按视口宽度夹取的面板宽度，随窗口尺寸调整 | `Control.set_anchors_preset()` |
| 运行时语言刷新 | `Localization.locale_changed` 发出后，标题、暂停、设置、HUD、升级、结算和局外成长面板用自身缓存的状态或配置数据刷新文本；订阅的 UI 在 `_exit_tree()` 断开 signal，避免离树节点收到后续语言切换 | `Localization.locale_changed`、`refresh_texts()` |
| 失败 / 结算 / 重开 | 玩家生命归零后先向 `MetaProgressionSystem` 提交本局摘要并写入 `meta`，再删除 `run` 存档、进入 `GameState.GAME_OVER`、冻结 `GameClock` 并显示唯一失败面板；失败面板只展示本局结算摘要、账号经验、当前账号等级、账号等级提升提示、余额、重开和回标题，不提供局外成长购买或跳转入口。玩家可重开或回标题，按 `pause` 仍可快捷重开 | `MetaProgressionSystem.apply_run_settlement()`、`SaveManager.delete(run)`、`UIManager.push()`、`GameState.change_state()`、`GameplayRunLoop.restart_requested` |
| 自动 smoke / probe | `godot_bridge.py runtime-smoke` 以 `--runtime-smoke` 用户参数启动正式主场景，并挂载 runtime smoke；`save-smoke` / `meta-smoke` / `settings-smoke` 分别挂载对应 smoke；F8 `perf-probe` 会启动一局并输出可比较指标 | `client/tools/runtime_smoke.gd` / `client/tools/save_manager_smoke.gd` / `client/tools/meta_progression_smoke.gd` / `client/tools/settings_smoke.gd` / `client/tools/perf_probe.gd` |

## 公共 API

F4 脚本当前是阶段性内部模块，主要公共面向为 signal 和实体生命周期：

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `Player.configure(base_stats)` | 合并后的玩家属性 | `void` | `move_speed` / `max_hp` / `damage_invulnerability_duration` / `player_separation_radius` 来自数据 |
| `Player.invulnerability_remaining()` | 无 | `float` | 只读诊断值；用于 smoke / 调试确认玩家侧无敌窗口是否归零 |
| `Player.pickup_range()` / `pickup_orb_speed()` / `luck()` / `separation_radius()` | 无 | `float` | 只读运行时属性；经验球、升级候选数量判定和玩家中心排斥使用 |
| `Player.apply_modifiers(modifiers)` | `growth_pools.json` 的 modifiers | `void` | 按 `(基础 + 加法) * 乘法` 更新玩家运行时属性 |
| `Player.receive_damage(info)` | `DamageInfo` | result dictionary | 只能由 `Combat.apply_damage()` 间接调用；无敌期返回 `reason=invulnerable` 且不扣生命 |
| `WeaponSystem.configure(player, active_parent, weapon_data)` | 玩家、活跃父节点、武器数据 | `void` | 武器数据来自 `weapons.json` |
| `WeaponSystem.apply_modifiers(modifiers)` | `growth_pools.json` 的 modifiers | `void` | 按 `(基础 + 加法) * 乘法` 更新武器运行时属性 |
| `WeaponSystem.stat_value(stat)` | stat id | `float` | smoke / 调试读取当前武器数值 |
| `Bullet.configure(stats, projectile, direction, source)` | 武器属性、弹体数据、方向、来源 | `void` | 节点必须来自 `PoolManager` |
| `Enemy.configure(enemy_data, target)` | 敌人 CSV 行、目标玩家 | `void` | 节点必须来自 `PoolManager` |
| `Enemy.separation_radius()` / `visual_color()` / `is_defeat_feedback_active()` | 无 | `float` / `Color` / `bool` | 只读诊断值；用于中心排斥、占位色、死亡反馈和 smoke 确认 |
| `PickupOrb.configure(amount, target, pickup_speed)` | 经验值、目标玩家、吸附速度 | `void` | 节点必须来自 `PoolManager` |
| `PickupOrb.is_attracting()` / `is_collect_feedback_active()` | 无 | `bool` | 只读诊断值；用于 smoke 确认吸附 / 拾取反馈生命周期 |
| `GameplayRunLoop.current_xp()` / `current_level_xp()` / `current_level_xp_required()` | 无 | `int` | `current_xp()` 是累计总经验；HUD 使用本级经验和本级需求显示升级进度 |
| `GameplayRunLoop.create_run_snapshot()` | 无 | `Dictionary` | 生成 `SaveManager` 的 `run` payload；只保存 JSON 友好的状态，不保存节点或对象池内部队列；`ui_restore` 记录普通游玩、暂停菜单或升级选择面板恢复点 |
| `GameplayRunLoop.configure_restore_snapshot(snapshot)` | `Dictionary` | `void` | 在节点入树前由 `FormalClientBoot` 调用；`_ready()` 后重建玩家、武器、敌人、子弹、经验球、RNG、GameClock 和 `ui_restore` 状态 |
| `LevelUpPanel.configure(choices)` / `choose_index(index)` | 升级候选 | `void` | 面板节点通过 `UIManager` 挂载；玩家可见文案来自 locale；面板宽度随视口宽度在最小 / 最大值之间自适应；按 `pause` action 时发出 `pause_requested`；语言切换时重用 `_choices` 重建按钮 |
| `GameplayHud.set_life()` / `set_kills()` / `set_level()` / `set_xp()` / `show_upgrade_feedback()` | HUD 状态 | `void` | 文案使用 `tr()`；布局使用容器和锚点而非固定屏幕坐标；失败 UI 由 `GameOverPanel` 独占显示；语言切换时重用缓存生命、击杀、等级、经验和最近升级反馈 key 刷新 |
| `TitleMenu.refresh_meta_summary()` | 无 | `void` | 刷新标题菜单账号等级 / 余额摘要；有可购买升级时把 `MetaProgressionButton` 文案切到可购买提示，局外升级面板关闭后由 `FormalClientBoot` 调用 |
| `TitleMenu.start_requested` / `continue_requested` / `meta_progression_requested` / `settings_requested` / `quit_requested` | 无 | signal | 由 `FormalClientBoot` 处理，不在标题菜单里直接创建 run；`continue_requested` 只在有 `run` 存档时可见；`meta_progression_requested` 和 `settings_requested` 会通过 `UIManager` 打开对应面板 |
| `MetaProgressionPanel.closed_requested` | 无 | signal | 由 `FormalClientBoot` 从标题菜单弹出面板并回到标题；购买升级由面板调用 `MetaProgressionSystem.purchase_upgrade()` 后刷新列表、余额和购买反馈；语言切换时刷新标题、关闭按钮、列表和可见反馈；关闭按钮和 `ui_back` 共用 `request_close()` |
| `PauseMenu.resume_requested` / `settings_requested` / `save_and_quit_requested` / `restart_requested` / `quit_to_title_requested` | 无 | signal | 由 `GameplayRunLoop` 处理；设置只叠加 `SettingsPanel`，保存退出保留 `run` 存档，重开 / 回标题会删除旧 `run` 存档；`ui_back` 通过 `request_close()` 走继续游戏路径 |
| `GameOverPanel.configure(kills, run_time, settlement)` | 击杀、时长、结算结果 | `void` | F6 只展示结算奖励、账号等级 / 余额、重开和回标题；文案全部来自 locale；语言切换时重用缓存的击杀、时长和结算字典重画 |
| `GameOverPanel.restart_requested` / `quit_to_title_requested` | 无 | signal | 由 `GameplayRunLoop` 转发给 `FormalClientBoot` 清理并切换流程 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `Player.life_changed` | `current_life`, `max_life` | 玩家生命初始化或变化 |
| `Player.died` | 无 | 玩家生命归零 |
| `Enemy.defeated` | `enemy`, `exp_reward` | 敌人生命归零 |
| `PickupOrb.collected` | `amount` | 经验球被玩家拾取 |
| `LevelUpPanel.choice_selected` | `choice` | 玩家选择一个升级候选 |
| `LevelUpPanel.pause_requested` | 无 | 玩家在升级选择面板按 `pause` action 请求打开暂停菜单 |
| `PauseMenu.resume_requested` | 无 | 玩家选择继续或再次按 `pause` |
| `PauseMenu.save_and_quit_requested` | 无 | 玩家在暂停菜单选择保存并退出 |
| `GameplayRunLoop.restart_requested` | 无 | 玩家在失败后请求重开 |
| `GameplayRunLoop.quit_to_title_requested` | 无 | 玩家在失败后请求回标题 |

## 数据与契约

- 角色：默认读取 `character_default`，其 id 来自生成常量 `CharacterIds`。
- 模式：默认读取 `mode_standard_survival`，其 id 来自生成常量 `GameModes`。
- 武器：从 `characters[].starting_loadout.weapon_id` 读取，不在代码写武器 id 分支。
- 子弹池：从 `weapons[].projectile.pool_id` 读取；当前样例为已登记 `bullet_basic`。
- 敌人池：从 `enemies.csv.pool_id` 读取；当前 F4 注册已登记 `enemy_chaser` 与 `enemy_swarm`，两者复用 `Enemy` 追击行为但用数据区分数值和占位色。
- 敌人中心间距：从 `enemies.csv.separation_radius` 读取；当前默认 9px，低于 `hit_radius` 以允许视觉重叠。
- 玩家中心排斥：从合并后的玩家 `base_stats.player_separation_radius` 读取；当前默认 10px。敌人与玩家的最小中心距离为两者分离半径之和，碰到时只推开敌人，不改变玩家移动手感；接触伤害距离会取敌人 `hit_radius` 与双方分离半径之和的较大值，避免推开后反而打不到玩家。
- 敌人占位色：从 `enemies.csv.visual_color` 读取 HTML 色值，只用于开发期几何占位图，不承载行为分支。
- 受伤无敌：从合并后的玩家 `base_stats.damage_invulnerability_duration` 读取；当前默认 `player.json` 为 0.7 秒。
- 经验球：使用词表 §8 `pickup_orb` 对象池；`player.json.base_stats.pickup_range` 控制吸附范围，`pickup_orb_speed` 控制吸附速度。
- 等级阈值：从 `growth.csv.total_xp_required` 读取累计总经验阈值；运行时内部保留累计经验判定升级，HUD 显示 `当前累计经验 - 当前等级累计阈值` / `下一级累计阈值 - 当前等级累计阈值`。
- 升级候选：从当前模式 `resource_pools.growth_pools` 引用的 `growth_pools.json` 池读取；当前 F4 只解释 `kind=stat_modifier` 且应用其 `modifiers`。
- 分辨率与 UI：默认 viewport 由 `client/project.godot` 设为 1920×1080；窗口禁止任意拖拽缩放，屏幕比例不匹配时通过 `canvas_items + keep` 保比例加黑边；F4 HUD 和升级面板应使用 `Control` 锚点 / 容器布局适配预设分辨率。
- run 续局快照：F5 首片使用 `SaveManager` 的 `run` kind，payload schema version 当前为 1，字段包括模式 / 角色 id、等级、累计经验、击杀、`GameClock.snapshot()`、`RNG.snapshot()`、刷怪状态、玩家状态、武器状态、活跃敌人、活跃子弹、活跃经验球和 `ui_restore`。`ui_restore.state` 当前支持 `playing`、`paused`、`level_up`：暂停保存后续局会先回到暂停菜单；升级选择面板打开时保存会保留已经掷出的候选列表并续回同一组选择，不重新消耗 `RNG.ui_choice`；暂停菜单叠在升级面板上时保存为 `state=paused` 且 `underlying_state=level_up`，恢复时先重建升级面板再叠回暂停菜单。旧 payload 没有 `ui_restore` 时按 `playing` 处理。`SaveManager` 的 `run` kind envelope 当前为 version 2，v1 -> v2 迁移只补齐缺失结构字段，不改变 F4 payload schema。RNG 大整数 state 以字符串保存，避免 JSON 精度变化导致 `data_hash` mismatch。
- 局外成长接入：F6 首片使用 `SaveManager` 的 `meta` kind；F4 只向 `MetaProgressionSystem.apply_run_settlement()` 提交 `kills`、`run_time`、`first_boss_defeated`，不在 F4 复制奖励公式。结算后必须删除 `run` 存档，避免死亡结算后的旧局重复领取奖励。标题菜单通过 `MetaProgressionSystem.profile_summary()` 显示账号等级 / 余额摘要，通过 `first_available_purchase()` 给局外升级按钮加可购买提示，并通过 `MetaProgressionPanel` 消费 `upgrade_summaries()` 显示完整升级列表。新开局时 `MetaProgressionSystem.current_modifiers()` 输出的永久升级 modifiers 会复用 `Player.apply_modifiers()` 与 `WeaponSystem.apply_modifiers()`。
- 伤害类型：从 `weapons.json` / `enemies.csv` 读取，交给 `Combat` 校验。
- UI / HUD / 升级文案：`ui_title_name`、`ui_title_subtitle`、`ui_start`、`ui_continue_run`、`ui_run_save_unavailable`、`ui_settings*`、`ui_pause_title`、`ui_save_and_quit`、`ui_quit`、`ui_hud_life`、`ui_hud_kills`、`ui_hud_time`、`ui_hud_level`、`ui_hud_xp`、`ui_level_up_title`、`ui_upgrade_applied`、`ui_game_over`、`ui_restart_hint`、`ui_restart`、`ui_quit_to_title`、`ui_run_summary`、`ui_meta_settlement`、`ui_meta_balance`、`ui_meta_account_level`、`ui_meta_account_level_up`、`ui_meta_title_summary`、`ui_meta_purchase_upgrade`、`ui_meta_purchase_unavailable`、`ui_meta_purchase_success`、`ui_meta_purchase_failed`、`ui_meta_progression`、`ui_meta_progression_available`、`ui_meta_progression_title`、`ui_meta_upgrade_level`、`ui_meta_upgrade_cost`、`ui_meta_upgrade_maxed`、`ui_meta_upgrade_locked`、`ui_meta_upgrade_insufficient`，升级候选使用 `growth_pools.json` 的 `name_key` / `desc_key`。常驻 UI 必须在 `Localization.locale_changed` 后刷新已有节点，不依赖重启或重新实例化。

## 依赖

- 上游依赖：`DataLoader`、`GameState`、`GameClock`、`RNG.spawn`、`RNG.ui_choice`、`PoolManager`、`UIManager`、`SaveManager`、`MetaProgressionSystem`、`Combat`、`Settings` 写入的 InputMap action、locale。
- 下游调用方：当前无；后续可拆分为正式 Player / WeaponSystem / Spawner / HUD 模块。
- 禁止依赖：不得复制历史 MVP 代码；不得绕过正式 `.tscn` 场景资源临时拼长期 UI / runtime 节点；不得绕过 `PoolManager` 创建高频实体；不得直接扣生命；不得绕过 InputMap 读物理输入；不得用裸随机或原始时间。

## 扩展点

- 加武器：优先改 `weapons.json`，运行时继续解释 `base_stats` 和 `projectile`。
- 加敌人：优先改 `enemies.csv`、`game_modes.json` 和 `spawn_waves.csv`，行为差异等后续可复用 AI strategy；不要在 F4 enemy 里按 id 分支。
- 加刷怪：改 `spawn_waves.csv`；多个波次可复用当前时间窗 / 预算解释。
- 加升级候选：优先改 `growth_pools.json`；新候选如果仍是 `stat_modifier` 不需要改逻辑，新增候选类型才需要扩展运行时解释和文档。
- 场景资源化：新增稳定 gameplay / UI 层级时优先新增 `.tscn`，脚本只做节点绑定、配置和 signal 编排；只有对象池工厂与数据驱动重复项可以在运行时创建节点，并要在模块文档说明原因。
- 扩展 run 快照：新增可恢复实体字段时先保证 JSON 友好，再更新本文档、SaveManager 文档、`runtime-smoke` 和 `save-smoke`；不要保存 `PoolManager` 内部队列或节点引用。
- 扩展死亡结算：新增奖励来源时先扩展 `MetaProgressionSystem.apply_run_settlement()` summary 与 `meta-smoke`，F4 只提供局内事实，不解释公式。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调玩家速度 / 生命 / 受伤无敌 / 中心排斥 | `player.json` / `characters.json` | `client/data/README.md` | `python tools/validate_data.py` |
| 调武器伤害 / 射速 / 弹速 | `weapons.json` | `client/data/README.md` | `validate_data` + headless |
| 调敌人血量 / 速度 / 接触伤害 / 中心间距 / 占位色 | `enemies.csv` | `client/data/README.md` | `validate_data` + 手动跑一局 |
| 调刷怪节奏 | `spawn_waves.csv` | `client/data/README.md` | `validate_data` + 手动 1 分钟 |
| 调升级阈值 / 候选 | `growth.csv` / `growth_pools.json` | `client/data/README.md` | `validate_data` + `runtime-smoke` |
| 改 HUD 文案 | `strings.csv` | `client/locale/README.md` | `validate_data` |
| 改 HUD / 升级面板布局 | `client/scenes/gameplay/gameplay_hud.tscn`、`client/scenes/ui/level_up_panel.tscn`、对应脚本 | 本文档 | `runtime-smoke` + 手动不同窗口尺寸检查 |
| 改暂停 / 保存续局 | `client/scripts/ui/pause_menu.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`formal_client_boot.gd` | 本文档、SaveManager / FormalClientBoot 文档 | `runtime-smoke` + `save-smoke` + L5 暂停 / 存档 checklist |
| 改设置入口 / 设置叠层 | `title_menu.gd`、`pause_menu.gd`、`settings_panel.gd`、`formal_client_boot.gd`、`gameplay_run_loop.gd` | 本文档、Settings / UIManager / FormalClientBoot 文档 | `settings-smoke` + `runtime-smoke` |
| 改死亡结算 / 局外升级应用 | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/ui/game_over_panel.gd`、`client/scripts/autoload/meta_progression_system.gd` | 本文档、MetaProgressionSystem / SaveManager 文档 | `runtime-smoke` + `meta-smoke` |
| 改标题局外升级入口 / 摘要 | `client/scenes/ui/title_menu.tscn`、`client/scenes/ui/meta_progression_panel.tscn`、对应脚本、`client/scripts/boot/formal_client_boot.gd`、`client/scripts/autoload/meta_progression_system.gd` | 本文档、FormalClientBoot / MetaProgressionSystem 文档 | `headless-boot` + `meta-smoke` + `runtime-smoke` + 手动标题菜单点开 |
| 改运行时行为 | `client/scripts/gameplay/*.gd` | 本文档、必要时 GDD / ADR | L0 + L2 + `runtime-smoke`，必要时补 L1 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动没有进入 F4 | `DataLoader.validate_project_data()` 是否通过；`FormalClientBoot` 日志 |
| 场景化后节点找不到 | `.tscn` 中稳定节点名是否与脚本 `get_node_or_null()` 路径一致；按钮是否保留 `PROCESS_MODE_ALWAYS`；scene ext_resource 是否能被 Godot 解析 |
| 无法移动 | InputMap action 是否存在；`GameplayRunLoop._ensure_input_actions()` 是否执行 |
| 改键后旧键仍生效 | `Settings` 是否替换了对应 action 的 `InputEventKey`；`GameplayRunLoop._ensure_input_actions()` 不应再追加键盘默认事件 |
| 手柄输入消失 | `Settings` 是否误删了 `InputEventJoypadButton` / `InputEventJoypadMotion`；runtime 手柄兜底是否执行 |
| 移动感知不明显 | `WorldBackground` 是否挂载；网格是否随玩家附近重绘 |
| 不开火 | `starting_loadout.weapon_id` 是否存在；`fire_rate` 是否大于 0；子弹池是否注册 |
| 不刷怪 | `spawn_waves.csv` 时间窗、预算、`max_alive` 是否允许；敌人池是否注册 |
| 第二敌人不出现 | `enemies.csv.pool_id` 是否为已注册池；`game_modes.json.resource_pools.enemies` 与 `spawn_waves.csv.enemy_id` 是否引用该敌人；`runtime-smoke` 是否通过第二敌人池断言 |
| 敌人中心完全重叠 | `enemies.csv.separation_radius` 是否为 0；`runtime-smoke` 是否通过中心分离断言 |
| 敌人中心贴到玩家中心 | `player.json.base_stats.player_separation_radius` 是否为 0；`Enemy` 是否仍调用玩家中心排斥；`runtime-smoke` 是否通过玩家-敌人分离断言 |
| 子弹打不到 | `hit_radius`、敌人位置、`bullet_range` / `lifetime` 是否合理 |
| 同一敌人贴住玩家不再造成后续伤害 | 玩家 `damage_invulnerability_duration` 是否过长；`Enemy` 不应保存单只敌人的接触伤害冷却 |
| 不掉经验 / 不升级 | `enemies.csv.exp_reward` 是否大于 0；`pickup_orb` 池是否注册；`growth.csv` 下一级阈值是否达到 |
| 升级面板不出现或无法选择 | `GameState` 是否进入 `LEVEL_UP`；`UIManager.top()` 是否为 `LevelUpPanel`；`growth_pools.json` 是否有满足 `min_level` 的候选 |
| 升级界面按暂停键无反应 | `LevelUpPanel.pause_requested` 是否连接到 `GameplayRunLoop._on_level_up_pause_requested()`；升级面板是否是 `UIManager.top()`；`pause` action 是否已注册 |
| 游戏结束后计时继续 | `GameClock` 是否把 `GAME_OVER` 视为冻结状态；`runtime-smoke` 是否通过冻结断言 |
| 死亡后没有局外奖励 | `MetaProgressionSystem.apply_run_settlement()` 是否被调用；`meta.save` 是否写入；`client/tools/runtime_smoke.gd` 是否通过死亡结算断言 |
| 死亡后没有账号等级提升提示 | 本局账号经验是否跨过 `meta_progression.json.account_level.thresholds`；`GameOverPanel` 是否收到 `previous_account_level`；`meta-smoke` 是否通过 GameOverPanel 账号进度断言 |
| 死亡后还能继续旧局 | `SaveManager.delete(slot_0, run)` 是否在结算后执行；标题继续按钮是否仍看见旧 `run` |
| 标题菜单看不到局外升级 | `TitleMenu` 是否有 `MetaProgressionButton`；locale 是否有 `ui_meta_progression`；`FormalClientBoot` 是否连接 `meta_progression_requested` |
| 标题菜单账号 / 余额摘要不刷新 | `TitleMenu.refresh_meta_summary()` 是否被调用；`FormalClientBoot._on_meta_progression_closed()` 是否在关闭面板后刷新标题菜单；`meta-smoke` 是否通过可购买提示断言 |
| 局外升级面板没有升级列表 | `MetaProgressionSystem.upgrade_summaries()` 是否返回轨道；`MetaProgressionPanel` 是否能找到 `MetaUpgradeList`；`meta-smoke` 是否通过面板列表断言 |
| 失败面板出现局外成长购买或跳转入口 | `GameOverPanel` 是否意外恢复 `PurchaseUpgradeButton` / `MetaProgressionButton`；`runtime-smoke` 是否通过失败页不显示局外成长入口断言 |
| 下一局永久升级无效 | `MetaProgressionSystem.current_modifiers()` 是否输出目标 stat；F4 开局是否在玩家 / 武器 configure 后应用 modifiers |
| 失败后无法重开 / 回标题 | 是否处于 `GameState.GAME_OVER`；`GameOverPanel` 是否挂到 `UIManager`；`restart_requested` / `quit_to_title_requested` 是否被 `FormalClientBoot` 连接 |
| 暂停菜单打不开或不冻结 | `pause` action 是否已注册；`PauseMenu.pauses_game` 是否为 true；`UIManager` 是否切到 `GameState.PAUSED` |
| 暂停菜单打开设置后关不掉 | `SettingsPanel` 是否是栈顶；`SettingsPanel.request_close()` 是否复用关闭按钮路径；`runtime-smoke` 是否通过暂停设置入口断言 |
| 手柄 / 键盘返回键不生效 | `Settings` 是否把 `input.ui_back` 写入 InputMap；栈顶 UI 是否实现 `request_close()`；不应依赖 `UIManager` 盲目出栈 |
| 新打开 UI 没有焦点 | UI 是否有可聚焦控件；复杂面板是否实现 `grab_default_focus()`；`runtime-smoke` 是否断言焦点在栈顶面板内部 |
| 保存后标题没有继续游戏 | `SaveManager.has_save(slot_0, run)` 是否为 true；旧存档是否因 hash mismatch 被隔离 |
| 继续坏档后没有提示 | `TitleMenu` 是否存在 `RunSaveNoticeLabel`；`ui_run_save_unavailable` 是否在 `strings.csv` 与 `.translation` 中；`runtime-smoke` 是否通过坏 run 存档点击继续断言 |
| 继续游戏后状态不对 | run payload 是否包含玩家 / 武器 / 敌人 / 子弹 / 经验球 / RNG / GameClock / `ui_restore`；恢复时是否通过 `PoolManager.acquire()` 重建实体；暂停和升级选择是否经由 `UIManager` 恢复 |

## 测试义务

- Gameplay runtime 代码改动必跑：`python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`。
- Gameplay runtime / UI 场景结构改动还必须跑 `python tools/godot_bridge.py --project client runtime-smoke`，涉及标题局外升级面板时追加 `meta-smoke`。
- 涉及启动、输入、WeaponSystem、子弹、敌人、Spawner、经验球、升级选择、Combat 或失败状态时追加 `python tools/godot_bridge.py --project client runtime-smoke`。
- 涉及暂停、保存退出、标题继续、坏档提示、RNG / GameClock 快照或 run payload 时必须追加 `python tools/godot_bridge.py --project client runtime-smoke` 与 `python tools/godot_bridge.py --project client save-smoke`，并做至少一次手动保存续局检查。
- 涉及标题 / 暂停设置入口、设置面板关闭、`ui_back` 返回或运行时语言刷新时，追加 `python tools/godot_bridge.py --project client settings-smoke` 与 `python tools/godot_bridge.py --project client runtime-smoke`。
- 涉及死亡结算、局外成长、`meta` 存档或永久升级应用时追加 `python tools/godot_bridge.py --project client meta-smoke`；如果改了 F4 死亡接入或失败面板，同时跑 `runtime-smoke`。
- 数据 / locale 变化还要跑 `python tools/validate_data.py`、`python tools/lint_project_rules.py`。
- 当前没有 GUT runner，F4 首切片用 L0 + L2 + `runtime-smoke` + 手动 1 分钟跑通作为阶段门槛；后续接入 Godot 测试时补 Player / Combat / Pool / Spawner 的 L1。

## 迁移 / 兼容

F5 已开始写 `SaveManager` 的 `run` kind，F6 首切片已开始写 `meta` kind。当前 gameplay runtime 自身 payload schema version 仍为 1；`SaveManager` 的 `run` envelope version 已提升到 2，并提供 v1 -> v2 迁移来补齐早期 payload 可能缺失的结构字段。`ui_restore` 是 run payload 的可选恢复提示，缺失时按 `playing` 兼容旧 run 存档。死亡结算不写入 `run` payload，而是通过 `MetaProgressionSystem` 更新 `meta` profile；后续新增遗物、主动道具或局外奖励时，需要决定是否提升 runtime payload schema、`meta` payload schema 或 SaveManager kind version，并补迁移 / roundtrip 测试；不得保存对象池内部状态或节点引用。

## 相关文档

- `docs/AI协作/工作包/F4-MinPlayableLoop.md`
- `docs/正式项目工作规划.md` F4
- `docs/游戏设计文档.md` §3 / §4 / §5.3 / §9.13 / §9.15.1
- `docs/代码/combat.md`
- `docs/代码/meta_progression_system.md`
