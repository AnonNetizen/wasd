# 正式客户端（client）

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式 Godot 客户端入口与运行说明；改项目启动方式、目录结构或验证命令时，必须同步 `README.md`、`docs/AI导航.md`、`docs/正式项目工作规划.md`、`docs/AI记忆/current_state.json`。

`client/` 是完整项目的 Godot 4.6.3 项目根，即 Godot 内的 `res://`。

当前阶段为 F6 局外成长首切片：正式工程已可启动，F2 横向 autoload 矩阵、F3 数据 / 契约闭环、F4 最小可玩闭环和 F5 暂停 / 存档 / 续局已通过阶段验证。启动场景在数据校验通过后会显示最小标题界面，开始后进入战斗 runtime；若存在 `SaveManager` 的 `run` 存档，标题菜单会显示“继续游戏”，续局读取失败时会提示本局存档已重置；标题菜单常驻“局外升级”入口，可查看余额、账号等级和升级轨道并购买永久升级。当前 runtime 覆盖玩家移动与居中相机、默认起始武器、池化子弹、两种池化敌人、`spawn_waves.csv` 刷怪、`Combat.apply_damage()` 伤害入口、经验 / 升级选择、升级获得反馈、响应式基础 HUD、主动暂停、暂停保存退出、标题继续游戏、暂停 / 升级 UI 恢复点、死亡结算、`meta` profile roundtrip、结算页最小购买、标题局外升级面板和下一局永久 modifiers。`SaveManager` 的 `run` kind 已有 version 2 迁移与 `save-smoke` 可靠性验证，`MetaProgressionSystem` 已有 `meta-smoke` 局外成长验证。项目默认 viewport 为 1920×1080，窗口不允许任意拖拽缩放，并通过 `canvas_items + keep` 在比例不匹配时保比例加黑边。

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
| `MetaProgressionSystem` | `res://scripts/autoload/meta_progression_system.gd` | 局外成长 profile、结算奖励、升级购买、解锁和永久 modifiers |
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

F6 局外成长 smoke：

```powershell
python tools/godot_bridge.py --project client meta-smoke
```

F5 存档可靠性 smoke：

```powershell
python tools/godot_bridge.py --project client save-smoke
```

若本机没有系统 Python，可使用 Codex 桌面内置 Python 路径运行同一命令。

## 当前启动场景

`res://scenes/boot/main.tscn` 挂载 `res://scripts/boot/formal_client_boot.gd`。启动脚本会先执行正式数据 schema smoke 并输出日志；若校验通过，会显示 F4/F5/F6 阶段最小标题界面；开始新局会挂载 `res://scripts/gameplay/f4_run_loop.gd`，继续游戏会先从 `SaveManager` 读取 `run` payload 再挂载同一 runtime，并按 payload 的 `ui_restore` 回到普通游玩、暂停菜单或升级选择面板；读取失败或坏档被隔离时会回到标题菜单并显示本局存档重置提示；局外升级会通过 `UIManager` 把 `MetaProgressionPanel` 叠在标题菜单上。死亡后 F4 runtime 会通过 `MetaProgressionSystem` 写入 `meta` profile 并清理旧 `run`。

F4/F5/F6 runtime 当前仍是阶段性实现，文档见 `docs/代码/f4_min_playable_loop.md` 与 `docs/代码/meta_progression_system.md`。它不迁移 MVP 临时代码；当前实现 `run` 暂停保存续局、暂停 / 升级 UI 恢复点、坏档提示、v1 -> v2 迁移、死亡结算、标题局外升级购买和 `meta` 存档验证，不实现完整主菜单、完整局外包装、黄金回放或平衡 sim。
