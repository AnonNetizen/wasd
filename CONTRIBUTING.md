# 贡献指南

> 权威范围：新机器 setup、贡献流程和 Git 约定。项目共同规则见 `docs/AI协作/项目规则.md`。

## 新机器 setup

```bash
git clone <repo-url>
cd wasd
git config --local core.quotepath false
git config --local commit.template .gitmessage
git config --global user.name "<your name>"
git config --global user.email "<your email>"
```

按任务安装 Godot 4.7.1、Python 3.10+ 与可选的 `pre-commit`。纯文档协作不需要 Godot。

## 动手前

1. 读 [`AGENTS.md`](AGENTS.md) 和 [`docs/AI协作/项目规则.md`](docs/AI协作/项目规则.md)。
2. 读 [`docs/AI协作/快速开工.md`](docs/AI协作/快速开工.md) 与 [`docs/AI记忆/current_state.json`](docs/AI记忆/current_state.json)。
3. 用 [`docs/AI导航.md`](docs/AI导航.md) 定位唯一权威；不要预读无关文档。
4. 数据、设计、契约、测试或模块任务只补读对应权威来源。

## 开发流程

- 内容和数值优先改 `client/data/`；玩家可见文本改 `client/locale/strings.csv`。
- 新约定 ID 先改 `docs/词表与契约.md`，再运行契约生成与校验。
- 业务输入通过 `InputService` 和 intent，横向能力通过项目统一 autoload。
- 私有实现与无行为重构不更新文档；公共契约变化只更新一个模块文档。
- 设计、schema、契约、测试政策或项目规则变化只更新直接权威来源。
- 只有长期、跨系统、协议断代、项目级红线或高代价难回滚决策才新增 ADR。

完整文档契约见 [`docs/AI协作/文档维护指南.md`](docs/AI协作/文档维护指南.md)。

## 验证

按 [`docs/测试策略.md`](docs/测试策略.md) 根据变更风险选测。常用静态门禁：

```bash
python tools/sync_contracts.py --check
python tools/validate_data.py
python tools/lint_gdscript_rules.py
python tools/lint_project_rules.py
python tools/lint_semantic_rules.py
python tools/test_docs_health_check.py
python tools/docs_health_check.py
```

Godot 自动验证统一通过 `python tools/godot_bridge.py --project client <command>`。人工检查、L5、真实设备和视觉 / 听觉 / 手感验收必须交给人工。

已安装 `pre-commit` 时，优先对本次文件范围运行 hook；CI 对主分支和 PR 执行全量门禁。

## Git 约定

- 使用 Conventional Commits：`<type>(<scope>): <subject>`。
- 常用 type：`feat`、`fix`、`docs`、`data`、`locale`、`refactor`、`perf`、`style`、`chore`、`ci`、`test`、`revert`。
- `main` 保持可运行；功能开发使用短分支并通过 PR 合入。
- 图片、音频、字体默认作为普通 Git blob；只有独立决策后才对明确路径启用 LFS。
- 不提交用户已有脏改动、人工草稿、本机私有配置或未确认临时文件。
- 大型代码改动提交前执行事实型 review；提交前检查 status、diff、近期 log 与对应验证。

## 提议与反馈

- Bug 和功能请求使用 `.github/ISSUE_TEMPLATE/`。
- 未承诺想法进入 [`docs/功能建议池.md`](docs/功能建议池.md)；用户决定实施后再进入 [`docs/TODO.md`](docs/TODO.md) 或直接权威文档。
