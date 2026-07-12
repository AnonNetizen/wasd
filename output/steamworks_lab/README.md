# Steamworks Slime Lab —— 雷电式竖版卷轴射击

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是独立 Steamworks Slime Lab 的运行、Steam App ID、联机测试与发布边界权威；改 App ID、GodotSteam adapter、Lobby 协议、导出方式或手动 smoke 时，必须同步本项目配置 / 测试、`docs/AI导航.md`、`docs/测试策略.md`、ADR 与 AI 记忆。

独立 Godot 4.7 Steam 应用项目（固定 540×960 设计画布，窗口可选 540×960 / 720×1280 / 1080×1920），使用专属 Steam App ID **`4955670`**，验证 Steamworks / GodotSteam 联机链路并承载一个可联机的雷电式竖版卷轴射击玩法。它是仓库内长期维护的独立应用，仍不属于正式 `client/`，也不依赖正式项目的 `PlatformServices` / 词表 / autoload 体系。

Windows Steam 集成锁定为 **普通 Godot 4.7 + 官方 GodotSteam 4.20 GDExtension + Steamworks SDK 1.64**。版本、插件下载地址和 SHA-256 记录在 `steam_toolchain.lock.json`；插件安装到忽略的 `addons/godotsteam/`，工具会在 `.toolchain/` 准备一份不带冲突 DLL 的普通 Godot 4.7 与标准 Windows templates，二进制均不提交仓库。可复现安装、验证和导出统一走 `tools/steamworks_lab_toolchain.py`。

UI 走 lab 内置的正式街机 demo 风格：不引入外部字体 / PNG / 图标资源，统一用 `Theme`、`StyleBoxFlat`、代码绘制和 `Tween` 做深色霓虹面板、按钮反馈、页面切换、HUD 脉冲、屏幕震动、冲击闪光、爆碎冲击环、buff / 结算入退场和表情轮展开动画。

主菜单提供 `设置 / Settings` 页面，可在 `简体中文 / English` 间切换语言，选择 `540×960`（适配 1080p）、`720×1280`（适配 2K）、`1080×1920`（适配 4K）三档窗口分辨率，并切换全屏。分辨率档位只改变窗口像素尺寸；游戏逻辑、碰撞和 UI 设计坐标始终保持 540×960，由 Godot stretch 负责放大。全屏使用 Godot stretch 扩展画布，宽屏多出的区域用动态背景填满，不再显示固定画布外黑边。主菜单也提供 `自定义 / Customize` 页面，可设置昵称、史莱姆主体色和玩家子弹色，并提供 `退出游戏 / Quit Game` 按钮；外观只影响表现，不改变血量、碰撞、伤害、速度等玩法数值。设置持久化到 `user://settings.cfg`；已有玩家选择优先，没有保存时优先读取 GodotSteam 暴露的 Steam 当前游戏语言（Steamworks `ISteamApps::GetCurrentGameLanguage()`），取不到 Steam 语言再读系统语言。`schinese` / `tchinese` / 任意 `zh*` 默认进 `zh_CN`，其他语言默认 `en`；headless 测试下不会实际切换窗口模式。

主菜单也提供 `记录 / Records` 入口，用 `user://save.cfg` 本地保存当前最长存活时间。当前只记录 `records.best_survival_seconds`，仅在战斗进入 Game Over 时更新；手动返回主菜单、离开联机会话或重开不会刷新纪录。

## 玩法

- 每个玩家是一只软体史莱姆，WASD / 方向键移动（限制在战场内），按住鼠标左键朝鼠标方向连续射击，按住 `T` 开表情轮盘，按 `Esc` 打开暂停菜单。
- 双人靠近后双方按住 `E` 可短时间合体成大史莱姆：发起者控制移动和主炮，队友控制副炮；合体有临时护盾、倒计时和冷却，不改变永久外观或存档。
- 主菜单 `设置 / Settings` 可切换语言、窗口分辨率和全屏；语言影响主菜单、准备房间、HUD、buff、主动道具名、结算和表情轮标签，Steam 状态提示仍以英文为主；`退出游戏 / Quit Game` 可直接关闭 lab。
- 主菜单 `自定义 / Customize` 可设置本机昵称、8 个预设史莱姆色和 8 个预设子弹色。单机昵称留空时不显示名字；联机昵称留空时会显示 `Host` / `Peer N`。外观会随 host 快照同步给所有玩家，中途加入也会看到当前外观。
- 主菜单 `记录 / Records` 会弹出街机风格窗口显示最长存活时间；无记录时显示 `暂无记录 / No record yet`，有记录时统一显示为 `MM:SS`。
- 单机 / offline 下 `Esc` 会真暂停战斗：敌人、boss、敌弹、玩家弹、无敌计时、战斗时钟和背景滚动都会停住；多人联机下 `Esc` 只打开本地菜单并清零本地输入，host 权威战斗继续运行，不新增网络暂停。
- 敌人不断从画面上方过来：直冲怪（撞人自爆）、悬停炮手（瞄准弹，高 tier 三扇）、掠射怪（斜穿 + 垂直弹）。炮手 / 掠射怪会远程攻击，敌弹为暖色，玩家弹为冷色；子弹命中会有小火花，敌人 / 障碍 / boss 被击破会有爆碎冲击环与轻重不同的屏幕震动。
- 敌人死亡约 12% 掉主动道具，踩到自动收入单槽，已有道具会替换；按 `Q` 使用。当前 5 个道具：修复波（全队回血）、清场脉冲（清敌弹并伤害敌人 / boss / 障碍）、凝滞场（冻结敌人 / boss / 敌弹 / 障碍）、团队过载（全队短时强化射速 / 伤害 / 弹速）、应急护膜（自己回血 + 短暂无敌）。
- 玩家 **3 滴血**：被敌弹 / 敌人 / boss / 障碍物碰到扣 1 血，受击后 1.2 秒无敌闪烁，并触发红色冲击闪光与短屏幕震动。
- **每坚持 30 秒**：战斗时停（子弹悬停、背景停滚），每个存活玩家三选一 buff（射速 / 伤害 / 多发 / 移速 / 回血 / 弹速 / 穿透，可叠加）；所有人选完才恢复，联机下 20 秒不选自动随机。每轮 tier +1，之后新刷的敌人血量 / 移速 / 射速 / 弹速 / 刷怪密度都更强（伤害恒 1 血）。
- **每 2 分钟一个 boss**：瞄准扇 + 环形弹两种弹幕，血量低于 30% 狂暴加速；每个 boss 都比上一个更强。boss 期间普通刷怪减半，顶部显示 boss 血条。
- **障碍物**：不定期从上方飘下的岩块，会挡住玩家 / 敌人 / 玩家子弹，可打碎，撞到玩家扣 1 血。
- **死亡观战**：多人下玩家死亡变半透明观战（不能开火、不再被打），全灭才 Game Over；单机自己死了即结束。结算面板显示存活时间 / tier / boss 击破数，只有 host（或单机）有"再来一局"按钮，重开后全场同步复位。

多人沿用 host 权威：进入联机 session 后先停在准备房间，支持 2-4 名玩家，host 至少等到 2 名玩家后手动开始战斗；敌人 / boss / 障碍物 / 主动道具掉落与使用 / 伤害 / buff / 时停都在 host 结算，位置、HP、外观、掉落物、主动槽和团队效果走 60Hz 快照，开始战斗 / 敌弹齐射 / 开火 / 使用主动道具 / phase / buff / 重开走 reliable RPC，client 修改外观时会可靠提交给 host。Host 退出 = 全场结束（不支持 host 迁移）。中途加入会收到开始战斗信号并立即从快照对齐当前战况。

## 运行

首次配置 Windows Steam 工具链：

```powershell
py -3 tools\steamworks_lab_toolchain.py setup
py -3 tools\steamworks_lab_toolchain.py verify
```

`setup` 需要本机已有普通 Godot 4.7 和 Windows x64 export templates；可在子命令前用 `--godot <path>`（例如 `... --godot C:\Godot\godot.exe setup`）或环境变量 `GODOT_PATH` 指定。Steam 商店版 Godot 目录自带同名 `steam_api64.dll`，会与 GodotSteam 插件冲突，因此工具会硬链接或复制同一个普通 Godot 二进制及标准 templates 到 `.toolchain/godot-4.7-standard/`，不是 GodotSteam 定制引擎。用图形编辑器开发时从该干净目录启动：

```powershell
& 'output\steamworks_lab\.toolchain\godot-4.7-standard\godot.windows.opt.tools.64.exe' --path 'output\steamworks_lab' --editor
```

生成并验证 Windows x64 release：

```powershell
py -3 tools\steamworks_lab_toolchain.py export-release
```

产物位于 `output/steamworks_lab/build/windows/`，必须包含 `SteamworksSlimeLab.exe`、`SteamworksSlimeLab.pck`、`libgodotsteam.windows.template_release.x86_64.dll`、`steam_api64.dll` 与 `THIRD_PARTY_NOTICES.txt`，且不得包含开发用 `steam_appid.txt`、测试脚本或 `.toolchain/`。

正式 release 双击时会请求由 Steam App `4955670` 重启；如果该 App 尚未通过 Depot 安装，进程会主动退出，看起来像闪退。本地只看离线 GUI 时显式禁用 Steam：

```powershell
& 'output\steamworks_lab\build\windows\SteamworksSlimeLab.exe' -- --disable-steam
```

```powershell
py -3 tools\godot_bridge.py --project output\steamworks_lab headless-boot
```

也可以用 Godot 4.7 打开 `output/steamworks_lab/project.godot`。默认主场景是 `res://scenes/main.tscn`。

headless 战斗回归（刷怪 / 受击 / 无敌帧 / GameOver / 最长存活时间存档 / 重开 / buff 时停 / boss / 障碍物 / 主动道具）：

```powershell
$godot = 'C:\path\to\godot.exe'
& $godot --headless --max-fps 60 --path output\steamworks_lab --script res://tests/battle_smoke.gd -- --disable-steam
```

Steam 配置与离线降级 smoke（不要求安装 GodotSteam）：

```powershell
$godot = 'C:\path\to\godot.exe'
& $godot --headless --path output\steamworks_lab --script res://tests/steam_config_smoke.gd -- --disable-steam
```

## 本地双开测试清单

1. 实例 A：`开始联机游戏` → `Host Local`；实例 B：地址 `127.0.0.1` 端口 `24567` → `Join Local`。
2. 进入 `设置 / Settings`，切到 English 再切回简体中文，确认主菜单、设置页、HUD 空道具槽、buff 面板、结算和表情轮标签刷新；切换三档分辨率与全屏后重启确认 `user://settings.cfg` 生效。打开 `记录 / Records`，确认无记录 / 最长存活时间文本随语言刷新，Game Over 后再次打开会显示 `MM:SS` 纪录。
3. 进入 `自定义 / Customize`，A / B 分别设置不同昵称、史莱姆颜色和子弹颜色；确认重启后 `user://settings.cfg` 保留，准备房间、战斗中、死亡观战和重开后双方看到的昵称 / 主体色 / 子弹色一致。
4. 两端确认：主菜单 / 准备房间 / 入场切换有淡入和轻微回弹，按钮 hover / press 有反馈；A / B 都停在准备房间，没有敌人和计时；A 看到玩家数达到 2 后点 `Start Battle`，两端才进入战斗。
5. 两端确认：敌人从顶部同步出现；B 开火能打死敌人（血量在 A 端结算，B 端子弹碰到敌人会视觉消隐）；敌弹两端轨迹一致；障碍物会挡住玩家和敌人；双方血心随受击同步扣减并闪烁。
6. A / B 分别按 `Esc`：确认联机只出现本地暂停菜单，本地移动 / 开火 / `Q` / 表情轮被禁用，但另一端和 host 战斗计时仍继续；点击 `Resume / 继续` 或再按 `Esc` 关闭。
7. 手测主动道具：打怪掉落后任一玩家踩到收进 HUD 的 `Q` 胶囊槽并触发脉冲；已有道具时新道具替换；按 `Q` 使用后槽位清空。优先验证修复波 / 清场脉冲 / 凝滞场 / 团队过载在两端都影响全队或全场，而不是只改使用者本地状态。
8. 撑到 30 秒：两端同时冻结（空中子弹悬停、背景停滚），各自弹三选一；A 先选后显示"等待其他玩家选择… (n)"；B 挂机 20 秒验证超时自动选择并恢复，恢复后敌人明显变强。
9. 让 B 死亡：B 变半透明观战、不能开火、不再被打；A 继续打；A 也死 → 双端出结算面板，只有 A 有"再来一局"，按下后两端同步复位再来一轮。
10. B 中途 `Leave Game` 再重新 Join：验证 B 收到开战信号后立即看到当前 tier / 计时 / 在场敌人 / 障碍物 / 主动道具掉落 / 持有槽 / 团队效果和所有玩家外观；若加入时正值选 buff，显示等待且不阻塞 A。
11. （可选）手测 boss 两端同步与血条：默认每 2 分钟会生成一个 boss。

headless 自动化版（host 与 client 需要不同项目目录副本，见下方故障提示）：

```powershell
# 终端 1
$godot = 'C:\path\to\godot.exe'
& $godot --headless --max-fps 60 --path output\steamworks_lab --script res://tests/net_host_smoke.gd -- --disable-steam
# 终端 2（项目副本目录）
$godot = 'C:\path\to\godot.exe'
$projectCopy = 'C:\path\to\steamworks_lab-copy'
& $godot --headless --max-fps 60 --path $projectCopy --script res://tests/net_client_smoke.gd -- --disable-steam
```

## Steam App ID 与测试

GodotSteam / Steamworks 二进制不提交进仓库。当前固定使用 GodotSteam 4.20 官方 GDExtension；4.20 已把 `SteamMultiplayerPeer` 合并进主仓库的 `gdextension` 分支，因此普通 Godot 4.7 加插件即可同时提供 `Steam` singleton、`SteamPacketPeer` 与 `SteamMultiplayerPeer`，不再依赖退役的独立 Peer 仓库或 GodotSteam module editor/templates。

1. 在仓库根运行 `py -3 tools/steamworks_lab_toolchain.py setup`，下载并校验锁定的 Win64 GDExtension、安装到忽略的 `addons/godotsteam/`，并从本机普通 Godot 4.7 准备无 DLL 冲突的标准编辑器 / templates；再运行 `verify`，确认插件实际加载、GodotSteam 4.20、`Steam` singleton 与 `SteamMultiplayerPeer.host_with_lobby/connect_to_lobby/add_peer`。
2. 本地编辑器 / 直接运行测试保留项目根的 `steam_appid.txt`，内容必须只有 `4955670`；`project.godot` 的 `steam/initialization/app_data/app_id` 是 GodotSteam 4.20 与发布重启策略的配置源。插件自动初始化与 embedded callbacks 保持关闭，由 `TransportAdapter` 显式调用 `steamInitEx(4955670, false)` 并在 `_process()` 运行 callbacks。
3. 启动 Steam 客户端并登录。
4. 运行本项目，点 `开始联机游戏`。若 GodotSteam 可用，Steam 状态会显示可用；否则 Steam 按钮会记录缺失原因，本地 ENet 仍可用。
5. A 点 `Invite Friend / 邀请好友` 会自动创建 Steam lobby 并打开 Steam 好友邀请 overlay；也可以点 `Host Steam` 后把显示的 lobby id 发给 B，由 B 输入该 id 点 `Join Steam by ID`。
6. B 接受 Steam 邀请时，若当前正在会话或战斗中会先弹确认框；从 Steam 冷启动时会通过 `+connect_lobby <lobby id>` 自动加入对应 lobby。
7. 用两个拥有 App `4955670` 许可证的不同 Steam 账号 / 设备，按上面的双开测试清单验证战斗同步；同账号双开不能替代真实 P2P smoke。
8. 需要稳定验证单机或本地 ENet 时，在 Godot 参数分隔符 `--` 后追加 `--disable-steam`，Steam 初始化与客户端重启会被显式禁用。

Steam lobby metadata 会写入 `wasd_lab=steamworks_slime_v1` 和 `lab_version=1`，作为应用内协议兼容标识；加入端会拒绝 marker 或版本不匹配的 lobby，避免不同网络协议版本互连。

语言默认值同样优先走 GodotSteam：若 `Steam` singleton 存在，adapter 会尝试读取 `getCurrentGameLanguage`（以及 GodotSteam 等价命名），再映射到 lab 仅支持的 `zh_CN` / `en`。没有 Steam 或读不到时使用系统 locale。

### 发布边界

- 当前仓库已完成专属 App ID、初始化结果校验、运行时 App ID 核对、Steam 客户端重启、Lobby 协议校验、离线退化、GodotSteam 4.20 GDExtension 版本锁和 Windows export preset；本机插件与干净普通 Godot / templates 由统一工具安装到忽略目录。SteamPipe app/depot VDF、后台分支和双账号实机验证仍未纳管，因此“本地 release 可构建”不等于“Depot 已可发布”。
- `steam_appid.txt` 只用于本地开发。根据 [Steamworks 官方初始化说明](https://partner.steamgames.com/doc/sdk/api)，上传 Steam Depot 时必须从可执行文件目录移除；正式构建通过 Steam App `4955670` 启动，并由 adapter 核对 Steam runtime 报告的 App ID。
- 当前 GDExtension 发行方式使用普通 Godot editor / export templates；Windows Depot 需要提交导出的 exe、PCK、`libgodotsteam.windows.template_release.x86_64.dll`、同版 `steam_api64.dll` 与 `THIRD_PARTY_NOTICES.txt`。插件包已经包含官方 `SteamMultiplayerPeer`，不再额外提交 module template 或第三方 Peer 原生库。
- 发布候选必须从 `steam://run/4955670` 启动，手动验证登录、overlay、Lobby 创建 / 加入、好友邀请、`+connect_lobby` 冷启动、断网 / 未登录退化，以及单机 / 本地 ENet 不受影响。

## 文件结构

- `scripts/steamworks_lab.gd`：主场景、主菜单 / 联机 / 设置 / 自定义 / 战斗街机 UI、页面 / 按钮动效、玩家生成、host 权威同步、射击链路、滚动背景与战斗接线。
- `scripts/ui_style.gd`：lab 专用 UI 色板、Theme、Panel / Button / Input 等 StyleBox 工具。
- `scripts/lab_locale.gd` / `scripts/lab_settings.gd`：lab 轻量本地化字典、Steam / 系统语言映射、`user://settings.cfg` 读写、分辨率 / 外观设置和 headless 安全的全屏应用。
- `scripts/lab_save.gd`：lab 轻量本地存档，只读写 `user://save.cfg` 的 `records.best_survival_seconds`。
- `scripts/battle_director.gd`：战斗核心。权威端：刷怪波次 / tier 缩放 / boss / 障碍物 / 主动道具调度、圆-圆判伤、buff 状态机与时停；client 端：快照镜像重建、敌弹 volley 视觉、玩家弹视觉消隐。
- `scripts/enemy.gd` / `scripts/enemy_bullet.gd`：三种敌人（直冲 / 炮手 / 掠射）与暖色敌弹。
- `scripts/boss.gd`：每 2 分钟的 boss（瞄准扇 + 环形弹、enrage）。
- `scripts/obstacle.gd`：可打碎的下落岩块（seed 形状 + 按损伤显示裂纹）。
- `scripts/active_pickup.gd`：可拾取主动道具，host 生成并通过快照镜像到 client。
- `scripts/battle_hud.gd`：血心 / 胶囊主动槽 / 存活时间 / Tier / boss 血条 / 观战角标 / 动效结算面板。
- `scripts/buff_panel.gd`：三选一强化面板（含等待、超时倒计时和入退场动效）。
- `scripts/pause_panel.gd`：`Esc` 暂停面板；单机真暂停，联机只作为本地菜单。
- `scripts/records_panel.gd`：主菜单 `记录 / Records` 弹窗，显示本机最长存活时间并随语言切换刷新。
- `scripts/burst_effect.gd`：通用爆碎特效，包含碎片与扩散冲击环。
- `scripts/slime_body.gd`：无骨骼软体史莱姆（弹簧膜 + Catmull-Rom 轮廓），带战场移动边界 clamp。
- `scripts/slime_player.gd`：玩家实体包装，含外观色板、3 血 / 无敌帧 / 观战 / 快照扩展。
- `scripts/slime_bullet.gd`：玩家视觉子弹（膜锚定分裂），带伤害 / 穿透 / 速度字段。
- `scripts/expression_wheel.gd`：按住 `T` 的表情轮盘（径向展开 / 收回与选中扇区反馈）。
- `scripts/network_session.gd`：统一 host / join / leave / RPC 同步入口（输入 / 快照 / 射击 / 主动道具 / 表情 / phase / buff / volley / 重开）。
- `scripts/transport_adapter.gd`：本地 ENet 与可选 GodotSteam adapter。
- `steam_toolchain.lock.json` / `export_presets.cfg` / `THIRD_PARTY_NOTICES.txt`：GodotSteam 4.20 / Godot 4.7 / Steamworks 1.64 Win64 依赖锁、Windows Steam release preset 与随包第三方许可声明。
- `tools/steamworks_lab_toolchain.py`：仓库根统一 setup / verify / export-release 工具；下载缓存、忽略的 GDExtension、干净普通 editor、标准 Windows templates 与构建产物均不入库。
- `tests/battle_smoke.gd`：单机战斗 headless 回归。
- `tests/steam_config_smoke.gd`：App ID、初始化返回值、Lobby 兼容和显式离线降级 headless 回归。
- `tests/steam_runtime_presence_smoke.gd`：用普通 Godot 4.7 验证锁定 GDExtension 已加载、版本正确、singleton 与高层 multiplayer peer 方法存在，不初始化真实 Steam 会话。
- `tests/net_host_smoke.gd` / `tests/net_client_smoke.gd`：双进程 ENet 联机 headless 回归。

## 故障提示

- `GodotSteam singleton is not installed`：插件未安装或当前 Godot 没有加载 `addons/godotsteam/godotsteam.gdextension`；先运行 `setup` / `verify`，再用工具准备的干净普通 Godot 4.7 启动。
- `Can't open dynamic library ... Error 127`：编辑器目录存在另一份 `steam_api64.dll`，常见于 Steam 商店版 Godot；不要直接从该安装目录运行 Lab，改用 `setup` 生成的 `.toolchain/godot-4.7-standard/` 干净副本。
- `SteamMultiplayerPeer is missing`：GDExtension 未加载、版本不匹配或插件安装不完整；重新运行 `setup` / `verify`，不要再安装退役独立仓库或第三方 Peer。
- 正式 exe 双击后立即消失：`restartAppIfNecessary(4955670)` 已请求 Steam 重启，但本机尚未通过 Depot 安装该 App；离线预览追加 `-- --disable-steam`，真实 Steam 路径等测试分支安装后从 Steam 库启动。
- `Steam initialization failed for app id 4955670`：检查当前账号是否拥有 App 许可证、默认 package 是否已配置、Steam 客户端是否登录，以及本地 GodotSteam / Steamworks 二进制版本是否匹配。
- `Steam App ID mismatch`：当前 Steam runtime 不是 App `4955670`；检查 Steam 启动入口、项目配置和本地开发文件是否一致。
- `Steam is available, but the user is not logged on`：Steam 客户端未登录或未通过正确 App ID 启动。
- Host 只显示 1 个玩家、Client 显示 0 个玩家：说明 lobby 可能加入成功，但 Steam P2P peer 没连上。观察左侧日志是否出现 `Steam P2P peer added`；如果出现 `same account` 提示，说明同一 Steam 账号双开无法形成第二个真实 P2P peer，请用另一台设备 / 另一个账号测 Steam 路径，本机同步先用 `Host Local` / `Join Local` 验证。
- `Failed to host local ENet server`：端口可能被占用，换端口或关闭旧实例。
- 两端冻结后一直不恢复：看是否有玩家停在三选一没选（联机下 20 秒会自动选）；若有人中途掉线，host 会自动剔除其待选状态并恢复。
- Windows 下两个 **headless** Godot 实例共用同一项目目录时，后启动的实例可能因 `.godot` 缓存锁报 `File not found`：headless 联机回归请给 client 用一份项目目录副本（图形模式双开同一项目不受影响）。
