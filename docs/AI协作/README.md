# AI 协作（工程化目录）

> 本目录把"AI 怎么协作"沉淀为可复用工程，配合 `游戏设计文档.md` 9.11 节落地。
> 与 `docs/AI记忆/` 的区别：
> - `AI记忆/` 是**项目状态的长期记忆**（项目快照 / ADR / 待决策 / 近期脉络）。
> - `AI协作/` 是**协作方式的工程模板**（任务模板 / 上下文预算 / 角色分工 / 引擎接入 / 实时验证）。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 AI 协作目录索引；新增模板、agent、command、skill、工具适配或协作规则时，必须同步 `AGENTS.md`、`CLAUDE.md`、`CODEX.md`、`OPENCODE.md`、`.codebuddy/`、`.codex/`、`.opencode/`、`docs/AI导航.md`、`docs/AI协作/工具适配指南.md`、`docs/AI记忆/项目记忆.md`。

## 文件结构

```
AGENTS.md                  # 所有 AI agent 的通用开工入口
CLAUDE.md                  # Claude Code 入口适配
CODEX.md                   # OpenAI Codex CLI 入口适配
OPENCODE.md                # OpenCode 入口适配

docs/AI协作/
├── README.md             # 本文件
├── 快速开工.md           # 日常接手的低 token 热路径
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
├── 工作包/               # 正式项目阶段任务的低 token 工作包
│   ├── F3-DataLoader.md
│   ├── F4-MinPlayableLoop.md
│   ├── F6-MetaProgression.md
│   ├── F7-SettingsLocalizationUI.md
│   └── F8-ReplayTestingBalance.md
├── 上下文预算.md         # 不同任务该读哪些文件、读多少
├── 角色分工.md           # 设计/实现/评审/平衡 四角色协作
├── 代码审核流程.md       # 工具先行、LLM 聚焦 diff 的 review SOP
├── 引擎集成.md           # Godot/Unity MCP 等接入指南
├── 实时验证回路.md       # pre-commit hook + watch 脚本设计
├── AI技能资源评估.md     # 外部 skills / agents / MCP / rules 资源筛选与安装清单
├── ECC工具吸收清单.md    # ECC 全工具面逐项筛选、吸收和拒绝结论
└── 工具适配指南.md       # 各 AI 工具的接入配法

tools/
├── check_staged_whitespace.py # pre-commit staged whitespace 检查，排除 draft / DRAFT
├── sync_contracts.py      # 词表 → _contracts.json + GDScript 常量
├── validate_data.py       # 正式数据 / locale 校验
├── test_data_loader_schema.py # DataLoader schema 回归坏样例测试
├── lint_gdscript_rules.py # 第一档 GDScript 项目规则 lint
├── lint_project_rules.py  # 第二档项目规则 lint：数据字段文档、locale 双语、release debug 资源边界
├── test_project_rules_lint.py # 项目规则 lint 坏样例回归测试
├── lint_semantic_rules.py # 第三档非阻塞语义 advisory lint：特殊 id 分支、autoload 绕过、类型 / Doc / contract 常量风险
├── test_semantic_rules_lint.py # 语义 advisory lint 坏样例回归测试
├── docs_health_check.py   # 文档知识库健康检查
└── godot_bridge.py        # 正式 client 场景树导出 / headless boot / runtime / Settings / Meta / Save / F8 runner / golden capture 轻量 Bridge

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
├── skills/                # 项目级 skills（按需加载的可复用流程）
└── rules/
```

关联根目录文档：`docs/AI知识库索引.md` 与 `docs/_kb_index.json` 管理知识库元数据，`docs/术语表.md` 管理术语别名，`docs/AI记忆/current_state.json` 管理机器可读当前状态，`docs/AI记忆/项目记忆.md` 作为长期冷存储，`docs/代码文档规范.md` 定义代码变更与对应文档的同步规则，`docs/代码/` 存放长期详细模块文档。

## 触发约定

AI agent 接到任务时优先按以下顺序：

1. **先完成快速开工**：读 `快速开工.md`、`current_state.json`、当前平台规则入口和 `AI导航.md` 相关段落。
2. **是不是有专属 slash command**？是 → 直接用（如 `/new-relic`）。
3. **是不是该转给 subagent**？数据条目改动 → `data-author`；契约校验 → `contract-validator`；平衡相关 → `balancer`；玩法评估 → `game-designer`；数值模型 → `numeric-designer`；世界观 → `ip-designer`；文案包装 → `copywriter-packager`；UI 美术 → `ui-art-designer`；游戏美术 → `game-art-designer`；宣发策略 → `marketing-strategist`。
4. **是不是正式项目阶段任务**？优先读 `工作包/`；当前 F8 用 `工作包/F8-ReplayTestingBalance.md`，F7 设置 / 本地化 / UI 栈维护看 `工作包/F7-SettingsLocalizationUI.md`，F6 局外成长闭环看 `工作包/F6-MetaProgression.md`，F4 最小可玩闭环看 `工作包/F4-MinPlayableLoop.md`，历史 F3 数据闭环看 `工作包/F3-DataLoader.md`。
5. **是不是高频任务**？是则直接套 `任务模板/` 对应文件。
6. **不是高频任务**？读 `上下文预算.md` 决定读取范围，避免盲目全仓搜索。
7. **任务复杂**？参照 `角色分工.md` 切角色（先设计 → 再实现 → 再评审）。
8. **是不是已有项目级 skill**？CodeBuddy / Codex / OpenCode 均有同名项目级 skill（`.codebuddy/skills/` / `.codex/skills/` / `.opencode/skills/`）：Godot 实现 / 场景验证 / Godot 测试诊断 / 试玩复盘 / 文档同步 / 安全提交 / 事实 review / AI 资源筛选与协作面审计 / MCP 评估；外部 GodotPrompter / headless-godot / CCGS / ECC 的有用流程已吸收进这些项目 skill，不再通过 reference 跳转。
9. **想直接操作引擎**？查 `引擎集成.md` 是否已接入 MCP，再决定走文件还是走引擎 API。
10. **改了词表 / 数据 / 文案 / GDScript**？跑 `python tools/sync_contracts.py --check`、`python tools/validate_data.py`、`python tools/lint_gdscript_rules.py`、`python tools/lint_project_rules.py` 与非阻塞 `python tools/lint_semantic_rules.py`；改 F4 运行时追加 `python tools/godot_bridge.py --project client runtime-smoke`；改 Settings 持久化 / 回退 / 设置面板追加 `python tools/godot_bridge.py --project client settings-smoke`，改标题 / 暂停设置入口再追加 `runtime-smoke`；改 MetaProgression / 局外成长结算追加 `python tools/godot_bridge.py --project client meta-smoke`；改 SaveManager / run 存档 / 续局 schema 追加 `python tools/godot_bridge.py --project client save-smoke`；改 F8 测试 / 回放 / 采样入口追加 `l1-smoke`、`replay-smoke`、`replay-runner`、`capture-golden-replay`、`replay-runner --replay-file client/tests/replays/golden_basic_run.replay --rerun-runtime-summary`、`perf-probe`；改 DataLoader、项目规则 lint 或语义 lint schema 时追加对应 `test_*.py` 回归。
11. **改完了**？让 `实时验证回路.md` 描述的 hook 在秒级反馈是否合规；大型代码改动提交前按 `代码审核流程.md` 追加一次工具先行的事实型 code review，小改动不触发正式 review。

## 维护

- 新高频任务出现 → 在 `任务模板/` 加一份。
- 新正式项目阶段反复消耗上下文 → 在 `工作包/` 加一份短工作包。
- 新长期文档 / 术语 / 知识库路径变化 → 同步 `docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/术语表.md`，并运行 `python tools/docs_health_check.py`。
- 引擎工具链变化 → 更新 `引擎集成.md`。
- AI skills / MCP / plugin / rules / agent-harness 资源变化 → 更新 `AI技能资源评估.md`、必要时更新来源专属清单（如 `ECC工具吸收清单.md`）、`.codebuddy/skills/`、`.codex/skills/`、`.opencode/skills/`、`CODEX.md`、`OPENCODE.md` 与工具适配指南；新增或吸收资源后用 `ai-resource-curator` 的 AI surface audit 检查重复、上下文成本、验证门禁和安全边界。
- 角色分工经验积累 → 微调 `角色分工.md`。
- 新代码模块 / 公共 API / 数据 schema 变化 → 按 `docs/代码文档规范.md` 同步详细的 `docs/代码/` 模块文档；数值字段同步 `client/data/README.md`，文案 / 语言 / 占位符同步 `client/locale/README.md`。
- 平台入口变化 → 同步 `AGENTS.md` / `CLAUDE.md` / `CODEX.md` / `OPENCODE.md` / `.codebuddy/` / `.codex/` / `.opencode/` / `工具适配指南.md`。
- 重大变更 → 同步进 `决策记录.md` + `AI记忆/项目记忆.md`。
