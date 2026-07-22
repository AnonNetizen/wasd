# F4 MinPlayableLoop 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F4 最小可玩闭环的低 token 工作包；改 F4 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/AI记忆/current_state.json`。

---

## 目标

在正式 `client/` 项目内做出最小 1 分钟可玩战斗闭环：

- 玩家实体、输入读取和相机居中。
- 默认角色起始携带的武器运行时发放。
- 基础 WeaponSystem、子弹实体、对象池接入。
- 基础 Enemy、Spawner 和 `spawn_waves.csv` 时间窗读取。
- `Combat.apply_damage` 单入口伤害结算。
- 失败 / 重开最小流程与基础 HUD 计数。

F4 只做最小竖切，不做升级选择、局外成长、暂停保存续局、复杂 UI、完整音画表现、回放稳定性或平衡 sim。

## 必读

1. `docs/AI协作/快速开工.md`
2. `docs/AI记忆/current_state.json`
3. 当前平台编码规则入口
4. `docs/正式项目工作规划.md` F4 段
5. `docs/测试策略.md` §7 与 L0 / L2 要求
6. `docs/代码文档规范.md`
7. 相关已存在模块文档：`docs/代码/data_loader.md`、`docs/代码/pool_manager.md`、`docs/代码/game_state.md`、`docs/代码/game_clock.md`
8. 目标数据手册：`client/data/README.md`

只在实现对应运行时模块时，按需补读 GDD 的玩家 / 输入 / 武器 / 敌人 / 刷怪 / 对象池 / 伤害章节和相关词表节；不要默认整篇加载。

## 建议拆分

1. 玩家移动 + 相机居中：Player 场景 / 脚本读取 `InputService` 的 `move` / `aim` 归一化 intent，移动数值来自 `characters.json` / `player.json`。
2. WeaponSystem + 子弹：读取 `characters[].starting_loadout.weapon_id` 与 `weapons.json`，高频子弹走 `PoolManager.acquire/release`。
3. Combat + Enemy：建立最小敌人实体，伤害必须走 `Combat.apply_damage`；如 `Combat` 尚未落地，先做可复用模块而不是直接扣血。
4. Spawner：读取 `spawn_waves.csv`，时间走 `GameClock`，随机走 `RNG.spawn`。
5. 最小 HUD / 失败重开：只显示必须状态，不提前做完整菜单与升级流程。

## 可改文件

- `client/scenes/` 与 `client/scripts/` 中 F4 所需新场景 / 脚本
- `client/project.godot`（只注册必要输入 action、autoload 或主场景变更）
- `client/data/*.json` / `client/data/*.csv`（只补运行时必须字段，改字段同步手册和 schema）
- `client/locale/strings.csv`（只补玩家可见文本）
- `docs/代码/*.md`
- `docs/AI导航.md`、`docs/AI记忆/current_state.json`、当日会话日志（收尾同步）

## 禁止事项

- 不绕过 `DataLoader` 读取数据，不硬编码武器 / 敌人 / 角色 id 特判。
- 高频子弹 / 敌人不得长期 `instantiate` / `queue_free`，第一版就接 `PoolManager`。
- 随机必须走 `RNG.<stream>`，时间必须走 `GameClock`，暂停 / 流程必须走 `GameState`。
- 伤害不得 `target.hp -= n`，必须走 `Combat.apply_damage`。
- 不提前实现 F5+ 的暂停保存续局、完整主菜单、局外成长、升级选择、黄金回放或平衡 sim。
- 不复活历史 MVP 临时代码；只能按正式项目规则重新落地可迁移经验。

## 验收命令

- `python tools/sync_contracts.py --check`
- `python tools/validate_data.py`
- `python tools/test_data_loader_schema.py`
- `python tools/lint_gdscript_rules.py`
- `python tools/lint_project_rules.py`
- `python tools/lint_semantic_rules.py`
- `python tools/godot_bridge.py --project client headless-boot`
- `python -m json.tool docs/AI记忆/current_state.json`
- `python -m json.tool docs/_kb_index.json`
- `python tools/docs_health_check.py`
- `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`

## 完成定义

- 正式 `client/` 能启动到一局最小战斗。
- 玩家可移动，相机保持玩家居中。
- 默认武器能按数据射出子弹，子弹使用对象池。
- 敌人按数据生成并能通过 `Combat` 受伤 / 死亡。
- 失败后能重开或回到最小入口。
- headless boot 与 L0 门禁通过；手动可跑通 1 分钟基础战斗。
