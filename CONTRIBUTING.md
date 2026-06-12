# 贡献指南

> 欢迎参与 **wasd**！本项目以「数据驱动 + AI 友好工程」为核心，所有贡献者（包括 AI agent）都需遵守本指南。

---

## 一、动手前必读

按优先级顺序阅读：

1. [`.codebuddy/rules/game-coding-rules.md`](.codebuddy/rules/game-coding-rules.md) —— **强制编码规则**
2. [`docs/AI导航.md`](docs/AI导航.md) —— 项目地图与扩展点速查
3. [`docs/词表与契约.md`](docs/词表与契约.md) —— 约定字符串白名单
4. [`docs/游戏设计文档.md`](docs/游戏设计文档.md) —— 完整设计
5. [`docs/决策记录.md`](docs/决策记录.md) —— 既定决策
6. [`docs/修改建议.md`](docs/修改建议.md) —— 待决策项
7. [`docs/AI记忆/项目记忆.md`](docs/AI记忆/项目记忆.md) —— 跨会话/跨机器的 AI 协作记忆

> AI agent 工作前请按 `docs/AI导航.md` 定位，避免盲目全仓搜索；在新环境续接对话前，先读 `docs/AI记忆/项目记忆.md`。

---

## 二、开发流程

### 1. 选定任务类型，按对应扩展点修改
参见 `docs/AI导航.md` 第 4 节「扩展点速查」。常见入口（数据/资源路径基于 `client/`，对应 Godot `res://`）：

| 任务 | 入口 |
|------|------|
| 加敌人 / 遗物 / 道具 | 改 `client/data/*.json`（即 `res://data/`），**不改逻辑** |
| 改数值 | 只改 `client/data/`，**绝不改代码常量** |
| 加面向玩家文本 | 加 `client/locale/strings.csv` 的 key + 译文 |
| 加设置项 | `Settings` 加配置 + UI 控件 |
| 加埋点 | 调用 `Analytics.track_event(name, params)` |
| 加效果原语 | **先在 `docs/词表与契约.md` 登记**，再实现，最后在数据中使用 |

### 2. 三大红线（最易踩坑，必查）
- ❌ 硬编码可调数值、玩家可见文本、按键、约定字符串
- ❌ 为每个遗物/道具写独立分支
- ✅ 高频实体用对象池；相机不开 limit / drag margin

完整自检清单见 `.codebuddy/rules/game-coding-rules.md` 末尾。

### 3. 文档同步（元规则 19/20）
**新规则 / 决策 / 设计变更必须同步到对应文档**：
- 新规则 → `.codebuddy/rules/game-coding-rules.md`
- 新决策 → `docs/决策记录.md`
- 设计变更 → `docs/游戏设计文档.md` + `docs/AI导航.md` + `docs/词表与契约.md`
- 重要对话/决策结束后 → `docs/AI记忆/项目记忆.md`（跨机器续接对话用）

文档不同步等同于未完成。

---

## 三、Git 约定

### 1. Commit 信息风格（Conventional Commits）

```
<type>(<scope>): <subject>
```

**type**：`feat` / `fix` / `docs` / `data` / `locale` / `refactor` / `perf` / `style` / `chore` / `ci` / `test` / `revert`

启用项目 commit 模板（一次即可）：
```bash
git config --local commit.template .gitmessage
```

示例：
```
feat(weapon): 添加 split 效果原语
data(relics): 新增锋利弹头与急速射击
docs(adr): 记录暂停功能实现约定
```

### 2. 分支策略
- `main`：可运行的稳定分支
- 功能开发用 `feat/xxx` / `fix/xxx` / `docs/xxx` 分支，PR 合入 `main`

### 3. 行尾符 / 编码
仓库已通过 `.gitattributes` 与 `.editorconfig` 锁定行尾符（统一 LF）与编码（UTF-8），**无需在本地另行配置 `core.autocrlf`**。

### 4. 中文文件名显示
仓库级已开启 `core.quotepath=false`。如 clone 后仍显示转义码，可手动执行：
```bash
git config --local core.quotepath false
```

---

## 四、PR Checklist（提交前自检）

- [ ] 没有硬编码可调数值（都在 `res://data/`）？
- [ ] 没有硬编码玩家可见文本（都用 `tr()` 文本键）？
- [ ] 玩家偏好都走 `Settings` 单例？
- [ ] 新遗物/道具是加数据而非加逻辑分支？
- [ ] 高频实体用了对象池？
- [ ] 约定字符串都来自 `docs/词表与契约.md` 且以常量引用？
- [ ] 新代码使用类型化 GDScript？
- [ ] 已更新 `docs/AI导航.md` / `docs/决策记录.md` 等相关文档？
- [ ] 本次新规则 / 设计变更已同步到对应文档？

---

## 五、报告问题 / 提议

- **bug / 功能请求**：使用 GitHub Issue（`.github/ISSUE_TEMPLATE/` 内有模板）。
- **设计建议**：先在 `docs/修改建议.md` 起草（按现有 A~D / J~R 风格编号），由维护者评审后转为决策（写入 `docs/决策记录.md`）或采纳实施。

---

感谢贡献 🎮
