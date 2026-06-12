# AGENTS.md —— 给所有 AI agent 的开工说明

> 任何 AI agent 在本项目动手前，**必须先按下面顺序读完这 5 份文件**，再开始任何任务。
> 这是规则 14 与 ADR #15 的明文化入口；忽略此约定 = 违反项目规则。

---

## 🚦 开工 5 步（按顺序，不要跳）

1. **本文件**（`AGENTS.md`）—— 你正在读的这份
2. **`docs/AI记忆/项目记忆.md`** —— **跨会话/跨机器的项目长时记忆**
   - 项目快照（v1.5、Godot 4.6.3 + GDScript、文档阶段）
   - 28 条 ADR 摘要
   - 待决策项（A~D）
   - 工具链与基础设施现状
   - **下一步候选**（最关键，告诉你现在该干什么）
3. **`.codebuddy/rules/game-coding-rules.md`** —— 强制编码规则（含 12-A/B/C/D 等基础设施约束 + 自检清单）
4. **`docs/AI导航.md`** —— 项目地图、扩展点速查、系统依赖图
5. **按当前任务读下列其一**：
   - 高频任务 → `docs/AI协作/任务模板/<任务>.md`
   - 改约定字符串 → `docs/词表与契约.md`
   - 改设计 → `docs/游戏设计文档.md`
   - 改既定决策 → `docs/决策记录.md`
   - 写/改测试 → `docs/测试策略.md`

读完这 5 步就能"接得上"，无需翻历史聊天。

---

## ⛓️ 三条不可妥协的规则（红线节选）

完整列表见 `.codebuddy/rules/game-coding-rules.md` 与 `docs/AI导航.md` 第 6 节红线。这里只抽最易踩的：

1. **数据驱动**：可调数值进 `client/data/*.json`；玩家可见文本走 `tr("key")`；按键走 InputMap action；约定字符串来自 `docs/词表与契约.md` 白名单且以**自动生成的常量**引用。
2. **统一 autoload**：随机 `RNG.<stream>` / 时间 `GameClock` / 流程 `GameState` / UI 弹窗 `UIManager` / 高频实体 `PoolManager` / 伤害 `Combat.apply_damage` / 持续效果 `StatusEffect` / 存档 `SaveManager` / 音频 `AudioManager`。**禁止**绕过这些走原始 API。
3. **改完同步文档**：新规则 → 规则文件；新决策 → ADR；设计变更 → GDD + AI 导航 + 词表；重要对话 → `docs/AI记忆/项目记忆.md`（自动瘦身见规则 14-B）。

---

## 🛠️ 高频任务直通车

如果你的任务是下面这些之一，直接套对应模板（不必重新摸索）：

| 任务 | 模板 |
|------|------|
| 加遗物 / 道具 | `docs/AI协作/任务模板/加遗物.md`（或用 `/new-relic` 命令） |
| 加敌人 | `docs/AI协作/任务模板/加敌人.md` |
| 加效果原语 | `docs/AI协作/任务模板/加效果原语.md` |
| 加设置项 | `docs/AI协作/任务模板/加设置项.md` |
| 加埋点 | `docs/AI协作/任务模板/加埋点.md` |
| 调数值 | `docs/AI协作/任务模板/调数值.md` |
| 加本地化文本 | `docs/AI协作/任务模板/加本地化文本.md` |

任务不在模板里 → 按 `docs/AI协作/上下文预算.md` 决定读取范围（**禁止盲目全仓搜索**）。

## 🤝 子智能体（Subagents，可主动调用）

复杂或专业任务直接转给对应 subagent，避免主对话被污染：

| Subagent | 何时调用 | 定义位置 |
|----------|---------|---------|
| `data-author` | 加 / 改数据条目（遗物 / 敌人 / locale / 设置 / 埋点） | `.codebuddy/agents/data-author.md` |
| `contract-validator` | 改了词表、想检查代码常量 / 裸字符串 / id 同步 | `.codebuddy/agents/contract-validator.md` |
| `balancer` | 跑回放回归 / sim / 数值平衡建议 | `.codebuddy/agents/balancer.md` |

调用方式见 codebuddy 的 Task 工具或对应触发词。

## ⚡ 项目级斜杠命令（Slash Commands）

| 命令 | 用途 | 定义位置 |
|------|------|---------|
| `/sync-contracts` | 跑词表→代码常量同步流水线 | `.codebuddy/commands/sync-contracts.md` |
| `/new-relic <概念>` | 交互式加遗物 | `.codebuddy/commands/new-relic.md` |
| `/run-replay-regression` | 跑黄金回放回归 | `.codebuddy/commands/run-replay-regression.md` |
| `/health-check` | 项目健康度报告 | `.codebuddy/commands/health-check.md` |
| `/update-memory` | 显式兜底触发记忆更新 | `.codebuddy/commands/update-memory.md` |

---

## 📝 改完之后

按编码规则末尾的「自检清单」逐条核对；按 `docs/测试策略.md` §7 表履行测试义务；改了重要内容就更新 `docs/AI记忆/项目记忆.md`（按其第 9 节「自动瘦身」规则维护）。

不确定写什么？参照本目录最近的 ADR 风格（`docs/决策记录.md`）：**一句话决策 + 一句话理由**。

---

> 本文件由项目维护者人为定义；AI agent 不得未经允许修改。
> 若在新平台/新 IDE 中此文件未被自动加载，请用户在对话开始时显式提示："先读 `AGENTS.md`"。
