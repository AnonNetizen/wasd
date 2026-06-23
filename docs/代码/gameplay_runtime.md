# Gameplay Runtime 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式客户端 gameplay runtime 的聚合模块契约；拆分 Player、WeaponSystem、Enemy、Spawner、HUD 等长期模块或改变公共行为时必须同步本文档、AI 导航、代码索引和相关阶段工作包。

## 职责

- 在正式 `client/` 内提供一局最小战斗：最小标题入口、标题设置入口、标题局外成长摘要与升级入口、有限地图、玩家移动、相机居中、基础背景参照、起始武器、起始主动技能、池化子弹、池化敌人、池化机关、波次刷怪、经验掉落、升级三选一、HUD、主动暂停、暂停设置入口、暂停保存退出、标题继续游戏、暂停 / 升级 UI 恢复点、失败后结算、重开 / 回标题。
- 复用 F3/F9 已建立的数据边界：`player.json`、`characters.json`、`weapons.json`、`skills.json`、`enemies.csv`、`enemy_ai_profiles.json`、`hazards.csv`、`map_layouts.json`、`spawn_waves.csv`、`growth.csv`、`growth_pools.json` 和 `game_modes.json`。
- 第一版只做标准生存模式、默认角色、默认起始武器、一个起始技能和通用范围机关的竖切；F5 首片已接入 gameplay runtime 的 `run` 续局快照，F6 首片已接入死亡结算、`meta` 存档、标题局外升级面板和下一局永久 modifiers；游戏结束页只展示结算收益、账号等级 / 余额、重开和回标题，不提供局外成长购买入口；角色选择、完整商店 / 局外包装、技能 UI、音频、美术资产或平衡 sim 仍未实现。升级内容只落地 `stat_modifier` 最小切片，后续遗物 / 主动强化 / 刷新等仍按数据与设计扩展。

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
| 改主动技能释放 / 资源消耗 | `docs/代码/skill_system.md`、`client/scripts/gameplay/skill_system.gd`、`client/data/skills.json` |
| 改敌人生态 AI / 接触伤害 | `docs/代码/enemy_ai.md`、`client/scripts/gameplay/enemy.gd`、`enemy_ai_profiles.json` |
| 改有限地图 / PCG / 人工摆点 | `docs/代码/map_manager.md`、`client/scripts/gameplay/map_manager.gd`、`client/data/map_layouts.json` |
| 改机关运行时 / FEA-12 | `docs/代码/hazard_system.md`、`client/scripts/gameplay/hazard.gd`、`client/data/hazards.csv` |
| 改经验球 / 拾取 | `client/scripts/gameplay/pickup_orb.gd`、`player.json` |
| 改升级候选 / 奖励 | `growth.csv`、`growth_pools.json`、`client/scripts/gameplay/gameplay_run_loop.gd` |
| 改 HUD 文案 / 详细数值面板 | `client/scripts/gameplay/gameplay_hud.gd`、`client/scenes/gameplay/gameplay_hud.tscn`、`client/locale/strings.csv` |
| 改稳定节点结构 / UI 层级 | `client/scenes/gameplay/*.tscn`、`client/scenes/ui/*.tscn` |
| 改 GM 指令影响局内状态 | `docs/代码/debug_tools.md`、`client/scripts/debug/gm_command_registry.gd`、`client/scripts/gameplay/gameplay_run_loop.gd` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/boot/formal_client_boot.gd` | 数据校验通过后挂载 gameplay runtime |
| `client/scenes/gameplay/gameplay_run_loop.tscn` | 正式 gameplay runtime 场景；包含 `ActiveWorld`、`WorldBackground`、`Player` 和 `GameplayHud` |
| `client/scenes/gameplay/player.tscn` | 正式玩家场景；包含 `CenteredCamera` 与 `WeaponSystem` |
| `client/scenes/gameplay/bullet.tscn` / `enemy.tscn` / `pickup_orb.tscn` / `hit_spark.tscn` / `damage_number.tscn` / `hazard.tscn` | 对象池实体场景；由 `PoolManager` 工厂实例化并复用 |
| `client/scenes/ui/title_menu.tscn` / `pause_menu.tscn` / `settings_panel.tscn` / `game_over_panel.tscn` / `level_up_panel.tscn` / `meta_progression_panel.tscn` | 正式 UI 场景；脚本只绑定稳定节点、连接 signal 和刷新数据 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 正式运行时编排、输入 action 手柄兜底注册、对象池注册、刷怪和重开 |
| `client/scripts/gameplay/world_background.gd` | 世界网格背景，让玩家移动具备空间参照 |
| `client/scripts/gameplay/map_manager.gd` | 有限地图边界、PCG 机关摆放、人工摆点、刷怪位置 clamp 和地图快照 |
| `client/scripts/gameplay/player.gd` | 玩家移动、鼠标相对玩家 / 视口中心方向瞄准、方向键 / 手柄兜底瞄准、左右朝向表现、相机居中、受伤 / 死亡；提供少量受控 debug 生命 API 给 GM 命令调用 |
| `client/scripts/gameplay/weapon_system.gd` | 起始武器自动开火和子弹池获取 |
| `client/scripts/gameplay/skill_system.gd` | 起始主动技能释放、技能资源、冷却、目标筛选、效果解释和 run 快照 |
| `client/scripts/gameplay/bullet.gd` | 子弹飞行、射程 / 生命周期裁剪、敌人命中 |
| `client/scripts/gameplay/enemy.gd` | 数据驱动敌人生态 AI、接触伤害、受伤 / 死亡和 AI 快照 |
| `client/scripts/gameplay/hazard.gd` | 通用机关节点：半径触发、冷却、占位表现、`Combat` 伤害和快照 |
| `client/scripts/gameplay/pickup_orb.gd` | 池化经验球：进入玩家拾取范围后吸附并发放经验 |
| `client/scripts/gameplay/hit_spark.gd` / `damage_number.gd` | 池化命中反馈：Combat 成功造成伤害时生成短命火花和飘字；不进入 run 快照 |
| `client/scripts/gameplay/level_up_panel.gd` | 响应式升级三选一面板；通过 `UIManager.push()` 挂载；语言切换时用缓存候选重建按钮 |
| `client/scripts/gameplay/gameplay_hud.gd` | 响应式最小 HUD：生命、击杀、时间、等级、经验、升级获得反馈；语言切换时用当前 HUD 状态重画 |
| `client/scripts/ui/title_menu.gd` | 最小标题界面：账号等级 / 余额摘要、开始 / 继续 / 局外升级 / 设置 / 退出 |
| `client/scripts/ui/settings_panel.gd` | F7 设置面板：从标题或暂停菜单打开，读写 `Settings` 并响应语言切换 |
| `client/scripts/ui/meta_progression_panel.gd` | F6 阶段局外升级面板：从标题菜单打开，显示余额、账号等级、所有升级轨道、购买状态和购买反馈；语言切换时刷新标题、余额、升级列表和可见反馈 |
| `client/scripts/ui/pause_menu.gd` | F5 / F7 暂停菜单：继续、设置、保存并退出、重新开始、回标题；语言切换时刷新按钮 |
| `client/scripts/ui/game_over_panel.gd` | 失败面板：结算摘要、账号等级 / 余额、重开 / 回标题；语言切换时用缓存结算重画 |
| `client/tools/runtime_smoke.gd` | gameplay runtime headless smoke，覆盖启动、输入、池化、伤害、失败状态和真实死亡结算 |
| `client/tools/debug_tools_smoke.gd` | DebugTools headless smoke，覆盖 GM 命令调用 runtime debug API 和 release guard |
| `client/tools/meta_progression_smoke.gd` | F6 MetaProgression smoke，覆盖 meta roundtrip、结算、购买和永久 modifier |
| `client/tools/save_manager_smoke.gd` | F5 SaveManager run 存档可靠性 smoke，覆盖 roundtrip、备份回退、坏档隔离和迁移 |
| `client/tools/perf_probe.gd` | F8 轻量 perf / 平衡采样入口，输出 schema v2 可比较 JSON：warmup 后帧时间分布、实体峰值、池峰值、等级、击杀和预算状态 |
| `client/tools/golden_replay_capture.gd` | F8 golden replay capture 工具，固定 seed 启动真实 `GameplayRunLoop` 并采样运行时摘要；支持 basic、pause/resume、full-death 和 level-up choice 场景 |
| `client/tools/replay_input_smoke.gd` | F8 gameplay 输入录制 smoke，确认移动 / 瞄准 / pause / ui_back 写入 Replay 输入事件 |
| `tools/godot_bridge.py` | `runtime-smoke` / `save-smoke` / `meta-smoke` / `settings-smoke` / `debug-tools-smoke` / `debug-tools-release-smoke` / F8 `l1-smoke`、`replay-smoke`、`replay-runner`、`replay-input-smoke`、`capture-golden-replay`、`capture-golden-replay --golden-scenario golden_full_death`、`perf-probe` 命令入口 |
| `docs/代码/combat.md` | 伤害统一入口文档 |
| `docs/代码/map_manager.md` | 有限地图 / PCG / 人工摆点文档 |
| `docs/代码/hazard_system.md` | 机关运行时文档 |
| `docs/代码/debug_tools.md` | GM 控制台、命令和 release guard 文档 |

## 场景 / 节点结构

Gameplay runtime 的稳定节点结构已迁入正式 `.tscn` 场景资源。脚本职责是读取数据、绑定场景节点、连接 signal 和刷新运行时状态；不再在业务脚本中临时拼出长期 UI / runtime 层级。允许动态生成的范围限于对象池工厂实例化场景、升级候选按钮、局外升级列表这类数据驱动重复项。

```text
FormalClientBoot
└── GameplayRunLoop (Node2D)
    ├── ActiveWorld (Node2D)
    │   ├── WorldBackground (Node2D)
    │   ├── MapManager (Node2D)
    │   ├── Player (CharacterBody2D)
    │   │   ├── CenteredCamera (Camera2D)
    │   │   └── WeaponSystem (Node)
    │   ├── hazard_spike_* (pooled Hazard scene, active only)
    │   ├── bullet_basic_* (pooled Bullet scene, active only)
    │   └── enemy_* (pooled Enemy scenes, active only)
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

闲置子弹、敌人、机关和经验球节点归 `PoolManager` autoload 管理。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `FormalClientBoot` 跑数据 schema smoke，正常启动显示 `TitleMenu`；标题菜单显示账号等级 / 局外货币摘要，有可购买升级时局外升级按钮显示可购买提示；标题菜单可打开 `MetaProgressionPanel` 查看 / 购买局外升级，也可打开 `SettingsPanel` 修改设置；`--runtime-smoke` 模式跳过标题并直接创建 `GameplayRunLoop` | `DataLoader.validate_project_data()`、`UIManager.push()` |
| 开局 | `FormalClientBoot` 实例化 `gameplay_run_loop.tscn`；运行时重置 `GameClock`，注册 / 预热子弹、经验球、机关、命中反馈和当前 F4 敌人对象池，读取默认模式 / 角色 / 起始武器，并在玩家 / 武器配置后应用 `MetaProgressionSystem.current_modifiers()` | `PackedScene.instantiate()`、`PoolManager.register_pool()`、`DataLoader.load_json()`、`MetaProgressionSystem.current_modifiers()` |
| 地图 / 机关 | `MapManager` 按 `map_layouts.json` 配置有限边界、出生点、安全半径、刷怪边距、手工机关摆点和 PCG 机关；玩家移动会被 bounds clamp，机关通过对象池生成，触发伤害走 `Combat` | `MapManager.configure()`、`generate_hazard_placements()`、`Player.set_movement_bounds()`、`PoolManager.acquire()`、`Combat.apply_damage()` |
| 背景 | 在玩家附近绘制世界空间网格和原点十字，让相机移动有参照 | `WorldBackground.configure()` |
| 输入 | `Settings` 在启动 / 加载 / 修改时把键盘主绑定写入 InputMap；运行时只确保同一 action 有手柄轴 / 按钮兜底事件。键鼠默认按鼠标相对视口中心的偏移瞄准（玩家恒居中时等价于玩家到鼠标的世界方向），方向键 / 手柄右摇杆 / D-pad 在没有鼠标动作时作为兜底。按住 `show_stats_panel` action（默认 Tab）只显示 HUD 详细数值面板，不进入暂停态。F8 输入录制首片会把移动 / 兜底瞄准 action 状态变化以及 `pause` / `ui_back` 离散事件写入 `Replay`，但鼠标向量录制仍待后续输入回放扩展 | `Settings`、`InputMap`、`Input.get_vector()`、`InputEventMouseMotion.position`、`Replay.record_input_action()`、`Replay.record_input_event()` |
| 移动 / 瞄准 | 玩家按数据移速移动，鼠标激活后按鼠标相对视口中心的方向瞄准；无鼠标动作时用方向键 / 手柄右摇杆 / D-pad 兜底，松开保持上一方向；玩家和敌人的占位表现只区分向左 / 向右，不做向上 / 向下朝向 | `Player.aim_direction` |
| 自动开火 | WeaponSystem 按 `fire_rate` 从子弹池取节点并配置 | `PoolManager.acquire()` |
| 子弹命中 | 子弹用距离检测命中 `active_enemies` 组，伤害走 `Combat.apply_damage()` | `DamageInfo` |
| 主动技能 | SkillSystem 从 `skills.json` 读取起始技能；默认 `use_active_item` action 释放 `skill_whirlwind_slash`，消耗角色声明的 `mana`，对施法者半径内敌人造成 `Combat` AOE 伤害；技能激活使用项目版轻量 GAS 的 ability tag gating，技能冷却与资源回复走 `GameClock` | `SkillSystem.cast_primary_skill()`、`Combat.apply_damage()` |
| 刷怪 | Spawner 读取 `spawn_waves.csv` 的时间窗、间隔、上限和预算，在视野外围刷敌人；当前有追猎者、疾行者、潜猎者和壁垒四种数据化敌人 | `GameClock.now()`、`RNG.spawn` |
| 机关触发 | `Hazard` 在 `PLAYING` 下按 `GameClock.delta_scaled()` 消耗冷却；玩家进入半径后构造 `DamageInfo` 并交给 `Combat`，当前 FEA-12 用于验证 PCG / 手工摆点和伤害链路 | `Hazard.configure()`、`Combat.apply_damage()` |
| 受击 / 击杀反馈 | `Combat.damage_applied` 成功应用伤害后生成池化 `hit_spark` 与 `damage_number`；玩家受伤时短暂红闪，敌人命中时短暂暖白闪，敌人死亡后立即离开活敌组并橙色放大淡出后归池；玩家进入数据化受伤无敌窗口 | `_draw()` / `queue_redraw()` / `PoolManager.acquire()` |
| 敌人行为 | 敌人从 `enemy_ai_profiles.json` 读取感知、目标权重和动作列表；运行时可接近玩家、逃离威胁、狩猎其他敌人、守出生点或冲锋。敌人与玩家 / 敌人接触伤害都走 `Combat`；怪物互杀不会计入玩家击杀或经验掉落 | `Enemy.defeated`、`docs/代码/enemy_ai.md` |
| 经验掉落 | 敌人死亡时按 `exp_reward` 生成池化经验球；经验球进入玩家 `pickup_range` 后显示吸附反馈，贴近玩家时立即发放经验并短暂弹出淡出后归池 | `PoolManager.acquire(PICKUP_ORB)` |
| 升级选择 | 累计经验达到 `growth.csv` 阈值后进入 `GameState.LEVEL_UP`，玩法时间冻结；HUD 显示本级经验进度（升级后从 0 重新计入下一等级段）；候选从模式声明的 `growth_pools` 中按权重和 `RNG.ui_choice` 抽取，入选后按 id 稳定排序以保证选择索引可回放；升级面板可在暂停态响应鼠标选择，也可按 `pause` action 把暂停菜单叠到升级面板上；选择后通过 `Replay.record_decision(level_up, ...)` 记录等级、候选数量、候选 id、选择 id 和 luck 快照，再应用 `stat_modifier`、显示获得反馈并回到 `PLAYING` | `LevelUpPanel.choice_selected`、`LevelUpPanel.pause_requested` |
| 主动暂停 | `pause` action 在 `PLAYING` 中打开 `PauseMenu`，在 `LEVEL_UP` 中由升级面板请求把 `PauseMenu` 叠在升级面板上；菜单通过 `UIManager` 请求 `GameState.PAUSED`，玩法时间、敌人、子弹和刷怪冻结，菜单仍响应鼠标、`ui_back` 和再次 `pause` action；暂停菜单可打开 `SettingsPanel`，关闭后仍回到同一个暂停菜单；关闭升级态上方的暂停菜单后必须回到 `LEVEL_UP` | `UIManager.push()`、`GameState.PAUSED` |
| 保存退出 / 继续 | 暂停菜单“保存并退出”生成 `run` payload 并写入 `SaveManager`；标题菜单检测到 `run.save` 后显示“继续游戏”，加载 payload 后由 gameplay runtime 通过对象池重建活跃敌人、子弹和经验球，并按 `ui_restore` 回到普通游玩、暂停菜单或升级选择面板；若续局读取失败，坏档由 `SaveManager` 隔离，标题菜单显示重置提示并隐藏继续按钮 | `SaveManager.save()`、`SaveManager.load_envelope()`、`configure_restore_snapshot()` |
| UI 布局 | HUD 使用全屏锚点下的 `MarginContainer + VBoxContainer`；升级面板使用全屏遮罩、居中容器和按视口宽度夹取的面板宽度，随窗口尺寸调整 | `Control.set_anchors_preset()` |
| 运行时语言刷新 | `Localization.locale_changed` 发出后，标题、暂停、设置、HUD、升级、结算和局外成长面板用自身缓存的状态或配置数据刷新文本；订阅的 UI 在 `_exit_tree()` 断开 signal，避免离树节点收到后续语言切换 | `Localization.locale_changed`、`refresh_texts()` |
| 失败 / 结算 / 重开 | 玩家生命归零后先向 `MetaProgressionSystem` 提交本局摘要并写入 `meta`，再删除 `run` 存档、进入 `GameState.GAME_OVER`、冻结 `GameClock` 并显示唯一失败面板；失败面板只展示本局结算摘要、账号经验、当前账号等级、账号等级提升提示、余额、重开和回标题，不提供局外成长购买或跳转入口。玩家可重开或回标题，按 `pause` 仍可快捷重开 | `MetaProgressionSystem.apply_run_settlement()`、`SaveManager.delete(run)`、`UIManager.push()`、`GameState.change_state()`、`GameplayRunLoop.restart_requested` |
| DebugTools smoke | `debug-tools-smoke` 启动一局并通过 `DebugConsole` 调用 `GMCommandRegistry`，验证 help/stats/spawn/xp/hp/damage/heal/meta/kill/clear；`debug-tools-release-smoke` 模拟 release guard，确认没有 `DebugConsole` / `GMCommandRegistry` 或 debug action | `client/tools/debug_tools_smoke.gd` / `docs/代码/debug_tools.md` |
| 自动 smoke / probe | `godot_bridge.py runtime-smoke` 以 `--runtime-smoke` 用户参数启动正式主场景，并挂载 runtime smoke；`save-smoke` / `meta-smoke` / `settings-smoke` 分别挂载对应 smoke；F8 `replay-runner` 对照 `.replay` 摘要并在 `--rerun-runtime-summary` 下播放录制输入和工具层 runtime event，`replay-input-smoke` 验证 gameplay 输入录制，`capture-golden-replay` 生成 basic / pause-resume / full-death golden，`perf-probe` 会启动一局并输出 schema v2 可比较性能 / 平衡基线 | `client/tools/runtime_smoke.gd` / `client/tools/save_manager_smoke.gd` / `client/tools/meta_progression_smoke.gd` / `client/tools/settings_smoke.gd` / `client/tools/replay_runner.gd` / `client/tools/replay_input_smoke.gd` / `client/tools/golden_replay_capture.gd` / `client/tools/perf_probe.gd` |

## 公共 API

F4 脚本当前是阶段性内部模块，主要公共面向为 signal 和实体生命周期：

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `Player.configure(base_stats)` | 合并后的玩家属性 | `void` | `move_speed` / `max_hp` / `damage_invulnerability_duration` / `player_separation_radius` 来自数据 |
| `Player.invulnerability_remaining()` | 无 | `float` | 只读诊断值；用于 smoke / 调试确认玩家侧无敌窗口是否归零 |
| `Player.pickup_range()` / `pickup_orb_speed()` / `luck()` / `separation_radius()` / `stat_value(stat)` | 无 / stat id | `float` | 只读运行时属性；经验球、升级候选数量判定、玩家中心排斥和 HUD 详细数值面板使用 |
| `Player.aim_at_world_position(world_position)` | 世界坐标 | `void` | 按玩家到目标世界坐标的方向更新 `aim_direction`；headless smoke 和未来脚本化瞄准可复用，真实鼠标输入使用视口中心偏移路径 |
| `Player.apply_modifiers(modifiers)` | `growth_pools.json` 的 modifiers | `void` | 按 `(基础 + 加法) * 乘法` 更新玩家运行时属性 |
| `Player.receive_damage(info)` | `DamageInfo` | result dictionary | 只能由 `Combat.apply_damage()` 间接调用；无敌期返回 `reason=invulnerable` 且不扣生命 |
| `Player.debug_heal()` / `debug_set_life()` / `debug_clear_invulnerability()` | 调试数值 | Dictionary / `void` | 仅供 debug/dev_tools GM 指令调用；正式 gameplay 不应依赖 |
| `WeaponSystem.configure(player, active_parent, weapon_data)` | 玩家、活跃父节点、武器数据 | `void` | 武器数据来自 `weapons.json` |
| `WeaponSystem.apply_modifiers(modifiers)` | `growth_pools.json` 的 modifiers | `void` | 按 `(基础 + 加法) * 乘法` 更新武器运行时属性 |
| `WeaponSystem.stat_value(stat)` | stat id | `float` | smoke / 调试读取当前武器数值 |
| `SkillSystem.configure(caster, active_parent, skills, resources)` | 施法者、活跃父节点、技能定义、资源定义 | `void` | 技能数据来自 `skills.json`，资源来自角色 `skill_resources`；详见 `docs/代码/skill_system.md` |
| `SkillSystem.cast_primary_skill()` / `cast_skill(skill_id)` | 无 / 技能 id | Dictionary | 失败不消耗资源；伤害效果必须走 `Combat.apply_damage()` |
| `SkillSystem.snapshot()` / `restore_snapshot(snapshot_data)` | run 快照 | Dictionary / `void` | 只保存冷却与资源当前值，不保存节点引用 |
| `Bullet.configure(stats, projectile, direction, source)` | 武器属性、弹体数据、方向、来源 | `void` | 节点必须来自 `PoolManager` |
| `Enemy.configure(enemy_data, target)` | 敌人 CSV 行 + AI profile、目标玩家 | `void` | 节点必须来自 `PoolManager` |
| `Enemy.content_tags()` / `ai_debug_summary()` / `was_defeated_by_player()` | 无 | `Array[String]` / `Dictionary` / `bool` | 供敌人生态感知、smoke / 调试和玩家击杀归因使用 |
| `Enemy.separation_radius()` / `visual_color()` / `is_defeat_feedback_active()` | 无 | `float` / `Color` / `bool` | 只读诊断值；用于中心排斥、占位色、死亡反馈和 smoke 确认 |
| `PickupOrb.configure(amount, target, pickup_speed)` | 经验值、目标玩家、吸附速度 | `void` | 节点必须来自 `PoolManager` |
| `PickupOrb.is_attracting()` / `is_collect_feedback_active()` | 无 | `bool` | 只读诊断值；用于 smoke 确认吸附 / 拾取反馈生命周期 |
| `HitSpark.configure(spawn_position)` / `DamageNumber.configure(spawn_position, amount, defeated, player_damage)` | 反馈位置与伤害摘要 | `void` | 节点必须来自 `PoolManager`；只做短命视觉反馈，不写入 run 快照 |
| `GameplayRunLoop.current_xp()` / `current_level_xp()` / `current_level_xp_required()` | 无 | `int` | `current_xp()` 是累计总经验；HUD 使用本级经验和本级需求显示升级进度 |
| `GameplayRunLoop.create_run_snapshot()` | 无 | `Dictionary` | 生成 `SaveManager` 的 `run` payload；只保存 JSON 友好的状态，不保存节点或对象池内部队列；`ui_restore` 记录普通游玩、暂停菜单或升级选择面板恢复点 |
| `GameplayRunLoop.configure_restore_snapshot(snapshot)` | `Dictionary` | `void` | 在节点入树前由 `FormalClientBoot` 调用；`_ready()` 后重建玩家、武器、敌人、子弹、经验球、RNG、GameClock 和 `ui_restore` 状态 |
| `GameplayRunLoop.debug_summary()` / `debug_spawn_enemy()` / `debug_give_xp()` / `debug_heal_player()` / `debug_set_player_hp()` / `debug_damage_player()` / `debug_kill_player()` / `debug_kill_enemies()` / `debug_clear_enemies()` | GM 指令参数 | `Dictionary` | 只作为 DebugTools 的受控 runtime API；刷怪走对象池，伤害 / 击杀走 `Combat`，经验走原有升级流程 |
| `LevelUpPanel.configure(choices)` / `choose_index(index)` | 升级候选 | `void` | 面板节点通过 `UIManager` 挂载；玩家可见文案来自 locale；面板宽度随视口宽度在最小 / 最大值之间自适应；按 `pause` action 时发出 `pause_requested`；语言切换时重用 `_choices` 重建按钮 |
| `GameplayHud.set_life()` / `set_kills()` / `set_level()` / `set_xp()` / `show_upgrade_feedback()` / `set_stats_panel_visible()` / `set_detailed_stats()` | HUD 状态 | `void` | 文案使用 `tr()`；布局使用容器和锚点而非固定屏幕坐标；详细数值面板是非模态 HUD 叠层，按住 action 显示、松开隐藏，不暂停；失败 UI 由 `GameOverPanel` 独占显示；语言切换时重用缓存生命、击杀、等级、经验、详细数值和最近升级反馈 key 刷新 |
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

- 角色：默认读取 `character_default`，其 id 来自生成常量 `CharacterIds`；默认角色使用鼠标瞄准、左右朝向和自动开火。
- 模式：默认读取 `mode_standard_survival`，其 id 来自生成常量 `GameModes`。
- 武器：从 `characters[].starting_loadout.weapon_id` 读取，不在代码写武器 id 分支。
- 技能：从 `characters[].starting_loadout.skill_ids` 读取，不绑定英雄 id；默认技能为 `skill_whirlwind_slash`，技能定义在 `skills.json`，模式可用池在 `game_modes.resource_pools.skills`；ability tag / activation 条件来自词表 §12-G。
- 技能资源：从 `characters[].skill_resources` 读取，当前默认资源为 `mana`；后续怒气、能量等资源应新增资源 id 和角色资源池，不在 SkillSystem 写死。
- 子弹池：从 `weapons[].projectile.pool_id` 读取；当前样例为已登记 `bullet_basic`。子弹占位绘制为黄色圆点加暗色轮廓，不承载行为差异。
- 敌人池：从 `enemies.csv.pool_id` 读取；当前注册已登记 `enemy_chaser` 与 `enemy_swarm`，不同敌人可复用同一 `Enemy` 场景和对象池。
- 敌人 AI profile：从 `enemies.csv.ai_profile_id` 引用 `enemy_ai_profiles.json`；profile 负责感知半径、动作评分、怪物互相狩猎 / 逃跑、领地和冲锋参数。详细规则见 `docs/代码/enemy_ai.md`。
- 敌人中心间距：从 `enemies.csv.separation_radius` 读取；当前默认 9px，低于 `hit_radius` 以允许视觉重叠。
- 玩家中心排斥：从合并后的玩家 `base_stats.player_separation_radius` 读取；当前默认 10px。敌人与玩家的最小中心距离为两者分离半径之和，碰到时只推开敌人，不改变玩家移动手感；接触伤害距离会取敌人 `hit_radius` 与双方分离半径之和的较大值，避免推开后反而打不到玩家。
- 玩家占位表现：运行时绘制蓝色圆点、暗色轮廓和朝向标记；受伤反馈为 0.16 秒红闪，不承载行为差异。
- 敌人占位表现：从 `enemies.csv.visual_color` 读取 HTML 色值作为填充色，运行时统一绘制几何三角、暗色轮廓和眼睛描边；命中反馈为 0.16 秒暖白闪，死亡反馈为 0.18 秒橙色放大淡出，只用于开发期占位可读性，不承载行为分支。
- 受伤无敌：从合并后的玩家 `base_stats.damage_invulnerability_duration` 读取；当前默认 `player.json` 为 0.7 秒，和受伤红闪时长分离。
- 经验球：使用词表 §8 `pickup_orb` 对象池；`player.json.base_stats.pickup_range` 控制吸附范围，`pickup_orb_speed` 控制吸附速度。经验球占位绘制为绿色圆点加暗色轮廓，吸附时显示短弧线，收集时放大淡出。
- 等级阈值：从 `growth.csv.total_xp_required` 读取累计总经验阈值；运行时内部保留累计经验判定升级，HUD 显示 `当前累计经验 - 当前等级累计阈值` / `下一级累计阈值 - 当前等级累计阈值`。
- 升级候选：从当前模式 `resource_pools.growth_pools` 引用的 `growth_pools.json` 池读取；当前 F4 只解释 `kind=stat_modifier` 且应用其 `modifiers`。候选入选使用 `RNG.ui_choice`，显示 / 选择顺序按候选 `id` 稳定排序，避免同一候选集合在不同进程中只因抽取顺序影响 replay 选择索引。选择后 HUD 使用金色文字、暗色阴影和 1.35 秒淡出显示获得反馈。
- 分辨率与 UI：默认 viewport 由 `client/project.godot` 设为 1920×1080；窗口禁止任意拖拽缩放，屏幕比例不匹配时通过 `canvas_items + keep` 保比例加黑边；F4 HUD 和升级面板应使用 `Control` 锚点 / 容器布局适配预设分辨率。
- run 续局快照：F5 首片使用 `SaveManager` 的 `run` kind，payload schema version 当前为 2，字段包括模式 / 角色 id、等级、累计经验、击杀、`GameClock.snapshot()`、`RNG.snapshot()`、有限地图状态、刷怪状态、玩家状态、武器状态、技能状态、活跃敌人、活跃子弹、活跃机关、活跃经验球和 `ui_restore`。`map` 保存 layout id、bounds、玩家出生点、安全半径、刷怪边距和机关 placement；`hazards` 保存活动机关 id、位置、冷却和激活表现状态。技能快照保存冷却、资源当前值与 owned ability tag 计数，不保存目标节点引用。敌人快照现在额外保存出生点、当前 AI action、冲锋 FSM、冲锋 cooldown 和最后伤害来源队伍，以保证生态 AI 续局后可恢复；不保存感知到的节点引用。`ui_restore.state` 当前支持 `playing`、`paused`、`level_up`：暂停保存后续局会先回到暂停菜单；升级选择面板打开时保存会保留已经掷出的候选列表并续回同一组选择，不重新消耗 `RNG.ui_choice`；暂停菜单叠在升级面板上时保存为 `state=paused` 且 `underlying_state=level_up`，恢复时先重建升级面板再叠回暂停菜单。旧 payload 没有 `ui_restore` 时按 `playing` 处理，旧 payload 没有 `skills` 时按空技能快照处理；旧 payload 没有 `map` / `hazards` 时由 `SaveManager` 迁移补空结构，运行时可按当前 layout 重新生成初始机关。`SaveManager` 的 `run` kind envelope 当前为 version 2，v1 -> v2 迁移只补齐缺失结构字段。RNG 大整数 state 以字符串保存，SaveManager 会在写入前做 JSON 归一化再计算 `data_hash`，避免高精度浮点 / JSON 读回类型差异导致 hash mismatch。
- 局外成长接入：F6 首片使用 `SaveManager` 的 `meta` kind；F4 只向 `MetaProgressionSystem.apply_run_settlement()` 提交 `kills`、`run_time`、`first_boss_defeated`，不在 F4 复制奖励公式。结算后必须删除 `run` 存档，避免死亡结算后的旧局重复领取奖励。标题菜单通过 `MetaProgressionSystem.profile_summary()` 显示账号等级 / 余额摘要，通过 `first_available_purchase()` 给局外升级按钮加可购买提示，并通过 `MetaProgressionPanel` 消费 `upgrade_summaries()` 显示完整升级列表。新开局时 `MetaProgressionSystem.current_modifiers()` 输出的永久升级 modifiers 会复用 `Player.apply_modifiers()` 与 `WeaponSystem.apply_modifiers()`。
- 伤害类型：从 `weapons.json` / `enemies.csv` / `hazards.csv` 读取，交给 `Combat` 校验。
- UI / HUD / 升级文案：`ui_title_name`、`ui_title_subtitle`、`ui_start`、`ui_continue_run`、`ui_run_save_unavailable`、`ui_settings*`、`ui_pause_title`、`ui_save_and_quit`、`ui_quit`、`ui_hud_life`、`ui_hud_kills`、`ui_hud_time`、`ui_hud_level`、`ui_hud_xp`、`ui_stats_*`、`ui_level_up_title`、`ui_upgrade_applied`、`ui_game_over`、`ui_restart_hint`、`ui_restart`、`ui_quit_to_title`、`ui_run_summary`、`ui_meta_settlement`、`ui_meta_balance`、`ui_meta_account_level`、`ui_meta_account_level_up`、`ui_meta_title_summary`、`ui_meta_purchase_upgrade`、`ui_meta_purchase_unavailable`、`ui_meta_purchase_success`、`ui_meta_purchase_failed`、`ui_meta_progression`、`ui_meta_progression_available`、`ui_meta_progression_title`、`ui_meta_upgrade_level`、`ui_meta_upgrade_cost`、`ui_meta_upgrade_maxed`、`ui_meta_upgrade_locked`、`ui_meta_upgrade_insufficient`，升级候选使用 `growth_pools.json` 的 `name_key` / `desc_key`。常驻 UI 必须在 `Localization.locale_changed` 后刷新已有节点，不依赖重启或重新实例化。
- GM / DebugTools：`debug_*` action 只由 `DebugConsole` 在 debug/dev_tools guard 通过后注册；GM 对局内状态的变更集中走本节公开 `debug_*` runtime API，且不得写入正式 analytics。

## 依赖

- 上游依赖：`DataLoader`、`GameState`、`GameClock`、`RNG.spawn`、`RNG.world`、`RNG.ui_choice`、`PoolManager`、`UIManager`、`SaveManager`、`MetaProgressionSystem`、`Combat`、`MapManager`、`hazards.csv`、`map_layouts.json`、`Settings` 写入的 InputMap action、locale。
- 下游调用方：当前无；后续可拆分为正式 Player / WeaponSystem / Spawner / HUD 模块。
- 禁止依赖：不得复制历史 MVP 代码；不得绕过正式 `.tscn` 场景资源临时拼长期 UI / runtime 节点；不得绕过 `PoolManager` 创建高频实体；不得直接扣生命；不得绕过 InputMap 读物理输入；不得用裸随机或原始时间。

## 扩展点

- 加武器：优先改 `weapons.json`，运行时继续解释 `base_stats` 和 `projectile`。
- 加技能：优先改 `skills.json`、`characters.json` 的 `starting_loadout.skill_ids` / `skill_resources` 和 `game_modes.json` 的 `resource_pools.skills`；新 ability tag、目标类型或效果原语先登记词表，再扩展 SkillSystem，不按技能 id 写分支。
- 加敌人：优先改 `enemies.csv`、`enemy_ai_profiles.json`、`game_modes.json` 和 `spawn_waves.csv`；行为差异通过 AI profile / tag 权重表达，不在 `enemy.gd` 按 id 分支。
- 加地图 / PCG 规则：优先改 `map_layouts.json`；运行时通过 `MapManager` 解释有限边界、手工摆点和 PCG，不在 `GameplayRunLoop` 按 layout id 分支。
- 加机关：优先改 `hazards.csv`、`game_modes.json.resource_pools.hazards` 和 `map_layouts.json`；普通范围机关复用 `Hazard`，新行为先设计通用 primitive，不按机关 id 写分支。
- 加刷怪：改 `spawn_waves.csv`；多个波次可复用当前时间窗 / 预算解释。
- 加升级候选：优先改 `growth_pools.json`；新候选如果仍是 `stat_modifier` 不需要改逻辑，新增候选类型才需要扩展运行时解释和文档。
- 场景资源化：新增稳定 gameplay / UI 层级时优先新增 `.tscn`，脚本只做节点绑定、配置和 signal 编排；只有对象池工厂与数据驱动重复项可以在运行时创建节点，并要在模块文档说明原因。
- 扩展 run 快照：新增可恢复实体字段时先保证 JSON 友好，再更新本文档、SaveManager 文档、`runtime-smoke` 和 `save-smoke`；不要保存 `PoolManager` 内部队列或节点引用。
- 扩展死亡结算：新增奖励来源时先扩展 `MetaProgressionSystem.apply_run_settlement()` summary 与 `meta-smoke`，F4 只提供局内事实，不解释公式。
- 扩展 GM 指令：先在 `GMCommandRegistry` 增命令，再在目标系统补受控 API；禁止在命令注册表里直接改 gameplay 私有字段、节点树或存档文件。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调玩家速度 / 生命 / 受伤无敌 / 中心排斥 | `player.json` / `characters.json` | `client/data/README.md` | `python tools/validate_data.py` |
| 调武器伤害 / 射速 / 弹速 | `weapons.json` | `client/data/README.md` | `validate_data` + headless |
| 调技能伤害 / 半径 / 资源消耗 / 冷却 | `skills.json`、`characters.json` | `client/data/README.md`、`docs/代码/skill_system.md` | `validate_data` + `l1-smoke` + `runtime-smoke` |
| 调敌人血量 / 速度 / 接触伤害 / 中心间距 / 占位色 | `enemies.csv` | `client/data/README.md` | `validate_data` + 手动跑一局 |
| 调敌人生态 AI | `enemy_ai_profiles.json`、`enemies.csv.tags` | `client/data/README.md`、`docs/代码/enemy_ai.md` | `validate_data` + `runtime-smoke` + 必要时 golden replay |
| 调地图边界 / PCG 机关 / 手工摆点 | `map_layouts.json` | `client/data/README.md`、`docs/代码/map_manager.md` | `validate_data` + `runtime-smoke` + `f9-demo-smoke` |
| 调机关伤害 / 半径 / 冷却 | `hazards.csv` | `client/data/README.md`、`docs/代码/hazard_system.md` | `validate_data` + `f9-demo-smoke` |
| 调刷怪节奏 | `spawn_waves.csv` | `client/data/README.md` | `validate_data` + 手动 1 分钟 |
| 调升级阈值 / 候选 | `growth.csv` / `growth_pools.json` | `client/data/README.md` | `validate_data` + `runtime-smoke` |
| 改 HUD 文案 | `strings.csv` | `client/locale/README.md` | `validate_data` |
| 改 HUD / 升级面板布局 | `client/scenes/gameplay/gameplay_hud.tscn`、`client/scenes/ui/level_up_panel.tscn`、对应脚本 | 本文档 | `runtime-smoke` + 手动不同窗口尺寸检查 |
| 改暂停 / 保存续局 | `client/scripts/ui/pause_menu.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`formal_client_boot.gd` | 本文档、SaveManager / FormalClientBoot 文档 | `runtime-smoke` + `save-smoke` + L5 暂停 / 存档 checklist |
| 改设置入口 / 设置叠层 | `title_menu.gd`、`pause_menu.gd`、`settings_panel.gd`、`formal_client_boot.gd`、`gameplay_run_loop.gd` | 本文档、Settings / UIManager / FormalClientBoot 文档 | `settings-smoke` + `runtime-smoke` |
| 改死亡结算 / 局外升级应用 | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/ui/game_over_panel.gd`、`client/scripts/autoload/meta_progression_system.gd` | 本文档、MetaProgressionSystem / SaveManager 文档 | `runtime-smoke` + `meta-smoke` |
| 改标题局外升级入口 / 摘要 | `client/scenes/ui/title_menu.tscn`、`client/scenes/ui/meta_progression_panel.tscn`、对应脚本、`client/scripts/boot/formal_client_boot.gd`、`client/scripts/autoload/meta_progression_system.gd` | 本文档、FormalClientBoot / MetaProgressionSystem 文档 | `headless-boot` + `meta-smoke` + `runtime-smoke` + 手动标题菜单点开 |
| 改 GM 指令影响运行时 | `client/scripts/debug/gm_command_registry.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、目标系统脚本 | 本文档、DebugTools 文档、测试策略 | `debug-tools-smoke` + `debug-tools-release-smoke`，必要时追加 `runtime-smoke` / `meta-smoke` |
| 改运行时行为 | `client/scripts/gameplay/*.gd` | 本文档、必要时 GDD / ADR | L0 + L2 + `runtime-smoke`，必要时补 L1 |
| 改鼠标 / 手柄瞄准手感 | `client/scripts/gameplay/player.gd`、`weapon_system.gd`、`client/tools/runtime_smoke.gd` | 本文档、GDD、词表、测试策略 | `lint_gdscript_rules` + `lint_semantic_rules` + `runtime-smoke` + `replay-input-smoke` |

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
| 玩家走出地图 | `MapManager.bounds()` 是否配置；`Player.set_movement_bounds()` 是否调用；`map_layouts.json.bounds` 是否有效 |
| 机关不出现 | `map_layouts.json` 是否生成 placement；`hazards.csv.pool_id` 是否已注册；`runtime-smoke` 是否通过 active hazards 断言 |
| FEA-12 不伤害玩家 | 玩家是否在机关半径内；玩家无敌窗口是否清零；`hazards.csv.damage` / `damage_type` 是否有效；`f9-demo-smoke` 是否通过 |
| 机关续局后位置变化 | run payload 是否包含 `map.hazard_placements` 与 `hazards`；恢复是否误重新消耗 `RNG.world` |
| 第二敌人不出现 | `enemies.csv.pool_id` 是否为已注册池；`game_modes.json.resource_pools.enemies` 与 `spawn_waves.csv.enemy_id` 是否引用该敌人；`runtime-smoke` 是否通过第二敌人池断言 |
| 敌人不按生态关系互动 | `enemies.csv.ai_profile_id` 是否正确；`enemies.csv.tags` 是否含 `tag_enemy_prey` / `tag_enemy_predator` / `tag_enemy_territorial`；`enemy_ai_profiles.json` 的 `hunt_tags` / `flee_tags` 是否在感知半径内有权重 |
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
| 详细数值面板不显示或导致暂停 | `show_stats_panel` action 是否由 `Settings` 写入 InputMap；`GameplayRunLoop._update_stats_panel()` 是否只在 `PLAYING` 下显示 HUD 叠层；不应调用 `UIManager.push()` 或改变 `GameState` |
| 暂停菜单打开设置后关不掉 | `SettingsPanel` 是否是栈顶；`SettingsPanel.request_close()` 是否复用关闭按钮路径；`runtime-smoke` 是否通过暂停设置入口断言 |
| 手柄 / 键盘返回键不生效 | `Settings` 是否把 `input.ui_back` 写入 InputMap；栈顶 UI 是否实现 `request_close()`；不应依赖 `UIManager` 盲目出栈 |
| 手柄导航时新打开 UI 没有焦点 | 最近是否有手柄输入；UI 是否有可聚焦控件；复杂面板是否实现 `grab_default_focus()`；`runtime-smoke` 是否覆盖鼠标无焦点和手柄补焦点 |
| 保存后标题没有继续游戏 | `SaveManager.has_save(slot_0, run)` 是否为 true；旧存档是否因 hash mismatch 被隔离 |
| 继续坏档后没有提示 | `TitleMenu` 是否存在 `RunSaveNoticeLabel`；`ui_run_save_unavailable` 是否在 `strings.csv` 与 `.translation` 中；`runtime-smoke` 是否通过坏 run 存档点击继续断言 |
| 继续游戏后状态不对 | run payload 是否包含地图 / 机关 / 玩家 / 武器 / 敌人 / 子弹 / 经验球 / RNG / GameClock / `ui_restore`；恢复时是否通过 `PoolManager.acquire()` 重建实体；暂停和升级选择是否经由 `UIManager` 恢复 |
| GM 命令没有生效 | 当前是否为 debug/dev_tools 构建；`DebugConsole` 是否存在；命令是否通过 `GameplayRunLoop.debug_*` / `MetaProgressionSystem.debug_*` 受控 API，而不是直接改节点 |

## 测试义务

- Gameplay runtime 代码改动必跑：`python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`。
- Gameplay runtime / UI 场景结构改动还必须跑 `python tools/godot_bridge.py --project client runtime-smoke`，涉及标题局外升级面板时追加 `meta-smoke`。
- 涉及启动、输入、WeaponSystem、SkillSystem、子弹、敌人、EnemyAI、Spawner、经验球、升级选择、Combat 或失败状态时追加 `python tools/godot_bridge.py --project client runtime-smoke`。
- 涉及有限地图、`map_layouts.json`、PCG 摆放、手工机关摆点、HazardSystem 或 `hazards.csv` 时追加 `python tools/godot_bridge.py --project client runtime-smoke`、`python tools/godot_bridge.py --project client f9-demo-smoke`；涉及 run 快照恢复时追加 `save-smoke`。
- 涉及技能目标、资源、冷却、效果解释或 run 技能快照时追加 `python tools/godot_bridge.py --project client l1-smoke`；改 run 快照恢复还要追加 `save-smoke`。
- 涉及 gameplay 输入录制、`Replay` 输入事件、升级选择 decision、暂停 / 返回 action 录制时追加 `python tools/godot_bridge.py --project client replay-input-smoke`；涉及升级选择 replay 基线时追加 `capture-golden-replay --golden-scenario golden_level_up_choice` 与对应 `replay-runner --replay-file client/tests/replays/golden_level_up_choice.replay --rerun-runtime-summary`。
- 涉及暂停、保存退出、标题继续、坏档提示、RNG / GameClock 快照或 run payload 时必须追加 `python tools/godot_bridge.py --project client runtime-smoke` 与 `python tools/godot_bridge.py --project client save-smoke`，并做至少一次手动保存续局检查。
- 涉及标题 / 暂停设置入口、设置面板关闭、`ui_back` 返回或运行时语言刷新时，追加 `python tools/godot_bridge.py --project client settings-smoke` 与 `python tools/godot_bridge.py --project client runtime-smoke`。
- 涉及死亡结算、局外成长、`meta` 存档或永久升级应用时追加 `python tools/godot_bridge.py --project client meta-smoke`；如果改了 F4 死亡接入或失败面板，同时跑 `runtime-smoke`。
- 涉及 GM 指令或 runtime debug API 时，追加 `python tools/godot_bridge.py --project client debug-tools-smoke` 与 `python tools/godot_bridge.py --project client debug-tools-release-smoke`；命令影响局内战斗时追加 `runtime-smoke`。
- 数据 / locale 变化还要跑 `python tools/validate_data.py`、`python tools/lint_project_rules.py`。
- 地图 / 机关数量、对象池生命周期或性能相关变化追加 `python tools/godot_bridge.py --project client perf-probe`；影响稳定运行时摘要时重跑 checked-in golden replay runner。
- 当前没有 GUT runner，F4 首切片用 L0 + L2 + `runtime-smoke` + 手动 1 分钟跑通作为阶段门槛；后续接入 Godot 测试时补 Player / Combat / Pool / Spawner 的 L1。

## 迁移 / 兼容

F5 已开始写 `SaveManager` 的 `run` kind，F6 首切片已开始写 `meta` kind。当前 gameplay runtime 自身 payload schema version 为 2；`SaveManager` 的 `run` envelope version 仍为 2，并提供 v1 -> v2 迁移来补齐早期 payload 可能缺失的结构字段。`ui_restore` 是 run payload 的可选恢复提示，缺失时按 `playing` 兼容旧 run 存档；`skills` 是可选技能快照，缺失时按空技能状态兼容旧 run 存档；`map` / `hazards` 缺失时由迁移补空结构，运行时会按当前 layout 重新生成初始机关，保证可加载但不保证旧局逐帧一致。死亡结算不写入 `run` payload，而是通过 `MetaProgressionSystem` 更新 `meta` profile；后续新增遗物、主动道具、技能栏、地图兴趣点或局外奖励时，需要决定是否提升 runtime payload schema、`meta` payload schema 或 SaveManager kind version，并补迁移 / roundtrip 测试；不得保存对象池内部状态或节点引用。

## 相关文档

- `docs/AI协作/工作包/F4-MinPlayableLoop.md`
- `docs/正式项目工作规划.md` F4
- `docs/代码/debug_tools.md`
- `docs/游戏设计文档.md` §3 / §4 / §5.3 / §9.13 / §9.15.1
- `docs/代码/combat.md`
- `docs/代码/map_manager.md`
- `docs/代码/hazard_system.md`
- `docs/代码/skill_system.md`
- `docs/代码/meta_progression_system.md`
