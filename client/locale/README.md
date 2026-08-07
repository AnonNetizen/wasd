# 多语言文案配置手册

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/游戏设计文档.md` §9.4 与 `docs/词表与契约.md` §6。
> 本文档是完整项目 `client/locale/` 的人工多语言文案配置手册；新增语言、改 CSV 格式、改 key 命名规则、改占位符约定或新增文案域时，必须同步 GDD、词表、AI导航、任务模板和相关 UI / 数据模块文档。

---

## 目标

- 所有面向玩家的文本集中在 `client/locale/strings.csv`，便于人工翻译和校对。
- 代码和数据只引用 key：代码用 `tr("key")`，数据用 `name_key` / `desc_key` 等字段。
- 同一行维护多语言译文，避免每种语言散落在不同文件里难以对照。
- 动态数值使用占位符，禁止在代码里拼接句子；来自数据、可能参与平衡调整的数值不得在 `*_desc` 译文中重复写死。
- 当前首批只维护简体中文 `zh_CN` 与英文 `en` 两种语言；新增语言另行决策。
- AI 负责为缺失的 `zh_CN` 或 `en` 自动生成首版译文，人工负责最终审校和润色。

## Godot 数据配表入口

Godot 中央主界面的“数据配表”把 `strings.csv` 作为完整可编辑数据集，并在带 `name_key` / `desc_key` 的普通 JSON/CSV 记录右侧直接显示中文与英文输入框。修改技能描述时，同一区域复用 `SkillDescriptionFormatter` 按真实技能参数和默认能力倍率解析占位符，避免译文数值与配置脱节。

全局搜索会索引 `strings.csv` 的 key、中文和英文，也会把关联译文并入普通内容记录的搜索上下文；模块制作数据和 VFX/profile 不进入该索引。未保存译文进入 `user://data_table_editor/` 草稿，只有与数据一起通过 hash 检查和 `DataLoader.validate_project_data()` 后才写入项目。直接编辑 CSV 仍受本手册全部格式、双语和占位符规则约束；详细流程见 `docs/代码/data_table_editor.md` 与 ADR #180。

## 快速上手

| 你想做什么 | 怎么做 |
|------------|--------|
| 加 UI 文案 | 在 `strings.csv` 加 `ui_*` key；代码使用 `tr("ui_xxx")` |
| 加标题 / 暂停 / 失败 / 结果面板文案 | 在 `strings.csv` 加 `ui_title_*`、`ui_start`、`ui_continue_run`、`ui_run_save_unavailable`、`ui_pause_title`、`ui_save_and_quit`、`ui_restart`、`ui_quit_to_title`、`ui_result_*` 等 key；结果清单行格式使用 `ui_result_resource_line` / `ui_result_gear_mod_line`，UI 代码使用 `tr()` |
| 加图鉴 / 内容解锁结果文案 | 在 `strings.csv` 加 `ui_codex_*` 与 `ui_result_new_unlock*` key；图鉴分类固定为智能碎片、Gear Mod、心象，锁定名使用 `ui_codex_locked`，进度 / rank / 新解锁数量必须保留约定占位符 |
| 加设置面板文案 | 在 `strings.csv` 加 `ui_settings_*` key；设置入口沿用 `ui_settings`，设置面板标题、分组、控件标签、反馈和选项都走本地化；无障碍、输入绑定选项也必须独立建 key |
| 加 HUD / 失败提示 | 在 `strings.csv` 加 `ui_hud_*`、`ui_difficulty_*`、`ui_stats_*` 或 `ui_*` key；HUD 代码用 `tr("ui_xxx")` 并在运行时刷新 |
| 加智能碎片名 / 描述 | 在 `strings.csv` 加遗留稳定 key `character_*_name` / `character_*_desc`；清理智能组合名使用 `character_composition_name_format` 的 `{main}` / `{sub}` 占位符；数据填 `name_key` / `desc_key` |
| 加元素 / 智能碎片被动文案 | 在 `strings.csv` 加 `element_*_name` 与遗留稳定 key `passive_*_name` / `passive_*_desc`；数据只引用 key；被动数值使用 `{param_<字段>...}` |
| 加武器名 / 描述 | 在 `strings.csv` 加 `weapon_*_name` / `weapon_*_desc`；数据填 `name_key` / `desc_key` |
| 加心象个体名 / 图鉴描述 | 在 `strings.csv` 加遗留稳定 key `enemy_*_name` / `enemy_*_desc`；`enemies.csv` 填 `name_key` / `desc_key` |
| 加遗物 / 道具名和描述 | 在 `strings.csv` 加 `relic_*_name` / `relic_*_desc`、`item_*_name` / `item_*_desc`；数据填 `name_key` / `desc_key` |
| 加技能名和描述 | 在 `strings.csv` 加 `skill_*_name` / `skill_*_desc`；`skills.json` 填 `name_key` / `desc_key`；消耗、范围、效果参数等使用下方配置占位符 |
| 加描述文本 | 在 `strings.csv` 加 `*_desc`；数据填 `desc_key`，可能调整的数值必须使用命名占位符并由配置注入 |
| 加装备 Mod / 局外装配 UI 文案 | 在 `strings.csv` 加 `gear_mod_*` / `ui_gear_mod_*` key，例如 Mod 名称、资源名称、标题入口、容量、费用、操作成功 / 失败反馈；Mod 描述保持定性，当前 rank 的实际修正值由通用 modifier 摘要显示；UI 代码使用 `tr("ui_xxx")` |
| 加开发者测试岛文案 | 在 `strings.csv` 加 `ui_debug_test_arena_*` key；该域只供独立 debug/dev_tools scene 的配装、区域标签、控制面板和伤害 HUD 使用，仍须维护 `zh_CN` / `en` 并按英文长度验收 |
| 加机关 / 危险物名 | 在 `strings.csv` 加 `hazard_*_name`；数据填 `name_key` |
| 改中文或英文翻译 | 只改对应语言列，不改 key；另一语言由 AI 自动补首版译文后人工复核 |
| 改 UI 布局或按钮文案 | 切到 `en` 验收宽度、换行和遮挡；英文长度是 UI 尺寸基准 |
| 新增语言 | 先新增决策，再给 `strings.csv` 加新语言列，并同步 Settings 语言选项与 Godot Localization 注册 |

## CSV 格式

当前文件：`client/locale/strings.csv`

```csv
keys,zh_CN,en
ui_settings,设置,Settings
ui_resume,继续,Resume
```

| 列 | 是否必填 | 说明 |
|----|----------|------|
| `keys` | 是 | Godot 本地化 key，必须唯一 |
| `zh_CN` | 是 | 简体中文译文 |
| `en` | 是 | 英文译文 |
| 其他语言列 | 可选 | 例如 `zh_TW` / `ja` / `ko`，新增前同步设置项和项目导入配置 |

格式规则：

- 文件使用 UTF-8 与 LF 换行。
- key 不改名；改名等于破坏所有引用，必须同步代码 / 数据 / 词表。
- 译文含逗号、换行或双引号时，按 CSV 规则用双引号包裹，并把内部双引号写成 `""`。
- `zh_CN` 与 `en` 是当前必填语言；新增 key 时两列都要填。
- 若用户只提供中文或英文，AI 必须自动补齐另一列首版译文；不得留空。
- 临时占位可以复制英文，但必须在人工校对清单里标出，不能长期留空。

## key 命名

权威来源：`docs/词表与契约.md` §6。

| 前缀 | 用途 | 示例 |
|------|------|------|
| `ui_` | UI、菜单、按钮、HUD | `ui_settings` / `ui_pause` |
| `ui_codex_` | 图鉴标题、分类、锁定状态、详情标签与本局暂存提示 | `ui_codex_category_character` / `ui_codex_requirement_progress` |
| `ui_result_` | 局终结果与新解锁汇总 | `ui_result_new_unlocks_header` / `ui_result_new_unlock_line` |
| `ui_settings_` | 设置面板标题、分组、控件标签和选项 | `ui_settings_master_volume` / `ui_settings_aim_mode_auto` |
| `ui_settings_input_` | 设置面板输入绑定动作标签 | `ui_settings_input_move_up` / `ui_settings_input_pause` |
| `ui_hud_` | 局内常驻 HUD 标签与短时状态 / 拾取反馈 | `ui_hud_life` / `ui_hud_kills` / `ui_hud_level` |
| `ui_difficulty_` | 难度 profile 名称、局内威胁等级、阶段与暂停状态 | `ui_difficulty_standard_name` / `ui_difficulty_level` / `ui_difficulty_stage_dormant` |
| `ui_stats_` | 局内详细数值面板标签 | `ui_stats_damage` / `ui_stats_skill_resource` |
| `ui_gear_mod_` | 装备 Mod 面板、标题入口和操作反馈 | `ui_gear_mod_title` / `ui_gear_mod_upgrade_cost` |
| `ui_debug_test_arena_` | 独立 debug/dev_tools 开发者测试岛、配装、控制面板和伤害 HUD | `ui_debug_test_arena_setup_title` / `ui_debug_test_arena_spawn` |
| `ui_credits_` | 致谢界面分组、角色和用途标签 | `ui_credits_section_staff` / `ui_credits_usage_engine_runtime` |
| `character_` | 智能碎片名称和描述；`character` 是不迁移的遗留内部前缀 | `character_primary_a_name` / `character_primary_b_name` |
| `element_` | 七元素名称 | `element_neutral_name` / `element_composite_ab_name` |
| `passive_` | 智能碎片被动名称和描述；`passive` key 保持稳定 | `passive_primary_a_guard_name` / `passive_primary_a_guard_desc` |
| `weapon_` | 武器名称和描述 | `weapon_basic_blaster_name` / `weapon_basic_blaster_desc` |
| `relic_` | 被动遗物名称和描述 | `relic_sharp_rounds_name` / `relic_sharp_rounds_desc` |
| `item_` | 主动道具 / 消耗品名称和描述 | `item_bomb_name` / `item_bomb_desc` |
| `skill_` | 技能名称和描述 | `skill_overdrive_rounds_name` / `skill_overdrive_rounds_desc` |
| `status_` | HUD 与状态观察中的状态名称 | `status_slow_name` / `status_vulnerable_name` |
| `gear_mod_` | 局内 Gear Mod 名称与描述 | `gear_mod_weapon_damage_test_name` / `gear_mod_weapon_damage_test_desc` |
| `enemy_` | 心象个体名称与图鉴描述；`enemy` 是不迁移的遗留内部前缀，显示名可随当前设计更新但 key 与内容 id 保持稳定 | `enemy_chaser_name` / `enemy_chaser_desc`；`enemy_spitter_name` 保留 key，当前译文为“突击枪手 / Assault Gunner” |
| `hazard_` | 机关 / 危险物名称 | `hazard_spike_trap_name` |
| `hint_` | 教程、提示、引导 | `hint_aim_with_right_stick` |

命名规则：

- 统一蛇形小写：`<域>_<对象>_<字段>`。
- 名称用 `_name`，描述用 `_desc`，提示可用 `_title` / `_body`。
- 不把语言写进 key；语言是 CSV 列，不是 key 后缀。
- 不复用语义不同的 key；即使中文一样，只要上下文不同就新建 key。

### 集体无意识 IP 的显示语义与遗留 key

- 正式客户端玩家文案使用“清理智能 / `Cleanup Intelligence`”“智能碎片 / `Intelligence Fragment`”“主智能碎片 / `Primary Fragment`”“副智能碎片 / `Secondary Fragment`”“心象 / `Mindform`”“意识层 / `Mind Layer`”和“意识核 / `Mind Core`”。
- `character_*`、`ui_hero_*`、`enemy_*`、`ui_stats_enemy_*`、`ui_*_kills` 与 `ui_difficulty_stage_nestfall` 是兼容代码、数据、存档和测试引用的遗留稳定 key；不得仅为匹配新 IP 显示词而改名。其译文分别显示智能碎片 / 清理智能、心象、清理统计与“失序 / `Disarray`”，不得把遗留 key 原样暴露给玩家。
- `{kills}` 仍是稳定统计占位符，正式客户端显示口径为“清理 / `Cleared`”；占位符改名属于接口变更，不随译文迁移。
- `ui_title_subtitle` 保留“集体无意识 / `Collective Unconscious`”非空备用译文；正式标题页当前只显示项目代号 `WASD`，副标题由界面层隐藏。
- `ui_debug_test_arena_*` 只属于开发者测试岛内部文案，可继续使用英雄、敌人、击杀等运行时术语；这不代表正式客户端玩家显示口径。

## 占位符规则

动态数值必须用命名占位符，不允许字符串拼接。

正确：

```csv
keys,zh_CN,en
relic_sharp_rounds_desc,伤害 +{value},Damage +{value}
ui_reward_choice_title,选择奖励,Choose Reward
```

错误：

```gdscript
label.text = tr("ui_damage") + str(value)
```

占位符规则：

- 同一个 key 的所有语言必须使用同一组占位符名。
- 占位符名用蛇形小写，如 `{value}`、`{count}`、`{seconds}`。
- 单位、数字顺序允许按语言调整，但占位符不能丢。
- 复数、性别、语序复杂的文本不要拼接；拆成独立 key 或后续引入更强格式化规则。
- 伤害、消耗、冷却、范围、持续时间、概率、层数、倍率等可能调整的数值必须来自配置与统一格式化器；禁止在 `*_desc` 译文中再写一份数字。只有不属于配置且不会参与平衡调整的固定语义数字可以直接写，仍应优先改写为自然语言。

### 技能与被动的配置占位符

`SkillDescriptionFormatter` 使用主智能碎片的能力属性解析 `skills.json`，并在清理智能组合选择界面格式化四槽技能；运行时 `SkillSystem` 与描述共用 `SkillValueResolver`，因此强度、范围、效率和持续时间的缩放结果一致。

| 占位符 | 来源 / 含义 |
|--------|-------------|
| `{cooldown}` | 技能 `cooldown` |
| `{target_radius}` | `targeting.radius`，已应用范围 |
| `{cost_<resource>}` | 对应资源成本，已应用效率与槽位成本倍率，例如 `{cost_energy}` |
| `{effect_<序号>_<参数>}` | 第 N 个 effect 的数值参数，已应用声明的能力缩放，例如 `{effect_1_duration}` |
| `{effect_<序号>_modifier_<序号>_<字段>}` | effect 内第 N 个 modifier 的数值字段，例如 `{effect_1_modifier_1_value_bonus_percent}` |
| `{param_<字段>}` | 被动 `params` 的数值字段，例如 `{param_multiplier}` |

每个数值 token 还可使用：

- `_percent`：原值乘 `100`，例如 `0.35 → 35`。
- `_bonus_percent`：相对 `1.0` 的增益百分比，例如 `1.35 → 35`。
- `_reduction_percent`：相对 `1.0` 的减免百分比，例如 `0.6 → 40`。

新增 token 时不应在格式化器里按 skill id / passive id 特判。`python tools/validate_data.py` 会拒绝配置无法提供的描述占位符；`zh_CN` / `en` 的占位符集合仍必须完全一致。

## 英文长度基准 / UI 适配规则

- UI 布局、按钮宽度、面板宽度、换行和 HUD 信息密度以英文 `en` 文案长度作为最小设计与验收基准；中文 `zh_CN` 信息密度高，不能作为唯一尺寸依据。
- 新增 / 修改玩家可见 UI 文案或 UI 布局时，必须切到英文检查按钮、面板标题、设置项、奖励选择、HUD、失败结算和局外成长界面不截断、不溢出、不互相遮挡。
- Godot UI 优先用 `Container`、锚点、`size_flags`、`custom_minimum_size`、`autowrap_mode` 和合理的响应式约束承接文本长度；避免按中文短文本写死窄宽。
- 英文太长时，优先调整布局宽度、换行、层级或控件分组；确需精简译文时，只能在不改变功能含义、数值承诺和语气边界的前提下改英文列。
- `python tools/godot_bridge.py --project client settings-smoke` 会在英文 locale 下检查现有可见按钮类控件的文本宽度；复杂视觉布局仍需按 `docs/测试策略.md` 的 L5 checklist 人工确认。

## 常见工作流

### AI 自动翻译工作流

1. 用户或设计文档给出中文文案时，AI 同步生成 `en` 首版译文。
2. 用户或参考资料给出英文文案时，AI 同步生成 `zh_CN` 首版译文。
3. AI 翻译必须保留所有 `{value}` / `{count}` 等占位符，且两种语言占位符集合一致。
4. AI 可按游戏语气润色，但不得改变数值含义、功能承诺、触发条件或稀有度表达。
5. 人工校对是最终权威；发现译文别扭时只改译文列，不改 key。

### 加一段 UI 文案

1. 在 `strings.csv` 新增一行，如 `ui_restart,重开,Restart`；若只给了一种语言，AI 先补齐另一种。
2. UI 代码使用 `tr("ui_restart")`。
3. 如果该 UI 支持运行时切语言，确认 `NOTIFICATION_TRANSLATION_CHANGED` 后会刷新。
4. 切到英文 `en` 检查按钮 / 面板不会截断、溢出或遮挡；必要时先调整 UI 尺寸或换行。
5. 加载界面使用通用 `ui_loading` / `ui_loading_failed`；只显示中性的“正在加载…” / “Loading…”，不要把资源阶段、百分比、技术错误或取消操作写给玩家。

### 加一段 HUD 文案

1. 在 `strings.csv` 新增 `ui_hud_*`、`ui_difficulty_*`、`ui_stats_*` 或局内交互提示 key，例如 `ui_hud_life,生命,Life` / `ui_difficulty_level,威胁 Lv. {level},Threat Lv. {level}` / `ui_stats_fire_rate,射速,Fire Rate` / `ui_interact_open_cache,按 {binding} 打开缓存箱,Press {binding} to open cache`。Gear Mod 实体拾取提示使用 `ui_interact_pickup_gear_mod`，必须同时保留 `{binding}`、`{name}`、`{rank}`、`{effect}`；满阶溢出提示改用 `ui_interact_pickup_gear_mod_overflow` 的 `{gold}`。世界事件完成后只显示“Gear Mod 已掉落”，不能提前显示“已获得”。威胁阶段名称使用 `ui_difficulty_stage_<stage>`，跨语言共用同一 key。
   难度 profile 显示名同样使用 `ui_difficulty_*_name`；当前标准 profile 固定引用 `ui_difficulty_standard_name`（“标准 / Standard”），不得把显示名写进 `difficulty_profiles.json`。
2. HUD 代码只显示 `tr("ui_hud_life")` / `tr("ui_stats_fire_rate")` 和格式化数值，不硬编码玩家可见标签。
3. 若 HUD 会常驻局内或按住显示，手动切语言时要确认标签刷新；当前 Gameplay HUD 会订阅 `Localization.locale_changed` 并用缓存生命、清理数、难度时间、威胁阶段、等级、金币余额 / 进度、详细数值、等级 / 奖励反馈和交互提示重画。

### 加一个设置面板控件文案

1. 在 `strings.csv` 新增 `ui_settings_*` key，例如：

```csv
ui_settings_screen_shake,屏幕震动,Screen Shake
ui_settings_screen_flashes,屏幕闪烁,Screen Flashes
```

2. `SettingsPanel` 使用 `tr("ui_settings_screen_shake")` 刷新控件文本。
3. 如果控件有枚举选项，每个选项也单独建 key，例如 `ui_settings_aim_mode_mouse` / `ui_settings_aim_mode_4dir` / `ui_settings_aim_mode_auto`。
4. 如果新增了 key，先让 Godot 重新导入 `strings.csv` 生成 `strings.zh_CN.translation` / `strings.en.translation`。
5. 新设置控件只有在已有下游系统即时生效时才显示给玩家；仅预留的设置 key 可以保留文案，但面板应隐藏或禁用。
6. 修改后运行 `python tools/godot_bridge.py --project client settings-smoke`，确认新增 key 已导入 `.translation` 并能在面板中解析。
7. 在 `en` 下确认控件标签、选项、反馈和按钮能完整显示；英文长度不应被中文密度掩盖。

### 加一个输入绑定标签

1. 在 `strings.csv` 新增 `ui_settings_input_*` key，例如：

```csv
ui_settings_input_pause,暂停,Pause
```

2. `SettingsPanel` 的绑定动作名称使用该 key；键名选项（如 `W` / `Escape`）来自 `Settings.input_binding_options()`，不作为普通 UI 句子翻译。
3. 四技能槽与冲刺固定使用 `ui_settings_input_skill_1`～`ui_settings_input_skill_4`、`ui_settings_input_dash`；旧主动道具 action 不再占用输入绑定。
4. 输入绑定反馈、共用键位提示和恢复默认按钮使用 `ui_settings_input_feedback_*` / `ui_settings_input_restore_defaults`。
5. 同步 `docs/词表与契约.md` 的 `input.*` key / action 后运行 `python tools/sync_contracts.py --check`、`python tools/validate_data.py` 与 `python tools/godot_bridge.py --project client settings-smoke`。

### 加一个致谢条目

1. 在 `client/data/credits.json` 新增条目；人名、项目名、URL、许可证名和版权声明保持原文。
2. 若需要新的分组标题、角色或用途标签，在 `strings.csv` 新增 `ui_credits_*` key，并补齐 `zh_CN` / `en`。
3. 同步根目录 `CREDITS.md`，发行前人工复核许可证和 notice 要求。

### 加一个遗物名称和描述

1. 在 `strings.csv` 新增：

```csv
relic_sharp_rounds_name,锋利弹头,Sharp Rounds
relic_sharp_rounds_desc,伤害 +{value},Damage +{value}
```

2. 在 `client/data/relics.json` 使用：

```json
{
  "id": "relic_sharp_rounds",
  "name_key": "relic_sharp_rounds_name",
  "desc_key": "relic_sharp_rounds_desc"
}
```

3. 代码显示时通过 key 查译文，不直接读取硬文本。

### 加一个装备 Mod 名称和描述

1. 在 `strings.csv` 新增 `gear_mod_<id>_name` / `gear_mod_<id>_desc`，例如：

```csv
gear_mod_weapon_recoil_damper_name,反冲阻尼,Recoil Dampener
gear_mod_weapon_recoil_damper_desc,降低主武器后坐力。,Reduces primary weapon recoil.
gear_mod_weapon_spread_stabilizer_name,弹道稳定器,Ballistic Stabilizer
gear_mod_weapon_spread_stabilizer_desc,降低主武器弹道扩散。,Reduces primary weapon projectile spread.
```

2. `gear_mods.json` 只引用对应 `name_key` / `desc_key`；描述说明用途，不重复写死 rank、倍率或百分比。
3. 当前 rank 的实际加成或减免由装备 Mod 面板的通用 modifier 摘要格式化，避免数据升级后译文中的数值失真。

### 加图鉴与解锁结果文案

1. 图鉴入口与标题使用 `ui_codex` / `ui_codex_title`；三个首版分类固定使用 `ui_codex_category_character`、`ui_codex_category_gear_mod`、`ui_codex_category_enemy`。
2. 未解锁名称统一显示 `ui_codex_locked` 的 `???`。通用要求进度使用 `ui_codex_requirement_progress`；具体计数器分别映射到 `ui_codex_requirement_runs_ended`、`ui_codex_requirement_runs_completed`、`ui_codex_requirement_character_run_completed`、`ui_codex_requirement_enemy_defeated_total` 与 `ui_codex_requirement_enemy_defeated`，组合模式使用 `ui_codex_requirement_mode_all` / `ui_codex_requirement_mode_any`。两种语言都必须保留对应的 `{subject}`、`{current}`、`{target}`；本局暂存提示使用 `ui_codex_pending_preview` 的 `{count}`。
3. Gear Mod rank 范围使用 `ui_codex_gear_rank` 的 `{min_rank}` / `{max_rank}`；槽位与稀有度显示通过 `ui_codex_slot_<slot>` / `ui_codex_rarity_<rarity>` 映射，不把契约 id 直接暴露给玩家。
4. 局终新解锁结果使用 `ui_result_new_unlocks_header`、`ui_result_new_unlock_line` 的 `{name}` 与 `ui_result_new_unlocks_summary` 的 `{count}`；同一 key 的中英文占位符集合必须完全一致。
5. 心象图鉴正文使用 `enemy_*_desc`，由 `enemies.csv.desc_key` 引用；智能碎片与 Gear Mod 继续复用各自已有 `*_desc`。

### 加一个世界事件

1. 在 `strings.csv` 新增 `world_event_<id>_name` / `world_event_<id>_desc`，并为交互、忙碌、成功、失败和奖励反馈复用或新增 `ui_world_event_*` key。
2. 价格、献祭比例、剩余时间、波次、目标生命与占领进度必须使用命名占位符；`zh_CN` / `en` 的占位符集合完全一致，数值仍以 `world_events.json` 为唯一来源。
3. `world_events.json` 只引用 `name_key` / `desc_key`；运行时通过 `tr()` 与 context 格式化，语言即时切换时重新渲染 HUD 和交互提示。
4. 运行 `validate_data`、`world_event_smoke`、`module-world-smoke`，并以中英文分别检查长价格、目标生命和占点双进度不会截断。

### 新增语言

1. 在 `strings.csv` 表头新增语言列，如 `ja`。
2. 给每个 key 补齐该列译文。
3. 更新 `docs/词表与契约.md` 中 `general.locale` 的取值范围。
4. 更新 `Settings` 语言选项、`SettingsPanel` 语言选项与 Godot Project Settings 的 Localization 注册。
5. 运行 `python tools/validate_data.py`，确认 key 唯一、必填语言非空、占位符一致。
6. 人工切换语言检查 UI、道具名、描述、设置菜单和失败 / 结算面板。

## 人工校对清单

- [ ] `keys` 是否唯一且命名符合词表 §6？
- [ ] `zh_CN` 与 `en` 是否都有译文？
- [ ] AI 自动补译的内容是否经过人工复核，且没有误改功能含义？
- [ ] 所有语言的占位符集合是否一致？
- [ ] 描述中的可调数值是否全部来自配置占位符，没有在 `*_desc` 中重复硬编码？
- [ ] 新增 / 修改 UI 文案或布局是否已按英文 `en` 长度验收，无截断、溢出或遮挡？
- [ ] 是否已运行 `python tools/validate_data.py`？
- [ ] 数据文件是否只引用 `name_key` / `desc_key`，没有硬文本？
- [ ] 代码是否只使用 `tr("key")`，没有玩家可见硬文本？
- [ ] 新语言是否同步设置项、设置面板语言选项、Godot Localization 和字体覆盖？

## 与数值配置的关系

- 数值字段、概率、倍率、敌人属性等去 `client/data/` 配置。
- 文案只在 `client/locale/strings.csv` 配置。
- 数据文件用 key 把二者连接起来，例如 `desc_key` 指向含 `{value}` 占位符的译文，实际数值来自 `client/data/` 的 CSV / JSON。
