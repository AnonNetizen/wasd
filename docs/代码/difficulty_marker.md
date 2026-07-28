# DifficultyMarker 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是局内威胁难度标记器的场景、布局和文案契约；改节点、公开 API、阶段文案或详细面板字段时必须同步 Gameplay Runtime、Locale 手册和测试策略。

## 职责

- `DifficultyMarker` 是 `GameplayHud` 下的场景化 `PanelContainer`，位于右上角模块小地图下方。
- 它只展示 RunLoop 提供的 difficulty snapshot，不自行推进时间、不读取敌人、不解释增长公式。
- 常驻显示 `MM:SS`、`威胁 Lv. X`、阶段名称和当前 90 秒段的进度；详细倍率只出现在按住显示的详细数值面板。
- 起点房额外显示“难度时间暂停 / 武器与技能锁定”，但不宣称安全或无敌。

## 代码与场景

| 路径 | 作用 |
|------|------|
| `client/scenes/ui/difficulty_marker.tscn` | 面板、时间 / 等级 / 阶段 label、ProgressBar 和锁定提示 |
| `client/scripts/ui/difficulty_marker.gd` | snapshot 渲染、阶段配色、等级高亮、语言刷新 |
| `client/scenes/gameplay/gameplay_hud.tscn` | 在 `Root/DifficultyMarker` 实例化 |
| `client/scripts/gameplay/gameplay_hud.gd` | `set_difficulty_snapshot()`、详细面板字段、与 StatsPanel 避让 |
| `client/locale/strings.csv` | 标题、锁定提示、9 个阶段名和倍率标签 |

## 阶段名称

| 等级 | 中文 | 英文 |
|------|------|------|
| 1 | 蛰伏 | Dormant |
| 2 | 警戒 | Alert |
| 3 | 搜猎 | Hunt |
| 4 | 交火 | Clash |
| 5 | 围剿 | Siege |
| 6 | 致命 | Lethal |
| 7 | 失控 | Unbound |
| 8 | 崩坏 | Collapse |
| 9+ | 巢灾 | Nestfall |

等级数字和分段进度无限增长；Lv.9 后只固定名称，不封顶数值。

## API

| API | 输入 | 作用 |
|-----|------|------|
| `GameplayHud.set_difficulty_snapshot(snapshot, combat_locked)` | DifficultyProgression snapshot、锁定状态 | 缓存并刷新 marker / 详细面板 |
| `DifficultyMarker.set_snapshot(snapshot, combat_locked)` | 同上 | 刷新时间、等级、阶段、进度、锁定提示和阶段样式 |
| `DifficultyMarker.refresh_locale()` | 无 | 用缓存 key 即时重画当前语言 |

snapshot 至少包含 `elapsed`、`difficulty_level`、`progress`、`name_key`、`health_multiplier`、`damage_multiplier`。

## 布局与无障碍

- 默认矩形在小地图下方；StatsPanel 打开时移到面板左侧，避免右上角相互覆盖。
- 阶段信息同时使用文字、等级数字、刻度和颜色，不依赖色相单独表达。
- 正常模式跨级时有 0.22 秒轻量非模态缩放 / 描边高亮，不占用 UI 栈、不暂停游戏。
- ADR #168 后跨级始终播放上述高亮，不再存在低动态替代分支。
- 语言切换由 `Localization.locale_changed` 驱动，现有节点原地刷新。

## 详细数值面板

新增两行：

- `ui_stats_enemy_health_multiplier`：新生成敌人生命倍率。
- `ui_stats_enemy_damage_multiplier`：新生成敌人伤害倍率。

它们显示当前出生快照值并使用 `×` 格式；常驻 marker 不展示公式。

## 验证

- `headless-boot` / `runtime-smoke` / `settings-smoke` 验证场景绑定、语言与设置隔离。
- 手动在 1920×1080 检查中英文、小地图与 StatsPanel 遮挡、Lv.9 以上长等级、进度条和起点提示。
- 阶段色修改时必须保留文字、数字和刻度三种非色相信息。
