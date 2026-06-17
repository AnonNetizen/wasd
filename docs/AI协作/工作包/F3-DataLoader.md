# F3 DataLoader 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F3 数据 / 契约闭环的低 token 工作包；改 F3 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/AI记忆/current_state.json`。

---

## 目标

把 `DataLoader` 从通用 JSON / CSV 加载器推进为正式数据 schema 校验入口，优先覆盖：

- `client/data/player.json`
- `client/data/characters.json`
- `client/data/weapons.json`
- `client/data/enemies.csv`
- `client/data/hazards.csv`
- `client/data/spawn_waves.csv`
- `client/data/relics.json`
- `client/data/active_items.json`
- `client/data/consumables.json`
- `client/data/credits.json`
- `client/data/meta_progression.json`
- `client/locale/strings.csv`
- `client/data/growth.csv`
- `client/data/growth_pools.json`
- `client/data/game_modes.json` 的资源池 / 权重 / 轻量覆盖 / participant / team 预留边界

已覆盖的后续内容边界可以保留在本工作包验收范围内；继续扩展其他内容数据时仍遵守“不实现玩法运行时，只落数据 / schema / 诊断”的约束。

## 必读

1. `docs/AI协作/快速开工.md`
2. `docs/AI记忆/current_state.json`
3. 当前平台编码规则入口
4. `docs/代码/data_loader.md`
5. `client/data/README.md`
6. `client/locale/README.md`
7. `docs/词表与契约.md` 中与本次目标文件相关的节
8. 目标源码：`client/scripts/autoload/data_loader.gd`

只在 schema 与既定设计冲突、需要新增决策或需要解释玩法语义时，补读 `docs/游戏设计文档.md`、`docs/决策记录.md` 或 `docs/正式项目工作规划.md` 的相关段落。

## 可改文件

- `client/scripts/autoload/data_loader.gd`
- `client/scripts/boot/formal_client_boot.gd`（只做 smoke 输出 / 启动验证）
- `client/data/*.json` / `client/data/*.csv`
- `client/locale/strings.csv`
- `CREDITS.md`
- `tools/validate_data.py`、`tools/sync_contracts.py`
- `tools/test_data_loader_schema.py`
- `client/data/README.md`
- `client/locale/README.md`
- `docs/代码/data_loader.md`
- `docs/词表与契约.md`
- `docs/AI导航.md`、`docs/AI记忆/current_state.json`、当日会话日志（收尾同步）

## 禁止事项

- 不默认读取整份 GDD；优先以模块文档、数据手册、词表和目标源码为工作上下文。
- 不实现玩法系统、成长 UI、局外成长逻辑或游戏模式运行时，只做数据读取 / schema / 诊断边界。
- 不新增未登记的约定字符串；新增 id 先改 `docs/词表与契约.md` 并跑契约同步。
- 不把 schema 校验散落到业务系统；正式数据入口仍以 `DataLoader` / 数据校验工具为主。

## 验收命令

- `python tools/sync_contracts.py --check`
- `python tools/validate_data.py`
- `python tools/test_data_loader_schema.py`
- `python tools/godot_bridge.py --project client headless-boot`
- `python -m json.tool docs/AI记忆/current_state.json`
- `python -m json.tool docs/_kb_index.json`
- `python tools/docs_health_check.py`
- `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`

## 完成定义

- `DataLoader` 能对本阶段目标数据给出 fail-fast、可读的 schema 诊断。
- headless boot smoke 能证明目标数据 / locale / contract cache 的关键数量或状态。
- 数据手册、locale 手册和 `docs/代码/data_loader.md` 与实现同步。
- `current_state.json.next_actions` 指向 F3 的下一小步，而不是重新要求读完整规划。
