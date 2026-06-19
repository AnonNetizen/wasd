# SaveManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `SaveManager` autoload 的代码契约权威；改存档 envelope、公共 API、迁移、原子写入、损坏隔离、save kind 或测试义务时必须同步本文档。

## 职责

- `SaveManager` 负责完整项目的游戏内进度存档，统一管理 `meta`、`run` 与 `replay_index` 三类 save kind。
- 所有存档写入必须包含标准头字段：`version`、`kind`、`slot`、`created_at`、`updated_at`、`game_version`、`data_hash` 和 `payload`。
- 写入必须先落 `*.tmp`，替换前保留 `*.bak`；加载失败时尝试 `.bak`，仍失败则隔离到 `user://saves/.broken/` 并广播 / 埋点。
- 当前 F5 首片已由 gameplay runtime 接入真实 `run` 快照：暂停菜单“保存并退出”调用 `SaveManager.save(slot_0, run, payload)`，标题菜单“继续游戏”调用 `load()` 后交给运行时重建节点和 `ui_restore` 恢复点；`SaveManager` 仍只负责可靠读写，不解释玩家、敌人、子弹或 UI 字段。
- F5 存档可靠性切片已把 `run` kind 提升到 version 2，并注册 `run` v1 -> v2 迁移；`save-smoke` 覆盖 run roundtrip、`.bak` 回退、双坏档隔离和迁移链。
- F6 首片已由 `MetaProgressionSystem` 接入真实 `meta` profile：死亡结算写局外货币、账号经验、升级和解锁，购买永久升级后保存，并由下一局读取 modifiers；`SaveManager` 仍不解释 profile 字段。
- 玩家偏好不归 `SaveManager` 管，仍由 `Settings` 写入 `user://settings.cfg`。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 写局外成长状态 | 本文档 `meta` kind 与 GDD §7.2 / §9.16 |
| 做暂停保存退出 | 本文档 `run` kind、`save()` / `load()` 与 `GameState` / `UIManager` |
| 改存档 schema | 本文档迁移 / 兼容与 `register_migration()` |
| 排查坏档 | 本文档故障排查、`.bak` 和 `.broken` 规则 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/save_manager.gd` | `SaveManager` autoload 脚本 |
| `client/scripts/autoload/meta_progression_system.gd` | `meta` profile 的业务解释者和 SaveManager 调用方 |
| `client/tools/save_manager_smoke.gd` | F5 存档可靠性 headless smoke：run roundtrip、备份回退、坏档隔离、迁移 |
| `client/tools/meta_progression_smoke.gd` | F6 meta profile headless smoke：结算、购买、roundtrip、modifier |
| `tools/godot_bridge.py` | `save-smoke` 命令入口 |
| `client/scripts/contracts/save_kinds.gd` | 自动生成的 save kind 常量 |
| `client/scripts/contracts/analytics_events.gd` | 自动生成的存档相关埋点事件常量 |
| `client/project.godot` | autoload 注册 |

## 场景 / 节点结构

`SaveManager` 是 autoload singleton，没有 `.tscn` 场景。存档文件写入 Godot `user://`：

```text
user://saves/
├── slot_0/
│   ├── meta.save
│   ├── meta.save.bak
│   └── run.save
└── .broken/
    └── slot_0_meta_<timestamp>.save
```

`slot` 表示玩家档案，`kind` 表示该档案下的存档种类。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动 | 不主动读写任何存档，只暴露 API 和 kind / slot 查询 | `registered_save_kinds()` / `list_slots()` |
| 写入 | 校验 slot / kind，创建标准 envelope，写 `*.tmp`，备份旧文件到 `.bak`，再原子替换 | `save()` / `save_written` |
| 读取 | 读取正式文件，校验 envelope 与 `data_hash`，必要时跑迁移；失败则尝试 `.bak` | `load()` / `load_envelope()` / `save_loaded` |
| 迁移 | 按版本逐级调用已注册迁移函数，更新 payload、version 与 hash | `register_migration()` / `save_migrated` |
| 损坏 | 正式文件和备份都失败时，用唯一文件名隔离坏文件到 `.broken` 并发事件 | `save_corrupted` |
| 删除 | 删除正式、备份、临时文件；若 slot 目录空则清理空目录 | `delete()` / `save_deleted` |
| F5 续局 | Gameplay runtime 生成 JSON 友好的 run payload，SaveManager 写入 envelope；标题继续时只返回 payload | `save()` / `load()` |
| F6 局外成长 | `MetaProgressionSystem` 归一化 profile、写入 meta payload，并在结算 / 购买 / 下一局 modifier 读取时调用 SaveManager | `save()` / `load()` / `has_save()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `save(slot, kind, payload)` | 槽位、save kind、payload 字典 | `bool` | kind 必须登记；失败时 `last_error()` 有原因 |
| `load(slot, kind)` | 槽位、save kind | `Dictionary` | 返回 payload 深拷贝；失败返回空字典 |
| `load_envelope(slot, kind)` | 槽位、save kind | `Dictionary` | 返回完整 envelope，供诊断 / UI 排序使用 |
| `delete(slot, kind)` | 槽位、save kind | `bool` | 删除正式、`.bak` 与 `.tmp`，无文件时返回 `false` |
| `has_save(slot, kind)` | 槽位、save kind | `bool` | 只检查正式 `*.save` 是否存在 |
| `list_slots()` | 无 | `Array[String]` | 返回 `user://saves/` 下非隐藏 slot 目录 |
| `register_migration(kind, from_version, to_version, migration)` | kind、版本、Callable | `bool` | 只允许逐级升版本；migration 必须返回 `Dictionary` |
| `registered_save_kinds()` | 无 | `Array[String]` | 返回已生成 save kind 列表 |
| `current_version(kind)` | save kind | `int` | 未登记 kind 返回 `0` |
| `save_root()` | 无 | `String` | 返回 `user://saves` |
| `last_error()` | 无 | `String` | 最近一次失败信息 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `save_written` | `slot`, `kind`, `path` | 存档写入成功 |
| `save_loaded` | `slot`, `kind`, `version`, `migrated` | 存档读取成功 |
| `save_deleted` | `slot`, `kind` | 存档删除成功 |
| `save_migrated` | `slot`, `kind`, `from_version`, `to_version` | 单步迁移完成 |
| `save_corrupted` | `slot`, `kind`, `path`, `error` | 坏档被隔离或标记 |

对应埋点走 `Analytics.track_event()`，事件名包括 `save_written`、`save_loaded`、`save_deleted`、`save_migrated` 和 `save_corrupted`。

## 数据与契约

save kind 来自 `docs/词表与契约.md` §14，当前为：

| kind | 用途 |
|------|------|
| `meta` | 局外成长长期档案：货币、账号等级、升级、解锁、累计统计 |
| `run` | 当前一局续局档案：暂停保存退出后加载恢复；当前 SaveManager kind version 为 2 |
| `replay_index` | 回放索引档案：具体回放文件仍由 `Replay` 管理 |

存档 envelope：

| 字段 | 类型 | 说明 |
|------|------|------|
| `version` | `int` | 当前 kind schema 版本 |
| `kind` / `slot` | `String` | 必须与文件路径和调用参数一致 |
| `created_at` / `updated_at` | `String` | wall time 诊断字段，不参与玩法判定 |
| `game_version` | `String` | 当前 GDD / 构建版本标签 |
| `data_hash` | `String` | payload 的稳定 hash，用于发现截断 / 人工破坏 |
| `payload` | `Dictionary` | 调用方的实际存档数据 |

`data_hash` 使用稳定序列化：字典按 key 排序，数组按原顺序，数字做整数 / 浮点规范化，避免 JSON 读回后 `3` / `3.0` 类型差异造成误报。

F5 首片的 F4 run payload 当前包含：schema version、模式 / 角色 id、等级、累计经验、击杀数、`GameClock` 快照、`RNG` 快照、刷怪状态、玩家状态、武器状态、活跃敌人、活跃子弹、活跃经验球和 `ui_restore`。`ui_restore` 只由玩法运行时解释，当前用于区分普通游玩、暂停菜单和升级选择面板；旧 payload 缺失该字段时由运行时按普通游玩处理。`RNG` seed/state 这类可能超过 JSON 安全整数精度的值必须以字符串保存，否则读回后会触发 `data_hash` mismatch。

`run` kind version 2 目前不改变 gameplay runtime 的 payload schema version（仍为 1），而是在 `SaveManager` 层为 v1 旧 envelope 补齐缺失的结构字段：`schema_version`、`spawn_states`、`player`、`weapon`、`game_clock`、`rng`、`enemies`、`bullets`、`pickups`。这样早期 F5 run 存档即使缺少可选数组 / 字典，也能加载为结构完整的 payload 后交给 runtime 恢复。

`meta` kind version 1 当前由 `MetaProgressionSystem` 写入，payload 字段包括 `schema_version`、`currencies`、`account_xp`、`account_level`、`purchased_upgrades`、`unlocked_ids` 和累计 `stats`。SaveManager 不校验这些业务字段，只校验 envelope 和 hash；profile 归一化、结算公式和购买规则见 `docs/代码/meta_progression_system.md`。

## 依赖

- 上游依赖：`DataLoader` 提供 save kind 契约校验；`Analytics` 记录存档诊断事件。
- 下游调用方：`MetaProgressionSystem`、暂停菜单、主菜单继续游戏、结算流程、回放索引 UI。
- 禁止依赖：玩家设置不得写入 `SaveManager`；`Replay` 的具体回放文件不得混入 `run` 存档；业务系统不得直接写 `user://saves/`。

## 扩展点

- 新 save kind：先登记 `docs/词表与契约.md` §14，跑 `tools/sync_contracts.py`，再补当前版本与文档。
- 新 schema 版本：更新 `CURRENT_KIND_VERSIONS`，注册逐级 migration，并补 L1 迁移测试。
- `meta` 接入：`MetaProgressionSystem` 负责解释 `meta_progression.json` 与 profile，`SaveManager` 只负责可靠读写；改 profile schema 时同步 `docs/代码/meta_progression_system.md`。
- `run` 接入：玩法系统生成可恢复快照，`SaveManager` 不知道玩家 / 敌人 / 子弹内部字段；保存对象池实体时只保存活动节点字段，恢复时由玩法系统通过 `PoolManager` 重新 acquire。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增 save kind | `docs/词表与契约.md`、`save_manager.gd` | 本文档、AI 导航 | `tools/sync_contracts.py --check`、headless boot |
| 改 envelope 字段 | `save_manager.gd` | 本文档、GDD §9.16、测试策略 | L1 + roundtrip + 坏档测试 |
| 改 `meta` payload | `MetaProgressionSystem`、数据配置 | 本文档、局外成长文档 | meta roundtrip + 数据校验 |
| 改 `run` 快照 / 迁移 | 玩法快照生产者、`save_manager.gd`、`client/tools/save_manager_smoke.gd` | 本文档、测试策略、回放文档 | `python tools/godot_bridge.py --project client save-smoke` + L5 存档 checklist |
| 改损坏隔离 | `save_manager.gd` | 本文档 | 坏 JSON / hash mismatch smoke |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| `save()` 返回 `false` | slot 是否为空或含路径字符；kind 是否登记；`last_error()` |
| `load()` 返回空字典 | 文件是否存在；hash 是否匹配；版本是否高于当前支持 |
| `.bak` 没有被使用 | 正式文件是否仍可通过 envelope 校验 |
| `.broken` 增长异常 | 是否有外部代码直接改存档；payload 是否含不稳定 / 不可 JSON 化数据 |
| 双坏档隔离后 `.bak` 残留 | `_unique_broken_path()` 是否仍为同一秒内的多个坏文件生成不撞名路径；跑 `save-smoke` |
| `save_slots` 数量异常 | `user://saves/` 下是否有空 slot 目录或人工文件 |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查、L2 headless boot，并跑 `python tools/godot_bridge.py --project client save-smoke`。
- 改 `meta` profile、结算、购买或局外成长存档调用方时追加 `python tools/godot_bridge.py --project client meta-smoke`；改死亡结算接入时追加 `python tools/godot_bridge.py --project client runtime-smoke`。
- 后续引入 GUT 后，`SaveManager` 必须覆盖 envelope 字段、hash mismatch、原子写入 / `.bak`、迁移链、坏档隔离、`meta` / `run` roundtrip、slot 校验和删除行为。
- 改存档 schema 必须注册 migration 并补迁移测试；改 `run` 续局字段还要跑 L5 存档 checklist，影响确定性时补黄金回放。

## 迁移 / 兼容

当前 `meta` 和 `replay_index` schema version 为 `1`；`run` schema version 为 `2`，已注册 `run` v1 -> v2 迁移，用于给早期 F5 run payload 补齐缺失的结构字段。未来每次提升 kind 版本时必须：

1. 更新 `CURRENT_KIND_VERSIONS[kind]`。
2. 用 `register_migration(kind, old, old + 1, fn)` 补逐级迁移。
3. 保证 migration 返回新的 payload `Dictionary`。
4. 更新本文档、测试策略中对应测试说明和当日会话日志。

不得跳版本注册迁移，不得静默丢弃未知字段。

## 相关文档

- `docs/游戏设计文档.md` §9.16
- `docs/词表与契约.md` §14
- `docs/测试策略.md`
- `docs/代码/analytics.md`
- `docs/代码/game_state.md`
- `docs/代码/meta_progression_system.md`
