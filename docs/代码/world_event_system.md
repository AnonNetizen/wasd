# WorldEventSystem 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/游戏设计文档.md`、`docs/决策记录.md` 与 `client/data/README.md`。
> 本文档是世界事件运行时、模块摆放、敌人事件上下文、内容可用池与 Run v20 快照的代码契约；改事件规则、奖励、后台固定、敌人目标或保存字段时必须同步 GDD、ADR、Gameplay Runtime、EnemyAI、ModuleWorldManager、ContentUnlockSystem、SaveManager 与测试策略。

## 职责

- 用 `world_events.json` schema v2 定义防御、生存、占点、金币祭坛和血量祭坛；公共普通 Mod 池统一来自 `gear_mods.json`。
- 由场景化 `WorldEventController` 维护事件实例状态、持续事件全局互斥、波次游标、隐藏奖励、祭坛事务和 HUD 状态。
- 由模块 schema v5 的 `module_place_world_event` 把可交互物摆进 approved 模块；运行时不按事件 id 临时生成模块。HUD 小地图从开局显示整张 assignment 上的该 placement：金币 / 血量祭坛为三角，其余三类事件为信标圆环；未访问格仍保持迷雾底色。
- 持续事件激活后固定所属模块并继续真实模拟；完成或失败后，残敌转为普通敌人，离开原模块或死亡后解除固定。
- Run v20 保存事件、固定模块、事件波次计划、事件敌人归属、敌人金币快照、冻结内容池、事务进度、Gear Mod 棋盘 placements、效果程序状态与带 ID 未拾取 Mod；不保存 Node 引用。小地图 marker 从已恢复 assignment 重新派生，visited 只影响迷雾底色，不新增快照字段。

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/data/world_events.json` | 五类事件数值、波次、奖励和普通 Mod 池 |
| `client/scripts/gameplay/world_events/world_event_controller.gd` | 状态机、互斥、计时、奖励和快照 |
| `client/scripts/gameplay/world_events/world_event_interactable.gd` | 通用交互与表现门面 |
| `client/scripts/gameplay/world_events/world_event_defense_target.gd` | 防御目标生命、队伍护栏和快照 |
| `client/scripts/gameplay/world_events/world_event_capture_visual.gd` | 占点半径、启动延迟和永久进度表现 |
| `client/scenes/gameplay/world_events/*.tscn` | 五类可编辑交互物场景 |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 模块注册、事件上下文、波次生成、奖励、敌人转换和恢复顺序 |
| `client/scripts/gameplay/module_world_manager.gd` | 三个限量事件模块的 assignment 与后台固定 |
| `client/scripts/gameplay/enemy.gd` / `bullet.gd` | 事件主目标、玩家附带受击和跨目标组最近命中 |
| `client/tools/world_event_smoke.gd` | 五类事件、互斥、波次、奖励和 controller roundtrip |

## 运行流程

| 阶段 | 行为 |
|------|------|
| 世界组合 | `RNG.world` 从五种等权模板无放回选三种，各放一次；其余普通槽由 `module_flat_ground` 填充 |
| 注册 | RunLoop 遍历稳定 7×7 assignment，为三个 placement 创建场景实例并注册稳定 `instance_id` |
| 交互 | RunLoop 将兴趣点和世界事件候选按距离统一仲裁，复用 `interact` action |
| 激活 | Controller 固定所属模块；RunLoop 用 `RNG.world_event` 和激活时难度固化完整敌种 / 位置计划与生命 / 伤害语义 |
| 推进 | 仅在 `PLAYING` 下通过 `GameClock.delta_scaled()` 推进；玩家离开模块不暂停持续事件 |
| 终止 | 防御、生存、占点完成目标后先通过 RunLoop 同步投放奖励；handler 回执成功才提交 `reward_committed`、终态和观察 signal。投放失败保持 pending，并按 1 秒退避在后续 tick 重试；事件 pin 与连续事件名额在成功前不释放 |
| 残敌 | 事件敌人改以玩家为主目标，保留事件实例 id 直到死亡或离开原模块，以便安全解除 pin |
| 恢复 | 先恢复模块 assignment，再注册交互物和防御目标，然后恢复 Controller / 固定波次，最后恢复敌人和子弹 |

## 五类事件

| 类型 | 当前规则 |
|------|----------|
| 防御 | 1200 HP、45 秒、0/15/30 秒生成 4/5/6 敌人；目标激活前拒伤、不回血，只接受 `team_enemy` |
| 生存 | 40 秒、0/10/20/30 秒生成 4/5/5/6 敌人；离场后继续，玩家存活到结束即成功 |
| 占点 | 半径 260 px；进区 3 秒后开始累计 18 秒，离区时启动延迟以 0.5 秒/秒衰减，正式进度冻结不倒退；0/6/12 秒生成 4/5/6 敌人，120 秒超时失败 |
| 金币祭坛 | 初价 30，每次扣费后 `ceil(cost × 1.4)`，50% 成功；失败也扣费涨价，两次成功 Mod 必须不同，费用钳制在 JSON 安全整数上限 |
| 血量祭坛 | 三次比例 50%/75%/90%，基数为当次最大生命＋最大护盾；原子按超量盾→盾→生命扣除并至少保留 1 生命，立即获得实际献祭值 50% 的向下取整金币 |

防御、生存、占点完成后都固定从 `gear_mods.json` 公共普通池等权锁定一个 Mod，并在事件位置上方生成手动拾取实体，不再进行 70/30 空奖励，也不直接授予。玩家执行 `interact` 后只进入配置事务，确认棋盘合法位置才放置无等级实例；重复 effect id 仍逐份乘算。金币祭坛成功时同样生成 Mod，最多两次且两次不能重复；两次分别使用来源左 / 右 28 px 位置，不额外消费 RNG。血量祭坛只产即时局内金币，不产 Mod。事件敌人仍保留普通击杀金币与个体 Mod 掉落。事件计划只固定敌种、位置和战斗难度语义；每只敌人的普通击杀金币仍在实际生成时按当下威胁阶段与 `RNG.economy` 锁定。

## 奖励投放事务

- RunLoop 通过 `set_reward_delivery_handler(handler)` 注册同步投放边界；handler 接收 `instance_id / event_id / reward`，返回 `{ok, reason}`。只有金币入账或 Mod 拾取物生成完成后才可回 `ok=true`；失败 reason 会保存在 pending 上下文，并由 debug summary 或祭坛交互结果暴露用于诊断。
- Controller 先准备奖励并调用 handler，回执成功后才提交 `reward_committed`、祭坛成功 / 使用次数、`SUCCEEDED / EXHAUSTED` 终态，再发出兼容 signal `reward_requested` 供只读观察。RunLoop 不再订阅该 signal 执行投放，避免成功通知与实际交付混成无回执广播。
- 持续事件投放失败时保持 `ACTIVE` pending，目标停止继续受击；pending 上下文保存 1 秒重试剩余时间，后续 tick 到期后只重试同一奖励，避免对象池持续满载时逐帧放大错误与埋点，且 snapshot / restore 延续剩余退避。金币 / 血量祭坛投放失败时保持可交互 pending，下一次交互只重试，不重新扣金币、重投成功率或再次献祭。祭坛 pending 不由 tick 自动完成。
- pending 事务复用 Run v20 已有 `prepared_reward` 与 `reward_committed`：内部 `_delivery_pending` / `_delivery_context` 随现有字典 roundtrip，不新增顶层保存字段、不升级 Run schema。成功后清除内部投放元数据，公开 reward 不暴露这些内部键。

## 敌人事件上下文

`Enemy.configure(..., spawn_context)` 可选字段：

- `event_instance_id`：稳定事件归属；对象池 release/reset 必须清空。
- `primary_target`：防御事件为专用目标，其他事件仍为玩家。
- `damage_target_groups`：事件远程弹可命中地形、防御目标与玩家；普通环境敌弹不含防御目标组。

近战、冲撞、远程和爆炸均攻击事件主目标；主目标不是玩家时，路径上的玩家仍可正常受击。`Bullet` 汇总全部目标组后按扫掠命中时间与稳定实例 id 选择最近目标，不能由数组顺序抢伤害。

## 快照与幂等

Run v20 的 `world_events` 块保存 Controller 实例状态与固定波次计划；模块快照保存 7×7 assignment / 目标角落、`pinned_slots` 与带 `instance_id` 的非活动槽未拾取 Mod，顶层 `gear_mod_pickups` 保存活动模块未拾取 Mod，`gear_mods.placements` 保存已确认的棋盘实例，GameplayEffectRuntime 保存程序状态。Controller 保存事务游标、prepared reward、pending delivery context 与提交结果；恢复 pending 祭坛后只重试交付，不得重发波次、重复扣费 / 献祭 / 生成 Mod、引入新解锁内容或重抽既有敌人金币 / 刷怪笼计划。

旧 Run v19 与 Replay v9 保持源文件但拒绝继续 / 播放，不迁移。Replay v10 延续规范化 Gear Mod v6 components、统一效果契约与 mod environment 指纹，并增加传送选择语义；小地图 marker 不进入 Replay wire。

## 扩展点

- 新事件先登记词表 id / kind / state / reward，再扩 `world_events.json` 严格 schema、可复用场景与 Controller 策略。
- 新模块只通过 Module JSON 的世界事件下拉生成 `{type, cell, world_event_id}`；每模块最多一个世界事件 placement。
- 改事件波次必须保持激活时一次性固化、先与冻结敌池求交、独立 `RNG.world_event` 和 Run v20 roundtrip；普通击杀金币必须按各敌人实际生成阶段走 `RNG.economy`。
- 不得把事件复杂状态塞回兴趣点字典，不得让普通环境敌人攻击防御目标，不得直接修改金币或 Meta 背包。

## 验证

- 数据与契约：`sync_contracts --check`、`validate_data`、`test_data_loader_schema`。
- 核心状态机：`py -3 tools/godot_bridge.py world-event-smoke`（`client/tools/world_event_smoke.gd`），覆盖连续事件投放失败后的逐帧重试抑制，以及金币与血量祭坛投放失败 → snapshot / restore → 重试成功；pending 期间不提交、不重复收费 / 献祭 / 奖励。
- 真实投放边界：`py -3 tools/godot_bridge.py gear-mod-pickup-smoke`（`client/tools/gear_mod_pickup_smoke.gd`）在 FormalBoot RunLoop 内用容量为 1 的正式 pickup pool 制造 `PoolManager.acquire()` 失败，验证 `{ok:false, reason="gear_mod_pickup_pool_exhausted"}` 让 Controller 保持 pending；释放容量后同一事务成功，且只收费、投放、通知各一次。该集成不放在 direct `--script` 的 world-event smoke 中，因为该入口不加载项目 autoload 符号表，不能预载完整 RunLoop。
- 模块与恢复：正式 / 技术 `module-world-smoke`、`save-smoke`、`loading-smoke`。
- 战斗：`runtime-smoke`、`l1-smoke`、`actor-scene-smoke`、`vfx-smoke`。
- 完整变更还需三档 lint、content-progression、effect-runtime、headless boot/editor、四条 Replay v10 golden、文档健康和 pre-commit；中英文布局与局内反馈保持待人工验收并由用户执行。ADR #143 后不自动运行性能 probe。

## 相关文档

- `docs/游戏设计文档.md` §5.3
- `docs/决策记录.md` ADR #173 / #175
- `docs/代码/gameplay_runtime.md`
- `docs/代码/enemy_ai.md`
- `docs/代码/module_world_manager.md`
- `docs/代码/save_manager.md`
- `docs/测试策略.md`
