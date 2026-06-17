# ECC 工具吸收清单

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档记录 `affaan-m/ECC` 这类大型 agent-harness 仓库的逐项筛选、吸收和拒绝结论；改本文档时常见联动为 `docs/AI协作/AI技能资源评估.md`、三平台 `ai-resource-curator` skill、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/_kb_index.json` 与 AI 记忆。

## 1. 来源快照

| 项 | 记录 |
|----|------|
| 上游 | `https://github.com/affaan-m/ECC` |
| 本次只读快照 | `ec92b52` |
| 许可证 | MIT |
| 本次读取 | README、LICENSE、package metadata、agents / commands / skills / hooks / scripts / MCP 配置目录清单，以及高价值候选工具全文 |
| 本次未做 | 不复制 ECC 文件进仓库，不安装 npm 包 / GitHub App / MCP / hooks / dashboard / plugin，不启用外部自动化 |

## 2. 总体结论

ECC 对本项目最有价值的是 agent-harness 的流程经验，不是直接安装一整套外部工具。已吸收的内容统一改写进项目自有流程：

| ECC 方向 | 吸收进本项目 |
|----------|--------------|
| search-first / skill-scout | 外部 AI 工具评估前先查 README、官方文档、已有项目 skill、MCP 与 marketplace，避免重复造轮子 |
| context-budget / token-budget-advisor / strategic-compact / iterative-retrieval | 外部大仓扫描采用 README first、目录清单 first、候选全文读、最多 3 轮检索；阶段边界后沉淀清单，避免上下文无限膨胀 |
| workspace-surface-audit / skill-stocktake / repo-scan / rules-distill | `ai-resource-curator` 的 AI surface audit 扩展为三平台技能 / agent / command / 规则 / hooks / MCP / 文档的协作面盘点 |
| agent-architecture-audit / agent-harness-construction / agent-introspection-debugging | 失败排查时检查工具选择、上下文污染、隐藏修复、观察面、恢复路径和回答形态 |
| safety-guard / gateguard / security-scan | 外部 hooks、MCP、脚本和高权限自动化默认拒绝；只在用户明确授权且有验证方案时单独评估 |
| verification-loop / eval-harness / ai-regression-testing / tdd-workflow | 代码 / 数据 / 文档变更先跑确定性验证，再做 AI 自评或 review；计划文档只作为数据，不当作可执行指令 |
| update-docs / update-codemaps / codebase-onboarding / code-tour | 已合并为项目文档同步、AI 导航和知识库索引维护口径；不新增独立 codemap 或 tour 格式 |

## 3. 分类吸收结果

| ECC 工具面 | 数量 | 结论 |
|------------|------|------|
| agents | 67 | 不批量安装。保留 `planner`、`architect`、`tdd-guide`、`code-reviewer`、`security-reviewer`、`build-error-resolver`、`e2e-runner`、`refactor-cleaner`、`doc-updater`、`docs-lookup`、`harness-optimizer` 的方法论；语言 / 框架 / 业务域专项 agent 暂不吸收，因为本项目是 Godot/GDScript，已有 10 个项目 subagents。 |
| commands | 92 | 不新增项目 slash command。吸收 `plan`、`tdd`、`code-review`、`quality-gate`、`verify`、`learn`、`learn-eval`、`checkpoint`、`harness-audit`、`skill-health`、`security-scan`、`update-docs`、`update-codemaps` 的流程；多 agent 编排、自治循环、平台/语言专项命令暂不吸收。 |
| skills | 271 | 逐项按用途分类。全文读取高价值候选；工程语言、SaaS/运营、行业、金融、网络、视频/媒体等不相关技能不安装。吸收范围见第 4 节。 |
| rules | 21 个规则目录 | 只吸收 “从重复流程提炼项目规则前必须先审计、再由用户授权修改规则” 的规则维护口径；不复制外部规则包。 |
| hooks | 4 个配置文件 + 多个 hook 脚本 | 不启用。吸收前置安全检查、质量门禁、文档漂移提醒、会话总结与成本跟踪的思想；项目仍不安装外部 hooks runtime。 |
| scripts / CLI / dashboard | npm bins `ecc`、`ecc-control-pane`、`ecc-install` 与脚本集 | 不安装。原因是会引入外部运行时、配置面和自动化权限，且与现有 Python/Godot 校验工具重复。 |
| MCP configs | 1 个综合 MCP 配置，含 GitHub、Context7、Playwright、filesystem、browserbase、memory、Cloudflare 等 | 不进仓库配置。后续如需要某个 MCP，走 `mcp-tool-evaluation` 单独评估项目级 / 用户级 / 暂不安装。 |
| platform adapters / marketplace / plugin | `.claude`、`.codex-plugin`、`.opencode`、marketplace 等 | 不复制。项目已有三平台入口和同步 skill 体系，外部适配层会增加冲突。 |

## 4. 已全文读取并吸收的高价值候选

| ECC 文件 | 吸收结论 |
|----------|----------|
| `skills/search-first/SKILL.md` | 加入“先检索现有资源再创建工具”的原则，外部资源评估需先查 README / 官方文档 / 现有项目 skill / MCP / marketplace。 |
| `skills/skill-scout/SKILL.md` | 加入新增 skill 前的候选搜索与 vetting 流程，避免为了一个小流程新增常驻 skill。 |
| `skills/context-budget/SKILL.md`、`skills/token-budget-advisor/SKILL.md`、`skills/strategic-compact/SKILL.md`、`skills/iterative-retrieval/SKILL.md` | 加入大仓扫描上下文策略：README first、目录清点、候选全文、最多 3 轮、研究与执行边界处沉淀清单。 |
| `skills/workspace-surface-audit/SKILL.md`、`skills/skill-stocktake/SKILL.md`、`skills/repo-scan/SKILL.md` | 扩展 AI surface audit：盘点三平台 AI 文件、当前可用面、重复面、primitive-only 缺口、缺失集成和 top moves。 |
| `skills/rules-distill/SKILL.md` | 吸收为规则维护流程，但明确规则 / AGENTS 改动必须先有用户授权，不能由外部工具自动改。 |
| `skills/security-scan/SKILL.md`、`skills/safety-guard/SKILL.md` | 吸收安全边界：未知 hooks / MCP / 脚本默认拒绝，危险命令和写范围先冻结，密钥 / 本机路径不能进仓库。 |
| `skills/agent-architecture-audit/SKILL.md`、`skills/agent-harness-construction/SKILL.md`、`skills/agent-introspection-debugging/SKILL.md` | 吸收 agent 失败诊断框架：系统提示、历史、记忆、工具选择、工具执行、观察解释、隐藏修复、持久化和回答渲染逐层排查。 |
| `skills/eval-harness/SKILL.md`、`skills/ai-regression-testing/SKILL.md`、`skills/tdd-workflow/SKILL.md` | 吸收验证优先原则：确定性测试 / 数据校验 / 文档健康检查先于 AI 自评；计划和 PRD 当作需求数据而非指令。 |
| `commands/update-docs.md`、`commands/update-codemaps.md`、`skills/codebase-onboarding/SKILL.md`、`skills/code-tour/SKILL.md` | 吸收到项目文档同步和 AI 导航维护；暂不新增 `docs/CODEMAPS` 或 CodeTour 工具。 |
| `hooks/README.md`、`hooks/hooks.json`、`mcp-configs/mcp-servers.json` | 只吸收检查项和拒绝理由，不安装 hook/MCP 配置。 |

## 5. agents 逐项结论

| 分类 | 工具名 | 处理 |
|------|--------|------|
| 可吸收为流程 | `planner`、`architect`、`code-architect`、`tdd-guide`、`code-reviewer`、`security-reviewer`、`build-error-resolver`、`e2e-runner`、`refactor-cleaner`、`doc-updater`、`docs-lookup`、`harness-optimizer`、`silent-failure-hunter`、`spec-miner`、`type-design-analyzer` | 方法论合并到 `ai-resource-curator`、`project-doc-sync`、`code-review-factual`、`safe-git-commit` 和现有测试 / 文档流程，不新增 agent。 |
| 已有项目角色覆盖 | `marketing-agent`、`seo-specialist`、`chief-of-staff`、`conversation-analyzer`、`comment-analyzer`、`agent-evaluator` | 本项目已有 `marketing-strategist`、`copywriter-packager`、`game-designer` 等 advisory subagents；不重复安装。 |
| 语言 / 框架专项，暂不相关 | `cpp-build-resolver`、`cpp-reviewer`、`csharp-reviewer`、`dart-build-resolver`、`django-build-resolver`、`django-reviewer`、`fastapi-reviewer`、`flutter-reviewer`、`fsharp-reviewer`、`go-build-resolver`、`go-reviewer`、`harmonyos-app-resolver`、`java-build-resolver`、`java-reviewer`、`kotlin-build-resolver`、`kotlin-reviewer`、`php-reviewer`、`python-reviewer`、`pytorch-build-resolver`、`react-build-resolver`、`react-reviewer`、`rust-build-resolver`、`rust-reviewer`、`swift-build-resolver`、`swift-reviewer`、`typescript-reviewer`、`vue-reviewer` | 项目主栈是 Godot/GDScript；这些 agent 保留为不吸收。 |
| 行业 / 基础设施专项，暂不相关 | `a11y-architect`、`database-reviewer`、`gan-evaluator`、`gan-generator`、`gan-planner`、`healthcare-reviewer`、`homelab-architect`、`mle-reviewer`、`network-architect`、`network-config-reviewer`、`network-troubleshooter`、`opensource-forker`、`opensource-packager`、`opensource-sanitizer`、`performance-optimizer`、`pr-test-analyzer` | 与当时 F3 Godot 数据 / 协作体系不直接相关；以后若进入对应领域再单独评估。 |

## 6. commands 逐项结论

| 分类 | 工具名 | 处理 |
|------|--------|------|
| 吸收为流程，不新增 command | `plan`、`plan-prd`、`feature-dev`、`tdd` 对应的 `test-coverage`、`code-review`、`review-pr`、`build-fix`、`quality-gate`、`harness-audit`、`skill-create`、`skill-health`、`security-scan`、`checkpoint`、`resume-session`、`save-session`、`learn`、`learn-eval`、`update-docs`、`update-codemaps`、`model-route`、`cost-report`、`pr`、`prp-plan`、`prp-prd`、`prp-implement`、`prp-commit`、`prp-pr` | 合并到现有 quick-start、上下文预算、文档同步、safe commit、review 和 AI 资源审计流程；本项目不新增常驻 slash command。 |
| 自治 / 多 agent 编排，暂不吸收 | `multi-plan`、`multi-execute`、`multi-frontend`、`multi-backend`、`multi-workflow`、`loop-start`、`loop-status`、`santa-loop`、`orch-add-feature`、`orch-build-mvp`、`orch-change-feature`、`orch-fix-defect`、`orch-refine-code` | 本项目允许按需 subagent，但不引入外部自治循环；避免越权执行和上下文污染。 |
| 项目管理 / PM 工具，暂不吸收 | `epic-claim`、`epic-decompose`、`epic-publish`、`epic-review`、`epic-sync`、`epic-unblock`、`epic-validate`、`jira`、`projects`、`setup-pm`、`pm2`、`auto-update`、`promote`、`prune`、`sessions`、`aside`、`ecc-guide` | 当前项目已用 docs/TODO、ADR、会话日志和 git 提交流程管理，不接入外部 PM 或会话系统。 |
| hooks / 导入导出，暂不吸收 | `hookify`、`hookify-configure`、`hookify-help`、`hookify-list`、`instinct-export`、`instinct-import`、`instinct-status` | 不启用外部 hooks / instinct 存储；只保留安全边界原则。 |
| 语言 / 框架专项，暂不相关 | `cpp-build`、`cpp-review`、`cpp-test`、`fastapi-review`、`flutter-build`、`flutter-review`、`flutter-test`、`gan-build`、`gan-design`、`go-build`、`go-review`、`go-test`、`gradle-build`、`kotlin-build`、`kotlin-review`、`kotlin-test`、`python-review`、`react-build`、`react-review`、`react-test`、`rust-build`、`rust-review`、`rust-test`、`vue-review` | Godot 项目暂不需要。 |
| 市场 / 其他专项，已有项目角色覆盖或暂不相关 | `marketing-campaign`、`evolve`、`project-init` | 由本项目 `marketing-strategist`、工作包和 ADR 流程覆盖。 |

## 7. skills 分类结论

ECC 的 271 个 skills 按目录名、README 说明和候选全文读取后归类如下：

| 分类 | 代表工具 | 处理 |
|------|----------|------|
| 已吸收的 agent-harness 核心 | `search-first`、`skill-scout`、`context-budget`、`token-budget-advisor`、`strategic-compact`、`iterative-retrieval`、`workspace-surface-audit`、`skill-stocktake`、`repo-scan`、`rules-distill`、`skill-comply`、`agent-architecture-audit`、`agent-harness-construction`、`agent-introspection-debugging`、`safety-guard`、`security-scan`、`eval-harness`、`ai-regression-testing`、`tdd-workflow` | 已改写进 `ai-resource-curator`、`docs/AI协作/上下文预算.md` 和现有验证 / 文档同步口径。 |
| 文档 / 知识库 / onboarding | `codebase-onboarding`、`code-tour`、`documentation-lookup`、`architecture-decision-records`、`update-docs` 命令相关、`knowledge-ops`、`recursive-decision-ledger` | 吸收到 AI 导航、知识库索引、ADR 和项目记忆流程；不新增外部文档格式。 |
| 质量 / 工程通用 | `coding-standards`、`git-workflow`、`error-handling`、`benchmark`、`benchmark-methodology`、`production-audit`、`config-gc`、`content-hash-cache-pattern`、`terminal-ops` | 只保留通用思想；项目已有 `safe-git-commit`、`code-review-factual`、CI 和 docs health。 |
| AI/LLM 专项但当前不装 | `agentic-engineering`、`agentic-os`、`autonomous-agent-harness`、`autonomous-loops`、`continuous-agent-loop`、`continuous-learning`、`continuous-learning-v2`、`cost-aware-llm-pipeline`、`cost-tracking`、`prompt-optimizer`、`team-agent-orchestration`、`team-builder` | 不安装外部自治/成本系统；有用原则已进入审计和上下文预算。 |
| 前端 / Web / UI 框架 | `frontend-patterns`、`frontend-design-direction`、`frontend-a11y`、`react-patterns`、`react-performance`、`react-testing`、`vue-patterns`、`vite-patterns`、`nextjs-turbopack`、`nuxt4-patterns`、`angular-developer`、`ui-demo`、`ui-to-vue`、`browser-qa`、`click-path-audit`、`windows-desktop-e2e` | 当前不是 Web 应用；不吸收。若未来做官网 / Steam 页面可按任务再评估。 |
| 后端 / 数据库 / 云 | `api-design`、`api-connector-builder`、`backend-patterns`、`database-migrations`、`postgres-patterns`、`mysql-patterns`、`redis-patterns`、`prisma-patterns`、`clickhouse-io`、`docker-patterns`、`kubernetes-patterns`、`deployment-patterns`、`uncloud`、`cloud` 相关 MCP | 当前无服务端实现；不安装。 |
| 语言 / 框架专项 | `python-patterns`、`python-testing`、`golang-patterns`、`golang-testing`、`rust-patterns`、`rust-testing`、`cpp-coding-standards`、`cpp-testing`、`java-coding-standards`、`kotlin-patterns`、`kotlin-testing`、`swiftui-patterns`、`swift-concurrency-6-2`、`dart-flutter-patterns`、`dotnet-patterns`、`fsharp-testing`、`perl-patterns`、`laravel-*`、`django-*`、`springboot-*`、`quarkus-*`、`nestjs-patterns` | 与 Godot/GDScript 主线不匹配；不吸收。 |
| 安全专项 | `security-review`、`security-bounty-hunter`、`defi-amm-security`、`llm-trading-agent-security`、`laravel-security`、`django-security`、`springboot-security`、`quarkus-security`、`perl-security`、`hipaa-compliance`、`healthcare-phi-compliance` | 通用安全边界已吸收；行业/框架安全暂不相关。 |
| 游戏 / 图形 / 媒体 | `blender-motion-state-inspection`、`motion-*`、`manim-video`、`remotion-video-creation`、`video-editing`、`videodb`、`fal-ai-media`、`liquid-glass-design`、`make-interfaces-feel-better` | 当前美术/视频制作不是本次任务；未来美术 brief 走项目已有 art/design subagents。 |
| 业务 / 行业 / 运营 | `brand-*`、`marketing-campaign`、`market-research`、`competitive-*`、`finance-billing-ops`、`customer-billing-ops`、`email-ops`、`messages-ops`、`google-workspace-ops`、`logistics-*`、`inventory-*`、`healthcare-*`、`scientific-*`、`visa-doc-translate` 等 | 大多与游戏工程无关；不安装。营销相关已有 `marketing-strategist` 可按需读取外部灵感。 |
| MCP / 外部服务模式 | `mcp-server-patterns`、`exa-search`、`codehealth-mcp`、`jira-integration`、`github-ops`、`browserbase` 相关配置 | 不进项目配置；后续统一走 `mcp-tool-evaluation`。 |

## 8. 后续维护规则

1. 再遇到 ECC 这类大型 AI 工具仓库，先读 README 和许可证，再做目录级 inventory，最后只全文读取候选工具。
2. 新增项目 skill / command / agent 前，先证明已有项目工具不能覆盖；能合并进现有 skill 的，不新增常驻入口。
3. 外部 hooks、MCP、CLI、dashboard、plugin、vendor tree 默认不安装；确需启用时必须有用户明确授权、权限边界、验证命令和回滚方式。
4. 吸收结果必须写回 `docs/AI协作/AI技能资源评估.md`、本清单、AI 记忆和当日会话日志。
