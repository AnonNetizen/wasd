# CI/CD 规划

> 本文档汇总本项目的 CI/CD 路线图与候选项，按「阶段 + 优先级」排列，作为后续逐步落地的清单。
> 配套：`README.md`、`CONTRIBUTING.md`、`.codebuddy/rules/game-coding-rules.md`、`词表与契约.md`、`决策记录.md`。
>
> 当前状态：**未启用任何 workflow**。本文件仅为规划，不影响现有仓库行为；逐项落地时再新建 `.github/workflows/*.yml` 等具体文件，并同步更新本文档。

---

## 0. 项目特点（决定 CI/CD 重点）

| 特点 | 对 CI/CD 的影响 |
|------|----------------|
| **Godot 4.6.3 + GDScript**，代码尚未落地 | 可分阶段开：先文档/数据校验，再代码 |
| **数据驱动**（`res://data/*.json`）+ 强契约（`词表与契约.md`） | CI 重点在「契约不漂移、数据不失效」 |
| **文档密集**（GDD / AI导航 / ADR / 修改建议） | 重点防文档脱节、链接死链、版本号不同步 |
| **AI 协作密集** | CI 输出需 fail-fast 且明确（让 AI 据报错自我纠错） |
| **元规则 19/20**：新规则/决策/设计变更必须同步到对应文档 | CI 可把"同步检查"自动化 |

---

## 1. 阶段 1：现在就能开（无需等代码）

### 1.A 文档与契约校验 ⭐⭐⭐
**workflow（拟建）**：`.github/workflows/docs-check.yml`

- Markdown lint（标题层级、行内格式）
- **内部链接死链检查**：`README.md` / `CONTRIBUTING.md` / `AI导航.md` 等引用的相对路径必须真实存在（中文文件名易写错）
- **`修改建议.md` 编号唯一性**：A~D / J~R 不能撞号
- **`决策记录.md` ADR 编号连续性**：递增、不跳号
- **设计文档版本号同步**：`README.md` 与 `游戏设计文档.md` 的版本号一致

候选实现：`markdownlint-cli2` + 一段 Python/Node 脚本做编号与版本校验。

### 1.B 词表契约校验 ⭐⭐⭐（**项目独有护城河**）
**workflow（拟建）**：`.github/workflows/contract-check.yml`
**脚本（拟建）**：`scripts/validate_contract.py`

- 解析 `词表与契约.md` 表格 → 抽出白名单：`stat` / `effect` / `behavior.event` / 埋点 `event_name` / 设置 `key` / 输入 `action id` / 本地化 key 前缀
- 当 `res://data/*.json` 落地后，扫描其中的 `stat` / `effect` / `event` 等字段
- **未在白名单的 id 一律 CI 失败**，输出「文件名 + 字段路径 + 期望值」（对齐规则 16 的 fail-fast）
- 即使代码尚未落地，脚本可先开发就绪，等数据出现立即起效

> 把规则 15「禁止裸字符串/编造 id」从约定升级为**强制门禁**。

### 1.C 本地化 key 一致性 ⭐⭐
- `res://locale/strings.csv` 与 `res://data/*.json` 中所有 `name_key` / `desc_key` 双向核对：
  - 数据引用的 key 必须在 csv 有定义（缺失即 fail）
  - csv 定义但无人引用 → warning（防野生 key 堆积）
- 触发时机：等 `res://locale/` 与 `res://data/` 落地后启用

### 1.D Commit 规范校验 ⭐⭐
**workflow（拟建）**：`.github/workflows/commitlint.yml`
**配置（拟建）**：`commitlint.config.js`

- 用 [commitlint](https://commitlint.js.org/) 校验所有 commit message
- 强制 `.gitmessage` 中约定的 type：`feat` / `fix` / `docs` / `data` / `locale` / `refactor` / `perf` / `style` / `chore` / `ci` / `test` / `revert`
- 触发：PR 与 push

---

## 2. 阶段 2：代码落地后

### 2.E GDScript Lint + Format ⭐⭐⭐
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
- 优先覆盖：
  - `ModifierEngine`：属性聚合 `(基础+加法)×乘法` 公式
  - `DataLoader`：坏数据能 fail-fast
  - `RNG`：同种子结果一致（参见 `修改建议.md` J 项）
  - `StatusEffect`：DoT/debuff 叠加规则（参见 `修改建议.md` N 项）

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

### 4.L PR 自动加标签 ⭐
- 用 [labeler](https://github.com/actions/labeler)，按改动路径自动打 label：
  - 改 `res://data/` → `data`
  - 改 `.codebuddy/rules/` → `rules-change`
  - 改 `决策记录.md` → `adr`
  - 改 `res://locale/` → `locale`

### 4.M 「文档同步」自动检查 ⭐⭐⭐（**项目独有**）
- 用 [Danger.js](https://danger.systems/) 把规则 19/20 自动化
- PR 改下列文件时强制提示并要求确认：
  - 改 `游戏设计文档.md` → 是否同步 `AI导航.md`
  - 新增决策 → 是否同步 `决策记录.md`
  - 新增 `stat`/`effect`/`event` → 是否在 `词表与契约.md` 登记
  - 改 `.codebuddy/rules/game-coding-rules.md` → 是否同步 `README.md` / `CONTRIBUTING.md`

### 4.N 依赖自动更新 ⭐
- 启用 Dependabot 或 Renovate
- 主要管 `gdtoolkit`、`godot-ci`、`ajv-cli`、`commitlint` 等工具链版本

### 4.O Stale 自动关闭 ⭐
- [actions/stale](https://github.com/actions/stale)
- 长期无活动的 issue / PR 自动关闭

---

## 5. 优先级总表

| 阶段 | 项 | 何时做 | 收益 | 成本 |
|------|---|-------|------|------|
| 1 | A. 文档/链接/版本号 | **现在** | 高 | 低 |
| 1 | B. 词表契约校验 | **现在**（脚本先建） | 极高 | 中 |
| 1 | C. 本地化 key 一致性 | 等数据落地 | 高 | 低 |
| 1 | D. commitlint | **现在** | 中 | 极低 |
| 2 | E. GDScript lint | 代码落地后 | 高 | 低 |
| 2 | F. 数据 schema 校验 | 代码落地后 | 极高 | 中 |
| 2 | G. Godot headless 启动 | 代码落地后 | 高 | 低 |
| 2 | H. GUT 单测 | 核心系统就位后 | 中 | 中 |
| 3 | I. 多平台构建 + Release | 准备发布时 | 高 | 中 |
| 3 | I+. 自动 CHANGELOG | 发布前 | 中 | 低 |
| 3 | J. itch.io 部署 | 想发布到 itch | 中 | 低 |
| 3 | K. Web Demo 到 Pages | 想给人看时 | 中 | 低 |
| 4 | L. PR 自动加标签 | 多人协作时 | 中 | 极低 |
| 4 | M. 文档同步 Danger 检查 | 多人协作时 | 高 | 中 |
| 4 | N. 依赖自动更新 | 工具链稳定后 | 中 | 低 |
| 4 | O. Stale 自动关闭 | issue 多了 | 低 | 极低 |

---

## 6. 推荐落地顺序（建议路径）

1. **第一批（现在）**：1.A + 1.B + 1.D —— 文档/契约/commit 三道门禁
2. **第二批（数据/locale 落地后）**：1.C + 2.F —— 数据完整性校验
3. **第三批（代码落地后）**：2.E + 2.G —— GDScript 质量与启动验证
4. **第四批（核心系统稳定后）**：2.H —— 关键模块单测
5. **第五批（准备发布时）**：3.I + 3.K —— 自动构建 + Web demo
6. **第六批（多人协作或体量大时）**：4.M + 4.L + 4.N

---

## 7. 维护

- 任何 workflow 落地或调整时，**必须同步更新本文档**对应阶段的状态（"拟建" → "已启用 / `.github/workflows/xxx.yml`"）。
- 新增 CI 检查项 = 一次「规则相关变更」，按规则 19/20 同步到：
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
