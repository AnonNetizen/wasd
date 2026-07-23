# 正式客户端（client）

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式 Godot 客户端入口与运行说明；改项目启动方式、目录结构或验证命令时，必须同步 `README.md`、`docs/AI导航.md`、`docs/正式项目工作规划.md`、`docs/AI记忆/current_state.json`。

`client/` 是完整项目的 Godot 4.7.1 stable 项目根，即 Godot 内的 `res://`。

当前阶段为 F14 敌人导航与感知收口后：正式工程当前使用 Godot 4.7.1 stable，启动场景在数据校验通过后显示标题界面；开始、继续和重开会统一进入 `GameState.LOADING`，显示全屏暗色加载遮罩与旋转图形，完成资源准备后才激活战斗 runtime。若存在 `SaveManager` 的 `run` 存档，标题菜单会显示“继续游戏”，续局读取失败时会提示本局存档已重置；标题菜单常驻“装备 Mod”和“设置”入口。当前 runtime 覆盖 F13 9×9 模块世界、五种独立池敌人、玩家对局级相机、射击、机关、短局目标 / 撤离、暂停保存续局、Gear Mod 与回放护栏。`loading-smoke`、`runtime-smoke`、`save-smoke` 等覆盖正式入口；`startup-probe` / `perf-probe` 仅在用户明确要求性能测试时运行。项目当前只设计 / 验收固定 16:9 分辨率，默认 viewport 为 1920×1080，窗口不允许任意拖拽缩放，并通过 `canvas_items + keep` 在非 16:9 屏幕上等比缩放、补上下或左右黑边；其他宽高比留作未来按独立固定预设接入的优化项。

ADR #151 / #152 后，正式输入由固定版本 GUIDE 解释物理设备，项目业务统一消费 `InputService` 的生成 action 与 `move` / `aim` `Vector2` intent；绑定保存到 `user://input_bindings.tres`，设置配置为 v2，Replay file / recording 仅支持 schema v2。输入架构和插件维护分别见 `docs/代码/input_service.md` 与 `docs/代码/guide.md`。

## 目录

| 路径 | 用途 |
|------|------|
| `project.godot` | 正式 Godot 项目配置 |
| `scenes/` | 正式项目场景 |
| `scripts/` | 正式项目 GDScript |
| `scripts/debug/` | debug/dev_tools 专用控制台与 GM 命令注册表；正式 release 不应加载或导出 |
| `addons/` | 固定版本 Godot 编辑器插件；来源、许可、本地补丁与升级流程见 `client/addons/README.md` |
| `data/` | 数值与复杂配置，说明见 `client/data/README.md` |
| `locale/` | 本地化表，说明见 `client/locale/README.md` |
| `assets/` | 美术、音频等资源 |
| `templates/` | 新内容脚手架模板 |
| `tools/` | 项目内 Godot headless smoke 脚本 |

## Godot 插件

正式项目固定版本启用 `@icons 1.4.0`、`Script-IDE 2.2.3`、`Phantom Camera 0.11.0.3` 与 `G.U.I.D.E 0.14.0`。全部源码入库且不自动更新；仓库内代码按项目 GDScript 规则维护，同时保留上游许可证和版权声明。Phantom Camera 与 GUIDE 是玩法运行时依赖，对应 manager / autoload 均由项目稳定注册；升级必须按 `client/addons/README.md` 记录发布包哈希、审查上游差异、迁移本地补丁并重新运行完整验证。

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
| `GUIDE` | `res://addons/guide/guide.gd` | 固定版本物理输入、mapping context、trigger / modifier 和 remapping 引擎；业务不得直接调用 |
| `InputService` | `res://scripts/autoload/input_service.gd` | 项目 action / intent、context、重绑定持久化、设备提示、回放覆盖和 Godot UI 窄桥 |
| `Analytics` | `res://scripts/autoload/analytics.gd` | 已登记事件的本地内存缓冲与隐私开关联动 |
| `Replay` | `res://scripts/autoload/replay.gd` | 输入 / 关键决策的内存态回放录制边界 |
| `PoolManager` | `res://scripts/autoload/pool_manager.gd` | 高频实体对象池注册、获取、释放、统计与溢出埋点 |
| `SaveManager` | `res://scripts/autoload/save_manager.gd` | `meta` / `run` / `replay_index` 存档 envelope、原子写入、备份回退、迁移与坏档隔离 |
| `GearModSystem` | `res://scripts/autoload/gear_mod_system.gd` | 装备 Mod profile、资源、库存、英雄 / 武器 loadout、掉落、升级、分解和下一局 modifier snapshot |
| `AudioManager` | `res://scripts/autoload/audio_manager.gd` | SFX / voice / music 注册、播放入口、Bus 路由与音量设置同步 |
| `Localization` | `res://scripts/autoload/localization.gd` | 当前语言、语言切换与翻译入口 |
| `UIManager` | `res://scripts/autoload/ui_manager.gd` | UI 场景栈与暂停 UI 联动 |
| `Combat` | `res://scripts/combat/combat.gd` | 统一伤害入口，`DamageInfo` 载荷定义在 `res://scripts/combat/damage_info.gd` |
| `PhantomCameraManager` | `res://addons/phantom_camera/scripts/managers/phantom_camera_manager.gd` | Phantom Camera host / virtual camera / noise 的运行时信号中枢 |

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

正式开始 / 继续 / 重开加载 smoke：

```powershell
python tools/godot_bridge.py --project client loading-smoke
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

`res://scenes/boot/main.tscn` 挂载 `res://scripts/boot/formal_client_boot.gd`。启动脚本会先执行正式数据 schema smoke 并输出日志；若校验通过，会显示标题界面。点击开始、继续或重开后，启动层先进入 `LOADING` 并通过 `UIManager` 显示 `LoadingScreen`；至少渲染一帧后，再读取 run 或挂载 `GameplayRunLoop`。runtime 使用 Godot `ResourceLoader` 线程接口读取本局 actor / 模块 `PackedScene`，对象池预热、初始模块挂载和续局实体恢复在主线程分批完成；准备成功时先移除加载界面，再进入 `PLAYING` 并恢复 `ui_restore`。读取失败沿用本局存档重置提示，准备失败会清理半成品和对象池并回标题。装备 Mod 与设置面板仍通过 `UIManager` 叠加。debug/dev_tools 构建中，启动脚本会动态加载 `res://scripts/debug/debug_console.gd`；正式 release 不应启用 `dev_tools`，也不应导出 `res://scripts/debug/*`。

Gameplay runtime 与加载流程文档见 `docs/代码/gameplay_runtime.md`、`docs/代码/gameplay_loading.md`、`docs/代码/gear_mod_system.md` 与 `docs/代码/debug_tools.md`。玩家加载不显示阶段、百分比或取消按钮，也不人为延长；应用冷启动和进入标题菜单前的耗时暂不在此流程内处理。
