# Gameplay Runtime 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式客户端 gameplay runtime 的聚合模块契约；拆分 Player、WeaponSystem、Enemy、Spawner、HUD 等长期模块或改变公共行为时必须同步本文档、AI 导航、代码索引和相关阶段工作包。
> 玩家相机的项目适配行为归本文档；Phantom Camera vendored 内部架构、公共 API、编辑器工具和升级补丁归 `docs/代码/phantom_camera.md`。
> gameplay 的输入消费行为归本文档；GUIDE 插件内部归 `docs/代码/guide.md`，action / context / 重绑定 / 回放输入边界归 `docs/代码/input_service.md`。

## 职责

- 在正式 `client/` 内编排标题 → 主／子英雄组合选择 → Loading → 对局，以及继续、暂停保存退出、重开和回标题。对局包含主英雄场景 / 属性 / 被动 / 技能 1/2、子英雄强调色 / 技能 3/4、起始武器、四技能共享能量、基础冲刺、七元素、防御层、武器弹药 / 换弹 / 后坐、敌人击退、池化实体、生成时金币奖励、弹药掉落、金币成长、显式奖励选择、敌人显式攻击、F13 模块世界、五类世界事件、模式级威胁时间、难度标记器与 Run v11 恢复。
- ADR #157 后为正式玩家入口提供“准备完成、尚未激活”的边界：资源读取和分帧构建期间保持 `LOADING`，加载界面移除后才进入 `PLAYING` 并恢复保存的 UI；headless / replay / smoke 工具继续走同步准备。
- 复用 F3/F9/F10 已建立的数据边界，并由 F13 增加 `module_worlds.json`、`module_templates.json` 与 `modules/*.json`；模块世界只引用既有敌人、机关、奖励、目标和撤离 primitive，不在运行时调用 AI。
- ADR #161 已提供冷静 / 愤怒两名英雄与正式组合选择，固定四技能、共享能量、技能 / 冲刺 HUD、状态汇总、能力 / 防御详细面板和 Meta v2 / Replay v3；ADR #166 将 Run 提升到 v6，并加入独立威胁时间、敌人出生倍率和难度标记器。本期明确不实现局内换子英雄、同英雄开局、第三基础元素内容、超量护盾局外来源、N×N 组合场景、敌人组合升级或遭遇预算扩张。F11 Gear Mod 仍是下一局属性来源；F12 的兴趣点、暂存战利品、小巢核与撤离结算继续运行在 F13 模块世界内。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 改运行时启动 / 重开 | `client/scripts/gameplay/gameplay_run_loop.gd` |
| 改玩家加载准备 / 激活边界 | `docs/代码/gameplay_loading.md`、`client/scripts/boot/formal_client_boot.gd`、`client/scripts/gameplay/gameplay_run_loop.gd` |
| 改模块大地图 / 模块模板 / 流式加载 | `docs/代码/module_world_manager.md`、`client/scripts/gameplay/module_world_manager.gd`、`client/scripts/gameplay/module_chunk.gd`、`client/data/module_worlds.json`、`client/data/module_templates.json`、`client/data/modules/*.json` |
| 改标题 / 失败面板 | `client/scripts/ui/title_menu.gd`、`client/scripts/ui/game_over_panel.gd` |
| 改标题装备 Mod 面板 | `client/scripts/ui/gear_mod_panel.gd`、`client/scripts/autoload/gear_mod_system.gd`、`client/scripts/boot/formal_client_boot.gd` |
| 改武器弹药 / 换弹 / 后坐 / 扩散 / 玩家反冲 | `client/scripts/gameplay/weapon_system.gd`、`client/scripts/data/weapon_recoil_resolver.gd`、`client/scripts/gameplay/player.gd`、`client/data/weapons.json`、`client/data/ammo_rules.json` |
| 改暂停 / 保存退出 | `client/scripts/ui/pause_menu.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`docs/代码/save_manager.md` |
| 改失败面板 / run 清理 | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/ui/game_over_panel.gd` |
| 改玩家移动 / 相机 | `client/scripts/gameplay/player.gd`、`client/scripts/gameplay/gameplay_camera_controller.gd`、`client/data/camera_feedback.json` |
| 改按住开火 / 子弹生成 | `client/scripts/gameplay/weapon_system.gd`、`bullet.gd` |
| 改子弹墙体阻挡 / 穿墙能力 | `client/scripts/gameplay/bullet.gd`、`client/scripts/gameplay/module_chunk.gd`、`client/data/weapons.json`、`docs/代码/module_world_manager.md` |
| 改主动技能释放 / 资源消耗 | `docs/代码/skill_system.md`、`client/scripts/gameplay/skill_system.gd`、`client/data/skills.json` |
| 改敌人对玩家 AI / 显式攻击 / 连锁爆炸 | `docs/代码/enemy_ai.md`、`client/scripts/gameplay/enemy.gd`、`enemy_ai_profiles.json` |
| 改有限地图 / PCG / 人工摆点 | `docs/代码/map_manager.md`、`client/scripts/gameplay/map_manager.gd`、`client/data/map_layouts.json` |
| 改机关运行时 / FEA-12 | `docs/代码/hazard_system.md`、`client/scripts/gameplay/hazard.gd`、`client/data/hazards.csv` |
| 改战区导演 / 阶段主题 / 兴趣点 | `docs/代码/warzone_director.md`、`client/scripts/gameplay/warzone_director.gd`、`client/data/warzone_directors.json` |
| 改难度 profile / 威胁时间 / 敌人出生倍率 | `docs/代码/difficulty_progression.md`、`client/scripts/data/difficulty_progression.gd`、`client/data/difficulty_profiles.json`、`client/data/game_modes.json` |
| 改敌人金币公式 / 价值倍率 / 出生奖励快照 | `docs/代码/enemy_reward_resolver.md`、`client/scripts/data/enemy_reward_resolver.gd`、`client/data/enemy_rewards.json`、`client/data/enemies.csv` |
| 改金币球 / 弹药弹匣 / 拾取 | `client/scripts/gameplay/gold_orb.gd`、`client/scripts/gameplay/ammo_magazine_pickup.gd`、`player.json.gold_drop`、`ammo_rules.json` |
| 改金币等级曲线 / 通用奖励 | `level_progression.json`、`reward_choice_pools.json`、`GoldProgression`、`RewardChoiceController`、`GameplayRunLoop`；调用方显式请求 2–5 个候选，等级提升不自动触发 |
| 改 HUD 文案 / 详细数值面板 | `client/scripts/gameplay/gameplay_hud.gd`、`client/scenes/gameplay/gameplay_hud.tscn`、`client/locale/strings.csv` |
| 改稳定节点结构 / UI 层级 | `client/scenes/gameplay/*.tscn`、`client/scenes/ui/*.tscn` |
| 改 GM 指令影响局内状态 | `docs/代码/debug_tools.md`、`client/scripts/debug/gm_command_registry.gd`、`client/scripts/gameplay/gameplay_run_loop.gd` |
| 改开发者测试岛 | `docs/代码/debug_test_arena.md`、`client/scenes/debug/`、`client/scripts/debug/debug_test_arena_*.gd`、`client/scripts/gameplay/gameplay_run_loop.gd` |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/boot/formal_client_boot.gd` | 数据校验通过后挂载 gameplay runtime |
| `client/scenes/gameplay/gameplay_run_loop.tscn` | 正式 gameplay runtime 场景；包含 `ActiveWorld`、`WorldBackground`、`PlayerHost` 和 `GameplayHud`；玩家由角色数据在入树前选择并挂到 host |
| `client/scenes/gameplay/actors/player_base.tscn` / `characters/*.tscn` | 玩家基础场景与角色专属继承场景；基础场景提供脚本、碰撞、武器、状态组件和角色头顶短时世界文字节点，专属场景保存角色静态外观和节点覆盖；对局级相机 Rig 固定在 RunLoop |
| `client/scenes/ui/loading_screen.tscn` / `client/scripts/ui/loading_screen.gd` | 正式玩家入口准备期间的全屏加载界面 |
| `client/tools/loading_smoke.gd` | 开始、继续、重开、重入与准备失败的真实玩家入口回归 |
| `client/scenes/gameplay/actors/enemy_base.tscn` / `enemies/*.tscn` | 敌人基础场景与五种敌人专属继承场景；共享 `Enemy` 脚本和必需组件，专属场景保存颜色、轮廓及未来动画 / 素材节点 |
| `client/scenes/gameplay/gameplay_camera_controller.tscn` / `client/scripts/gameplay/gameplay_camera_controller.gd` | 稳定摄像机场景与类型化门面；管理 `Camera2D` + Phantom Camera host / player PCam / 瞄准引导偏移 / 受伤与武器两个 noise emitter，读 `camera_feedback.json`、按输入源平滑预看、按 context 缩放武器震屏并响应 `gameplay.screen_shake` |
| `client/scripts/data/weapon_recoil_resolver.gd` | 纯数据解析 `recoil_model` 与武器运行时 stats，输出有效后坐、完整扩散锥角、后移距离 / 初速度及持续时间 |
| `client/scenes/gameplay/bullet.tscn` / `gold_orb.tscn` / `hit_spark.tscn` / `damage_number.tscn` / `hazard.tscn` | 其他对象池实体场景；由 `PoolManager` 工厂实例化并复用。共享 Bullet 场景同时保存玩家黄弹 / 拖尾与敌方红弹 / 拖尾，运行时按 `source_team` 切换并在池复用时完整重置；其他静态占位表现同样由可编辑 `Polygon2D` / `Line2D` 子节点承载，不走实体 `_draw()` |
| `client/scenes/gameplay/interest_point_target.tscn` / `client/scripts/gameplay/interest_point_target.gd` | F12 低频兴趣点目标：精英巢点和小巢核可伤害占位；视觉 footprint 对齐地图矩形格，摧毁后通过 signal 触发通用兴趣点奖励 |
| `client/scenes/gameplay/interest_point_cache.tscn` / `client/scripts/gameplay/interest_point_cache.gd` | F12 低频缓存箱：资源缓存 / Mod 缓存可见交互占位；矩形 footprint 对齐地图矩形格，主体是低矮俯视箱体，功能色只作为小嵌片，渲染在地图背景之上、机关 / 敌人 / 玩家之下，打开后保留已开启状态 |
| `client/scenes/ui/title_menu.tscn` / `gear_mod_panel.tscn` / `pause_menu.tscn` / `settings_panel.tscn` / `game_over_panel.tscn` / `reward_choice_panel.tscn` | 正式 UI 场景；脚本只绑定稳定节点、连接 signal 和刷新数据 |
| `client/scenes/ui/stats_row.tscn` / `reward_choice_button.tscn` / `gear_mod_row.tscn` / `gear_mod_empty_row.tscn` / `input_binding_row.tscn` | 数据驱动重复 UI 的可编辑行模板；运行时允许实例化模板并填入文本 / signal，不允许逐个 `Label.new()` / `Button.new()` 拼装长期行结构 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 正式运行时编排、输入 action 手柄兜底注册、对象池注册、刷怪和重开 |
| `client/scripts/data/difficulty_progression.gd` | 模式级威胁时间、难度系数、90 秒阶段、敌人出生倍率和 Run v11 快照；由 RunLoop 决定每帧是否推进 |
| `client/scripts/data/enemy_reward_resolver.gd` | 纯计算敌人生成时金币及完整明细；不读取随机、时间或节点 |
| `client/scenes/debug/debug_test_arena_run.tscn` / `client/scripts/debug/debug_test_arena_controller.gd` | ADR #159 / #160 独立测试岛内部 RunLoop：复用正式战斗系统的场景化训练岛、控制器与只读伤害统计 |
| `client/scripts/gameplay/module_world_manager.gd` | F13 模块世界协调器：组合 81 槽、三种限量事件模板、地图 hash / 迷雾 / 动态状态，并激活玩家 3×3 邻域及最多三个固定模块 |
| `client/scenes/gameplay/module_chunk.tscn` / `client/scripts/gameplay/module_chunk.gd` | 12 个预置复用槽位共用的薄场景；挂载缓存生成场景，不从 JSON 建 TileMap、逐格建 Node 或重算碰撞 |
| `client/scenes/gameplay/module_world_manager.tscn` | 预置 12 个 `ModuleChunk`：九个邻域容量与三个世界事件固定容量 |
| `client/scripts/gameplay/module_minimap.gd` | HUD 9×9 模块级迷雾、当前位置、目标与撤离方向标记 |
| `client/tools/module_world_smoke.gd` | 覆盖 seed assignment/hash、三种不同事件、12 chunk / 三 pin、无缝流式、起点门禁、敌人倍率、目标撤离及 Run v11 恢复 |
| `client/scripts/gameplay/world_events/` / `client/scenes/gameplay/world_events/` | 五类事件的场景化 Controller、交互物、防御目标与占点表现；详见 `docs/代码/world_event_system.md` |
| `client/scripts/gameplay/world_background.gd` | 量化矩形地图格背景；读取 `MapManager.grid_cell_size()`，让背景格、机关绘制和触发判定共享同一份地图度量，不改变世界坐标或相机缩放 |
| `client/scripts/gameplay/map_manager.gd` | 有限地图边界、PCG 机关摆放、人工摆点、刷怪位置 clamp 和地图快照 |
| `client/scripts/gameplay/player.gd` / `player_world_prompt.gd` | 玩家移动、瞄准、冲刺、主英雄属性、超量护盾 / 普通护盾 / 护盾门 / 护甲 / 生命防御链、临时修饰器、受控 debug 资源 API，以及跟随角色并按 `GameClock` 消退的短时世界文字 |
| `client/scripts/gameplay/warzone_director.gd` | F10 敌巢战区导演，解释固定阶段、巢变异主题、兴趣点和阶段启用 wave |
| `client/scripts/gameplay/weapon_system.gd` | 起始武器按住开火、临时武器修正、子弹池获取，以及打空时单次发出的 `ammo_attention_requested` 反馈请求 |
| `client/scenes/gameplay/skill_system.tscn` / `client/scripts/gameplay/skill_system.gd` | 预置 `StatusEffectComponent` 的四槽技能系统；负责槽位快照、共享能量、能力四维缩放、通用效果 / 状态 / 修饰器、屏障、combat gate 和 Run v11 恢复 |
| `client/scripts/gameplay/bullet.gd` | 子弹飞行、圆形地形重叠 / 扫掠、射程 / 生命周期裁剪、敌人和兴趣点目标命中、敌弹跨屏障圆周判定、墙体穿透与首帧开火位置快照，以及按队伍选择且池化时严格清空的玩家 / 敌方 Shader RibbonTrail |
| `client/scripts/gameplay/enemy.gd` | 数据驱动敌人 AI、事件主目标 / 玩家附带受击、显式攻击 / 连锁、友伤护栏、出生倍率、锁定金币、退场语义和 Run v11 快照 |
| `client/scripts/gameplay/hazard.gd` | 通用机关节点：矩形范围触发、冷却、占位表现、`Combat` 伤害和快照 |
| `client/scripts/gameplay/gold_progression.gd` | 场景预置金币账本：余额、累计量、整数等级曲线、交易校验与 64 位溢出保护 |
| `client/scripts/gameplay/gold_orb.gd` | 池化金币球：进入玩家拾取范围后按 `gold_drop.pickup_speed` 吸附并发放金币 |
| `client/scripts/gameplay/reward_choice_controller.gd` | 场景预置通用奖励控制器：验证请求、按等级过滤、稳定加权无放回抽取、保存 / 恢复原候选 |
| `client/scripts/gameplay/hit_spark.gd` / `damage_number.gd` | 池化命中反馈：Combat 成功造成伤害时生成短命火花和飘字；不进入 run 快照 |
| `client/scripts/gameplay/presentation/` | `ActorPresentationController`、`VfxHost` 与 `GameplayFeedbackController`；完整契约见 `docs/代码/visual_effects.md` |
| `client/scripts/gameplay/reward_choice_panel.gd` | 响应式通用奖励选择面板；支持 2–5 项，通过 `UIManager.push()` 挂载；语言切换时用缓存候选重建按钮 |
| `client/scripts/gameplay/gameplay_hud.gd` / `client/scripts/ui/difficulty_marker.gd` | 响应式 HUD：生命、普通 / 超量护盾、能量、四技能、冲刺、当前战区状态、击杀、威胁时间 / 等级 / 阶段 / 分段进度、起点锁定、撤离反馈与能力 / 防御 / 新敌人倍率详细属性；语言切换时用当前状态重画 |
| `client/scripts/ui/title_menu.gd` | 最小标题界面：开始 / 继续 / 装备 Mod / 设置 / 退出 |
| `client/scripts/ui/settings_panel.gd` | F7 设置面板：从标题或暂停菜单打开，读写 `Settings` 并响应语言切换 |
| `client/scripts/ui/gear_mod_panel.gd` | F11 装备 Mod 面板：从标题菜单打开，切换英雄 / 武器 loadout，显示资源、容量、Mod 列表、详情和操作反馈 |
| `client/scripts/ui/pause_menu.gd` | F5 / F7 暂停菜单：继续、设置、保存并退出、重新开始、回标题；语言切换时刷新按钮 |
| `client/scripts/ui/game_over_panel.gd` | 失败 / 完成结果面板：本局摘要、暂存战利品带回或丢失提示、重开 / 回标题；语言切换时用缓存状态重画 |
| `client/tools/runtime_smoke.gd` | gameplay runtime headless smoke，覆盖启动、输入、池化、伤害、失败状态和真实死亡结算 |
| `client/tools/debug_tools_smoke.gd` | DebugTools headless smoke，覆盖 GM 命令调用 runtime debug API 和 release guard |
| `client/tools/debug_test_arena_smoke.gd` | 开发者测试岛隔离 smoke，覆盖配装、固定靶 / AI、作弊、死亡复位、DPS、存档与 Replay / Analytics 边界 |
| `client/tools/gear_mod_smoke.gd` | F11 Gear Mod smoke，覆盖 profile、授予、装备、容量、升级、分解、掉落、HUD 暂存提示和 Gear Mod 面板按钮流 |
| `client/tools/save_manager_smoke.gd` | F5 SaveManager run 存档可靠性 smoke，覆盖 roundtrip、备份回退、坏档隔离和迁移 |
| `client/tools/perf_probe.gd` | F8 轻量 perf / 平衡采样入口，输出 schema v2 可比较 JSON：warmup 后帧时间分布、实体峰值、池峰值、等级、击杀和预算状态 |
| `client/tools/golden_replay_capture.gd` | F8 golden replay capture 工具，固定 seed 启动真实 `GameplayRunLoop` 并采样运行时摘要；支持 basic、pause/resume、full-death 和 reward-choice 场景 |
| `client/tools/replay_input_smoke.gd` | F8 gameplay 输入录制 smoke，确认移动 / 瞄准 / pause / ui_back 写入 Replay 输入事件 |
| `tools/godot_bridge.py` | `module-world-smoke` / `module-world-technical-slice-smoke` / `runtime-smoke` / `save-smoke` / `settings-smoke` / `gear-mod-smoke` / `debug-tools-smoke` / `debug-test-arena-smoke` / `debug-tools-release-smoke` / F8 `l1-smoke`、`replay-smoke`、`replay-runner`、`replay-input-smoke`、`capture-golden-replay` 命令入口；`startup-probe` / `perf-probe` 保留为用户明确触发的按需入口 |
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
    │   ├── PlayerHost (Node2D)
    │   │   └── Player (character-specific inherited CharacterBody2D)
    │   │       ├── CollisionShape2D (CircleShape2D; blocked module-cell collision)
    │   │       ├── WeaponSystem (Node)
    │   │       └── StatusEffectComponent (Node)
    │   ├── GameplayCameraController (Node2D; run-level rig)
    │   │   ├── CenteredCamera (Camera2D; current, level, uniform scale)
    │   │   │   └── PhantomCameraHost (Node)
    │   │   ├── PlayerCamera (PhantomCamera2D; GLUED follow current Player)
    │   │   ├── PlayerDamageShake (PhantomCameraNoiseEmitter2D)
    │   │   └── WeaponRecoilShake (PhantomCameraNoiseEmitter2D)
    │   ├── hazard_spike_* (pooled Hazard scene, active only)
    │   ├── InterestPointTarget_* (low-frequency POI target, active only)
    │   ├── InterestPointCache_* (low-frequency POI cache, active only)
    │   ├── bullet_basic_* (pooled Bullet scene, active only)
    │   └── enemy_* (per-enemy pooled inherited CharacterBody2D scenes, active only)
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
    ├── RewardChoicePanel (only while GameState.REWARD_CHOICE)
    └── GameOverPanel (only while GameState.GAME_OVER)
```

闲置子弹、敌人、机关和金币球节点归 `PoolManager` autoload 管理。

### Carrier 概念（F13）

`GameplayRunLoop` 的地图 carrier 现在分为两条明确路径：

- **module-world** 是 `mode_standard_survival` 默认载体：世界固定 9×9 模块、每模块 11×11 格；`ModuleWorldManager` 按 seed 组合 approved 模板，只激活玩家周围 3×3，并保存离开邻域的槽位动态状态。
- **open-warzone** 仅由 `--open-warzone` 或测试 debug API 显式启用，保留 F12 `MapManager` / `WarzoneDirector` 对照回归；模块模式不会运行旧 PCG / director 摆点。
- carrier 只决定地图载体与内容入口；对象池生成、`Combat`、击杀归因和战利品提交仍由 `GameplayRunLoop` 负责，`ModuleWorldManager` 不直接绕过统一 autoload。
- 线性房间 carrier 已由 ADR #142 取代并删除；旧 run v3 会明确重置，不尝试迁移其房间进度。

ADR #159 另有一个非 carrier、非 game mode 的内部运行用途 `DEBUG_TEST_ARENA`。它只允许节点入树前配置，使用测试岛场景提供的矩形边界和出生点，关闭 module-world / open-warzone、Spawner、WarzoneDirector、兴趣点、撤离、成长、奖励、普通 Game Over 与 run snapshot；Player、Weapon、Skill、Enemy、Combat、Pool、VFX 和 Gear Mod modifier 仍走正式实现。详细边界见 `docs/代码/debug_test_arena.md`。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | `FormalClientBoot` 跑数据 schema smoke，正常启动显示 `TitleMenu`；标题菜单可打开 `GearModPanel` 配置英雄 / 武器 Mod，也可打开 `SettingsPanel` 修改设置；旧局外升级入口和面板已删除；`--runtime-smoke` 模式跳过标题并直接创建 `GameplayRunLoop` | `DataLoader.validate_project_data()`、`UIManager.push()` |
| 开发者测试岛 | 直接运行独立 `debug_test_arena.tscn`，由 host 先显示配装，再在 runtime 入树前切内部用途，应用纯 Gear Mod preview modifiers，关闭正式世界 / 成长 / 结算并默认打开暂停控制面板。死亡只复位场地与玩家；返回配装 / 退出由独立 host 重建或清理 | `configure_debug_test_arena()`、`debug_test_arena_*()`、`debug_test_arena_setup_requested`、`debug_test_arena_exit_requested` |
| 开局准备 / 激活 | 普通标题开始 / 局内重开由 `FormalClientBoot` 先显示 `LoadingScreen`、等待一帧并调用 `RNG.set_random_run_seed()`，再实例化 `gameplay_run_loop.tscn`。玩家加载模式用 `ResourceLoader` 线程读取 actor / 模块场景，主线程分批注册 / 预热对象池、挂载初始模块或恢复实体；完成时只发出 `run_prepared`，由启动层移除加载界面后调用 `activate_prepared_run()` 进入 `PLAYING`。工具 / replay 路径可显式固定 seed 后同步准备并立即激活 | `configure_player_loading_mode()`、`load_threaded_request()`、`run_prepared`、`activate_prepared_run()` |
| 地图 / 模块 | 默认按 `module_worlds.json` schema v3 配置 99×99 格世界；中心 `(4,4)` 对齐原点。Manager 先从五个事件模板无放回选三种，再以平地填充普通槽；常态挂载 3×3 邻域，并为三个后台事件模块预留固定容量。仅 `--open-warzone` 回归路径解释旧 PCG / director 摆点 | `ModuleWorldManager.configure()`、`build_assignment()`、`set_slot_pinned()`、`tick()` |
| 难度 / 威胁时间 / 战区导演 | RunLoop 优先使用入树前配置的 difficulty profile id，否则读取 mode 默认。profile 的 `difficulty_coefficient` 缩放威胁时间推进；模块世界只在玩家不处于 `module_role_start` 时推进，开放战区立即推进，开发者测试岛关闭；暂停 / Loading / 结算时不推进。`WarzoneDirector` 用该 elapsed 解释固定 phase 和启用 wave；兴趣点领取内部计时仍使用 `GameClock`，不读玩家状态、不做隐藏动态调难 | `configure_difficulty_profile_id()`、`DifficultyProgression.configure()` / `advance()` / `current_snapshot()`、`WarzoneDirector.is_wave_enabled()` |
| 模块世界 carrier（F13） | 默认开局配置完整 9×9 assignment；固定中心起点、目标、撤离和三个事件模块。首次进入遭遇仍按有效空地固化 4–6 个敌人；事件模块不再叠加普通首次遭遇。跨边界时普通槽按世界槽位流式保存，激活事件模块通过 pin 继续真实模拟。续局由 `module_world` 恢复 assignment/hash/迷雾/slot state/pin，再注册事件目标，最后恢复敌人与子弹 | `ModuleWorldManager.build_assignment()`、`tick()`、`snapshot()` / `restore_state()`、`WorldEventController.restore_snapshot()` |
| 背景 | 在玩家附近绘制量化矩形地图格和原点十字；网格来自 `map_layouts.json.grid`，与机关尺寸 / 判定共用同一格度量，但不缩放或旋转世界坐标，也不模拟斜俯视透视 | `WorldBackground.configure()` |
| 输入 | `InputService` 从 GUIDE 的 gameplay context 产生 `move` / `aim` `Vector2` 与开火、四技能、冲刺、交互、暂停等按钮 intent。键鼠瞄准取 pointer viewport position 相对玩家实际屏幕位置的方向，不读取相机震屏噪声 offset；Replay v3 记录最终 intent 与组合选择 | `InputService`、生成 `Actions` 常量、`Replay` v3 |
| 移动 / 瞄准 / 相机 | 玩家按数据移速在 2D 平面移动；RunLoop 在角色实例化 / 恢复后，把 `ActiveWorld` 预置 Rig 的 `PlayerCamera` 配成 Phantom Camera `GLUED` 跟随当前 Player，`CenteredCamera` 保持水平与等比缩放。开局先居中；首次有效瞄准后，鼠标按实际屏幕距离的死区 / 30% 比例 / 240 px 上限计算引导，键盘、手柄与 Replay 按最终瞄准方向使用 240 px，松开保持最后方向；控制器以 0.18 秒时间常数指数平滑，暂停冻结 | `Player.aim_direction`、`Player.set_camera_look_offset()`、`GameplayCameraController.configure()` |
| 开火 / 换弹 / 后坐 | WeaponSystem 读取 `reload` 与 `fire` intent，同 tick 先处理换弹。弹匣打空后持续按住被锁住，松开再按时有备弹则自动换弹、总弹药为零则武装 50% 射速 / 弹速的降级射击；一次扳机只扣一发。只有至少取得一个子弹池实体才提交弹药、`RNG.combat` 和冷却。combat gate 只锁定开火，起点房仍允许换弹；换弹和冷却使用 `GameClock`。每次提交仍只发一次 `weapon_fired` context，RunLoop 将反向冲量交给 Player、动态震屏交给 Camera | `WeaponSystem.request_reload()`、`ammo_state()`、`add_ammo()`、`WeaponRecoilResolver.resolve()` |
| 弹药 HUD / 打空反馈 | 常驻区只显示弹匣内剩余子弹与弹匣外备弹，不显示两者合计、总容量或打空说明；详细面板同样只显示弹匣、备弹和换弹时间。正常射击打出最后一发时，WeaponSystem 每次弹匣只请求一次角色头顶短时文字；有备弹时显示动态 `reload` 绑定，总弹药耗尽时提示再次开火。长按不重复，总弹药为零后每次重新按开火可再次提示；文字消退使用 `GameClock`，暂停冻结 | `WeaponSystem.ammo_attention_requested`、`Player.show_world_prompt()`、`PlayerWorldPrompt`、`ui_player_ammo_reload_prompt`、`ui_player_ammo_depleted_prompt` |
| 子弹移动 / 地形 | 玩家和敌方子弹移动前先用 `hit_radius` 圆形 `intersect_shape()` 检查初始重叠，再用 `cast_motion()` 扫掠本帧位移；只查询地形层 bit 1。命中后停在安全比例、立即 `PoolManager.release()`，不再检查墙后伤害目标；`wall_pierce > 0` 的发射快照跳过全部地形查询。场景内玩家 `RibbonTrail` 与敌方 `EnemyRibbonTrail` 各自使用有界世界坐标历史，configure / acquire / release 都清空两条历史 | `PhysicsShapeQueryParameters2D` / `PhysicsDirectSpaceState2D` / `VfxRibbonTrail` |
| 子弹命中 | 地形通过后，子弹汇总配置的全部伤害目标组，按扫掠命中时间与稳定实例 id 选择最近目标。普通敌弹只含玩家组；防御事件敌弹额外含防御目标组。屏障边界、地形和 pierce 规则保持不变，伤害统一走 Combat | `DamageInfo` / `ProjectileBarrier.projectile_boundary_hit_fraction()` |
| 英雄 / 技能 / 状态 | RunLoop 用 `HeroCompositionResolver` 解析主／子英雄：主英雄提供属性、被动、场景和技能 1/2，子英雄只提供强调色与技能 3/4。SkillSystem 按固定槽位释放、共享能量并解释通用屏障 / 状态 / 修饰器原语；combat gate 锁定时返回 `reason=combat_locked`，不消耗资源、不进入冷却，且离房后必须重新按键。所有冷却、状态、护盾恢复和超盾衰减继续只走 `GameClock` | `configure_hero_composition()`、`SkillSystem.configure_combat_gate()`、`SkillSystem.cast_slot()`、`StatusEffectComponent` |
| 刷怪 / 出生强化 / 金币锁定 | 模块 carrier 读取 `module_worlds.json.first_visit_enemy_spawn` 的数量、预警时长和按威胁时间解锁的敌种权重，并按首次实际进入规则固化计划；起点豁免。F12 open-warzone carrier 使用 `spawn_waves.csv` 与 `WarzoneDirector.is_wave_enabled()`，时间 gating 同样读取威胁时间。敌人在真正成功取得对象池实体后，先取得生命 / 伤害倍率，再只消费一次 `RNG.economy`，按实际生成阶段、难度系数、敌种价值倍率和默认特殊化倍率 `1.0` 锁定金币；失败生成不消费任何 RNG。预警跨档按生成时等级，场上既有敌人不重算生命、伤害或金币 | `DifficultyProgression.enemy_spawn_snapshot()`、`EnemyRewardResolver.resolve()`、`RNG.spawn`、`RNG.economy` |
| 弹药掉落 / 拾取 | 只有玩家伤害归因且允许奖励的敌人才参与。武器未满时按 `ammo_rules.json` 和连续未掉计数用独立 `RNG.ammo` 抽取；满弹完全不抽取也不推进计数。成功产生一个当前武器完整弹匣并重置计数；空弹拾取优先装匣，其余进备弹，超上限丢弃。场上拾取物通过 `ammo_magazine` 池生成、回收和快照恢复 | `WeaponSystem.can_accept_ammo()` / `add_ammo()`、`GameplayRunLoop._try_spawn_ammo_magazine()` |
| 机关触发 | `Hazard` 在 `PLAYING` 下按 `GameClock.delta_scaled()` 消耗冷却；玩家进入矩形范围后构造 `DamageInfo` 并交给 `Combat`，当前 FEA-12 用于验证 PCG / 手工摆点和伤害链路 | `Hazard.configure()`、`Combat.apply_damage()` |
| 受击 / 击杀反馈 | `Combat.damage_applied` 成功应用伤害后由 profile cue 生成池化火花 / 飘字；玩家有效受伤才触发屏幕叠层与 `camera_feedback.json` 震屏，无敌拦截和敌人受伤不震。角色闪色 / 敌人退场由 `ActorPresentationController + AnimationPlayer` 驱动；击杀、掉落和移出 active group 即时，0.18 秒后回池 | `GameplayFeedbackController.play()`、`GameplayCameraController.play_feedback()` |
| 敌人行为 | 普通敌人仍只感知玩家；防御事件生成上下文可注入专用主目标和目标组，四种攻击都能伤害目标且仍可伤害路径上的玩家。事件结束后残敌转为普通玩家目标，死亡或离开原模块后解除 pin。其他显式攻击、点射和稳定连锁语义不变 | `Enemy.configure(..., spawn_context)`、`convert_to_player_target()`、`docs/代码/enemy_ai.md` |
| 世界事件 | RunLoop 从 assignment 注册三个稳定实例；持续事件全局互斥，祭坛并行。Controller 用 GameClock 推进并请求波次 / 奖励 / pin；RunLoop 用 `RNG.world_event` 固化激活时计划、生命 / 伤害语义和隐藏奖励，统一结算金币或 pending Mod。事件波次中的普通击杀金币仍按各敌人实际生成阶段由 `RNG.economy` 锁定 | `WorldEventController.interact()` / `tick()` / `snapshot()`、`docs/代码/world_event_system.md` |
| 金币掉落 / 成长 | 玩家归因击杀且锁定 `gold_reward > 0` 时必定生成一个池化金币球；死亡时只使用 Enemy 快照中的最终金额，不重算、不抽随机，也不消费掉落 RNG。金币球进入 `pickup_range` 后按 `gold_drop.pickup_speed` 吸附。拾取通过 `add_gold(..., enemy_drop)` 同时增加余额与累计获得金币；等级由 `level_progression.json` 的 100 起步、1.3× 向上取整曲线从累计金币推导。消费只扣余额，不影响等级；一次跨多级只显示一次约 1.35 秒的最终等级提示，不暂停玩法 | `EnemyRewardResolver.resolve()`、`PoolManager.acquire(GOLD_ORB)`、`GoldProgression.add_gold()` |
| 通用奖励选择 | 标准模式不配置默认触发器，升级不会打开选择。调用方在 `PLAYING` 下提供 pool、trigger 和 2–5 个候选发起请求；控制器先完整校验池、数量、候选充足、状态和忙碌条件，再以稳定 id 顺序用 `RNG.ui_choice` 加权无放回抽取。成功后进入 `REWARD_CHOICE` 并冻结玩法，不能取消；暂停菜单可覆盖其上，关闭后回到原选择。选择后记录 `reward_choice` decision，沿用 Player / WeaponSystem modifier 路径应用效果，并发出 trigger、pool、entry 完成信号；`luck` 不参与抽取 | `request_reward_choice()`、`RewardChoicePanel.choice_selected` |
| 主动暂停 | `pause` action 在 `PLAYING` 中打开 `PauseMenu`，在 `REWARD_CHOICE` 中由奖励面板请求把 `PauseMenu` 叠在其上；菜单通过 `UIManager` 请求 `GameState.PAUSED`，玩法时间、敌人、子弹和刷怪冻结，菜单仍响应鼠标、`ui_back` 和再次 `pause` action；暂停菜单可打开 `SettingsPanel`，关闭后仍回到同一个暂停菜单；关闭奖励选择态上方的暂停菜单后必须回到 `REWARD_CHOICE` | `UIManager.push()`、`GameState.PAUSED` |
| 保存退出 / 继续 | 暂停菜单生成 Run v11 payload；除既有战斗 / 世界事件 / 奖励状态外，保存武器弹匣、备弹、换弹剩余时间、弹药未掉计数、`RNG.ammo` 和场上弹匣。恢复已有敌人、射击、换弹与弹药交易均不得重复提交。旧 Run v10 明确不兼容，只删除 run 并保留 Meta v2 | `SaveManager.load_envelope()`、`WeaponSystem.restore_snapshot()`、`AmmoMagazinePickup.restore_snapshot()` |
| UI 布局 | HUD 使用全屏锚点下的容器布局；难度标记器挂在右上小地图下方，详细数值面板显示时向左让位。阶段变化使用固定的非模态颜色、描边和缩放 Tween 高亮。升级面板使用全屏遮罩、居中容器和按视口宽度夹取的面板宽度 | `GameplayHud.set_difficulty_snapshot()`、`Control.set_anchors_preset()` |
| 运行时语言刷新 | `Localization.locale_changed` 发出后，标题、暂停、设置、HUD、升级、失败页和 Gear Mod 面板用自身缓存的状态或配置数据刷新文本；订阅的 UI 在 `_exit_tree()` 断开 signal，避免离树节点收到后续语言切换 | `Localization.locale_changed`、`refresh_texts()` |
| 失败 / 撤离 / 重开 | 玩家生命归零后删除 `run` 存档、丢失 `pending_loot`、进入 `GameState.GAME_OVER`、冻结底层时钟并显示唯一失败面板；小巢核击破后仍保持 `PLAYING`，只有玩家完成撤离读条才提交 `pending_loot`、删除 `run` 并显示完成面板。结果面板、GameState 结果 payload、埋点和 Replay `run_end` 统一使用 `DifficultyProgression.elapsed` 作为本局用时，并附等级及敌人生命 / 伤害倍率 | `SaveManager.delete(run)`、`UIManager.push()`、`GameState.change_state()`、`GameplayRunLoop.restart_requested` |
| DebugTools smoke | `debug-tools-smoke` 启动一局并通过 `DebugConsole` 调用 `GMCommandRegistry`，验证 help/stats/spawn/gold/hp/damage/heal/dust/kill/clear；`debug-tools-release-smoke` 模拟 release guard，确认没有 `DebugConsole` / `GMCommandRegistry` 或 debug action | `client/tools/debug_tools_smoke.gd` / `docs/代码/debug_tools.md` |
| 自动 smoke / 按需 probe | `world_event_smoke` 验证五类状态机；`module-world-smoke` 验证三事件 assignment、pin 与 Run v11；`runtime-smoke` 覆盖金币快照、弹药掉落、显式攻击和防御目标。Replay v3 runner 重建同 seed并对照摘要。仅当用户明确要求性能测试时才运行 `perf-probe` | 对应 smoke / runner 工具 |

## 公共 API

F4 脚本当前是阶段性内部模块，主要公共面向为 signal 和实体生命周期：

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `Player.configure(base_stats)` | 合并后的玩家属性 | `void` | `move_speed` / `max_hp` / `health_regen` / `damage_invulnerability_duration` / `player_separation_radius` 来自数据 |
| `Player.invulnerability_remaining()` | 无 | `float` | 只读诊断值；用于 smoke / 调试确认玩家侧无敌窗口是否归零 |
| `Player.pickup_range()` / `luck()` / `separation_radius()` / `stat_value(stat)` | 无 / stat id | `float` | 只读运行时属性；金币 / 能量球吸附范围、玩家中心排斥和 HUD 详细数值面板使用；`luck` 当前保留但不影响金币、等级或奖励抽取 |
| `Player.aim_at_world_position(world_position)` | 世界坐标 | `void` | 按玩家到目标世界坐标的方向更新 `aim_direction`，并清掉上一帧鼠标瞄准缓存；headless smoke 和未来脚本化瞄准可复用，真实鼠标输入使用玩家实际屏幕位置 + 稳定引导偏移的投影反算路径 |
| `Player.set_camera_look_offset(offset)` | 稳定镜头引导偏移 | `void` | 由 `GameplayCameraController` 写入；用于把鼠标位置换算为相对玩家实际屏幕位置的方向，`Camera2D.offset` 震屏噪声不得包含在参数内 |
| `Player.apply_modifiers(modifiers)` | `reward_choice_pools.json` 的 modifiers | `void` | 按 `(基础 + 加法) * 乘法` 更新玩家运行时属性 |
| `Player.apply_status_effect(status_effect)` / `active_statuses()` | `StatusEffect` 兼容对象 / 无 | Dictionary / `Array[String]` | 玩家状态走 `StatusEffectComponent`；新开局 `configure()` 清空状态与 owned ability tags |
| `Player.combat_team_id()` | 无 | String | 返回玩家队伍 id，供状态 DoT 等延迟伤害保存 source / target team 归因 |
| `Player.add_owned_tag()` / `remove_owned_tag()` / `has_owned_tag()` / `owned_tags()` | ability tag id | bool / `Array[String]` | 只接受词表 §12-G 已登记 tag；供状态授予 / 移除和调试查询 |
| `Player.snapshot()` / `restore_snapshot(snapshot_data)` | 无 / run payload | Dictionary / `void` | 保存位置、朝向、生命 / 防御、冲刺、武器后坐速度 / 剩余时间 / 总时长、modifiers、owned tag 计数和状态效果；缺失后坐字段按静止读取 |
| `Player.configure_weapon_recoil(recoil_model)` / `apply_weapon_recoil(direction, initial_speed, duration)` | 后坐模型 / 中心开火方向与冲量 | `void` | 配置运行时速度上限；开火时叠加反向向量并钳制，冲刺激活时不新增冲量 |
| `Player.receive_damage(info)` | `DamageInfo` | result dictionary | 只能由 `Combat.apply_damage()` 间接调用；无敌期返回 `reason=invulnerable` 且不扣生命 |
| `Player.debug_heal()` / `debug_set_life()` / `debug_clear_invulnerability()` | 调试数值 | Dictionary / `void` | 仅供 debug/dev_tools GM 指令调用；正式 gameplay 不应依赖 |
| `GameplayCameraController.configure(target, feedback_config)` | 实现 `set_camera_look_offset()` 的玩家 `Node2D`、`camera_feedback.json` 根对象 | `void` | 签名不变；绑定 GLUED 跟随目标，读取 `aim_look` 并向受击 / 武器两个 noise resource 与 emitter 写入已校验参数；重绑时从零偏移开始 |
| `GameplayCameraController.current_look_offset()` | 无 | `Vector2` | 只读诊断接口；返回当前平滑后的稳定引导偏移，不包含震屏噪声 |
| `GameplayCameraController.play_feedback(feedback_id, context)` | profile id、开火 context | `void` | 受击震屏使用固定数据；武器震屏按 `recoil_ratio` 和 profile 指数缩放，连射刷新且保留较强振幅；自行检查 `gameplay.screen_shake` |
| `WeaponSystem.configure(player, active_parent, weapon_data, recoil_model)` | 玩家、活跃父节点、武器数据、后坐模型 | `void` | 武器与根级模型来自 `weapons.json` |
| `WeaponSystem.configure_combat_gate(gate)` | 返回 bool 的 Callable | `void` | `false` 时开火不生成子弹、不消耗 RNG；持续按住 intent 可在解锁后立即生效 |
| `WeaponSystem.apply_modifiers(modifiers)` | `reward_choice_pools.json` 的 modifiers | `void` | 按 `(基础 + 加法) * 乘法` 更新武器运行时属性 |
| `WeaponSystem.stat_value(stat)` | stat id | `float` | smoke / 调试读取当前武器数值 |
| `WeaponSystem.active_temporary_modifiers()` | 无 | `Array[Dictionary]` | 当前权威临时强化生命周期快照，续局后用于表现重建 |
| `WeaponSystem.ammo_state()` | 无 | `Dictionary` | 返回弹匣、备弹、总量 / 上限、换弹计时和降级武装状态 |
| `WeaponSystem.can_accept_ammo()` / `add_ammo(amount)` | 无 / 数量 | `bool` / 实际加入量 | 满弹拒绝；总弹为零时先直接装入弹匣 |
| `WeaponSystem.request_reload()` | 无 | `bool` | 仅 `PLAYING`、弹匣未满且有备弹时提交；完成时才转移备弹 |
| `SkillSystem.configure(caster, active_parent, skills, resources)` | 施法者、活跃父节点、技能定义、资源定义 | `void` | 技能数据来自 `skills.json`，资源来自角色 `skill_resources`；详见 `docs/代码/skill_system.md` |
| `SkillSystem.configure_combat_gate(gate)` | 返回 bool 的 Callable | `void` | `false` 时释放返回 `combat_locked`，不消耗资源、不进入冷却 |
| `SkillSystem.cast_primary_skill()` / `cast_skill(skill_id)` | 无 / 技能 id | Dictionary | 失败不消耗资源；伤害效果必须走 `Combat.apply_damage()`；状态效果必须走 `StatusEffectComponent` |
| `SkillSystem.apply_status_effect(status_effect)` | `StatusEffect` 兼容对象 | Dictionary | 给释放者自身施加沉默等状态；状态授予 / 移除 ability tags 由组件管理 |
| `SkillSystem.snapshot()` / `restore_snapshot(snapshot_data)` | run 快照 | Dictionary / `void` | 保存冷却、资源、owned ability tag 计数和状态效果，不保存节点引用 |
| `Bullet.configure(stats, projectile, direction, source)` | 武器属性、弹体数据、方向、来源 | `void` | 节点必须来自 `PoolManager`；发射时快照 `wall_pierce > 0`，敌弹额外快照首帧屏障扫掠起点；默认地形阻挡，当前可命中 `active_enemies` 与 `active_interest_point_targets`，伤害统一走 `Combat.apply_damage()` |
| `Enemy.configure(enemy_data, player, navigation_provider = null, spawn_difficulty = {}, spawn_context = {})` | 合并敌人数据、玩家、可选模块导航门面、出生倍率、锁定奖励与事件上下文 | `void` | 节点必须来自独立 `PoolManager` 池；生命 / 显式攻击伤害按快照缩放，移速与 AI 不变 |
| `Enemy.ai_debug_summary()` | 无 | `Dictionary` | debug 包含感知 / 导航、攻击 action / 阶段 / 剩余时间、armed、锁向、倍率后伤害、范围、命中位和生成序号 |
| `Enemy.separation_radius()` / `visual_color()` / `is_defeat_feedback_active()` | 无 | `float` / `Color` / `bool` | 只读诊断值；用于中心排斥、占位色、死亡反馈和 smoke 确认 |
| `Enemy.apply_status_effect(status_effect)` / `active_statuses()` | `StatusEffect` 兼容对象 / 无 | Dictionary / `Array[String]` | 敌人状态走 `StatusEffectComponent`；`configure()`、`_pool_release()` 和 `_pool_reset()` 清空状态，避免对象池泄漏 |
| `Enemy.combat_team_id()` | 无 | String | 返回敌人队伍 id，供状态 DoT 等延迟伤害保存 source / target team 归因 |
| `Enemy.add_owned_tag()` / `remove_owned_tag()` / `has_owned_tag()` / `owned_tags()` | ability tag id | bool / `Array[String]` | 只接受词表 §12-G 已登记 tag；供状态授予 / 移除和调试查询 |
| `Enemy.snapshot()` / `restore_snapshot(snapshot_data)` | 无 / run payload | Dictionary / `void` | 保存生命、位置、AI action / FSM、伤害归因、出生生命 / 伤害倍率、完整奖励明细、owned tag 计数和状态效果；正式 Run v11 要求奖励快照 |
| `GoldOrb.configure(amount, target, pickup_speed)` | 金币值、目标玩家、吸附速度 | `void` | 节点必须来自 `PoolManager`；拾取速度来自 `player.json.gold_drop.pickup_speed` |
| `GoldOrb.is_attracting()` / `is_collect_feedback_active()` | 无 | `bool` | 只读诊断值；用于 smoke 确认吸附 / 拾取反馈生命周期 |
| `HitSpark.configure(spawn_position)` / `DamageNumber.configure(spawn_position, amount, defeated, player_damage)` | 反馈位置与伤害摘要 | `void` | 节点必须来自 `PoolManager`；只做短命视觉反馈，不写入 run 快照 |
| `GameplayRunLoop.add_gold(amount, reason_id)` / `try_spend_gold(amount, reason_id)` | 正整数、登记原因 id | `Dictionary` | 64 位溢出、非法原因、非正数或余额不足均原子失败；结果含余额、累计金币、旧 / 新等级和提升级数 |
| `GameplayRunLoop.gold_balance()` / `gold_earned_total()` / `current_level()` / `current_level_gold()` / `current_level_gold_required()` / `can_afford_gold(amount)` | 无 / 金额 | `int` / `bool` | HUD、交易调用方和诊断使用；等级只由累计金币推导 |
| `GameplayRunLoop.request_reward_choice(pool_id, trigger_id, candidate_count)` | 奖励池、触发 id、2–5 | `Dictionary` | 只允许 `PLAYING` 且无未完成请求；失败不消耗 RNG、不改状态、不显示 UI |
| `GameplayRunLoop.create_run_snapshot()` | 无 | `Dictionary` | 生成 Run v11 payload；保存既有对局状态、弹药 / 换弹 / 弹匣掉落、难度 profile、模块 / 世界事件事务、敌人奖励快照和全部 RNG state。只保存 JSON 友好数据 |
| `GameplayRunLoop.configure_restore_snapshot(snapshot)` | `Dictionary` | `void` | 在节点入树前由 `FormalClientBoot` 调用；要求 schema v10 与合法 difficulty / 金币 / 奖励选择 / 敌人奖励快照，随后重建玩家、武器、敌人、子弹、金币球、RNG、GameClock 和 `ui_restore` 状态 |
| `GameplayRunLoop.configure_difficulty_profile_id(profile_id)` | profile id | `void` | 只能在入树前调用；空值使用 mode 默认。当前玩家 UI 总是传标准 profile，接口为未来选择保留 |
| `GameplayRunLoop.debug_difficulty_snapshot()` | 无 | `Dictionary` | 只读返回 profile/name/difficulty coefficient、当前威胁 elapsed / level / progress / 生命 / 伤害倍率，供 smoke 与 debug summary |
| `GameplayRunLoop.configure_player_loading_mode(enabled)` | `bool` | `void` | 必须在节点入树前调用；`true` 启用线程资源读取、分帧准备和外部激活，默认 `false` 保留工具同步时序 |
| `GameplayRunLoop.activate_prepared_run()` | 无 | `bool` | 仅在准备成功且尚未激活时有效；切换 `PLAYING` 后才恢复保存的暂停 / 奖励选择 UI |
| `GameplayRunLoop.debug_summary()` / `debug_spawn_enemy()` / `debug_give_gold()` / `debug_request_reward_choice()` / `debug_heal_player()` / `debug_set_player_hp()` / `debug_damage_player()` / `debug_kill_player()` / `debug_kill_enemies()` / `debug_clear_enemies()` / `debug_damage_interest_point_target()` | GM 指令参数 | `Dictionary` | 只作为 DebugTools / smoke / golden replay 的受控 runtime API；刷怪走对象池，伤害 / 击杀走 `Combat`，金币走正式交易，奖励走正式请求 API |
| `GameplayRunLoop.debug_enable_open_warzone()` | 无 | `void` | 仅测试 / 对照回归显式切到 F12 open-warzone；正式标准模式默认模块世界 |
| `RewardChoicePanel.configure(choices)` / `choose_index(index)` | 奖励候选 | `void` | 面板节点通过 `UIManager` 挂载；玩家可见文案来自 locale；面板宽度随视口宽度在最小 / 最大值之间自适应；按 `pause` action 时发出 `pause_requested`；语言切换时重用 `_choices` 重建按钮 |
| `GameplayHud.set_life()` / `set_kills()` / `set_level()` / `set_gold_progress()` / `set_difficulty_snapshot()` / `show_level_up_feedback()` / `show_reward_feedback()` / `show_extraction_feedback()` / `set_stats_panel_visible()` / `set_detailed_stats()` | HUD 状态 | `void` | 常驻 HUD 显示等级和“金币余额 · 等级进度”；详细面板拆分余额、累计金币和等级进度并保留 luck；难度标记器同时显示时间、等级、阶段、刻度和起点锁定 |
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
| `Enemy.defeated` | `enemy`, `gold_reward`, `player_attributed` | 敌人生命归零；`gold_reward` 是生成时锁定整数 |
| `GoldOrb.collected` | `amount` | 金币球被玩家拾取 |
| `WeaponSystem.ammo_changed` | `state` | 配置、开火、拾取、换弹开始 / 完成或恢复后 |
| `WeaponSystem.reload_started` / `reload_completed` | `state` | 一轮换弹成功开始 / 完成时各一次 |
| `AmmoMagazinePickup.collected` | `amount` | 弹匣将实际可加入数量交给当前武器后 |
| `RewardChoicePanel.choice_selected` | `choice` | 玩家选择一个奖励候选 |
| `RewardChoicePanel.pause_requested` | 无 | 玩家在奖励选择面板按 `pause` action 请求打开暂停菜单 |
| `GameplayRunLoop.reward_choice_resolved` | `trigger_id`, `pool_id`, `entry_id` | 奖励成功应用并结束选择 |
| `PauseMenu.resume_requested` | 无 | 玩家选择继续或再次按 `pause` |
| `PauseMenu.save_and_quit_requested` | 无 | 玩家在暂停菜单选择保存并退出 |
| `GameplayRunLoop.restart_requested` | 无 | 玩家在失败后请求重开 |
| `GameplayRunLoop.quit_to_title_requested` | 无 | 玩家在失败后请求回标题 |
| `GameplayRunLoop.run_prepared` | 无 | 玩家加载模式准备完成，但 gameplay 尚未激活 |
| `GameplayRunLoop.run_prepare_failed` | `reason`, `restoring` | 玩家加载模式资源或构建失败；启动层据此清理并回标题 |

## 数据与契约

- 英雄组合：默认“冷静主 + 愤怒子”；`characters.json` schema v3 的两个初始 hero id 可复用同一基础场景。RunLoop 入树前接收主／子 id，解析器拒绝未知 id 和局外重复组合；续局从 Run v11 恢复。主英雄独占基础属性、被动、身体／主体色，子英雄只贡献技能 3/4 与强调色。
- 模式：默认读取 `mode_standard_survival`，其 id 来自生成常量 `GameModes`。
- 武器：从 `characters[].starting_loadout.weapon_id` 读取，不在代码写武器 id 分支。`weapons.json` schema v4 的 `ammo` 必填弹匣、开局备弹、总上限、换弹时间与零弹射速 / 弹速倍率；基础枪为 30 / 150 / 240 / 1.2 秒 / 0.5 / 0.5。
- 技能：每个英雄声明两个 `hero_skill_ids`，组合固定映射到 `skill_1`～`skill_4`，冷却按槽位保存；共享资源为能量。主英雄能力四维缩放全部四槽。初始技能为静域屏障、镇静脉冲、怒意超频、激怒标记，均由通用 effect / status / modifier 原语解释。
- 技能资源：从 `characters[].skill_resources` 读取，当前默认资源为 `mana`；后续怒气、能量等资源应新增资源 id 和角色资源池，不在 SkillSystem 写死。
- 子弹池：从 `weapons[].projectile.pool_id` 读取；当前样例为已登记 `bullet_basic`。`base_stats.pierce_count` 只表示额外伤害目标数，`base_stats.wall_pierce` 为全地形开关且基础武器显式为 `0.0`。两者都经 ModifierEngine 合并，但 `Bullet.configure()` 在发射时快照结果；Buff 结束不追改飞行中的子弹。子弹场景使用黄色圆点、暗色轮廓与共享 Shader RibbonTrail；尾迹只表达飞行方向，不承载伤害或行为差异。
- Actor 场景缓存：运行开始时按唯一 `scene_path` 一次性加载角色与本局五种敌人的 `PackedScene`。正式玩家入口使用 `ResourceLoader.load_threaded_request()` / `load_threaded_get()`，工具入口同步加载；两条路径得到同一缓存。多个内容 id 可复用同一场景路径，但角色场景不得指向 `player_base.tscn`，敌人场景不得指向 `enemy_base.tscn` 或正式 actor 目录之外。
- 敌人池：从 `enemies.csv.pool_id` / `pool_prewarm` 读取；当前五种敌人分别使用 `enemy_chaser`、`enemy_swarm`、`enemy_stalker`、`enemy_bulwark`、`enemy_spitter` 独立对象池，预热为 `8 / 5 / 3 / 4 / 8`。factory 绑定该行 `scene_path`，首次进入计划生成与快照恢复必须取得相同专属场景，池复用不得跨敌人类型。
- 模块首次遭遇：`module_worlds.json.first_visit_enemy_spawn` 是数量、预警时长和累计敌种解锁权重的唯一数值来源。Manager 只返回按行列排序的有效空地格心；RunLoop 消耗 `RNG.spawn`、把 `enemy_id + world_position` 与 `telegraphing/spawned` / `remaining_telegraph` 立即写入槽位，并管理预警 VFX 与池化生成。空地不检查玩家 / 动态实体，不设安全半径；恢复和重新激活只重建 VFX，不重抽计划。
- 敌人 AI profile：从 `enemies.csv.ai_profile_id` 引用 schema v5 `enemy_ai_profiles.json`；`perception` 配置视觉 / 路径 / 记忆，`movement` 只保留通用移动字段，攻击 action 必须携带精确 `attack`，远程攻击额外必填 `windup` / `burst_count` / `shot_interval`。派生导航缓存不进 Run v11；攻击阶段、事件归属 / target mode、剩余时间、锁向、点射、armed、生成序号、出生倍率、奖励明细和状态效果进入快照。
- 敌人中心间距：从 `enemies.csv.separation_radius` 读取；当前默认 9px，低于 `hit_radius` 以允许视觉重叠。
- 玩家中心排斥：从合并后的玩家 `base_stats.player_separation_radius` 读取；当前默认 10px。敌人与玩家的最小中心距离为两者分离半径之和，碰到时只推开敌人，不改变玩家移动手感，也不造成伤害；显式攻击使用各自的范围、扇区或扫掠判定。
- 俯视资产规则：地面范围类资产（机关、AOE、房间边界、地面符号）默认使用矩形 / 方形俯视格或清晰俯视轮廓；机关和规则型地面 footprint 尺寸应表达为格子整数倍。角色、敌人、拾取物、子弹、障碍物和特效不强制矩形，但必须有清晰俯视轮廓、方向标记、功能色和真实判定形状。AI 生成正式资源或占位替换时先写清 footprint、anchor、orientation_read、sort layer 和真实判定形状。
- 玩家占位表现：由 `player_base.tscn` 和角色专属继承场景中的 `Polygon2D` / `Line2D` 保存蓝色轮廓、朝向标记和可编辑静态结构；脚本只驱动完整 `aim_direction`、受伤红闪和运行时状态。基础场景保留与 12 px 轮廓一致的 `CircleShape2D`，使 `move_and_slide()` 能与模块封锁格的 `StaticBody2D` 边界碰撞；不能只画角色而省略物理 shape。正式玩家场景不再挂 `Player3DVisual`，不再用 `SubViewport + Camera3D` 正交渲染低模胶囊。
- 敌人占位表现：`enemy_base.tscn` 提供共享组件，每个 `enemies/enemy_*.tscn` 继承它并覆盖导出的 `fill_color`、`Polygon2D` 轮廓和可编辑静态子节点；`Enemy.configure()` 应用 `hit_radius`、出生生命 / 伤害倍率、速度、AI 和表现 profile，但不缩放速度，也不覆盖场景颜色 / 归一化几何。命中 / 退场时间轴由 `ActorPresentationController`，语义组合由 `GameplayFeedbackController` 驱动。
- 机关占位表现：通用 `Hazard` 绘制矩形危险地块；`hazards.csv.radius_tiles` 表示占用地图矩形格的整数倍，`MapManager.grid_cell_size()` 同时驱动背景网格、机关绘制和触发判定。
- 战区导演：`warzone_directors.json` 声明当前模式的固定 phase、mutation 和兴趣点；`GameplayRunLoop` 用它 gating wave，并把当前 layout 的兴趣点交给 `MapManager` 生成初始 `source="director"` 机关；不能让它读取玩家血量、DPS、受伤次数、输入节奏或其它玩家状态。F12 当前四个兴趣点通过通用 `resource_rewards[]` / `gear_mod_rewards[]`、`requires_interaction`、`target_hp` / `target_hit_radius` 和 `completes_run` 接线，不按 `poi_id` 特判；`requires_interaction` 缓存箱和 `target_hp` 目标都必须走 MapManager 的独立 POI anchor，不能复用陷阱位置；缓存箱是贴地 POI 视觉，层级应在地图背景之上、机关 / 敌人 / 玩家模型之下；后续守卫或核心实体仍应复用 reward / objective 数据而不是新增 id 分支。
- 玩家生命尺度：默认角色 `max_hp` 为 600.0，采用浮点血量尺度而非旧心数尺度；`health_regen` 在 `PLAYING` 状态下按 `GameClock.delta_scaled()` 自动恢复生命且不超过上限，当前默认 1.5 HP/s。
- 玩家俯视表现：`Player` 是 `CharacterBody2D`，移动、碰撞、受击、武器反冲、显示占位和 run 快照都维持 2D；`GameplayCameraController` 是 `GameplayRunLoop/ActiveWorld` 中与 `PlayerHost` 并列的唯一对局级 Rig，RunLoop 在角色创建或恢复后重新绑定 GLUED PCam。当前固定 `ignore_rotation=true`、无插件 smoothing / damping / lookahead / dead zone / auto zoom / load tween，并保持 `Vector2.ONE` 等比缩放。`camera_feedback.json` schema v3 的 `aim_look` 驱动帧率无关平滑引导；由于当前固定版本插件的 GLUED 更新路径不消费其导出 `follow_offset`，项目适配层仍动态写该属性作为权威状态，同时在 host 更新后把相同稳定偏移镜像到真实 `Camera2D` 位置，不修改插件源码。鼠标瞄准使用光标相对玩家实际屏幕位置的方向；`Camera2D.offset` 只承载震屏，开关震屏不清理引导偏移。
- 受伤无敌：从合并后的玩家 `base_stats.damage_invulnerability_duration` 读取；当前默认 `player.json` 为 0.7 秒，和受伤红闪时长分离。
- 金币球：使用词表 §8 `gold_orb` 对象池；`player.json.base_stats.pickup_range` 控制吸附范围，`gold_drop.pickup_speed` 控制 360 px/s 吸附速度。能量球同样读取 `pickup_range`，速度独立来自 `energy_drop.pickup_speed`。金币球占位使用金色圆点、暗色轮廓与收集反馈。
- 弹药弹匣：使用词表 §8 `ammo_magazine` 对象池；`ammo_rules.json` schema v1 配置池 id、360 px/s 吸附速度、每次一个完整弹匣，以及 8% 起步、每次未掉增加 15%、第 8 次保证成功的曲线。数量只取当前武器 `magazine_size`，不受敌人价值、难度、阶段或低弹比例影响。
- 敌人金币：`enemy_rewards.json` schema v1 配置基础系数 10、每阶段 10% 和 `0.9..1.1` 随机区间；`enemies.csv.gold_value_multiplier` 配置敌种价值。公式还乘 profile 难度系数和 `spawn_context.reward_specialization_multiplier`，四舍五入后至少 1 并在安全整数上限饱和。生成时锁定，死亡只发锁定值。
- 金币与等级：`GoldProgression` 是余额、累计获得金币和等级推导的唯一事实源。`level_progression.json` 配置首段 100 与有理倍率 13/10；每段 `ceil(previous × 13 / 10)`，不用浮点幂，前十段固定为 `100, 130, 169, 220, 286, 372, 484, 630, 819, 1065`。余额可消费，累计金币只增不减；等级从累计金币重算，不单独保存。
- 奖励选择：`reward_choice_pools.json` 定义池和候选；当前只解释 `kind=stat_modifier`。调用方显式提供 pool / trigger / 2–5 候选数，控制器按当前等级过滤、稳定 id 排序后使用 `RNG.ui_choice` 加权无放回抽取；`luck` 无影响。Run v11 保存 trigger、pool 和原候选，续局恢复时不再消耗 RNG。
- 分辨率与 UI：当前只设计 / 验收固定 16:9，默认 viewport 由 `client/project.godot` 设为 1920×1080；窗口禁止任意拖拽缩放，非 16:9 屏幕通过 `canvas_items + keep` 等比缩放并补黑边，不拉伸、不裁切、不扩大玩法视野；F4 HUD 和升级面板使用 `Control` 锚点 / 容器布局适配经过验证的 16:9 固定预设。其他宽高比留作未来按独立固定预设接入的 P3 优化，不作为当前响应式布局目标。
- run 续局快照：`RUN_SNAPSHOT_SCHEMA_VERSION` 与 `SaveManager` run envelope 均为 v11。除既有对局字段外，保存武器弹匣 / 备弹 / 换弹状态与剩余时间、`ammo_drop_misses`、`RNG.ammo` 和 `active_ammo_magazines` 快照。恢复武器后再恢复场上弹匣并重新绑定当前 Player / WeaponSystem；不保存瞬时 held latch，加载后空弹必须重新按下。旧 Run v10 不兼容，只删除 run、保留 Meta v2。RNG 大整数 state 继续以字符串保存并在 hash 前 JSON 归一化。
- 局外成长接入：F11 后 Gear Mod 是唯一当前跨局装配运行时。死亡不再写旧局外货币 / 账号经验，也不再弹旧升级入口；死亡后仍必须删除 `run` 存档，避免继续旧局。新开局属性来源为 `GearModSystem.current_modifiers("hero")` / `current_modifiers("weapon")`：hero modifiers 只应用到 `Player.apply_modifiers()`，weapon modifiers 只应用到 `WeaponSystem.apply_modifiers()`。项目尚未上线，不维护旧局外成长测试档迁移或补偿。
- 装备 Mod 掉落：玩家归因击败敌人时，`GameplayRunLoop._on_enemy_defeated()` 会生成金币球，再调用 `GearModSystem.roll_drop_for_enemy(enemy_id, ..., commit_immediately=false)`，把命中的 Mod 放进 `run.pending_loot`；怪物互杀或非玩家归因击杀不会计入击杀、金币或 Gear Mod 掉落。首片 `enemy_chaser` 掉落率来自 `gear_mod_drop_tables.csv` 的 `0.01`，随机走 `RNG.drop`；金币球是确定性掉落，不消耗该随机流。掉落结果携带 `name_key`，命中后通过 `GameplayHud.show_gear_mod_drop_feedback()` 显示暂存反馈；击破小巢核或未来撤离成功时才调用 `GearModSystem.grant_mod()` / `grant_resource()` 写入 `meta.gear_mods`。
- 伤害类型：从 `weapons.json` / `enemies.csv` / `hazards.csv` 读取，交给 `Combat` 校验。
- UI / HUD / 奖励文案：`ui_title_name`、`ui_title_subtitle`、`ui_start`、`ui_continue_run`、`ui_run_save_unavailable`、`ui_settings*`、`ui_pause_title`、`ui_save_and_quit`、`ui_quit`、`ui_hud_life`、`ui_hud_kills`、`ui_hud_time`、`ui_hud_level`、`ui_hud_gold_progress`、`ui_stats_*`、`ui_reward_choice_title`、`ui_reward_applied`、`ui_level_reached`、`ui_game_over`、`ui_restart_hint`、`ui_restart`、`ui_quit_to_title`、`ui_run_summary`、`ui_result_*`、`ui_gear_mod_*`，奖励候选使用 `reward_choice_pools.json` 的 `name_key` / `desc_key`。常驻 UI 必须在 `Localization.locale_changed` 后刷新已有节点，不依赖重启或重新实例化。
- GM / DebugTools：`debug_*` action 只由 `DebugConsole` 在 debug/dev_tools guard 通过后注册；GM 对局内状态的变更集中走本节公开 `debug_*` runtime API，且不得写入正式 analytics。

## 依赖

- 上游依赖：`DataLoader`、`GameState`、`GameClock`、`DifficultyProgression`、`EnemyRewardResolver`、`RNG.spawn`、`RNG.world`、`RNG.world_event`、`RNG.economy`、`RNG.ammo`、`RNG.ui_choice`、`RNG.camera_fx`、`InputService`、`PoolManager`、`UIManager`、`SaveManager`、`GearModSystem`、`Combat`、`StatusEffectComponent`、`PhantomCameraManager`、`MapManager`、`WarzoneDirector`、`difficulty_profiles.json`、`enemy_rewards.json`、`ammo_rules.json`、`game_modes.json`、`camera_feedback.json`、`hazards.csv`、`map_layouts.json`、`warzone_directors.json`、locale。
- 下游调用方：当前无；后续可拆分为正式 Player / WeaponSystem / Spawner / HUD 模块。
- 禁止依赖：不得复制历史 MVP 代码；不得绕过正式 `.tscn` 场景资源临时拼长期 UI / runtime 节点；不得绕过 `PoolManager` 创建高频实体；不得直接扣生命；不得绕过 `InputService` 读取 GUIDE / `Input` / `InputMap` 或物理输入；不得用裸随机或原始时间。

## 扩展点

- 加武器：优先改 `weapons.json`，运行时继续解释 `base_stats` 和 `projectile`。
- 加穿墙 Buff：通过既有 modifier 管线给 `wall_pierce` 增加正值；不要复用 `pierce_count`，也不要把它解释成有限穿墙次数。穿墙只忽略地形，不自动附加穿敌、穿机关、反弹或爆炸。
- 加技能：优先改 `skills.json` 与 `characters.json.hero_skill_ids`；新 ability tag、状态、叠加规则、目标类型、缩放参数或效果原语先登记词表，再扩展 SkillSystem / StatusEffectComponent，不按英雄或技能 id 写分支。
- 加状态宿主：可被状态影响的新实体应复用 `StatusEffectComponent`，实现 `apply_status_effect()`、owned ability tag 查询、`combat_team_id()` 和 JSON 友好快照；对象池实体必须在 `configure()` / 回收路径清空状态。
- 加敌人：优先改 `enemies.csv`、`enemy_ai_profiles.json`、`game_modes.json` 和 `spawn_waves.csv`；行为差异通过对玩家 AI profile 表达，不在 `enemy.gd` 按 id 分支。
- 加地图 / PCG 规则：优先改 `map_layouts.json`；运行时通过 `MapManager` 解释有限边界、手工摆点、PCG 和导演传入的通用兴趣点机关，不在 `GameplayRunLoop` 按 layout id 分支。
- 加 / 改战区导演：优先改 `warzone_directors.json`；固定节奏、巢变异主题、wave gating 和兴趣点都应由数据表达，兴趣点可通过 `MapManager` 变成初始地图机关，但仍不读取玩家状态、不做隐藏 DDA、不接运行时 LLM。
- 加模块（F13）：从 `client/templates/module_template.json` 创建独立 11×11 schema v3 JSON，先登记为 `candidate`；通过 schema、边缘共同开放格、占格、可达性和内容预算校验后，由人工改为 `approved` 才可进入默认模板池。模块只能引用词表和数据中已登记的 primitive，不能添加敌人 spawn placement；详见 `docs/代码/module_world_manager.md`。
- 加机关：优先改 `hazards.csv`、`game_modes.json.resource_pools.hazards` 和 `map_layouts.json`；普通矩形范围机关复用 `Hazard`，新行为先设计通用 primitive，不按机关 id 写分支。
- 加刷怪：F13 首次进入遭遇改 `module_worlds.json.first_visit_enemy_spawn`；F12 open-warzone 波次改 `spawn_waves.csv`。两者的时间 gating 必须使用 `DifficultyProgression.elapsed`，位置 / 敌种随机继续使用 `RNG.spawn`；不得回退到 `GameClock.now()` 或互相复用隐藏状态。
- 加奖励候选：优先改 `reward_choice_pools.json`；调用方必须显式选择池、触发 id 和 2–5 候选数，标准模式不配置默认触发器。新候选如果仍是 `stat_modifier` 不需要改逻辑，新增候选类型才需要扩展运行时解释和文档。
- 场景资源化：新增稳定 gameplay / UI 层级时优先新增 `.tscn`，脚本只做节点绑定、配置和 signal 编排；只有对象池工厂与数据驱动重复项可以在运行时创建节点，并要在模块文档说明原因。
- 扩展 run 快照：新增可恢复实体字段时先保证 JSON 友好，再更新本文档、SaveManager 文档、`runtime-smoke` 和 `save-smoke`；不要保存 `PoolManager` 内部队列或节点引用。
- 改普通新局 seed：只在 `FormalClientBoot` 的人工开始 / 重开入口生成新主 seed；不要在 `GameplayRunLoop` 内部、继续游戏、回放 runner 或 golden capture 路径隐式随机化。
- 扩展死亡后奖励：旧 `MetaProgressionSystem` 死亡结算已删除。若要新增死亡后奖励或局外资源来源，先写 ADR / 数据契约并接入当前 Gear Mod 或新的明确系统，不要恢复旧永久升级运行时。
- 扩展 GM 指令：先在 `GMCommandRegistry` 增命令，再在目标系统补受控 API；禁止在命令注册表里直接改 gameplay 私有字段、节点树或存档文件。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 调玩家速度 / 生命 / 受伤无敌 / 中心排斥 | `player.json` / `characters.json` | `client/data/README.md` | `python tools/validate_data.py` |
| 调瞄准引导距离 / 死区 / 平滑或震屏 | `camera_feedback.json`、`gameplay_camera_controller.gd`、`player.gd` | 数据手册、本文档、Phantom Camera 文档、GDD §5.2 | data/schema + 三档 lint + actor/input/settings/runtime/replay-input/headless + 黄金回放 |
| 调武器伤害 / 射速 / 弹速 / 后坐 / 扩散 | `weapons.json` | `client/data/README.md` | contracts + data/schema + L1/runtime + replay |
| 改子弹墙体阻挡 / 穿墙 | `bullet.gd`、`module_chunk.gd`、`weapons.json` | 本文档、ModuleWorldManager 文档、GDD、词表、ADR | contracts + data/schema + `module-world-smoke` + technical slice + runtime/save/L1 + golden replay |
| 调技能伤害 / 半径 / 资源消耗 / 冷却 | `skills.json`、`characters.json` | `client/data/README.md`、`docs/代码/skill_system.md` | `validate_data` + `l1-smoke` + `runtime-smoke` |
| 改 Player / Enemy 状态宿主 | `player.gd`、`enemy.gd`、`status_effect_component.gd`、`l1_smoke.gd` | 本文档、状态组件文档、EnemyAI、GDD、测试策略 | `lint_gdscript_rules` + `lint_semantic_rules` + `l1-smoke` + `runtime-smoke` + `save-smoke` |
| 调敌人血量 / 速度 / 金币 / 中心间距 / 占位色 | `enemies.csv` / 专属 TSCN | `client/data/README.md` | `validate_data` + actor/runtime smoke |
| 调爆炸 / 近战 / 冲撞 / 远程 | `enemy_ai_profiles.json.actions[].attack` | `client/data/README.md`、Enemy AI、VFX | schema + runtime + golden replay |
| 调敌人对玩家 AI | `enemy_ai_profiles.json`、`enemies.csv.ai_profile_id` | `client/data/README.md`、`docs/代码/enemy_ai.md` | `validate_data` + `runtime-smoke` + 必要时 golden replay |
| 调远程敌人点射 / 投射物 | `enemy_ai_profiles.json.actions[].attack`、`enemy.gd`、`bullet.gd`、`bullet.tscn` | `client/data/README.md`、`docs/代码/enemy_ai.md`、PoolManager | data/schema + actor/runtime/save/module-world + golden replay |
| 调地图边界 / PCG 机关 / 手工摆点 | `map_layouts.json` | `client/data/README.md`、`docs/代码/map_manager.md` | `validate_data` + `runtime-smoke` + `f9-demo-smoke` |
| 调机关伤害 / 占格尺寸 / 冷却 | `hazards.csv` | `client/data/README.md`、`docs/代码/hazard_system.md` | `validate_data` + `f9-demo-smoke` |
| 调战区导演阶段 / 兴趣点 | `warzone_directors.json` | `client/data/README.md`、`docs/代码/warzone_director.md`、必要时 `docs/代码/map_manager.md` | `validate_data` + `test_data_loader_schema` + `runtime-smoke` + `f9-demo-smoke` |
| 调刷怪节奏 | `spawn_waves.csv` | `client/data/README.md` | `validate_data` + 手动 1 分钟 |
| 调金币等级曲线 / 奖励候选 | `level_progression.json` / `reward_choice_pools.json` | `client/data/README.md` | `validate_data` + schema + runtime/save/replay；等级仍不得自动弹奖励面板 |
| 改 HUD 文案 | `strings.csv` | `client/locale/README.md` | `validate_data` |
| 改 HUD / 奖励面板布局 | `client/scenes/gameplay/gameplay_hud.tscn`、`client/scenes/ui/reward_choice_panel.tscn`、对应脚本 | 本文档 | `runtime-smoke` + 手动不同窗口尺寸检查 |
| 改暂停 / 保存续局 | `client/scripts/ui/pause_menu.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、`formal_client_boot.gd` | 本文档、SaveManager / FormalClientBoot 文档 | `runtime-smoke` + `save-smoke` + L5 暂停 / 存档 checklist |
| 改模块世界 / 模板 / 流式状态 | `module_worlds.json`、`module_templates.json`、`modules/*.json`、`module_world_manager.gd`、`module_chunk.gd`、`gameplay_run_loop.gd` | `client/data/README.md`、本文档、`docs/代码/module_world_manager.md` | `sync_contracts --check` + `validate_data` + `test_data_loader_schema` + `module-world-smoke` + `save-smoke` |
| 改普通新局 / 重开 seed | `client/scripts/autoload/rng.gd`、`client/scripts/boot/formal_client_boot.gd`、`client/tools/l1_smoke.gd` | 本文档、RNG / FormalClientBoot 文档、ADR、AI记忆 | `l1-smoke` + `runtime-smoke` + `save-smoke` + checked-in replay runner 抽查 |
| 改设置入口 / 设置叠层 | `title_menu.gd`、`pause_menu.gd`、`settings_panel.gd`、`formal_client_boot.gd`、`gameplay_run_loop.gd` | 本文档、Settings / UIManager / FormalClientBoot 文档 | `settings-smoke` + `runtime-smoke` |
| 改失败页 / 死亡清理 | `client/scripts/gameplay/gameplay_run_loop.gd`、`client/scripts/ui/game_over_panel.gd` | 本文档、SaveManager 文档 | `runtime-smoke` + `save-smoke` |
| 改标题装备 Mod 入口 / 面板 | `client/scenes/ui/title_menu.tscn`、`client/scenes/ui/gear_mod_panel.tscn`、对应脚本、`client/scripts/boot/formal_client_boot.gd`、`client/scripts/autoload/gear_mod_system.gd` | 本文档、FormalClientBoot / GearModSystem 文档 | `headless-boot` + `gear-mod-smoke` + 手动标题菜单点开 |
| 改旧局外升级删除边界 | `client/scenes/ui/title_menu.tscn`、`client/scripts/ui/title_menu.gd`、`client/scripts/boot/formal_client_boot.gd`、`client/project.godot` | 本文档、FormalClientBoot / GearModSystem / SaveManager 文档 | `headless-boot` + `runtime-smoke` + `gear-mod-smoke` |
| 改 GM 指令影响运行时 | `client/scripts/debug/gm_command_registry.gd`、`client/scripts/gameplay/gameplay_run_loop.gd`、目标系统脚本 | 本文档、DebugTools 文档、测试策略 | `debug-tools-smoke` + `debug-tools-release-smoke`，必要时追加 `runtime-smoke` / `gear-mod-smoke` |
| 改运行时行为 | `client/scripts/gameplay/*.gd` | 本文档、必要时 GDD / ADR | L0 + L2 + `runtime-smoke`，必要时补 L1 |
| 改鼠标 / 手柄瞄准手感或俯视相机 / 地图显示参数 | `client/scripts/gameplay/player.gd`、`gameplay_run_loop.gd/.tscn`、`gameplay_camera_controller.gd/.tscn`、`world_background.gd`、`weapon_system.gd`、`client/tools/runtime_smoke.gd` | 本文档、Phantom Camera 文档、GDD、ADR、测试策略 | `lint_gdscript_rules` + `lint_semantic_rules` + `actor-scene-smoke` + `settings-smoke` + `runtime-smoke` |

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
| 模块首次进入不刷怪 / 无预警 | 是否真正进入新模块而非仅进入 3×3 活跃邻域；起点是否被正确豁免；`first_visit_enemy_spawn` 是否通过数据校验；空地数是否足够；槽位 `enemy_encounter.state` 是否为 `telegraphing/spawned`；敌人池和 `presentation_module_encounter` 是否已注册 |
| 开放战区不刷怪 | `spawn_waves.csv` 时间窗、预算、`max_alive` 是否允许；敌人池是否注册；F12 7 分钟才打开 bulwark |
| 特定阶段不刷预期 wave | `warzone_directors.json.phases[].wave_ids` 是否包含该 wave；`debug_summary().warzone_director.phase_id` 是否符合当前时间；9 分钟后应处于软加压 `phase_overtime_collapse` |
| 战区兴趣点机关不出现 | `warzone_directors.json.interest_points[].map_layout_id` 是否匹配当前 layout；`hazard_ids[]` 是否非空且引用存在；`debug_summary().map.hazard_sources.director` 是否大于 0 |
| 兴趣点不领奖 | `claim_radius` 是否大于 0；`claim_start_time` 是否已到；无 `target_hp` 时玩家是否进入 `debug_summary().interest_points[point_id].position` 附近；若 `requires_interaction=true`，HUD 是否出现交互提示且玩家是否按了 `interact` action；有 `target_hp` 时目标是否被摧毁；奖励 id 是否通过 DataLoader schema |
| 小巢核领取后不出现结果面板 | `completes_run` 是否为 `true`；`target_hp` 目标是否被摧毁或已领取；撤离区是否激活；玩家是否站进撤离区并完成 `extraction_hold_time`；`GameOverPanel.configure(..., completed=true)` 是否在撤离成功后调用；当前 `run` 存档是否被删除；`pending_loot` 是否已提交 |
| 模块 assignment / hash 不稳定 | world seed、approved 模板池顺序、rotation 与固定锚点是否一致；是否绕过 `RNG.world`；`module-world-smoke` 是否通过 |
| 跨模块卡住 / 出界 | 相邻模块旋转后是否至少有一个共同开放边缘格；完整 99×99 flood-fill 是否通过；外圈是否封闭；`ModuleChunk` 合并碰撞是否重建；`MapManager.bounds()` 与 99×99 格配置是否一致 |
| 返回模块重复刷怪 / 预警重置 / 领奖 | 首次进入时是否立即把计划和剩余时间写入 `enemy_encounter`；卸载时是否只取消 VFX 并保留槽位状态；激活时是否恢复同一计划而非再次消耗 `RNG.spawn`；敌人快照和奖励领取状态是否按槽位保存 |
| 玩家走出地图 | `MapManager.bounds()` 是否配置；`Player.set_movement_bounds()` 是否调用；`map_layouts.json.bounds` 是否是 grid 的整数倍 |
| 敌人走出地图 | `MapManager.bounds()` 是否配置；`GameplayRunLoop._apply_enemy_movement_bounds()` 是否在生成 / 续局恢复时调用；`Enemy.set_movement_bounds()` 是否在移动、分离和快照恢复后 clamp |
| 机关不出现 | `map_layouts.json` 是否生成 placement；`hazards.csv.pool_id` 是否已注册；`runtime-smoke` 是否通过 active hazards 断言 |
| FEA-12 不伤害玩家 | 玩家是否在机关矩形范围内；是否命中护盾门 / 冲刺无敌；`hazards.csv.damage` / `element_id` 是否有效；`f9-demo-smoke` 是否通过 |
| 机关续局后位置变化 | run payload 是否包含 `map.hazard_placements` 与 `hazards`；恢复是否误重新消耗 `RNG.world` |
| 普通新局 seed 总是一样 / replay 变随机 | 普通开始 / 重开是否走 `FormalClientBoot._start_new_gameplay_run()`；继续、replay runner、golden capture 和 smoke 是否仍走恢复 / 固定 seed 路径 |
| 第二敌人不出现 | `enemies.csv.pool_id` 是否为已注册池；`game_modes.json.resource_pools.enemies` 与 `spawn_waves.csv.enemy_id` 是否引用该敌人；`runtime-smoke` 是否通过第二敌人池断言 |
| 敌人错误锁定或伤害其他敌人 | `_sense_context()` 是否只构造玩家候选；`Enemy.receive_damage()` 是否仍拒绝 `team_enemy` 来源；runtime smoke 的玩家目标、友伤和中心分离断言是否通过 |
| 敌人中心完全重叠 | `enemies.csv.separation_radius` 是否为 0；`runtime-smoke` 是否通过中心分离断言 |
| 敌人中心贴到玩家中心 | `player.json.base_stats.player_separation_radius` 是否为 0；`Enemy` 是否仍调用玩家中心排斥；`runtime-smoke` 是否通过玩家-敌人分离断言 |
| 子弹打不到 | `hit_radius`、敌人位置、`bullet_range` / `lifetime` 是否合理 |
| 子弹穿墙或在墙前异常消失 | `ModuleChunk.TerrainCollision` 是否显式位于 bit 1；Bullet 查询 mask / 圆形半径 / 首帧重叠 / `cast_motion()` 是否正常；快照 `wall_pierce_enabled` 是否符合发射时能力；不要把 `pierce_count` 当穿墙开关 |
| 突击枪手预警后转向或点射数量错误 | Enemy ranged windup / burst 是否只读锁定方向；`burst_shots_remaining` 是否从 4 逐发减一；每轮是否只发一次 windup、每弹一次 commit，最后一发后是否进入 0.95 秒冷却 |
| 玩家子弹变红或敌弹变黄 | `Bullet._refresh_visuals()` / `_resolve_trail()` 是否按 `source_team` 切换；configure / reset / release 是否同时清空玩家与敌方 trail 历史 |
| 敌人身体贴住玩家仍扣血 | `Enemy` 是否残留接触检测；CSV 是否错误恢复旧 contact 表头；伤害是否只在 attack commit 触发 |
| 爆猎者前摇后被打断 | armed 是否在同一帧启用、碰撞是否关闭、`receive_damage()` 是否早退 |
| 连锁奖励 / RNG 顺序漂移 | 爆炸是否先冻结目标并按 `runtime_spawn_serial` 结算 |
| 玩家击杀不掉金币 | Enemy 的 `reward.gold_reward` 是否为正；生成时是否在 acquire 成功后解析；致命伤 `source_team` 是否为 `team_player`；`gold_orb` 池是否注册 |
| 同一敌人跨阶段或续局后金币变化 | 奖励是否在生成时写入 Enemy 快照；恢复是否错误调用 resolver 或消费 `RNG.economy`；死亡不得重新读取当前 difficulty |
| 打空后持续按住仍自动换弹 / 自动恢复 | 检查 `_empty_trigger_latched` 是否只在 release 清除；拾取弹药不得替玩家制造新的开火边沿 |
| 完全没生成子弹却扣弹 / 扰动随机 | `_fire_once()` 必须先成功 acquire 至少一个 `bullet_basic`，再消费 `RNG.combat`、弹药和冷却 |
| 满弹仍改变后续掉率 | 调用 `RNG.ammo` 前必须先检查 `WeaponSystem.can_accept_ammo()`；满弹不抽取、不推进 `ammo_drop_misses` |
| 金币拾取后等级 / 余额不对 | `GoldProgression.add_gold()` 的原因是否为已登记 id；`level_progression.json` 是否仍为 100、13/10；消费是否误改 `gold_earned_total` |
| 奖励面板不出现或无法选择 | 请求是否在 `PLAYING`、候选数是否为 2–5、池 / trigger 是否登记且合格候选充足；成功后 `GameState` 应为 `REWARD_CHOICE`、`UIManager.top()` 应为 `RewardChoicePanel` |
| 奖励界面按暂停键无反应 | `RewardChoicePanel.pause_requested` 是否连接到 `GameplayRunLoop._on_reward_choice_pause_requested()`；奖励面板是否是 `UIManager.top()`；`pause` action 是否已注册 |
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
| 继续游戏后状态不对 | Run v11 是否包含弹药 / 换弹 / 弹匣、难度 profile / 系数、世界事件、pin、波次计划、敌人归属 / target mode、既有攻击和奖励字段；是否按依赖顺序恢复且未重复提交 |
| 准备期间已能移动 / 计时 | 是否在 `run_prepared` 前切到 `PLAYING`，或在加载界面仍存在时调用了 `activate_prepared_run()` |
| 加载动画停止 | 大批量主线程工作是否使用 staged 路径并在批次间 `await process_frame`；是否误用阻塞资源加载或自管线程 |
| 继续游戏后状态效果丢失 | 玩家 / 敌人 / 技能快照是否包含 `status_effects` 与 `owned_tag_counts`；恢复已有 tag 计数时是否避免状态组件重复授予 tags |
| 池化敌人带着上一只怪的状态 | `Enemy.configure()`、`_pool_release()`、`_pool_reset()` 是否调用状态清理；L1 是否覆盖 configure 复用后旧状态被清空 |
| GM 命令没有生效 | 当前是否为 debug/dev_tools 构建；`DebugConsole` 是否存在；命令是否通过 `GameplayRunLoop.debug_*` / `GearModSystem.debug_*` 受控 API，而不是直接改节点 |
| 测试岛进入普通模块世界 / 结算 | `configure_debug_test_arena()` 是否在入树前调用；`RunPurpose` 分支是否在准备、process、死亡、击杀和 snapshot 路径完整 guard |
| 测试岛污染正式存档 | 测试用途是否误调用 SaveManager / GearMod profile API；跑 `debug-test-arena-smoke` 的 meta/run 哨兵断言 |
| 固定靶移动或对象池串状态 | `Enemy.configure()` 后是否调用训练靶配置；`_pool_reset()` / `_pool_release()` 是否清掉测试 metadata 与 AI 开关 |

## 测试义务

- Gameplay runtime 代码改动必跑：`python tools/lint_gdscript_rules.py`、`python tools/lint_semantic_rules.py`、`python tools/godot_bridge.py --project client headless-boot`。
- Gameplay runtime / UI 场景结构改动还必须跑 `python tools/godot_bridge.py --project client runtime-smoke`，涉及标题 Gear Mod 面板时追加 `gear-mod-smoke`。
- 涉及启动、输入、WeaponSystem、SkillSystem、子弹、敌人、EnemyAI、Spawner、金币球、金币成长、奖励选择、Combat 或失败状态时追加 `python tools/godot_bridge.py --project client runtime-smoke`。
- 改角色挂点、表现 cue、命中 / 退场、VfxHost 或回池边界时追加 `vfx-smoke` 与 `actor-scene-smoke`；回放 summary 和 gameplay RNG 不得因纯表现变化而改变。
- 涉及有限地图、`map_layouts.json`、PCG 摆放、WarzoneDirector 兴趣点接入、手工机关摆点、HazardSystem 或 `hazards.csv` 时追加 `python tools/godot_bridge.py --project client runtime-smoke`、`python tools/godot_bridge.py --project client f9-demo-smoke`；涉及兴趣点奖励、`GearModSystem` 资源 / Mod 发放或完成面板时追加 `gear-mod-smoke` 与 `save-smoke`；涉及 run 快照恢复时追加 `save-smoke`。
- 涉及技能目标、资源、冷却、效果解释或 run 技能快照时追加 `python tools/godot_bridge.py --project client l1-smoke`；改 run 快照恢复还要追加 `save-smoke`。
- 涉及 Player / Enemy 状态宿主、owned ability tag 或实体状态快照时追加 `python tools/godot_bridge.py --project client l1-smoke`、`python tools/godot_bridge.py --project client runtime-smoke` 与 `python tools/godot_bridge.py --project client save-smoke`；对象池状态清理变化还要检查复用路径。
- 涉及 gameplay 输入录制、`Replay` 输入事件、奖励选择 decision、暂停 / 返回 action 录制时追加 `python tools/godot_bridge.py --project client replay-input-smoke`；奖励选择基线使用 `golden_reward_choice` 显式发起请求，标准模式仍应断言升级不自动进入 `REWARD_CHOICE`。
- 涉及暂停、保存退出、标题继续、坏档提示、RNG / GameClock 快照或 run payload 时必须追加 `python tools/godot_bridge.py --project client runtime-smoke` 与 `python tools/godot_bridge.py --project client save-smoke`，并做至少一次手动保存续局检查。
- 涉及玩家加载模式、线程资源读取、分帧预热 / 恢复、准备 / 激活边界或失败清理时，必须追加 `python tools/godot_bridge.py --project client loading-smoke`，并按 `docs/代码/gameplay_loading.md` 跑 actor、module-world full / technical 与四条 checked-in golden replay。
- 涉及普通新局 / 重开 seed 策略时，追加 `python tools/godot_bridge.py --project client l1-smoke`、`runtime-smoke`、`save-smoke` 和至少一条 checked-in replay runner，确认玩家入口随机化但工具 / replay 固定 seed 路径不漂移。
- 涉及标题 / 暂停设置入口、设置面板关闭、`ui_back` 返回或运行时语言刷新时，追加 `python tools/godot_bridge.py --project client settings-smoke` 与 `python tools/godot_bridge.py --project client runtime-smoke`。
- 涉及 `meta.gear_mods` 存档结构、Gear Mod loadout、掉落、升级、分解或下一局 modifier snapshot 时追加 `python tools/godot_bridge.py --project client gear-mod-smoke`；如果改了 F4 死亡接入、敌人击杀归因或失败面板，同时跑 `runtime-smoke`。
- 涉及 GM 指令或 runtime debug API 时，追加 `python tools/godot_bridge.py --project client debug-tools-smoke` 与 `python tools/godot_bridge.py --project client debug-tools-release-smoke`；命令影响局内战斗时追加 `runtime-smoke`。
- 涉及 `DEBUG_TEST_ARENA`、训练靶、作弊、伤害统计、测试岛死亡或存档 / 服务隔离时，必跑 `debug-test-arena-smoke` 与 `debug-tools-release-smoke`；正式 Player / Weapon / Skill / Enemy / Combat / Pool 适配变化追加 runtime、save、Gear Mod、L1、actor、完整 / 技术切片 module-world 和四条黄金回放。不得自动运行性能 probe。
- 涉及模块世界、事件 placement、chunk / pin、迷雾、地图 hash 或 Run v11 恢复时，追加 `world-event-smoke`、`module-world-smoke` 与 `save-smoke`，并跑 contracts、data 和 schema 检查。
- 涉及子弹地形阻挡、`wall_pierce` 或子弹能力快照时，必须跑完整与技术切片 `module-world-smoke`、`runtime-smoke`、`save-smoke`、`l1-smoke`、正式 headless boot 和四条黄金回放；契约或武器字段变化追加双端 schema 与契约同步。
- 数据 / locale 变化还要跑 `python tools/validate_data.py`、`python tools/lint_project_rules.py`。
- 地图 / 机关数量、对象池生命周期或性能相关变化仍按对应功能 smoke 验证；影响稳定运行时摘要时重跑 checked-in golden replay runner。`startup-probe` / `perf-probe` 只有用户当次明确要求性能测试时才追加。
- 当前没有 GUT runner，F4 首切片用 L0 + L2 + `runtime-smoke` + 手动 1 分钟跑通作为阶段门槛；后续接入 Godot 测试时补 Player / Combat / Pool / Spawner 的 L1。

## 迁移 / 兼容

当前 `SaveManager` 的 `run` envelope 与 gameplay payload 均为 v11；保存既有战斗 / 经济 / 模块 / 世界事件事务、难度 profile、敌人奖励，以及弹药 / 换弹 / 掉率 / 弹匣拾取状态。v10 因缺少武器弹药、`RNG.ammo` 和场上弹匣状态不做有损迁移：迁移器设置 `legacy_run_incompatible=true`，正式启动显示提示、删除该 run 并要求新开；Meta v2、Gear Mod 资产与 loadout 保持不变。死亡仍删除 run 并丢失 `pending_loot`；撤离成功先结算暂存战利品再删除 run。不得保存对象池内部状态或节点引用。

## 相关文档

- `docs/AI协作/工作包/F4-MinPlayableLoop.md`
- `docs/AI协作/工作包/F13-ModularGridWorld.md`
- `docs/正式项目工作规划.md` F4
- `docs/代码/phantom_camera.md`
- `docs/代码/gameplay_loading.md`
- `docs/代码/debug_tools.md`
- `docs/代码/debug_test_arena.md`
- `docs/游戏设计文档.md` §3 / §4 / §5.3 / §9.13 / §9.15.1
- `docs/代码/combat.md`
- `docs/代码/map_manager.md`
- `docs/代码/module_world_manager.md`
- `docs/代码/world_event_system.md`
- `docs/代码/hazard_system.md`
- `docs/代码/skill_system.md`
- `docs/代码/gear_mod_system.md`
