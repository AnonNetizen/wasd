# F10 WarzoneDirector 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F10 敌巢战区导演的低 token 工作包；改 F10 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/AI记忆/current_state.json`。

---

## 目标

F10 把标准生存模式从“按时间刷怪”推进到“敌巢战区有可读主题和阶段组织”。本阶段采用数据驱动导演，不接运行时大模型，不读取玩家状态，不做隐藏动态难度：

- **节奏导演**：用固定阶段组织暖场、加压、生态混合和中段尖峰。
- **巢变异导演**：每局绑定一个可诊断的巢主题 / mutation，用于组合敌人生态、兴趣点和后续奖励语义。
- **地图兴趣点 / 机关导演**：在数据中声明兴趣点和机关组合，由 `WarzoneDirector` 过滤当前 layout 后交给 `MapManager` 生成初始 `source="director"` 机关 placement。
- **敌人生态导演**：用已有敌人 tags 和 AI profile 组合 prey / predator / territorial 等生态关系，而不是按敌人 id 写分支。

F10 的重点是让玩家感觉“这局战区有组织、有脾气”，同时保持 replay、存档、数据校验和调参入口稳定。

## 明确不做

- 不读取玩家血量、DPS、受伤次数、死亡边缘、输入频率、停顿时间或其它玩家状态来调整难度。
- 不做隐藏 DDA，不因玩家强弱临时改刷怪、伤害、掉落或地图。
- 不接运行时 LLM；AI 只用于离线产出数据、文档和设计稿。
- 不新增玩家可见文案，除非先补 locale key。
- 不改 run 存档 schema，除非导演引入随机选择或必须保存的状态。
- 不按 `director_id`、`mutation_id`、`wave_id` 或 `enemy_id` 写特殊 gameplay 分支。

## 必读

1. `docs/AI协作/快速开工.md`
2. `docs/AI记忆/current_state.json`
3. 当前平台编码规则入口
4. `docs/游戏设计文档.md` §5、§7、§9.3
5. `docs/AI导航.md` 第 4 节扩展点速查
6. `docs/测试策略.md`
7. `docs/代码文档规范.md`
8. `docs/代码/gameplay_runtime.md`
9. `docs/代码/data_loader.md`
10. `docs/代码/map_manager.md`
11. `docs/代码/enemy_ai.md`
12. `client/data/README.md`
13. `client/data/game_modes.json`
14. `client/data/map_layouts.json`
15. `client/data/spawn_waves.csv`
16. `client/data/enemies.csv`
17. `client/data/enemy_ai_profiles.json`
18. `client/scripts/gameplay/gameplay_run_loop.gd`
19. `client/scripts/autoload/data_loader.gd`
20. `tools/validate_data.py`

只在新增词表 id、玩家可见文案、存档 / 回放字段或长期模块时，补读对应词表、locale、SaveManager / Replay 文档和目标源码。

## F10.1 首片

先落一个低风险骨架，让现有行为尽量不变但建立导演解释层：

1. 新增 `client/data/warzone_directors.json`，声明标准模式导演、固定 mutation、阶段时间窗、阶段启用 wave、生态 encounter 和兴趣点。
2. 新增 `client/scripts/gameplay/warzone_director.gd`，只解释数据并提供 `is_wave_enabled(wave_id, elapsed)` 与 `debug_summary(elapsed)`。
3. `GameplayRunLoop` 在加载 `spawn_waves.csv` 后配置导演；刷怪仍沿用原有时间窗、预算、同时存活上限、对象池和 `GameClock`。
4. 第一片阶段表覆盖现有四条 wave，阶段边界与 wave 起始时间一致，避免无意改变当前 F9 demo 节奏。
5. `DataLoader` 和 `tools/validate_data.py` fail-fast 校验导演 schema、模式引用、wave 引用、content tag、hazard 引用和 map layout 引用。
6. 冒烟测试只验证导演调试摘要和中段 wave 仍能出现；不录新 golden，不改回放输入。

## 数据形状

`warzone_directors.json` 是复杂配置，使用 JSON：

```json
{
  "schema_version": 1,
  "directors": [
    {
      "id": "director_standard_warzone",
      "mode_id": "mode_standard_survival",
      "mutation_id": "nest_mutation_hunting_ground",
      "phases": [
        {
          "id": "phase_warmup",
          "start_time": 0.0,
          "end_time": 20.0,
          "pressure_tag": "warmup",
          "wave_ids": ["wave_standard_early_chasers"],
          "encounter_ids": ["encounter_chaser_screen"]
        }
      ],
      "encounters": [],
      "interest_points": []
    }
  ]
}
```

字段规则：

| 字段 | 规则 |
|------|------|
| `directors[].mode_id` | 必须是已登记且存在的 game mode id；每个模式首片只允许一个导演 |
| `directors[].mutation_id` | 非空本地数据 id；首片不玩家可见，不进词表 |
| `phases[]` | 非空、按时间升序、不重叠；`end_time > start_time` |
| `phases[].wave_ids[]` | 必须引用同模式 `spawn_waves.csv` 的 wave id；同一模式所有 wave 必须至少被一个 phase 引用 |
| `phases[].encounter_ids[]` | 必须引用同导演 `encounters[].id` |
| `encounters[].enemy_tags[]` | 必须来自 `content_tags`；生态组合优先读 tag，不读敌人 id |
| `interest_points[].hazard_ids[]` | 非空数组；每项必须存在于 `hazards.csv` |
| `interest_points[].map_layout_id` | 非空时必须存在于 `map_layouts.json` |

## F10.2 兴趣点接入地图生成

F10.2 把 `interest_points` 从调试摘要推进到玩家可感知的初始地图机关，但仍保持数据驱动和确定性边界：

1. `WarzoneDirector.interest_points_for_layout(layout_id)` 返回当前 layout 匹配的兴趣点深拷贝；空 `map_layout_id` 可匹配所有 layout。
2. `GameplayRunLoop` 在开局生成地图机关时，把当前 layout 的导演兴趣点传入 `MapManager.generate_hazard_placements(layout_data, director_interest_points)`；旧快照缺少机关 placement 的恢复 fallback 也走同一路径。
3. `MapManager` 仍先放 `manual_hazards`，再按 `pcg.hazards` 生成，最后为每个匹配兴趣点的 `hazard_ids[]` 用通用 PCG 规则补一个 `source="director"` placement，并保留 `interest_point_id` 供 debug / run snapshot 诊断。
4. 兴趣点不读取玩家状态、不按 `poi_id` 或 `hazard_id` 特判、不改变机关行为 primitive、不提升 run 存档 schema；生成随机仍只走 `RNG.world`。
5. `runtime-smoke` 与 `f9-demo-smoke` 覆盖 `debug_summary().map.hazard_sources.director > 0`，确认 FEA-12 兴趣点进入初始地图。

## 验收

默认验证：

```powershell
python tools/sync_contracts.py --check
python tools/validate_data.py
python tools/test_data_loader_schema.py
python tools/lint_gdscript_rules.py
python tools/lint_project_rules.py
python tools/lint_semantic_rules.py
python tools/docs_health_check.py
python tools/godot_bridge.py --project client runtime-smoke
python tools/godot_bridge.py --project client f9-demo-smoke
```

若只改文档，可按文档维护指南缩小为 `python tools/docs_health_check.py`。若导演开始影响地图生成、run snapshot、随机 mutation、replay summary 或 golden fingerprint，追加对应 smoke / replay runner，并在 ADR 和本工作包写明原因；F10.2 兴趣点接入地图生成至少追加 `headless-boot`、`save-smoke` 与 checked-in golden replay runner 评估。`perf-probe` 仅在用户明确要求性能测试时运行。

## 红线

- 导演逻辑只能读数据、局内时间和自身状态；禁止读取 `_player.current_life()`、玩家输入、近期伤害、DPS、击杀速度等玩家表现指标。
- 运行时随机必须走已登记 RNG stream；首片不随机。
- 任何新增可调参数先放数据，再让代码解释；禁止硬编码阶段时间、wave id、敌人 id、机关 id。
- 新增兴趣点或 encounter 先做通用 schema 和校验，再接生成逻辑。
- 大改刷怪行为前先说明对 golden replay、存档恢复和性能预算的影响。
