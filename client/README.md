# 正式客户端（client）

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式 Godot 客户端入口与运行说明；改项目启动方式、目录结构或验证命令时，必须同步 `README.md`、`docs/AI导航.md`、`docs/正式项目工作规划.md`、`docs/AI记忆/current_state.json`。

`client/` 是完整项目的 Godot 4.7.1 stable 项目根，即 Godot 内的 `res://`。

当前阶段为 F11 装备 Mod / 局外装配推进中：正式工程当前使用 Godot 4.7.1 stable，F1-F8 当前验收基线已完成，F9 已预留本地数据包式 `ModLoader`、Steam 优先 `PlatformServices`，以及 debug/dev_tools 专用 `DebugConsole` / `GMCommandRegistry`。启动场景在数据校验通过后会显示最小标题界面，开始后进入战斗 runtime；若存在 `SaveManager` 的 `run` 存档，标题菜单会显示“继续游戏”，续局读取失败时会提示本局存档已重置；标题菜单常驻“装备 Mod”和“设置”入口，可配置英雄 / 武器两套 Gear Mod，或打开设置面板修改语言、音量、显示、玩法和隐私开关。当前 runtime 覆盖玩家移动与居中相机、默认起始武器、池化子弹、两种池化敌人、`spawn_waves.csv` 刷怪、`Combat.apply_damage()` 伤害入口、经验 / 升级选择、升级获得反馈、响应式基础 HUD、主动暂停、暂停设置入口、暂停保存退出、标题继续游戏、暂停 / 升级 UI 恢复点、失败摘要、`meta.gear_mods` profile roundtrip、标题装备 Mod 面板和 Gear Mod 下一局 hero / weapon modifier snapshot；死亡后只展示本局击杀、时长、重开和回标题，不再写旧局外货币 / 账号经验。`Settings` 已有 `user://settings.cfg` 持久化、正式设置面板和 `settings-smoke` 验证，`SaveManager` 的 `run` kind 已有 version 2 迁移与 `save-smoke` 可靠性验证，`GearModSystem` 已有 `gear-mod-smoke` 装配 / UI 验证；项目尚未上线，不维护旧测试档迁移或旧 `purchased_upgrades` 补偿。DebugTools 已有 `debug-tools-smoke` 与 release guard smoke，Replay / golden replay / perf-probe 已作为内容扩展的回归护栏。项目当前只设计 / 验收固定 16:9 分辨率，默认 viewport 为 1920×1080，窗口不允许任意拖拽缩放，并通过 `canvas_items + keep` 在非 16:9 屏幕上等比缩放、补上下或左右黑边；其他宽高比留作未来按独立固定预设接入的优化项。

## 目录

| 路径 | 用途 |
|------|------|
| `project.godot` | 正式 Godot 项目配置 |
| `scenes/` | 正式项目场景 |
| `scripts/` | 正式项目 GDScript |
| `scripts/debug/` | debug/dev_tools 专用控制台与 GM 命令注册表；正式 release 不应加载或导出 |
| `data/` | 数值与复杂配置，说明见 `client/data/README.md` |
| `locale/` | 本地化表，说明见 `client/locale/README.md` |
| `assets/` | 美术、音频等资源 |
| `templates/` | 新内容脚手架模板 |
| `tools/` | 项目内 Godot headless smoke 脚本 |

## Autoload

已注册以下全局单例：

| 名称 | 脚本 | 作用 |
|------|------|------|
| `ModLoader` | `res://scripts/autoload/mod_loader.gd` | 本地 mod manifest 扫描、诊断和声明式数据 patch 入口 |
| `DataLoader` | `res://scripts/autoload/data_loader.gd` | JSON / CSV 数据读取与 `_contracts.json` 契约缓存 |
| `RNG` | `res://scripts/autoload/rng.gd` | 确定性随机子流 |
| `GameState` | `res://scripts/autoload/game_state.gd` | 全局流程状态与暂停联动 |
| `GameClock` | `res://scripts/autoload/game_clock.gd` | 玩法时间、tick 与时间缩放 |
| `PlatformServices` | `res://scripts/autoload/platform_services.gd` | Steam 优先的平台能力门面；当前空后端安全退化 |
| `Settings` | `res://scripts/autoload/settings.gd` | 设置默认值、契约校验、类型 / 范围校验、`user://settings.cfg` 持久化与变更广播 |
| `Analytics` | `res://scripts/autoload/analytics.gd` | 已登记事件的本地内存缓冲与隐私开关联动 |
| `Replay` | `res://scripts/autoload/replay.gd` | 输入 / 关键决策的内存态回放录制边界 |
| `PoolManager` | `res://scripts/autoload/pool_manager.gd` | 高频实体对象池注册、获取、释放、统计与溢出埋点 |
| `SaveManager` | `res://scripts/autoload/save_manager.gd` | `meta` / `run` / `replay_index` 存档 envelope、原子写入、备份回退、迁移与坏档隔离 |
| `GearModSystem` | `res://scripts/autoload/gear_mod_system.gd` | 装备 Mod profile、资源、库存、英雄 / 武器 loadout、掉落、升级、分解和下一局 modifier snapshot |
| `AudioManager` | `res://scripts/autoload/audio_manager.gd` | SFX / voice / music 注册、播放入口、Bus 路由与音量设置同步 |
| `Localization` | `res://scripts/autoload/localization.gd` | 当前语言、语言切换与翻译入口 |
| `UIManager` | `res://scripts/autoload/ui_manager.gd` | UI 场景栈与暂停 UI 联动 |
| `Combat` | `res://scripts/combat/combat.gd` | 统一伤害入口，`DamageInfo` 载荷定义在 `res://scripts/combat/damage_info.gd` |

## 启动

用 Godot 4.7.1 stable 打开：

```powershell
godot --path client
```

Headless 启动验证：

```powershell
python tools/godot_bridge.py --project client headless-boot
```

F4 最小运行时 smoke：

```powershell
python tools/godot_bridge.py --project client runtime-smoke
```

F11 装备 Mod smoke：

```powershell
python tools/godot_bridge.py --project client gear-mod-smoke
```

F7 设置持久化 smoke：

```powershell
python tools/godot_bridge.py --project client settings-smoke
```

F5 存档可靠性 smoke：

```powershell
python tools/godot_bridge.py --project client save-smoke
```

DebugTools / GM 指令 smoke：

```powershell
python tools/godot_bridge.py --project client debug-tools-smoke
python tools/godot_bridge.py --project client debug-tools-release-smoke
```

若本机没有系统 Python，可使用 Codex 桌面内置 Python 路径运行同一命令。

## 当前启动场景

`res://scenes/boot/main.tscn` 挂载 `res://scripts/boot/formal_client_boot.gd`。启动脚本会先执行正式数据 schema smoke 并输出日志；若校验通过，会显示最小标题界面；开始新局会挂载 `res://scripts/gameplay/gameplay_run_loop.gd`，继续游戏会先从 `SaveManager` 读取 `run` payload 再挂载同一 runtime，并按 payload 的 `ui_restore` 回到普通游玩、暂停菜单或升级选择面板；读取失败或坏档被隔离时会回到标题菜单并显示本局存档重置提示；装备 Mod 会通过 `UIManager` 把 `GearModPanel` 叠在标题菜单上，设置入口会把 `SettingsPanel` 叠在标题菜单或暂停菜单上。死亡后 gameplay runtime 会清理旧 `run` 并显示失败摘要，不再写旧局外结算。debug/dev_tools 构建中，启动脚本会动态加载 `res://scripts/debug/debug_console.gd`，用 F1 或反引号打开 GM 控制台；正式 release 构建不应启用 `dev_tools`，也不应导出 `res://scripts/debug/*`。

Gameplay runtime 的稳定结构已迁入 `client/scenes/gameplay/*.tscn` 与 `client/scenes/ui/*.tscn`，文档见 `docs/代码/gameplay_runtime.md`、`docs/代码/gear_mod_system.md` 与 `docs/代码/debug_tools.md`。它不迁移 MVP 临时代码；当前实现 `run` 暂停保存续局、暂停 / 升级 UI 恢复点、坏档提示、v1 -> v2 迁移、失败摘要、标题装备 Mod 配置、`meta.gear_mods` 存档验证和调试专用 GM 指令入口。完整局外包装、更多内容切片、更多 replay 场景和平衡 sim 属于后续工作。
