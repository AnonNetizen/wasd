# wasd —— 俯视角射击 Roguelike

> Godot 4.7.1 stable 项目。玩家在 7×7 连续模块世界中探索、战斗并用局内 Gear Mod 棋盘构筑，清理意识核后完成本局。当前使用项目代号 `WASD`，正式标题待定。
>
> 权威范围：本文件只提供仓库入口、运行方式和核心链接；规则、设计、模块契约与当前任务以各自权威文档为准。

## 快速开始

AI agent 动手前依次读取：

1. [`AGENTS.md`](AGENTS.md)
2. [`docs/AI协作/项目规则.md`](docs/AI协作/项目规则.md)
3. [`docs/AI协作/快速开工.md`](docs/AI协作/快速开工.md) 与 [`docs/AI记忆/current_state.json`](docs/AI记忆/current_state.json)
4. [`docs/AI导航.md`](docs/AI导航.md) 中与任务有关的入口

人类贡献者的新机器配置、提交与验证流程见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 项目定位

- 2D 平面移动、碰撞与射击，`Camera2D` 保持水平和等比缩放。
- WASD / 手柄左摇杆移动，鼠标 / 方向键 / 手柄右摇杆或 D-pad 瞄准射击。
- 技能与 Gear Mod 共用 trigger / condition / action 效果运行时；内容通过组件组合，不写内容 ID 分支。
- 可调数值走 `client/data/`，玩家可见文本走 `client/locale/`，稳定约定字符串走生成契约。
- Meta v4、Run v20、Replay v10、游戏 v1.19。

## 权威文档

| 文档 | 用途 |
|---|---|
| [`docs/AI协作/项目规则.md`](docs/AI协作/项目规则.md) | 跨平台项目规则正文 |
| [`docs/AI导航.md`](docs/AI导航.md) | 权威来源表、目录地图与通用任务路由 |
| [`docs/游戏设计文档.md`](docs/游戏设计文档.md) | 玩法与系统设计 |
| [`docs/词表与契约.md`](docs/词表与契约.md) | ID、action、事件与常量契约 |
| [`docs/决策记录.md`](docs/决策记录.md) | 长期重大决策 |
| [`docs/代码/README.md`](docs/代码/README.md) | 公共模块契约入口 |
| [`client/data/README.md`](client/data/README.md) | 数据 schema 与字段手册 |
| [`client/locale/README.md`](client/locale/README.md) | 本地化键、语言与占位符手册 |
| [`docs/测试策略.md`](docs/测试策略.md) | 分层测试与按变更类型选测规则 |
| [`docs/TODO.md`](docs/TODO.md) | 未完成事项、E/S 待决策和人工验收指针 |
| [`docs/功能建议池.md`](docs/功能建议池.md) | 未承诺的功能与 AI 辅助候选 |

## 仓库结构

```text
wasd/
├── client/            # 正式 Godot 项目、数据、本地化与资产
├── docs/              # 设计、契约、模块、测试与协作权威
├── tools/             # 校验、生成、Bridge 与回归工具
├── output/test_lab/   # 隔离 UI / 素材 / 交互实验
├── AGENTS.md          # 通用 AI 开工入口
├── CODEX.md           # Codex 适配入口
├── CLAUDE.md          # Claude Code 适配入口
└── OPENCODE.md        # OpenCode 适配入口
```

`draft/` / `DRAFT/` 是人工草稿禁区，AI 只有得到当前任务明确授权才能处理。

## 运行与验证

- 用 Godot 4.7.1 stable 打开 `client/project.godot`，或运行 `godot --path client`。
- 最小 headless 启动：`python tools/godot_bridge.py --project client headless-boot`。
- 按变更类型选择 smoke / replay / schema / lint，入口见 [`docs/测试策略.md`](docs/测试策略.md)。
- 文档治理检查：`python tools/test_docs_health_check.py` 与 `python tools/docs_health_check.py`。
- 提交前按相关文件运行 `pre-commit`；CI 负责全量门禁。

## 文档变更成本

- 私有 helper、文件拆分、测试新增、无行为重构：不改文档。
- 公共 API、可观察行为或模块边界变化：只改一个对应模块文档。
- 设计、schema、契约或项目规则变化：只改直接权威来源。

完整契约见 [`docs/AI协作/文档维护指南.md`](docs/AI协作/文档维护指南.md)。

## 许可证

本项目采用 [MIT License](LICENSE)。第三方来源见 [CREDITS.md](CREDITS.md)，游戏内 Credits 数据见 [client/data/credits.json](client/data/credits.json)。
