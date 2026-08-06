# EnemyRewardResolver 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/代码文档规范.md`、GDD §7.1 与 ADR #175。
> 本文档是敌人生成时金币公式、随机消费边界和奖励快照的代码契约；改公式、数据字段、取整、上限、生成时机或恢复语义时必须同步数据手册、DifficultyProgression、Gameplay Runtime、EnemyAI、RNG、SaveManager 与测试策略。

## 职责与边界

- `EnemyRewardResolver` 是无节点、无随机、无时间读取的纯计算器。调用方必须显式传入基础系数、难度系数、怪物价值倍率、特殊化倍率、生成阶段、每阶段增长和外部随机倍率。
- `enemy_rewards.json` schema v1 保存全局基础系数、阶段增长和随机范围；`enemies.csv.gold_value_multiplier` 保存各敌种价值倍率。
- `GameplayRunLoop` 只在敌人成功取得对象池实体后消费一次 `RNG.economy`，读取实际生成时的威胁阶段并解析结果。取得实体失败、恢复已有敌人或死亡结算均不得消费随机。
- `Enemy` 保存最终整数金币与完整计算明细；死亡只通过既有 `defeated` signal 发放锁定值，不重新查询难度、时间或数据。

## 公式

```text
最终金币 = round(
    base_coefficient
    × difficulty_coefficient
    × gold_value_multiplier
    × reward_specialization_multiplier
    × (1 + time_growth_per_tier × spawn_tier)
    × random_multiplier
)
```

当前标准数据为基础系数 `10.0`、每阶段增长 `0.10`、随机范围 `0.9..1.1`。结果至少为 1，并在超过安全整数上限时饱和到 `2_147_483_647`。NaN、无穷、非正倍率或负阶段返回 `valid=false`；运行时遇到无效结果会释放刚取得的实体并取消该次生成。

五种敌人的 `gold_value_multiplier` 分别为：爆猎者 `1.0`、群袭者 `0.6666667`、伏击者 `1.6666667`、壁垒者 `2.0`、突击枪手 `1.0`。标准难度 tier 0 的取整范围约为 `9–11 / 6–7 / 15–18 / 18–22 / 9–11`。

## 公共 API

| API | 输入 | 输出 | 约束 |
|-----|------|------|------|
| `EnemyRewardResolver.resolve(...)` | 全部公式倍率、阶段与外部随机值 | `Dictionary` | 纯计算，不读 autoload；返回 `valid`、`gold_reward` 和完整明细 |
| `GameplayRunLoop.configure_difficulty_profile_id(id)` | profile id | `void` | 只能在 RunLoop 入树前调用；空 id 使用 mode 默认 |
| `Enemy.configure(..., spawn_context)` | `spawn_context.reward` | `void` | 新生成敌人接收已解析奖励；默认特殊化倍率为 `1.0` |
| `Enemy.snapshot()` / `restore_snapshot()` | 无 / 快照 | `Dictionary` / `void` | Run v13 精确保存和恢复最终金额、阶段及全部倍率 |

## 确定性与存档

- `RNG.economy` 与 `spawn`、`drop`、`world_event`、`combat` 等子流隔离；金币变化不会扰动敌种、Gear Mod、世界事件或战斗随机。
- 模块首次遭遇、开放战区与世界事件波次都按敌人的实际生成时刻取阶段。世界事件的生命 / 伤害仍可使用激活时固定快照，金币不使用该旧阶段。
- Run v13 保存敌人奖励快照和 `RNG.economy` state。已有敌人恢复不重抽；尚未生成的计划从保存的子流 state 继续。
- Run v9 缺少上述状态，明确不兼容并只清理 run；历史迁移边界见 SaveManager。当前 Replay v5 的数据指纹或运行时摘要变化仍需重录四条黄金回放。

## 验证义务

- 数据：`validate_data`、`test_data_loader_schema` 覆盖旧列 / 旧 difficulty schema、缺失 / 多余字段、有限值、上下界和正倍率。
- L1：公式、四舍五入、随机边界、无效倍率、安全上限、`89.999/90` 阶段边界、特殊化倍率和难度系数推进。
- Runtime / Save：五种开局范围、成功生成只消费 economy、失败生成不消费、跨阶段锁定、世界事件实际生成时间、单金币球、非奖励退场、Run v13 roundtrip 和恢复不重抽。
- Replay：重录并重跑四条 Replay v5 黄金回放；不运行性能 probe。
- 待人工验收（由用户执行）：标准开局金币节奏、阶段增长体感、约 `3.33×` 平均收入对升级 / 祭坛节奏的影响；AI 不代替执行。

## 相关文档

- `docs/游戏设计文档.md` §7.1 / §7.3
- `docs/决策记录.md` ADR #175
- `client/data/README.md`
- `docs/代码/difficulty_progression.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/enemy_ai.md`
- `docs/代码/rng.md`
- `docs/代码/save_manager.md`
- `docs/测试策略.md`
