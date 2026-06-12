# AI 协作（工程化目录）

> 本目录把"AI 怎么协作"沉淀为可复用工程，配合 `游戏设计文档.md` 9.11 节落地。
> 与 `docs/AI记忆/` 的区别：
> - `AI记忆/` 是**项目状态的长期记忆**（项目快照 / ADR / 待决策 / 近期脉络）。
> - `AI协作/` 是**协作方式的工程模板**（任务模板 / 上下文预算 / 角色分工 / 引擎接入 / 实时验证）。

## 文件结构

```
docs/AI协作/
├── README.md             # 本文件
├── 任务模板/             # 高频任务的标准 prompt + 文件操作清单
│   ├── 加遗物.md
│   ├── 加敌人.md
│   ├── 加效果原语.md
│   ├── 加设置项.md
│   ├── 加埋点.md
│   ├── 调数值.md
│   └── 加本地化文本.md
├── 上下文预算.md         # 不同任务该读哪些文件、读多少
├── 角色分工.md           # 设计/实现/评审/平衡 四角色协作
├── 引擎集成.md           # Godot/Unity MCP 等接入指南
├── 实时验证回路.md       # pre-commit hook + watch 脚本设计
└── 工具适配指南.md       # 不用 CodeBuddy 时各 AI 工具的接入配法

.codebuddy/agents/        # 项目级 subagents（codebuddy 平台）
├── balancer.md           # 平衡测试 / 回放回归 / 数值建议
├── contract-validator.md # 词表↔常量同步 / 裸字符串扫描
└── data-author.md        # 数据驱动内容创作（不动 .gd）

.codebuddy/commands/      # 项目级 slash commands（codebuddy 平台）
├── sync-contracts.md     # /sync-contracts
├── new-relic.md          # /new-relic <概念>
├── run-replay-regression.md
├── health-check.md
└── update-memory.md
```

## 触发约定

AI agent 接到任务时优先按以下顺序：

1. **是不是有专属 slash command**？是 → 直接用（如 `/new-relic`）。
2. **是不是该转给 subagent**？数据条目改动 → `data-author`；契约校验 → `contract-validator`；平衡相关 → `balancer`。
3. **是不是高频任务**？是则直接套 `任务模板/` 对应文件。
4. **不是高频任务**？读 `上下文预算.md` 决定读取范围，避免盲目全仓搜索。
5. **任务复杂**？参照 `角色分工.md` 切角色（先设计 → 再实现 → 再评审）。
6. **想直接操作引擎**？查 `引擎集成.md` 是否已接入 MCP，再决定走文件还是走引擎 API。
7. **改完了**？让 `实时验证回路.md` 描述的 hook 在秒级反馈是否合规。

## 维护

- 新高频任务出现 → 在 `任务模板/` 加一份。
- 引擎工具链变化 → 更新 `引擎集成.md`。
- 角色分工经验积累 → 微调 `角色分工.md`。
- 重大变更 → 同步进 `决策记录.md` + `AI记忆/项目记忆.md`。
