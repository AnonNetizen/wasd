# DebugTools 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是调试控制台与 GM 指令的代码契约；改 `DebugConsole`、`GMCommandRegistry`、debug action、GM 命令或 release 调试资源边界时必须同步本文档、`docs/测试策略.md`、`docs/AI导航.md` 与 `docs/AI记忆/current_state.json`。

## 职责

- 只在 Godot debug build 或带 `dev_tools` feature 的构建中挂载调试控制台。
- 提供 GM 命令注册与执行入口，当前覆盖 `help` / `stats` / `spawn` / `xp` / `heal` / `hp` / `damage` / `kill_player` / `kill_enemies` / `clear_enemies` / `dust` / `seed`。
- GM 命令只能调用正式系统 API 或受控 `debug_*` API，不直接散落修改 gameplay 私有状态、存档文件或 analytics。
- release 构建默认不会挂载 `DebugConsole` / `GMCommandRegistry`，也不会注册 `debug_*` InputMap action。

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/debug/debug_console.gd` | 动态构建控制台 UI，注册 `debug_*` action，转发命令给 GM registry |
| `client/scripts/debug/gm_command_registry.gd` | 命令解析、参数校验和正式系统 API 调用 |
| `client/scripts/boot/formal_client_boot.gd` | 通过字符串路径动态加载 `DebugConsole`，并提供 release 双重 guard |
| `client/scripts/gameplay/gameplay_run_loop.gd` | 提供 `debug_summary()`、刷怪、经验、玩家生命、杀敌 / 清敌等受控 runtime debug API |
| `client/scripts/gameplay/player.gd` | 提供生命值设置 / 治疗 / 清无敌的 debug API |
| `client/scripts/autoload/gear_mod_system.gd` | 提供 `debug_grant_resource()`，仍走 profile normalize 与 `save_meta_profile()` |
| `client/tools/debug_tools_smoke.gd` | headless 自动验证 debug 可用与 release 模拟禁用 |
| `tools/godot_bridge.py` | 暴露 `debug-tools-smoke` 与 `debug-tools-release-smoke` |

## 运行流程

| 阶段 | 发生什么 |
|------|----------|
| 启动 guard | `FormalClientBoot._debug_tools_enabled()` 检查 `OS.is_debug_build()` 或 `OS.has_feature("dev_tools")`；`--force-release-debug-tools-off` 只用于 smoke 模拟 release |
| 动态加载 | 通过 `load("res://scripts/debug/debug_console.gd")` 创建控制台，避免正式启动脚本静态 preload 调试脚本 |
| 控制台输入 | `F1` 或反引号打开 / 关闭，`Esc` 关闭；输入框提交后调用 `GMCommandRegistry.execute()` |
| 命令执行 | registry 查找当前 `GameplayRunLoop` 或 autoload，然后调用正式系统 API / `debug_*` API |
| release 路径 | guard 失败时不加载控制台、不创建 registry、不注册 debug action |

## 命令

| 命令 | 行为 |
|------|------|
| `help` | 输出当前命令列表 |
| `stats` | 输出 GameState、seed、GameClock、UI 栈、对象池、敌人数量和 runtime 摘要 |
| `spawn <enemy_id> [count]` | 通过 `GameplayRunLoop.debug_spawn_enemy()` 走对象池和敌人 `configure()` 刷怪，默认 `enemy_chaser` |
| `xp <amount>` | 通过 runtime 原有经验收集路径增加经验，可触发升级 |
| `heal [amount]` | 调用玩家 debug 治疗 API，默认回满 |
| `hp <amount>` | 设置玩家生命值，`0` 会触发死亡信号 |
| `damage <amount>` | 清玩家短暂无敌后通过 `Combat.apply_damage()` 造成伤害 |
| `kill_player` | 通过 `Combat.apply_damage()` 造成足量伤害 |
| `kill_enemies` | 对当前 active enemies 走 `Combat.apply_damage()` |
| `clear_enemies` | 通过 `PoolManager.release()` 清理当前 active enemies |
| `dust <amount>` | 通过 `GearModSystem.debug_grant_resource()` 增加 Gear Mod 升级资源 |
| `seed <int>` | 调用 `RNG.set_run_seed()` 设置 run seed |

## Release 边界

- 正式导出不得启用 `dev_tools` feature。
- 正式导出 preset 应排除 `res://scripts/debug/*` 和 `res://tools/debug_tools_smoke.gd` 等开发资源。
- 业务脚本不得直接 preload 调试脚本；当前只有 `FormalClientBoot` 保存字符串路径并在 guard 通过后动态加载。
- `debug-tools-release-smoke` 是 headless 模拟检查，不等价于真实 release export；真正接 export preset 时仍必须检查资源过滤和 `custom_features`。

## 测试义务

- 改控制台 / 命令注册 / debug action：跑 `py tools/godot_bridge.py --project client debug-tools-smoke` 和 `py tools/godot_bridge.py --project client debug-tools-release-smoke`。
- 改 runtime debug API：追加 `py tools/godot_bridge.py --project client runtime-smoke`。
- 改 Gear Mod 资源 GM：追加 `py tools/godot_bridge.py --project client gear-mod-smoke` 或确认 `debug-tools-smoke` 已覆盖对应路径。
- 改 release preset：跑 `py tools/lint_project_rules.py`，并人工确认导出资源不含调试脚本。

## 相关文档

- `docs/游戏设计文档.md` §9.20
- `docs/词表与契约.md` §7
- `docs/测试策略.md` §5.10
- `docs/代码/formal_client_boot.md`
- `docs/代码/gameplay_runtime.md`
