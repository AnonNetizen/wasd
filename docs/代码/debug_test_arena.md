# Developer Test Arena 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是正式项目内“开发者测试岛”的代码契约；改独立场景入口、运行用途、配装配置、训练靶、控制面板、伤害统计、存档隔离或 release 导出边界时，必须同步 ADR #159 / #160、GDD §9.20、DebugTools / Gameplay Runtime / FormalClientBoot / GearModSystem 文档、测试策略、AI 导航和 AI 记忆。

## 职责

- 在正式 `client/` 的 debug/dev_tools 构建中提供可重复的战斗验证场地，借鉴英雄演示 / sandbox 的开发体验，但不复刻第三方地图、UI、名称或素材。
- 作为可由 Godot 直接运行当前场景的独立工具启动，不挂接标题菜单、`FormalClientBoot` 或正式游戏 CLI。
- 复用真实 `Player`、`WeaponSystem`、`SkillSystem`、`Enemy` / `EnemyAI`、`Combat`、`PoolManager`、VFX 和 Gear Mod modifier 链路。
- 提供入场前配装、固定训练靶、正常 AI、作弊控制、死亡复位和只读伤害统计。
- 把开发配置、正式 `meta` / `run`、Replay / Analytics 和 release 资源边界明确隔离。

## 非职责

- 不是正式 game mode，不进入 `game_modes.json`，不新增 save kind、pool id 或 input action。
- 不接经验、升级选择、遗物、主动道具、消耗品、机关、兴趣点、巢核、撤离、奖励结算或正式 Game Over。
- 不支持局内热切换角色、武器、主技能或 Gear Mod；改变配装必须重建测试局。
- 不替代完整试玩、黄金回放、平衡 sim 或性能测试。

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scenes/debug/debug_test_arena.tscn` / `client/scripts/debug/debug_test_arena_host.gd` | 唯一独立入口；先打开配装，再创建 / 重建 runtime，管理服务隔离和退出 |
| `client/scenes/debug/debug_test_arena_run.tscn` | 继承正式 `gameplay_run_loop.tscn`，预置测试岛控制器、三区地面、边界、出生点和伤害 HUD |
| `client/scripts/debug/debug_test_arena_controller.gd` | 目标生成、控制动作、死亡复位、伤害统计和面板生命周期 |
| `client/scenes/debug/debug_test_arena_control_panel.tscn` / 对应脚本 | UIManager 管理的暂停控制面板 |
| `client/scenes/debug/debug_test_arena_setup.tscn` / 对应脚本 | 数据驱动配装界面和开发配置保存 |
| `client/scenes/debug/debug_test_arena_mod_row.tscn` / 对应脚本 | Gear Mod 重复行模板 |
| `client/scripts/debug/debug_test_arena_config.gd` | `user://debug_test_arena.cfg` schema v1、回退诊断和内容列表 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 内部 `DEBUG_TEST_ARENA` 运行用途及受控 arena API |
| `client/scripts/gameplay/player.gd` / `weapon_system.gd` / `skill_system.gd` / `enemy.gd` | 无敌、免费释放、刷新、训练靶 AI 开关与复位的最小 debug API |
| `client/scripts/autoload/gear_mod_system.gd` | 不读取 / 写入 SaveManager 的纯 `resolve_preview_loadout()` |
| `client/tools/debug_test_arena_smoke.gd` | 隔离用户目录的端到端 smoke |
| `tools/godot_bridge.py` | `debug-test-arena-smoke` 命令 |
| `tools/release_debug_resource_check.gd` | 挂载临时 release PCK 并确认调试目录 / smoke 路径不存在 |

## 场景与区域

```text
DebugTestArena (standalone host)
└── DebugTestArenaRun (inherits GameplayRunLoop; runtime-created)
    ├── ActiveWorld
    │   └── ArenaVisuals
    │       ├── CentralZone
    │       ├── StationaryZone
    │       ├── AiZone
    │       └── Boundary / localized labels
    └── DebugTestArenaController
        └── StatsHud
```

- 中央出生区：玩家进入、传送和死亡复位点。
- 固定靶区：生成真实敌人场景，关闭 AI，生命上限使用场景导出值（默认 `1,000,000`），只允许手动复位。
- AI 实战区：生成正常 EnemyAI，继续移动、感知和攻击玩家。
- 两区目标都走现有敌人独立池；不创建测试专用敌人类型或 pool id。

## 运行流程

| 阶段 | 行为 |
|------|------|
| 独立入口 | 在 Godot 中直接运行 `debug_test_arena.tscn`；host 仅接受 debug 或 `dev_tools` 构建，并先验证正式项目数据 |
| 配装入口 | 每次启动先通过 UIManager 打开上次配置的 setup；没有标题菜单或正式 `--debug-test-arena` 启动路径 |
| 配置归一化 | 正 seed、角色、武器、主技能与 Gear Mod/rank 被校验；无效 id 回退到首个合法内容并写诊断 |
| Runtime 配置 | host 实例化 `debug_test_arena_run.tscn`，并在入树前调用 `configure_debug_test_arena()`；内部运行用途关闭模块世界、Spawner、导演、兴趣点、撤离、成长与普通结算 |
| 服务隔离 | host 启动时保存 Replay / Analytics enabled 状态并临时关闭；返回配装期间保持关闭，退出独立测试时幂等恢复 |
| 激活 | 玩家和正式战斗系统完成配置后，默认打开控制面板；面板通过 UIManager 暂停并接管输入 |
| 游玩 | 关闭面板后开始战斗；`pause` action 可重新打开面板 |
| 玩家死亡 | 清敌与弹体、恢复玩家 / 技能 / 武器、传回出生点、关闭作弊并重新打开面板，不进入 Game Over |
| 离开 | 返回配装会销毁 runtime、清空对象池并重建测试局；“退出测试”恢复服务并结束当前场景进程，不保存 run、meta、奖励或临时掉落 |

## 配装与开发配置

唯一持久文件是 `user://debug_test_arena.cfg`：

```ini
[arena]
schema_version=1
seed=424242
character_id="character_default"
weapon_id="weapon_basic_blaster"
primary_skill_id="skill_overdrive_rounds"
gear_mods=[{"mod_id":"gear_mod_weapon_damage_test","rank":0}]
```

- 配置使用 `ConfigFile`，不走 `SaveManager`，不触碰 `user://saves/`。
- 可用选择器从 `DataLoader` 动态列出角色、武器、技能和 Gear Mod；当前只有样例内容也不写死单项。
- 遗物、主动道具和消耗品只列出名称并明确显示“运行时尚未接入”，不可选择。
- 测试内容视为已解锁，不读取背包或货币。
- Gear Mod 容量固定复用正式默认值 8；`resolve_preview_loadout()` 执行 slot、`unique_by_id`、rank clamp、drain 和容量校验，输出 hero / weapon modifiers 与诊断。

## 控制面板

- 敌人：数据驱动选择敌人、固定靶 / 正常 AI、数量 1–50，并按实际数量居中为确定性网格，最大数量仍完整落在对应区域内。
- 清理：清固定靶、清 AI、全部清理、击杀 AI、复位固定靶。
- 玩家：治疗、无敌开关、免费技能开关、刷新技能资源 / 冷却 / 临时武器状态、传送回出生点。
- 场地：重置整个场地、清零伤害统计、返回配装、退出测试。
- 所有作弊开关每次进入默认关闭，不写入开发配置。
- UI 点击由 UIManager 的暂停模态层拦截，不应透传为移动、技能或射击输入。

## 伤害统计

控制器监听 `Combat.damage_applied(target, info, result)`：

- 只接受带测试岛目标 metadata 的 target。
- 只接受 `source_team == team_player` 且 `result.applied == true`、实际伤害大于 0 的事件。
- 显示最近一击、命中次数、累计有效伤害、最近 5 秒滚动 DPS 和活动目标数。
- DoT tick 只要保持玩家来源归因，就按每次有效 Combat 结果正常计入。
- 清零统计只清内存样本，不改目标生命或正式 analytics。

## 公共 API

| API | 用途 |
|-----|------|
| `DebugTestArenaConfig.available_content()` | 返回 setup 可展示的正式内容定义 |
| `load_config()` / `save_config()` / `normalize_config()` | 独立开发配置读写与回退诊断 |
| `GearModSystem.resolve_preview_loadout(selections, capacity)` | 纯内存解析合法 Mod/rank 与 hero/weapon modifiers |
| `DebugTestArenaHost.debug_active_setup()` / `debug_active_run_loop()` | smoke 只读查询当前独立场景阶段 |
| `DebugTestArenaHost.debug_service_state_before()` / `debug_exit_is_completed()` | smoke 验证服务恢复与退出完成 |
| `GameplayRunLoop.configure_debug_test_arena(config)` | 入树前选择内部运行用途与配装 |
| `debug_test_arena_spawn_at()` / `clear_targets()` / `kill_ai()` / `reset_stationary_targets()` | 受控目标生命周期 |
| `debug_test_arena_set_god_mode()` / `set_free_skills()` / `refresh_skills()` / `teleport_to_spawn()` | 玩家测试控制 |
| `debug_test_arena_reset_player()` / `clear_projectiles()` | 死亡与场地复位 |
| `debug_test_arena_summary()` | smoke 只读摘要 |

这些 API 是 debug/dev_tools 边界，不是正式 gameplay 扩展接口。普通 RunLoop 未配置为测试岛时必须拒绝或保持无副作用。

## Signal

| Signal | 来源 | 用途 |
|--------|------|------|
| `debug_test_arena_setup_requested` | `GameplayRunLoop` | 请求独立 host 销毁 runtime 并返回配装 |
| `debug_test_arena_exit_requested` | `GameplayRunLoop` | 请求独立 host 清理并退出测试 |
| `start_requested(config)` | setup | 保存成功后启动新测试局 |
| `closed_requested` | setup | 关闭配装并退出独立测试 |

## 存档、回放与埋点边界

- `create_run_snapshot()` 在测试用途返回空字典；测试岛不调用 run 保存 / 删除、正式奖励结算或 meta 写入。
- Gear Mod 掉落与击杀奖励路径在测试用途关闭；临时战斗状态只存在当前节点树。
- 测试岛不会读取或删除进入前已有的正式 run；之后单独启动正式游戏时，“继续游戏”仍按原存档判断。
- Replay / Analytics 只在测试岛生命周期内禁用，退出恢复进入前状态；测试操作不进入正式 replay 或 analytics。
- smoke 必须在隔离用户目录写 meta / run 哨兵并证明前后完全一致。

## Release 边界

- 正式标题场景、`FormalClientBoot` 和正式启动参数不得引用测试岛；`lint_project_rules.py` 对这三个入口执行零耦合检查。
- 唯一入口及内部 runtime 都位于 `scenes/debug/`，host / 控制 / 配置脚本都位于 `scripts/debug/`。
- release preset 必须排除 `scenes/debug/*`、`scripts/debug/*` 与两个 debug smoke 脚本的精确路径；不能依赖 Godot 不支持的中段文件名通配。
- `lint_project_rules.py` 会拒绝 release preset 缺少上述排除项、启用 debug/dev_tools feature 或显式包含调试资源；`debug-tools-release-smoke` 还会临时导出 release PCK 并从虚拟 `res://` 检查调试目录 / smoke 不存在。

## 依赖与禁止依赖

- 上游：`DataLoader`、`GearModSystem`、`GameplayRunLoop`、`UIManager`、`InputService`。
- 战斗：正式 Player / Weapon / Skill / Enemy、`Combat`、`PoolManager`、`GameClock`、VFX。
- 禁止：测试岛脚本直接读写正式存档、直接改敌人生命、直接实例化高频敌人、绕过 UIManager 暂停、使用裸随机 / 时间、向正式 game mode / save kind / action / pool 契约加测试 id。

## 常见改动入口

| 改动 | 主要文件 | 必验 |
|------|----------|------|
| 增加控制按钮 | control panel scene/script、controller、locale | 专用 smoke + 手动键鼠 / 手柄焦点 |
| 改配装字段 | config、setup、GearModSystem preview、本文档 | 配置回退 / 保存 + Gear Mod + save smoke |
| 改固定靶 | controller、Enemy debug API、arena scene | 固定靶不移动、真实受击、复位和对象池复用 |
| 改伤害 HUD | controller、HUD scene、Combat 过滤 | 直接伤害 + DoT + 非玩家来源拒绝 |
| 改死亡复位 | RunLoop、Player / Skill / Weapon debug API | 死亡不结算、不改 run/meta、面板重开 |
| 改独立启动 / release guard | host scene/script、export preset、project lint | arena smoke + release smoke + project lint |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| F6 没有先显示配装 | 是否运行 `debug_test_arena.tscn` 而非内部 `debug_test_arena_run.tscn`；host 的数据校验和 UIManager push 是否成功 |
| 独立场景立即退出 | 当前运行是否为 debug/dev_tools；host、setup 和 runtime 调试资源是否存在 |
| 固定靶移动 | `Enemy.debug_configure_training_target()` 是否关闭 AI；池复用时是否被 `configure()` 重置 |
| AI 不移动 | 是否生成在 `active_ai` 类型；面板是否仍暂停游戏 |
| 伤害不统计 | target metadata、`source_team`、Combat result 的 applied / damage |
| 退出测试后 Replay/Analytics 仍关闭 | host `_request_exit()` / `_exit_tree()` 是否走幂等 `_restore_services()` |
| 正式继续游戏消失 | 独立 host 是否误调用 `SaveManager`；先跑哨兵 smoke |
| release 带入测试资源 | 检查 export preset 的目录与 smoke 精确排除项、实际 PCK 检查和 project rules lint |

## 测试义务

- 专用必跑：`py -3 tools/godot_bridge.py --project client debug-test-arena-smoke`，成功标志必须精确为 `DEBUG TEST ARENA ALL PASS`，并拒绝脚本错误 / 致命日志。
- release 必跑：`debug-tools-release-smoke` + `lint_project_rules.py` + `test_project_rules_lint.py`。
- 改正式战斗适配：追加 runtime、save、Gear Mod、L1、actor scene、完整 / 技术切片 module-world 和四条 checked-in golden replay。
- 改 host / UI / locale：追加 loading、settings、独立 scene headless、正式 headless editor/boot、export-tree，并手动检查 1920×1080 的 `zh_CN` / `en`、键鼠与手柄焦点。
- 不因本模块自动运行 `startup-probe`、`perf-probe` 或 Profiler。

## 迁移与兼容

- 开发配置 schema 当前为 v1；未知 / 缺失版本按当前合法内容归一化并记录诊断，不迁移正式存档。
- 新增正式内容无需改选择器结构；只要 DataLoader 数据合法，就会自动进入对应列表。
- 遗物、主动道具、消耗品在运行时接线前必须继续保持禁用；接线属于新的设计 / API 变更，需要更新 ADR、测试与本文档。

## 相关文档

- `docs/决策记录.md` ADR #159 / #160
- `docs/游戏设计文档.md` §9.20
- `docs/代码/debug_tools.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/formal_client_boot.md`
- `docs/代码/gear_mod_system.md`
- `docs/测试策略.md` §5.10
