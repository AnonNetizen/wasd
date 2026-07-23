# Gameplay Runtime 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式客户端 gameplay runtime 的聚合模块契约；拆分 Player、WeaponSystem、Enemy、Spawner、HUD 等长期模块或改变公共行为时必须同步本文档、AI 导航、代码索引和相关阶段工作包。
> 玩家相机的项目适配行为归本文档；Phantom Camera vendored 内部架构、公共 API、编辑器工具和升级补丁归 `docs/代码/phantom_camera.md`。
> gameplay 的输入消费行为归本文档；GUIDE 插件内部归 `docs/代码/guide.md`，action / context / 重绑定 / 回放输入边界归 `docs/代码/input_service.md`。

## 职责

- 在正式 `client/` 内提供一局最小战斗：最小标题入口、标题设置入口、标题装备 Mod 入口、有限地图、玩家移动、相机居中、基础背景参照、起始武器、起始主动技能、池化子弹、池化敌人、池化机关、波次刷怪、HUD、主动暂停、暂停设置入口、暂停保存退出、标题继续游戏、暂停 / 可选升级 UI 恢复点、失败后摘要、重开 / 回标题。ADR #120 后默认标准模式不启用局内升级三选一；经验升级能力保留给未来挂接 `growth_pools` 的非默认模式。
- 复用 F3/F9/F10 已建立的数据边界，并由 F13 增加 `module_worlds.json`、`module_templates.json` 与 `modules/*.json`；模块世界只引用既有敌人、机关、奖励、目标和撤离 primitive，不在运行时调用 AI。
- 第一版只做标准生存模式、默认角色、默认起始武器、默认主技能、第二个数据驱动技能和通用范围机关的竖切；F5 首片已接入 gameplay runtime 的 `run` 续局快照；F11 已把下一局属性来源切到 Gear Mod 英雄 / 武器 loadout，接入标题装备 Mod 面板，并在玩家归因掉落 Mod 时显示 HUD 暂存提示。ADR #117 后旧 `MetaProgressionSystem` 运行时、标题旧升级面板、死亡结算旧货币 / 账号经验奖励和 `meta-smoke` 已删除；ADR #120 后标准模式转为暗黑式短刷图，`mode_standard_survival` 不挂 `growth_pools`，因此默认不产经验球、不弹升级三选一。F12 首片已把标准局数据调为 8-12 分钟软目标：偏外侧出生、0-1 / 1-4 / 4-7 / 7-9 / 9+ 分钟导演阶段、四个 director 兴趣点、7 分钟小巢核压力、兴趣点 dust / Mod 暂存、可见缓存箱交互，以及可被子弹 / Combat 摧毁的精英巢点 / 小巢核目标；资源缓存 / Mod 缓存通过 `requires_interaction` 生成低频 `InterestPointCache`，玩家进入半径后按 `interact` 打开，不再被子弹摧毁或进圈自动领取；缓存箱使用独立格心 anchor、矩形 footprint 和低矮俯视箱体表现，功能色仅作为小嵌片区分 Mod / 资源缓存，MapManager 会让关联 director 机关避开缓存箱 footprint；ADR #122 后 Gear Mod / dust 先进入 `run.pending_loot`，ADR #123 后击破小巢核只开启贴格撤离区，ADR #125 后该撤离区按矩形俯视格绘制和判定；玩家站进撤离区完成短读条后才提交到 `meta.gear_mods`、删除 `run` 并显示完成面板；`GameOverPanel` 会按成功 / 失败列出带回或丢失的 dust / Gear Mod、击杀数和用时；死亡 / 放弃不带回。正式核心美术 / 行为、多出口撤离、更正式 Result UI、缓存箱守卫 / 爆出表现还未实现。角色选择、完整商店 / 局外包装、技能 UI、音频、美术资产或平衡 sim 仍未实现。升级内容只保留 `stat_modifier` 最小切片，供未来非默认模式按数据与设计重新启用。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改运行时启动 / 重开 | `client/scripts/gameplay/gameplay_run_loop.gd` |
| 改模块大地图 / 模块模板 / 流式加载 | `docs/代码/module_world_manager.md`、`client/scripts/gameplay/module_world_manager.gd`、`client/scripts/gameplay/module_chunk.gd`、`client/data/module_worlds.json`、`client/data/module_templates.json`、`client/data/modules/*.json` |
| 改标题 / 失败面板 | `client/scripts/ui/title_menu.gd`、`client/scripts/ui/game_over_panel.gd` |
| 改标题装备 Mod 面板 | `client/scripts/ui/gear_mod_panel.gd`、`client/scripts/autoload/gear_mod_system.gd`、`client/scripts/boot/formal_client_boot.gd` |
| 改暂停 / 保存退出 | `client/scripts/ui/pause_menu.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`docs/代码/save_manager.md` |
| 改失败面板 / run 清理 | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/ui/game_over_panel.gd` |
| 改玩家移动 / 相机 | `client/scripts/gameplay/player.gd`、`client/scripts/gameplay/gameplay_camera_controller.gd`、`client/data/camera_feedback.json` |
| 改按住开火 / 子弹生成 | `client/scripts/gameplay/weapon_system.gd`、`bullet.gd` |
| 改子弹墙体阻挡 / 穿墙能力 | `client/scripts/gameplay/bullet.gd`、`client/scripts/gameplay/module_chunk.gd`、`client/data/weapons.json`、`docs/代码/module_world_manager.md` |
| 改主动技能释放 / 资源消耗 | `docs/代码/skill_system.md`、`client/scripts/gameplay/skill_system.gd`、`client/data/skills.json` |
| 改敌人对玩家 AI / 接触伤害 | `docs/代码/enemy_ai.md`、`client/scripts/gameplay/enemy.gd`、`enemy_ai_profiles.json` |
| 改有限地图 / PCG / 人工摆点 | `docs/代码/map_manager.md`、`client/scripts/gameplay/map_manager.gd`、`client/data/map_layouts.json` |
| 改机关运行时 / FEA-12 | `docs/代码/hazard_system.md`、`client/scripts/gameplay/hazard.gd`、`client/data/hazards.csv` |
| 改战区导演 / 阶段主题 / 兴趣点 | `docs/代码/warzone_director.md`、`client/scripts/gameplay/warzone_director.gd`、`client/data/warzone_directors.json` |
| 改经验球 / 拾取 | `client/scripts/gameplay/pickup_orb.gd`、`player.json` |
| 改升级候选 / 奖励 | `growth.csv`、`growth_pools.json`、`client/data/game_modes.json`、`client/scripts/gameplay/gameplay_run_loop.gd`；默认模式不挂 `growth_pools`，未来模式启用时才进入升级选择 |
| 改 HUD 文案 / 详细数值面板 | `client/scripts/gameplay/gameplay_hud.gd`、`client/scenes/gameplay/gameplay_hud.tscn`、`client/locale/strings.csv` |
| 改稳定节点结构 / UI 层级 | `client/scenes/gameplay/*.tscn`、`client/scenes/ui/*.tscn` |
| 改 GM 指令影响局内状态 | `docs/代码/debug_tools.md`、`client/scripts/debug/gm_command_registry.gd`、`client/scripts/gameplay/gameplay_run_loop.gd` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/boot/formal_client_boot.gd` | 数据校验通过后挂载 gameplay runtime |
| `client/scenes/gameplay/gameplay_run_loop.tscn` | 正式 gameplay runtime 场景；包含 `ActiveWorld`、`WorldBackground`、`Player` 和 `GameplayHud` |
| `client/scenes/gameplay/player.tscn` | 正式玩家场景；包含 `GameplayCameraController`、`WeaponSystem`、`StatusEffectComponent` 与由 `Polygon2D` / `Line2D` 组成的可编辑占位视觉，不挂 3D 正交视觉层 |
| `client/scenes/gameplay/gameplay_camera_controller.tscn` / `client/scripts/gameplay/gameplay_camera_controller.gd` | 稳定摄像机场景与类型化门面；管理 `Camera2D` + Phantom Camera host / player PCam / 受伤 noise emitter，读 `camera_feedback.json` 并响应 `gameplay.screen_shake` |
| `client/scenes/gameplay/bullet.tscn` / `enemy.tscn` / `pickup_orb.tscn` / `hit_spark.tscn` / `damage_number.tscn` / `hazard.tscn` | 对象池实体场景；由 `PoolManager` 工厂实例化并复用。玩家、敌人、子弹、掉落与命中特效的静态占位表现由可编辑 `Polygon2D` / `Line2D` 子节点承载，不再走实体 `_draw()` |
| `client/scenes/gameplay/interest_point_target.tscn` / `client/scripts/gameplay/interest_point_target.gd` | F12 低频兴趣点目标：精英巢点和小巢核可伤害占位；视觉 footprint 对齐地图矩形格，摧毁后通过 signal 触发通用兴趣点奖励 |
| `client/scenes/gameplay/interest_point_cache.tscn` / `client/scripts/gameplay/interest_point_cache.gd` | F12 低频缓存箱：资源缓存 / Mod 缓存可见交互占位；矩形 footprint 对齐地图矩形格，主体是低矮俯视箱体，功能色只作为小嵌片，渲染在地图背景之上、机关 / 敌人 / 玩家之下，打开后保留已开启状态 |
| `client/scenes/ui/title_menu.tscn` / `gear_mod_panel.tscn` / `pause_menu.tscn` / `settings_panel.tscn` / `game_over_panel.tscn` / `level_up_panel.tscn` | 正式 UI 场景；脚本只绑定稳定节点、连接 signal 和刷新数据 |
| `client/scenes/ui/stats_row.tscn` / `level_up_choice_button.tscn` / `gear_mod_row.tscn` / `gear_mod_empty_row.tscn` / `input_binding_row.tscn` | 数据驱动重复 UI 的可编辑行模板；运行时允许实例化模板并填入文本 / signal，不允许逐个 `Label.new()` / `Button.new()` 拼装长期行结构 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 正式运行时编排、输入 action 手柄兜底注册、对象池注册、刷怪和重开 |
| `client/scripts/gameplay/module_world_manager.gd` | F13 模块世界协调器（非 autoload）：按 run seed 组合 81 个槽位、维护地图 hash / 迷雾 / 动态槽位状态，并只激活玩家周围最多 3×3 chunk。详见 `docs/代码/module_world_manager.md` |
| `client/scenes/gameplay/module_chunk.tscn` / `client/scripts/gameplay/module_chunk.gd` | 三层 TileMapLayer 与合并碰撞的可复用场景；激活时应用 `ModuleBakedData`，不逐格绘制、建 Node 或重算碰撞 |
| `client/scenes/gameplay/module_world_manager.tscn` | 预置九个 `ModuleChunk` 实例；运行时只切换 3×3 活跃邻域 |
| `client/scripts/gameplay/module_minimap.gd` | HUD 9×9 模块级迷雾、当前位置、目标与撤离方向标记 |
| `client/tools/module_world_smoke.gd` | 覆盖 seed assignment/hash、无缝跨模块、最多 9 个活跃 chunk、离开返回不重复生成、迷雾、目标后撤离及 run v4 恢复 |
| `client/scripts/gameplay/world_background.gd` | 量化矩形地图格背景；读取 `MapManager.grid_cell_size()`，让背景格、机关绘制和触发判定共享同一份地图度量，不改变世界坐标或相机缩放 |
| `client/scripts/gameplay/map_manager.gd` | 有限地图边界、PCG 机关摆放、人工摆点、刷怪位置 clamp 和地图快照 |
| `client/scripts/gameplay/player.gd` | 玩家移动、鼠标相对玩家 / 视口中心方向瞄准、方向键 / 手柄兜底瞄准、驱动场景内 2D 俯视视觉的朝向 / 受击状态、相机居中、受伤 / 死亡；提供少量受控 debug 生命 API 给 GM 命令调用 |
| `client/scripts/gameplay/warzone_director.gd` | F10 敌巢战区导演，解释固定阶段、巢变异主题、兴趣点和阶段启用 wave |
| `client/scripts/gameplay/weapon_system.gd` | 起始武器按住开火、临时武器修正和子弹池获取 |
| `client/scenes/gameplay/skill_system.tscn` / `client/scripts/gameplay/skill_system.gd` | 预置 `StatusEffectComponent` 的技能系统场景；负责主动技能释放、资源、冷却、目标筛选、效果解释和 run 快照 |
| `client/scripts/gameplay/bullet.gd` | 子弹飞行、圆形地形重叠 / 扫掠、射程 / 生命周期裁剪、敌人和兴趣点目标命中，以及墙体穿透快照 |
| `client/scripts/gameplay/enemy.gd` | 数据驱动敌人对玩家 AI、敌方友伤护栏、接触伤害、受伤 / 死亡和 AI 快照 |
| `client/scripts/gameplay/hazard.gd` | 通用机关节点：矩形范围触发、冷却、占位表现、`Combat` 伤害和快照 |
| `client/scripts/gameplay/pickup_orb.gd` | 池化经验球：进入玩家拾取范围后吸附并发放经验 |
| `client/scripts/gameplay/hit_spark.gd` / `damage_number.gd` | 池化命中反馈：Combat 成功造成伤害时生成短命火花和飘字；不进入 run 快照 |
| `client/scripts/gameplay/level_up_panel.gd` | 响应式升级三选一面板；通过 `UIManager.push()` 挂载；语言切换时用缓存候选重建按钮 |
| `client/scripts/gameplay/gameplay_hud.gd` | 响应式最小 HUD：生命、击杀、时间、等级、经验、升级 / Gear Mod / 撤离点反馈；语言切换时用当前 HUD 状态重画 |
| `client/scripts/ui/title_menu.gd` | 最小标题界面：开始 / 继续 / 装备 Mod / 设置 / 退出 |
| `client/scripts/ui/settings_panel.gd` | F7 设置面板：从标题或暂停菜单打开，读写 `Settings` 并响应语言切换 |
| `client/scripts/ui/gear_mod_panel.gd` | F11 装备 Mod 面板：从标题菜单打开，切换英雄 / 武器 loadout，显示资源、容量、Mod 列表、详情和操作反馈 |
| `client/scripts/ui/pause_menu.gd` | F5 / F7 暂停菜单：继续、设置、保存并退出、重新开始、回标题；语言切换时刷新按钮 |
| `client/scripts/ui/game_over_panel.gd` | 失败 / 完成结果面板：本局摘要、暂存战利品带回或丢失提示、重开 / 回标题；语言切换时用缓存状态重画 |
| `client/tools/runtime_smoke.gd` | gameplay runtime headless smoke，覆盖启动、输入、池化、伤害、失败状态和真实死亡结算 |
| `client/tools/debug_tools_smoke.gd` | DebugTools headless smoke，覆盖 GM 命令调用 runtime debug API 和 release guard |
| `client/tools/gear_mod_smoke.gd` | F11 Gear Mod smoke，覆盖 profile、授予、装备、容量、升级、分解、掉落、HUD 暂存提示和 Gear Mod 面板按钮流 |
| `client/tools/save_manager_smoke.gd` | F5 SaveManager run 存档可靠性 smoke，覆盖 roundtrip、备份回退、坏档隔离和迁移 |
| `client/tools/perf_probe.gd` | F8 轻量 perf / 平衡采样入口，输出 schema v2 可比较 JSON：warmup 后帧时间分布、实体峰值、池峰值、等级、击杀和预算状态 |
| `client/tools/golden_replay_capture.gd` | F8 golden replay capture 工具，固定 seed 启动真实 `GameplayRunLoop` 并采样运行时摘要；支持 basic、pause/resume、full-death 和 level-up choice 场景 |
| `client/tools/replay_input_smoke.gd` | F8 gameplay 输入录制 smoke，确认移动 / 瞄准 / pause / ui_back 写入 Replay 输入事件 |
| `tools/godot_bridge.py` | `module-world-smoke` / `module-world-technical-slice-smoke` / `runtime-smoke` / `save-smoke` / `settings-smoke` / `gear-mod-smoke` / `debug-tools-smoke` / `debug-tools-release-smoke` / F8 `l1-smoke`、`replay-smoke`、`replay-runner`、`replay-input-smoke`、`capture-golden-replay` 命令入口；`startup-probe` / `perf-probe` 保留为用户明确触发的按需入口 |
| `docs/代码/combat.md` | 伤害统一入口文档 |
| `docs/代码/map_manager.md` | 有限地图 / PCG / 人工摆点文档 |
| `docs/代码/module_world_manager.md` | F13 模块大地图 / 流式状态 / 坐标与存档文档 |
| `docs/代码/hazard_system.md` | 机关运行时文档 |
| `docs/代码/debug_tools.md` | GM 控制台、命令和 release guard 文档 |

## 场景 / 节点结构

Gameplay runtime 的稳定节点结构已迁入正式 `.tscn` 场景资源。脚本职责是读取数据、绑定场景节点、连接 signal 和刷新运行时状态；不再在业务脚本中临时拼出长期 UI / runtime 层级。允许动态生成的范围限于对象池工厂实例化场景、`UIManager` 弹窗，以及统计、升级候选、装备 Mod、输入绑定这类数据列表实例化可编辑行模板。地图范围、机关 footprint、撤离进度和 minimap 等运行时几何仍可使用专用 `_draw()`，但其颜色、线宽、间距和标记尺寸必须通过场景导出属性人工调整。

```text
FormalClientBoot
└── GameplayRunLoop (Node2D)
    ├── ActiveWorld (Node2D)
    │   ├── WorldBackground (Node2D)
    │   ├── MapManager (Node2D)
    │   ├── ModuleWorldManager (Node2D; default carrier coordinator)
    │   │   └── ModuleChunk × 9 (scene-authored pool; 0..9 active)
    │   ├── Player (CharacterBody2D)
    │   │   ├── CollisionShape2D (CircleShape2D; blocked module-cell collision)
    │   │   ├── GameplayCameraController (Node2D)
    │   │   │   ├── CenteredCamera (Camera2D; current, level, uniform scale)
    │   │   │   │   └── PhantomCameraHost (Node)
    │   │   │   ├── PlayerCamera (PhantomCamera2D; GLUED follow)
    │   │   │   └── PlayerDamageShake (PhantomCameraNoiseEmitter2D)
    │   │   ├── WeaponSystem (Node)
    │   │   └── StatusEffectComponent (Node)
    │   ├── hazard_spike_* (pooled Hazard scene, active only)
    │   ├── InterestPointTarget_* (low-frequency POI target, active only)
    │   ├── InterestPointCache_* (low-frequency POI cache, active only)
    │   ├── bullet_basic_* (pooled Bullet scene, active only)
    │   └── enemy_* (pooled CharacterBody2D Enemy scenes, active only)
    ├── SkillSystem (Node)
    │   └── StatusEffectComponent (Node)
    └── GameplayHud (CanvasLayer)
        └── Root/ModuleMinimap (Control)
UIManager
    └── UIRoot
    ├── TitleMenu (normal boot before a run)
    ├── GearModPanel (opened from title menu)
    ├── SettingsPanel (opened from title menu or pause menu)
    ├── PauseMenu (only while GameState.PAUSED)
    ├── LevelUpPanel (only while GameState.LEVEL_UP)
    └── GameOverPanel (only while GameState.GAME_OVER)
```

闲置子弹、敌人、机关和经验球节点归 `PoolManager` autoload 管理。

### Carrier 概念（F13）

`GameplayRunLoop` 的地图 carrier 现在分为两条明确路径：

- **module-world** 是 `mode_standard_survival` 默认载体：世界固定 9×9 模块、每模块 11×11 格；`ModuleWorldManager` 按 seed 组合 approved 模板，只激活玩家周围 3×3，并保存离开邻域的槽位动态状态。
- **open-warzone** 仅由 `--open-warzone` 或测试 debug API 显式启用，保留 F12 `MapManager` / `WarzoneDirector` 对照回归；模块模式不会运行旧 PCG / director 摆点。
- carrier 只决定地图载体与内容入口；对象池生成、`Combat`、击杀归因和战利品提交仍由 `GameplayRunLoop` 负责，`ModuleWorldManager` 不直接绕过统一 autoload。
- 线性房间 carrier 已由 ADR #142 取代并删除；旧 run v3 会明确重置，不尝试迁移其房间进度。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `FormalClientBoot` 跑数据 schema smoke，正常启动显示 `TitleMenu`；标题菜单可打开 `GearModPanel` 配置英雄 / 武器 Mod，也可打开 `SettingsPanel` 修改设置；旧局外升级入口和面板已删除；`--runtime-smoke` 模式跳过标题并直接创建 `GameplayRunLoop` | `DataLoader.validate_project_data()`、`UIManager.push()` |
| 开局 | 普通标题开始 / 局内重开由 `FormalClientBoot` 先调用 `RNG.set_random_run_seed()`，再实例化 `gameplay_run_loop.tscn`；运行时重置 `GameClock`，注册 / 预热子弹、经验球、机关、命中反馈和当前 F4 敌人对象池，读取默认模式 / 角色 / 起始武器，并在玩家 / 武器配置后分别应用 `GearModSystem.current_modifiers("hero")` 与 `GearModSystem.current_modifiers("weapon")`；工具 / replay 路径可显式固定 seed 后直接启动 runtime | `RNG.set_random_run_seed()`、`PackedScene.instantiate()`、`PoolManager.register_pool()`、`DataLoader.load_json()`、`GearModSystem.current_modifiers()` |
| 地图 / 模块 | 默认按 `module_worlds.json` 配置 99×99 格矩形世界；中心模块 `(4,4)` / 全局格 `(49,49)` 对齐世界原点。`GameplayRunLoop` 从已加载 EnemyAI profile 的最大视觉范围推导局部流场半径（当前 8 格）并传给 `ModuleWorldManager`；Manager 生成 assignment/hash、构建 3×3 活跃邻域并驱动模块内容。玩家和敌人仍复用 `MapManager` 的矩形 bounds、格吸附和 clamp。仅 `--open-warzone` 回归路径解释旧 PCG / director 摆点 | `ModuleWorldManager.configure()`、`build_assignment()`、`tick()`、`MapManager.configure()`、`PoolManager.acquire()`、`Combat.apply_damage()` |
| 战区导演 | `WarzoneDirector` 读取 `warzone_directors.json` 的当前模式导演，用固定时间 phase 组织巢变异主题、兴趣点和启用 wave；F12 标准局按 0-1 / 1-4 / 4-7 / 7-9 / 9+ 分钟组织短刷图节奏，9 分钟后软加压但不硬切；兴趣点交给 `MapManager` 初始机关生成并透传领取 / 奖励 / 交互 / 可伤害目标 / 撤离元数据；`GameplayRunLoop` 对无目标且不要求交互的兴趣点按 `claim_radius`、`claim_start_time` 和玩家位置把 dust / Mod 放入 `run.pending_loot`；对 `requires_interaction=true` 的兴趣点按 `interest_point_cache_position` 生成可见 `InterestPointCache`，玩家进入半径后按 `interact` 打开并暂存奖励；对有 `target_hp` 的兴趣点按 `interest_point_target_position` 生成立即可被子弹 / `Combat` 伤害的格子化 `InterestPointTarget`，摧毁后暂存奖励；POI 目标 / 缓存 anchor 均由 MapManager 保证贴格并避开 active hazards；小巢核领取后开启贴合地图矩形格的撤离矩形，玩家完成 `extraction_hold_time` 读条后提交暂存战利品并进入结果面板；不读玩家状态、不随机动态调难 | `WarzoneDirector.configure()`、`is_wave_enabled()`、`interest_points_for_layout()`、`GearModSystem.grant_resource()`、`GearModSystem.grant_mod()`、`debug_summary()` |
| 模块世界 carrier（F13） | 默认开局配置完整 9×9 assignment；固定中心起点、目标和撤离锚点，普通槽位从 approved 模板池按 `RNG.world` / run seed 组合。`tick()` 在跨越模块边界时按世界槽位保存离开邻域的敌人、机关、子弹与掉落，释放池化实体并激活新 3×3 邻域；子弹 / 掉落以卸载时的实际位置归槽，避免跨缝后错误留存。迷雾在进入模块后揭示，完成目标后激活撤离。续局由 `module_world` 块恢复 assignment、rotation、内容敏感 map hash、迷雾、目标 / 撤离和 81 个槽位状态；世界配置或已引用模块 JSON 任一玩法内容变化都会使 hash 不匹配并拒绝继续恢复 | `ModuleWorldManager.build_assignment()`、`tick()`、`snapshot()` / `restore_state()`、`PoolManager.acquire()` |
| 背景 | 在玩家附近绘制量化矩形地图格和原点十字；网格来自 `map_layouts.json.grid`，与机关尺寸 / 判定共用同一格度量，但不缩放或旋转世界坐标，也不模拟斜俯视透视 | `WorldBackground.configure()` |
| 输入 | `InputService` 从 GUIDE 的 gameplay context 产生 `move` / `aim` `Vector2` 与按钮 intent。键鼠瞄准由 pointer viewport position 经当前 canvas / camera transform 得到世界方向；右摇杆、D-pad 或方向键是兜底。`show_stats_panel` 只显示 HUD 叠层，`interact` 打开范围内缓存。Replay v2 记录最终 move / aim 与按钮值，鼠标和手柄使用同一 intent wire | `InputService`、生成 `Actions` 常量、`Replay` v2 |
| 移动 / 瞄准 / 相机 | 玩家按数据移速在 2D 平面移动；`GameplayCameraController` 把 `PlayerCamera` 配成 Phantom Camera `GLUED` 严格跟随，`CenteredCamera` 保持屏幕水平、玩家居中和等比缩放。鼠标激活后按 canvas transform 换算后的世界方向瞄准；无鼠标动作时用方向键 / 手柄右摇杆 / D-pad 兜底，松开保持上一方向 | `Player.aim_direction`、`GameplayCameraController.configure()` |
| 按住开火 | WeaponSystem 读取 `InputService` 的 `fire` intent；按住时按 `fire_rate` 从子弹池取节点并配置，松开停火 | `InputService` / `PoolManager.acquire()` |
| 子弹移动 / 地形 | 玩家和敌方子弹移动前先用 `hit_radius` 圆形 `intersect_shape()` 检查初始重叠，再用 `cast_motion()` 扫掠本帧位移；只查询地形层 bit 1。命中后停在安全比例、立即 `PoolManager.release()`，不再检查墙后伤害目标；`wall_pierce > 0` 的发射快照跳过全部地形查询 | `PhysicsShapeQueryParameters2D` / `PhysicsDirectSpaceState2D` |
| 子弹命中 | 地形通过后，子弹才用距离检测命中 `active_enemies` 与 `active_interest_point_targets` 组；远程敌人可通过同一 `Bullet.configure()` 指定 `active_player` 目标组和敌方队伍，伤害统一走 `Combat.apply_damage()`。`pierce_count` 只表示可额外命中的伤害目标数量，不影响墙体 | `DamageInfo` |
| 主动技能 / 状态 | SkillSystem 从 `skills.json` 读取起始技能列表；默认 `use_active_item` action 释放第一个技能 `skill_overdrive_rounds`，消耗角色声明的 `mana`，通过 `skill_effect_weapon_modifiers` 临时强化玩家主武器射速与弹速；技能激活使用项目版轻量 GAS 的 ability tag gating，状态效果通过目标实体的 `StatusEffectComponent` 管理，技能冷却、资源回复、状态过期和 DoT tick 都走 `GameClock` | `SkillSystem.cast_primary_skill()`、`SkillSystem.cast_skill(skill_id)`、`WeaponSystem.apply_temporary_modifiers()`、`Combat.apply_damage()`、`Player.apply_status_effect()`、`Enemy.apply_status_effect()` |
| 刷怪 | Spawner 读取 `spawn_waves.csv` 的时间窗、间隔、上限和预算，在视野外围刷敌人；F10 起先通过 `WarzoneDirector.is_wave_enabled()` 判断当前 phase 是否允许该 wave，当前有追猎者、疾行者、潜猎者、喷棘者和壁垒五种数据化敌人 | `GameClock.now()`、`RNG.spawn`、`WarzoneDirector.is_wave_enabled()` |
| 机关触发 | `Hazard` 在 `PLAYING` 下按 `GameClock.delta_scaled()` 消耗冷却；玩家进入矩形范围后构造 `DamageInfo` 并交给 `Combat`，当前 FEA-12 用于验证 PCG / 手工摆点和伤害链路 | `Hazard.configure()`、`Combat.apply_damage()` |
| 受击 / 击杀反馈 | `Combat.damage_applied` 成功应用伤害后生成池化 `hit_spark` 与 `damage_number`；玩家有效受伤另按 `camera_feedback.json` 触发 Phantom Camera 位移震屏，随机走 `RNG.camera_fx`，无敌拦截和敌人受伤不触发；`gameplay.screen_shake=false` 会立即停止并抑制震屏。玩家占位短暂红闪，敌人命中时短暂暖白闪，死亡后橙色淡出并归池 | `GameplayCameraController.play_player_damage_shake()`、`PoolManager.acquire()` |
| 敌人行为 | 敌人从 schema v3 `enemy_ai_profiles.json` 读取视线 / 路径 / 记忆感知、玩家权重和动作列表；模块模式注入 `ModuleWorldManager`，畅通时直追、受阻时沿局部共享流场绕行，守家 / 最后已知位置使用决策 tick 的全图 AStar waypoint。玩家是唯一战斗目标，冲锋要求清晰走廊，远程开火要求当前地形视线；敌方友伤被拒绝，中心分离只防重叠 | `Enemy.defeated`、`docs/代码/enemy_ai.md` |
| 经验掉落 | ADR #120 后默认标准模式没有成长候选池，玩家归因击杀不生成经验球；未来模式若在 `game_modes.json.resource_pools.growth_pools` 声明升级池，则敌人死亡按 `exp_reward` 生成池化经验球，进入 `pickup_range` 后吸附并发放经验 | `PoolManager.acquire(PICKUP_ORB)` |
| 升级选择 | 只在当前模式加载到 `growth_pools` 候选池时启用。累计经验达到 `growth.csv` 阈值后进入 `GameState.LEVEL_UP`，玩法时间冻结；候选按权重和 `RNG.ui_choice` 抽取，入选后按 id 稳定排序以保证选择索引可回放；升级面板可在暂停态响应鼠标选择，也可按 `pause` action 把暂停菜单叠到升级面板上；选择后通过 `Replay.record_decision(level_up, ...)` 记录等级、候选数量、候选 id、选择 id 和 luck 快照，再应用 `stat_modifier`、显示获得反馈并回到 `PLAYING`。`golden_level_up_choice` 是测试 harness 显式调用 `debug_enable_level_up_growth()` 的能力回归，不代表默认标准模式启用升级。 | `LevelUpPanel.choice_selected`、`LevelUpPanel.pause_requested` |
| 主动暂停 | `pause` action 在 `PLAYING` 中打开 `PauseMenu`，在 `LEVEL_UP` 中由升级面板请求把 `PauseMenu` 叠在升级面板上；菜单通过 `UIManager` 请求 `GameState.PAUSED`，玩法时间、敌人、子弹和刷怪冻结，菜单仍响应鼠标、`ui_back` 和再次 `pause` action；暂停菜单可打开 `SettingsPanel`，关闭后仍回到同一个暂停菜单；关闭升级态上方的暂停菜单后必须回到 `LEVEL_UP` | `UIManager.push()`、`GameState.PAUSED` |
| 保存退出 / 继续 | 暂停菜单“保存并退出”生成 `run` payload 并写入 `SaveManager`，其中包含 `RNG.snapshot()`、`pending_loot` 和撤离状态；标题菜单检测到 `run.save` 后显示“继续游戏”，加载 payload 后由 gameplay runtime 恢复 RNG / GameClock、暂存战利品、已开启撤离区和读条进度，并通过对象池重建活跃敌人、子弹和经验球，再按 `ui_restore` 回到普通游玩、暂停菜单或升级选择面板；继续游戏不生成新 seed，也不结算战利品；若续局读取失败，坏档由 `SaveManager` 隔离，标题菜单显示重置提示并隐藏继续按钮 | `SaveManager.save()`、`SaveManager.load_envelope()`、`configure_restore_snapshot()` |
| UI 布局 | HUD 使用全屏锚点下的 `MarginContainer + VBoxContainer`；升级面板使用全屏遮罩、居中容器和按视口宽度夹取的面板宽度，随窗口尺寸调整 | `Control.set_anchors_preset()` |
| 运行时语言刷新 | `Localization.locale_changed` 发出后，标题、暂停、设置、HUD、升级、失败页和 Gear Mod 面板用自身缓存的状态或配置数据刷新文本；订阅的 UI 在 `_exit_tree()` 断开 signal，避免离树节点收到后续语言切换 | `Localization.locale_changed`、`refresh_texts()` |
| 失败 / 撤离 / 重开 | 玩家生命归零后删除 `run` 存档、丢失 `pending_loot`、进入 `GameState.GAME_OVER`、冻结 `GameClock` 并显示唯一失败面板；小巢核击破后仍保持 `PLAYING`，只有玩家站进撤离区完成读条才提交 `pending_loot`、删除 `run` 并显示完成面板。结果面板展示本局击杀、时长，以及成功带回或失败丢失的 dust / Gear Mod 清单；不写旧局外货币 / 账号经验，也不提供旧局外升级购买或跳转入口。玩家可重开或回标题，按 `pause` 仍可快捷重开 | `SaveManager.delete(run)`、`UIManager.push()`、`GameState.change_state()`、`GameplayRunLoop.restart_requested` |
| DebugTools smoke | `debug-tools-smoke` 启动一局并通过 `DebugConsole` 调用 `GMCommandRegistry`，验证 help/stats/spawn/xp/hp/damage/heal/dust/kill/clear；`debug-tools-release-smoke` 模拟 release guard，确认没有 `DebugConsole` / `GMCommandRegistry` 或 debug action | `client/tools/debug_tools_smoke.gd` / `docs/代码/debug_tools.md` |
| 自动 smoke / 按需 probe | `module-world-smoke` 验证默认 81 槽、流式状态、迷雾、目标撤离和 run v4；`runtime-smoke` / `f9-demo-smoke` 显式使用 open-warzone 回归。Replay runner 重建同 seed 并对照 `module_map_hash`。仅当用户明确要求性能测试时，`perf-probe` 才在 180 帧采样内强制跨模块并检查 p99、单帧尖峰、内存和实体上限 | `client/tools/module_world_smoke.gd` / `runtime_smoke.gd` / `save_manager_smoke.gd` / `replay_runner.gd` / `golden_replay_capture.gd` / `perf_probe.gd` |

## 公共 API

F4 脚本当前是阶段性内部模块，主要公共面向为 signal 和实体生命周期：

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `Player.configure(base_stats)` | 合并后的玩家属性 | `void` | `move_speed` / `max_hp` / `health_regen` / `damage_invulnerability_duration` / `player_separation_radius` 来自数据 |
| `Player.invulnerability_remaining()` | 无 | `float` | 只读诊断值；用于 smoke / 调试确认玩家侧无敌窗口是否归零 |
| `Player.pickup_range()` / `pickup_orb_speed()` / `luck()` / `separation_radius()` / `stat_value(stat)` | 无 / stat id | `float` | 只读运行时属性；经验球、升级候选数量判定、玩家中心排斥和 HUD 详细数值面板使用 |
| `Player.aim_at_world_position(world_position)` | 世界坐标 | `void` | 按玩家到目标世界坐标的方向更新 `aim_direction`，并清掉上一帧鼠标瞄准缓存；headless smoke 和未来脚本化瞄准可复用，真实鼠标输入使用视口中心偏移 + 相机投影反算路径 |
| `Player.apply_modifiers(modifiers)` | `growth_pools.json` 的 modifiers | `void` | 按 `(基础 + 加法) * 乘法` 更新玩家运行时属性 |
| `Player.apply_status_effect(status_effect)` / `active_statuses()` | `StatusEffect` 兼容对象 / 无 | Dictionary / `Array[String]` | 玩家状态走 `StatusEffectComponent`；新开局 `configure()` 清空状态与 owned ability tags |
| `Player.combat_team_id()` | 无 | String | 返回玩家队伍 id，供状态 DoT 等延迟伤害保存 source / target team 归因 |
| `Player.add_owned_tag()` / `remove_owned_tag()` / `has_owned_tag()` / `owned_tags()` | ability tag id | bool / `Array[String]` | 只接受词表 §12-G 已登记 tag；供状态授予 / 移除和调试查询 |
| `Player.snapshot()` / `restore_snapshot(snapshot_data)` | 无 / run payload | Dictionary / `void` | 保存位置、朝向、生命、无敌窗口、modifiers、owned tag 计数和状态效果；旧状态字段缺失时按无状态兼容 |
| `Player.receive_damage(info)` | `DamageInfo` | result dictionary | 只能由 `Combat.apply_damage()` 间接调用；无敌期返回 `reason=invulnerable` 且不扣生命 |
| `Player.debug_heal()` / `debug_set_life()` / `debug_clear_invulnerability()` | 调试数值 | Dictionary / `void` | 仅供 debug/dev_tools GM 指令调用；正式 gameplay 不应依赖 |
| `GameplayCameraController.configure(target, feedback_config)` | 玩家 `Node2D`、`camera_feedback.json` 根对象 | `void` | 绑定 GLUED 跟随目标并向 noise resource / emitter 写入已校验参数 |
| `GameplayCameraController.play_player_damage_shake()` / `is_player_damage_shake_emitting()` | 无 | `void` / `bool` | 只由玩家实际伤害路径触发；自行检查 `gameplay.screen_shake` |
| `WeaponSystem.configure(player, active_parent, weapon_data)` | 玩家、活跃父节点、武器数据 | `void` | 武器数据来自 `weapons.json` |
| `WeaponSystem.apply_modifiers(modifiers)` | `growth_pools.json` 的 modifiers | `void` | 按 `(基础 + 加法) * 乘法` 更新武器运行时属性 |
| `WeaponSystem.stat_value(stat)` | stat id | `float` | smoke / 调试读取当前武器数值 |
| `SkillSystem.configure(caster, active_parent, skills, resources)` | 施法者、活跃父节点、技能定义、资源定义 | `void` | 技能数据来自 `skills.json`，资源来自角色 `skill_resources`；详见 `docs/代码/skill_system.md` |
| `SkillSystem.cast_primary_skill()` / `cast_skill(skill_id)` | 无 / 技能 id | Dictionary | 失败不消耗资源；伤害效果必须走 `Combat.apply_damage()`；状态效果必须走 `StatusEffectComponent` |
| `SkillSystem.apply_status_effect(status_effect)` | `StatusEffect` 兼容对象 | Dictionary | 给释放者自身施加沉默等状态；状态授予 / 移除 ability tags 由组件管理 |
| `SkillSystem.snapshot()` / `restore_snapshot(snapshot_data)` | run 快照 | Dictionary / `void` | 保存冷却、资源、owned ability tag 计数和状态效果，不保存节点引用 |
| `Bullet.configure(stats, projectile, direction, source)` | 武器属性、弹体数据、方向、来源 | `void` | 节点必须来自 `PoolManager`；发射时快照 `wall_pierce > 0`，默认地形阻挡；当前可命中 `active_enemies` 与 `active_interest_point_targets`，伤害统一走 `Combat.apply_damage()` |
| `Enemy.configure(enemy_data, target)` | 敌人 CSV 行 + AI profile、目标玩家 | `void` | 节点必须来自 `PoolManager` |
| `Enemy.configure(enemy_data, player, navigation_provider = null)` | 合并敌人数据、玩家、可选模块导航门面 | `void` | 模块世界注入 Manager；开放战区无门面时保留直线兜底 |
| `Enemy.ai_debug_summary()` / `was_defeated_by_player()` | 无 | `Dictionary` / `bool` | debug 包含感知状态、路径距离、最后已知位置与导航模式；敌人不公开种间感知 tag API |
| `Enemy.separation_radius()` / `visual_color()` / `is_defeat_feedback_active()` | 无 | `float` / `Color` / `bool` | 只读诊断值；用于中心排斥、占位色、死亡反馈和 smoke 确认 |
| `Enemy.apply_status_effect(status_effect)` / `active_statuses()` | `StatusEffect` 兼容对象 / 无 | Dictionary / `Array[String]` | 敌人状态走 `StatusEffectComponent`；`configure()`、`_pool_release()` 和 `_pool_reset()` 清空状态，避免对象池泄漏 |
| `Enemy.combat_team_id()` | 无 | String | 返回敌人队伍 id，供状态 DoT 等延迟伤害保存 source / target team 归因 |
| `Enemy.add_owned_tag()` / `remove_owned_tag()` / `has_owned_tag()` / `owned_tags()` | ability tag id | bool / `Array[String]` | 只接受词表 §12-G 已登记 tag；供状态授予 / 移除和调试查询 |
| `Enemy.snapshot()` / `restore_snapshot(snapshot_data)` | 无 / run payload | Dictionary / `void` | 保存生命、位置、AI action / FSM、伤害归因、owned tag 计数和状态效果；旧状态字段缺失时按无状态兼容 |
| `PickupOrb.configure(amount, target, pickup_speed)` | 经验值、目标玩家、吸附速度 | `void` | 节点必须来自 `PoolManager` |
| `PickupOrb.is_attracting()` / `is_collect_feedback_active()` | 无 | `bool` | 只读诊断值；用于 smoke 确认吸附 / 拾取反馈生命周期 |
| `HitSpark.configure(spawn_position)` / `DamageNumber.configure(spawn_position, amount, defeated, player_damage)` | 反馈位置与伤害摘要 | `void` | 节点必须来自 `PoolManager`；只做短命视觉反馈，不写入 run 快照 |
| `GameplayRunLoop.current_xp()` / `current_level_xp()` / `current_level_xp_required()` | 无 | `int` | `current_xp()` 是累计总经验；HUD 使用本级经验和本级需求显示升级进度 |
| `GameplayRunLoop.create_run_snapshot()` | 无 | `Dictionary` | 生成 `SaveManager` 的 run v4 payload；`module_world` 保存 world id、seed、81 个模板分配及旋转、map hash、迷雾、目标 / 撤离和各世界槽位动态状态。只保存 JSON 友好数据，不保存 Node 或对象池内部队列；`ui_restore` 记录普通游玩、暂停菜单或升级选择面板恢复点 |
| `GameplayRunLoop.configure_restore_snapshot(snapshot)` | `Dictionary` | `void` | 在节点入树前由 `FormalClientBoot` 调用；`_ready()` 后重建玩家、武器、敌人、子弹、经验球、RNG、GameClock 和 `ui_restore` 状态 |
| `GameplayRunLoop.debug_summary()` / `debug_spawn_enemy()` / `debug_give_xp()` / `debug_heal_player()` / `debug_set_player_hp()` / `debug_damage_player()` / `debug_kill_player()` / `debug_kill_enemies()` / `debug_clear_enemies()` / `debug_damage_interest_point_target()` | GM 指令参数 | `Dictionary` | 只作为 DebugTools / smoke 的受控 runtime API；`debug_summary()` 包含 map / skills / warzone_director / interest point / extraction 摘要；刷怪走对象池，伤害 / 击杀走 `Combat`，经验走原有升级流程 |
| `GameplayRunLoop.debug_enable_level_up_growth(pool_id="default_level_up")` | growth pool id | `void` | 仅测试 / golden replay harness 显式启用局内升级池；默认标准模式仍以 `game_modes.json` 无 `growth_pools` 为准 |
| `GameplayRunLoop.debug_enable_open_warzone()` | 无 | `void` | 仅测试 / 对照回归显式切到 F12 open-warzone；正式标准模式默认模块世界 |
| `LevelUpPanel.configure(choices)` / `choose_index(index)` | 升级候选 | `void` | 面板节点通过 `UIManager` 挂载；玩家可见文案来自 locale；面板宽度随视口宽度在最小 / 最大值之间自适应；按 `pause` action 时发出 `pause_requested`；语言切换时重用 `_choices` 重建按钮 |
| `GameplayHud.set_life()` / `set_kills()` / `set_level()` / `set_xp()` / `show_upgrade_feedback()` / `show_extraction_feedback()` / `set_stats_panel_visible()` / `set_detailed_stats()` | HUD 状态 | `void` | 文案使用 `tr()`；布局使用容器和锚点而非固定屏幕坐标；详细数值面板是非模态 HUD 叠层，按住 action 显示、松开隐藏，不暂停；失败 UI 由 `GameOverPanel` 独占显示；语言切换时重用缓存生命、击杀、等级、经验、详细数值和最近反馈 key 刷新 |
| `TitleMenu.start_requested` / `continue_requested` / `gear_mod_requested` / `settings_requested` / `quit_requested` | 无 | signal | 由 `FormalClientBoot` 处理，不在标题菜单里直接创建 run；`continue_requested` 只在有 `run` 存档时可见；`gear_mod_requested` 和 `settings_requested` 会通过 `UIManager` 打开对应面板 |
| `GearModPanel.closed_requested` | 无 | signal | 由 `FormalClientBoot` 从标题菜单弹出面板并回到标题；装备、升级和分解由面板调用 `GearModSystem` API 后刷新列表、资源、容量和反馈；语言切换时刷新标题、按钮、列表和可见反馈 |
| `PauseMenu.resume_requested` / `settings_requested` / `save_and_quit_requested` / `restart_requested` / `quit_to_title_requested` | 无 | signal | 由 `GameplayRunLoop` 处理；设置只叠加 `SettingsPanel`，保存退出保留 `run` 存档，重开 / 回标题会删除旧 `run` 存档；`ui_back` 通过 `request_close()` 走继续游戏路径 |
| `GameOverPanel.configure(kills, run_time, completed, loot_summary)` | 击杀、时长、是否完成、战利品摘要 | `void` | 展示本局摘要、带回 / 丢失战利品逐项清单、重开和回标题；`loot_summary.resources` 显示资源名称和数量，`loot_summary.gear_mods[].name_key` 按 Mod 名聚合数量；文案全部来自 locale；语言切换时重用缓存状态重画 |
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

- 角色：默认读取 `character_default`，其 id 来自生成常量 `CharacterIds`；默认角色使用鼠标瞄准、2D 俯视占位完整瞄准方向表现和按住开火。
- 模式：默认读取 `mode_standard_survival`，其 id 来自生成常量 `GameModes`。
- 武器：从 `characters[].starting_loadout.weapon_id` 读取，不在代码写武器 id 分支。
- 技能：从 `characters[].starting_loadout.skill_ids` 读取，不绑定英雄 id；默认主技能为列表第一项 `skill_overdrive_rounds`，通过 `skill_effect_weapon_modifiers` 服务射击强化；技能定义在 `skills.json`，模式可用池在 `game_modes.resource_pools.skills`；ability tag / activation 条件来自词表 §12-G，状态效果与叠加规则来自词表 §9-A~§9-B。
- 技能资源：从 `characters[].skill_resources` 读取，当前默认资源为 `mana`；后续怒气、能量等资源应新增资源 id 和角色资源池，不在 SkillSystem 写死。
- 子弹池：从 `weapons[].projectile.pool_id` 读取；当前样例为已登记 `bullet_basic`。`base_stats.pierce_count` 只表示额外伤害目标数，`base_stats.wall_pierce` 为全地形开关且基础武器显式为 `0.0`。两者都经 ModifierEngine 合并，但 `Bullet.configure()` 在发射时快照结果；Buff 结束不追改飞行中的子弹。子弹占位绘制为黄色圆点加暗色轮廓，不承载行为差异。
- 敌人池：从 `enemies.csv.pool_id` 读取；当前注册已登记 `enemy_chaser`、`enemy_ranged` 与 `enemy_swarm`，不同敌人可复用同一 `Enemy` 场景和对象池。
- 敌人 AI profile：从 `enemies.csv.ai_profile_id` 引用 schema v3 `enemy_ai_profiles.json`；`perception` 分别配置视觉半径、隔墙路径感知半径和记忆时间，profile 继续负责动作评分、守家、冲锋和远程投射参数。模块模式的共享导航 / 地形视线来自 `ModuleWorldManager`，派生缓存不进 run v4。玩家是唯一战斗目标，敌方伤害来源会被拒绝；中心分离只负责防重叠。详细规则见 `docs/代码/enemy_ai.md`。
- 敌人中心间距：从 `enemies.csv.separation_radius` 读取；当前默认 9px，低于 `hit_radius` 以允许视觉重叠。
- 玩家中心排斥：从合并后的玩家 `base_stats.player_separation_radius` 读取；当前默认 10px。敌人与玩家的最小中心距离为两者分离半径之和，碰到时只推开敌人，不改变玩家移动手感；接触伤害距离会取敌人 `hit_radius` 与双方分离半径之和的较大值，避免推开后反而打不到玩家。
- 俯视资产规则：地面范围类资产（机关、AOE、房间边界、地面符号）默认使用矩形 / 方形俯视格或清晰俯视轮廓；机关和规则型地面 footprint 尺寸应表达为格子整数倍。角色、敌人、拾取物、子弹、障碍物和特效不强制矩形，但必须有清晰俯视轮廓、方向标记、功能色和真实判定形状。AI 生成正式资源或占位替换时先写清 footprint、anchor、orientation_read、sort layer 和真实判定形状。
- 玩家占位表现：默认由 `Player._draw()` 绘制蓝色 2D 圆点、白色朝向线和箭头，朝向标记按完整 `aim_direction` 旋转；受伤反馈为 0.16 秒红闪，不承载行为差异。`Player` 场景同时保留与 12 px 占位圆点一致的 `CircleShape2D`，使 `move_and_slide()` 能与模块封锁格的 `StaticBody2D` 边界碰撞；不能只画角色而省略物理 shape。正式玩家场景不再挂 `Player3DVisual`，不再用 `SubViewport + Camera3D` 正交渲染低模胶囊。
- 敌人占位表现：从 `enemies.csv.visual_color` 读取 HTML 色值作为填充色，运行时统一绘制几何三角、暗色轮廓和眼睛描边；命中反馈为 0.16 秒暖白闪，死亡反馈为 0.18 秒橙色放大淡出，只用于开发期占位可读性，不承载行为分支。
- 机关占位表现：通用 `Hazard` 绘制矩形危险地块；`hazards.csv.radius_tiles` 表示占用地图矩形格的整数倍，`MapManager.grid_cell_size()` 同时驱动背景网格、机关绘制和触发判定。
- 战区导演：`warzone_directors.json` 声明当前模式的固定 phase、mutation 和兴趣点；`GameplayRunLoop` 用它 gating wave，并把当前 layout 的兴趣点交给 `MapManager` 生成初始 `source="director"` 机关；不能让它读取玩家血量、DPS、受伤次数、输入节奏或其它玩家状态。F12 当前四个兴趣点通过通用 `resource_rewards[]` / `gear_mod_rewards[]`、`requires_interaction`、`target_hp` / `target_hit_radius` 和 `completes_run` 接线，不按 `poi_id` 特判；`requires_interaction` 缓存箱和 `target_hp` 目标都必须走 MapManager 的独立 POI anchor，不能复用陷阱位置；缓存箱是贴地 POI 视觉，层级应在地图背景之上、机关 / 敌人 / 玩家模型之下；后续守卫或核心实体仍应复用 reward / objective 数据而不是新增 id 分支。
- 玩家生命尺度：默认角色 `max_hp` 为 600.0，采用浮点血量尺度而非旧心数尺度；`health_regen` 在 `PLAYING` 状态下按 `GameClock.delta_scaled()` 自动恢复生命且不超过上限，当前默认 1.5 HP/s。
- 玩家俯视表现：`Player` 是 `CharacterBody2D`，移动、碰撞、受击、显示占位和 run 快照都维持 2D；`GameplayCameraController` 仍作为 Player 子场景，由 Phantom Camera GLUED PCam 驱动 `CenteredCamera`。当前固定 `ignore_rotation=true`、无 smoothing / damping / lookahead / dead zone / auto zoom / load tween，并保持 `Vector2.ONE` 等比缩放；鼠标瞄准通过 canvas transform 反投影回世界方向。
- 受伤无敌：从合并后的玩家 `base_stats.damage_invulnerability_duration` 读取；当前默认 `player.json` 为 0.7 秒，和受伤红闪时长分离。
- 经验球：使用词表 §8 `pickup_orb` 对象池；`player.json.base_stats.pickup_range` 控制吸附范围，`pickup_orb_speed` 控制吸附速度。经验球占位绘制为绿色圆点加暗色轮廓，吸附时显示短弧线，收集时放大淡出。
- 等级阈值：从 `growth.csv.total_xp_required` 读取累计总经验阈值；运行时内部保留累计经验判定升级，HUD 显示 `当前累计经验 - 当前等级累计阈值` / `下一级累计阈值 - 当前等级累计阈值`。
- 升级候选：从当前模式 `resource_pools.growth_pools` 引用的 `growth_pools.json` 池读取；当前 F4 只解释 `kind=stat_modifier` 且应用其 `modifiers`。候选入选使用 `RNG.ui_choice`，显示 / 选择顺序按候选 `id` 稳定排序，避免同一候选集合在不同进程中只因抽取顺序影响 replay 选择索引。选择后 HUD 使用金色文字、暗色阴影和 1.35 秒淡出显示获得反馈。
- 分辨率与 UI：当前只设计 / 验收固定 16:9，默认 viewport 由 `client/project.godot` 设为 1920×1080；窗口禁止任意拖拽缩放，非 16:9 屏幕通过 `canvas_items + keep` 等比缩放并补黑边，不拉伸、不裁切、不扩大玩法视野；F4 HUD 和升级面板使用 `Control` 锚点 / 容器布局适配经过验证的 16:9 固定预设。其他宽高比留作未来按独立固定预设接入的 P3 优化，不作为当前响应式布局目标。
- run 续局快照：`RUN_SNAPSHOT_SCHEMA_VERSION` 与 `SaveManager` run envelope 均为 v4。除通用模式、角色、时钟、RNG、玩家、武器、技能、池化实体、`pending_loot` 与 `ui_restore` 外，默认模式必须保存完整 `module_world`：世界 id / seed、81 个 assignment / rotation、内容敏感 map hash、迷雾、目标 / 撤离和逐世界槽位动态状态；同一模板复用到多个槽位时状态互不共享。子弹快照保存发射时的 `wall_pierce_enabled`；旧 run 或旧模块槽位快照缺该字段时默认 `false`，因此无需提升 run schema。map hash 覆盖世界配置和本局引用的模块 JSON；恢复时以相同 seed / assignment 重建并校验，失败则整个续局 fail closed，不把旧玩家 / 实体状态载入新地图，再恢复当前 3×3 邻域。旧 v3 run 明确标记 `legacy_run_incompatible`、显示专用“不兼容”提示后只删除 run；`meta` envelope 与 `meta.gear_mods` 不受影响。RNG 大整数 state 继续以字符串保存并在 hash 前 JSON 归一化。
- 局外成长接入：F11 后 Gear Mod 是唯一当前跨局装配运行时。死亡不再写旧局外货币 / 账号经验，也不再弹旧升级入口；死亡后仍必须删除 `run` 存档，避免继续旧局。新开局属性来源为 `GearModSystem.current_modifiers("hero")` / `current_modifiers("weapon")`：hero modifiers 只应用到 `Player.apply_modifiers()`，weapon modifiers 只应用到 `WeaponSystem.apply_modifiers()`。项目尚未上线，不维护旧局外成长测试档迁移或补偿。
- 装备 Mod 掉落：玩家归因击败敌人时，`GameplayRunLoop._on_enemy_defeated()` 会在发放击杀 / 经验后调用 `GearModSystem.roll_drop_for_enemy(enemy_id, ..., commit_immediately=false)`，把命中的 Mod 放进 `run.pending_loot`；怪物互杀或非玩家归因击杀不会计入击杀、经验或 Gear Mod 掉落。首片 `enemy_chaser` 掉落率来自 `gear_mod_drop_tables.csv` 的 `0.01`，随机走 `RNG.drop`。掉落结果携带 `name_key`，命中后通过 `GameplayHud.show_gear_mod_drop_feedback()` 显示暂存反馈；击破小巢核或未来撤离成功时才调用 `GearModSystem.grant_mod()` / `grant_resource()` 写入 `meta.gear_mods`。
- 伤害类型：从 `weapons.json` / `enemies.csv` / `hazards.csv` 读取，交给 `Combat` 校验。
- UI / HUD / 升级文案：`ui_title_name`、`ui_title_subtitle`、`ui_start`、`ui_continue_run`、`ui_run_save_unavailable`、`ui_settings*`、`ui_pause_title`、`ui_save_and_quit`、`ui_quit`、`ui_hud_life`、`ui_hud_kills`、`ui_hud_time`、`ui_hud_level`、`ui_hud_xp`、`ui_stats_*`、`ui_level_up_title`、`ui_upgrade_applied`、`ui_game_over`、`ui_restart_hint`、`ui_restart`、`ui_quit_to_title`、`ui_run_summary`、`ui_result_*`、`ui_gear_mod_*`，升级候选使用 `growth_pools.json` 的 `name_key` / `desc_key`。常驻 UI 必须在 `Localization.locale_changed` 后刷新已有节点，不依赖重启或重新实例化。
- GM / DebugTools：`debug_*` action 只由 `DebugConsole` 在 debug/dev_tools guard 通过后注册；GM 对局内状态的变更集中走本节公开 `debug_*` runtime API，且不得写入正式 analytics。

## 依赖

- 上游依赖：`DataLoader`、`GameState`、`GameClock`、`RNG.spawn`、`RNG.world`、`RNG.ui_choice`、`RNG.camera_fx`、`InputService`、`PoolManager`、`UIManager`、`SaveManager`、`GearModSystem`、`Combat`、`StatusEffectComponent`、`PhantomCameraManager`、`MapManager`、`WarzoneDirector`、`camera_feedback.json`、`hazards.csv`、`map_layouts.json`、`warzone_directors.json`、locale。
- 下游调用方：当前无；后续可拆分为正式 Player / WeaponSystem / Spawner / HUD 模块。
- 禁止依赖：不得复制历史 MVP 代码；不得绕过正式 `.tscn` 场景资源临时拼长期 UI / runtime 节点；不得绕过 `PoolManager` 创建高频实体；不得直接扣生命；不得绕过 `InputService` 读取 GUIDE / `Input` / `InputMap` 或物理输入；不得用裸随机或原始时间。

## 扩展点

- 加武器：优先改 `weapons.json`，运行时继续解释 `base_stats` 和 `projectile`。
- 加穿墙 Buff：通过既有 modifier 管线给 `wall_pierce` 增加正值；不要复用 `pierce_count`，也不要把它解释成有限穿墙次数。穿墙只忽略地形，不自动附加穿敌、穿机关、反弹或爆炸。
- 加技能：优先改 `skills.json`、`characters.json` 的 `starting_loadout.skill_ids` / `skill_resources` 和 `game_modes.json` 的 `resource_pools.skills`；新 ability tag、状态效果、叠加规则、目标类型或效果原语先登记词表，再扩展 SkillSystem / StatusEffectComponent，不按技能 id 写分支。
- 加状态宿主：可被状态影响的新实体应复用 `StatusEffectComponent`，实现 `apply_status_effect()`、owned ability tag 查询、`combat_team_id()` 和 JSON 友好快照；对象池实体必须在 `configure()` / 回收路径清空状态。
- 加敌人：优先改 `enemies.csv`、`enemy_ai_profiles.json`、`game_modes.json` 和 `spawn_waves.csv`；行为差异通过对玩家 AI profile 表达，不在 `enemy.gd` 按 id 分支。
- 加地图 / PCG 规则：优先改 `map_layouts.json`；运行时通过 `MapManager` 解释有限边界、手工摆点、PCG 和导演传入的通用兴趣点机关，不在 `GameplayRunLoop` 按 layout id 分支。
- 加 / 改战区导演：优先改 `warzone_directors.json`；固定节奏、巢变异主题、wave gating 和兴趣点都应由数据表达，兴趣点可通过 `MapManager` 变成初始地图机关，但仍不读取玩家状态、不做隐藏 DDA、不接运行时 LLM。
- 加模块（F13）：从 `client/templates/module_template.json` 创建独立 11×11 JSON，先登记为 `candidate`；通过 schema、通道、占格、可达性、安全区和内容预算校验后，由人工改为 `approved` 才可进入默认模板池。模块只能引用词表和数据中已登记的 primitive，详见 `docs/代码/module_world_manager.md`。
- 加机关：优先改 `hazards.csv`、`game_modes.json.resource_pools.hazards` 和 `map_layouts.json`；普通矩形范围机关复用 `Hazard`，新行为先设计通用 primitive，不按机关 id 写分支。
- 加刷怪：改 `spawn_waves.csv`；多个波次可复用当前时间窗 / 预算解释。
- 加升级候选：优先改 `growth_pools.json`；目标模式还必须在 `game_modes.json.resource_pools.growth_pools` 引用候选池，否则默认标准模式不会启用局内升级选择。新候选如果仍是 `stat_modifier` 不需要改逻辑，新增候选类型才需要扩展运行时解释和文档。
- 场景资源化：新增稳定 gameplay / UI 层级时优先新增 `.tscn`，脚本只做节点绑定、配置和 signal 编排；只有对象池工厂与数据驱动重复项可以在运行时创建节点，并要在模块文档说明原因。
- 扩展 run 快照：新增可恢复实体字段时先保证 JSON 友好，再更新本文档、SaveManager 文档、`runtime-smoke` 和 `save-smoke`；不要保存 `PoolManager` 内部队列或节点引用。
- 改普通新局 seed：只在 `FormalClientBoot` 的人工开始 / 重开入口生成新主 seed；不要在 `GameplayRunLoop` 内部、继续游戏、回放 runner 或 golden capture 路径隐式随机化。
- 扩展死亡后奖励：旧 `MetaProgressionSystem` 死亡结算已删除。若要新增死亡后奖励或局外资源来源，先写 ADR / 数据契约并接入当前 Gear Mod 或新的明确系统，不要恢复旧永久升级运行时。
- 扩展 GM 指令：先在 `GMCommandRegistry` 增命令，再在目标系统补受控 API；禁止在命令注册表里直接改 gameplay 私有字段、节点树或存档文件。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调玩家速度 / 生命 / 受伤无敌 / 中心排斥 | `player.json` / `characters.json` | `client/data/README.md` | `python tools/validate_data.py` |
| 调武器伤害 / 射速 / 弹速 | `weapons.json` | `client/data/README.md` | `validate_data` + headless |
| 改子弹墙体阻挡 / 穿墙 | `bullet.gd`、`module_chunk.gd`、`weapons.json` | 本文档、ModuleWorldManager 文档、GDD、词表、ADR | contracts + data/schema + `module-world-smoke` + technical slice + runtime/save/L1 + golden replay |
| 调技能伤害 / 半径 / 资源消耗 / 冷却 | `skills.json`、`characters.json` | `client/data/README.md`、`docs/代码/skill_system.md` | `validate_data` + `l1-smoke` + `runtime-smoke` |
| 改 Player / Enemy 状态宿主 | `player.gd`、`enemy.gd`、`status_effect_component.gd`、`l1_smoke.gd` | 本文档、状态组件文档、EnemyAI、GDD、测试策略 | `lint_gdscript_rules` + `lint_semantic_rules` + `l1-smoke` + `runtime-smoke` + `save-smoke` |
| 调敌人血量 / 速度 / 接触伤害 / 中心间距 / 占位色 | `enemies.csv` | `client/data/README.md` | `validate_data` + 手动跑一局 |
| 调敌人对玩家 AI | `enemy_ai_profiles.json`、`enemies.csv.ai_profile_id` | `client/data/README.md`、`docs/代码/enemy_ai.md` | `validate_data` + `runtime-smoke` + 必要时 golden replay |
| 调远程敌人投射物 | `enemy_ai_profiles.json` 的 `ranged_*` 字段、`enemy.gd`、`bullet.gd` | `client/data/README.md`、`docs/代码/enemy_ai.md` | `validate_data` + `runtime-smoke` + 必要时 golden replay |
| 调地图边界 / PCG 机关 / 手工摆点 | `map_layouts.json` | `client/data/README.md`、`docs/代码/map_manager.md` | `validate_data` + `runtime-smoke` + `f9-demo-smoke` |
| 调机关伤害 / 占格尺寸 / 冷却 | `hazards.csv` | `client/data/README.md`、`docs/代码/hazard_system.md` | `validate_data` + `f9-demo-smoke` |
| 调战区导演阶段 / 兴趣点 | `warzone_directors.json` | `client/data/README.md`、`docs/代码/warzone_director.md`、必要时 `docs/代码/map_manager.md` | `validate_data` + `test_data_loader_schema` + `runtime-smoke` + `f9-demo-smoke` |
| 调刷怪节奏 | `spawn_waves.csv` | `client/data/README.md` | `validate_data` + 手动 1 分钟 |
| 调升级阈值 / 候选 | `growth.csv` / `growth_pools.json` / `game_modes.json` | `client/data/README.md` | `validate_data` + 目标模式 smoke；默认模式应继续断言不弹升级面板 |
| 改 HUD 文案 | `strings.csv` | `client/locale/README.md` | `validate_data` |
| 改 HUD / 升级面板布局 | `client/scenes/gameplay/gameplay_hud.tscn`、`client/scenes/ui/level_up_panel.tscn`、对应脚本 | 本文档 | `runtime-smoke` + 手动不同窗口尺寸检查 |
| 改暂停 / 保存续局 | `client/scripts/ui/pause_menu.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`formal_client_boot.gd` | 本文档、SaveManager / FormalClientBoot 文档 | `runtime-smoke` + `save-smoke` + L5 暂停 / 存档 checklist |
| 改模块世界 / 模板 / 流式状态 | `module_worlds.json`、`module_templates.json`、`modules/*.json`、`module_world_manager.gd`、`module_chunk.gd`、`gameplay_run_loop.gd` | `client/data/README.md`、本文档、`docs/代码/module_world_manager.md` | `sync_contracts --check` + `validate_data` + `test_data_loader_schema` + `module-world-smoke` + `save-smoke` |
| 改普通新局 / 重开 seed | `client/scripts/autoload/rng.gd`、`client/scripts/boot/formal_client_boot.gd`、`client/tools/l1_smoke.gd` | 本文档、RNG / FormalClientBoot 文档、ADR、AI记忆 | `l1-smoke` + `runtime-smoke` + `save-smoke` + checked-in replay runner 抽查 |
| 改设置入口 / 设置叠层 | `title_menu.gd`、`pause_menu.gd`、`settings_panel.gd`、`formal_client_boot.gd`、`gameplay_run_loop.gd` | 本文档、Settings / UIManager / FormalClientBoot 文档 | `settings-smoke` + `runtime-smoke` |
| 改失败页 / 死亡清理 | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/ui/game_over_panel.gd` | 本文档、SaveManager 文档 | `runtime-smoke` + `save-smoke` |
| 改标题装备 Mod 入口 / 面板 | `client/scenes/ui/title_menu.tscn`、`client/scenes/ui/gear_mod_panel.tscn`、对应脚本、`client/scripts/boot/formal_client_boot.gd`、`client/scripts/autoload/gear_mod_system.gd` | 本文档、FormalClientBoot / GearModSystem 文档 | `headless-boot` + `gear-mod-smoke` + 手动标题菜单点开 |
| 改旧局外升级删除边界 | `client/scenes/ui/title_menu.tscn`、`client/scripts/ui/title_menu.gd`、`client/scripts/boot/formal_client_boot.gd`、`client/project.godot` | 本文档、FormalClientBoot / GearModSystem / SaveManager 文档 | `headless-boot` + `runtime-smoke` + `gear-mod-smoke` |
| 改 GM 指令影响运行时 | `client/scripts/debug/gm_command_registry.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、目标系统脚本 | 本文档、DebugTools 文档、测试策略 | `debug-tools-smoke` + `debug-tools-release-smoke`，必要时追加 `runtime-smoke` / `gear-mod-smoke` |
| 改运行时行为 | `client/scripts/gameplay/*.gd` | 本文档、必要时 GDD / ADR | L0 + L2 + `runtime-smoke`，必要时补 L1 |
| 改鼠标 / 手柄瞄准手感或俯视相机 / 地图显示参数 | `client/scripts/gameplay/player.gd`、`world_background.gd`、`weapon_system.gd`、`client/tools/runtime_smoke.gd` | 本文档、GDD、词表、测试策略 | `lint_gdscript_rules` + `lint_semantic_rules` + `runtime-smoke` + `replay-input-smoke` |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动没有进入 F4 | `DataLoader.validate_project_data()` 是否通过；`FormalClientBoot` 日志 |
| 场景化后节点找不到 | `.tscn` 中稳定节点名是否与脚本 `get_node_or_null()` 路径一致；按钮是否保留 `PROCESS_MODE_ALWAYS`；scene ext_resource 是否能被 Godot 解析 |
| 无法移动 | GUIDE / `InputService` autoload 顺序；gameplay context 是否启用；`move` action 资源和 remapping config 是否有效；播放 override 是否误残留 |
| 改键后旧键仍生效 | `Settings` 是否替换了对应 action 的 `InputEventKey`；`GameplayRunLoop._ensure_input_actions()` 不应再追加键盘默认事件 |
| 手柄输入消失 | `Settings` 是否误删了 `InputEventJoypadButton` / `InputEventJoypadMotion`；runtime 手柄兜底是否执行 |
| 移动感知不明显 | `WorldBackground` 是否挂载；网格是否随玩家附近重绘 |
| 不开火 | `starting_loadout.weapon_id` 是否存在；`fire_rate` 是否大于 0；子弹池是否注册 |
| 不刷怪 | `spawn_waves.csv` 时间窗、预算、`max_alive` 是否允许；敌人池是否注册；F12 标准局 7 分钟才打开 bulwark |
| 特定阶段不刷预期 wave | `warzone_directors.json.phases[].wave_ids` 是否包含该 wave；`debug_summary().warzone_director.phase_id` 是否符合当前时间；9 分钟后应处于软加压 `phase_overtime_collapse` |
| 战区兴趣点机关不出现 | `warzone_directors.json.interest_points[].map_layout_id` 是否匹配当前 layout；`hazard_ids[]` 是否非空且引用存在；`debug_summary().map.hazard_sources.director` 是否大于 0 |
| 兴趣点不领奖 | `claim_radius` 是否大于 0；`claim_start_time` 是否已到；无 `target_hp` 时玩家是否进入 `debug_summary().interest_points[point_id].position` 附近；若 `requires_interaction=true`，HUD 是否出现交互提示且玩家是否按了 `interact` action；有 `target_hp` 时目标是否被摧毁；奖励 id 是否通过 DataLoader schema |
| 小巢核领取后不出现结果面板 | `completes_run` 是否为 `true`；`target_hp` 目标是否被摧毁或已领取；撤离区是否激活；玩家是否站进撤离区并完成 `extraction_hold_time`；`GameOverPanel.configure(..., completed=true)` 是否在撤离成功后调用；当前 `run` 存档是否被删除；`pending_loot` 是否已提交 |
| 模块 assignment / hash 不稳定 | world seed、approved 模板池顺序、rotation 与固定锚点是否一致；是否绕过 `RNG.world`；`module-world-smoke` 是否通过 |
| 跨模块卡住 / 出界 | 相邻模块有效边缘通道是否匹配；外圈是否封闭；`ModuleChunk` 合并碰撞是否重建；`MapManager.bounds()` 与 99×99 格配置是否一致 |
| 返回模块重复刷怪 / 领奖 | 离开 3×3 邻域时是否把带 `module_slot` 的实体快照写入对应世界槽位；激活时是否区分 `initialized` 与 restore；奖励领取状态是否按槽位保存 |
| 玩家走出地图 | `MapManager.bounds()` 是否配置；`Player.set_movement_bounds()` 是否调用；`map_layouts.json.bounds` 是否是 grid 的整数倍 |
| 敌人走出地图 | `MapManager.bounds()` 是否配置；`GameplayRunLoop._apply_enemy_movement_bounds()` 是否在生成 / 续局恢复时调用；`Enemy.set_movement_bounds()` 是否在移动、分离和快照恢复后 clamp |
| 机关不出现 | `map_layouts.json` 是否生成 placement；`hazards.csv.pool_id` 是否已注册；`runtime-smoke` 是否通过 active hazards 断言 |
| FEA-12 不伤害玩家 | 玩家是否在机关矩形范围内；玩家无敌窗口是否清零；`hazards.csv.damage` / `damage_type` 是否有效；`f9-demo-smoke` 是否通过 |
| 机关续局后位置变化 | run payload 是否包含 `map.hazard_placements` 与 `hazards`；恢复是否误重新消耗 `RNG.world` |
| 普通新局 seed 总是一样 / replay 变随机 | 普通开始 / 重开是否走 `FormalClientBoot._start_new_gameplay_run()`；继续、replay runner、golden capture 和 smoke 是否仍走恢复 / 固定 seed 路径 |
| 第二敌人不出现 | `enemies.csv.pool_id` 是否为已注册池；`game_modes.json.resource_pools.enemies` 与 `spawn_waves.csv.enemy_id` 是否引用该敌人；`runtime-smoke` 是否通过第二敌人池断言 |
| 敌人错误锁定或伤害其他敌人 | `_sense_context()` 是否只构造玩家候选；`Enemy.receive_damage()` 是否仍拒绝 `team_enemy` 来源；runtime smoke 的玩家目标、友伤和中心分离断言是否通过 |
| 敌人中心完全重叠 | `enemies.csv.separation_radius` 是否为 0；`runtime-smoke` 是否通过中心分离断言 |
| 敌人中心贴到玩家中心 | `player.json.base_stats.player_separation_radius` 是否为 0；`Enemy` 是否仍调用玩家中心排斥；`runtime-smoke` 是否通过玩家-敌人分离断言 |
| 子弹打不到 | `hit_radius`、敌人位置、`bullet_range` / `lifetime` 是否合理 |
| 子弹穿墙或在墙前异常消失 | `ModuleChunk.TerrainCollision` 是否显式位于 bit 1；Bullet 查询 mask / 圆形半径 / 首帧重叠 / `cast_motion()` 是否正常；快照 `wall_pierce_enabled` 是否符合发射时能力；不要把 `pierce_count` 当穿墙开关 |
| 同一敌人贴住玩家不再造成后续伤害 | 玩家 `damage_invulnerability_duration` 是否过长；`Enemy` 不应保存单只敌人的接触伤害冷却 |
| 默认模式不掉经验 / 不升级 | ADR #120 后这是预期行为；标准模式没有 `growth_pools` 时不会生成经验球或弹升级面板 |
| 非默认成长模式不掉经验 / 不升级 | 目标模式是否在 `game_modes.json.resource_pools.growth_pools` 引用升级池；`enemies.csv.exp_reward` 是否大于 0；`pickup_orb` 池是否注册；`growth.csv` 下一级阈值是否达到 |
| 升级面板不出现或无法选择 | `GameState` 是否进入 `LEVEL_UP`；`UIManager.top()` 是否为 `LevelUpPanel`；`growth_pools.json` 是否有满足 `min_level` 的候选 |
| 升级界面按暂停键无反应 | `LevelUpPanel.pause_requested` 是否连接到 `GameplayRunLoop._on_level_up_pause_requested()`；升级面板是否是 `UIManager.top()`；`pause` action 是否已注册 |
| 游戏结束后计时继续 | `GameClock` 是否把 `GAME_OVER` 视为冻结状态；`runtime-smoke` 是否通过冻结断言 |
| 死亡后仍带回战利品 | `GameplayRunLoop._on_player_died()` 是否只清理 `run`、显示丢失清单且没有调用 `_commit_pending_loot()`；`GearModSystem` inventory / resources 是否未增长；`GameOverPanel` 是否显示 `ui_result_lost_header` 而不是成功带回标题 |
| 死亡后还能继续旧局 | `SaveManager.delete(slot_0, run)` 是否在死亡后执行；标题继续按钮是否仍看见旧 `run` |
| 标题装备 Mod 面板打不开 | `TitleMenu` 是否有 `GearModButton`；`gear_mod_requested` 是否被 `FormalClientBoot` 连接；`ui_gear_mod_title_entry` 是否已导入 `.translation` |
| Gear Mod 面板按钮没有生效 | `GearModPanel` 是否调用 `GearModSystem` API；`gear-mod-smoke` 是否通过面板按钮流；当前槽位是否有对应 slot 的 Mod |
| 标题菜单仍出现旧局外升级 | `TitleMenu` 是否意外恢复 `MetaProgressionButton` / `MetaProfileSummaryLabel`；`FormalClientBoot` 是否意外恢复 `meta_progression_requested` 连接 |
| 失败面板出现局外成长购买或跳转入口 | `GameOverPanel` 是否意外恢复 `PurchaseUpgradeButton` / `MetaProgressionButton`；`runtime-smoke` 是否通过失败页不显示局外成长入口断言 |
| 下一局 Gear Mod 属性无效 | `GearModSystem.current_modifiers(slot)` 是否输出目标 stat；开局是否在玩家 / 武器 configure 后应用对应 slot modifiers |
| 失败后无法重开 / 回标题 | 是否处于 `GameState.GAME_OVER`；`GameOverPanel` 是否挂到 `UIManager`；`restart_requested` / `quit_to_title_requested` 是否被 `FormalClientBoot` 连接 |
| 暂停菜单打不开或不冻结 | `pause` action 是否已注册；`PauseMenu.pauses_game` 是否为 true；`UIManager` 是否切到 `GameState.PAUSED` |
| 详细数值面板不显示或导致暂停 | `show_stats_panel` 是否在 gameplay context 有效；`GameplayRunLoop._update_stats_panel()` 是否只在 `PLAYING` 下显示 HUD 叠层；不应调用 `UIManager.push()` 或改变 `GameState` |
| 暂停菜单打开设置后关不掉 | `SettingsPanel` 是否是栈顶；`SettingsPanel.request_close()` 是否复用关闭按钮路径；`runtime-smoke` 是否通过暂停设置入口断言 |
| 手柄 / 键盘返回键不生效 | `InputService` 的 ui context、安全兜底和 UI bridge 是否有效；栈顶 UI 是否实现 `request_close()`；不应依赖 `UIManager` 盲目出栈 |
| 手柄导航时新打开 UI 没有焦点 | 最近是否有手柄输入；UI 是否有可聚焦控件；复杂面板是否实现 `grab_default_focus()`；`runtime-smoke` 是否覆盖鼠标无焦点和手柄补焦点 |
| 保存后标题没有继续游戏 | `SaveManager.has_save(slot_0, run)` 是否为 true；旧存档是否因 hash mismatch 被隔离 |
| 继续坏档后没有提示 | `TitleMenu` 是否存在 `RunSaveNoticeLabel`；`ui_run_save_unavailable` 是否在 `strings.csv` 与 `.translation` 中；`runtime-smoke` 是否通过坏 run 存档点击继续断言 |
| 继续游戏后状态不对 | run payload 是否包含地图 / 机关 / 玩家 / 武器 / 敌人 / 子弹 / 经验球 / RNG / GameClock / `ui_restore`；恢复时是否通过 `PoolManager.acquire()` 重建实体；暂停和升级选择是否经由 `UIManager` 恢复 |
| 继续游戏后状态效果丢失 | 玩家 / 敌人 / 技能快照是否包含 `status_effects` 与 `owned_tag_counts`；恢复已有 tag 计数时是否避免状态组件重复授予 tags |
| 池化敌人带着上一只怪的状态 | `Enemy.configure()`、`_pool_release()`、`_pool_reset()` 是否调用状态清理；L1 是否覆盖 configure 复用后旧状态被清空 |
| GM 命令没有生效 | 当前是否为 debug/dev_tools 构建；`DebugConsole` 是否存在；命令是否通过 `GameplayRunLoop.debug_*` / `GearModSystem.debug_*` 受控 API，而不是直接改节点 |

## 测试义务

- Gameplay runtime 代码改动必跑：`python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`。
- Gameplay runtime / UI 场景结构改动还必须跑 `python tools/godot_bridge.py --project client runtime-smoke`，涉及标题 Gear Mod 面板时追加 `gear-mod-smoke`。
- 涉及启动、输入、WeaponSystem、SkillSystem、子弹、敌人、EnemyAI、Spawner、经验球、升级选择、Combat 或失败状态时追加 `python tools/godot_bridge.py --project client runtime-smoke`。
- 涉及有限地图、`map_layouts.json`、PCG 摆放、WarzoneDirector 兴趣点接入、手工机关摆点、HazardSystem 或 `hazards.csv` 时追加 `python tools/godot_bridge.py --project client runtime-smoke`、`python tools/godot_bridge.py --project client f9-demo-smoke`；涉及兴趣点奖励、`GearModSystem` 资源 / Mod 发放或完成面板时追加 `gear-mod-smoke` 与 `save-smoke`；涉及 run 快照恢复时追加 `save-smoke`。
- 涉及技能目标、资源、冷却、效果解释或 run 技能快照时追加 `python tools/godot_bridge.py --project client l1-smoke`；改 run 快照恢复还要追加 `save-smoke`。
- 涉及 Player / Enemy 状态宿主、owned ability tag 或实体状态快照时追加 `python tools/godot_bridge.py --project client l1-smoke`、`python tools/godot_bridge.py --project client runtime-smoke` 与 `python tools/godot_bridge.py --project client save-smoke`；对象池状态清理变化还要检查复用路径。
- 涉及 gameplay 输入录制、`Replay` 输入事件、升级选择 decision、暂停 / 返回 action 录制时追加 `python tools/godot_bridge.py --project client replay-input-smoke`；涉及非默认模式升级选择 replay 基线时追加对应 capture / replay-runner，默认标准模式应继续断言不进入 `LEVEL_UP`。
- 涉及暂停、保存退出、标题继续、坏档提示、RNG / GameClock 快照或 run payload 时必须追加 `python tools/godot_bridge.py --project client runtime-smoke` 与 `python tools/godot_bridge.py --project client save-smoke`，并做至少一次手动保存续局检查。
- 涉及普通新局 / 重开 seed 策略时，追加 `python tools/godot_bridge.py --project client l1-smoke`、`runtime-smoke`、`save-smoke` 和至少一条 checked-in replay runner，确认玩家入口随机化但工具 / replay 固定 seed 路径不漂移。
- 涉及标题 / 暂停设置入口、设置面板关闭、`ui_back` 返回或运行时语言刷新时，追加 `python tools/godot_bridge.py --project client settings-smoke` 与 `python tools/godot_bridge.py --project client runtime-smoke`。
- 涉及 `meta.gear_mods` 存档结构、Gear Mod loadout、掉落、升级、分解或下一局 modifier snapshot 时追加 `python tools/godot_bridge.py --project client gear-mod-smoke`；如果改了 F4 死亡接入、敌人击杀归因或失败面板，同时跑 `runtime-smoke`。
- 涉及 GM 指令或 runtime debug API 时，追加 `python tools/godot_bridge.py --project client debug-tools-smoke` 与 `python tools/godot_bridge.py --project client debug-tools-release-smoke`；命令影响局内战斗时追加 `runtime-smoke`。
- 涉及模块世界、模板 JSON、边缘契约、chunk 流式状态、迷雾、地图 hash、run v4 或 v3 重置流程时，追加 `python tools/godot_bridge.py --project client module-world-smoke` 与 `python tools/godot_bridge.py --project client save-smoke`，并跑 `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`；详见 `docs/代码/module_world_manager.md`。
- 涉及子弹地形阻挡、`wall_pierce` 或子弹能力快照时，必须跑完整与技术切片 `module-world-smoke`、`runtime-smoke`、`save-smoke`、`l1-smoke`、正式 headless boot 和四条黄金回放；契约或武器字段变化追加双端 schema 与契约同步。
- 数据 / locale 变化还要跑 `python tools/validate_data.py`、`python tools/lint_project_rules.py`。
- 地图 / 机关数量、对象池生命周期或性能相关变化仍按对应功能 smoke 验证；影响稳定运行时摘要时重跑 checked-in golden replay runner。`startup-probe` / `perf-probe` 只有用户当次明确要求性能测试时才追加。
- 当前没有 GUT runner，F4 首切片用 L0 + L2 + `runtime-smoke` + 手动 1 分钟跑通作为阶段门槛；后续接入 Godot 测试时补 Player / Combat / Pool / Spawner 的 L1。

## 迁移 / 兼容

F5 已开始写 `SaveManager` 的 `run` kind，F11 的 `meta` profile 继续由 `GearModSystem` 管理 `gear_mods` 子 payload。F13 模块世界将 gameplay payload 与 run envelope 升为 v4；默认 run 必须带 `module_world` 块并在恢复时校验 map hash。ADR #149 为子弹快照增加可选 `wall_pierce_enabled`，旧字段缺失按 `false` 恢复，因此 run 继续保持 v4。旧 v3 run 不做有损猜测迁移：读取后标记 `legacy_run_incompatible`，启动入口显示提示、删除该 run 并要求新开；`meta` kind 版本、Gear Mod 资产与 loadout 保持不变。死亡仍删除 run 并丢失 `pending_loot`；撤离成功先结算暂存战利品再删除 run。后续扩展模块 primitive、地图事件或局外奖励时，需要分别判断 run / meta schema 是否升级并补迁移与 roundtrip；不得保存对象池内部状态或节点引用。

## 相关文档

- `docs/AI协作/工作包/F4-MinPlayableLoop.md`
- `docs/AI协作/工作包/F13-ModularGridWorld.md`
- `docs/正式项目工作规划.md` F4
- `docs/代码/phantom_camera.md`
- `docs/代码/debug_tools.md`
- `docs/游戏设计文档.md` §3 / §4 / §5.3 / §9.13 / §9.15.1
- `docs/代码/combat.md`
- `docs/代码/map_manager.md`
- `docs/代码/module_world_manager.md`
- `docs/代码/hazard_system.md`
- `docs/代码/skill_system.md`
- `docs/代码/gear_mod_system.md`
