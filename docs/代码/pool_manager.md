# PoolManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `PoolManager` autoload 的代码契约权威；改对象池 API、池 id 契约、预热 / 溢出策略、节点生命周期或测试义务时必须同步本文档。

## 职责

- `PoolManager` 负责统一管理高频实体对象池，后续子弹、敌人、伤害数字、命中特效和掉落物都应通过 `acquire()` / `release()` 进入生命周期。
- 池 id 必须来自 `docs/词表与契约.md` 第 8 节，并通过 `client/scripts/contracts/pool_ids.gd` 与 `DataLoader` 的 `_contracts.json` 校验。
- 池化节点必须实现 `_pool_reset() -> void`，用于每次获取时重置运行时状态；可选实现 `_pool_release() -> void`，用于释放前清理连接、计时器或外部引用。
- 正式 `GameplayRunLoop` 已用它管理子弹、五种敌人、机关、掉落和反馈实体；敌人池按 `enemies.csv` 动态注册并绑定专属 `PackedScene`。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 新增一个高频实体池 | `docs/词表与契约.md` 第 8 节，再看本文档公共 API |
| 接入子弹 / 敌人生成 | 本文档生命周期、`acquire()` / `release()` 约束 |
| 调对象池容量 | 本文档数据与契约、后续实体配置文档 |
| 排查溢出 | 本文档统计、`Analytics` 的 `pool_overflow` 事件 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/pool_manager.gd` | `PoolManager` autoload 脚本 |
| `client/scripts/contracts/pool_ids.gd` | 自动生成的对象池 id 常量 |
| `client/scripts/contracts/analytics_events.gd` | 自动生成的埋点事件常量 |
| `client/data/enemies.csv` | 五种敌人的独立 `pool_id`、专属 `scene_path` 与 `pool_prewarm` |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 运行开始时缓存唯一 actor 场景并按敌人数据注册 / 预热 / 清理各池 |
| `client/project.godot` | autoload 注册 |

## 场景 / 节点结构

`PoolManager` 是 autoload singleton，没有 `.tscn` 场景。预热或释放后的闲置节点会作为 `PoolManager` 子节点保存，并设置为不处理逻辑；获取后的节点可被调用方重新挂到玩法场景中。

```text
PoolManager (autoload Node)
├── bullet_basic_0 (inactive pooled node)
├── enemy_chaser_0 (inactive dedicated Enemy scene)
├── enemy_swarm_0 (inactive dedicated Enemy scene)
├── hit_spark_0 (inactive pooled node)
└── ...
```

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 注册 | 调用方传入已登记 pool id、factory 和容量上限 | `register_pool()` / `pool_registered` |
| 预热 | 按需提前创建节点，放入闲置队列 | `prewarm()` / `pool_warmed` |
| 获取 | 优先复用闲置节点；没有闲置且未到上限时创建；到上限时拒绝并埋点 | `acquire()` / `node_acquired` / `pool_overflow` |
| 重置 | 节点进入活跃状态后调用 `_pool_reset()` | `_pool_reset()` |
| 释放 | 调用 `_pool_release()`，移回 `PoolManager` 下并进入闲置队列 | `release()` / `node_released` |
| 清理 | 释放指定池或全部池的节点 | `clear_pool()` / `clear_all()` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `registered_pool_ids()` | 无 | `Array[String]` | 返回已生成的 pool id 列表 |
| `register_pool(pool_id, factory, max_size = 256)` | pool id、创建函数、上限 | `bool` | id 未登记、factory 无效或重复注册时返回 `false` |
| `prewarm(pool_id, count)` | pool id、数量 | `int` | 返回实际新建数量；不会超过 `max_size` |
| `acquire(pool_id)` | pool id | `Node` 或 `null` | 溢出或未注册时返回 `null` |
| `release(node)` | 池化节点 | `bool` | 节点不是由 `PoolManager` 获取时返回 `false` |
| `clear_pool(pool_id)` | pool id | `bool` | 删除并移除指定池 |
| `clear_all()` | 无 | `void` | 删除并移除全部池 |
| `has_pool(pool_id)` | pool id | `bool` | 当前运行时是否已注册该池 |
| `pool_count()` | 无 | `int` | 当前已注册池数量 |
| `available_count(pool_id)` | pool id | `int` | 闲置节点数量 |
| `active_count(pool_id)` | pool id | `int` | 活跃节点数量 |
| `stats(pool_id = "")` | 可选 pool id | `Dictionary` | 空参数返回全部池统计 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `pool_registered` | `pool_id`, `max_size` | 池注册成功后 |
| `pool_warmed` | `pool_id`, `requested`, `available` | 预热完成后 |
| `node_acquired` | `pool_id`, `node` | 节点获取成功后 |
| `node_released` | `pool_id`, `node` | 节点释放成功后 |
| `pool_overflow` | `pool_id`, `active_count`, `max_size` | 活跃 + 闲置已达上限且仍请求获取时 |
| `pool_cleared` | `pool_id` | 指定池清理完成后 |

溢出时还会调用 `Analytics.track_event(ANALYTICS_EVENTS.POOL_OVERFLOW, ...)`，用于后续调参和性能诊断。

## 数据与契约

池 id 源头是 `docs/词表与契约.md`，当前由 `tools/sync_contracts.py` 生成到：

- `client/data/_contracts.json`
- `client/scripts/contracts/pool_ids.gd`

当前敌人池为 `enemy_chaser`、`enemy_swarm`、`enemy_stalker`、`enemy_bulwark`、`enemy_spitter`。每行 `enemies.csv.pool_id` 必须唯一且等于敌人 id；旧 `enemy_ranged` 已删除。`pool_prewarm` 当前分别为 `8 / 5 / 3 / 4 / 8`，合计仍为 28。不同敌人内容 id 可以共享同一个 `scene_path`，但仍必须使用独立池，避免同一池在复用后出现错误的 `scene_file_path` 或静态外观。

视觉效果目录保留 `hit_spark`、`damage_number`，并登记 `vfx_weapon_muzzle_flash`。`visual_effects.json.high_frequency=true` 的效果必须提供已登记 `pool_id`；普通低频效果不需要预登记池。VFX 回池除了通用变换 / 可见性，还必须清理 Tween、AnimationPlayer 游标、材质实例参数、粒子 emitting / restart 和轨迹历史。

运行时每个池保存以下统计：

| 字段 | 类型 | 说明 |
|------|------|------|
| `available` | `int` | 闲置节点数量 |
| `active` | `int` | 活跃节点数量 |
| `created` | `int` | factory 累计创建节点数 |
| `acquired` | `int` | 累计获取次数 |
| `released` | `int` | 累计释放次数 |
| `overflows` | `int` | 达到上限后被拒绝的获取次数 |
| `max_size` | `int` | 池容量上限 |

## 依赖

- 上游依赖：`DataLoader` 提供 pool id 契约校验；`Analytics` 记录 `pool_overflow` 诊断事件。
- 下游调用方：正式子弹系统、敌人生成 / 模块 placement / 快照恢复、掉落物、伤害数字、命中特效和性能调试面板。
- 禁止依赖：高频实体不得直接 `instantiate()` / `queue_free()`；池 id 不得在调用点裸写未登记字符串。

## 扩展点

- 新实体池：先登记 pool id，再由实体系统调用 `register_pool()`，factory 返回对应场景实例。
- 新高频 VFX：先登记 pool id，再在 catalog 声明 `high_frequency/pool_id/prewarm`；由 `VfxHost` 延迟注册和预热。
- 预热配置：敌人从 `enemies.csv.pool_prewarm` 读取，其他实体继续由对应运行时 / 数据配置决定；不得把敌人预热数量重新硬编码到 RunLoop。
- 调试面板：读取 `stats()` 展示各池水位、命中率和溢出次数。
- 生命周期钩子：实体脚本实现 `_pool_reset()` 和 `_pool_release()`，不要让 `PoolManager` 知道具体玩法字段。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增 pool id | `docs/词表与契约.md` | 本文档、AI 导航 | `tools/sync_contracts.py --check`、headless boot |
| 调整对象池 API | `pool_manager.gd` | 本文档、测试策略 | L1 + L2 |
| 接入子弹池 | 子弹场景 / 脚本、生成系统 | 本文档、对应模块文档 | L1 + L2 + 性能 smoke |
| 加 / 改敌人专属池 | `enemies.csv`、专属继承场景、`GameplayRunLoop` | 数据手册、Gameplay Runtime、EnemyAI | data/schema + `actor-scene-smoke` + runtime/save/module-world |
| 加高频视觉效果池 | 词表、`visual_effects.json`、效果场景 | Visual Effects 文档、数据手册 | contracts/data + `vfx-smoke` |
| 改溢出策略 | `pool_manager.gd`、`Analytics` | 本文档、Analytics 文档 | L1 + 埋点检查 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| `register_pool()` 返回 `false` | pool id 是否登记；factory 是否有效；是否重复注册 |
| `acquire()` 返回 `null` | 池是否注册；是否达到 `max_size`；是否有 `pool_overflow` 事件 |
| 复用后状态残留 | 节点是否实现 `_pool_reset()` 并清掉运行时状态 |
| 释放后仍在场景里动 | 是否通过 `PoolManager.release()`；节点是否被外部重新设置 `process_mode` |

## 测试义务

- 必跑 L0 契约 / 数据 / 文档检查和 L2 headless boot。
- `l1-smoke` 覆盖基础 acquire / release 生命周期；`actor-scene-smoke` 覆盖五个独立敌人池；`vfx-smoke` 覆盖 VfxHost 延迟注册、预热、取消回池和可复用状态。
- 后续引入 GUT 后，继续补齐注册校验、预热上限、未知 id 拒绝、溢出埋点和 `stats()` 精细单测。性能 smoke 仍只在用户明确要求时运行。

## 迁移 / 兼容

当前没有持久化对象池状态，`PoolManager` 不参与存档。未来如果 `run` 续局需要恢复子弹、敌人或掉落物，状态应由 `SaveManager` 保存为玩法快照，再由实体系统通过 `PoolManager` 重建节点；不能直接保存池内部队列。

## 相关文档

- `docs/游戏设计文档.md` §9.13
- `docs/词表与契约.md` 第 8 节
- `docs/测试策略.md`
- `docs/代码/analytics.md`
