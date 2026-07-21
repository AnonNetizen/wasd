# WarzoneDirector 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 F10 敌巢战区导演的代码契约权威；改导演数据 schema、阶段解释、刷怪接线、调试摘要或兴趣点生成时，必须同步 `docs/AI协作/工作包/F10-WarzoneDirector.md`、`docs/代码/gameplay_runtime.md`、`docs/代码/data_loader.md`、`client/data/README.md`、GDD 与 ADR。

## 职责

- 读取 `client/data/warzone_directors.json` 中与当前模式匹配的导演配置。
- 按 `GameClock.now()` 对局内时间解释固定阶段。
- 判断某个 `spawn_waves.csv` wave 是否在当前阶段被允许。
- 按当前 `map_layout_id` 输出可用于初始地图机关生成和 F12 奖励领取的兴趣点。
- F12 标准模式用 0-1 / 1-4 / 4-7 / 7-9 / 9+ 分钟阶段组织短刷图节奏；9 分钟后是软加压，不是硬性结束。
- 输出 debug summary，供 smoke、DebugTools 或后续平衡诊断查看当前 director / mutation / phase / wave / interest point。
- 保持首片确定性：不随机、不读玩家状态；奖励领取状态由 `GameplayRunLoop` 保存，不由导演保存运行时状态。

## 非职责

- 不读取玩家生命、DPS、受伤次数、击杀速度、输入节奏或其它玩家表现指标。
- 不做隐藏动态难度，不临时改伤害、掉落、敌人属性或地图。
- 不直接实例化敌人或机关；地图兴趣点只作为数据交给 `MapManager` 通用 placement 规则解释。
- 不播放 UI / 音频，不显示玩家可见文案。

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/warzone_director.gd` | `WarzoneDirector` 实现，`RefCounted` 数据解释器 |
| `client/data/warzone_directors.json` | schema v2 导演、mutation、phase、wave gating、interest point 数据 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 创建导演、把 `debug_summary()` 暴露给运行时摘要、在 `_update_spawner()` 调用 `is_wave_enabled()`、把当前 layout 的兴趣点传给 `MapManager` |
| `client/scripts/autoload/data_loader.gd` | Godot 侧 schema 校验 |
| `tools/validate_data.py` | Python 侧数据校验 |
| `tools/test_data_loader_schema.py` | 坏样例回归：导演引用不存在的 wave、空兴趣点机关列表、非法兴趣点奖励必须 fail-fast |
| `client/tools/runtime_smoke.gd` | 验证开局 insertion phase 摘要、F12 四个兴趣点、director-sourced 地图机关、兴趣点奖励领取和小巢核完成面板 |
| `client/tools/f9_demo_smoke.gd` | 验证 7 分钟小巢核 phase 仍允许 bulwark wave，且 FEA-12 兴趣点进入地图 |

## 数据契约

`warzone_directors.json` 是 schema v2 复杂 JSON：

- `schema_version` 必须为 `2`；旧顶层 encounter 数组和 phase encounter 引用必须被 Godot / Python schema 拒绝，不能静默忽略。
- `directors[].mode_id` 必须存在于 `game_modes.json`。
- 每个模式首片只允许一个 director。
- `phases[]` 必须非空、按时间升序、不重叠，且 `end_time > start_time`。
- `phases[].wave_ids[]` 必须引用同模式 `spawn_waves.csv` 中的 wave；同模式所有 wave 必须至少被一个 phase 引用。
- `interest_points[].hazard_ids[]` 必须是非空数组，且每项存在于 `hazards.csv`。
- `interest_points[].map_layout_id` 必须存在于 `map_layouts.json`。
- `interest_points[].min_distance_from_player` / `min_spacing` 为可选摆放约束，由 `MapManager` 解释；首片用它们把精英巢点、Mod 缓存、资源缓存和小巢核分散到战区中。
- `interest_points[].claim_radius` / `claim_start_time` 为 F12 领取约束，由 `GameplayRunLoop` 解释；有奖励或 `completes_run=true` 时必须提供正数 `claim_radius`。
- `interest_points[].requires_interaction` 为可选交互领取标记；为 `true` 时运行时生成贴合地图矩形格的 `InterestPointCache`，玩家进入 `claim_radius` 后按 `interact` action 打开并触发同一套暂存奖励。
- `interest_points[].target_hp` / `target_hit_radius` 为可选可伤害目标数值；存在 `target_hp` 时运行时生成贴合地图矩形格的 `InterestPointTarget`，目标一生成即可被子弹 / `Combat` 摧毁并触发同一套奖励，`claim_start_time` 只继续约束无目标兴趣点的进圈领取。
- `interest_points[].resource_rewards[]` 必须引用 `gear_mod_resources`；`gear_mod_rewards[]` 必须引用 `gear_mods.json` 中存在的 `gear_mod_ids`；领取时分别走 `GearModSystem.grant_resource()` 与 `grant_mod()`。
- `interest_points[].extraction_radius` / `extraction_hold_time` 为 F12 撤离约束；`completes_run=true` 时必须提供正数，运行时用它们开启贴合地图格的撤离区和读条。
- `interest_points[].completes_run` 为可选 bool；为 `true` 时领取后只开启撤离区，玩家完成撤离读条后才提交暂存战利品、进入完成结果面板并删除当前 `run` 存档。

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(target_mode, data, waves)` | `String`, `Dictionary`, `Array[Dictionary]` | `void` | 只缓存数据拷贝；空数据表示未配置，所有 wave 默认允许 |
| `is_configured()` | 无 | `bool` | 供调试判断是否找到 director |
| `is_wave_enabled(wave_id, elapsed)` | `String`, `float` | `bool` | 未配置时返回 `true`；已配置时只看当前 phase 的 `wave_ids` |
| `current_phase(elapsed)` | `float` | `Dictionary` | phase 起点包含、终点除最后阶段外不包含；最后阶段终点包含 |
| `interest_points_for_layout(layout_id)` | `String` | `Array[Dictionary]` | 返回 `map_layout_id` 为空或匹配当前 layout 的兴趣点深拷贝 |
| `debug_summary(elapsed)` | `float` | `Dictionary` | 返回 director、mutation、phase、pressure、wave 和 interest point 摘要；不返回旧 encounter 元数据 |

## 运行流程

1. `GameplayRunLoop._start_run()` 先读取 mode、敌人、地图、成长和 `spawn_waves.csv`。
2. `GameplayRunLoop` 读取 `DataLoader.WARZONE_DIRECTORS_PATH`，选择当前 mode 的 director。
3. `WarzoneDirector.configure()` 缓存 phases / interest_points。
4. 开局生成地图机关时，`GameplayRunLoop` 用 `interest_points_for_layout(layout_id)` 取当前地图兴趣点，并传给 `MapManager.generate_hazard_placements()`。
5. `MapManager` 为每个兴趣点的 `hazard_ids[]` 走通用 PCG 规则生成 `source="director"` placement，并透传 `claim_radius`、奖励数组、交互标记、可伤害目标数值、`completes_run` 和撤离数值等兴趣点元数据。
6. `GameplayRunLoop` 从 placement 重建兴趣点状态；无目标且不要求交互的兴趣点每帧只按 `GameClock.now()`、玩家位置和 `claim_radius` 判断能否领取；要求交互的兴趣点生成可见 `InterestPointCache`，玩家在半径内按 `interact` 领取；有目标的兴趣点生成可伤害 `InterestPointTarget`，目标被摧毁后领取；小巢核领取后开启撤离区，撤离完成才提交暂存战利品，不读取玩家表现数据。
7. 每帧 `GameplayRunLoop._update_spawner()` 先询问 `is_wave_enabled(wave_key, GameClock.now())`，被当前 phase 禁用的 wave 直接跳过。
8. 通过导演后，原有 wave 时间窗、预算、同时存活上限和对象池生成逻辑继续执行。

## 依赖

- 上游依赖：`DataLoader`、`GameClock`、`spawn_waves.csv`、`warzone_directors.json`。
- 下游调用方：`GameplayRunLoop`、`MapManager` 初始机关生成、`GameplayRunLoop.debug_summary()`、`runtime-smoke`、`f9-demo-smoke`。
- 禁止依赖：`Player`、`WeaponSystem`、`Combat` 结果、HUD 输入、FPS / 性能指标或任何玩家表现数据。

## 扩展点

- 随机 mutation：必须先决定 RNG stream、保存 / 恢复策略和 replay 影响；首片不做。
- 地图兴趣点生成：已接入 `MapManager` 的数据化生成接口；F12 首片已有 `poi_elite_nest`、`poi_mod_cache`、`poi_resource_cache`、`poi_minor_nest_core` 四个调试语义点位，并通过通用 `resource_rewards[]` / `gear_mod_rewards[]` 表达 dust / Mod 奖励，通过 `requires_interaction` 表达缓存箱交互领取，通过 `target_hp` / `target_hit_radius` 表达可伤害巢点 / 巢核目标，通过 `extraction_radius` / `extraction_hold_time` 表达小巢核后的撤离区。后续扩展 kind / 奖励语义仍不能按 `poi_id` 或 `hazard_id` 写特殊分支。
- 敌人组合由 `spawn_waves.csv` 或 F13 模块 JSON 负责；导演不再维护额外敌人组合元数据。
- 玩家可见主题：新增 name / desc 前先补 `client/locale/strings.csv`，数据只存 locale key。

## 常见改动入口

| 你想改什么 | 主要文件 | 验证 |
|------------|----------|------|
| 调阶段时间 / wave 组合 | `client/data/warzone_directors.json` | `validate_data`、`test_data_loader_schema`、`runtime-smoke`、`f9-demo-smoke` |
| 新增 interest point | `warzone_directors.json`、必要时 `map_layouts.json` / `hazards.csv` | `validate_data` + `test_data_loader_schema`；兴趣点影响地图时追加 runtime / F9 smoke |
| 调兴趣点奖励 / 交互 / 目标 / 小巢核撤离完成 | `warzone_directors.json`、`gameplay_run_loop.gd`、`interest_point_cache.gd`、`interest_point_target.gd`、`gear_mod_system.gd` | `validate_data` + `test_data_loader_schema` + `runtime-smoke` + `gear-mod-smoke` + `save-smoke` |
| 改 schema | `data_loader.gd`、`validate_data.py`、`test_data_loader_schema.py`、本文档、数据手册 | schema test + docs health |
| 让导演影响地图 | `warzone_director.gd`、`map_manager.gd`、`gameplay_run_loop.gd` | runtime-smoke、f9-demo-smoke、save-smoke，评估 golden；性能 probe 仅由用户明确触发 |

## 测试义务

- 改数据或 schema：`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`。
- 改 GDScript：`python tools/lint_gdscript_rules.py`、`python tools/godot_bridge.py --project client runtime-smoke`。
- 改 7 分钟小巢核压力、9 分钟后软加压或 FEA-12 兴趣点：追加 `python tools/godot_bridge.py --project client f9-demo-smoke`。
- 改兴趣点奖励、`claim_radius`、`requires_interaction`、`completes_run`、撤离数值或结果面板：追加 `python tools/godot_bridge.py --project client runtime-smoke`、`gear-mod-smoke` 与 `save-smoke`。
- 改兴趣点地图生成接线：追加 `python tools/godot_bridge.py --project client save-smoke`，并跑 checked-in golden replay runner 评估行为漂移；`perf-probe` 仅在用户明确要求性能测试时运行。
- 若引入随机 mutation、run snapshot 字段或 replay summary 变化，必须追加对应 save / replay runner 并更新 ADR。

## 迁移 / 兼容

导演当前由静态数据和 `GameClock.now()` 推导，本身不保存状态。schema v2 删除的旧导演敌人组合元数据不进入 run payload，因此不需要提升 run schema。F12 奖励领取状态保存于 run payload 的可选 `interest_points` 字段，撤离开启 / 读条状态保存于可选 `extraction` 字段；旧 payload 缺失这些字段时按未领取 / 未开启撤离处理，旧 `map.hazard_placements` 缺少奖励或撤离元数据时只恢复机关，不补发奖励也不开启撤离。后续若加入随机 mutation、阶段内部计数器或玩家可见选择，必须保存 director state 并同步 `GameplayRunLoop.create_run_snapshot()` / `configure_restore_snapshot()`。
