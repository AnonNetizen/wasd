# 多语言文案配置手册

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`、`docs/游戏设计文档.md` §9.4 与 `docs/词表与契约.md` §6。
> 本文档是完整项目 `client/locale/` 的人工多语言文案配置手册；新增语言、改 CSV 格式、改 key 命名规则、改占位符约定或新增文案域时，必须同步 GDD、词表、AI导航、任务模板和相关 UI / 数据模块文档。

---

## 目标

- 所有面向玩家的文本集中在 `client/locale/strings.csv`，便于人工翻译和校对。
- 代码和数据只引用 key：代码用 `tr("key")`，数据用 `name_key` / `desc_key` 等字段。
- 同一行维护多语言译文，避免每种语言散落在不同文件里难以对照。
- 动态数值使用占位符，禁止在代码里拼接句子。
- 当前首批只维护简体中文 `zh_CN` 与英文 `en` 两种语言；新增语言另行决策。
- AI 负责为缺失的 `zh_CN` 或 `en` 自动生成首版译文，人工负责最终审校和润色。

## 快速上手

| 你想做什么 | 怎么做 |
|------------|--------|
| 加 UI 文案 | 在 `strings.csv` 加 `ui_*` key；代码使用 `tr("ui_xxx")` |
| 加标题 / 暂停 / 失败面板文案 | 在 `strings.csv` 加 `ui_title_*`、`ui_start`、`ui_continue_run`、`ui_run_save_unavailable`、`ui_pause_title`、`ui_save_and_quit`、`ui_restart`、`ui_quit_to_title` 等 key；UI 代码使用 `tr()` |
| 加 HUD / 失败提示 | 在 `strings.csv` 加 `ui_hud_*` 或 `ui_*` key；HUD 代码用 `tr("ui_xxx")` 并在运行时刷新 |
| 加角色名 / 描述 | 在 `strings.csv` 加 `character_*_name` / `character_*_desc`；数据填 `name_key` / `desc_key` |
| 加武器名 / 描述 | 在 `strings.csv` 加 `weapon_*_name` / `weapon_*_desc`；数据填 `name_key` / `desc_key` |
| 加敌人名 | 在 `strings.csv` 加 `enemy_*_name`；`enemies.csv` 填 `name_key` |
| 加遗物 / 道具名和描述 | 在 `strings.csv` 加 `relic_*_name` / `relic_*_desc`、`item_*_name` / `item_*_desc`；数据填 `name_key` / `desc_key` |
| 加描述文本 | 在 `strings.csv` 加 `*_desc`；数据填 `desc_key`，动态数值用 `{value}` 这类占位符 |
| 加局外成长文案 | 在 `strings.csv` 加 `meta_*_name` / `meta_*_desc`；`meta_progression.json` 填 `name_key` / `desc_key` |
| 加机关 / 危险物名 | 在 `strings.csv` 加 `hazard_*_name`；数据填 `name_key` |
| 改中文或英文翻译 | 只改对应语言列，不改 key；另一语言由 AI 自动补首版译文后人工复核 |
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
| `ui_hud_` | 局内 HUD 标签 | `ui_hud_life` / `ui_hud_kills` |
| `ui_credits_` | 致谢界面分组、角色和用途标签 | `ui_credits_section_staff` / `ui_credits_usage_engine_runtime` |
| `character_` | 角色名称和描述 | `character_default_name` / `character_default_desc` |
| `weapon_` | 武器名称和描述 | `weapon_basic_blaster_name` / `weapon_basic_blaster_desc` |
| `relic_` | 被动遗物名称和描述 | `relic_sharp_rounds_name` / `relic_sharp_rounds_desc` |
| `item_` | 主动道具 / 消耗品名称和描述 | `item_bomb_name` / `item_bomb_desc` |
| `enemy_` | 敌人名称 | `enemy_chaser_name` / `enemy_swarm_name` |
| `hazard_` | 机关 / 危险物名称 | `hazard_spike_trap_name` |
| `hint_` | 教程、提示、引导 | `hint_aim_with_right_stick` |
| `meta_` | 局外货币、永久升级、账号等级、解锁项 | `meta_upgrade_damage_name` / `meta_currency_essence_name` |

命名规则：

- 统一蛇形小写：`<域>_<对象>_<字段>`。
- 名称用 `_name`，描述用 `_desc`，提示可用 `_title` / `_body`。
- 不把语言写进 key；语言是 CSV 列，不是 key 后缀。
- 不复用语义不同的 key；即使中文一样，只要上下文不同就新建 key。

## 占位符规则

动态数值必须用命名占位符，不允许字符串拼接。

正确：

```csv
keys,zh_CN,en
relic_sharp_rounds_desc,伤害 +{value},Damage +{value}
ui_level_up_choices,选择 {count} 个升级奖励,Choose {count} level-up reward
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

### 加一段 HUD 文案

1. 在 `strings.csv` 新增 `ui_hud_*` key，例如 `ui_hud_life,生命,Life`。
2. HUD 代码只显示 `tr("ui_hud_life")` 和格式化数值，不硬编码玩家可见标签。
3. 若 HUD 会常驻局内，手动切语言时要确认标签刷新；F4 临时 HUD 当前在启动时读取本地化文本。

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

### 加一个局外成长节点

1. 在 `strings.csv` 新增名称和描述：

```csv
meta_upgrade_damage_name,淬火弹芯,Tempered Rounds
meta_upgrade_damage_desc,永久提升基础伤害,Permanently increases base damage
```

2. 在 `client/data/meta_progression.json` 的 `upgrade_tracks` 中引用：

```json
{
  "id": "meta_upgrade_damage",
  "name_key": "meta_upgrade_damage_name",
  "desc_key": "meta_upgrade_damage_desc"
}
```

3. 若新增了货币、升级轨道或解锁 id，先登记 `docs/词表与契约.md` §13。

### 新增语言

1. 在 `strings.csv` 表头新增语言列，如 `ja`。
2. 给每个 key 补齐该列译文。
3. 更新 `docs/词表与契约.md` 中 `general.locale` 的取值范围。
4. 更新 `Settings` 语言选项与 Godot Project Settings 的 Localization 注册。
5. 运行 `python tools/validate_data.py`，确认 key 唯一、必填语言非空、占位符一致。
6. 人工切换语言检查 UI、道具名、描述、设置菜单和失败 / 结算面板。

## 人工校对清单

- [ ] `keys` 是否唯一且命名符合词表 §6？
- [ ] `zh_CN` 与 `en` 是否都有译文？
- [ ] AI 自动补译的内容是否经过人工复核，且没有误改功能含义？
- [ ] 所有语言的占位符集合是否一致？
- [ ] 是否已运行 `python tools/validate_data.py`？
- [ ] 数据文件是否只引用 `name_key` / `desc_key`，没有硬文本？
- [ ] 代码是否只使用 `tr("key")`，没有玩家可见硬文本？
- [ ] 新语言是否同步设置项、Godot Localization 和字体覆盖？

## 与数值配置的关系

- 数值字段、概率、倍率、敌人属性等去 `client/data/` 配置。
- 文案只在 `client/locale/strings.csv` 配置。
- 数据文件用 key 把二者连接起来，例如 `desc_key` 指向含 `{value}` 占位符的译文，实际数值来自 `client/data/` 的 CSV / JSON。
