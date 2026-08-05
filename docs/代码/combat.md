# Combat / 七元素与防御层模块

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是统一伤害入口、七元素和玩家防御层的权威代码契约。

## 职责

- 所有显式攻击、投射物、机关伤害与状态 tick 都必须走 `Combat.apply_damage(target, DamageInfo)`；敌人身体重叠不构造伤害请求。
- `DamageInfo` 承载 `amount`、`element_id`、source / target、双方 team 与通用 flags。
- `Combat` 校验目标、正数伤害与已登记元素，再调用目标 `receive_damage(info)`；具体护盾、护甲、被动抗性和状态易伤由目标的可复用处理链结算。
- 旧 `damage_type`、物理／真实伤害、穿甲与 `pierce_armor` 已删除。

## 代码与数据

| 路径 | 作用 |
|------|------|
| `client/scripts/combat/combat.gd` | 统一 autoload 门面与 `damage_applied` signal |
| `client/scripts/combat/damage_info.gd` | 单次伤害数据 |
| `client/scripts/contracts/elements.gd` | 七元素生成常量 |
| `client/data/elements.json` | 组合表与显示策略 |
| `client/scripts/gameplay/player.gd` | 超量护盾、普通护盾、护盾门、元素被动、护甲和生命 |
| `client/scripts/gameplay/enemy.gd` | 显式攻击提交、爆炸来源例外、击杀 / 掉落归因 |
| `client/scripts/combat/status_effect_component.gd` | 易伤来源过滤与 DoT |

## 七元素

稳定 ID：`element_neutral`、`element_primary_a`、`element_primary_b`、`element_primary_c`、`element_composite_ab`、`element_composite_bc`、`element_composite_ca`。

- A+B→AB、B+C→BC、C+A→CA；中性与任意元素组合为该元素；相同元素仍为自身。
- 复合元素不继续自动合成，除非以后在表中显式增加规则。
- 现有武器、敌人、投射物、机关和状态伤害默认迁移为中性。
- 冷静主英雄只对纯 A 伤害乘 `0.6`；愤怒主英雄只对纯 B 乘 `0.6`，复合元素不触发被动。

## 玩家防御结算

伤害顺序固定：

1. 超量护盾；
2. 普通护盾；
3. 对剩余生命伤害应用纯元素被动；
4. 应用护甲；然后扣生命。

护甲公式：`damage_multiplier = 1.0 - armor / (armor + 300)`；护甲校验范围 `0～1200`，最大减伤 80%。

普通护盾受伤后延迟 4 秒，以 25/秒恢复。超量护盾无上限，从获得后立即按当前值 5%/秒指数衰减，低于 1 归零；暂停时两者都不推进。

普通护盾从正值被一次攻击击破时触发护盾门：本次溢出全部吞掉，无敌时间为 `0.5 × clamp(shield_before / max_shield, 0, 1)`。超量护盾不增加持续时间；普通护盾原本为零不触发。旧“每次受伤统一 0.7 秒无敌”已删除。

冲刺的 0.12 秒无敌是独立窗口，不改变护盾门规则。

## 状态与来源过滤

- 易伤每层使 `team_player` 来源的直接或 DoT 伤害增加 10%，最多 5 层；其他来源不放大。
- 状态 DoT 通过 `DamageInfo.flags=["is_dot"]` 标记并继续走 Combat。
- 敌人不再拥有通用接触伤害或接触计时器。爆炸、扇区近战、冲撞扫掠与远程投射物各自在明确提交点构造一次 `DamageInfo`。
- `team_enemy` 伤害默认由 `Enemy.receive_damage()` 拒绝；只有来源节点仍处于已提交爆猎者状态时，爆炸才可伤害其他敌人。普通敌人被炸死按 `enemy_explosion` 计击杀并掉落，实际爆炸的爆猎者按 `exploder_detonation` 无奖励退场。
- 冲撞接触玩家后立即把本次释放标记为已命中，最多尝试一次伤害。只有 `Combat` 返回实际应用且 amount 大于零时，壁垒者才调用玩家外部击退；玩家无敌、冲刺规避或完全抵消时不击退。

## 公共 API

| API | 约束 |
|-----|------|
| `DamageInfo.setup(amount, element_id, source, target, source_team, target_team, flags)` | amount 钳到非负；element 必须来自生成契约 |
| `Combat.apply_damage(target, info) -> Dictionary` | 目标必须实现 `receive_damage(info)`；无效请求返回明确 reason |
| `Player.receive_damage(info) -> Dictionary` | 返回实际分层消耗、生命损失、护盾门和击败结果 |
| `Enemy.receive_damage(info) -> Dictionary` | armed 早退；普通敌方友伤早退；玩家或合法爆炸来源按 cause 进入统一退场信号 |

`damage_applied(target, info, result)` 在目标完成结算后发出，表现、埋点和归因可订阅，不得复制伤害计算。

## 扩展边界

- 新元素先改词表与 `elements.json` 组合表，再同步生成常量、数据校验、GDD 和测试；不能靠业务裸字符串扩展。
- 暴击、不可致死、自伤、DoT 等仍可作为与元素无关的 flag；新 flag 必须登记契约。
- 屏障只接受敌方投射物扫掠命中，不拦角色移动、近战、冲撞、环境或 AOE；其生命损失仍使用合法 `DamageInfo`。

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 伤害无效 | `element_id` 是否登记、amount 是否大于零、目标是否实现 receiver |
| 复合元素被英雄被动减伤 | 被动表是否只列纯 A / B，组合解析是否误把复合映射回基础元素 |
| 空盾仍触发门 | 攻击前普通护盾是否确实大于零；超量护盾不得作为门前值 |
| 敌人身体重叠仍扣血 | `Enemy` 是否残留接触检测；`enemies.csv` 是否错误恢复旧 contact 列 |
| 敌方任意伤害绕过友伤护栏 | source 是否真实处于 `is_committed_exploder()`，爆炸提交后是否仍只使用一次 |
| 玩家规避后仍被击退 | 冲撞调用方是否检查 `result.applied` 与实际 `amount > 0` |

## 测试义务

- `sync_contracts.py --check`、`validate_data.py`、schema test 和三档 lint。
- `l1-smoke` 覆盖三层顺序、空／半／满盾门、恢复、超盾衰减、护甲公式、纯元素抗性、复合不减伤、易伤来源过滤与 DoT。
- `runtime-smoke`、`save-smoke`、`headless-boot` 和四条 Replay v4 黄金回放覆盖整局与恢复。

## 迁移边界

Run v12 保存生命、普通护盾、超量护盾、护盾门、元素被动、玩家敌人击退、Enemy 显式攻击 / armed / 生成序号、锁定金币及世界事件目标上下文，不含弹药字段；旧 Run v11 明确不兼容。Replay v4 删除 `reload` 输入语义和弹药摘要，数据指纹与黄金摘要随当前行为重录。

## 相关文档

- `docs/游戏设计文档.md` §9.15
- `docs/代码/status_effect_component.md`
- `docs/代码/skill_system.md`
- `docs/代码/gameplay_runtime.md`
- `docs/词表与契约.md`
- `docs/测试策略.md`
