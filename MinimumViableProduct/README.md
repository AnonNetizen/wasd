# MinimumViableProduct

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与根目录 `AGENTS.md`。
> 本目录是最小可行产品（MVP）隔离实验区；改 MVP 目标、目录结构或与完整项目的边界时，必须同步 `MinimumViableProduct/docs/`、根目录 `docs/AI导航.md`、`docs/决策记录.md`、`docs/AI记忆/项目记忆.md`。

---

## 目的

`MinimumViableProduct/` 用来快速验证工作流、操作想法和最小玩法闭环。这里的文档与客户端代码独立于完整项目的 `client/`，避免 MVP 的临时实现污染正式架构。

## MVP 核心约束

- 玩家固定在场景中心，**不能移动**。
- 玩家只能用方向键或手柄 D-pad / 摇杆改变射击方向，射击方向限定上 / 下 / 左 / 右四方向。
- 开火自动进行，不需要单独开火键。
- 敌人只从上 / 下 / 左 / 右四个方向刷新，并向玩家位置推进。
- MVP 的目标是验证“能否快速做出可玩闭环 + 记录经验”，不是复刻完整 GDD。

## 目录结构

| 路径 | 用途 |
|------|------|
| `MinimumViableProduct/docs/` | MVP 文档、计划、经验记录 |
| `MinimumViableProduct/client/` | MVP 独立 Godot 客户端代码，后续可单独放 `project.godot` |
| `MinimumViableProduct/docs/MVP设计说明.md` | MVP 玩法范围与系统边界 |
| `MinimumViableProduct/docs/开发计划.md` | 前期准备到可玩闭环的阶段计划 |
| `MinimumViableProduct/docs/MVP决策记录.md` | 只影响 MVP 的局部决策 |
| `MinimumViableProduct/docs/经验记录.md` | 制作过程中的经验、坑点、可迁移结论 |
| `MinimumViableProduct/docs/代码/` | MVP 客户端代码模块文档 |

## 与完整项目的边界

- MVP 可以采用更小的系统集合，但不得改写根目录 GDD 对完整项目的长期目标。
- MVP 中验证成功的经验，先写入 `docs/经验记录.md`；只有决定迁移到完整项目时，才更新根目录 GDD / ADR / 词表 / 测试策略。
- MVP 客户端代码只放在 `MinimumViableProduct/client/`，不要放入根目录 `client/`。
- MVP 仍应遵守根项目红线：不读取 `draft/`、默认中文沟通、重要经验留文档。
