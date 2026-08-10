# SaveManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `SaveManager` autoload 的代码契约权威；改存档 envelope、公共 API、迁移、原子写入、损坏隔离、save kind 或测试义务时必须同步本文档。

## 职责

- `SaveManager` 负责完整项目的游戏内进度存档，统一管理 `meta`、`run` 与 `replay_index` 三类 save kind。
- 所有存档写入必须包含标准头字段：`version`、`kind`、`slot`、`created_at`、`updated_at`、`game_version`、`data_hash` 和 `payload`。
- 写入必须先落 `*.tmp`，替换前保留 `*.bak`。主文件缺失时允许尝试 `.bak`；普通损坏主文件只有成功隔离到 `user://saves/.broken/` 并广播 / 埋点后才能尝试备份，隔离失败必须保留主 / 备文件并立即失败，避免静默绕过仍在原位的坏档。主文件若是需保留的不兼容 Run（版本或 mod environment 不匹配），同样立即失败并保留主 / 备文件，禁止用兼容备份偷偷覆盖该诊断。已实际尝试的备份若普通损坏则隔离，若需保留则原字节保留；最终失败的 `last_error()` 采用已存在且被尝试的备份错误。
- 当前 F5 首片已由 gameplay runtime 接入真实 `run` 快照：暂停菜单“保存并退出”调用 `SaveManager.save(slot_0, run, payload)`，标题菜单“继续游戏”调用 `load_envelope()` 后交给运行时重建节点和 `ui_restore` 恢复点；`SaveManager` 仍只负责可靠读写，不解释玩家、敌人、子弹或 UI 字段。
- 当前 `meta` 为 v4、`run` 为 v19：Meta 保存上次确认的主／副智能碎片和稀疏横向内容进度，不含本地或局内 Gear Mod 实例；Run 保存精确 `mod_environment`、GameplayEffectRuntime 状态、完整 7×7 assignment、Gear Mod placements、带实例 ID 的地面物、冻结内容池、玩家、经济、敌人、世界事件和 RNG 状态。旧 Run v18 保持原文件但不显示继续入口，不迁移。
- `GameplayRunLoop + GearModBoard` 是空间 Mod 状态权威，`GearModSystem` 不读写 SaveManager；Meta v4 中只允许 `content_progression.unlocked.gear_mod` 保存内容可用资格。Meta v3→v4 保留英雄组合并初始化空进度。
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
| `client/scripts/autoload/gear_mod_system.gd` | Gear Mod 无状态规则服务；不得调用 SaveManager |
| `client/tools/save_manager_smoke.gd` | F5 存档可靠性 headless smoke：run roundtrip、主档缺失 / 损坏 / 不兼容 × 备份有效 / 损坏 / 不兼容矩阵、坏档隔离与隔离失败关闭、FormalBoot 失败续局保留与迁移 |
| `client/tools/gear_mod_smoke.gd` | 局内 Gear Mod headless smoke：空开局、固定效果、重复实例乘算、立即应用、清空与 Run 恢复 |
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
| 读取 | 读取正式文件，校验 envelope 与 `data_hash`，必要时跑迁移；主文件缺失时尝试 `.bak`，普通损坏时先成功隔离再尝试 `.bak`，隔离失败或需保留的不兼容主文件直接返回错误且不读取备份；已尝试备份失败时返回备份诊断 | `load()` / `load_envelope()` / `save_loaded` |
| 迁移 | 按版本逐级调用已注册迁移函数，更新 payload、version 与 hash | `register_migration()` / `save_migrated` |
| 损坏 | 普通损坏主文件在回退前用唯一文件名隔离到 `.broken`；已尝试且普通损坏的备份同样隔离。需保留的不兼容文件不隔离 | `save_corrupted` |
| 删除 | 删除正式、备份、临时文件；若 slot 目录空则清理空目录 | `delete()` / `save_deleted` |
| F5 续局 | Gameplay runtime 生成 JSON 友好的 run payload，SaveManager 写入 envelope；标题继续时只返回 payload | `save()` / `load()` |
| 局内 Gear Mod / 效果 | `GameplayRunLoop` 把棋盘、Runtime 程序状态与带 `instance_id` 的未拾取实体写入 Run v19；恢复后只从 modifier components 替换应用 Mod 层，再恢复 Runtime | `save()` / `load()` |
| 内容进度 | `ContentUnlockSystem` 原子提交 Meta v4；Run v19 只暂存冻结池与未结算增量，本地 Gear Mod 不写 Meta | `save()` / `load()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `save(slot, kind, payload)` | 槽位、save kind、payload 字典 | `bool` | kind 必须登记；失败时 `last_error()` 有原因 |
| `load(slot, kind)` | 槽位、save kind | `Dictionary` | 返回 payload 深拷贝；失败返回空字典 |
| `load_envelope(slot, kind)` | 槽位、save kind | `Dictionary` | 返回完整 envelope，供诊断 / UI 排序使用 |
| `delete(slot, kind)` | 槽位、save kind | `bool` | 删除正式、`.bak` 与 `.tmp`，无文件时返回 `false` |
| `has_save(slot, kind)` | 槽位、save kind | `bool` | 当前版本且环境兼容时为 true；不兼容文件仍保留 |
| `save_status(slot, kind)` | 槽位、save kind | `Dictionary` | 返回 `exists/compatible/preserved_incompatible/error`，供标题继续入口与诊断使用 |
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
| `meta` | 局外长期档案，当前 v4：上次确认的 `main_hero_id` / `sub_hero_id` 与稀疏 `content_progression`；不含局内 Gear Mod 实例 |
| `run` | 当前一局续局档案，当前 v19：完整世界、英雄组合、冻结内容池、未结算进度、Gear Mod 棋盘 / 效果程序 / 地图行为 / 地面实例、经济、威胁时间、敌人奖励快照、显式攻击、世界事件和事务游标 |
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

Run v19 payload 延续模块、事件和敌人奖励确定性字段，并保存精确 `mod_environment[{id,version,gameplay_hash}]`、GameplayEffectRuntime 来源 / 冷却 / 周期 / action state、49 槽 assignment、`gear_mods.next_instance_id`、行优先 `unlocked_cells` / placements、顶层活动 `gear_mod_pickups`、非活动模块 `gear_mod_pickup_snapshots`、`content_availability` 与 `content_progress_delta`。核心从主英雄派生，不保存；每个地面拾取快照携带正整数 `instance_id` 与有限 `position`，棋盘、活动物和模块缓存间必须全局唯一。未提交 placement transaction 不保存，恢复后仍是普通地面物。缺包、版本或 gameplay hash 不匹配时保留原文件并阻止继续，不按损坏档隔离；当前版本内部未知字段、非法坐标 / 来源、非有限位置或逻辑上限超限才走坏档隔离。

`run` kind version 2 会在 `SaveManager` 层为 v1 旧 envelope 补齐缺失的结构字段：`schema_version`、`spawn_states`、`player`、`weapon`、`game_clock`、`rng`、`map`、`enemies`、`bullets`、`hazards`、`pickups`。这样早期 F5 run 存档即使缺少可选数组 / 字典，也能加载为结构完整的 payload 后交给 runtime 恢复；旧档没有机关快照时由 runtime 按当前 layout 重新生成。

`run` v4→v5 不猜测主／子英雄、四槽、防御层和部署物状态。迁移只写入 `legacy_run_incompatible=true` 与缺失组合标记；`FormalClientBoot` 读到后显示一次兼容性提示并删除该 run，不误报为损坏。该流程不读写 Meta，因此 Gear Mod 和上次选择保持不变。

`run` v5→v6 同样是不兼容重置边界：旧 payload 只有 `GameClock`，无法区分玩家在起点房停留的时间，也没有每只敌人的出生倍率。迁移只标记 `legacy_run_incompatible=true`，不使用当前难度重算既有敌人；`FormalClientBoot` 提示一次后只删除 run，Meta v2 与 Gear Mod 完整保留。

`run` v6→v7 是本次金币成长边界：迁移器清除旧 `level` / `xp` / 经验球 / 升级 UI 状态，写入空的金币、金币球和奖励选择结构，并设置 `legacy_run_incompatible=true`。正式启动不会尝试把 XP 猜测为余额或累计金币，而是提示一次后删除该 run；Meta v2 与 Gear Mod 完整保留。

`run` v8→v9 是世界事件幂等边界：旧档没有事件实例、固定模块、目标生命、固定波次、隐藏奖励或祭坛事务游标，无法安全推导中途状态。迁移器写入 schema 9、补空 `world_events` 并设置 `legacy_run_incompatible=true`；正式启动提示一次后只删除 run，Meta v2 与 Gear Mod 完整保留。

`run` v9→v10 是敌人奖励确定性边界：旧档没有既有敌人的最终金币 / 计算明细，也没有 `RNG.economy` state，无法在不多发、漏发或扰动未来随机的前提下恢复。迁移器写入 schema 10、清空旧敌人数组并设置 `legacy_run_incompatible=true`；正式启动提示一次后只删除 run，Meta v2 与 Gear Mod 完整保留。

`run` v10→v11 是 ADR #177 已废止的历史边界；迁移器不再创建任何弹药字段，只保留逐级迁移链并设置 `legacy_run_incompatible=true`。

`run` v11→v12 是 ADR #186 完全删除弹药系统的边界：迁移器删除旧武器弹量 / 换弹字段、顶层掉落计数 / 场上弹匣以及任何遗留弹药状态，并设置 `legacy_run_incompatible=true`。正式启动提示一次后只删除 run，Meta v2 与 Gear Mod 完整保留；不尝试把旧弹药状态折算为其他资源。

`run` v12→v13 是 ADR #188 的 Roguelike 直接通关与局内 Gear Mod 边界：旧 run 的 `pending_loot`、`extraction`、跨局 Mod 依赖和 modifier 恢复顺序不能无损转换，迁移只设置 `legacy_run_incompatible=true`；正式启动提示后删除旧 run，不尝试补发或折算奖励。

`run` v13→v14 是 ADR #189 的内容池冻结与结算进度边界：旧 run 没有 `content_availability` 与 `content_progress_delta`，无法证明局终计数是否已经提交，也无法按原池恢复 RNG。迁移只推进 schema 并设置 `legacy_run_incompatible=true`，不得伪造快照或增量；正式启动只删除旧 Run，Meta v4 保留。

`run` v14→v15 是 ADR #190 的 7×7 世界与随机意识核边界：旧 run 保存 9×9 / 81 槽 assignment，无法无损映射到 49 槽、左下起点与三候选目标。迁移只推进 schema 并设置 `legacy_run_incompatible=true`，不得裁剪旧 assignment 或重抽目标；正式启动只删除旧 Run，Meta v4 保留。

`run` v15→v16 是 ADR #191 的手动 Gear Mod 拾取边界：v15 尚未生成场上 Mod 实体，因此迁移无损保留 ranks 与全部局内状态，仅推进 schema 并补 `gear_mod_pickups=[]`；不得标记不兼容、补发或重抽奖励。

`run` v16→v17 是 ADR #193 的等级删除边界：旧 `gear_mods.ranks` 同时编码拾取次数与强度，不能无损映射为固定实例。迁移只推进 schema 并设置 `legacy_run_incompatible=true`，不读取、折算或伪造 `mod_ids`；正式启动提示一次后只删除 Run，Meta v4 保留。

`run` v17→v18 是 ADR #194 的空间棋盘边界：旧 `gear_mods.mod_ids` 没有实例 ID、坐标、解锁格和地图行为状态，无法无损推断 placement。迁移只推进 schema 并设置 `legacy_run_incompatible=true`；正式启动提示一次后只删除 Run，Meta v4 保留。

`meta` v1→v2 在保留当时 `gear_mods` 字段的同时补入默认组合；`meta` v2→v3 保留合法的 `main_hero_id` / `sub_hero_id`，直接删除旧 `gear_mods` inventory、rank、dust 与 loadout，不补偿。SaveManager 仍只校验 envelope 与 hash，业务层只解释英雄组合。

## 依赖

- 上游依赖：`DataLoader` 提供 save kind 契约校验；`Analytics` 记录存档诊断事件。
- 下游调用方：`GameplayRunLoop`、暂停菜单、主菜单继续游戏、回放索引 UI。
- 禁止依赖：玩家设置不得写入 `SaveManager`；`Replay` 的具体回放文件不得混入 `run` 存档；业务系统不得直接写 `user://saves/`。

## 扩展点

- 新 save kind：先登记 `docs/词表与契约.md` §14，跑 `tools/sync_contracts.py`，再补当前版本与文档。
- 新 schema 版本：更新 `CURRENT_KIND_VERSIONS`，注册逐级 migration，并补 L1 迁移测试。
- `meta` 接入：FormalClientBoot 解释上次英雄组合；`ContentUnlockSystem` 是内容资格与计数唯一写入方，局内 Gear Mod 实例不得写入 Meta。
- `run` 接入：玩法系统生成可恢复快照，`SaveManager` 不知道玩家 / 敌人 / 子弹内部字段；保存对象池实体时只保存活动节点字段，恢复时由玩法系统通过 `PoolManager` 重新 acquire。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增 save kind | `docs/词表与契约.md`、`save_manager.gd` | 本文档、AI 导航 | `tools/sync_contracts.py --check`、headless boot |
| 改 envelope 字段 | `save_manager.gd` | 本文档、GDD §9.16、测试策略 | L1 + roundtrip + 坏档测试 |
| 改 `meta` payload | `FormalClientBoot`、`save_manager.gd` | 本文档、GDD、测试策略 | `save-smoke` + `runtime-smoke` |
| 改 `run` 快照 / 迁移 | 玩法快照生产者、`save_manager.gd`、`client/tools/save_manager_smoke.gd` | 本文档、测试策略、回放文档 | `python tools/godot_bridge.py --project client save-smoke`；人工存档 checklist 由用户执行 |
| 改损坏隔离 | `save_manager.gd` | 本文档 | 坏 JSON / hash mismatch smoke |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| `save()` 返回 `false` | slot 是否为空或含路径字符；kind 是否登记；`last_error()` |
| `load()` 返回空字典 | 文件是否存在；hash 是否匹配；版本是否高于当前支持 |
| `.bak` 没有被使用 | 正式文件是否仍可通过 envelope 校验，或是否属于必须保留且阻止备份回退的版本 / mod environment 不兼容 Run |
| `.broken` 增长异常 | 是否有外部代码直接改存档；payload 是否含不稳定 / 不可 JSON 化数据 |
| 高精度浮点保存后 hash mismatch | `save()` 是否仍先调用 JSON 归一化；payload 是否含非 JSON 友好的 Godot 对象或 Variant |
| 双坏档隔离后 `.bak` 残留 | `_unique_broken_path()` 是否仍为同一秒内的多个坏文件生成不撞名路径；跑 `save-smoke` |
| `save_slots` 数量异常 | `user://saves/` 下是否有空 slot 目录或人工文件 |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查、L2 headless boot，并跑 `python tools/godot_bridge.py --project client save-smoke`。
- 改 Meta v4 英雄组合 / 内容进度或 Run v19 Gear Mod 棋盘 / Runtime / 地面实例 / 冻结池 / mod environment / 7×7 assignment 字段时追加 `content-progression-smoke`、`save-smoke`、`effect-runtime-smoke`、`mod-loader-v2-smoke`、`gear-mod-smoke`、`gear-mod-pickup-smoke`、`module-world-smoke` 与 `runtime-smoke`；Meta 必须断言不存在局内或本地 `gear_mods`。
- 后续引入 GUT 后，`SaveManager` 必须覆盖 envelope 字段、hash mismatch、原子写入 / `.bak`、迁移链、坏档隔离、`meta` / `run` roundtrip、slot 校验和删除行为；当前 smoke 的主 / 备 3×3 矩阵固定覆盖主文件缺失 / 普通损坏 / 需保留不兼容 × 备份有效 / 普通损坏 / 需保留不兼容，并逐项断言返回值、`last_error()`、原字节保留与 `.broken` 隔离状态；另以 `.broken` 路径碰撞覆盖“损坏主档隔离失败时不读取有效备份”。还须从 FormalBoot 继续按钮路径验证“损坏主档 + 不兼容备份”失败后退出 `LOADING`、显示不可用提示且备份字节不变。
- 改存档 schema 必须注册 migration 并补迁移测试；改 `run` 续局字段还要跑适用的自动 roundtrip，L5 存档 checklist 保持待人工验收并由用户执行。影响确定性时补黄金回放；改 payload hash / 序列化路径时必须保留高精度浮点 roundtrip 用例。

## 迁移 / 兼容

当前 `meta` 为 v4、`run` 为 v19、`replay_index` 为 v1，游戏版本标签为 `v1.18`。Meta v3→v4 保留英雄组合并初始化稀疏内容进度；旧 Run v18 保留但拒绝继续，不迁移。Replay 文件由 `Replay` 独立管理，当前为 v9，旧 Replay v8 保留但拒绝播放；四条黄金回放因统一效果、Gear Mod v6 与本地环境指纹变化有意重录。未来每次提升 kind 版本时必须：

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
