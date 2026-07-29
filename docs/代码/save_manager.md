# SaveManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `SaveManager` autoload 的代码契约权威；改存档 envelope、公共 API、迁移、原子写入、损坏隔离、save kind 或测试义务时必须同步本文档。

## 职责

- `SaveManager` 负责完整项目的游戏内进度存档，统一管理 `meta`、`run` 与 `replay_index` 三类 save kind。
- 所有存档写入必须包含标准头字段：`version`、`kind`、`slot`、`created_at`、`updated_at`、`game_version`、`data_hash` 和 `payload`。
- 写入必须先落 `*.tmp`，替换前保留 `*.bak`；加载失败时尝试 `.bak`，仍失败则隔离到 `user://saves/.broken/` 并广播 / 埋点。
- 当前 F5 首片已由 gameplay runtime 接入真实 `run` 快照：暂停菜单“保存并退出”调用 `SaveManager.save(slot_0, run, payload)`，标题菜单“继续游戏”调用 `load()` 后交给运行时重建节点和 `ui_restore` 恢复点；`SaveManager` 仍只负责可靠读写，不解释玩家、敌人、子弹或 UI 字段。
- 当前 `meta` 为 v2、`run` 为 v11：Meta 保存上次确认组合且保留现有 Gear Mod payload；Run 在 v10 奖励状态基础上，额外保存武器弹匣 / 备弹 / 换弹、弹药未掉计数、`RNG.ammo` 与场上弹匣。旧 Run v10 无法恢复弹药确定性，不做有损迁移；启动流程提示一次后只删除 run，Meta v2 保留。
- F11 已由 `GearModSystem` 接管真实 `meta` profile：装备 Mod 资源、库存、loadout 和 rank 写入 `meta.gear_mods`；旧死亡结算货币 / 账号经验 / 永久升级运行时代码与旧档补偿路径已删除。`SaveManager` 仍不解释 profile 字段。
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
| `client/scripts/autoload/gear_mod_system.gd` | 当前 `meta.gear_mods` profile 的业务解释者和 SaveManager 调用方 |
| `client/tools/save_manager_smoke.gd` | F5 存档可靠性 headless smoke：run roundtrip、备份回退、坏档隔离、迁移 |
| `client/tools/gear_mod_smoke.gd` | F11 `meta.gear_mods` profile headless smoke：资源、库存、loadout、升级、分解和掉落 |
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
| 写入 | 校验 slot / kind，把 payload JSON 归一化后创建标准 envelope，写 `*.tmp`，备份旧文件到 `.bak`，再原子替换 | `save()` / `save_written` |
| 读取 | 读取正式文件，校验 envelope 与 `data_hash`，必要时跑迁移；失败则尝试 `.bak` | `load()` / `load_envelope()` / `save_loaded` |
| 迁移 | 按版本逐级调用已注册迁移函数，更新 payload、version 与 hash | `register_migration()` / `save_migrated` |
| 损坏 | 正式文件和备份都失败时，用唯一文件名隔离坏文件到 `.broken` 并发事件 | `save_corrupted` |
| 删除 | 删除正式、备份、临时文件；若 slot 目录空则清理空目录 | `delete()` / `save_deleted` |
| F5 续局 | Gameplay runtime 生成 JSON 友好的 run payload，SaveManager 写入 envelope；标题继续时只返回 payload | `save()` / `load()` |
| F11 装备 Mod | `GearModSystem` 归一化 profile、写入 `meta.gear_mods`，并在掉落 / 装备 / 升级 / 分解 / 开局 modifier 读取时调用 SaveManager | `save()` / `load()` / `has_save()` |

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
| `meta` | 局外长期档案，当前 v2：Gear Mod profile + 上次确认的 `main_hero_id` / `sub_hero_id` |
| `run` | 当前一局续局档案，当前 v11：完整世界、英雄组合、弹药 / 换弹 / 场上弹匣、经济、威胁时间、敌人奖励快照、显式攻击、世界事件和事务游标 |
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

`data_hash` 使用稳定序列化：字典按 key 排序，数组按原顺序，数字做整数 / 浮点规范化。写入前会先把 payload 通过 JSON stringify / parse 归一化，再基于归一化 payload 计算 hash 和落盘，避免高精度浮点或 JSON 读回后 `3` / `3.0` 类型差异造成误报。

Run v11 payload 包含 v10 的模块、事件和敌人奖励确定性字段，并在 `weapon` 保存弹匣、备弹、换弹状态 / 剩余时间，在顶层保存 `ammo_drop_misses`、全部 `ammo_magazines` 与独立 `RNG.ammo` state。恢复先建立武器配置再还原其弹药状态，随后通过 `ammo_magazine` 池恢复场上拾取物并重新绑定当前 Player / WeaponSystem；恢复不生成新的开火边沿，不重复转移备弹、不重抽掉率。所有对象池实体只保存 JSON 友好活动快照，恢复时重新 acquire；RNG 大整数仍以字符串保存。

`run` kind version 2 会在 `SaveManager` 层为 v1 旧 envelope 补齐缺失的结构字段：`schema_version`、`spawn_states`、`player`、`weapon`、`game_clock`、`rng`、`map`、`enemies`、`bullets`、`hazards`、`pickups`。这样早期 F5 run 存档即使缺少可选数组 / 字典，也能加载为结构完整的 payload 后交给 runtime 恢复；旧档没有机关快照时由 runtime 按当前 layout 重新生成。

`run` v4→v5 不猜测主／子英雄、四槽、防御层和部署物状态。迁移只写入 `legacy_run_incompatible=true` 与缺失组合标记；`FormalClientBoot` 读到后显示一次兼容性提示并删除该 run，不误报为损坏。该流程不读写 Meta，因此 Gear Mod 和上次选择保持不变。

`run` v5→v6 同样是不兼容重置边界：旧 payload 只有 `GameClock`，无法区分玩家在起点房停留的时间，也没有每只敌人的出生倍率。迁移只标记 `legacy_run_incompatible=true`，不使用当前难度重算既有敌人；`FormalClientBoot` 提示一次后只删除 run，Meta v2 与 Gear Mod 完整保留。

`run` v6→v7 是本次金币成长边界：迁移器清除旧 `level` / `xp` / 经验球 / 升级 UI 状态，写入空的金币、金币球和奖励选择结构，并设置 `legacy_run_incompatible=true`。正式启动不会尝试把 XP 猜测为余额或累计金币，而是提示一次后删除该 run；Meta v2 与 Gear Mod 完整保留。

`run` v8→v9 是世界事件幂等边界：旧档没有事件实例、固定模块、目标生命、固定波次、隐藏奖励或祭坛事务游标，无法安全推导中途状态。迁移器写入 schema 9、补空 `world_events` 并设置 `legacy_run_incompatible=true`；正式启动提示一次后只删除 run，Meta v2 与 Gear Mod 完整保留。

`run` v9→v10 是敌人奖励确定性边界：旧档没有既有敌人的最终金币 / 计算明细，也没有 `RNG.economy` state，无法在不多发、漏发或扰动未来随机的前提下恢复。迁移器写入 schema 10、清空旧敌人数组并设置 `legacy_run_incompatible=true`；正式启动提示一次后只删除 run，Meta v2 与 Gear Mod 完整保留。

`run` v10→v11 是枪械弹药确定性边界：旧档没有弹匣 / 备弹 / 换弹、独立 `RNG.ammo`、递增掉率计数或场上弹匣，无法判断下一次按下应开火、换弹还是抽取何种掉落。迁移器写入 schema 11、补空弹匣列表与零未掉计数并设置 `legacy_run_incompatible=true`；正式启动提示一次后只删除 run，Meta v2 与 Gear Mod 完整保留。

`meta` v1→v2 在保留 `gear_mods` 全部字段的同时补入默认组合“冷静主 + 愤怒子”。`FormalClientBoot` 在玩家确认组合时合并写回这两个 ID；SaveManager 仍只校验 envelope 与 hash，不解释业务字段。

## 依赖

- 上游依赖：`DataLoader` 提供 save kind 契约校验；`Analytics` 记录存档诊断事件。
- 下游调用方：`GearModSystem`、暂停菜单、主菜单继续游戏、回放索引 UI。
- 禁止依赖：玩家设置不得写入 `SaveManager`；`Replay` 的具体回放文件不得混入 `run` 存档；业务系统不得直接写 `user://saves/`。

## 扩展点

- 新 save kind：先登记 `docs/词表与契约.md` §14，跑 `tools/sync_contracts.py`，再补当前版本与文档。
- 新 schema 版本：更新 `CURRENT_KIND_VERSIONS`，注册逐级 migration，并补 L1 迁移测试。
- `meta` 接入：`GearModSystem` 解释 `meta.gear_mods`，FormalClientBoot 解释上次英雄组合；写入时必须合并，不能覆盖另一业务域。
- `run` 接入：玩法系统生成可恢复快照，`SaveManager` 不知道玩家 / 敌人 / 子弹内部字段；保存对象池实体时只保存活动节点字段，恢复时由玩法系统通过 `PoolManager` 重新 acquire。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增 save kind | `docs/词表与契约.md`、`save_manager.gd` | 本文档、AI 导航 | `tools/sync_contracts.py --check`、headless boot |
| 改 envelope 字段 | `save_manager.gd` | 本文档、GDD §9.16、测试策略 | L1 + roundtrip + 坏档测试 |
| 改 `meta` payload | `GearModSystem`、Gear Mod 数据配置 | 本文档、GearModSystem 文档 | `gear-mod-smoke` + 数据校验 |
| 改 `run` 快照 / 迁移 | 玩法快照生产者、`save_manager.gd`、`client/tools/save_manager_smoke.gd` | 本文档、测试策略、回放文档 | `python tools/godot_bridge.py --project client save-smoke`；人工存档 checklist 由用户执行 |
| 改损坏隔离 | `save_manager.gd` | 本文档 | 坏 JSON / hash mismatch smoke |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| `save()` 返回 `false` | slot 是否为空或含路径字符；kind 是否登记；`last_error()` |
| `load()` 返回空字典 | 文件是否存在；hash 是否匹配；版本是否高于当前支持 |
| `.bak` 没有被使用 | 正式文件是否仍可通过 envelope 校验 |
| `.broken` 增长异常 | 是否有外部代码直接改存档；payload 是否含不稳定 / 不可 JSON 化数据 |
| 高精度浮点保存后 hash mismatch | `save()` 是否仍先调用 JSON 归一化；payload 是否含非 JSON 友好的 Godot 对象或 Variant |
| 双坏档隔离后 `.bak` 残留 | `_unique_broken_path()` 是否仍为同一秒内的多个坏文件生成不撞名路径；跑 `save-smoke` |
| `save_slots` 数量异常 | `user://saves/` 下是否有空 slot 目录或人工文件 |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查、L2 headless boot，并跑 `python tools/godot_bridge.py --project client save-smoke`。
- 改 `meta.gear_mods` profile 或局外装配存档调用方时追加 `python tools/godot_bridge.py --project client gear-mod-smoke`；改死亡面板、标题入口或 run 清理时追加 `python tools/godot_bridge.py --project client runtime-smoke`。
- 后续引入 GUT 后，`SaveManager` 必须覆盖 envelope 字段、hash mismatch、原子写入 / `.bak`、迁移链、坏档隔离、`meta` / `run` roundtrip、slot 校验和删除行为。
- 改存档 schema 必须注册 migration 并补迁移测试；改 `run` 续局字段还要跑适用的自动 roundtrip，L5 存档 checklist 保持待人工验收并由用户执行。影响确定性时补黄金回放；改 payload hash / 序列化路径时必须保留高精度浮点 roundtrip 用例。

## 迁移 / 兼容

当前 `meta` 为 v2、`run` 为 v11、`replay_index` 为 v1，游戏版本标签为 `v1.10`。Meta v1→v2 保留 Gear Mod并补默认组合；Run 保留旧逐级迁移链，v4→v5 至 v10→v11 都是明确的不兼容重置边界。Replay 文件由 `Replay` 独立管理，当前为 v3。未来每次提升 kind 版本时必须：

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
- `docs/代码/gear_mod_system.md`
