# WarzoneDirector 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 F10 敌巢战区导演的代码契约权威；改导演数据 schema、阶段解释、刷怪接线、调试摘要或兴趣点生成时，必须同步 `docs/AI协作/工作包/F10-WarzoneDirector.md`、`docs/代码/gameplay_runtime.md`、`docs/代码/data_loader.md`、`client/data/README.md`、GDD 与 ADR。

## 职责

- 读取 `client/data/warzone_directors.json` 中与当前模式匹配的导演配置。
- 按 `GameClock.now()` 对局内时间解释固定阶段。
- 判断某个 `spawn_waves.csv` wave 是否在当前阶段被允许。
- 按当前 `map_layout_id` 输出可用于初始地图机关生成的兴趣点。
- 输出 debug summary，供 smoke、DebugTools 或后续平衡诊断查看当前 director / mutation / phase / encounter / interest point。
- 保持首片确定性：不随机、不读玩家状态、不改变 run snapshot schema。

## 非职责

- 不读取玩家生命、DPS、受伤次数、击杀速度、输入节奏或其它玩家表现指标。
- 不做隐藏动态难度，不临时改伤害、掉落、敌人属性或地图。
- 不直接实例化敌人或机关；地图兴趣点只作为数据交给 `MapManager` 通用 placement 规则解释。
- 不播放 UI / 音频，不显示玩家可见文案。

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/gameplay/warzone_director.gd` | `WarzoneDirector` 实现，`RefCounted` 数据解释器 |
| `client/data/warzone_directors.json` | 导演、mutation、phase、encounter、interest point 数据 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 创建导演、把 `debug_summary()` 暴露给运行时摘要、在 `_update_spawner()` 调用 `is_wave_enabled()`、把当前 layout 的兴趣点传给 `MapManager` |
| `client/scripts/autoload/data_loader.gd` | Godot 侧 schema 校验 |
| `tools/validate_data.py` | Python 侧数据校验 |
| `tools/test_data_loader_schema.py` | 坏样例回归：导演引用不存在的 wave / 空兴趣点机关列表必须 fail-fast |
| `client/tools/runtime_smoke.gd` | 验证开局 warmup phase 摘要与 director-sourced 地图机关 |
| `client/tools/f9_demo_smoke.gd` | 验证 55 秒后 guarded phase 仍允许 bulwark wave，且 FEA-12 兴趣点进入地图 |

## 数据契约

`warzone_directors.json` 是复杂 JSON：

- `directors[].mode_id` 必须存在于 `game_modes.json`。
- 每个模式首片只允许一个 director。
- `phases[]` 必须非空、按时间升序、不重叠，且 `end_time > start_time`。
- `phases[].wave_ids[]` 必须引用同模式 `spawn_waves.csv` 中的 wave；同模式所有 wave 必须至少被一个 phase 引用。
- `phases[].encounter_ids[]` 必须引用同 director 的 `encounters[]`。
- `encounters[].enemy_tags[]` 必须来自 `content_tags`。
- `interest_points[].hazard_ids[]` 必须是非空数组，且每项存在于 `hazards.csv`。
- `interest_points[].map_layout_id` 必须存在于 `map_layouts.json`。

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `configure(target_mode, data, waves)` | `String`, `Dictionary`, `Array[Dictionary]` | `void` | 只缓存数据拷贝；空数据表示未配置，所有 wave 默认允许 |
| `is_configured()` | 无 | `bool` | 供调试判断是否找到 director |
| `is_wave_enabled(wave_id, elapsed)` | `String`, `float` | `bool` | 未配置时返回 `true`；已配置时只看当前 phase 的 `wave_ids` |
| `current_phase(elapsed)` | `float` | `Dictionary` | phase 起点包含、终点除最后阶段外不包含；最后阶段终点包含 |
| `interest_points_for_layout(layout_id)` | `String` | `Array[Dictionary]` | 返回 `map_layout_id` 为空或匹配当前 layout 的兴趣点深拷贝 |
| `debug_summary(elapsed)` | `float` | `Dictionary` | 返回 director、mutation、phase、pressure、wave、encounter、interest point 摘要 |

## 运行流程

1. `GameplayRunLoop._start_run()` 先读取 mode、敌人、地图、成长和 `spawn_waves.csv`。
2. `GameplayRunLoop` 读取 `DataLoader.WARZONE_DIRECTORS_PATH`，选择当前 mode 的 director。
3. `WarzoneDirector.configure()` 缓存 phases / encounters / interest_points。
4. 开局生成地图机关时，`GameplayRunLoop` 用 `interest_points_for_layout(layout_id)` 取当前地图兴趣点，并传给 `MapManager.generate_hazard_placements()`。
5. `MapManager` 为每个兴趣点的 `hazard_ids[]` 走通用 PCG 规则生成 `source="director"` placement；该 placement 会进入已有 `map.hazard_placements` 和活跃机关快照，不提升 run schema。
6. 每帧 `GameplayRunLoop._update_spawner()` 先询问 `is_wave_enabled(wave_key, GameClock.now())`，被当前 phase 禁用的 wave 直接跳过。
7. 通过导演后，原有 wave 时间窗、预算、同时存活上限和对象池生成逻辑继续执行。

## 依赖

- 上游依赖：`DataLoader`、`GameClock`、`spawn_waves.csv`、`warzone_directors.json`。
- 下游调用方：`GameplayRunLoop`、`MapManager` 初始机关生成、`GameplayRunLoop.debug_summary()`、`runtime-smoke`、`f9-demo-smoke`。
- 禁止依赖：`Player`、`WeaponSystem`、`Combat` 结果、HUD 输入、FPS / 性能指标或任何玩家表现数据。

## 扩展点

- 随机 mutation：必须先决定 RNG stream、保存 / 恢复策略和 replay 影响；首片不做。
- 地图兴趣点生成：已接入 `MapManager` 的数据化生成接口；后续扩展 kind / 奖励语义仍不能按 `poi_id` 或 `hazard_id` 写特殊分支。
- 生态 encounter：优先基于 enemy tags / AI profile / wave 组合，不按敌人 id 写逻辑。
- 玩家可见主题：新增 name / desc 前先补 `client/locale/strings.csv`，数据只存 locale key。

## 常见改动入口

| 你想改什么 | 主要文件 | 验证 |
|------------|----------|------|
| 调阶段时间 / wave 组合 | `client/data/warzone_directors.json` | `validate_data`、`test_data_loader_schema`、`runtime-smoke`、`f9-demo-smoke` |
| 新增 encounter / interest point | `warzone_directors.json`、必要时 `map_layouts.json` / `hazards.csv` | `validate_data` + `test_data_loader_schema`；兴趣点影响地图时追加 runtime / F9 smoke |
| 改 schema | `data_loader.gd`、`validate_data.py`、`test_data_loader_schema.py`、本文档、数据手册 | schema test + docs health |
| 让导演影响地图 | `warzone_director.gd`、`map_manager.gd`、`gameplay_run_loop.gd` | runtime-smoke、f9-demo-smoke、save-smoke、perf-probe，评估 golden |

## 测试义务

- 改数据或 schema：`python tools/validate_data.py`、`python tools/test_data_loader_schema.py`。
- 改 GDScript：`python tools/lint_gdscript_rules.py`、`python tools/godot_bridge.py --project client runtime-smoke`。
- 改 55 秒后中段压力或 FEA-12 兴趣点：追加 `python tools/godot_bridge.py --project client f9-demo-smoke`。
- 改兴趣点地图生成接线：追加 `python tools/godot_bridge.py --project client save-smoke`、`python tools/godot_bridge.py --project client perf-probe`，并跑 checked-in golden replay runner 评估行为漂移。
- 若引入随机 mutation、run snapshot 字段或 replay summary 变化，必须追加对应 save / replay runner 并更新 ADR。

## 迁移 / 兼容

F10.2 仍不提升 run snapshot schema。导演当前由静态数据和 `GameClock.now()` 推导；兴趣点只在开局生成已有 `map.hazard_placements` 与活跃 `hazards` 快照，续局直接恢复这些 placement。后续若加入随机 mutation、阶段内部计数器或玩家可见选择，必须保存 director state 并同步 `GameplayRunLoop.create_run_snapshot()` / `configure_restore_snapshot()`。
