# AI 协作（工程化目录）

> 本目录把"AI 怎么协作"沉淀为可复用工程，配合 `游戏设计文档.md` 9.11 节落地。
> 与 `docs/AI记忆/` 的区别：
> - `AI记忆/` 是**项目状态的长期记忆**（项目快照 / ADR / 待决策 / 近期脉络）。
> - `AI协作/` 是**协作方式的工程模板**（任务模板 / 上下文预算 / 角色分工 / 引擎接入 / 实时验证）。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 AI 协作目录索引；新增模板、agent、command、工具适配或协作规则时，必须同步 `AGENTS.md`、`CODEX.md`、`OPENCODE.md`、`.codebuddy/`、`.codex/`、`.opencode/`、`docs/AI导航.md`、`docs/AI协作/工具适配指南.md`、`docs/AI记忆/项目记忆.md`。

## 文件结构

```
AGENTS.md                  # 所有 AI agent 的通用开工入口
CLAUDE.md                  # Claude Code 入口适配
CODEX.md                   # OpenAI Codex CLI 入口适配
OPENCODE.md                # OpenCode 入口适配

docs/AI协作/
├── README.md             # 本文件
├── 文档维护指南.md       # 长期文档修改的联动规则
├── 文档健康检查.md       # docs 知识库健康检查命令与失败解释
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
├── AI技能资源评估.md     # 外部 skills / agents / MCP / rules 资源筛选与安装清单
└── 工具适配指南.md       # 各 AI 工具的接入配法

tools/
├── sync_contracts.py      # 词表 → _contracts.json + GDScript 常量
├── validate_data.py       # 数据 / locale / MVP config 校验
├── docs_health_check.py   # 文档知识库健康检查
└── godot_bridge.py        # MVP 场景树导出 / headless boot 轻量 Bridge

.codebuddy/agents/        # 项目级 subagents（codebuddy 平台；.codex/.opencode 下同名同步）
├── balancer.md              # 平衡测试 / 回放回归 / 数值建议
├── contract-validator.md    # 词表↔常量同步 / 裸字符串扫描
├── data-author.md           # 数据驱动内容创作（不动 .gd）
├── game-designer.md         # 玩法 / 系统设计评审，优缺点与参考对象
├── numeric-designer.md      # 数值模型、曲线、成本、难度节奏
├── ip-designer.md           # 世界观、主题、阵营、怪物生态、长期 IP
├── copywriter-packager.md   # UI / 道具 / 宣传语文案包装，中英文草案
├── ui-art-designer.md       # HUD、菜单、界面层级、UI 美术 brief
├── game-art-designer.md     # 角色、敌人、场景、特效、资产 brief
└── marketing-strategist.md  # 宣发定位、卖点、Steam 页面、预告片策略

.codebuddy/commands/      # 项目级 slash commands（codebuddy 平台）
├── sync-contracts.md     # /sync-contracts
├── new-relic.md          # /new-relic <概念>
├── run-replay-regression.md
├── health-check.md
└── update-memory.md

.codex/                   # Codex CLI 平台配置；核心语义一致，可按 Codex 优化
├── agents/
├── commands/
└── rules/

.opencode/                # OpenCode 平台配置；核心语义一致，可按 OpenCode 优化
├── opencode.json          # 指令加载 + command 注册
├── agents/
├── commands/
├── skills/                # 项目级 OpenCode skills（按需加载的可复用流程）
├── vendor/ai-resources/   # 外部 AI 资源整包 submodule（上游来源）
└── rules/

.agents/skills/            # Agent Skills；当前安装 headless-godot 与 CCGS 跨平台适配

.claude/                   # Claude Code Game Studios 工具（agents / skills / hooks / rules；不含模板）
```

关联根目录文档：`docs/AI知识库索引.md` 与 `docs/_kb_index.json` 管理知识库元数据，`docs/术语表.md` 管理术语别名，`docs/AI记忆/current_state.json` 管理机器可读当前状态，`docs/代码文档规范.md` 定义代码变更与对应文档的同步规则，`docs/代码/` 存放长期详细模块文档。

## 触发约定

AI agent 接到任务时优先按以下顺序：

1. **是不是有专属 slash command**？是 → 直接用（如 `/new-relic`）。
2. **是不是该转给 subagent**？数据条目改动 → `data-author`；契约校验 → `contract-validator`；平衡相关 → `balancer`；玩法评估 → `game-designer`；数值模型 → `numeric-designer`；世界观 → `ip-designer`；文案包装 → `copywriter-packager`；UI 美术 → `ui-art-designer`；游戏美术 → `game-art-designer`；宣发策略 → `marketing-strategist`。
3. **是不是高频任务**？是则直接套 `任务模板/` 对应文件。
4. **不是高频任务**？读 `上下文预算.md` 决定读取范围，避免盲目全仓搜索。
5. **任务复杂**？参照 `角色分工.md` 切角色（先设计 → 再实现 → 再评审）。
6. **是不是已有项目级 skill**？OpenCode 可加载 `.opencode/skills/` 与 `.agents/skills/`：Godot 实现 / 场景验证 / Godot 测试诊断 / Headless Godot / CCGS 跨平台适配 / 文档同步 / 安全提交 / 事实 review / AI 资源筛选 / MCP 评估；`GodotPrompter` 由 OpenCode plugin 注册；Claude Code 可用 `.claude/` 工具，其他 agent 可通过 `.agents/skills/ccgs-game-studio/SKILL.md` 按需复用 CCGS。
7. **想直接操作引擎**？查 `引擎集成.md` 是否已接入 MCP，再决定走文件还是走引擎 API。
8. **改了词表 / 数据 / 文案**？跑 `python tools/sync_contracts.py --check` 与 `python tools/validate_data.py`。
9. **改完了**？让 `实时验证回路.md` 描述的 hook 在秒级反馈是否合规。

## 维护

- 新高频任务出现 → 在 `任务模板/` 加一份。
- 新长期文档 / 术语 / 知识库路径变化 → 同步 `docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/术语表.md`，并运行 `python tools/docs_health_check.py`。
- 引擎工具链变化 → 更新 `引擎集成.md`。
- AI skills / MCP / plugin / rules 资源变化 → 更新 `AI技能资源评估.md`、`.opencode/skills/`、`.agents/skills/`、`.claude/` 或 `.opencode/vendor/ai-resources/`、`OPENCODE.md` 与工具适配指南。
- 角色分工经验积累 → 微调 `角色分工.md`。
- 新代码模块 / 公共 API / 数据 schema 变化 → 按 `docs/代码文档规范.md` 同步详细的 `docs/代码/` 模块文档；数值字段同步 `client/data/README.md`，文案 / 语言 / 占位符同步 `client/locale/README.md`。
- 平台入口变化 → 同步 `AGENTS.md` / `CLAUDE.md` / `CODEX.md` / `OPENCODE.md` / `.codebuddy/` / `.codex/` / `.opencode/` / `.agents/skills/` / `工具适配指南.md`。
- 重大变更 → 同步进 `决策记录.md` + `AI记忆/项目记忆.md`。
