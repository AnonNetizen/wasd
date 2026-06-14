# 数值配置手册

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/游戏设计文档.md`、`docs/词表与契约.md` 与 `docs/代码文档规范.md`。
> 本文档是完整项目 `client/data/` 的人工调参数值手册；新增 / 修改数据文件、字段、单位、取值范围或 schema 时，必须同步 GDD、AI导航、词表、对应 `docs/代码/` 模块文档与测试义务。

---

## 目标

- 让策划 / 开发者 / AI 不改代码也能调整玩法数值。
- 所有可调数值集中在 `client/data/*.json`，由 `DataLoader` 读取，代码不写魔法数字。
- 每个数值字段都写清含义、单位、范围和影响范围，避免“看到字段不知道怎么调”。
- 玩家可见文案不写在数据里，只写 `name_key` / `desc_key` 等本地化 key，译文见 `client/locale/`。

## 快速上手

| 你想做什么 | 改哪里 | 注意 |
|------------|--------|------|
| 改玩家基础血量 / 移速 / 伤害 | `player.json` 的 `base_stats` | 字段名必须来自 `docs/词表与契约.md` 的 stat id |
| 改角色起始属性 / 起始武器 | `characters.json`（落地后） | 名字和描述只填 `name_key` / `desc_key` |
| 改敌人血量 / 速度 / 接触伤害 | `enemies.json`（落地后） | 敌人 id、标签、伤害类型必须来自词表 |
| 改遗物 / 道具数值 | `relics.json` / `active_items.json` / `consumables.json`（落地后） | 用 `modifiers` 和 `behaviors`，不要改逻辑分支 |
| 改刷怪强度 / 难度曲线 | `spawn_waves.json`（落地后） | 大改后需要跑回放 / 平衡验证 |
| 改经验阈值 / 升级候选概率 | `growth.json`（落地后） | 候选抽取走 `RNG.ui_choice`，概率字段不要写进代码 |
| 改局外货币 / 永久升级 / 解锁 | `meta_progression.json` | 存档走 `SaveManager` 的 `meta` kind，id 必须来自词表 §13 |
| 改界面、道具名、描述文案 | 不在这里改，去 `client/locale/strings.csv` | 数据只引用 key，译文集中管理 |

## 文件总览

| 文件 | 状态 | 作用 |
|------|------|------|
| `player.json` | 已建立 | 默认玩家基础属性，完整项目首个数值入口 |
| `characters.json` | 规划 | 角色列表：基础属性、起始武器 / 遗物、tags、capabilities、控制配置 |
| `weapons.json` | 规划 | 武器与子弹基础配置：射速、弹速、射程、池 id、默认伤害类型 |
| `relics.json` | 规划 | 被动遗物：`modifiers` + `behaviors`，只存 key 和数值，不存译文 |
| `active_items.json` | 规划 | 主动道具：充能方式、冷却、效果原语与参数 |
| `consumables.json` | 规划 | 消耗品：拾取 / 使用规则、效果原语与参数 |
| `enemies.json` | 规划 | 敌人基础属性、AI 类型、接触伤害、掉落表 |
| `hazards.json` | 规划 | 机关伤害、触发周期、范围、持续时间 |
| `spawn_waves.json` | 规划 | 刷怪波次、难度曲线、敌人权重、精英 / Boss 出现规则 |
| `growth.json` | 规划 | 经验阈值、升级候选数量概率、升级选项池和权重 |
| `meta_progression.json` | 已建立 | 局外货币、结算奖励、账号等级、永久升级轨道和内容解锁 |
| `_contracts.json` | 生成文件 | 由 `docs/词表与契约.md` 生成，禁止手改；`DataLoader` 用它校验 id |

## 通用格式规则

| 规则 | 说明 |
|------|------|
| JSON | 数据文件使用标准 JSON，不写注释；说明写在本文档或模块文档里 |
| UTF-8 / LF | 所有数据文件用 UTF-8 和 LF 换行 |
| snake_case | 字段名和 id 使用蛇形小写，和词表 id 保持一致 |
| `schema_version` | 长期维护数据文件必须有 schema 版本，schema 变更要配迁移 / 校验说明 |
| 单位明确 | 速度用 `px/s`，时间用秒，概率用 `0.0`~`1.0`，倍率用 `1.0` 表示不变 |
| 文案 key | 玩家可见名字 / 描述只存 `name_key` / `desc_key` / `hint_key` 等，不存硬文本 |
| id 白名单 | `stat`、`effect`、`event`、`damage_type`、`pool_id`、`tag` 等必须先登记到 `docs/词表与契约.md` |
| fail-fast | `DataLoader` 加载时必须校验字段类型、范围、必填项和词表 id；错误信息包含文件名 + 字段路径 + 期望值 |

## `player.json`

当前结构：

```json
{
  "schema_version": 1,
  "base_stats": {
    "max_hp": 6,
    "move_speed": 240.0,
    "fire_rate": 2.5,
    "damage": 3.5,
    "bullet_speed": 520.0,
    "bullet_range": 650.0,
    "bullet_count": 1,
    "pickup_range": 96.0,
    "luck": 0.0
  }
}
```

字段说明：

| 字段路径 | 类型 | 单位 / 范围 | 说明 | 调大后的效果 |
|----------|------|-------------|------|--------------|
| `schema_version` | int | `>= 1` | 数据结构版本 | 只在 schema 变更时调整 |
| `base_stats.max_hp` | int | `>= 1` | 默认最大生命 | 更耐打，失败更晚 |
| `base_stats.move_speed` | float | `px/s`，`> 0` | 默认移动速度 | 走位更灵活，地图探索更快 |
| `base_stats.fire_rate` | float | 每秒发数，`> 0` | 默认自动射击频率 | DPS 提升，弹幕更密 |
| `base_stats.damage` | float | `>= 0` | 单发基础伤害 | 击杀更快 |
| `base_stats.bullet_speed` | float | `px/s`，`> 0` | 子弹飞行速度 | 更容易命中远处移动敌人 |
| `base_stats.bullet_range` | float | `px`，`> 0` | 子弹最大射程 | 可打到更远敌人 |
| `base_stats.bullet_count` | int | `>= 1` | 每次开火基础子弹数 | 弹幕覆盖更宽 |
| `base_stats.pickup_range` | float | `px`，`>= 0` | 经验 / 金币自动吸附范围 | 收集更轻松 |
| `base_stats.luck` | float | `>= 0` | 幸运值 | 掉落、稀有度、升级 4 选 1 概率更高 |

## 内容数据通用字段

角色、敌人、遗物、道具等内容数据落地后，优先使用这些字段名，便于人和 AI 复用同一结构。

| 字段 | 类型 | 是否常见必填 | 说明 |
|------|------|--------------|------|
| `id` | string | 是 | 内容 id；必须来自对应词表或数据注册表 |
| `name_key` | string | 是 | 名称本地化 key，译文在 `client/locale/strings.csv` |
| `desc_key` | string | 视内容而定 | 描述本地化 key，译文在 `client/locale/strings.csv` |
| `tags` | array[string] | 视内容而定 | 内容标签；破限内容必须含 `tag_limit_break` |
| `capabilities` | array[string] | 视内容而定 | 允许突破的默认规则；id 来自词表 §12 |
| `base_stats` | object | 视内容而定 | 基础属性，字段来自词表 stat |
| `modifiers` | array[object] | 遗物常见 | 数值修正，格式见下节 |
| `behaviors` | array[object] | 行为内容常见 | 行为触发，格式见下节 |

## `modifiers` 格式

```json
{
  "stat": "damage",
  "type": "add",
  "value": 1.5
}
```

| 字段 | 类型 | 合法值 | 说明 |
|------|------|--------|------|
| `stat` | string | 词表 §1 stat id | 被修改属性 |
| `type` | string | `add` / `mult` | 加法或乘法修正 |
| `value` | number | 由具体 stat 决定 | `add` 为直接加值，`mult` 为倍率；`1.3` 表示乘 1.3 |

## `behaviors` 格式

```json
{
  "event": "on_hit",
  "effect": "split",
  "params": {
    "count": 2,
    "angle": 30.0
  }
}
```

| 字段 | 类型 | 合法值 | 说明 |
|------|------|--------|------|
| `event` | string | 词表 §3 behavior.event | 触发时机 |
| `effect` | string | 词表 §2 effect id | 效果原语 |
| `params` | object | 由 effect 定义 | 原语参数；新增参数要同步对应模块文档 |

## `meta_progression.json`

当前结构分为五块：

| 顶层字段 | 类型 | 说明 |
|----------|------|------|
| `schema_version` | int | 数据结构版本；schema 变更时递增并同步 `SaveManager` 迁移策略 |
| `currencies` | array[object] | 局外货币定义；当前默认 `meta_essence` |
| `run_rewards` | object | 单局结算奖励公式，决定局外货币来源 |
| `account_level` | object | 账号经验来源、等级阈值和等级奖励 |
| `upgrade_tracks` | array[object] | 可购买的永久升级轨道或成长树节点 |
| `unlocks` | array[object] | 可解锁内容列表，供等级奖励 / 升级轨道 / 挑战引用 |

### `currencies`

| 字段 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `id` | string | 词表 §13.1 currency id | 货币 id，存档中按该 id 保存余额 |
| `name_key` | string | `meta_*_name` | 货币名称本地化 key |
| `default_amount` | int | `>= 0` | 新存档初始余额 |
| `max_amount` | int | `> default_amount` | 余额上限，用于防溢出和 UI 显示 |

### `run_rewards`

| 字段 | 类型 | 单位 / 范围 | 说明 |
|------|------|-------------|------|
| `currency_id` | string | 词表 §13.1 currency id | 本公式产出的局外货币 |
| `base_amount` | int | `>= 0` | 完成一局的基础奖励 |
| `per_minute_survived` | int | 每分钟，`>= 0` | 按存活分钟追加奖励 |
| `per_50_kills` | int | 每 50 击杀，`>= 0` | 按击杀数追加奖励 |
| `first_boss_bonus` | int | `>= 0` | 本局首次 Boss / 精英里程碑奖励 |
| `max_amount_per_run` | int | `> 0` | 单局奖励上限，防止低风险刷货币 |

### `account_level`

| 字段 | 类型 | 单位 / 范围 | 说明 |
|------|------|-------------|------|
| `xp_per_minute_survived` | int | 每分钟，`>= 0` | 结算账号经验来源 |
| `xp_per_50_kills` | int | 每 50 击杀，`>= 0` | 击杀贡献的账号经验 |
| `thresholds` | array[int] | 递增，首项为 `0` | 每级所需累计账号经验 |
| `level_rewards` | array[object] | level 在阈值范围内 | 达到等级后授予的 `unlock_ids` |

### `upgrade_tracks`

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `id` | string | 词表 §13.2 upgrade id | 升级轨道 id，存档中保存已购等级 |
| `name_key` / `desc_key` | string | `meta_*_name` / `meta_*_desc` | 名称和描述本地化 key |
| `currency_id` | string | 词表 §13.1 currency id | 消耗的局外货币 |
| `max_level` | int | `>= 1` | 最大可购买等级 |
| `costs` | array[int] | 长度等于 `max_level` | 每一级购买成本 |
| `modifiers` | array[object] | stat 来自词表 §1 | 每级永久属性修正；用 `value_per_level` 表示逐级加成 |
| `unlock_ids_by_level` | array[array[string]] | unlock id 来自词表 §13.4 | 某级购买后额外授予的解锁，可选 |
| `unlock_condition` | object | 当前支持 `account_level` | 轨道显示 / 可购买条件 |

`modifiers` 示例：

```json
{ "stat": "damage", "type": "add", "value_per_level": 0.25 }
```

运行时由 `MetaProgressionSystem` 把已购等级转换为 `ModifierEngine` 修正器，禁止直接改 `player.json` 基础值。

### `unlocks`

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `id` | string | 词表 §13.4 unlock id | 解锁 id，存档中保存已解锁集合 |
| `kind` | string | 词表 §13.3 unlock kind | 解锁类型，如角色、遗物池、模式、难度阶层 |
| `target_id` | string | 对应内容 id | 被解锁的具体内容；若仅表示功能开关可省略 |
| `name_key` | string | `meta_*_name` | 面向玩家展示的解锁名，可选 |
| `default_unlocked` | bool | true / false | 新存档是否默认解锁 |

## 调参流程

1. 先看本文档确认字段单位和范围。
2. 只改目标 JSON，不改 GDScript 常量。
3. 如果新增 id，先改 `docs/词表与契约.md`，再跑 `/sync-contracts` 或等价同步流程。
4. 修改后运行 JSON / schema / 契约校验；代码落地后由 `DataLoader` fail-fast。
5. 大幅调整基础属性、难度曲线、掉落或升级概率后，按 `docs/测试策略.md` 跑回放 / 平衡验证。

## 新增数据文件或字段时

必须同步：

| 改动 | 必须同步 |
|------|----------|
| 新增数据文件 | 本文档文件总览、GDD §9.3、`docs/AI导航.md`、相关模块文档 |
| 新增字段 | 本文档字段说明、`DataLoader` schema、相关模块文档、必要时测试策略 |
| 新增 id 类型 | `docs/词表与契约.md`、生成常量、契约校验 |
| 新增玩家可见文案引用 | `client/locale/strings.csv` 与 `client/locale/README.md` |
| 改变玩家可见行为 | GDD、ADR、测试策略、模块文档 |

## 自检清单

- [ ] 数值是否在 `client/data/*.json`，而不是脚本常量？
- [ ] 字段单位、范围、默认值是否已写进本文档？
- [ ] 玩家可见文本是否只存 key，译文是否在 `client/locale/strings.csv`？
- [ ] 所有 id 是否来自 `docs/词表与契约.md`？
- [ ] 大幅平衡改动是否有回放 / sim / 人工试玩记录？
