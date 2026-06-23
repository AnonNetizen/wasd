# Combat 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `Combat` 伤害入口的代码契约权威；改 `DamageInfo` 字段、`apply_damage()` 行为、伤害类型依赖或测试义务时必须同步 GDD、AI 导航、测试策略和相关玩法模块文档。

## 职责

- `Combat` 是正式项目所有伤害结算的唯一入口。
- `DamageInfo` 承载一次伤害的来源、目标、数值、类型、队伍和 flags。
- 当前 F4/F9 切片只做最小转发和合法性校验：校验目标、伤害类型、正数伤害，并调用目标的 `receive_damage(info)`。
- 本模块不负责护甲、暴击、抗性、状态效果叠加、友伤规则、击退、飘字、音效或埋点细节；这些后续应在本入口内扩展，而不是绕过它。状态 DoT 由 `StatusEffectComponent` 计时，但每次 tick 仍通过本入口结算。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 接入新的伤害来源 | `client/scripts/combat/combat.gd` 的 `apply_damage()` |
| 改一次伤害包含哪些字段 | `client/scripts/combat/damage_info.gd` |
| 接敌人 / 玩家受伤 | 对应实体的 `receive_damage(info)` |
| 加伤害类型 | `docs/词表与契约.md` 第 9 节，再跑契约同步 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/combat/combat.gd` | `Combat` autoload，提供 `apply_damage()` |
| `client/scripts/combat/damage_info.gd` | 一次伤害的轻量数据对象 |
| `client/project.godot` | 注册 `Combat` autoload |
| `client/scripts/contracts/damage_types.gd` | 自动生成的伤害类型常量 |

## 场景 / 节点结构

`Combat` 是 autoload singleton，没有 `.tscn` 场景。`DamageInfo` 是 `RefCounted` 数据对象。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 构造伤害 | 调用方创建 `DamageInfo` 并写入伤害数值、类型和 source / target | `DamageInfo.setup()` |
| 申请结算 | 调用方只调用统一入口 | `Combat.apply_damage(target, info)` |
| 合法性校验 | 校验目标有效、伤害类型登记、数值为正、目标实现接收方法 | `damage_types.gd` |
| 目标处理 | 目标实体执行自己的生命值变化和死亡 signal | `receive_damage(info)` |
| 广播结果 | `Combat` 发出一次统一信号，后续埋点 / 飘字可订阅 | `damage_applied` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `DamageInfo.setup(...)` | 伤害数值、伤害类型、来源、目标、队伍、flags | `DamageInfo` | 伤害值会钳到 `>= 0` |
| `Combat.apply_damage(target, info)` | `Node`, `DamageInfo` / `RefCounted` | `Dictionary` | 只接受已登记 `damage_type`；目标必须有 `receive_damage(info)` |

返回字典当前字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `applied` | bool | 是否实际应用 |
| `amount` | float | 实际应用量 |
| `defeated` | bool | 是否导致目标被击败 |
| `reason` | string | 诊断原因 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `damage_applied` | `target`, `info`, `result` | 目标 `receive_damage()` 返回后 |

## 数据与契约

- `damage_type` 必须来自 `docs/词表与契约.md` 第 9 节，并由 `client/scripts/contracts/damage_types.gd` 生成。
- F4 默认武器和敌人接触伤害使用现有 `physical`；burn DoT 使用 `fire` 并在 `DamageInfo.flags` 中带 `is_dot`。
- 本模块不读取数值配置；伤害数值由武器、敌人、机关或状态效果系统从数据中读取后传入。

## 依赖

- 上游依赖：`damage_types.gd` 自动生成常量。
- 下游调用方：F4 子弹、敌人接触伤害、机关、状态效果 DoT、未来遗物行为和伤害飘字。
- 禁止依赖：业务代码不得直接改目标生命值来绕过 `Combat.apply_damage()`。

## 扩展点

- 护甲、抗性、暴击、友伤、状态效果注入都应集中在 `apply_damage()` 内部或其可复用策略中扩展。
- DoT 来源只负责构造 `DamageInfo` 并带 `is_dot` flag；不要在状态组件或技能系统里直接扣目标生命。
- 新 `DamageInfo.flags` 语义先登记词表 / GDD，再补本文档和测试。
- 后续埋点、音效、飘字应订阅 `damage_applied`，不让每个调用点各写一遍。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增伤害类型 | `docs/词表与契约.md` | 本文档、相关数据 | `python tools/sync_contracts.py --check`、`python tools/validate_data.py` |
| 改伤害结果字典 | `combat.gd` | 本文档、调用方模块文档 | GDScript lint + headless boot，后续补 L1 |
| 接状态效果 / 抗性 | `combat.gd` + `docs/代码/status_effect_component.md` 对应系统 | GDD、本文档、测试策略 | L0 + L1 + 必要黄金回放 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 伤害无效 | `damage_type` 是否登记；`amount` 是否大于 0 |
| 控制台报 `missing_receiver` | 目标实体是否实现 `receive_damage(info)` |
| 敌人不死亡 | 目标的生命字段和 `defeated` signal 是否正确 |

## 测试义务

- 本次 F4 首切片跑 L0、语义 advisory 和 L2 headless boot。
- 后续改伤害公式、抗性、暴击或状态效果叠加 / DoT 结算时必须补 L1 单测；若整局行为变化，按 `docs/测试策略.md` 补 L3 黄金回放。

## 迁移 / 兼容

当前不影响存档或回放 schema。未来 `DamageInfo` 进入 run 存档 / 回放关键帧后，字段改名必须配版本处理。

## 相关文档

- `docs/游戏设计文档.md` §9.15.1
- `docs/词表与契约.md` 第 9 节
- `docs/测试策略.md`
- `docs/代码/gameplay_runtime.md`
- `docs/代码/status_effect_component.md`
