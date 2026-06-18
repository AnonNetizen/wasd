# 正式客户端（client）

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式 Godot 客户端入口与运行说明；改项目启动方式、目录结构或验证命令时，必须同步 `README.md`、`docs/AI导航.md`、`docs/正式项目工作规划.md`、`docs/AI记忆/current_state.json`。

`client/` 是完整项目的 Godot 4.6.3 项目根，即 Godot 内的 `res://`。

当前阶段为 F4 最小可玩闭环首切片：正式工程已可启动，F2 横向 autoload 矩阵与 F3 数据 / 契约闭环已通过验收，启动场景在数据校验通过后会显示最小标题界面，开始后进入战斗 runtime。当前 runtime 覆盖玩家移动与居中相机、默认起始武器、池化子弹、两种池化敌人、`spawn_waves.csv` 刷怪、`Combat.apply_damage()` 伤害入口、经验 / 升级选择、升级获得反馈、响应式基础 HUD 和失败后的重开 / 回标题面板。项目默认 viewport 为 1920×1080，窗口不允许任意拖拽缩放，并通过 `canvas_items + keep` 在比例不匹配时保比例加黑边。

## 目录

| 路径 | 用途 |
|------|------|
| `project.godot` | 正式 Godot 项目配置 |
| `scenes/` | 正式项目场景 |
| `scripts/` | 正式项目 GDScript |
| `data/` | 数值与复杂配置，说明见 `client/data/README.md` |
| `locale/` | 本地化表，说明见 `client/locale/README.md` |
| `assets/` | 美术、音频等资源 |
| `templates/` | 新内容脚手架模板 |
| `tools/` | 项目内 Godot headless smoke 脚本 |

## Autoload

已注册以下全局单例：

| 名称 | 脚本 | 作用 |
|------|------|------|
| `DataLoader` | `res://scripts/autoload/data_loader.gd` | JSON / CSV 数据读取与 `_contracts.json` 契约缓存 |
| `RNG` | `res://scripts/autoload/rng.gd` | 确定性随机子流 |
| `GameState` | `res://scripts/autoload/game_state.gd` | 全局流程状态与暂停联动 |
| `GameClock` | `res://scripts/autoload/game_clock.gd` | 玩法时间、tick 与时间缩放 |
| `Settings` | `res://scripts/autoload/settings.gd` | 设置默认值、契约校验与变更广播 |
| `Analytics` | `res://scripts/autoload/analytics.gd` | 已登记事件的本地内存缓冲与隐私开关联动 |
| `Replay` | `res://scripts/autoload/replay.gd` | 输入 / 关键决策的内存态回放录制边界 |
| `PoolManager` | `res://scripts/autoload/pool_manager.gd` | 高频实体对象池注册、获取、释放、统计与溢出埋点 |
| `SaveManager` | `res://scripts/autoload/save_manager.gd` | `meta` / `run` / `replay_index` 存档 envelope、原子写入、备份回退、迁移与坏档隔离 |
| `AudioManager` | `res://scripts/autoload/audio_manager.gd` | SFX / voice / music 注册、播放入口、Bus 路由与音量设置同步 |
| `Localization` | `res://scripts/autoload/localization.gd` | 当前语言、语言切换与翻译入口 |
| `UIManager` | `res://scripts/autoload/ui_manager.gd` | UI 场景栈与暂停 UI 联动 |
| `Combat` | `res://scripts/combat/combat.gd` | 统一伤害入口，`DamageInfo` 载荷定义在 `res://scripts/combat/damage_info.gd` |

## 启动

用 Godot 4.6.3 打开：

```powershell
godot --path client
```

Headless 启动验证：

```powershell
python tools/godot_bridge.py --project client headless-boot
```

F4 最小运行时 smoke：

```powershell
python tools/godot_bridge.py --project client f4-smoke
```

若本机没有系统 Python，可使用 Codex 桌面内置 Python 路径运行同一命令。

## 当前启动场景

`res://scenes/boot/main.tscn` 挂载 `res://scripts/boot/formal_client_boot.gd`。启动脚本会先执行正式数据 schema smoke 并输出日志；若校验通过，会挂载 `res://scripts/gameplay/f4_run_loop.gd` 进入 F4 最小可玩闭环。

F4 runtime 当前仍是阶段性实现，文档见 `docs/代码/f4_min_playable_loop.md`。它不迁移 MVP 临时代码，不实现 F5+ 的暂停保存续局、完整主菜单、局外成长、黄金回放或平衡 sim。
