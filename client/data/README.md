# 数值配置手册

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/游戏设计文档.md`、`docs/词表与契约.md` 与 `docs/代码文档规范.md`。
> 本文档是完整项目 `client/data/` 的人工调参数值手册；新增 / 修改数据文件、字段、单位、取值范围或 schema 时，必须同步 GDD、AI导航、词表、对应 `docs/代码/` 模块文档与测试义务。

---

## 目标

- 让策划 / 开发者 / AI 不改代码也能调整玩法数值。
- 所有可调数值集中在 `client/data/`，由 `DataLoader` 读取，代码不写魔法数字。
- 文件格式按数据形态选择：**平表数值优先 CSV，复杂配置优先 JSON**。
- 每个数值字段都写清含义、单位、范围和影响范围，避免“看到字段不知道怎么调”。
- 玩家可见文案不写在数据里，只写 `name_key` / `desc_key` 等本地化 key，译文见 `client/locale/`。

## Godot 数据配表入口

Godot 4.7.1 顶部中央主界面的“数据配表”可一站式编辑普通 `client/data` JSON、全部数据 CSV 和 `client/locale/strings.csv`，并在这些来源中搜索 ID、字段名、中文、英文、数值、布尔和最多 8 层嵌套字段。JSON 不需要拥有相同层级：左侧数据集目录声明记录分区和主键，中间表格处理顶层标量，右侧递归属性树处理对象、数组和多态字段。

以下文件不属于数据配表：`_contracts.json` 是生成文件；`modules/*.json`、`module_templates.json`、`module_tile_catalog.json` 使用“Module JSON”；`visual_effects.json`、`presentation_profiles.json` 使用“VFX 效果库”。`module_worlds.json` 仍是普通配置，继续在数据配表中编辑和搜索。

数据配表的未完成修改只保存在 `user://data_table_editor/`。点击保存时会检查外部文件 hash，备份本事务全部目标，写入 JSON/CSV/locale/受控内容契约，再运行独立 headless `DataLoader.validate_project_data()`；失败会回滚项目文件并保留草稿。已有 ID 不直接改名，使用“复制为新 ID → 修正引用 → 删除旧记录”。完整契约见 `docs/代码/data_table_editor.md` 与 ADR #180。

## 快速上手

| 你想做什么 | 改哪里 | 注意 |
|------------|--------|------|
| 改玩家基础血量 / 移速 / 伤害 | `player.json` 的 `base_stats` | 字段名必须来自 `docs/词表与契约.md` 的 stat id |
| 改瞄准方向引导镜头或玩家受伤 / 武器后坐力震屏 | `camera_feedback.json` 的 `aim_look` / `player_damage_shake` / `weapon_recoil_shake` | 引导偏移按输入源计算并独立于震屏；噪声随机走 `RNG.camera_fx` |
| 选择 / 调整视觉效果 | `visual_effects.json`、`presentation_profiles.json` | 内容数据只引用 `presentation_profile_id`；在 Godot 的“VFX 效果库”中预览和绑定，不手抄字符串 |
| 改智能碎片主属性 / 被动 / 两个技能 / 配色 | `characters.json` | 名字和描述只填 `name_key` / `desc_key`；palette 必须且只能含一个 `primary`。主碎片提供属性、被动、主色和技能 1/2，副碎片提供副色和技能 3/4 |
| 改武器射速 / 后坐力 / 弹道扩散 / 弹匣 / 换弹 / 空弹降级 | `weapons.json` | 武器 id 文件内唯一；后坐力与基础扩散受根级 `recoil_model` 限制，弹匣、备用弹药、总容量、换弹时间和空弹倍率均为每武器必填；子弹池、元素和音频前缀必须来自词表 |
| 改弹匣拾取速度 / 敌人掉落概率 / 递增保底 | `ammo_rules.json` | schema v1；拾取物走 `ammo_magazine` 对象池，掉落判定只使用 `RNG.ammo`，满弹时不消费或推进该子流 |
| 改敌人血量 / 速度 / 怪物金币价值 / 中心间距 | `enemies.csv` | `gold_value_multiplier` 只表达怪物相对价值；全局金币公式改 `enemy_rewards.json`；显式攻击参数统一在 `enemy_ai_profiles.json.actions[].attack` |
| 改敌人对玩家 AI | `enemy_ai_profiles.json` | AI action 必须来自词表 §12-B；敌人的感知与战斗目标固定为玩家 |
| 改机关伤害 / 占格尺寸 / 触发周期 | `hazards.csv` | 机关标签、对象池 id、伤害类型必须来自词表；范围尺寸写正整数 `radius_tiles` |
| 改地图边界 / 矩形格 / PCG 机关 / 人工摆点 | `map_layouts.json` | 地图绑定模式 id；bounds 是轴对齐矩形，必须分别整除 `grid.cell_width` / `grid.cell_height`；PCG 使用 `RNG.world` 并按机关占格奇偶吸附到合法矩形格锚点 |
| 改敌巢战区导演 / 阶段主题 / 兴趣点组合 | `warzone_directors.json` | 只按固定时间阶段启用 wave，不读取玩家状态、不做隐藏动态难度；匹配当前 layout 的兴趣点会生成初始 `source="director"` 机关；wave / 机关 / 地图引用必须存在 |
| 加 / 改模块模板 | 在 Godot 的 `Module JSON` 中央主编辑区编辑 `modules/<id>.json`，再显式 Validate / Bake | 模块固定 11×11 格；JSON 是人工与 AI 协作主源，生成 TSCN 禁止手改，玩法变化会降为 `candidate` |
| 改 9×9 世界骨架 / 路线预算 | `module_worlds.json` | 同一世界统一格尺寸；固定起点 / 目标 / 撤离锚点，其余槽位按 `RNG.world` + run seed 组合 |
| 改世界事件数值 / 波次 / 祭坛概率 | `world_events.json` | schema v1；事件、Gear Mod 池、波次与祭坛参数严格校验，运行时随机走 `RNG.world_event` |
| 改遗物数值 / 效果声明 | `relics.json` | 用 `modifiers` 和 `behaviors`，不要改逻辑分支 |
| 改主动道具冷却 / 效果声明 | `active_items.json` | 用 `charge` 和 `use_effects`，不要实现运行时分支 |
| 改技能消耗 / 冷却 / 目标 / 伤害 | `skills.json` | 技能不绑定英雄；角色或道具只引用 skill id，资源消耗用 `skill_resources` 声明 |
| 改消耗品堆叠 / 效果声明 | `consumables.json` | 用 `stack` 和 `use_effects`，不要实现拾取 / 背包运行时 |
| 改某个游戏模式可用内容 / 权重 | `game_modes.json` | 模式只组合资源池、难度 profile 和轻量覆盖；不要复制角色 / 遗物本体 |
| 改难度名称 / 系数或敌人随时间增长的生命 / 伤害曲线 | `difficulty_profiles.json` | 难度系数缩放威胁时间和生成金币；当前只配置标准 `1.0`，尚无选择 UI |
| 改敌人金币基础系数 / 阶段增长 / 随机范围 | `enemy_rewards.json` | schema v1；实际金币在敌人成功生成时用 `RNG.economy` 锁定，死亡时不重算 |
| 改开放战区刷怪组合 / 波次 | `spawn_waves.csv` | 大改后需要跑回放 / 平衡验证 |
| 改金币等级曲线 / 通用奖励候选 | `level_progression.json` / `reward_choice_pools.json` | 等级曲线使用整数有理数；候选数量由调用方指定 2–5，抽取走 `RNG.ui_choice` |
| 改装备 Mod / 英雄或武器装配 | `gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv` | 装备 Mod 与本地数据包 mod 是不同概念；Mod id / slot / rarity / resource / stack rule 必须先登记契约 |
| 改致谢 / 第三方来源 | `credits.json` + 根目录 `CREDITS.md` | 游戏内 Credits UI 读 `credits.json`；Godot 编辑器插件来源与本地补丁另见 `client/addons/README.md`；发行前复核许可证与 notice |
| 改界面、道具名、描述文案 | 不在这里改，去 `client/locale/strings.csv` | 数据只引用 key，译文集中管理 |
| 做本地 mod 内容包 | `user://mods/<mod_id>/mod.json` + mod 自带 `data/` patch | 通过 `ModLoader` 声明式追加 JSON / CSV；不改 `client/data/` 原文件，不执行脚本 |

## 文件总览

| 文件 | 状态 | 作用 |
|------|------|------|
| `player.json` | 已建立 | 默认玩家基础属性，完整项目首个数值入口 |
| `camera_feedback.json` | 已建立 | 摄像机表现反馈；含瞄准方向引导偏移、玩家有效受伤与武器后坐力的 Phantom Camera 参数 |
| `difficulty_profiles.json` | 已建立 | schema v2：难度双语名称 / 系数、模式级威胁时间曲线、阶段跃升、伤害换算比例和九段名称 |
| `enemy_rewards.json` | 已建立 | schema v1：敌人金币基础系数、每阶段增长与 `RNG.economy` 随机倍率范围 |
| `game_modes.json` | 已建立 | 游戏模式配置：难度 profile、可用角色 / 武器 / 敌人 / 机关 / 遗物 / 主动道具 / 技能 / 消耗品、权重、禁用列表、参与者 / 队伍预留和轻量覆盖 |
| `characters.json` | 已建立 | 英雄列表：场景、主副配色、基础属性、被动、两个英雄技能和起始携带 |
| `weapons.json` | 已建立 | schema v4：武器、后坐力 / 弹道扩散、弹匣 / 备用弹药 / 换弹 / 空弹降级与子弹基础配置 |
| `ammo_rules.json` | 已建立 | schema v1：弹匣拾取对象池、吸附速度、单次补给、敌人掉落概率递增与 `RNG.ammo` 子流 |
| `relics.json` | 已建立 | 被动遗物：`modifiers` + `behaviors`，只存 key 和数值，不存译文 |
| `active_items.json` | 已建立 | 主动道具：充能方式、冷却、效果原语与参数 |
| `skills.json` | 已建立 | 可复用技能：冷却、资源消耗、目标选择和技能效果原语 |
| `consumables.json` | 已建立 | 消耗品：堆叠数量、拾取数量、效果原语与参数 |
| `enemy_ai_profiles.json` | 已建立 | 敌人对玩家 AI profile：感知、动作列表、冲锋 / 守家 / 远程等行为参数 |
| `enemies.csv` | 已建立 | 敌人基础数值平表：专属场景、独立对象池、预热数量、生命、移速、金币价值倍率和碰撞 / 分离半径 |
| `hazards.csv` | 已建立 | 机关基础数值平表：伤害、触发周期、占格尺寸、持续时间 |
| `map_layouts.json` | 已建立 | 有限地图配置：矩形地图边界、矩形格尺寸、玩家出生点、安全半径、PCG 机关规则和人工摆点 |
| `warzone_directors.json` | 已建立 | 敌巢战区导演：固定阶段、巢变异主题、兴趣点 / 机关组合和阶段启用 wave |
| `module_worlds.json` | 已建立 | F13 模块世界：9×9 槽位、11×11 格、统一格尺寸、固定锚点、模板池、安全布局和技术首片 |
| `world_events.json` | 已建立 | 世界事件 schema v1：防御、生存、占点、金币祭坛与血量祭坛，以及事件 Gear Mod 候选池 |
| `module_templates.json` | 已建立 | 模块注册表：角色、JSON 路径、AI 来源、审核状态、批准时 source hash 和可用旋转 |
| `module_tile_catalog.json` | 已建立 | 稳定 `module_tile_id` 到 Godot TileSet source / atlas / alternative 的编辑期映射 |
| `modules/*.json` | 制作主源 | 11×11 地形、placement 与三层视觉声明；由人工、AI 和 Module JSON Editor 协作维护 |
| `spawn_waves.csv` | 已建立 | 刷怪波次、难度曲线、敌人权重和可选机关权重 |
| `level_progression.json` | 已建立 | 金币驱动等级曲线：首段成本和整数倍率 |
| `reward_choice_pools.json` | 已建立 | 通用奖励选项池、权重、等级条件和 modifier 边界 |
| `gear_mods.json` | JSON | 装备 Mod 定义：英雄 / 武器槽位、稀有度、rank、drain、修正器和分解返还 |
| `gear_mod_drop_tables.csv` | CSV | 装备 Mod 掉落来源、概率和等级条件 |
| `gear_mod_fusion_costs.csv` | CSV | 装备 Mod 按稀有度 / rank 的升级资源成本 |
| `credits.json` | 已建立 | 游戏内致谢数据源：工作人员、开发工具、外部资源、外部库、适用构建目标与许可 / notice 状态；G.U.I.D.E、Xelu prompts 与 Lato 字体分别登记，vendored Godot 插件说明见 `client/addons/README.md`，Steamworks Lab 的随包声明见其 `THIRD_PARTY_NOTICES.txt` |
| `visual_effects.json` | 已建立 | 视觉效果 catalog：资源、领域、技术标签、空间、生命周期、对象池与预览元数据 |
| `presentation_profiles.json` | 已建立 | 表现 profile 继承与 cue → 视觉 / 音频 / 相机 / 屏幕绑定 |
| `_contracts.json` | 生成文件 | 由 `docs/词表与契约.md` 生成，禁止手改；`DataLoader` 用它校验 id |

## 视觉效果与表现 Profile

正式内容通过 `presentation_profile_id` 选择表现：当前角色、武器、技能、敌人和机关均必填；未来遗物、主动道具和消耗品可选。profile id 是数据主键，不要求新增代码常量；固定 `cue/domain/kind/space/lifecycle/anchor/quality` 必须来自 `docs/词表与契约.md` §16。

`visual_effects.json` 当前为 schema v3；旧 v1/v2 和遗留 `reduced_motion` / `quality_variants` 字段不兼容。`effects[]` 字段：

| 字段 | 类型 / 规则 | 说明 |
|------|-------------|------|
| `id` / `editor_name` | `id` 唯一；两者均为非空 string | `id` 是英文稳定主键；`editor_name` 是面向编辑器使用者的中文显示名，不参与引用与数据指纹语义 |
| `domain` / `kind` | 词表枚举 | 使用领域与 spawned scene / target animation / screen overlay |
| `resource_path` | 正式 `res://` 资源 | 禁止 addon、`output/test_lab` 和裸程序几何 |
| `space` / `lifecycle` | 词表枚举 | 挂载空间与 one-shot / loop / state |
| `duration` | 非负秒 | 播放 / 预览时长 |
| `pool_id` / `prewarm` / `max_size` | 可选 | 高频效果必须提供已登记 pool id；预热 / 上限为非负 / 正整数 |
| `high_frequency` | bool | 不能把枪口、命中等高频效果误标低频来绕过池校验 |
| `tags` | string array | 技术、读法与可选装饰标签；`screen_flash` 受设置控制 |
| `preview` | object | 编辑器预览参数 |
| `preview.background` | string | 预览背景 id |
| `preview.checkpoint` | string | `charge` / `contact` / `aftermath` |
| `preview.scale` | number | 预览默认比例，必须为正数 |

`presentation_profiles.json.profiles[]` 字段：

| 字段 | 类型 / 规则 | 说明 |
|------|-------------|------|
| `id` | 唯一非空 string | 稳定 profile id |
| `editor_name` | 可选非空 string | 中文编辑器显示名；缺省时回退显示稳定 `id`，不参与引用 |
| `parent_profile_id` | 可空 profile id | 按 cue 继承，禁止环 |
| `bindings` | cue → object | cue 来自词表；子级同 cue 完整覆盖父级 |
| `effects` | effect binding array | 每项含 `effect_id`、`anchor`，可选表现 `params` |
| `effects[].effect_id` / `effects[].anchor` | string | effect id 与词表 anchor |
| `effects[].params` | object | 仅覆盖表现参数，不改变玩法 |
| `effects[].params.tint` | HTML color string | 可选运行时色调覆盖 |
| `effects[].params.scale` | number 或 Vector2 | 可选实例缩放覆盖；只影响表现 |
| `audio_id` / `camera_feedback_id` / `screen_effect_id` | 可空 string | 跨系统反馈引用 |
| `hit_stop_profile_id` | 首版必须空 | 只预留接口，不驱动 `GameClock` |

`presentation_enemy_rifle` 只继承默认敌人受击 / 退场表现，不绑定 `enemy_attack_telegraph` 或 `enemy_attack_impact`；突击枪手保留每轮一次 telegraph cue 和每弹一次 impact cue 的玩法语义，但 0.32 秒前摇与逐发开火均不生成枪口视觉。`presentation_weapon_default.weapon_fire.effects` 固定为空，只保留 `weapon_recoil_shake` 相机反馈。正式 catalog 不登记枪口闪光 effect，也不登记其专用 VFX 池。

效果数据、内容 profile 引用与资源存在性由 `DataLoader` 和 `tools/validate_data.py` 双重校验；运行时契约与新增向导见 `docs/代码/visual_effects.md`。

## 本地 Mod 数据包

当前项目预留本地 mod 接口，供玩家未来制作内容包；创意工坊暂不接入。分发平台未来只负责把订阅内容放到 `user://mods/<mod_id>/`，游戏内加载仍走 `ModLoader` + `DataLoader`。

最小目录：

```text
user://mods/my_first_mod/
  mod.json
  data/
    relics_patch.json
    strings_patch.csv
```

`mod.json` 示例：

```json
{
  "schema_version": 3,
  "id": "my_first_mod",
  "name": "My First Mod",
  "version": "0.1.0",
  "enabled": true,
  "load_order": 0,
  "contract_extensions": {
    "content_tags": ["mod_my_first_mod_tag"],
    "locale_prefixes": ["mod_my_first_mod_"]
  },
  "data_patches": [
    {
      "type": "json_array_append",
      "target": "relics.json",
      "path": "data/relics_patch.json",
      "array_key": "relics"
    },
    {
      "type": "csv_append",
      "target": "strings.csv",
      "path": "data/strings_patch.csv"
    }
  ]
}
```

| 规则 | 说明 |
|------|------|
| 包 id | `mod.json` 的 `id` 必须等于目录名 `<mod_id>`，重复 id 只会启用第一个 |
| 数据追加 | 当前只支持 `json_array_append` 和 `csv_append`，不支持覆盖 / 删除基础数据 |
| 动态 id | 只允许 manifest 扩展 `character_ids`、`game_modes`、`content_tags`、`locale_prefixes`；值必须以 `mod_<mod_id>_` 开头 |
| 核心契约 | mod 不能扩展 `stats`、`effects`、`events`、`elements`、`pool_ids`、`audio_prefixes`、`rng_streams`、`save_kinds` 等需要代码或资源同步的类别 |
| 文案 | mod 文案仍用 CSV，建议通过 `locale_prefixes` 声明 `mod_<mod_id>_` 前缀；基础 `zh_CN` / `en` 列规则不变 |
| 安全 | manifest 的 `path` 只能指向 mod 自身目录内相对路径，禁止 `..`、绝对路径和 `://` |
| 验证 | 启动时 `DataLoader` 校验合并后的数据；错误看 `[ModLoader]` / `[DataLoader]` 日志 |

## 通用格式规则

| 规则 | 说明 |
|------|------|
| 格式选择 | 平表数值优先 CSV，复杂配置优先 JSON；现有文件不强制立即迁移，新增 / 重构时按本规则判断 |
| CSV | 使用标准逗号分隔、首行为表头；适合一行一个条目、列结构稳定的数值表 |
| JSON | 使用标准 JSON，不写注释；适合嵌套对象、数组、可变长度行为、条件树和参数包 |
| UTF-8 / LF | 所有数据文件用 UTF-8 和 LF 换行 |
| snake_case | 字段名和 id 使用蛇形小写，和词表 id 保持一致 |
| `schema_version` | 长期维护数据文件必须有 schema 版本，schema 变更要配迁移 / 校验说明 |
| 单位明确 | 速度用 `px/s`，时间用秒，概率用 `0.0`~`1.0`，倍率用 `1.0` 表示不变 |
| 模式复用 | 角色、遗物、道具、敌人等资源本体默认模式无关；模式配置只引用资源池、权重、条件、禁用列表和轻量覆盖 |
| 多人预留 | 当前只做单人；模式 / 伤害 / 回放 / 存档数据可预留 participant / team / friendly_fire 等字段，但不得提前实现网络协议或复制多人专用资源 |
| 文案 key | 玩家可见名字 / 描述只存 `name_key` / `desc_key` / `hint_key` 等，不存硬文本 |
| 致谢原文 | 外部项目名、人员名、许可证名、URL 与版权声明保持原文；面向玩家的分组标题 / 角色说明用 locale key |
| id 白名单 | `stat`、`effect`、`event`、`element_id`、`pool_id`、`tag` 等必须先登记到 `docs/词表与契约.md` |
| fail-fast | `DataLoader` 加载时必须校验字段类型、范围、必填项和词表 id；错误信息包含文件名 + 字段路径 + 期望值 |

## CSV / JSON 选择规则

| 数据形态 | 优先格式 | 示例 |
|----------|----------|------|
| 一行一个条目、列固定、经常人工排序 / 筛选 / 批量调参 | CSV | `enemies.csv`、`hazards.csv`、`spawn_waves.csv` |
| 数组 / 对象嵌套、每条内容参数数量不同、需要表达条件树 | JSON | `game_modes.json`、`map_layouts.json`、`warzone_directors.json`、`module_worlds.json`、`module_templates.json`、`modules/*.json`、`enemy_ai_profiles.json`、`weapons.json`、`ammo_rules.json`、`relics.json`、`active_items.json`、`consumables.json`、`characters.json`、`gear_mods.json`、`level_progression.json`、`reward_choice_pools.json` |
| 玩家可见文案 | CSV | `client/locale/strings.csv` |
| 致谢 / 第三方来源清单 | JSON | `credits.json`，需同时同步根目录 `CREDITS.md` |
| 自动生成契约 | JSON | `_contracts.json`，禁止手改 |

CSV 示例：

```csv
id,max_hp,move_speed,gold_value_multiplier
slime,20,90,1.0
bat,12,150,0.6666667
brute,80,60,2.0
```

JSON 示例：

```json
{
  "id": "relic_split_rounds",
  "behaviors": [
    { "event": "on_hit", "effect": "split", "params": { "count": 2, "angle": 20.0 } },
    { "event": "on_fire", "effect": "pierce", "params": { "count": 1 } }
  ]
}
```

## CSV 通用规则

| 规则 | 说明 |
|------|------|
| 表头必填 | 第一行必须是字段名，字段名使用 `snake_case` |
| `id` 列 | 内容表必须有稳定 `id` 列，id 不得重复 |
| 空值 | 空值只用于可选字段；必填字段空值 fail-fast |
| 数字类型 | `DataLoader` / 校验脚本按字段 schema 转 int / float；人工不要写单位后缀 |
| 布尔值 | 使用 `true` / `false` 小写 |
| 多值 id | CSV 中少量多标签字段使用 `|` 分隔，例如 `tag_enemy|tag_limit_break` |
| 列新增 | 新增列必须同步本文档字段说明和对应 schema |
| 复杂参数 | 不把 JSON 字符串硬塞进 CSV；出现复杂参数时拆到 JSON 文件或独立配置 |

## `player.json`

当前结构：

```json
{
  "schema_version": 4,
  "body": {
    "radius": 25.0
  },
  "base_stats": {
    "max_hp": 600.0,
    "health_regen": 0.0,
    "move_speed": 240.0,
    "player_separation_radius": 25.0,
    "fire_rate": 2.5,
    "damage": 3.5,
    "bullet_speed": 350.0,
    "bullet_range": 650.0,
    "bullet_count": 1,
    "pickup_range": 96.0,
    "luck": 0.0
  },
  "defense": {
    "shield": {
      "recharge_delay": 4.0,
      "recharge_rate": 25.0,
      "overshield_decay_ratio_per_second": 0.05,
      "overshield_snap_threshold": 1.0
    },
    "armor": {"coefficient": 300.0, "maximum": 1200.0},
    "shield_gate": {"max_duration": 0.5}
  },
  "dash": {
    "distance": 120.0,
    "speed": 750.0,
    "duration": 0.16,
    "cooldown": 1.25,
    "invulnerability_duration": 0.12
  },
  "energy_drop": {
    "chance": 0.1,
    "amount": 25.0,
    "pickup_speed": 360.0,
    "pool_id": "energy_orb",
    "rng_stream": "drop"
  },
  "gold_drop": {
    "pickup_speed": 360.0,
    "pool_id": "gold_orb"
  }
}
```

字段说明：

| 字段路径 | 类型 | 单位 / 范围 | 说明 | 调大后的效果 |
|----------|------|-------------|------|--------------|
| `schema_version` | int | 必须为 `4` | 数据结构版本 | 只在 schema 变更时调整 |
| `body.radius` | float | `px`，`> 0`；当前 25.0 | 玩家视觉、圆形碰撞、`hit_radius()` 和有限地图边界内缩的统一半径 | 更大时玩家更易受击、近战更早接触，地图可移动范围也相应缩小 |
| `base_stats.max_hp` | float | `> 0` | 默认最大生命；当前默认 600.0，采用 Dota 式血量尺度而非旧心数尺度 | 更耐打，失败更晚，也更容易做细粒度伤害 / 回复调参 |
| `base_stats.health_regen` | float | HP/s，`>= 0` | 默认自动生命恢复；只在 `PLAYING` 状态下按 `GameClock` 缩放时间恢复，不超过最大生命 | 更能缓冲小额失误，但过高会抵消低频伤害 |
| `base_stats.move_speed` | float | `px/s`，`> 0` | 默认移动速度 | 走位更灵活，地图探索更快 |
| `base_stats.player_separation_radius` | float | `px`，`>= 0`；当前 25.0 | 玩家中心排斥半径；当前与 `body.radius` 一致，与敌人 `separation_radius` 相加后决定敌人被推开的最小中心距离 | 更不容易被敌人中心侵入身体，但过大可能让围怪显得松散 |
| `base_stats.fire_rate` | float | 每秒发数，`> 0` | 按住开火时的射击频率 | DPS 提升，弹幕更密 |
| `base_stats.damage` | float | `>= 0` | 单发基础伤害 | 击杀更快 |
| `base_stats.bullet_speed` | float | `px/s`，`> 0` | 子弹飞行速度 | 更容易命中远处移动敌人 |
| `base_stats.bullet_range` | float | `px`，`> 0` | 子弹最大射程 | 可打到更远敌人 |
| `base_stats.bullet_count` | int | `>= 1` | 每次开火基础子弹数 | 弹幕覆盖更宽 |
| `base_stats.pickup_range` | float | `px`，`>= 0` | 金币球 / 能量球自动吸附范围 | 收集更轻松 |
| `base_stats.luck` | float | `>= 0` | 保留幸运值；当前无玩法效果 | 为后续系统保留调参入口 |
| `defense.shield.recharge_delay` / `recharge_rate` | float | 秒 / Shield/s，`>= 0` | 护盾受损后等待时间与每秒恢复量 | 等待更长会削弱续航；恢复率更高会强化脱战恢复 |
| `defense.shield.overshield_decay_ratio_per_second` / `overshield_snap_threshold` | float | `0..1` / Shield，`>= 0` | 超额护盾每秒按最大护盾衰减比例，以及低于阈值时归零 | 衰减更高会缩短超额护盾收益 |
| `defense.armor.coefficient` / `maximum` | float | `> 0` | 护甲减伤曲线系数与参与公式的护甲上限 | 系数更高会降低同值护甲收益；上限更高允许更高护甲参与 |
| `defense.shield_gate.max_duration` | float | 秒，`>= 0` | 护盾击破时的最长保护窗口 | 更长会降低破盾后被多段瞬杀概率 |
| `dash.distance` / `speed` / `duration` | float | px / px/s / 秒，均 `> 0` | 冲刺运动参数；`distance` 必须等于 `speed × duration` | 更远 / 更快会提升位移能力 |
| `dash.cooldown` / `invulnerability_duration` | float | 秒，`>= 0`；无敌不超过 duration | 冲刺冷却与冲刺内无敌窗口 | 更短冷却或更长无敌会提高生存 |
| `energy_drop.chance` / `amount` | float | `0..1` / `> 0` | 敌人死亡生成能量球的概率与拾取量 | 提高技能资源供给 |
| `energy_drop.pickup_speed` | float | `px/s`，`> 0` | 能量球吸附速度；当前 360.0 | 更快靠近玩家 |
| `energy_drop.pool_id` / `rng_stream` | string | `energy_orb` / `drop`，必须已登记 | 能量球对象池与确定性掉落 RNG 子流 | 不作数值调节 |
| `gold_drop.pickup_speed` | float | `px/s`，`> 0` | 金币球吸附速度；当前 360.0 | 更快靠近玩家 |
| `gold_drop.pool_id` | string | 必须为登记过的 `gold_orb` | 金币球对象池；玩家归因击杀且锁定金币 `> 0` 时必掉一个 | 不作数值调节 |

## `camera_feedback.json`

当前结构：

```json
{
  "schema_version": 3,
  "aim_look": {
    "pointer_offset_ratio": 0.30,
    "max_offset_px": 240.0,
    "pointer_dead_zone_px": 32.0,
    "smoothing_time_seconds": 0.18
  },
  "player_damage_shake": {
    "amplitude": 8.0,
    "frequency": 20.0,
    "growth_time": 0.01,
    "duration": 0.08,
    "decay_time": 0.12,
    "positional_multiplier_x": 1.0,
    "positional_multiplier_y": 1.0
  },
  "weapon_recoil_shake": {
    "amplitude": 6.0,
    "amplitude_exponent": 0.75,
    "frequency": 30.0,
    "growth_time": 0.005,
    "duration": 0.02,
    "decay_time": 0.055,
    "positional_multiplier_x": 1.0,
    "positional_multiplier_y": 1.0
  }
}
```

| 字段路径 | 类型 | 单位 / 范围 | 说明 | 调大后的效果 |
|----------|------|-------------|------|--------------|
| `schema_version` | int | 当前必须为 `3` | 数据结构版本 | 只在 schema 变更时调整 |
| `aim_look.pointer_offset_ratio` | float | `0..1` | 鼠标越过死区后的屏幕距离换算为目标偏移的比例 | 光标移动相同距离时预看更远 |
| `aim_look.max_offset_px` | float | px，`>= 0` | 所有输入源的最大引导偏移；方向输入与 Replay 使用该最大值 | 可看到更远的瞄准方向 |
| `aim_look.pointer_dead_zone_px` | float | px，`>= 0` | 鼠标相对玩家实际屏幕位置的中心死区 | 中心附近更不容易触发镜头移动 |
| `aim_look.smoothing_time_seconds` | float | 秒，`> 0` | 指数平滑时间常数，`alpha = 1 - exp(-delta / value)` | 镜头跟随目标偏移更慢、更柔 |
| `player_damage_shake.amplitude` | float | px，`>= 0` | 有效玩家伤害的最大位移震幅 | 受击摇动更明显；过高会影响瞬时瞄准可读性 |
| `player_damage_shake.frequency` | float | Hz，`> 0` | 噪声采样频率 | 抖动更快、更硬 |
| `player_damage_shake.growth_time` | float | 秒，`> 0` | 从零增长到完整震幅的时间 | 起振更慢、更柔 |
| `player_damage_shake.duration` | float | 秒，`> 0` | 保持完整震幅的时间 | 强震动持续更久 |
| `player_damage_shake.decay_time` | float | 秒，`> 0` | 从完整震幅衰减到停止的时间 | 尾音更长 |
| `player_damage_shake.positional_multiplier_x` | float | `0..1` | 水平位移噪声倍率 | 水平摇动更强 |
| `player_damage_shake.positional_multiplier_y` | float | `0..1` | 垂直位移噪声倍率 | 垂直摇动更强 |
| `weapon_recoil_shake.amplitude` | float | px，`>= 0` | `recoil` 达到根级上限时的最大武器震屏振幅 | 后坐力震屏更明显 |
| `weapon_recoil_shake.amplitude_exponent` | float | `> 0` | 归一化后坐力映射为震幅比例时使用的指数；当前 `0.75` | 小于 `1` 会让低后坐力武器仍保留较清晰的震屏反馈 |
| `weapon_recoil_shake.frequency` | float | Hz，`> 0` | 武器后坐力震屏的噪声采样频率 | 抖动更快、更硬 |
| `weapon_recoil_shake.growth_time` | float | 秒，`> 0` | 单次开火震屏从零增长到目标震幅的时间 | 起振更慢、更柔 |
| `weapon_recoil_shake.duration` | float | 秒，`> 0` | 单次开火保持目标震幅的时间 | 强震动持续更久 |
| `weapon_recoil_shake.decay_time` | float | 秒，`> 0` | 单次开火震屏从目标震幅衰减到停止的时间 | 尾音更长 |
| `weapon_recoil_shake.positional_multiplier_x` | float | `0..1` | 水平位移噪声倍率 | 水平摇动更强 |
| `weapon_recoil_shake.positional_multiplier_y` | float | `0..1` | 垂直位移噪声倍率 | 垂直摇动更强 |

`aim_look` 在首次有效瞄准前保持零偏移。鼠标目标偏移为 `方向 × min((玩家实际屏幕位置到光标的距离 - pointer_dead_zone_px) × pointer_offset_ratio, max_offset_px)`；死区内为零。键盘、手柄与 Replay 使用归一化最终瞄准方向乘 `max_offset_px`，松开后保持最后方向。暂停冻结当前引导偏移，恢复后继续平滑。

`player_damage_shake` 只有在 `Combat.damage_applied` 报告玩家伤害实际应用时触发；敌人受伤或无敌窗拦截不触发。`weapon_recoil_shake` 由主武器成功开火触发，并按 `weapons.json` 的归一化 `recoil` 计算目标振幅。关闭 `gameplay.screen_shake` 时两种反馈都即时停止且只清理噪声 `Camera2D.offset`，不清理 `aim_look` 引导偏移；噪声 seed 走 `RNG.camera_fx`，是与 spawn / drop / combat 隔离的纯表现子流。

## 内容数据通用字段

角色、武器、敌人、遗物、道具等内容数据落地后，优先使用这些字段名，便于人和 AI 复用同一结构。

| 字段 | 类型 | 是否常见必填 | 说明 |
|------|------|--------------|------|
| `id` | string | 是 | 内容 id；必须来自对应词表或数据注册表 |
| `name_key` | string | 是 | 名称本地化 key，译文在 `client/locale/strings.csv` |
| `desc_key` | string | 视内容而定 | 描述本地化 key，译文在 `client/locale/strings.csv` |
| `tags` | array[string] | 视内容而定 | 内容标签；破限内容必须含 `tag_limit_break` |
| `capabilities` | array[string] | 视内容而定 | 允许突破的默认规则；id 来自词表 §12 |
| `availability` | object | 否 | 可用条件；需要限制模式时用 tags / 条件声明，由 `game_modes.json` 组合，不在代码写分支 |
| `base_stats` | object | 视内容而定 | 基础属性，字段来自词表 stat |
| `modifiers` | array[object] | 遗物常见 | 数值修正，格式见下节 |
| `behaviors` | array[object] | 行为内容常见 | 行为触发，格式见下节 |

## `difficulty_profiles.json`

当前 schema v2 结构：

```json
{
  "schema_version": 2,
  "profiles": [
    {
      "id": "difficulty_standard_survival",
      "name_key": "ui_difficulty_standard_name",
      "difficulty_coefficient": 1.0,
      "tier_interval_seconds": 90.0,
      "continuous_growth_per_interval": 0.04,
      "tier_step_growth": 0.09,
      "damage_growth_ratio": 0.48,
      "stage_name_keys": [
        "ui_difficulty_stage_dormant",
        "ui_difficulty_stage_alert",
        "ui_difficulty_stage_hunt",
        "ui_difficulty_stage_clash",
        "ui_difficulty_stage_siege",
        "ui_difficulty_stage_lethal",
        "ui_difficulty_stage_unbound",
        "ui_difficulty_stage_collapse",
        "ui_difficulty_stage_nestfall"
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 固定 `2` | 难度 profile 数据结构版本；旧 v1 明确拒绝 |
| `profiles` | array[object] | 非空 | 可被游戏模式引用的难度 profile 注册表 |
| `profiles[].id` | string | 非空、文件内唯一 | profile id；由 `game_modes.json.modes[].difficulty_profile_id` 引用 |
| `profiles[].name_key` | string | 必须存在于 locale | 玩家可见难度名称；当前为“标准 / Standard” |
| `profiles[].difficulty_coefficient` | number | 有限且 `> 0` | 玩家选择难度的总体系数；缩放威胁时间推进速度并进入敌人生成金币公式 |
| `profiles[].tier_interval_seconds` | number | `> 0` 且 `<= 3600` | 每个难度阶段的秒数 |
| `profiles[].continuous_growth_per_interval` | number | `0..10` | 每经过一个完整阶段时，连续部分对系数增加的数值 |
| `profiles[].tier_step_growth` | number | `0..10` | 跨过阶段线时额外增加的阶跃数值 |
| `profiles[].damage_growth_ratio` | number | `0..10` | 生命系数增量折算为敌人伤害增量的比例 |
| `profiles[].stage_name_keys` | array[string] | 恰好 9 项，且每项必须存在于 locale | Lv.1～Lv.9 的阶段名称；Lv.9 后沿用最后一项 |

`DifficultyProgression.advance(delta)` 实际推进 `delta × difficulty_coefficient`。标准模式系数为 `1.0`，因此既有公式仍为 `tier=floor(elapsed/tier_interval_seconds)`、`coefficient=1+continuous_growth_per_interval*(elapsed/tier_interval_seconds)+tier_step_growth*tier`、`health_multiplier=coefficient`、`damage_multiplier=1+damage_growth_ratio*(coefficient-1)`。曲线没有最终上限；这里不配置移速、攻击间隔、弹速、敌人数或刷新预算。难度系数另会进入下节敌人金币公式，但不会改变每个 profile 内的生命 / 伤害参数含义。

## `enemy_rewards.json`

当前 schema v1：

```json
{
  "schema_version": 1,
  "base_coefficient": 10.0,
  "time_growth_per_tier": 0.10,
  "random_multiplier_min": 0.9,
  "random_multiplier_max": 1.1
}
```

| 字段 | 类型 / 范围 | 说明 |
|------|-------------|------|
| `schema_version` | int，固定 `1` | 敌人金币公式数据版本 |
| `base_coefficient` | 有限 number，`> 0` | 所有敌人的金币基础系数；当前为 `10.0` |
| `time_growth_per_tier` | 有限 number，`>= 0` | 敌人实际生成时每个威胁阶段增加的奖励比例；当前每阶段 `+10%` |
| `random_multiplier_min` | 有限 number，`> 0` | `RNG.economy` 的生成时随机倍率下界；当前 `0.9` |
| `random_multiplier_max` | 有限 number，`>= random_multiplier_min` | `RNG.economy` 的生成时随机倍率上界；当前 `1.1` |

最终金币为：

```text
round(
  base_coefficient
  × difficulty_coefficient
  × enemies.csv.gold_value_multiplier
  × spawn_context.reward_specialization_multiplier
  × (1 + time_growth_per_tier × spawn_tier)
  × RNG.economy[random_multiplier_min, random_multiplier_max]
)
```

所有正式倍率都必须为有限正数；特殊化倍率缺省为 `1.0`。有效结果至少为 1，并在安全整数上限饱和。随机数只在成功取得敌人池实体、即将生成时抽一次；完整明细进入 Enemy / 当前 Run v11 快照，死亡、跨阶段、流式恢复或续局都不重算。环境击杀仍不掉金币；等级门槛、金币祭坛价格和世界事件固定金币奖励不读本文件。

## `game_modes.json`

当前结构：

```json
{
  "schema_version": 3,
  "modes": [
    {
      "id": "mode_standard_survival",
      "name_key": "ui_mode_standard_survival_name",
      "desc_key": "ui_mode_standard_survival_desc",
      "default_unlocked": true,
      "difficulty_profile_id": "difficulty_standard_survival",
      "participants": [
        { "id": "local_player", "kind": "player", "team_id": "team_player", "control": "local_player" }
      ],
      "teams": [
        { "id": "team_player", "friendly_fire": false },
        { "id": "team_enemy", "friendly_fire": false }
      ],
      "resource_pools": {
        "characters": [{ "id": "character_primary_a", "weight": 100 }],
        "weapons": [{ "id": "weapon_basic_blaster", "weight": 100 }],
        "enemies": [{ "id": "enemy_chaser", "weight": 100 }],
        "hazards": [
          { "id": "hazard_spike_trap", "weight": 100 },
          { "id": "hazard_fea_12_pulse", "weight": 100 }
        ],
        "relics": [{ "id": "relic_sharp_rounds", "weight": 100 }],
        "active_items": [{ "id": "active_item_blink_burst", "weight": 100 }],
        "skills": [
          { "id": "skill_overdrive_rounds", "weight": 100 }
        ],
        "consumables": [{ "id": "consumable_pocket_bomb", "weight": 100 }]
      },
      "blocklists": { "content_tags": [] },
      "overrides": { "player_base_stats": {} }
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 固定 `3` | 数据结构版本；旧 `resource_pools.growth_pools` 被明确拒绝 |
| `modes[].id` | string | 词表 §12-A game mode id，文件内唯一 | 游戏模式 id；代码引用走生成常量 |
| `modes[].name_key` / `desc_key` | string | `ui_*_name` / `ui_*_desc` | 模式名称和描述译文 key |
| `modes[].default_unlocked` | bool | true / false | 新存档中是否默认可用 |
| `modes[].difficulty_profile_id` | string | 必须存在于 `difficulty_profiles.json` | 本模式的局内威胁时间与新生成敌人倍率曲线 |
| `participants[].id` | string | 模式内唯一 | 参与者 id；当前单人样例为 `local_player` |
| `participants[].kind` | string | 非空 | 参与者类型；当前样例为 `player`，后续 AI / 远端玩家需先补 schema |
| `participants[].team_id` | string | 必须存在于 `teams[].id` | 参与者所属队伍 |
| `participants[].control` | string | 非空，可选 | 控制来源；当前样例为本地玩家输入 |
| `teams[].id` | string | 模式内唯一 | 队伍 id；供伤害、回放、存档和未来多人边界引用 |
| `teams[].friendly_fire` | bool | true / false | 队伍内是否允许友伤；当前只做 schema 预留 |
| `resource_pools.characters[]` | array[object] | 已声明时必须非空 | 本模式可用角色池 |
| `resource_pools.characters[].id` | string | 词表 §12.1 character id，且必须存在于 `characters.json` | 可用角色 id |
| `resource_pools.weapons[]` | array[object] | 已声明时必须非空 | 本模式可用武器池 |
| `resource_pools.weapons[].id` | string | 必须存在于 `weapons.json` | 可用武器 id |
| `resource_pools.enemies[]` | array[object] | 已声明时必须非空 | 本模式可用敌人池 |
| `resource_pools.enemies[].id` | string | 必须存在于 `enemies.csv` | 可用敌人 id |
| `resource_pools.hazards[]` | array[object] | 已声明时必须非空 | 本模式可用机关池 |
| `resource_pools.hazards[].id` | string | 必须存在于 `hazards.csv` | 可用机关 id |
| `resource_pools.relics[]` | array[object] | 已声明时必须非空 | 本模式可用遗物池 |
| `resource_pools.relics[].id` | string | 必须存在于 `relics.json` | 可用遗物 id |
| `resource_pools.active_items[]` | array[object] | 已声明时必须非空 | 本模式可用主动道具池 |
| `resource_pools.active_items[].id` | string | 必须存在于 `active_items.json` | 可用主动道具 id |
| `resource_pools.skills[]` | array[object] | 已声明时必须非空 | 本模式可用技能池；角色或道具仍通过 skill id 引用技能本体 |
| `resource_pools.skills[].id` | string | 词表 §12-C skill id，且必须存在于 `skills.json` | 可用技能 id |
| `resource_pools.consumables[]` | array[object] | 已声明时必须非空 | 本模式可用消耗品池 |
| `resource_pools.consumables[].id` | string | 必须存在于 `consumables.json` | 可用消耗品 id |
| `resource_pools.*[].weight` | int | `>= 0` | 抽取 / 展示权重；具体抽取由后续系统实现 |
| `blocklists.content_tags[]` | array[string] | 词表 §12.3 content tag | 禁用某类内容标签；当前样例为空 |
| `overrides.player_base_stats` | object | stat 来自词表 §1 | 轻量覆盖玩家基础属性；只用于模式差异，不复制角色本体 |

`game_modes.json` 只声明模式边界和 `difficulty_profile_id`，不实现模式选择 UI、匹配、联网、刷怪、奖励抽取、敌人生成、遗物抽取或实际战斗规则。地图尺寸、PCG 机关和人工摆点不写在模式资源池里，改 `map_layouts.json`。通用奖励池由发起请求的系统显式选择，不再挂在模式 `resource_pools` 下。新增资源池类型时，必须同步本文档、`DataLoader` schema、词表或对应数据注册表。

## `map_layouts.json`

当前结构：

```json
{
  "schema_version": 1,
  "layouts": [
    {
      "id": "map_standard_nest",
      "mode_id": "mode_standard_survival",
      "bounds": { "width": 4000.0, "height": 2000.0 },
      "grid": { "cell_width": 160.0, "cell_height": 80.0 },
      "player_start": { "x": -800.0, "y": 400.0 },
      "safe_radius": 320.0,
      "enemy_spawn_margin": 160.0,
      "pcg": {
        "hazards": [
          {
            "id": "hazard_fea_12_pulse",
            "count": 7,
            "min_distance_from_player": 480.0,
            "min_spacing": 320.0
          }
        ]
      },
      "manual_hazards": []
    }
  ]
}
```

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `schema_version` | int | 当前 `1` | 文件 schema 版本 |
| `layouts[].id` | string | 文件内唯一，非空 | 地图 layout id，用于诊断和 run 快照 |
| `layouts[].mode_id` | string | 必须存在于 `game_modes.json` | 该 layout 绑定的游戏模式；当前每个模式使用第一条匹配 layout |
| `bounds.width` / `bounds.height` | number | `> 0`，px；分别为 `grid.cell_width` / `grid.cell_height` 的整数倍 | 有限地图的轴对齐矩形范围；运行时以原点为中心生成可见 / 逻辑矩形边界 |
| `grid.cell_width` | number | `> 0`，px | 单个矩形格的水平宽度 |
| `grid.cell_height` | number | `> 0`，px | 单个矩形格的垂直高度 |
| `player_start.x` | number | 矩形格中心坐标 | 玩家出生点 X 坐标；运行时会吸附并 clamp 到地图边界 |
| `player_start.y` | number | 矩形格中心坐标 | 玩家出生点 Y 坐标；运行时会吸附并 clamp 到地图边界 |
| `safe_radius` | number | `>= 0`，px | PCG 机关距离出生点的最小安全距离下限；运行时可见提示画成按矩形格向外吸附的出生安全矩形，不再画正圆 |
| `enemy_spawn_margin` | number | `>= 0`，px | 刷怪位置距地图边缘的 clamp 边距 |
| `pcg.hazards[]` | array[object] | 可空 | 程序化机关规则；当前使用 `RNG.world` 按 seed 可复现地撒布，并按 `radius_tiles` 奇偶吸附到合法矩形格锚点 |
| `pcg.hazards[].id` | string | 必须存在于 `hazards.csv` | 要生成的机关 id |
| `pcg.hazards[].count` | int | `>= 0` | 目标生成数量；约束太紧时实际生成数量可能少于目标 |
| `pcg.hazards[].min_distance_from_player` | number | `>= 0`，px | 距玩家出生点的额外最小距离，会与 `safe_radius` 取较大值 |
| `pcg.hazards[].min_spacing` | number | `>= 0`，px | 与已放置机关之间的最小间距；同时至少避开双方格子半宽 / 半高推导出的近似半径 |
| `manual_hazards[]` | array[object] | 可空 | 人工固定摆点，先于 PCG 放置，PCG 会避开这些点 |
| `manual_hazards[].id` | string | 必须存在于 `hazards.csv` | 固定摆放的机关 id |
| `manual_hazards[].x` | number | 合法矩形格锚点坐标 | 固定机关世界 X 坐标；奇数 `radius_tiles` 校验为格心，偶数 `radius_tiles` 校验为网格顶点，运行时也会按同一规则吸附并 clamp |
| `manual_hazards[].y` | number | 合法矩形格锚点坐标 | 固定机关世界 Y 坐标；奇数 `radius_tiles` 校验为格心，偶数 `radius_tiles` 校验为网格顶点，运行时也会按同一规则吸附并 clamp |

调参建议：
- 需要改变地图大小或边界节奏时，先改 `bounds`，并保持宽高分别整除 `grid.cell_width/cell_height`，再跑 `runtime-smoke`；`perf-probe` 仅在用户明确要求性能测试时运行。
- 改格子尺度时优先成对调整 `grid.cell_width` / `grid.cell_height`，并保持 `bounds` 为格尺寸整数倍；当前默认一格为 `160 x 160` 的矩形 / 方形俯视格。
- 机关锚点按 `hazards.csv.radius_tiles` 奇偶决定：奇数尺寸中心在格心，偶数尺寸中心在网格顶点，这样机关外边缘才能贴住背景矩形格线。
- 需要测试特定机关交互时，用 `manual_hazards` 固定位置；需要测试 PCG 稳定性时改 `pcg.hazards[].count` / `min_spacing`。
- `hazards.csv` 只管机关基础数值和占格尺寸，`map_layouts.json` 才管初始地图上的机关位置。
- PCG 摆放使用 `RNG.world`，刷怪位置仍使用 `RNG.spawn`，不要把二者混用。
- F12 标准短刷图首片把 `player_start` 放在偏外侧格心，让玩家从边缘切入战区；兴趣点本身仍由 `warzone_directors.json.interest_points[]` 通过 `source="director"` 初始机关表达。

## `enemies.csv`

当前结构：

```csv
id,name_key,tags,pool_id,scene_path,pool_prewarm,ai_profile_id,presentation_profile_id,max_hp,move_speed,gold_value_multiplier,hit_radius,separation_radius
enemy_spitter,enemy_spitter_name,tag_enemy,enemy_spitter,res://scenes/gameplay/actors/enemies/enemy_spitter.tscn,12,enemy_ai_ranged_spitter,presentation_enemy_rifle,10,88.0,1.0,12.0,8.0
```

字段说明：

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `id` | string | 文件内唯一，非空 | 敌人 id；模式敌人池和后续刷怪表引用此 id |
| `name_key` | string | `enemy_*_name` | 敌人名称译文 key |
| `tags` | string | `|` 分隔的词表 §12.3 content tag，必须含 `tag_enemy` | 内容标签；可被模式 blocklist、刷怪规则或后续内容系统筛选 |
| `pool_id` | string | 词表 §8 pool id，文件内唯一且等于本行 `id` | 每个敌人独立对象池；禁止复用旧 `enemy_ranged` |
| `scene_path` | string | `res://scenes/gameplay/actors/enemies/*.tscn`，文件存在且为 `PackedScene` | 专属敌人继承场景；不同内容 id 可以引用同一场景，但不能指向 `enemy_base.tscn` |
| `pool_prewarm` | int | `>= 0` | 本敌人独立池的开局预热数量；突击枪手 / 爆猎者 / 群袭者 / 伏击者 / 壁垒者当前为 `12 / 6 / 4 / 3 / 3`，合计仍为 28 |
| `ai_profile_id` | string | 必须存在于 `enemy_ai_profiles.json` | 运行时使用的对玩家 AI profile；决定动作集合与行为参数 |
| `presentation_profile_id` | string | 必须存在于 `presentation_profiles.json` | 敌人语义表现 profile；显式攻击前摇和提交通过 cue 解析 |
| `max_hp` | int | `>= 1` | 敌人最大生命 |
| `move_speed` | number | `> 0`，px/s | 敌人基础移动速度 |
| `gold_value_multiplier` | number | 有限且 `> 0` | 怪物相对金币价值；爆猎者 / 群袭者 / 伏击者 / 壁垒者 / 突击枪手依次为 `1 / 0.6666667 / 1.6666667 / 2 / 1`。标准难度第 0 阶段随机区间约为 `9–11 / 6–7 / 15–18 / 18–22 / 9–11` |
| `hit_radius` | number | `> 0`，px | 实体命中半径；冲撞扫掠会与玩家命中半径相加 |
| `separation_radius` | number | `>= 0`，px | 敌人中心排斥半径；小于 `hit_radius` 时允许视觉重叠但避免中心完全重合 |

`enemies.csv` 不再携带任何通用接触伤害字段。敌人身体重叠、推挤和中心分离只影响位置，永远不直接造成伤害；爆炸、近战、冲撞和远程投射物必须由 `enemy_ai_profiles.json.actions[].attack` 显式定义并走 `Combat.apply_damage()`。`team_enemy` 默认仍被拒绝，只有已提交的爆猎者爆炸可对敌人结算。

## `enemy_ai_profiles.json`

当前结构：

```json
{
  "schema_version": 5,
  "profiles": [
    {
      "id": "enemy_ai_charge_stalker",
      "perception": {
        "sight_radius": 820.0,
        "path_awareness_radius": 530.0,
        "memory_duration": 1.5
      },
      "decision_interval": 0.12,
      "targeting": {
        "player_weight": 0.55,
        "territory_radius": 0.0,
        "territory_weight": 0.0
      },
      "movement": {
        "orbit_radius": 190.0
      },
      "actions": [
        {
          "id": "ai_action_charge_target",
          "base_score": 0.95,
          "speed_scale": 1.0,
          "attack": {
            "trigger_range": 320.0,
            "windup": 0.34,
            "release_duration": 0.42,
            "cooldown": 1.4,
            "damage": 160.0,
            "element_id": "element_neutral",
            "speed_multiplier": 2.65,
            "stop_on_hit": false,
            "knockback_distance": 0.0,
            "knockback_duration": 0.0
          }
        },
        { "id": "ai_action_approach_target", "base_score": 0.65, "speed_scale": 1.05 }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `5` | 数据结构版本；旧接触字段、`sense_radius` 和旧 `movement` 攻击字段会被双端 schema 明确拒绝 |
| `profiles[].id` | string | 文件内唯一，非空 | AI profile id；由 `enemies.csv.ai_profile_id` 引用 |
| `profiles[].perception.sight_radius` | number | `> 0`，px | 地形视线畅通时的玩家视觉感知半径；首版为 360° 视野 |
| `profiles[].perception.path_awareness_radius` | number | `>= 0` 且不大于 `sight_radius`，px | 隔墙但路径可达时，按共享流场路径距离感知玩家的半径 |
| `profiles[].perception.memory_duration` | number | `>= 0`，秒 | 失去当前感知后，只追踪最后已知位置的持续时间 |
| `profiles[].decision_interval` | number | `> 0`，秒 | 重新计算 Utility 分数的间隔 |
| `targeting.player_weight` | number | `>= 0` | 玩家目标的评分权重；玩家是唯一战斗候选 |
| `targeting.territory_radius` | number | `>= 0`，px | 离出生点超过该距离时，守家动作会加分 |
| `targeting.territory_weight` | number | `>= 0` | 超出领地半径后的回家倾向权重 |
| `movement.orbit_radius` | number | `>= 0`，px | 环绕目标的期望半径 |
| `actions[]` | array[object] | 至少 1 个 | 此 profile 可参与评分的动作列表 |
| `actions[].id` | string | 词表 §12-B enemy AI action | 动作 id；运行时通过生成常量解释 |
| `actions[].base_score` | number | `>= 0` | 动作基础分；越高越容易选中 |
| `actions[].speed_scale` | number | `> 0` | 执行该动作时的移动速度倍率 |
| `actions[].attack` | object | 攻击 action 必填；非攻击 action 禁止 | 显式攻击参数；按 action 类型使用精确字段集合 |
| `actions[].attack.trigger_range` | number | `> 0`，px | 爆炸、近战或冲撞进入评分的最大距离 |
| `actions[].attack.windup` | number | `> 0`，秒 | 攻击前摇；爆猎者进入此前摇后即不可逆 |
| `actions[].attack.release_duration` | number | `> 0`，秒；仅冲撞 | 冲撞释放持续时间 |
| `actions[].attack.cooldown` | number | `> 0`，秒 | 近战、冲撞或远程攻击冷却 |
| `actions[].attack.damage` | number | `> 0` | 基础伤害；仅该值受生成时难度伤害倍率缩放 |
| `actions[].attack.element_id` | string | 词表 §9 element id | 显式攻击伤害元素 |
| `actions[].attack.radius` | number | `> 0`，px；仅爆炸 | 爆炸半径，无距离衰减 |
| `actions[].attack.range` | number | `> 0`，px；仅近战 | 方向扇区半径 |
| `actions[].attack.arc_degrees` | number | `0 < value <= 360`；仅近战 | 锁定方向的扇区夹角 |
| `actions[].attack.speed_multiplier` | number | `> 0`；仅冲撞 | 冲撞释放阶段速度倍率 |
| `actions[].attack.stop_on_hit` | bool | `true` / `false`；仅冲撞 | 命中后是否立即结束冲撞 |
| `actions[].attack.knockback_distance` | number | `>= 0`，px；仅冲撞 | 玩家敌人击退距离；与时长同时为零或同时为正 |
| `actions[].attack.knockback_duration` | number | `>= 0`，秒；仅冲撞 | 玩家敌人击退时长 |
| `actions[].attack.attack_range` | number | `> 0`，px；仅远程 | 远程攻击可发射的最大距离 |
| `actions[].attack.keep_distance` | number | `>= 0`，px；仅远程 | 低于该距离时尝试后撤 |
| `actions[].attack.burst_count` | int | `>= 1`；仅远程 | 每轮锁向点射的固定弹数；不受难度缩放 |
| `actions[].attack.shot_interval` | number | `> 0`，秒；仅远程 | 同轮点射相邻两发的固定间隔；不受难度缩放 |
| `actions[].attack.initial_cooldown` | number | `>= 0`，秒；仅远程 | 生成后的首次开火延迟 |
| `actions[].attack.projectile.pool_id` | string | 词表 §8 pool id | 远程投射物对象池 |
| `actions[].attack.projectile.speed` | number | `> 0`，px/s | 投射物速度 |
| `actions[].attack.projectile.range` | number | `> 0`，px | 投射物最大射程 |
| `actions[].attack.projectile.hit_radius` | number | `> 0`，px | 投射物命中半径 |
| `actions[].attack.projectile.lifetime` | number | `> 0`，秒 | 投射物最大存活时间 |
| `actions[].attack.projectile.muzzle_distance` | number | `>= 0`，px | 投射物从敌人中心的发射偏移 |

当前动作：

| action id | 行为 |
|-----------|------|
| `ai_action_approach_target` | 接近玩家，不造成伤害 |
| `ai_action_orbit_target` | 在目标附近绕行，预留给远程 / 试探型敌人 |
| `ai_action_explode_target` | 有地形视线时进入不可逆爆炸前摇，并按稳定生成序结算玩家和其他敌人 |
| `ai_action_melee_attack` | 锁定前摇方向，提交时结算前方扇区 |
| `ai_action_charge_target` | 锁定方向后进入前摇和线段扫掠冲撞，每次释放最多命中一次 |
| `ai_action_guard_home` | 离出生点太远时返回领地 |
| `ai_action_ranged_attack` | 保持距离；起手需要视线，锁向预警后沿固定方向完成整轮池化投射物点射 |

调参建议：先改 `base_score`，再改 `attack` 的距离 / 时间；远程敌人优先调 `cooldown`、`projectile.speed` 和 `keep_distance`。大幅改变稳定行为后需要重录并重跑四条 golden replay；性能测试仅在用户明确要求时运行。新增 action 必须先登记 `docs/词表与契约.md` §12-B，再同步生成常量、schema、`docs/代码/enemy_ai.md` 和测试。

## `hazards.csv`

当前结构：

```csv
id,name_key,tags,pool_id,damage,element_id,trigger_interval,radius_tiles,duration
hazard_spike_trap,hazard_spike_trap_name,tag_hazard,hazard_spike,100,element_neutral,1.0,1,0.35
```

字段说明：

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `id` | string | 文件内唯一，非空 | 机关 id；模式机关池和后续地图 / 波次表引用此 id |
| `name_key` | string | `hazard_*_name` | 机关名称译文 key |
| `tags` | string | `|` 分隔的词表 §12.3 content tag，必须含 `tag_hazard` | 内容标签；可被模式 blocklist、地图规则或后续内容系统筛选 |
| `pool_id` | string | 词表 §8 pool id | 运行时使用的机关对象池；当前 `hazard_spike` 复用通用 `Hazard` 场景 |
| `damage` | int | `>= 0` | 单次触发伤害；运行时必须经 `Combat.apply_damage` 结算 |
| `element_id` | string | 词表 §9 element id | 机关伤害元素 |
| `trigger_interval` | number | `> 0`，秒 | 持续存在机关的触发间隔 |
| `radius_tiles` | int | `>= 1` | 机关矩形 footprint 从中心到边缘占用的半格数；最终半宽 / 半高由 `map_layouts.json.grid` 推导，视觉矩形和触发判定都据此生成；奇数尺寸中心吸附格心，偶数尺寸中心吸附网格顶点 |
| `duration` | number | `>= 0`，秒 | 单次触发后的激活 / 预警表现时长 |

`hazards.csv` 只声明机关基础数值和占格尺寸。当前运行时已有通用 `Hazard` 节点：由 `MapManager` 读取 `map_layouts.json` 的 PCG / 人工摆点，经 `PoolManager` 取节点，在玩家进入矩形触发范围且冷却结束时通过 `Combat.apply_damage()` 结算。游戏模式仍通过 `resource_pools.hazards` 声明可用机关池；实际初始位置和格子尺度改 `map_layouts.json`。

## `spawn_waves.csv`

当前结构：

```csv
id,mode_id,wave_index,start_time,end_time,enemy_id,enemy_weight,spawn_interval,max_alive,spawn_budget,hazard_id,hazard_weight
wave_standard_early_chasers,mode_standard_survival,1,0.0,9999.0,enemy_chaser,55,1.8,9,9999,,0
wave_standard_swarm_mix,mode_standard_survival,2,60.0,9999.0,enemy_swarm,30,2.6,6,9999,,0
wave_standard_stalkers,mode_standard_survival,3,240.0,9999.0,enemy_stalker,15,5.2,3,9999,,0
wave_standard_ranged_spitters,mode_standard_survival,4,0.0,9999.0,enemy_spitter,100,1.35,16,9999,,0
wave_standard_mid_bulwarks,mode_standard_survival,5,420.0,9999.0,enemy_bulwark,20,5.0,3,9999,,0
```

字段说明：

| 字段 | 类型 | 合法值 / 范围 | 说明 |
|------|------|---------------|------|
| `id` | string | 文件内唯一，非空 | 波次条目 id；用于诊断、调试和未来回放记录 |
| `mode_id` | string | 词表 §12-A game mode id，且必须存在于 `game_modes.json` | 该波次所属游戏模式 |
| `wave_index` | int | `>= 1`，同一 `mode_id` 内唯一 | 波次序号；用于 UI / analytics / 存档快照中的当前波次 |
| `start_time` | number | `>= 0`，秒 | 本波次开始时间，按 `GameClock` 局内时间解释 |
| `end_time` | number | `> start_time`，秒 | 本波次结束时间；后续 Spawner 可据此选择当前波次 |
| `enemy_id` | string | 必须存在于 `enemies.csv` | 本波次主要敌人 id |
| `enemy_weight` | int | `>= 1` | 本波次敌人抽取权重；当前黄金样例只有一个敌人 |
| `spawn_interval` | number | `> 0`，秒 | 基础刷怪间隔；后续 Spawner 必须经 `GameClock` 解释 |
| `max_alive` | int | `>= 1` | 本波次同时存活敌人软上限 |
| `spawn_budget` | int | `>= 0` | 本波次预算；后续可按敌人成本或数量消耗 |
| `hazard_id` | string | 可空；非空时必须存在于 `hazards.csv` | 可选机关 id，用于把机关生成作为波次压力的一部分 |
| `hazard_weight` | int | `>= 0`；大于 0 时 `hazard_id` 必填 | 可选机关权重；`0` 表示本波次不使用机关 |

`spawn_waves.csv` 只声明刷怪 / 难度曲线数据边界；当前初始地图机关由 `map_layouts.json` 管理，波次中的 `hazard_id` / `hazard_weight` 仍是后续“把机关作为时间压力”时的预留字段。F12 标准短刷图从 0:00 起同时开放爆猎者与突击枪手，随后于 1:00 / 4:00 / 7:00 打开其余敌群层级；突击枪手以 `1.35s` 间隔和 `16` 上限承担最常见的基础远程压力，其余波次已等量下调，使总生成速率基本不变。`9999.0` 是软上限后的持续压力窗口，不是硬性局长限制。实际刷怪随机必须走 `RNG.spawn`，局内时间必须走 `GameClock`，高频实体必须走 `PoolManager`。

## `warzone_directors.json`

当前结构：

```json
{
  "schema_version": 2,
  "directors": [
    {
      "id": "director_standard_warzone",
      "mode_id": "mode_standard_survival",
      "mutation_id": "nest_mutation_hunting_ground",
      "description": "Standard short loot-run director. It targets an 8-12 minute clear, uses fixed phases, and never reads player-state pressure.",
      "phases": [
        {
          "id": "phase_insertion",
          "start_time": 0.0,
          "end_time": 60.0,
          "pressure_tag": "warmup",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_ranged_spitters"]
        },
        {
          "id": "phase_first_reward_node",
          "start_time": 60.0,
          "end_time": 240.0,
          "pressure_tag": "pressure",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_swarm_mix", "wave_standard_ranged_spitters"]
        },
        {
          "id": "phase_route_pressure",
          "start_time": 240.0,
          "end_time": 420.0,
          "pressure_tag": "route_pressure",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_swarm_mix", "wave_standard_stalkers", "wave_standard_ranged_spitters"]
        },
        {
          "id": "phase_minor_nest_core",
          "start_time": 420.0,
          "end_time": 540.0,
          "pressure_tag": "core",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_swarm_mix", "wave_standard_stalkers", "wave_standard_ranged_spitters", "wave_standard_mid_bulwarks"]
        },
        {
          "id": "phase_overtime_collapse",
          "start_time": 540.0,
          "end_time": 9999.0,
          "pressure_tag": "overtime",
          "wave_ids": ["wave_standard_early_chasers", "wave_standard_swarm_mix", "wave_standard_stalkers", "wave_standard_ranged_spitters", "wave_standard_mid_bulwarks"]
        }
      ],
      "interest_points": [
        {
          "id": "poi_elite_nest",
          "kind": "elite_nest",
          "hazard_ids": ["hazard_fea_12_pulse", "hazard_spike_trap"],
          "map_layout_id": "map_standard_nest",
          "claim_radius": 190.0,
          "claim_start_time": 60.0,
          "target_hp": 120.0,
          "target_hit_radius": 36.0,
          "resource_rewards": [{"resource_id": "gear_mod_dust", "amount": 25}]
        },
        {
          "id": "poi_mod_cache",
          "kind": "mod_cache",
          "hazard_ids": ["hazard_fea_12_pulse"],
          "map_layout_id": "map_standard_nest"
        },
        {
          "id": "poi_resource_cache",
          "kind": "resource_cache",
          "hazard_ids": ["hazard_spike_trap"],
          "map_layout_id": "map_standard_nest"
        },
        {
          "id": "poi_minor_nest_core",
          "kind": "minor_nest_core",
          "hazard_ids": ["hazard_fea_12_pulse", "hazard_spike_trap"],
          "map_layout_id": "map_standard_nest"
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `2` | 数据结构版本；旧导演敌人组合元数据会被双端 schema 明确拒绝 |
| `directors[]` | array[object] | 非空 | 战区导演列表；首片每个模式只允许一个导演 |
| `directors[].id` | string | 文件内唯一，非空 | 导演 id；只用于调试、验证和后续工具 |
| `directors[].mode_id` | string | 必须存在于 `game_modes.json`，且来自词表 §12-A | 该导演绑定的游戏模式 |
| `directors[].mutation_id` | string | 非空 | 巢变异 / 战区主题 id；首片不玩家可见，因此不进 locale / 词表 |
| `directors[].description` | string | 可选，非空 | 开发者说明；不玩家可见 |
| `directors[].phases[]` | array[object] | 非空、按时间升序、不重叠 | 固定节奏阶段；首片用时间而不是玩家状态推进 |
| `phases[].id` | string | 同 director 内唯一，非空 | 阶段 id |
| `phases[].start_time` | number | `>= 0`，秒 | 阶段开始时间，按 `GameClock` 局内时间解释 |
| `phases[].end_time` | number | `> start_time`，秒 | 阶段结束时间；除最后阶段终点包含外，其余阶段终点不包含 |
| `phases[].pressure_tag` | string | 非空 | 调试 / 平衡用节奏标签，不玩家可见 |
| `phases[].wave_ids[]` | array[string] | 非空；必须引用同模式 `spawn_waves.csv` | 当前阶段允许的刷怪 wave；同模式所有 wave 必须至少被一个阶段引用 |
| `directors[].interest_points[]` | array[object] | 非空 | 战区兴趣点 / 机关组合声明；匹配当前 layout 时进入初始地图机关生成 |
| `interest_points[].id` | string | 同 director 内唯一，非空 | 兴趣点 id |
| `interest_points[].kind` | string | 非空 | 兴趣点类型；F12 首片为 `elite_nest` / `mod_cache` / `resource_cache` / `minor_nest_core` 等调试语义 |
| `interest_points[].hazard_ids[]` | array[string] | 非空；每项必须存在于 `hazards.csv` | 兴趣点关联机关；每个 id 会生成一个 `source="director"` placement |
| `interest_points[].map_layout_id` | string | 可选；非空时必须存在于 `map_layouts.json` | 兴趣点所属地图 layout |
| `interest_points[].min_distance_from_player` | number | 可选，`>= 0`，px | 运行时摆放时距玩家出生点的额外最小距离；会与 layout `safe_radius` 取较大值 |
| `interest_points[].min_spacing` | number | 可选，`>= 0`，px | 与已放置机关之间的最小间距；用于把收益点分散到小而密的路线中 |
| `interest_points[].claim_radius` | number | 可选；有奖励或 `completes_run=true` 时必填且 `> 0`，px | 无目标兴趣点中，玩家进入该半径后可领取 / 交互一次兴趣点奖励；有目标兴趣点由目标摧毁触发领取 |
| `interest_points[].extraction_radius` | number | 可选；`completes_run=true` 时必填且 `> 0`，px | 小巢核领取后开启撤离区的基础半径；运行时会吸附为贴合 `map_layouts.json.grid` 的矩形范围 |
| `interest_points[].extraction_hold_time` | number | 可选；`completes_run=true` 时必填且 `> 0`，秒 | 玩家站在撤离区内需要保持的结算读条时间；离开撤离区会重置首版读条进度 |
| `interest_points[].claim_start_time` | number | 可选，`>= 0`，秒 | 奖励最早可领取时间；使用 `GameClock.now()`，不读取玩家状态 |
| `interest_points[].requires_interaction` | bool | 可选 | 为 `true` 时不会进圈自动领取；运行时生成可见缓存箱，玩家进入 `claim_radius` 后按 `interact` action 打开并把奖励放入 `run.pending_loot` |
| `interest_points[].target_hp` | number | 可选，`> 0` | 有值时 `GameplayRunLoop` 会生成可被子弹命中的 `InterestPointTarget`，摧毁后触发同一套奖励；目标生成后立即可受伤，无值时仍按进圈领取 |
| `interest_points[].target_hit_radius` | number | 可选，`> 0`，px | 可伤害目标的命中半径；只在 `target_hp` 存在时使用，视觉 footprint 会向上吸附到地图矩形格整数尺寸 |
| `interest_points[].resource_rewards[]` | array[object] | 可选，非空；`resource_id` 必须来自 `gear_mod_resources`，`amount >= 1` | 领取时先进入 `run.pending_loot.resources`；撤离成功时才通过 `GearModSystem.grant_resource()` 写入 `meta.gear_mods.resources` |
| `resource_rewards[].resource_id` | string | 必须存在于 `gear_mod_resources` | 当前首片使用 `gear_mod_dust` |
| `resource_rewards[].amount` | int | `>= 1` | 发放资源数量 |
| `interest_points[].gear_mod_rewards[]` | array[object] | 可选，非空；`mod_id` 必须存在于 `gear_mods.json`，`count >= 1` | 领取时先进入 `run.pending_loot.gear_mods`；撤离成功时才通过 `GearModSystem.grant_mod()` 写入库存 |
| `gear_mod_rewards[].mod_id` | string | 必须存在于 `gear_mods.json` 且来自 `gear_mod_ids` | 当前首片使用测试武器 Mod |
| `gear_mod_rewards[].count` | int | `>= 1` | 发放 Mod 实例数量 |
| `interest_points[].completes_run` | bool | 可选 | 为 `true` 时领取后开启撤离区；撤离读条完成才删除当前 `run` 存档、提交暂存战利品并显示完成结果面板；首片用于小巢核 |
| `interest_points[].notes` | string | 可选，非空 | 开发者说明；不玩家可见 |

`warzone_directors.json` 是 F10/F12 敌巢战区导演数据源。运行时使用 `phases[].wave_ids` 给 `GameplayRunLoop` 的 Spawner 做阶段 gating；刷怪本身仍由 `spawn_waves.csv` 的时间窗、间隔、预算和同时存活上限决定。F12 标准局按 0-1 分钟投放、1-4 分钟第一收益点、4-7 分钟路线压力、7-9 分钟小巢核、9 分钟后软加压组织；`phase_overtime_collapse` 只表达继续贪局时的高压段，不是硬性强制结束。匹配当前 `map_layout_id` 的 `interest_points[]` 会交给 `MapManager`；有 `target_hp` 的兴趣点先生成独立的格心 target anchor，再把 `hazard_ids[]` 机关放到目标附近并避开该 footprint；无目标兴趣点仍为每个 `hazard_ids[]` 用既有 PCG / 锚点 / 边界规则生成一个初始 `source="director"` placement，并把兴趣点奖励元数据透传给 `GameplayRunLoop`。无 `target_hp` 且无 `requires_interaction` 的兴趣点在玩家进入 `claim_radius` 且达到 `claim_start_time` 后领取；有 `requires_interaction=true` 的兴趣点会生成可见缓存箱，玩家进入半径后按 `interact` action 打开；有 `target_hp` 的兴趣点会生成可伤害目标，目标生成后即可被子弹 / Combat 伤害摧毁，摧毁后按通用 `resource_rewards[]` / `gear_mod_rewards[]` 放入 `run.pending_loot` 暂存；`completes_run=true` 的小巢核领取后只开启撤离区，玩家进入贴合地图矩形格的撤离矩形并完成 `extraction_hold_time` 读条后，才提交暂存战利品、删除当前 `run` 存档并显示完成结果面板。领取状态、目标状态、撤离状态和暂存战利品保存到 run payload，旧存档缺失时按未领取 / 未开启撤离 / 无暂存处理。导演不能读取玩家生命、DPS、受伤次数、输入频率或其它玩家状态；后续若增加随机 mutation、玩家可见主题或更复杂奖励语义，必须先同步 `docs/代码/warzone_director.md`、GDD、ADR、DataLoader schema 和对应 smoke / replay 策略。

## `world_events.json`

`world_events.json` schema v1 是五类世界事件和事件 Gear Mod 奖励池的唯一数值源。根级 `mod_pools[]` 必须完整覆盖 `world_event_mod_pool_ids`；每个池只引用已存在的 `gear_mod_ids`，池内不得重复。`events[]` 必须完整覆盖五个 `world_event_ids` 与五个 `world_event_kinds`，事件对象按 kind 使用严格字段集，不允许多余字段。

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `1` | 世界事件数据 schema |
| `mod_pools[].id` | string | `world_event_mod_pool_ids`，唯一且完整覆盖 | 事件奖励 Gear Mod 池 |
| `mod_pools[].mod_ids` | array[string] | 已存在的 `gear_mod_ids`，非空且不重复 | 当前普通池等权包含三个普通武器 Mod |
| `events[].id` / `events[].kind` | string | 分别完整覆盖 `world_event_ids` / `world_event_kinds` | 稳定事件 id 与严格类型 |
| `events[].name_key` / `desc_key` | string | 已存在的 `world_event_` locale key | 玩家可见名称与描述 |
| `events[].interaction_radius` | number | `> 0` | `interact` 可用距离，单位 px |
| `duration` / `capture_duration` / `timeout` | number | `> 0` | 持续事件与占点时长 |
| `waves[].trigger` / `count` | number / int | 首项 trigger 为 `0`，非递减且不超过事件时长；count `>= 1` | 激活时据此生成固定波次计划 |
| `target_max_health` / `target_hit_radius` | number | 防御类型必填且 `> 0` | 防御目标生命与受击半径 |
| `capture_radius` / `entry_delay` / `entry_delay_decay` | number | 占点类型必填且 `> 0` | 实际区域、启动延迟与离区反向衰减速率 |
| `completion_reward.gold_weight` / `mod_weight` | int | 均 `>= 1` | 持续事件隐藏固定奖励的相对权重 |
| `completion_reward.gold_amount` | int | `>= 1` | 对应事件的即时金币奖励 |
| `completion_reward.mod_pool_id` / `mod_pool_id` | string | 根级已定义的事件 Mod 池 | 完成奖励或金币祭坛的 Gear Mod 候选 |
| `base_cost` / `cost_multiplier` | int / number | `base_cost >= 1`、倍率 `> 1` | 金币祭坛递增价格 |
| `success_chance` | number | `0 < value < 1` | 金币祭坛每次独立成功率 |
| `max_successes` | int | `>= 1` | 金币祭坛成功耗尽次数 |
| `sacrifice_ratios[]` | array[number] | 恰好 3 个、严格递增且均在 `(0,1)` | 血量祭坛三次组合生命献祭比例 |
| `gold_ratio` | number | `(0,1)` | 实际献祭值到即时金币的换算比例 |

事件波次、隐藏奖励与祭坛判定使用独立 `RNG.world_event`，不得消费模块 assignment 的 `RNG.world` 或敌人普通生成流。

## `module_worlds.json` / `module_templates.json` / `module_tile_catalog.json` / `modules/*.json`

F13 的正式默认地图是 9×9 无缝模块世界；每模块固定 11×11 格，默认单格 160 px。`module_worlds.json` 定义世界几何、键槽、批准模板池、安全回退布局和中心 3×3 技术首片；`module_templates.json` 是审核门禁注册表；`modules/*.json` 是布局与表现的唯一制作主源。Godot Module JSON Editor 只读写 JSON，不修改模块场景；baker 为每模块单向生成唯一的 `scenes/generated/modules/<id>/rotation_0.tscn`，生成场景禁止手改。allowed rotations 只限制世界 assignment，运行时由 `ModuleChunk` 旋转规范场景根节点，不生成方向副本。

每个模块 JSON 必须包含恰好 11 行、每行 11 个 `module_cell_tokens`；四边 socket 由边缘 floor 自动推导，不在 schema v4 中重复存储。相邻非封锁模块旋转后的边缘开放格交集必须非空，不再要求整条 socket 完全一致；世界外圈仍不得越界开放。模块只允许 0/90/180/270° 世界旋转；单个视觉格允许使用同样的旋转和水平/垂直翻转。模块 placement 不包含敌人出生点，旧 `module_place_enemy_spawn` 会被 DataLoader、Python 校验器、编辑器与 baker 明确拒绝。世界事件模块使用 `module_place_world_event`，payload 严格只有 `world_event_id`。

ADR #164 后，正式 `template_pool` 只包含 0° 的 `module_flat_ground`；除三个固定槽外，`fallback_assignment` 也全部使用平地。平地 121 格都是 floor 且没有 gameplay placement。既有模块仍保留文件、生成场景和技术首片用途，但暂不进入普通正式随机池。固定起点不触发首次进入遭遇；固定目标和撤离槽与普通非起点槽使用同一套空地刷怪规则。

AI 产出新模块时必须先创建或修改模块 JSON 并登记为 `candidate`。通过 bake、schema、图块、通道、全局可达性、安全区和内容预算校验后，仍需在中央主编辑区中显式批准。玩法或注册策略变化会降回 candidate；纯视觉变化保持审核状态但必须重新烘焙。默认模板池只能引用 `approved`；模板复用时，运行状态按世界槽位保存，不按模板 id 共享。完整编辑、命令和发布规则见 `docs/代码/module_authoring_pipeline.md`。

`modules/*.json` schema v4 字段：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `4` | 模块制作 schema；新增严格世界事件 placement |
| `id` | string | 与注册表 id、文件名一致 | 稳定模块 id |
| `columns` / `rows` | int | 首版固定 `11` | 模块格尺寸 |
| `terrain_rows[y][x]` | string | `module_cell_tokens` | 11×11 玩法地形；edge socket 由边缘 floor 派生 |
| `placements[]` | object | type、整数 `cell`、可选 `footprint` 与类型专属 payload | 内容摆放；完整 footprint 必须落在 floor |
| `placements[].world_event_id` | string | `module_place_world_event` 时必填，来自 `world_event_ids` | 世界事件 placement 不允许 footprint 或其它多余字段 |
| `visual_layers.ground.default_tile_id` / `visual_layers.obstacles.default_tile_id` | string | 对应层的稳定 tile id | 该玩法层非空格的默认视觉 |
| `visual_layers.ground.overrides[]` / `visual_layers.obstacles.overrides[]` | object | cell、tile_id、rotation、flip_h、flip_v | 稀疏按格覆盖 |
| `visual_layers.decoration.cells[]` | object | cell、tile_id、rotation、flip_h、flip_v | 不改变玩法地形的稀疏装饰 |

`module_tile_catalog.json` 字段：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `1` | 图块目录 schema |
| `tile_set_path` | string | 已存在的 `res://resources/modules/*.tres` | baker 与 Dock 共用的 TileSet |
| `tiles[].id` | string | 词表 §15-F，唯一且覆盖全部 module tile id | 模块 JSON 使用的稳定图块 id |
| `tiles[].layer` | string | `ground` / `obstacles` / `decoration` | 图块允许出现的视觉层 |
| `tiles[].source_id` | int | `>= 0` | Godot TileSet source id，仅目录维护 |
| `tiles[].atlas_coords.x` / `tiles[].atlas_coords.y` | int | `>= 0` | TileSet atlas 坐标，仅目录维护 |
| `tiles[].alternative_id` | int | `0..4095` | Godot alternative tile id；高位保留给 Godot 变换标志 |

`module_worlds.json` 字段：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `3` | 增加限量模板组 |
| `worlds[].id` | string | 唯一、非空 | 世界 id；Run v9 的 `module_world` 子快照保存此值 |
| `worlds[].columns` / `worlds[].rows` | int | 首版固定 `9` | 模块槽位宽高 |
| `worlds[].module_columns` / `worlds[].module_rows` | int | 首版固定 `11` | 单模块局部格宽高 |
| `worlds[].cell_size` | int | `> 0`，默认 `160` | 同一世界统一的方格边长，单位 px |
| `worlds[].active_radius` | int | 首版固定 `1` | 当前模块向四周激活的半径；最多 3×3 chunk |
| `worlds[].seal_outer_edges` | bool | 首版必须 `true` | 外圈有效通道不得朝地图外开放 |
| `worlds[].start_slot.x` / `worlds[].start_slot.y` | int | `0..8`，固定 `(4,4)` | 起点模块槽位 |
| `worlds[].objective_slot.x` / `worlds[].objective_slot.y` | int | `0..8` | 目标模块固定槽位 |
| `worlds[].extraction_slot.x` / `worlds[].extraction_slot.y` | int | `0..8` | 撤离模块固定槽位 |
| `worlds[].route_budget.start_to_objective.min_crossings` / `worlds[].route_budget.start_to_objective.max_crossings` | int | `4..6` | 起点到目标的模块跨越预算 |
| `worlds[].route_budget.objective_to_extraction.min_crossings` / `worlds[].route_budget.objective_to_extraction.max_crossings` | int | `3..5` | 目标到撤离的模块跨越预算 |
| `worlds[].route_budget.main_route_modules.min` / `worlds[].route_budget.main_route_modules.max` | int | `8..12` | 主路线模块数预算 |
| `worlds[].route_budget.optional_exploration_modules.max` | int | 首版 `<= 14` | 可选探索模块预算上限 |
| `worlds[].fixed_slots[].slot.x` / `worlds[].fixed_slots[].slot.y` | int | `0..8`、不得重复 | 固定关键槽位坐标 |
| `worlds[].fixed_slots[].template_id` | string | 注册表中存在且 approved；必须在三个配置锚点各放恰好 1 个 start / objective / extraction 角色 | 固定关键模板引用，防止 seeded 世界缺少目标或撤离 |
| `worlds[].fixed_slots[].rotation` | int | `0/90/180/270` | 固定模板旋转，不允许镜像 |
| `worlds[].template_pool` | array[string] | 非空，只能引用 `approved` | 普通槽位随机模板池 |
| `worlds[].limited_template_groups[]` | array[object] | 非空；组 id 与模板引用均不得重复 | 在普通模板填充前执行的限量抽选 |
| `worlds[].limited_template_groups[].pick_distinct` | int | `1..entries.size()` | 按权重无放回抽取不同模板数；当前世界事件组为 3 |
| `worlds[].limited_template_groups[].entries[].template_id` | string | approved 且角色为 `module_role_world_event` | 当前五种纯平原事件模板等权候选 |
| `worlds[].limited_template_groups[].entries[].weight` | number | `> 0` | 组内相对抽取权重 |
| `worlds[].limited_template_groups[].entries[].count_per_floor` | int | `>= 1`，选中总数不得超过自由槽位 | 某候选被选中后放置次数；当前均为 1 |
| `worlds[].fallback_assignment[].slot.x` / `worlds[].fallback_assignment[].slot.y` | int | 完整覆盖 `0..8` | 固定安全布局槽位 |
| `worlds[].fallback_assignment[].template_id` | string | 注册表中存在且 approved | 固定安全布局模板 |
| `worlds[].fallback_assignment[].rotation` | int | `0/90/180/270` | 固定安全布局旋转 |
| `worlds[].technical_slice_assignment[].slot.x` / `worlds[].technical_slice_assignment[].slot.y` | int | 完整覆盖 `0..8` | 中心 3×3 首片与封锁槽位坐标 |
| `worlds[].technical_slice_assignment[].template_id` | string | 注册表中存在 | 首片内部模板或 candidate 封锁模板 |
| `worlds[].technical_slice_assignment[].rotation` | int | `0/90/180/270` | 首片模板旋转 |
| `first_visit_enemy_spawn.count_min` / `count_max` | int | `1 <= count_min <= count_max`；当前 `4..6` | 首次实际进入非起点槽时确定的敌人数；可用空地不足时运行时裁剪并诊断 |
| `first_visit_enemy_spawn.telegraph_duration` | number | `> 0`；当前 `1.5` 秒 | 所有计划位置同时显示地面预警的玩法时长 |
| `first_visit_enemy_spawn.enemy_pool[].enemy_id` | string | 唯一且引用 `enemies.csv` | 可抽取敌种 |
| `first_visit_enemy_spawn.enemy_pool[].unlock_time` | number | 非负、按数组非递减，首项为 `0` | 敌种开始参与抽取的 `GameClock` 局内时间 |
| `first_visit_enemy_spawn.enemy_pool[].weight` | number | `> 0` | 已解锁敌种的相对权重 |

“可刷怪空地”由 `ModuleWorldManager.empty_floor_positions_at()` 按世界槽位计算：世界旋转、外圈封边和封锁邻居处理后仍为 floor，并排除任何 gameplay placement 的 `cell` / 完整 `footprint`。它不检查玩家、敌人或其他动态实体占位，也不设置安全半径。返回位置固定为格心并按行、列稳定排序；`GameplayRunLoop` 使用 `RNG.spawn` 无放回抽取位置，并按同一 RNG 子流抽取当时按威胁时间已解锁的敌种。抽取结果、`telegraphing/spawned` 状态和剩余预警时间立即写入 Run v8 槽位状态，之后不得重抽；敌人的生命 / 显式攻击伤害倍率在预警结束真正生成时取得，不写入预警计划。

当前模块敌池按 `unlock_time` 非递减排列：0 秒开放爆猎者 55 与突击枪手 100，60 秒开放群袭者 30，240 秒开放伏击者 15，420 秒开放壁垒者 20。完整权重总和为 220，突击枪手占约 45.5%，是最高权重但不设置每房必出或保底。

`module_templates.json` 字段：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `templates[].id` | string | 唯一、非空 | 模板 id；世界 assignment 引用此值 |
| `templates[].path` | string | `res://data/modules/*.json` 且文件存在 | 独立模块 JSON 路径 |
| `templates[].role` | string | `module_roles` | 起点 / 连接 / 战斗 / 资源 / 机关 / 目标 / 撤离 / 世界事件 / 封锁角色 |
| `templates[].tags` | array[string] | 可为空 | 编辑期筛选标签，不直接产生玩法分支 |
| `templates[].source` | string | 首版 `ai` | 内容来源审计字段；AI 只在编辑期产出 JSON |
| `templates[].review_status` | string | `module_review_statuses` | `candidate` 不得进入默认池，人工批准后为 `approved` |
| `templates[].approved_gameplay_hash` | string | approved 时为 64 位小写 sha256，candidate 时省略 | terrain、派生 socket、placement、role、tags 与 allowed rotations 的批准锚点；纯视觉变化不降级，但仍要求重新 bake |
| `templates[].allowed_rotations` | array[int] | `0/90/180/270` 的非空子集 | assignment 允许的运行时根节点旋转集合；不支持镜像，也不为每个方向生成独立 TSCN |

## `elements.json` / `hero_passives.json`

`elements.json` schema v1 声明七个结构化 `element_id`、中性元素、未匹配结果与对称主元素组合表。单条元素字段为 `id`、`name_key`、`kind`（`neutral` / `primary` / `composite`）和 `components[]`；数据 id 必须与词表 §9 完全一致。组合表只显式登记 A+B→AB、B+C→BC、C+A→CA；中性与同元素 identity 由 `ElementResolver` 统一处理，复合元素不会继续自动合成，未匹配当前返回空字符串。

| 字段路径 | 类型 / 范围 | 说明 |
|----------|-------------|------|
| `neutral_element_id` | 已登记 element id | identity 规则使用的中性元素 |
| `unmatched_result` | string | 没有显式规则时的结果；当前为空字符串 |
| `combinations[].left` / `combinations[].right` | 不同的 primary element id | 无序输入对；解析器按对称键处理 |
| `combinations[].result` | composite element id | 显式组合结果 |

`hero_passives.json` schema v1 声明稳定 `hero_passive_id`、中英 key、通用 `effect` 与 params。当前两条被动都复用 `element_damage_taken_multiplier`，分别把纯主元素 A / B 的最终承伤乘 0.6；运行时不得按英雄 id 特判。

| 字段路径 | 类型 / 范围 | 说明 |
|----------|-------------|------|
| `passives[].params.multiplier` | number，`>= 0` | 匹配元素伤害的最终承伤倍率；当前为 0.6 |

## `characters.json`

当前结构：

```json
{
  "schema_version": 4,
  "characters": [
    {
      "id": "character_primary_a",
      "scene_path": "res://scenes/gameplay/actors/characters/character_default.tscn",
      "name_key": "character_primary_a_name",
      "desc_key": "character_primary_a_desc",
      "default_unlocked": true,
      "tags": ["tag_character"],
      "capabilities": [],
      "control_profile": "default_mouse_shooter",
      "palette": {
        "primary": "#68BCDD"
      },
      "element_id": "element_primary_a",
      "passive_id": "passive_primary_a_guard",
      "hero_skill_ids": [
        "skill_deploy_projectile_barrier",
        "skill_aoe_slow"
      ],
      "starting_loadout": {
        "weapon_id": "weapon_basic_blaster",
        "active_item_id": "active_item_blink_burst",
        "consumable_ids": ["consumable_pocket_bomb"]
      },
      "skill_resources": [
        {
          "id": "energy",
          "max_stat": "max_energy",
          "start_ratio": 1.0,
          "regen_per_second": 0.0
        }
      ],
      "base_stats": {
        "max_hp": 500.0,
        "max_shield": 250.0,
        "max_energy": 140.0,
        "health_regen": 0.0,
        "move_speed": 230.0,
        "armor": 60.0,
        "ability_strength": 1.0,
        "ability_range": 1.0,
        "ability_efficiency": 1.0,
        "ability_duration": 1.0
      }
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `4` | 数据结构版本 |
| `characters[].id` | string | 词表 §12.1 character id，文件内唯一 | 角色 id；模式池、局外解锁和存档引用此 id |
| `characters[].scene_path` | string | `res://scenes/gameplay/actors/characters/*.tscn`，文件存在且为 `PackedScene` | 角色专属继承场景；不同角色 id 可复用同一场景，但不能指向 `player_base.tscn` |
| `characters[].name_key` / `desc_key` | string | `character_*_name` / `character_*_desc` | 角色名称和描述译文 key |
| `characters[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续需与跨局解锁 / 装备 Mod 系统的解锁状态保持一致 |
| `characters[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_character` | 内容标签；破限角色还需含 `tag_limit_break` 并声明 capability |
| `characters[].capabilities` | array[string] | 词表 §12.2 capability id，可为空 | 允许突破的默认规则；空数组表示默认鼠标瞄准 / 左右朝向 / 按住开火 / 默认移动 |
| `characters[].control_profile` | string | 非空 | 控制配置标识；当前只做数据边界，不实现输入 profile 切换 |
| `characters[].palette` | object | 必须且只能含一个合法 HTML 颜色 `primary` | 每个碎片唯一的颜色来源；冷静当前为 `#68BCDD`，愤怒为 `#ED2F72`。遗留 `secondary` / `accent` 或任何额外键都会拒绝 |
| `characters[].element_id` | string | 词表 §9 element id，且存在于 `elements.json` | 英雄的主元素 |
| `characters[].passive_id` | string | 词表 §12-I，且存在于 `hero_passives.json` | 仅主英雄生效的通用数据被动 |
| `characters[].hero_skill_ids` | array[string] | 固定长度 2；技能已登记且存在，角色内不重复 | 主英雄映射槽 1–2，子英雄映射槽 3–4 |
| `characters[].starting_loadout` | object | 必填 | 角色起始携带内容引用；当前只做 schema，不发放运行时实体 |
| `characters[].starting_loadout.weapon_id` | string | 必须存在于 `weapons.json` | 默认起始武器引用 |
| `characters[].starting_loadout.active_item_id` | string | 必须存在于 `active_items.json` | 默认起始主动道具引用 |
| `characters[].starting_loadout.consumable_ids` | array[string] | 可为空；每项必须存在于 `consumables.json`，文件内不重复 | 默认起始消耗品引用列表；数量规则仍由后续 ConsumableSystem 解释 |
| `characters[].starting_loadout.consumable_ids[]` | string | 必须存在于 `consumables.json` | 单个默认起始消耗品引用 |
| `characters[].skill_resources[]` | array[object] | 可为空；每项 id 不重复 | 角色拥有的技能资源池；技能通过 `costs[].resource` 消耗这些资源 |
| `characters[].skill_resources[].id` | string | 词表 §12-D skill resource id | 当前为 `energy` |
| `characters[].skill_resources[].max_stat` | string | 当前必须为 `max_energy` | 从主英雄最终属性读取资源上限，避免重复维护数值 |
| `characters[].skill_resources[].start_ratio` | number | `0..1` | 开局资源比例；当前为 1.0（充满） |
| `characters[].skill_resources[].regen_per_second` | number | `>= 0`，每秒 | `GameClock` 缩放时间下每秒恢复量；0 表示不自动恢复 |
| `characters[].base_stats` | object | stat 来自词表 §1，非空 | 角色基础属性；数值范围同 `player.json` stat 校验 |
| `characters[].base_stats.max_shield` | number | `>= 0` | 主英雄基础护盾 |
| `characters[].base_stats.armor` | number | `>= 0` | 主英雄基础通用防御 |

`characters.json` 声明英雄场景、主元素、被动、primary-only palette、固定两项英雄技能和资源池。`HeroCompositionResolver` 只采用主英雄的场景、基础属性、被动、起始携带和资源池，并把主英雄技能映射到 `skill_1/2`、子英雄技能映射到 `skill_3/4`；组合 palette 精确输出 `main_primary` 与 `sub_primary`。正式 Shader 用双方颜色绘制两股涡旋，外轮廓 / 湿润边 / 朝向短束使用主色规则；HUD 名称与槽 1/2 使用主色、槽 3/4 使用副色、共享能量保持白色。默认禁止主/子重复；显式允许重复时，后出现的重复技能槽能量消耗与冷却倍率均为 1.5。

## `weapons.json`

当前结构：

```json
{
  "schema_version": 4,
  "recoil_model": {
    "recoil_max": 100.0,
    "spread_exponent": 1.5,
    "base_spread_cap": 60.0,
    "kickback_max_distance": 14.0,
    "kickback_duration": 0.08,
    "kickback_velocity_cap": 500.0,
    "runtime_spread_cap": 180.0
  },
  "weapons": [
    {
      "id": "weapon_basic_blaster",
      "name_key": "weapon_basic_blaster_name",
      "desc_key": "weapon_basic_blaster_desc",
      "default_unlocked": true,
      "fire_mode": "hold_mouse",
      "fire_audio_id": "sfx_player_shoot",
      "base_stats": {
        "damage": 3.5,
        "fire_rate": 2.5,
        "bullet_speed": 350.0,
        "bullet_range": 650.0,
        "bullet_count": 1,
        "pierce_count": 0,
        "wall_pierce": 0.0,
        "crit_chance": 0.0,
        "crit_mult": 1.5,
        "recoil": 20.0,
        "spread_angle_max": 60.0
      },
      "ammo": {
        "magazine_size": 30,
        "starting_reserve": 150,
        "total_capacity": 240,
        "reload_duration": 1.2,
        "depleted_fire_rate_multiplier": 0.5,
        "depleted_bullet_speed_multiplier": 0.5
      },
      "projectile": {
        "pool_id": "bullet_basic",
        "element_id": "element_neutral",
        "hit_radius": 12.0,
        "muzzle_distance": 38.0,
        "lifetime": 1.9
      }
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `4` | 数据结构版本；v4 为每个武器增加必填 `ammo` 配置 |
| `recoil_model.recoil_max` | number | `> 0`；当前 `100` | 武器基础 `recoil` 的校验上限，也是后坐力强度归一化分母 |
| `recoil_model.spread_exponent` | number | `> 0`；当前 `1.5` | 归一化后坐力映射为实际弹道扩散比例时使用的指数；大于 `1` 会压低低后坐力区间的扩散 |
| `recoil_model.base_spread_cap` | number | 度，`> 0`；当前 `60` | 武器基础 `spread_angle_max` 的数据校验上限 |
| `recoil_model.kickback_max_distance` | number | px，`>= 0`；当前 `14` | `recoil` 达到上限时，玩家单次开火反向冲量的最大目标距离 |
| `recoil_model.kickback_duration` | number | 秒，`> 0`；当前 `0.08` | 反向冲量换算为速度时使用的持续时间 |
| `recoil_model.kickback_velocity_cap` | number | px/s，`> 0`；当前 `500` | 单次开火反向冲量速度的绝对上限 |
| `recoil_model.runtime_spread_cap` | number | 度，`>= base_spread_cap`；当前 `180` | 应用全部修正器后实际完整扩散锥角的绝对上限 |
| `weapons[].id` | string | 文件内唯一，非空 | 武器 id；角色起始武器和模式武器池引用此 id |
| `weapons[].name_key` / `desc_key` | string | `weapon_*_name` / `weapon_*_desc` | 武器名称和描述译文 key |
| `weapons[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `weapons[].fire_mode` | string | 非空 | 开火模式标识；当前只做数据边界，不实现开火策略 |
| `weapons[].fire_audio_id` | string | 可选；已声明时必须符合词表 §10 audio prefix | 开火音效 id；当前只校验前缀，不要求资源已存在 |
| `base_stats.damage` | number | `>= 0` | 单发基础伤害 |
| `base_stats.fire_rate` | number | `> 0` | 每秒发射次数 |
| `base_stats.bullet_speed` | number | `> 0` | 子弹速度，px/s |
| `base_stats.bullet_range` | number | `> 0` | 子弹最大射程，px |
| `base_stats.bullet_count` | int | `>= 1` | 每次发射子弹数 |
| `base_stats.pierce_count` | int | `>= 0` | 可额外命中的伤害目标数量；`0` 表示命中首个目标后回收，不影响墙体 |
| `base_stats.wall_pierce` | number | `>= 0` | 全地形穿透开关；`0` 表示撞墙回收，`>0` 表示忽略地形；发射时快照 |
| `base_stats.crit_chance` | number | `0.0`~`1.0` | 暴击率 |
| `base_stats.crit_mult` | number | `> 0` | 暴击倍率 |
| `base_stats.recoil` | number | `0..recoil_model.recoil_max` | 武器后坐力强度；共同驱动震屏、玩家反向冲量与弹道扩散 |
| `base_stats.spread_angle_max` | number | 度，`0..recoil_model.base_spread_cap` | 武器在满后坐力下的基础完整扩散锥角上限；运行时仍受 `runtime_spread_cap` 约束 |
| `ammo.magazine_size` | int | 发，`>= 1`；基础枪为 `30` | 满弹匣可容纳的弹数；每次成功正常开火消耗一发 |
| `ammo.starting_reserve` | int | 发，`>= 0` 且 `<= total_capacity - magazine_size`；基础枪为 `150` | 新局在满弹匣之外携带的备用弹药 |
| `ammo.total_capacity` | int | 发，`>= magazine_size + starting_reserve`；基础枪为 `240` | 当前弹匣与备用弹药合计的携带上限 |
| `ammo.reload_duration` | number | 秒，`> 0`；基础枪为 `1.2` | 主动换弹从开始到提交的持续时间 |
| `ammo.depleted_fire_rate_multiplier` | number | 倍率，`> 0` 且 `<= 1`；基础枪为 `0.5` | 弹匣与备用弹药都为空时，降级射击对基础射速应用的倍率 |
| `ammo.depleted_bullet_speed_multiplier` | number | 倍率，`> 0` 且 `<= 1`；基础枪为 `0.5` | 弹匣与备用弹药都为空时，降级射击对子弹速度应用的倍率 |
| `projectile.pool_id` | string | 词表 §8 pool id | 使用的子弹对象池 |
| `projectile.element_id` | string | 词表 §9 element id | 默认战斗元素；旧 `damage_type` 已删除 |
| `projectile.hit_radius` | number | `> 0` | 命中半径，px |
| `projectile.muzzle_distance` | number | `> 0` | 发射点相对角色中心距离，px；基础玩家武器当前为 38（25 px 玩家半径 + 12 px 子弹半径 + 1 px 间隙），敌人攻击配置仍独立保持 24 |
| `projectile.lifetime` | number | `> 0` | 子弹存活秒数；业务系统可结合射程裁剪 |

`weapons.json` 只声明武器 / 子弹数据边界，不实现 WeaponSystem、子弹实例化、命中判定、音频播放或武器选择 UI。角色通过 `characters[].starting_loadout.weapon_id` 引用默认起始武器；游戏模式可通过 `resource_pools.weapons` 声明可用武器池。

## `ammo_rules.json`

当前结构：

```json
{
  "schema_version": 1,
  "pool_id": "ammo_magazine",
  "pickup_speed": 360.0,
  "pickup_magazine_count": 1,
  "initial_drop_chance": 0.08,
  "chance_increment_per_miss": 0.15,
  "guaranteed_after_misses": 7,
  "rng_stream": "ammo"
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `1` | 弹匣掉落与拾取规则的数据结构版本 |
| `pool_id` | string | 必须为词表 §8 的 `ammo_magazine` | 弹匣拾取物使用的统一对象池 |
| `pickup_speed` | number | px/s，`> 0`；当前 `360` | 弹匣进入玩家拾取范围后向玩家吸附的移动速度 |
| `pickup_magazine_count` | int | 个，`>= 1`；当前 `1` | 每次拾取补充的完整弹匣数量；实际弹数按当前武器 `ammo.magazine_size` 换算并受总容量限制 |
| `initial_drop_chance` | number | `0.0..1.0`；当前 `0.08` | 满足掉落资格的玩家归因击杀在零次连续未掉落时的初始概率 |
| `chance_increment_per_miss` | number | `0.0..1.0`；当前 `0.15` | 每次满足资格但未掉落后，为下一次判定增加的概率；有效概率最高按 `1.0` 处理 |
| `guaranteed_after_misses` | int | `>= 1`；当前 `7` | 连续未掉落达到该次数后，下一次满足资格的击杀必定掉落 |
| `rng_stream` | string | 必须为词表 §11 的 `ammo` | 弹匣掉落专用确定性 RNG 子流；满弹时不抽取、不推进连续未掉落计数 |

弹匣掉落成功后连续未掉落计数归零。`ammo_rules.json` 只声明全局弹匣掉落与拾取数值，不覆盖各武器的弹匣容量、起始备用弹药、总容量、换弹时间或空弹降级倍率。

## `relics.json`

当前结构：

```json
{
  "schema_version": 1,
  "relics": [
    {
      "id": "relic_sharp_rounds",
      "name_key": "relic_sharp_rounds_name",
      "desc_key": "relic_sharp_rounds_desc",
      "default_unlocked": true,
      "tags": ["tag_relic"],
      "modifiers": [
        { "stat": "damage", "type": "add", "value": 0.5 }
      ],
      "behaviors": []
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `relics[].id` | string | 文件内唯一，非空 | 遗物 id；模式遗物池引用此 id |
| `relics[].name_key` / `desc_key` | string | `relic_*_name` / `relic_*_desc` | 遗物名称和描述译文 key |
| `relics[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `relics[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_relic` | 内容标签；破限遗物还需含 `tag_limit_break` 并声明 capability / primitive |
| `relics[].modifiers` | array[object] | 可为空；与 `behaviors` 至少一个非空 | 数值修正列表，格式见下节 |
| `relics[].behaviors` | array[object] | 可为空；与 `modifiers` 至少一个非空 | 行为触发列表，格式见下节 |

`relics.json` 只声明被动遗物数据边界，不实现拾取、掉落、升级候选、`ModifierEngine` 应用、行为原语执行、UI 展示或存档快照。游戏模式可通过 `resource_pools.relics` 声明可用遗物池；实际抽取、解锁和应用由后续系统解释。

## `active_items.json`

当前结构：

```json
{
  "schema_version": 1,
  "active_items": [
    {
      "id": "active_item_blink_burst",
      "name_key": "item_blink_burst_name",
      "desc_key": "item_blink_burst_desc",
      "default_unlocked": true,
      "tags": ["tag_active_item"],
      "charge": {
        "mode": "cooldown",
        "cooldown": 8.0,
        "max_charges": 1,
        "start_charges": 1
      },
      "use_effects": [
        {
          "effect": "knockback",
          "params": {
            "force": 180.0,
            "radius": 96.0
          }
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `active_items[].id` | string | 文件内唯一，非空 | 主动道具 id；模式主动道具池引用此 id |
| `active_items[].name_key` / `desc_key` | string | `item_*_name` / `item_*_desc` | 主动道具名称和描述译文 key |
| `active_items[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `active_items[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_active_item` | 内容标签；突破栏位 / 使用规则时需补 capability / 测试说明 |
| `active_items[].charge.mode` | string | 当前为 `cooldown` | 充能模型；新增模型前先补 schema 与运行时设计 |
| `active_items[].charge.cooldown` | number | `> 0` | 单次充能冷却秒数 |
| `active_items[].charge.max_charges` | int | `>= 1` | 最大充能数 |
| `active_items[].charge.start_charges` | int | `0..max_charges` | 开局初始充能数 |
| `active_items[].use_effects[]` | array[object] | 必须非空 | 使用时触发的效果原语列表 |
| `active_items[].use_effects[].effect` | string | 词表 §2 effect id | 使用效果原语 |
| `active_items[].use_effects[].params` | object | 由 effect 解释 | 效果参数；当前只做 schema 校验，不执行 |
| `active_items[].use_effects[].params.force` | number | `> 0` 建议 | `knockback` 击退力度；当前只作为参数声明 |
| `active_items[].use_effects[].params.radius` | number | `> 0` 建议 | `knockback` 生效半径；当前只作为参数声明 |

`active_items.json` 只声明主动道具数据边界，不实现主动道具栏、输入响应、冷却计时、充能 UI、效果执行、掉落 / 解锁或存档快照。游戏模式可通过 `resource_pools.active_items` 声明可用主动道具池；旧 `use_active_item` action 已删除，未来主动道具使用入口须另行明确并继续遵守 `InputService`、`GameClock`、`RNG` 和对应业务系统边界。

## `skills.json`

当前结构：

```json
{
  "schema_version": 2,
  "skills": [
    {
      "id": "skill_aoe_slow",
      "name_key": "skill_aoe_slow_name",
      "desc_key": "skill_aoe_slow_desc",
      "default_unlocked": true,
      "tags": ["tag_skill"],
      "ability_tags": [
        "ability_tag_skill",
        "ability_tag_primary"
      ],
      "activation": {
        "required_tags": [],
        "blocked_tags": ["ability_tag_silenced"],
        "granted_tags": ["ability_tag_activating"]
      },
      "cooldown": 10.0,
      "costs": [{ "resource": "energy", "amount": 30.0 }],
      "targeting": {
        "type": "aoe_enemies_around_caster",
        "radius": 280.0,
        "max_targets": 0
      },
      "scaling": {
        "cost_stat": "ability_efficiency",
        "radius_stat": "ability_range",
        "duration_stat": "ability_duration",
        "strength_stat": "ability_strength"
      },
      "effects": [
        {
          "effect": "skill_effect_apply_status",
          "params": {
            "status": "slow",
            "duration": 5.0,
            "stack_rule": "MAX_MAGNITUDE",
            "magnitude": 0.35,
            "magnitude_cap": 0.7,
            "modifiers": [
              {"stat": "move_speed", "type": "mult", "value": 0.65, "scale_mode": "inverse_from_magnitude"}
            ],
            "granted_ability_tags": []
          }
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | 必须为 `2` | 数据结构版本 |
| `skills[].id` | string | 词表 §12-C skill id，文件内唯一 | 技能 id；角色、主动道具、敌人或事件系统可复用引用 |
| `skills[].name_key` / `desc_key` | string | `skill_*_name` / `skill_*_desc` | 技能名称和描述译文 key |
| `skills[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `skills[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_skill` | 内容标签；模式 blocklist 和后续构筑筛选可复用 |
| `skills[].ability_tags` | array[string] | 词表 §12-G ability tag，非空 | 项目版轻量 GAS 的能力语义标签；用于分类、阻断、解锁和后续 cue / AI 查询，不与 content tag 混用 |
| `skills[].activation` | object | 必填 | 项目版轻量 GAS 的激活条件配置 |
| `skills[].activation.required_tags` | array[string] | 词表 §12-G ability tag，可为空 | 释放者必须拥有的运行时能力标签；缺任一标签则返回 `missing_required_tag` 且不消耗资源 |
| `skills[].activation.blocked_tags` | array[string] | 词表 §12-G ability tag，可为空 | 释放者拥有任一标签时阻断释放；当前默认用 `ability_tag_silenced` 表达沉默 |
| `skills[].activation.granted_tags` | array[string] | 词表 §12-G ability tag，可为空 | 激活 / commit 期间临时授予释放者的标签；当前即时技能会在效果解释后移除 |
| `skills[].cooldown` | number | 秒，`>= 0` | 释放后冷却时间，走 `GameClock` 缩放时间 |
| `skills[].costs[]` | array[object] | 可为空 | 释放消耗列表；为空表示无消耗 |
| `skills[].costs[].resource` | string | 词表 §12-D skill resource id | 消耗的资源 id；释放者必须在 `skill_resources` 中拥有该资源 |
| `skills[].costs[].amount` | number | `>= 0` | 单次释放消耗量 |
| `skills[].targeting` | object | 必填 | 目标选择声明，由 `SkillSystem` 解释 |
| `skills[].targeting.type` | string | 词表 §12-E skill targeting id | 目标选择策略 |
| `skills[].targeting.radius` | number | `> 0`，px | AOE 或近邻目标查询半径 |
| `skills[].targeting.max_targets` | int | `>= 0` | 最大目标数量；0 表示不限制 |
| `skills[].scaling` | object | 必填 | 只声明实际启用的四维缩放映射；冷却不缩放 |
| `skills[].scaling.cost_stat` | string | 必须为 `ability_efficiency` | 能量消耗按效率反比缩放 |
| `skills[].scaling.radius_stat` | string | 可选，必须为 `ability_range` | targeting 或 effect 半径乘范围倍率 |
| `skills[].scaling.duration_stat` | string | 可选，必须为 `ability_duration` | 状态 / buff 持续时间乘持续倍率 |
| `skills[].scaling.strength_stat` | string | 可选，必须为 `ability_strength` | 屏障 HP、减速 magnitude 或 modifier 相对 1.0 的增量乘强度倍率 |
| `skills[].effects[]` | array[object] | 必须非空 | 命中目标后执行的技能效果原语列表 |
| `skills[].effects[].effect` | string | 词表 §12-F skill effect id | 技能效果原语 |
| `skills[].effects[].params` | object | 由 effect 解释 | 技能效果参数 |
| `skills[].effects[].params.amount` | number | `> 0` | `skill_effect_damage` 的伤害量 |
| `skills[].effects[].params.element_id` | string | 词表 §9 element id | `skill_effect_damage` 的战斗元素；`skill_effect_apply_status` 做 DoT 时也必须填写；结算走 `Combat.apply_damage` |
| `skills[].effects[].params.status` | string | 词表 §9-A status effect id | `skill_effect_apply_status` 施加的状态 id |
| `skills[].effects[].params.duration` | number | 秒，`> 0` | `skill_effect_apply_status` 的持续时间，过期走 `GameClock` |
| `skills[].effects[].params.stack_rule` | string | 词表 §9-B status stack rule | 状态重复施加时的叠加 / 刷新规则 |
| `skills[].effects[].params.granted_ability_tags` | array[string] | 词表 §12-G ability tag，可为空 | 状态存在期间授予目标的 ability tags；当前沉默使用 `ability_tag_silenced` |
| `skills[].effects[].params.magnitude` | number | 可选 | 状态强度；DoT 中表示单 tick 伤害，减速 / 增伤标记后续可复用 |
| `skills[].effects[].params.tick_interval` | number | 可选，`>= 0` | DoT tick 间隔；与正 `magnitude` 同时出现时必须提供已登记 `element_id` |
| `skills[].effects[].params.modifiers[]` | array[object] | actor / weapon modifier 或状态修正使用；格式同词表 §1 modifier | 临时属性修正；slow 可加 `scale_mode=inverse_from_magnitude` |
| `skills[].effects[].params.modifiers[].scale_mode` | string | 可选；当前只允许 `inverse_from_magnitude` | 按 `1 - magnitude × ability_strength` 重算减速乘区 |
| `skills[].effects[].params.radius` | number | `> 0`，px | 屏障或效果自身半径 |
| `skills[].effects[].params.hp` | number | `> 0` | 屏障生命值 |
| `skills[].effects[].params.max_active` | int | `>= 1` | 同一释放者可同时存在的屏障数量 |
| `skills[].effects[].params.recast_policy` | string | 当前必须为 `replace` | 达到 max_active 后重施替换旧屏障 |
| `skills[].effects[].params.magnitude_cap` | number | `>= 0` | ability strength 缩放后的状态强度上限 |
| `skills[].effects[].params.max_stacks` | int | 可选，`>= 1` | `ADD_STACK_REFRESH` 的叠层上限 |
| `skills[].effects[].params.incoming_damage_per_stack` | number | 可选，`>= 0` | vulnerable 每层易伤倍率 |
| `skills[].effects[].params.incoming_damage_source_team` | string | 非空 team id | 易伤只对指定来源队伍生效；当前为 `team_player` |

`skills.json` 是技能本体数据；英雄只通过 `hero_skill_ids` 引用技能。当前四技能为静域屏障、镇静脉冲、怒意超频和激怒标记，分别复用 deploy barrier、apply status 与 actor modifiers 原语；运行时按 `skill_1`～`skill_4` 解释，禁止按技能或英雄 id 特判。

## `consumables.json`

当前结构：

```json
{
  "schema_version": 1,
  "consumables": [
    {
      "id": "consumable_pocket_bomb",
      "name_key": "item_pocket_bomb_name",
      "desc_key": "item_pocket_bomb_desc",
      "default_unlocked": true,
      "tags": ["tag_consumable"],
      "stack": {
        "max_stack": 3,
        "start_count": 0,
        "pickup_count": 1
      },
      "use_effects": [
        {
          "effect": "explode",
          "params": {
            "radius": 96.0,
            "damage": 8.0
          }
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `consumables[].id` | string | 文件内唯一，非空 | 消耗品 id；模式消耗品池引用此 id |
| `consumables[].name_key` / `desc_key` | string | `item_*_name` / `item_*_desc` | 消耗品名称和描述译文 key |
| `consumables[].default_unlocked` | bool | true / false | 新存档中是否默认可用；后续可接局外解锁 |
| `consumables[].tags` | array[string] | 词表 §12.3 content tag，必须含 `tag_consumable` | 内容标签；突破携带规则时需补 capability / 测试说明 |
| `consumables[].stack.max_stack` | int | `>= 1` | 最大可持有数量 |
| `consumables[].stack.start_count` | int | `0..max_stack` | 开局初始数量 |
| `consumables[].stack.pickup_count` | int | `1..max_stack` | 单次拾取增加数量 |
| `consumables[].use_effects[]` | array[object] | 必须非空 | 使用时触发的效果原语列表 |
| `consumables[].use_effects[].effect` | string | 词表 §2 effect id | 使用效果原语 |
| `consumables[].use_effects[].params` | object | 由 effect 解释 | 效果参数；当前只做 schema 校验，不执行 |
| `consumables[].use_effects[].params.radius` | number | `> 0` 建议 | `explode` 爆炸半径；当前只作为参数声明 |
| `consumables[].use_effects[].params.damage` | number | `>= 0` 建议 | `explode` 爆炸伤害；当前只作为参数声明 |

`consumables.json` 只声明消耗品数据边界，不实现拾取物、背包栏、使用输入、数量扣减、效果执行、掉落 / 解锁或存档快照。游戏模式可通过 `resource_pools.consumables` 声明可用消耗品池；实际拾取随机必须走 `RNG.drop`，局内时间必须走 `GameClock`，高频拾取实体必须走 `PoolManager`。

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

## `gear_mods.json`

> 装备 Mod 系统见 `docs/AI协作/工作包/F11-GearModLoadout.md` 与 `docs/代码/gear_mod_system.md`。这里的装备 Mod 是玩家装配系统，不是 `ModLoader` 读取的本地数据包 mod。

```json
{
  "schema_version": 1,
  "mods": [
    {
      "id": "gear_mod_weapon_damage_test",
      "name_key": "gear_mod_weapon_damage_test_name",
      "desc_key": "gear_mod_weapon_damage_test_desc",
      "slot": "weapon",
      "rarity": "common",
      "max_rank": 5,
      "base_drain": 2,
      "drain_per_rank": 1,
      "rank_modifiers": [
        { "stat": "damage", "type": "mult", "base_value": 1.10, "value_per_rank": 0.05 }
      ],
      "stack_rule": "unique_by_id",
      "dismantle": {
        "resource_id": "gear_mod_dust",
        "amount": 10
      }
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 合法值 / 范围 | 说明 |
|----------|------|---------------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `mods[].id` | string | 词表 §13-A `gear_mod_id` | 装备 Mod id |
| `mods[].name_key` / `desc_key` | string | `gear_mod_*_name` / `gear_mod_*_desc` | 名称和描述译文 key |
| `mods[].slot` | string | 词表 §13-B | 可装备到英雄或武器 loadout |
| `mods[].rarity` | string | 词表 §13-C | 稀有度；用于掉落展示和升级成本 |
| `mods[].max_rank` | int | `>= 0` | 最大升级 rank；rank 0 表示初始获得状态 |
| `mods[].base_drain` | int | `>= 0` | rank 0 装备容量消耗 |
| `mods[].drain_per_rank` | int | `>= 0` | 每提升 1 rank 增加的容量消耗 |
| `mods[].rank_modifiers[]` | array[object] | stat 来自词表 §1 | 随 rank 计算的 modifiers |
| `rank_modifiers[].base_value` | number | 由 modifier 类型决定 | rank 0 的初始值；`mult` 用 `1.0` 表示不变 |
| `rank_modifiers[].value_per_rank` | number | 可正可负 | 每 rank 增量 |
| `mods[].stack_rule` | string | 词表 §13-E | 同一 loadout 内的重复装备规则；首片为 `unique_by_id` |
| `mods[].dismantle.resource_id` | string | 词表 §13-D | 分解返还资源 |
| `mods[].dismantle.amount` | int | `>= 0` | 分解返还数量；应低于一次升级成本，避免套利 |

当前普通武器 Mod 包含基础伤害、后坐力和弹道扩散三类修正。`gear_mod_weapon_recoil_damper` 与 `gear_mod_weapon_spread_stabilizer` 均从 rank 0 的 `0.90` 倍率开始，每 rank 递减 `0.05`，rank 5 为 `0.65`；运行时通过通用 modifier 摘要显示当前 rank 的实际百分比，描述文案不重复写死数值。所有掉落都必须用通用掉落表解释，不在敌人或武器代码中写按 id 分支。

## `gear_mod_drop_tables.csv`

```csv
source_enemy_id,mod_id,drop_chance,min_enemy_level,max_enemy_level
enemy_chaser,gear_mod_weapon_damage_test,0.01,1,999
```

字段说明：

| 字段 | 类型 | 单位 / 范围 | 说明 |
|------|------|-------------|------|
| `source_enemy_id` | string | 必须存在于 `enemies.csv` | 掉落来源敌人 |
| `mod_id` | string | 必须存在于 `gear_mods.json` | 掉落的装备 Mod |
| `drop_chance` | float | `0.0..1.0` | 单次玩家归因击杀掉落概率；高频敌人应按出现率反向校准，不能只比较单体概率 |
| `min_enemy_level` / `max_enemy_level` | int | `>= 1` | 可选等级区间；未实现敌人等级前可先填宽范围 |

当前基础伤害与后坐力 Mod 分别由 `enemy_chaser`、`enemy_bulwark` 以 `1%` 概率掉落；突击枪手 `enemy_spitter` 因完整敌池占比约 45.5%，其弹道稳定 Mod 单体概率下调为 `0.2%`，以大致维持改造前的总体获取节奏。掉落随机必须走 `RNG.drop`；怪物互杀、机关击杀或非玩家归因击杀不产出装备 Mod。

## `gear_mod_fusion_costs.csv`

```csv
rarity,rank,resource_id,cost
common,1,gear_mod_dust,20
common,2,gear_mod_dust,35
common,3,gear_mod_dust,55
common,4,gear_mod_dust,85
common,5,gear_mod_dust,130
```

字段说明：

| 字段 | 类型 | 单位 / 范围 | 说明 |
|------|------|-------------|------|
| `rarity` | string | 词表 §13-C | 装备 Mod 稀有度 |
| `rank` | int | `1..max_rank` | 升到该 rank 需要的成本 |
| `resource_id` | string | 词表 §13-D | 消耗的装备 Mod 资源 |
| `cost` | int | `>= 0` | 升级资源消耗 |

首片使用专用 `gear_mod_dust`，避免旧永久升级经济影响新系统。

## `level_progression.json`

当前结构：

```json
{
  "schema_version": 1,
  "first_level_cost": 100,
  "multiplier_numerator": 13,
  "multiplier_denominator": 10
}
```

字段说明：

| 字段 | 类型 | 单位 / 范围 | 说明 |
|------|------|-------------|------|
| `schema_version` | int | 固定 `1` | 数据结构版本 |
| `first_level_cost` | int | `> 0` | Lv.1→2 的累计金币段成本；当前 100 |
| `multiplier_numerator` | int | `> multiplier_denominator` | 后续段成本倍率分子；当前 13 |
| `multiplier_denominator` | int | `> 0` | 后续段成本倍率分母；当前 10 |

运行时从第一段起使用 `next = ceil(current × numerator / denominator)` 的整数有理数公式，不使用浮点幂或浮点累计。当前前十段固定为 `100, 130, 169, 220, 286, 372, 484, 630, 819, 1065`；对应 Lv.1–11 累计阈值为 `0, 100, 230, 399, 619, 905, 1277, 1761, 2391, 3210, 4275`。等级只由 `gold_earned_total` 推导，不重复保存；消费 `gold_balance` 不影响进度。

## `reward_choice_pools.json`

当前结构：

```json
{
  "schema_version": 1,
  "pools": [
    {
      "id": "default_reward_choice",
      "entries": [
        {
          "id": "reward_damage_small",
          "name_key": "ui_reward_damage_small_name",
          "desc_key": "ui_reward_damage_small_desc",
          "kind": "stat_modifier",
          "weight": 100,
          "min_level": 1,
          "modifiers": [
            { "stat": "damage", "type": "add", "value": 0.5 }
          ]
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 范围 | 说明 |
|----------|------|------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `pools[].id` | string | 非空，文件内唯一 | 通用奖励池 id；由发起请求的调用方显式指定 |
| `pools[].entries` | array[object] | 可为空 | 候选条目列表；当前只落 `stat_modifier` 黄金样例 |
| `entries[].id` | string | 非空，池内唯一 | 候选条目 id；用于回放记录和诊断 |
| `entries[].name_key` / `desc_key` | string | `ui_*` locale key | 奖励选择面板展示的名称和描述 |
| `entries[].kind` | string | 非空 | 候选类型；当前黄金样例为 `stat_modifier`，后续类型落地前需同步 schema |
| `entries[].weight` | int | `> 0` | 抽取权重；实际抽取走 `RNG.ui_choice` |
| `entries[].min_level` | int | `>= 1`，可选 | 条目最早出现等级 |
| `entries[].modifiers` | array[object] | stat 来自词表 §1 | 属性修正奖励；格式同通用 `modifiers`，使用 `value` |

当前只解释 `kind=stat_modifier`，选择后沿用 Player / WeaponSystem modifier 路径即时应用。调用方必须提供 pool id、登记过的 trigger id 和 2–5 的候选数量；运行时先按 `min_level` 过滤，再按稳定 id 顺序使用 `RNG.ui_choice` 加权无放回抽取。`luck` 当前不影响数量、权重或结果。标准模式不配置默认触发器，等级提升不会自动打开本面板。新增 `kind` 影响运行时行为时，必须同步对应系统模块文档和测试。

## `credits.json`

当前结构：

```json
{
  "schema_version": 1,
  "sections": [
    {
      "id": "staff",
      "title_key": "ui_credits_section_staff",
      "entries": [
        {
          "kind": "staff",
          "name": "Anon London / 伦敦阿农",
          "role_key": "ui_credits_role_project_owner"
        }
      ]
    }
  ]
}
```

字段说明：

| 字段路径 | 类型 | 范围 | 说明 |
|----------|------|------|------|
| `schema_version` | int | `>= 1` | 数据结构版本 |
| `sections[].id` | string | 文件内唯一，非空 | 致谢分组 id；供 UI 排序 / 锚点使用，不作为玩法契约 |
| `sections[].title_key` | string | `ui_*` locale key | 分组标题，如工作人员、引擎与外部库 |
| `sections[].entries` | array[object] | 非空 | 本分组的致谢条目 |
| `entries[].kind` | string | `staff` / `external_resource` / `external_library` / `external_tool` | 条目类型；外部条目必须记录来源和许可字段 |
| `entries[].name` | string | 非空 | 人名、项目名、工具名或库名，保持原文 |
| `entries[].role_key` | string | `ui_*` locale key | 面向玩家展示的角色 / 用途说明 |
| `entries[].url` | string | 外部条目必填 | 上游主页或许可证页 |
| `entries[].license` | string | 外部条目必填 | 许可证或服务 / 工具说明；发行前人工复核 |
| `entries[].copyright` | string | 可选 | 上游版权声明，保持原文 |
| `entries[].included_in_build` | bool | 外部条目必填 | 是否随游戏构建或发行包分发 |
| `entries[].requires_notice` | bool | 外部条目必填 | 是否需要在发行包或游戏内保留 notice |
| `entries[].review_required` | bool | 外部条目必填 | 是否仍需发行前人工许可复核 |

`credits.json` 是未来游戏内 Credits UI 的数据源；当前只落数据与 schema，不实现 UI。代码库级人类可读清单在根目录 `CREDITS.md`，两者应同步维护。外部项目名、许可证名、URL 与版权声明可以保持原文；分组标题、角色 / 用途说明走 `client/locale/strings.csv`。

## 调参流程

1. 先看本文档确认字段单位和范围。
2. 只改目标 CSV / JSON，不改 GDScript 常量。
3. 如果新增 id，先改 `docs/词表与契约.md`，再跑 `/sync-contracts` 或等价同步流程。
4. 修改后运行 `python tools/sync_contracts.py --check` 与 `python tools/validate_data.py`；代码落地后由 `DataLoader` fail-fast。
5. 大幅调整基础属性、难度曲线、掉落或升级概率后，按 `docs/测试策略.md` 跑回放 / 平衡验证。

## 新增数据文件或字段时

必须同步：

| 改动 | 必须同步 |
|------|----------|
| 新增数据文件 | 本文档文件总览、GDD §9.3、`docs/AI导航.md`、相关模块文档，并说明为何选 CSV 或 JSON |
| 新增字段 | 本文档字段说明、`DataLoader` schema、相关模块文档、必要时测试策略 |
| 新增 id 类型 | `docs/词表与契约.md`、生成常量、契约校验 |
| 新增玩家可见文案引用 | `client/locale/strings.csv` 与 `client/locale/README.md` |
| 改变玩家可见行为 | GDD、ADR、测试策略、模块文档 |

## 自检清单

- [ ] 数值是否在 `client/data/` 的 CSV / JSON，且格式选择符合“平表 CSV、复杂 JSON”？
- [ ] 字段单位、范围、默认值是否已写进本文档？
- [ ] 是否已运行 `python tools/validate_data.py`？
- [ ] 玩家可见文本是否只存 key，译文是否在 `client/locale/strings.csv`？
- [ ] 所有 id 是否来自 `docs/词表与契约.md`？
- [ ] 大幅平衡改动是否有回放 / sim / 人工试玩记录？
