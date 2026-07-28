# DifficultyProgression 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是模式级局内威胁时间、敌人出生倍率和初始房间战斗门禁的代码契约权威；改公式、暂停条件、模式引用、敌人倍率、Run 快照或测试义务时必须同步本文档、GDD §7.3、ADR #166、Gameplay Runtime、Save / Replay 文档和数据手册。

## 职责与边界

- `DifficultyProgression` 是每局一个的 `RefCounted` 模式组件，不是 autoload。`GameplayRunLoop` 从当前 `game_modes.json.difficulty_profile_id` 解析 profile 并持有实例。
- 它维护独立的“难度时间”。`GameClock` 继续驱动移动、冷却、状态、回复、敌人、子弹和回放 tick；不能通过暂停 `GameClock` 实现起点规则。
- 默认模块世界中，玩家实际位于 `module_role_start` 时难度时间暂停；开放战区从进入 `PLAYING` 起立即推进；开发者测试岛默认禁用。
- 起点房只锁武器和四技能。移动、冲刺、交互、回复、冷却、敌人 AI、敌弹和受伤继续运行，不是安全区。
- 难度只影响之后实际生成的敌人生命、接触伤害和远程弹丸伤害。移速、攻击间隔、弹速、AI、掉落、奖励、敌人数和刷新预算不变。

## 数据

`client/data/difficulty_profiles.json` 当前 schema v1：

| 字段 | 类型 | 当前标准值 | 说明 |
|------|------|------------|------|
| `id` | String | `difficulty_standard_survival` | profile 稳定主键 |
| `tier_interval_seconds` | float | `90.0` | 每级分段长度 |
| `continuous_growth_per_interval` | float | `0.04` | 每个 90 秒区间的连续系数增长 |
| `tier_step_growth` | float | `0.09` | 跨过阶段线时的额外跃升 |
| `damage_growth_ratio` | float | `0.48` | 生命系数变化映射到伤害的比例 |
| `stage_name_keys` | Array[String] | 9 个 key | Lv.1～9 名称；更高等级沿用第 9 个 |

`client/data/game_modes.json` schema v2 的每个 mode 必须用 `difficulty_profile_id` 强引用已登记 profile。DataLoader 与 Python 校验器共同拒绝缺失引用、重复 id、非正阶段时长、越界增长值、非 9 段文案和未本地化 key。

## 标准曲线

令 `elapsed` 为难度时间：

```text
tier = floor(elapsed / 90)
progress = (elapsed % 90) / 90
coefficient = 1 + 0.04 × (elapsed / 90) + 0.09 × tier
health_multiplier = coefficient
damage_multiplier = 1 + 0.48 × (coefficient - 1)
difficulty_level = tier + 1
```

曲线没有最终上限。12:00 时为 Lv.9、生命 `2.04×`、伤害 `1.4992×`；30:00 时为 Lv.21、生命 `3.6×`、伤害 `2.248×`。12 分钟只是短局设计窗口，不是硬封顶。

## 公共 API

| API | 输入 | 输出 | 约束 |
|-----|------|------|------|
| `configure(profile, enabled=true)` | profile、是否启用 | bool | 校验并重置到 0 秒 |
| `advance(delta)` | 已经 `GameClock.delta_scaled()` 的秒数 | void | 禁用、非正数或非有限值不推进 |
| `current_snapshot()` | 无 | Dictionary | 返回 elapsed、tier、progress、coefficient、等级、名称 key 和两倍率 |
| `enemy_spawn_snapshot()` | 无 | Dictionary | 生成敌人时取得的不可变出生倍率 |
| `snapshot()` | 无 | Dictionary | Run v7 保存 schema/profile/elapsed/enabled |
| `restore_snapshot(saved)` | 快照 | bool | schema/profile/elapsed 不匹配则拒绝 |

## 运行流程

1. RunLoop 读取 mode 和 profile，配置 progression。
2. 每个 `PLAYING` 帧先判断载体。模块世界根据玩家真实世界坐标换算当前槽位，开放战区直接允许推进。
3. 模块首次进入计划仍在进房时固化敌种和位置；预警倒计时结束后，敌人在真正 `PoolManager.acquire()` 时取得最新 `enemy_spawn_snapshot()`。
4. `Enemy.configure(..., spawn_difficulty)` 把生命倍率应用到最大生命，把伤害倍率应用到接触与远程弹丸伤害，并保存倍率。
5. 已生成敌人不订阅 progression，也不会在跨级时重算。模块卸载和 Run v7 续局从敌人快照恢复同一倍率。
6. HUD、详细面板、GameOverPanel、GameState 结果 payload 和 Replay 的 run-end / runtime summary 都使用难度时间。

## 战斗门禁

- `WeaponSystem.configure_combat_gate(callable)` 和 `SkillSystem.configure_combat_gate(callable)` 接收同一个同步门禁；回调 `true` 表示允许。
- 武器在检查射速和调用 `_fire_once()` 前检查门禁。因此起点房不会生成子弹、设置开火冷却或消费 `RNG.combat`；按住开火跨出起点后可立即射击。
- 技能在资源、冷却和效果解释之前检查门禁，失败返回 `reason=combat_locked`，不消耗资源、不进入冷却。技能输入是离散按压，离开起点后必须重新按键。
- 门禁只读取当前位置和模块 role，不修改 `GameState`，也不阻止移动、冲刺、交互或来自敌人的伤害。

## 存档与回放

- Run v7 继续保存顶层 `difficulty`，并在每个敌人快照保存 `spawn_health_multiplier` / `spawn_damage_multiplier`。
- Run v5 无法推断玩家在起点停留的时间，也无法还原已有敌人的出生倍率，因此 v5→v6 标记 `legacy_run_incompatible`，启动层只删除 run；Meta v2 和 Gear Mod 不受影响。
- Replay 文件和 recording 保持 v3。数据 schema count 会让 profile 变化进入 data fingerprint；四条 golden 的 `run_summary` 增加难度时间、等级和两倍率。

## 扩展点

- 后续敌人组合、刷新预算或遭遇预算应新增独立数据字段和明确 ADR；不得偷用生命系数推导数量。
- 新模式可引用不同 profile，也可在内部工具用途把 progression 设为 disabled；正式模式不得在运行时读取玩家生命、DPS、失误或输入频率做隐藏 DDA。
- 新敌人伤害出口必须使用保存的出生伤害倍率；不要在攻击时重新查询当前 progression。

## 验证

- 数据 / 单元：`validate_data`、`test_data_loader_schema`、`l1-smoke`；边界固定覆盖 0、89.999、90、719.999、720、1800 秒。
- 模块玩法：完整与技术切片 `module-world-smoke` 覆盖起点暂停、射击/技能门禁、离开后立即开火、返回再暂停、出生倍率、旧敌人不升级和流式恢复。
- 存档 / 回放：`save-smoke`、`runtime-smoke`、Replay smoke、四条 golden runtime rerun。
- UI：1920×1080 手动检查中英文、详细面板、小地图遮挡、长时间等级和正常阶段高亮。

## 故障排查

| 症状 | 优先检查 |
|------|----------|
| 起点仍计时 | `_is_combat_locked()` 是否根据玩家实际坐标得到 start role；RunLoop 是否在模块 `tick()` 后推进 |
| 起点能开火或消耗 RNG | WeaponSystem 是否在 `_fire_once()` 前检查 gate；是否绕过 `InputService` 直接调用发射 |
| 技能锁定后仍扣能量 | SkillSystem gate 是否位于成本 / 冷却判断之前 |
| 已有敌人跨级回血或增伤 | 是否错误地每帧查询 progression；Enemy 只能在 configure / restore 时设置出生倍率 |
| 续局敌人倍率变化 | Run 是否为 v6；敌人快照是否含两倍率；恢复 configure 是否先传入保存倍率 |
| 起点等候解锁后期敌种 | `unlock_time` 与 Warzone wave gating 是否仍读 `GameClock.now()`，应改读难度时间 |
