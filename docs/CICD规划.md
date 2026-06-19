# CI/CD 规划

> 本文档汇总本项目的 CI/CD 路线图与候选项，按「阶段 + 优先级」排列，作为后续逐步落地的清单。
> 配套：`README.md`、`CONTRIBUTING.md`、当前平台编码规则入口、`词表与契约.md`、`决策记录.md`。
>
> 当前状态：已启用 Stage 1 基础 workflow：`.github/workflows/docs-check.yml`；本地 `.pre-commit-config.yaml` 已复用同一批 Stage 1 脚本并追加 staged whitespace check。它跑契约生成同步检查、数据 / locale 校验、DataLoader schema 回归测试、第一档 GDScript 项目 lint、第二档项目规则 lint、第三档语义 advisory lint、文档健康检查和 whitespace diff；暂不启用 Godot、GUT、黄金回放、平衡 sim、commitlint 或复杂矩阵。
>
> **测试相关**：本文件只列 CI 工作流的"何时跑、跑什么"。完整测试金字塔、必测清单、里程碑要求、性能预算、手动回归 checklist 见 `docs/测试策略.md`（测试唯一权威）。
>
> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 CI/CD 路线图权威；改 workflow / hook / health-check 设计时，常见联动为 `docs/测试策略.md`、`docs/AI协作/实时验证回路.md`、`CONTRIBUTING.md`、规则自检清单、`docs/AI记忆/项目记忆.md`。

---

## 0. 项目特点（决定 CI/CD 重点）

| 特点 | 对 CI/CD 的影响 |
|------|----------------|
| **Godot 4.6.3 + GDScript**，代码尚未落地 | 可分阶段开：先文档/数据校验，再代码 |
| **数据驱动**（`res://data/*.json`）+ 强契约（`词表与契约.md`） | CI 重点在「契约不漂移、数据不失效」 |
| **文档密集**（GDD / AI导航 / ADR / 修改建议） | 重点防文档脱节、链接死链、版本号不同步 |
| **代码-文档同源**（`docs/代码文档规范.md` + `docs/代码/`） | 代码落地后要检查长期模块是否有对应文档 |
| **AI 协作密集** | CI 输出需 fail-fast 且明确（让 AI 据报错自我纠错） |
| **元规则 19/20/24**：新规则/决策/设计/代码契约变更必须同步到对应文档 | CI 可把"同步检查"自动化 |
| **Roguelike 平衡敏感** | 数值改动需"黄金回放"回归（见 4.M）；中后期跑批量 sim（见 4.N） |

> **本地实时验证回路**：与 CI 配套，在本地通过 pre-commit hook 提供秒级反馈，详见 `docs/AI协作/实时验证回路.md`。本规划阶段 1 的脚本（`sync_contracts.py` / `validate_data.py` / `test_data_loader_schema.py` / `lint_gdscript_rules.py` / `lint_project_rules.py` / `lint_semantic_rules.py` / `docs_health_check.py`）应同时被 hook 与 CI 复用。
> **代码审核流程**：详见 `docs/AI协作/代码审核流程.md`。Reviewer 先看 pre-commit / lint / test / docs 输出，再审当前 diff；第三档 semantic advisory warning 必须人工归类为 fix / accept / defer。

---

## 1. 阶段 1：现在就能开（无需等代码）

### 1.A 文档与数据基础校验 ⭐⭐⭐
**workflow（已启用，基础版）**：`.github/workflows/docs-check.yml`

当前检查：

- 契约生成同步：`python tools/sync_contracts.py --check`，确认 `docs/词表与契约.md`、`client/data/_contracts.json`、`client/scripts/contracts/*.gd` 一致
- 数据 / locale 校验：`python tools/validate_data.py`，覆盖 JSON 语法、`client/data/*.json` / `client/data/*.csv` 与 `strings.csv`
- DataLoader schema 回归：`python tools/test_data_loader_schema.py`，用临时数据副本断言黄金数据通过、未登记 id / 缺 locale / 类型范围错 / 跨文件引用错会 fail-fast
- 第一档 GDScript 项目 lint：`python tools/lint_gdscript_rules.py`，检查可低误报自动化的 style guide 顺序、危险 `:=`、中文硬编码字符串、裸随机 / 时间 / 暂停 API
- 第二档项目规则 lint：`python tools/lint_project_rules.py`，检查新增数据字段是否登记到 `client/data/README.md`、locale 是否保留 `zh_CN` / `en` 双语，以及 release preset 是否误带 debug/dev_tools 资源
- 项目规则 lint 回归：`python tools/test_project_rules_lint.py`，固定新增字段漏文档、locale 缺译文、release preset 带 `dev_tools` 的坏样例
- 第三档语义 advisory lint：`python tools/lint_semantic_rules.py` 默认非阻塞，提示特殊 id 分支、业务脚本绕过 autoload、缺类型签名、长期脚本缺 `# Doc:` 和未知 contract 常量；`python tools/test_semantic_rules_lint.py` 固定坏样例
- AI 知识库健康检查：运行 `python tools/docs_health_check.py`，校验知识库索引、ADR、current_state、链接、AI 修改说明和模块文档索引
- whitespace diff：对本次提交范围运行 `git diff --check`，排除 `draft/` / `DRAFT/`

暂缓项（避免初期 CI 过重）：

- Markdown lint（标题层级、行内格式）
- 独立 Node / markdownlint 工具链
- Godot headless、GUT、黄金回放和平衡 sim

后续可在脚本稳定后把 1.B、1.C、1.D 拆成独立 workflow 或并入本 workflow。

### 1.B 词表契约校验 ⭐⭐⭐（**项目独有护城河**）
**workflow（已并入）**：`.github/workflows/docs-check.yml`
**脚本（已落地）**：`tools/sync_contracts.py` + `tools/validate_data.py`

- 解析 `词表与契约.md` 表格 → 抽出白名单：`stat` / `effect` / `behavior.event` / 埋点 `event_name` / 设置 `key` / 输入 `action id` / 本地化 key 前缀等
- 生成并校验 `client/data/_contracts.json` 与 `client/scripts/contracts/*.gd`
- 扫描已落地的 `client/data/*.json` / `client/data/*.csv`，检查 `stat`、meta id、locale key 等引用
- 新增 / 修改数据字段时，检查 `client/data/README.md` 是否包含字段说明（字段含义、单位、范围）
- **未在白名单的 id 一律 CI 失败**，输出「文件名 + 字段路径 + 期望值」（对齐规则 16 的 fail-fast）
- 即使代码尚未落地，脚本可先开发就绪，等数据出现立即起效

> 把规则 15「禁止裸字符串/编造 id」从约定升级为**强制门禁**。

### 1.C 本地化 key 一致性 ⭐⭐
- `res://locale/strings.csv` 与 `res://data/*.json` 中所有 `name_key` / `desc_key` 双向核对：
  - 数据引用的 key 必须在 csv 有定义（缺失即 fail）
  - csv 定义但无人引用 → warning（防野生 key 堆积）
- 校验必填语言列 `zh_CN` / `en` 都非空，且同一 key 各语言占位符集合一致
- 新增语言列或占位符约定时，检查 `client/locale/README.md` 是否同步说明
- 触发时机：等 `res://locale/` 与 `res://data/` 落地后启用

### 1.D Commit 规范校验 ⭐⭐
**workflow（拟建）**：`.github/workflows/commitlint.yml`
**配置（拟建）**：`commitlint.config.js`

- 用 [commitlint](https://commitlint.js.org/) 校验所有 commit message
- 强制 `.gitmessage` 中约定的 type：`feat` / `fix` / `docs` / `data` / `locale` / `refactor` / `perf` / `style` / `chore` / `ci` / `test` / `revert`
- 触发：PR 与 push

### 1.E 本地 pre-commit hook ⭐⭐⭐
**配置（已落地）**：`.pre-commit-config.yaml`

- 本地安装 `pre-commit` 后，commit 前跑 Stage 1 本地门禁：contract sync、data validate、DataLoader schema 回归、三档 lint、lint 回归、docs health、staged whitespace。
- 第三档 `lint_semantic_rules.py` 仍默认非阻塞；其 regression test 是硬门禁。
- 没装 pre-commit 时，按 `docs/AI协作/实时验证回路.md` 的等价命令手动运行。

---

## 2. 阶段 2：代码落地后

### 2.E GDScript Lint + Format ⭐⭐⭐
- 当前 Stage 1 已先启用 `tools/lint_gdscript_rules.py` 作为低误报项目红线 lint，并启用 `tools/lint_project_rules.py` 覆盖数据 / locale / release 边界，另以非阻塞 `tools/lint_semantic_rules.py` 提示较高误报风险的语义问题；本阶段继续补齐更完整的第三方格式化与静态分析。
- 使用 [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit)：
  - `gdlint`：静态检查（命名、未使用变量、复杂度）
  - `gdformat --check`：格式化检查
- 自定义规则：配合规则 17「类型化 GDScript」，禁止 untyped 函数签名进 main

### 2.F 数据 Schema 校验 ⭐⭐⭐（**规则 16 的自动化**）
- 为每个数据文件写 JSON Schema：
  ```
  schemas/
    player.schema.json
    enemies.schema.json
    relics.schema.json
    active_items.schema.json
    consumables.schema.json
    hazards.schema.json
    spawn_waves.schema.json
  ```
- CI 用 `ajv-cli` 跑校验：字段缺失 / 类型错 / 取值越界 → 失败，输出精确路径（如 `relics.json[3].modifiers[0].stat`）
- 与 1.B 的词表校验配合，形成「**结构对、id 也对**」双重保险

### 2.G Godot Headless 启动验证 ⭐⭐⭐
- 用官方 [`barichello/godot-ci`](https://github.com/abarichello/godot-ci) Docker 镜像
- 跑：`godot --headless --quit`
- 只要项目能成功启动并退出，就排除致命错误（脚本编译错、缺 autoload、场景引用断链）
- 对 AI agent 价值极大——改完 push 上来 CI 能立即判定有没有崩

### 2.H GUT 单元测试 ⭐⭐
- [GUT](https://github.com/bitwes/Gut) 是 Godot 标配单测框架
- F8 首片在 GUT 插件接入前，先用 `python tools/godot_bridge.py --project client l1-smoke` 作为临时 headless L1 runner，覆盖 `RNG`、`GameClock`、`GameState`、`SaveManager` 和 `Combat` 的最小基础设施行为；后续再迁入正式 GUT。
- 优先覆盖：
  - `ModifierEngine`：属性聚合 `(基础+加法)×乘法` 公式
  - `DataLoader`：坏数据能 fail-fast
  - `RNG`：同种子结果一致（参见 `修改建议.md` J 项）
  - `StatusEffect`：DoT/debuff 叠加规则（参见 `修改建议.md` N 项）

### 2.H+ 代码-文档对应检查 ⭐⭐
- 扫描长期维护脚本文件头的 `# Doc:` 引用，确认目标 `docs/代码/<module_id>.md` 存在。
- 检查 `docs/代码/README.md` 中登记的模块文档路径与实际文件一致。
- 对自动生成文件、测试、一次性调试脚本和被上级模块覆盖的私有 helper 允许豁免，但豁免规则必须写进检查脚本。
- 与 `docs/代码文档规范.md` 配套，防止代码模块落地后没有维护入口。

---

## 3. 阶段 3：构建与发布

### 3.I 多平台自动构建 ⭐⭐
**workflow（拟建）**：`.github/workflows/release.yml`

- 触发：打 git tag（如 `v0.1.0`）
- 用 `barichello/godot-ci` 镜像并行 export 4 端：Windows / Linux / macOS / Web
- 产物上传到 GitHub Release

### 3.I+ 自动 CHANGELOG ⭐⭐
- 用 [release-please](https://github.com/googleapis/release-please) 或 [semantic-release](https://semantic-release.gitbook.io/)
- 根据已有的 conventional commits 自动生成 CHANGELOG
- 这是你 `.gitmessage` 规范带来的额外红利

### 3.J 自动部署到 itch.io ⭐
- 用 [butler](https://itch.io/docs/butler/) CLI，一条命令推送
- 集成进 `release.yml`，发布即上架

### 3.K Web Demo 自动部署到 GitHub Pages ⭐⭐
- Godot 4 支持 web export
- main 合并后自动 export web 并 push 到 `gh-pages` 分支
- 给玩家/朋友看进度的最低成本方案

---

## 4. 阶段 4：高级（视项目体量）

### 4.L 项目健康度 Dashboard ⭐⭐⭐（**度量规则违反率**）
**workflow（拟建）**：`.github/workflows/health-dashboard.yml`
**脚本（拟建）**：`tools/health_metrics.py`

把规则的"该不该"升级为"现在多健康"。在 README 顶部展示 badge：

| 指标 | 计算 | 目标 |
|------|------|------|
| 裸字符串率 | 代码中未走 `tr()` 的字符串字面量数 / 总字符串数 | → 0% |
| 数据驱动覆盖率 | 数据条目数 / (数据条目数 + 硬编码分支数) | → 100% |
| 词表登记率 | 数据中已登记 id 数 / 总 id 数 | = 100% |
| 类型化 GDScript 比例 | 已类型化函数签名 / 总函数签名 | → 100% |
| 文档同步度 | 互引文档间的死链 / 总链接 | = 0 |
| 代码文档覆盖率 | 有 `# Doc:` 或模块覆盖的长期脚本数 / 长期脚本总数 | → 100% |
| 黄金回放回归通过率 | 通过的黄金回放数 / 总数 | = 100% |

定期跑 → 输出 `health-report.md` 到 `gh-pages` 分支或写入 README badge。

### 4.M 回放回归测试（CI 跑黄金样例）⭐⭐
**workflow（拟建）**：`.github/workflows/replay-regression.yml`

- 用 `barichello/godot-ci` headless 模式跑 `tools/replay_runner.gd <golden_files>`
- 任意黄金回放产生 diff → 失败，输出首个 diff 帧 + 字段
- 数值/原语改动后**强制更新或确认**黄金样例
- 与 GDD 9.9 的"黄金回放"配套
- F8 已启用显式本地命令 `python tools/godot_bridge.py --project client replay-smoke`，验证 `.replay` 文件 envelope / hash / data fingerprint / 摘要 roundtrip；并启用 `python tools/godot_bridge.py --project client replay-runner`，先对照 `.replay` 内嵌 summary 或外部 expectation JSON。首条已入库 golden 为 `client/tests/replays/golden_basic_run.replay`，可用 `python tools/godot_bridge.py --project client replay-runner --replay-file client/tests/replays/golden_basic_run.replay --rerun-runtime-summary` 重跑真实 `GameplayRunLoop` 运行时摘要和稳定帧样本。`python tools/godot_bridge.py --project client replay-input-smoke` 已覆盖 gameplay 输入录制首片；`python tools/godot_bridge.py --project client replay-runner --rerun-runtime-summary` 已覆盖 runner 输入播放与稳定帧样本 diff 首片；更多黄金回放 CI 仍待后续接入。

### 4.N 平衡 Sim 报表（按需）⭐
**workflow（拟建）**：`.github/workflows/balance-sim.yml`（手动触发）

- headless 跑 `tools/sim.gd --runs 1000`
- 输出 build 强度 / 胜率分布 / 无人选择遗物清单
- 与 GDD 9.10 配套；MVP 后再启用
- F8 首片先启用 `python tools/godot_bridge.py --project client perf-probe` 输出轻量 JSON 指标，作为后续 sim 报表的最小可比较基线。

### 4.O PR 自动加标签 ⭐
- 用 [labeler](https://github.com/actions/labeler)，按改动路径自动打 label：
  - 改 `res://data/` → `data`
  - 改 `.codebuddy/rules/` 或 `.codex/rules/` 或 `.opencode/rules/` → `rules-change`
  - 改 `AGENTS.md` / `CODEX.md` / `OPENCODE.md` / `.codebuddy/agents/` / `.codex/agents/` / `.opencode/agents/` / `.codebuddy/commands/` / `.codex/commands/` / `.opencode/commands/` / `.opencode/opencode.json` → `ai-tooling`
  - 改 `决策记录.md` → `adr`
  - 改 `res://locale/` → `locale`

### 4.P 「文档同步」自动检查 ⭐⭐⭐（**项目独有**）
- 用 [Danger.js](https://danger.systems/) 把规则 19/20/24 自动化
- PR 改下列文件时强制提示并要求确认：
  - 改 `游戏设计文档.md` → 是否同步 `AI导航.md`
  - 新增决策 → 是否同步 `决策记录.md`
  - 新增 `stat`/`effect`/`event` → 是否在 `词表与契约.md` 登记
  - 改 `client/scripts/` 长期模块 / 公共 API / 数据 schema → 是否按 `docs/代码文档规范.md` 更新 `docs/代码/` 模块文档
  - 改 `.codebuddy/rules/game-coding-rules.md` 或 `.codex/rules/game-coding-rules.md` 或 `.opencode/rules/game-coding-rules.md` → 是否同步 `README.md` / `CONTRIBUTING.md` / `docs/AI协作/工具适配指南.md`
  - 改 `AGENTS.md` / `CODEX.md` / `OPENCODE.md` / `.codebuddy/` / `.codex/` / `.opencode/` 平台配置 → 是否仍满足规则 21（核心规则语义一致；平台专属优化已登记）

### 4.N 依赖自动更新 ⭐
- 启用 Dependabot 或 Renovate
- 主要管 `gdtoolkit`、`godot-ci`、`ajv-cli`、`commitlint` 等工具链版本

### 4.R Stale 自动关闭 ⭐
- [actions/stale](https://github.com/actions/stale)
- 长期无活动的 issue / PR 自动关闭

---

## 5. 优先级总表

| 阶段 | 项 | 何时做 | 收益 | 成本 |
|------|---|-------|------|------|
| 1 | A. 文档 / 数据 / locale / 知识库健康检查 | **已启用基础版** | 高 | 低 |
| 1 | B. 词表契约校验 | **已并入 docs-check** | 极高 | 中 |
| 1 | C. 本地化 key 一致性 | **已覆盖基础版** | 高 | 低 |
| 1 | D. commitlint | **后续** | 中 | 极低 |
| 1 | E. 本地 pre-commit hook | **已配置** | 高 | 低 |
| 2 | E. GDScript lint | 第一档与第三档 advisory 已并入 docs-check；完整 gdtoolkit 待代码规模扩大后 | 高 | 低 |
| 2 | F. 数据 schema 校验 | 代码落地后 | 极高 | 中 |
| 2 | G. Godot headless 启动 | 代码落地后 | 高 | 低 |
| 2 | H. GUT 单测 | 核心系统就位后 | 中 | 中 |
| 2 | H+. 代码-文档对应检查 | 代码落地后 | 中 | 低 |
| 3 | I. 多平台构建 + Release | 准备发布时 | 高 | 中 |
| 3 | I+. 自动 CHANGELOG | 发布前 | 中 | 低 |
| 3 | J. itch.io 部署 | 想发布到 itch | 中 | 低 |
| 3 | K. Web Demo 到 Pages | 想给人看时 | 中 | 低 |
| 4 | L. 项目健康度 Dashboard | 工具链稳定后 | 高 | 中 |
| 4 | M. 回放回归测试 | 回放系统落地后 | 极高 | 中 |
| 4 | N. 平衡 Sim 报表 | 中后期 | 高 | 中 |
| 4 | O. PR 自动加标签 | 多人协作时 | 中 | 极低 |
| 4 | P. 文档同步 Danger 检查 | 多人协作时 | 高 | 中 |
| 4 | Q. 依赖自动更新 | 工具链稳定后 | 中 | 低 |
| 4 | R. Stale 自动关闭 | issue 多了 | 低 | 极低 |

---

## 6. 推荐落地顺序（建议路径）

1. **第一批（已启用基础版）**：1.A + 1.B + 1.C —— 契约同步、数据 / locale、DataLoader schema、第一档 GDScript lint、第二档项目规则 lint、第三档语义 advisory、文档健康与 whitespace 守门
2. **第二批（下一步）**：1.D + 增量 watch —— commitlint 与保存即检体验；本地 pre-commit 已先落地
3. **第三批（数据/locale 扩大后）**：2.F —— 更细 JSON Schema 与内容数据完整性校验
4. **第四批（代码落地后）**：2.E + 2.G + 2.H+ —— GDScript 质量、启动验证与代码文档覆盖
5. **第五批（核心系统稳定后）**：2.H —— 关键模块单测
6. **第六批（准备发布时）**：3.I + 3.K —— 自动构建 + Web demo
7. **第七批（回放系统落地后）**：4.L 健康度 + 4.M 回放回归
8. **第八批（多人协作或体量大时）**：4.P 文档同步 + 4.O 标签 + 4.Q 依赖 + 4.N 平衡 sim

---

## 7. 维护

- 任何 workflow 落地或调整时，**必须同步更新本文档**对应阶段的状态（"拟建" → "已启用 / `.github/workflows/xxx.yml`"）。
- 新增 CI 检查项 = 一次「规则相关变更」，按规则 19/20/24 同步到：
  - `决策记录.md`（记录决策与理由）
  - `CONTRIBUTING.md`（若涉及贡献流程）
  - 本文件（更新状态）

---

## 附：候选第三方 Action / 工具速查

| 用途 | 工具 |
|------|------|
| Markdown lint | `DavidAnson/markdownlint-cli2-action` |
| JSON Schema 校验 | `ajv-cli` |
| Commit lint | `wagoid/commitlint-github-action` |
| GDScript lint/format | `Scony/godot-gdscript-toolkit` |
| Godot CI（含 export） | `barichello/godot-ci` |
| Godot 单测 | `bitwes/Gut` |
| 自动 CHANGELOG | `googleapis/release-please-action` |
| itch.io 上传 | `KikimoraGames/itch-publish` 或 butler 直调 |
| PR 标签 | `actions/labeler` |
| 文档同步检查 | `danger/danger-js` |
| 依赖更新 | Dependabot（GitHub 原生） |
| Stale | `actions/stale` |
