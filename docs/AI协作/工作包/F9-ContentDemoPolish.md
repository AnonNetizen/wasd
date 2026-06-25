# F9 ContentDemoPolish 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F9 内容扩展与 Demo 打磨的低 token 工作包；改 F9 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/AI记忆/current_state.json`。

---

## 目标

在 F4~F8 已经具备可玩闭环、暂停 / 存档 / 续局、局外成长、设置 / 本地化 / UI 栈和回放 / 性能基线后，F9 开始把项目从“工程闭环可跑”推进到“可演示、可试玩、内容稍厚且不脆”：

- 建立首批 Demo 内容切片：新增少量角色、武器、敌人、成长选项或局外升级，优先复用已有数据 schema 和运行时能力。
- 打磨当前核心手感：移动、射击、碰撞反馈、经验拾取、升级节奏、失败 / 重开 / 回标题路径和基础可读性。
- 补齐音频 / 美术占位规范，让新增内容有一致的临时表现，不把占位资产写死进逻辑。
- 以 F8 golden replay、smoke、perf-probe 和手动 checklist 保护内容扩展，避免内容变多后回归问题变隐蔽。
- 只在内容确实需要时新增可复用 primitive / runtime 能力；不要为某个 id 写特殊分支。

F9 的核心是“可试玩 Demo 的第一层内容和体验打磨”，不是无限堆数据、重做美术风格、做完整平衡平台、做商店页、做完整遗物协同系统或提前发版。

## 必读

1. `docs/AI协作/快速开工.md`
2. `docs/AI记忆/current_state.json`
3. 当前平台编码规则入口
4. `docs/正式项目工作规划.md` F9 段
5. `docs/AI导航.md` 第 4 节扩展点速查
6. `docs/测试策略.md` 中 L3 / L4 / L5、回放和性能预算相关段落
7. `docs/代码文档规范.md`
8. `docs/代码/gameplay_runtime.md`
9. `client/data/README.md`
10. `client/locale/README.md`
11. `docs/词表与契约.md` 与目标内容类型相关章节
12. 目标数据文件：`characters.json`、`weapons.json`、`enemies.csv`、`growth.csv`、`growth_pools.json`、`meta_progression.json`、`relics.json`、`active_items.json`、`consumables.json`、`hazards.csv`、`spawn_waves.csv`、`game_modes.json` 中本次会改的最小集合

只在新增 stat / effect / event / action / pool / audio id、修改运行时行为、改变回放 schema、改变存档 schema 或新增长期模块时，补读对应 GDD、ADR、模块文档和目标源码。不要为了“准备 F9”默认整篇加载 GDD 或批量扫全仓。

## 建议拆分

1. **F9.0 范围盘点与 Demo 内容清单**：先列出当前可复用内容、运行时已支持能力、不能做的内容类型和首批 Demo 目标。输出应是短清单，不直接改大量数据。
2. **F9.1 小内容首片**：优先新增 1 个低风险内容包，例如 1 个敌人变体 + 1 条刷怪波次 + 1~2 个成长候选，或 1 个武器数据变体 + 对应文案。只走数据 / locale / 验证；除非现有 runtime 无法表达，否则不改逻辑。
3. **F9.2 手感与可读性打磨**：围绕一次真实试玩修移动 / 射击 / 命中反馈 / 拾取节奏 / 升级提示 / 失败反馈。改动要小，能被 runtime-smoke、golden replay 或手动 checklist 描述。
4. **F9.3 Demo 表现占位规范**：为新增敌人、武器、拾取、机关、UI 提示、SFX / BGM 等建立一致占位策略；固定斜俯视资产遵守 GDD §8.2-A，地面范围读菱形并对齐量化菱形地图格，非地面资产保留自由轮廓但必须有落地点 / 阴影 / 遮挡层级。若新增音频 id，先登记词表并走 `AudioManager`，不在业务脚本直接播放。
5. **F9.4 回归与性能守门**：每个内容切片至少跑数据 / locale 校验、相关 smoke、一条或四条 golden replay runtime rerun、`perf-probe`。有意改变核心运行时语义时才重录 golden，并说明行为差异。
6. **F9.5 Demo 手动 checklist**：形成可重复试玩清单，覆盖启动、语言切换、设置、开始游戏、升级、暂停保存、继续游戏、死亡结算、局外升级、回标题、重开和性能感受。

## F9.0 盘点结果（2026-06-20）

### 当前可直接复用

- **可玩 runtime**：标题进入游戏、默认角色、鼠标瞄准 + 键盘 / 手柄兜底瞄准、按住 `fire` action 开火、玩家受击无敌、相机居中、世界网格参照、失败结算、重开 / 回标题、暂停保存退出与继续游戏都已接入正式场景和 smoke。
- **可数据化扩展的局内内容**：`characters.json` 已有默认角色，`weapons.json` 已有基础武器，`enemies.csv` 已有 `enemy_chaser` / `enemy_swarm` 两种追击型敌人，`spawn_waves.csv` 已有早期追猎者和 20 秒后的 swarm 混合波次。
- **可数据化扩展的成长内容**：`growth.csv` 已覆盖 1~10 级阈值，`growth_pools.json` 当前可直接新增 `kind=stat_modifier` 的属性奖励；运行时已支持 damage、fire_rate、pickup_range 等 modifiers。
- **可复用的局外成长**：`meta_progression.json` 已有生命、伤害、射速、移速、拾取范围、幸运和开局遗物候选等升级轨道；标题页局外升级入口与死亡结算已接上 `SaveManager` 的 `meta` kind。
- **可复用的守门工具**：`validate_data`、`lint_project_rules`、`runtime-smoke`、四条 checked-in golden replay runner、`perf-probe` 和手动 checklist 是 F9 内容扩展的默认护栏。

### 当前不要直接做

- **角色扩展**：可以补数据样例，但当前没有角色选择 UI；新增角色若不能被玩家选择，不适合作为首个 Demo 可见切片。
- **武器扩展**：可以补数据样例，但当前 runtime 只按角色起始武器开局；新增武器若没有选择 / 掉落 / 解锁路径，玩家不可感知。
- **遗物 / 主动道具 / 消耗品**：已有数据边界和样例，但缺少完整拾取、选择、使用、冷却、栏位、存档恢复和效果执行 runtime；不要把它们作为 F9.1 首个可玩切片，除非先实现对应系统。
- **机关 / hazard**：HazardSystem runtime 已落地，通用机关走 `hazards.csv.radius_tiles` + `map_layouts.json.grid` 的量化菱形格；第一批 Demo 内容可调现有 FEA-12 / 尖刺样例，但新增行为型机关仍需先设计 primitive、补 smoke 和文档。
- **新 effect / behavior / capability**：任何新原语都要先登记词表、实现可复用 runtime、补测试和文档；F9.1 优先避免。
- **音频 / 正式美术替换**：当前可以写占位规范和 audio id 计划，但不要直接绕过 `AudioManager` 或把资源路径硬写进 gameplay 脚本。

### F9.1 推荐首个 Demo 小内容包

首片目标：只用现有 enemy + spawn + growth runtime，做玩家能在 1~3 分钟内感知到的内容厚度提升。

1. 新增 1 个低风险敌人变体：复用已登记且 runtime 已支持的敌人池 / 追击行为，优先做“高血量慢速压迫型”或“低血量快速骚扰型”的数据变体；新增 `enemy_*_name` 双语文案。
2. 新增 1 条中段刷怪波次：在 45~90 秒加入该敌人，控制 `max_alive` 与 `spawn_interval`，避免首片直接拉高对象池和性能风险。
3. 新增 2 个 `stat_modifier` 升级候选：优先补 `move_speed` 与 `max_hp`，复用现有升级选择 runtime 和 `RNG.ui_choice`；避免新增候选类型。
4. 不新增词表 id 类型、不改 GDScript、不改存档 / 回放 schema；若新增敌人 id 只作为数据 id，不进入生成契约常量。
5. 验证最小集：`sync_contracts --check`、`validate_data`、`lint_project_rules`、`runtime-smoke`、四条 golden replay runtime rerun 和 `perf-probe`；若 gameplay summary 无意变化，禁止重录 golden。

### F9.2 候选手感打磨

- 试玩后优先看子弹命中宽容、敌人贴脸可读性、经验球吸附速度 / 范围、升级节奏和失败反馈；只调 `client/data/` 中已有字段。
- 若需要代码手感改动，先写明玩家可感知问题、影响到的 smoke / replay、是否需要更新 `docs/代码/gameplay_runtime.md`。
- 不在没有试玩证据时做大范围数值重平衡。

## F9.1 首个小内容包（2026-06-20）

已按 F9.0 推荐路线落地一个数据优先内容切片：

- **新敌人变体**：`enemy_bulwark`，复用 `enemy_chaser` 对象池和追击 runtime；定位为慢速高血量压迫型敌人，数值为 `max_hp=28`、`move_speed=72.0`、`contact_damage=200`、`exp_reward=6`，占位色 `#b07d52`。
- **新刷怪波次**：`wave_standard_mid_bulwarks`，在标准生存模式 55 秒后开始，每 4.5 秒尝试刷 1 个 `enemy_bulwark`，同时存活上限为 3，避免首片直接推高实体密度。
- **新升级候选**：`growth_move_speed_small`（移动速度 +18）与 `growth_max_hp_small`（最大生命 +100），均为 `kind=stat_modifier` 且 `min_level=3`，避免改变现有 `golden_level_up_choice` 的二级候选集合。
- **新双语文案**：补齐 `enemy_bulwark_name`、`ui_growth_move_speed_small_*`、`ui_growth_max_hp_small_*` 的 `zh_CN` / `en`。
- **回放处理**：内容数据变更导致 data fingerprint 从 `92b2a5487f50b4e06955fdd66a64b087ebf03955c2a795fe9bba5615ea1c5e65` 更新为 `b4138b1f767764bbafd3ef56d731e329567435c076b7a75dec498e15802dd302`；四条 checked-in golden replay 仅更新 envelope 指纹，运行时摘要重跑通过，未重录输入或改期望摘要。

下一步优先做 F9.2 手动试玩 / 手感可读性复核：观察 55 秒后的 `enemy_bulwark` 是否过硬或过慢、三级候选出现节奏是否合理、3~5 分钟内是否有明显性能尖峰。若只调数值，继续走 `client/data/`；若要改碰撞、反馈或 UI，需要同步 `docs/代码/gameplay_runtime.md` 与对应 smoke / replay 说明。

## F9.2 自动化 Demo 前置探针（2026-06-20）

已新增 `py -3 tools/godot_bridge.py --project client f9-demo-smoke`，作为 F9.1 内容进入人工试玩前的硬路径护栏：

- headless 启动正式 `GameplayRunLoop` 后用 `GameClock.set_time_scale(20.0)` 快进到 55 秒后的中段波次，确认 `enemy_bulwark` 会从 `wave_standard_mid_bulwarks` 生成。
- 校验 `enemy_bulwark` 的 data-driven 占位色、`wave_key`、run snapshot 保存和 `SaveManager` roundtrip，避免新增中段敌人破坏暂停保存 / 继续游戏的数据形状。
- 校验运行时已加载的三级成长池包含 `growth_move_speed_small` 与 `growth_max_hp_small`。
- 末尾通过正式 `Combat` 击杀玩家，确认死亡进入 `GAME_OVER` 并写入 `meta` 存档 / 记忆余烬。

这条 smoke 只证明新增内容能在正式 runtime 中出现并穿过存档 / 结算链路；它不替代人工手感试玩。下一步仍需按下方 checklist 做 3~5 分钟可视化试玩，重点判断 `enemy_bulwark` 的硬度、速度、接触伤害和三级升级节奏是否舒服。

## F9.2 手动试玩结论（2026-06-20）

用户完成 F9.1 内容切片的可视化试玩后反馈“没有什么问题”。本轮因此不做数值重平衡，保持 `enemy_bulwark` 的血量、速度、接触伤害、刷怪间隔、同时存活上限和三级成长候选数值不变。

## F9.3 首个表现占位切片（2026-06-20）

已先做一个低风险的敌人占位可读性切片：

- `Enemy._draw()` 对所有敌人统一绘制暗色轮廓和眼睛描边，提升 `enemy_chaser` / `enemy_swarm` / `enemy_bulwark` 在移动、叠靠和受击/死亡反馈中的轮廓可读性。
- 仍然只使用 `enemies.csv.visual_color` 作为填充色，不按敌人 id 写表现分支，也不引入正式美术资源路径。
- `enemy_bulwark` 继续靠较大的 `hit_radius` 和 `#b07d52` 占位色形成体型/颜色差异；后续若还需要更强区分，再优先考虑数据字段或通用表现 primitive。

下一步 F9.3 可继续盘点 SFX / BGM id、拾取 / 升级 / 命中反馈的一致占位策略；新增音频播放必须走 `AudioManager`，新增可调字段必须补 `client/data/README.md` 与 DataLoader schema。

## F9.3 固定斜俯视资产处理规则（2026-06-23）

后续占位替换或 AI 生成正式资源时，不要把“菱形机关”误读为“所有资产都要做成菱形”：

- 贴地范围（机关危险区、AOE 预警、房间边界、地面符号）优先用菱形或与量化菱形地图格对齐的轮廓；机关和规则型地面 footprint 尺寸用格子的整数倍表达，并让视觉边界和真实判定一致。
- 非贴地实体（角色、敌人、宝箱、石柱、墙、树、机器、拾取物、子弹、特效）可以使用自由轮廓；关键是有清晰 `anchor_point`、底座 / 阴影、`sort_layer` 和真实碰撞 / 触发形状。
- AI 写资产 brief 时至少声明 `asset_type`、`footprint_shape`、`anchor_point`、`shadow`、`sort_layer`、`collision_or_trigger_shape`；缺字段先补 brief，再生成或替换资源。
- 参考《哈迪斯》时可用 3D 辅助生成 2D 帧，或用低模 3D 视觉层，但玩法仍保持 2D 平面，不把地图 / 碰撞 / 回放改成真 3D。

## F9.3 Demo 音频 cue 计划（2026-06-20）

已在 `docs/代码/audio_manager.md` 补充 F9 Demo cue 矩阵，先建立音频占位命名和接入顺序，不在没有资源注册时播放音频：

- 当前具体 cue 计划覆盖 `sfx_player_shoot`、`sfx_player_hurt`、`sfx_enemy_hit`、`sfx_enemy_die`、`sfx_pickup_orb`、`sfx_ui_click`、`sfx_ui_levelup`、`music_run_loop` 和预留的 `music_boss`。
- `sfx_player_shoot` 已作为 `weapons.json.fire_audio_id` 的数据字段存在；后续播放仍必须等资源注册后通过 `AudioManager.play_sfx()` 触发。
- `docs/词表与契约.md` §10 仍只维护前缀白名单，具体 cue id 不写入该表，避免 `tools/sync_contracts.py` 把具体 id 误生成为 `AudioIds.PREFIXES`。
- 接入顺序建议为：先注册资源和验证 Bus / 计数，再接低风险 UI cue，最后接高频 gameplay cue；射击、命中、拾取等高频 cue 必须考虑 polyphony / 节流。

后续若获得临时音频资源，再补 `AudioManager` 注册和 smoke；当前已确认无资源，F9.3 先走视觉反馈一致性。

## F9.3 无音频资源视觉反馈切片（2026-06-20）

用户确认当前没有可用临时音频资源，因此本轮不接 `AudioManager` 注册 / 播放，改走视觉反馈一致性：

- `Bullet._draw()` 改为黄色圆点 + 统一暗色轮廓，提升快速移动时的弹体可读性。
- `PickupOrb._draw()` 改为绿色圆点 + 统一暗色轮廓，吸附短弧和收集放大淡出保持不变。
- 这与 F9.3 敌人占位轮廓使用同一类暗色边界语言，形成“敌人 / 子弹 / 拾取”三类核心实体的临时 Demo 可读性规范。

## F9.3 反馈颜色与时长一致性切片（2026-06-20）

在无音频资源前提下继续强化“看得懂发生了什么”的临时反馈规范：

- `Player._draw()` 增加暗色轮廓；受伤反馈从白闪改为 0.16 秒红闪，和玩家蓝色本体形成明确区分。
- `Enemy._enemy_color()` 将命中反馈明确为 0.16 秒暖白闪，死亡反馈明确为 0.18 秒橙色放大淡出。
- `GameplayHud.show_upgrade_feedback()` 的升级获得提示改为金色文字、暗色阴影和 1.35 秒淡出，保留原有本地化文本与回放 / 升级选择流程。

## F9.3 命中火花 / 伤害数字池切片（2026-06-20）

继续无音频资源下的局内反馈增强，本轮把词表中已预留的 `hit_spark` / `damage_number` pool id 接成可运行对象池：

- 新增 `HitSpark` / `DamageNumber` 场景和脚本，分别显示短命径向火花与向上漂淡出的伤害数字。
- `GameplayRunLoop` 注册、预热和清理两个反馈池，并监听 `Combat.damage_applied`；只有伤害实际应用时才生成反馈。
- `runtime-smoke` 增加池 acquire 断言，确认敌人受伤时会生成命中火花和伤害数字。
- 这些反馈不进入 `run` 快照，不影响回放语义字段，只作为当前 Demo 可读性占位。

## F9.3 命中反馈人工试玩结论（2026-06-20）

用户完成命中火花 / 伤害数字切片后的人工 Demo 观察，反馈飘字密度、遮挡和整体可读性没有问题。本轮不再调整火花持续时间、伤害数字漂移 / 淡出、池大小或触发条件；F9.3 无音频资源下的核心视觉占位反馈可进入收束。

后续已进入下方 F9.4 回归 / 性能守门审计；若后续获得临时音频资源，再回到 `AudioManager` 注册 / smoke。

## F9.4 回归与性能守门审计（2026-06-20）

F9.1~F9.3 首批内容 / 表现切片完成后，已按 F9.4 守门口径重跑自动化回归：

- 基础门禁：`sync_contracts --check`、`validate_data`、`test_data_loader_schema`、三层 lint、JSON 校验、`docs_health_check` 和 `git diff --check` 均通过。
- 核心 smoke：`headless-boot`、`runtime-smoke`、`f9-demo-smoke`、`settings-smoke`、历史 `meta-smoke`、`save-smoke`、`l1-smoke`、`replay-smoke` 均通过；ADR #117 后 `meta-smoke` 已退役，当前跨局成长验证改走 `gear-mod-smoke`；坏 JSON / 非法配置日志仍是既有恢复探针。
- 四条 checked-in golden replay 均通过 `replay-runner --rerun-runtime-summary`；本轮未重录输入、未更新期望摘要，也未改变 replay envelope。
- `perf-probe` 仍为 `schema_version=2` / `budget_status.status=pass`，本轮观测 `p99=9.09ms`，低于当前 `20ms` 目标。
- `lint_semantic_rules.py` 仍为通过状态并报告 21 条已接受 advisory：既有提示加 F9.3 反馈池工厂 `instantiate()` 提示。

结论：首批 F9 Demo 内容和无音频视觉反馈已穿过当前自动回归 / 性能守门；后续 F9.5 手动 checklist 结论见下方。

### F9 Demo 手动 checklist 首版

每个 F9 可玩切片后至少人工跑一遍：

- 标题冷启动后进入游戏，移动、鼠标瞄准、兜底瞄准、按住左键 / 右扳机射击和经验拾取正常。
- 1~3 分钟内能看到当前新增敌人 / 波次 / 升级候选，且无裸 key、无明显重叠遮挡、无无法点击 UI。
- 升级选择后属性反馈能在 HUD 或手感上体现，暂停菜单可叠出并返回正确状态。
- 暂停保存退出后回标题，继续游戏恢复玩家、敌人、子弹、经验、RNG / GameClock 与 UI 状态。
- 死亡后结算、局外货币 / 账号经验、标题局外升级入口、重开和回标题正常。
- 同一局试玩 3~5 分钟无明显卡顿、对象池泄漏、卡死或无法退出状态；若新增内容提高实体密度，必须对比 `perf-probe`。

## F9.5 手动 checklist 结论（2026-06-20）

用户完成 F9.5 完整 Demo 手动 checklist 复核后确认“没什么问题，已经可以收口”。F9 第一轮 Demo 内容 / 表现打磨因此收口：保留当前 `enemy_bulwark` 中段内容、三级成长候选、无音频视觉反馈规范、命中火花 / 伤害数字池，以及 F8 golden replay / smoke / perf-probe 作为后续内容扩展护栏。

本轮不继续追加第二个小内容包。下一步转为中型系统决策：优先评估武器选择 / 第二把武器的可见获取路径、角色选择、遗物 runtime、hazard runtime 或音频资源接入中的一个；若临时音频资源先到位，则回到 `AudioManager` 注册 / smoke。

## 可改文件

- `client/data/characters.json`
- `client/data/weapons.json`
- `client/data/enemies.csv`
- `client/data/spawn_waves.csv`
- `client/data/growth.csv`
- `client/data/growth_pools.json`
- `client/data/meta_progression.json`
- `client/data/relics.json`
- `client/data/active_items.json`
- `client/data/consumables.json`
- `client/data/hazards.csv`
- `client/data/game_modes.json`
- `client/locale/strings.csv`
- `client/data/README.md`
- `client/locale/README.md`
- `docs/词表与契约.md` 与生成契约产物（仅新增白名单 id 时）
- `client/scripts/gameplay/` 中与手感、反馈、内容 primitive 直接相关的最小脚本
- `client/scripts/autoload/audio_manager.gd` 与音频注册相关文件（仅新增音频播放能力时）
- `client/assets/` 中占位资源或资源说明（需要资源时）
- `client/tests/replays/` 与 `client/tools/golden_replay_capture.gd`（只有行为语义改变或新增可复现场景时）
- `docs/代码/` 中被触碰模块的文档
- `docs/测试策略.md`、`docs/CICD规划.md`（只有门禁 / checklist 变化时）
- `docs/AI导航.md`、`docs/AI记忆/current_state.json`、当日会话日志

## 禁止事项

- 不批量新增几十条内容；每个切片必须能独立验证、独立回滚、独立说明玩家可感知价值。
- 不为具体角色 / 武器 / 敌人 / 遗物 id 写特殊分支；需要新能力时先抽象为 stat、effect、behavior、capability、tag、strategy 或 runtime primitive。
- 不新增玩家可见文本而漏 `zh_CN` / `en`；不把显示名写死在代码或数据外。
- 不新增可调数值字段而漏 `client/data/README.md`、DataLoader schema 和校验。
- 不复活历史 MVP 临时代码；只能迁移已经被正式文档 / ADR 吸收的经验。
- 不绕过 `RNG`、`GameClock`、`GameState`、`PoolManager`、`Combat`、`SaveManager`、`AudioManager`、`UIManager` 等既有系统边界。
- 不把内容扩展作为修测试快照的借口；golden replay 只有在行为有意改变并已说明时才重录。
- 不在 F9 第一轮就做完整 AIPlayer、完整商店、完整遗物协同、完整手柄重绑定、正式美术替换或发版工程。
- 不因为菱形机关和量化背景网格，把角色、敌人、拾取物、子弹、障碍物或特效强制做成菱形；非地面资产靠落地点、阴影、遮挡和排序统一斜俯视读法。
- 不读取、整理、引用或修改 `draft/` / `DRAFT/`。

## 验收命令

基础门禁：

- `python tools/sync_contracts.py --check`
- `python tools/validate_data.py`
- `python tools/test_data_loader_schema.py`
- `python tools/lint_gdscript_rules.py`
- `python tools/lint_project_rules.py`
- `python tools/test_project_rules_lint.py`
- `python tools/lint_semantic_rules.py`
- `python tools/test_semantic_rules_lint.py`
- `python tools/godot_bridge.py --project client headless-boot`
- `python tools/godot_bridge.py --project client runtime-smoke`
- `python tools/godot_bridge.py --project client f9-demo-smoke`
- `python tools/godot_bridge.py --project client settings-smoke`
- 历史 `meta-smoke` 已退役；当前跨局成长相关改动跑 `python tools/godot_bridge.py --project client gear-mod-smoke`
- `python tools/godot_bridge.py --project client save-smoke`
- `python -m json.tool docs/AI记忆/current_state.json`
- `python -m json.tool docs/_kb_index.json`
- `python tools/docs_health_check.py`
- `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`

F8 基线守门（按改动风险选择，内容 / 手感变更建议至少跑四条 checked-in rerun 与 perf）：

- `python tools/godot_bridge.py --project client l1-smoke`
- `python tools/godot_bridge.py --project client replay-smoke`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_basic_run.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_pause_resume.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_full_death.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_level_up_choice.replay --rerun-runtime-summary`
- `python tools/godot_bridge.py --project client perf-probe`

手动 Demo checklist（每个 F9 可玩切片至少更新 / 复核一次）：

- 标题进入游戏，移动、瞄准、射击、拾取经验、升级选择正常。
- 暂停、设置、语言切换、返回游戏、保存退出、继续游戏正常。
- 死亡结算、局外成长摘要、标题局外升级入口、重开 / 回标题正常。
- 新内容可见、可理解、无裸 key、无明显重叠 / 遮挡 / 无法点击。
- 试玩 3~5 分钟无明显性能尖峰、对象池泄漏、卡死或无法退出状态。

## 完成定义

- F9 工作包、TODO、AI 导航、知识库索引、当前状态和会话日志都指向 F9，后续 AI 能低 token 接手。
- 首批 Demo 内容清单明确：哪些内容先做、哪些需要新 primitive、哪些明确延后。
- 第一批内容扩展仍遵守数据驱动、locale 双语、词表白名单、对象池、统一伤害、确定性和存档边界。
- F8 四条 golden replay、核心 smoke、数据 / 文档校验和 perf-probe 继续作为 F9 内容扩展的回归护栏。
- 手动 Demo checklist 有可执行条目，并在每次重要 F9 切片后记录结果。
