# Steamworks Slime Lab —— 雷电式竖版卷轴射击

独立 Godot 4.7 测试项目（540×960 竖屏），用来验证 Steamworks / GodotSteam 联机链路 + 一个可联机的雷电式竖版卷轴射击玩法。它不属于正式 `client/`，也不依赖正式项目的 `PlatformServices` / 词表 / autoload 体系。

UI 走 lab 内置的正式街机 demo 风格：不引入外部字体 / PNG / 图标资源，统一用 `Theme`、`StyleBoxFlat`、代码绘制和 `Tween` 做深色霓虹面板、按钮反馈、页面切换、HUD 脉冲、buff / 结算入退场和表情轮展开动画。

## 玩法

- 每个玩家是一只软体史莱姆，WASD / 方向键移动（限制在战场内），按住鼠标左键朝鼠标方向连续射击，按住 `T` 开表情轮盘。
- 敌人不断从画面上方过来：直冲怪（撞人自爆）、悬停炮手（瞄准弹，高 tier 三扇）、掠射怪（斜穿 + 垂直弹）。炮手 / 掠射怪会远程攻击，敌弹为暖色，玩家弹为冷色。
- 敌人死亡约 12% 掉主动道具，踩到自动收入单槽，已有道具会替换；按 `Q` 使用。当前 5 个道具：修复波（全队回血）、清场脉冲（清敌弹并伤害敌人 / boss / 障碍）、凝滞场（冻结敌人 / boss / 敌弹 / 障碍）、团队过载（全队短时强化射速 / 伤害 / 弹速）、应急护膜（自己回血 + 短暂无敌）。
- 玩家 **3 滴血**：被敌弹 / 敌人 / boss / 障碍物碰到扣 1 血，受击后 1.2 秒无敌闪烁。
- **每坚持 30 秒**：战斗时停（子弹悬停、背景停滚），每个存活玩家三选一 buff（射速 / 伤害 / 多发 / 移速 / 回血 / 弹速 / 穿透，可叠加）；所有人选完才恢复，联机下 20 秒不选自动随机。每轮 tier +1，之后新刷的敌人血量 / 移速 / 射速 / 弹速 / 刷怪密度都更强（伤害恒 1 血）。
- **每 2 分钟一个 boss**：瞄准扇 + 环形弹两种弹幕，血量低于 30% 狂暴加速；每个 boss 都比上一个更强。boss 期间普通刷怪减半，顶部显示 boss 血条。
- **障碍物**：不定期从上方飘下的岩块，会挡住玩家 / 敌人 / 玩家子弹，可打碎，撞到玩家扣 1 血。
- **死亡观战**：多人下玩家死亡变半透明观战（不能开火、不再被打），全灭才 Game Over；单机自己死了即结束。结算面板显示存活时间 / tier / boss 击破数，只有 host（或单机）有"再来一局"按钮，重开后全场同步复位。

多人沿用 host 权威：进入联机 session 后先停在准备房间，host 至少等到 2 名玩家后手动开始战斗；敌人 / boss / 障碍物 / 主动道具掉落与使用 / 伤害 / buff / 时停都在 host 结算，位置、HP、掉落物、主动槽和团队效果走 60Hz 快照，开始战斗 / 敌弹齐射 / 开火 / 使用主动道具 / phase / buff / 重开走 reliable RPC。Host 退出 = 全场结束（不支持 host 迁移）。中途加入会收到开始战斗信号并立即从快照对齐当前战况。

## 运行

```powershell
py -3 tools\godot_bridge.py --project output\steamworks_lab headless-boot
```

也可以用 Godot 4.7 打开 `output/steamworks_lab/project.godot`。默认主场景是 `res://scenes/main.tscn`。

headless 战斗回归（刷怪 / 受击 / 无敌帧 / GameOver / 重开 / buff 时停 / boss / 障碍物 / 主动道具）：

```powershell
& "<godot.exe>" --headless --path output\steamworks_lab --script res://tests/battle_smoke.gd
```

## 本地双开测试清单

1. 实例 A：`开始联机游戏` → `Host Local`；实例 B：地址 `127.0.0.1` 端口 `24567` → `Join Local`。
2. 两端确认：主菜单 / 准备房间 / 入场切换有淡入和轻微回弹，按钮 hover / press 有反馈；A / B 都停在准备房间，没有敌人和计时；A 看到玩家数达到 2 后点 `Start Battle`，两端才进入战斗。
3. 两端确认：敌人从顶部同步出现；B 开火能打死敌人（血量在 A 端结算，B 端子弹碰到敌人会视觉消隐）；敌弹两端轨迹一致；障碍物会挡住玩家和敌人；双方血心随受击同步扣减并闪烁。
4. 手测主动道具：打怪掉落后任一玩家踩到收进 HUD 的 `Q` 胶囊槽并触发脉冲；已有道具时新道具替换；按 `Q` 使用后槽位清空。优先验证修复波 / 清场脉冲 / 凝滞场 / 团队过载在两端都影响全队或全场，而不是只改使用者本地状态。
5. 撑到 30 秒：两端同时冻结（空中子弹悬停、背景停滚），各自弹三选一；A 先选后显示"等待其他玩家选择… (n)"；B 挂机 20 秒验证超时自动选择并恢复，恢复后敌人明显变强。
6. 让 B 死亡：B 变半透明观战、不能开火、不再被打；A 继续打；A 也死 → 双端出结算面板，只有 A 有"再来一局"，按下后两端同步复位再来一轮。
7. B 中途 `Leave Game` 再重新 Join：验证 B 收到开战信号后立即看到当前 tier / 计时 / 在场敌人 / 障碍物 / 主动道具掉落 / 持有槽 / 团队效果；若加入时正值选 buff，显示等待且不阻塞 A。
8. （可选）手测 boss 两端同步与血条：默认每 2 分钟会生成一个 boss。

headless 自动化版（host 与 client 需要不同项目目录副本，见下方故障提示）：

```powershell
# 终端 1
& "<godot.exe>" --headless --path output\steamworks_lab --script res://tests/net_host_smoke.gd
# 终端 2（项目副本目录）
& "<godot.exe>" --headless --path <steamworks_lab 副本> --script res://tests/net_client_smoke.gd
```

## Steam 测试

GodotSteam / Steamworks 二进制不提交进仓库。要启用 Steam 路径，运行环境需要同时提供 `Steam` singleton 和 `SteamMultiplayerPeer` 类；这可以来自 GodotSteam 对应分发版本，也可以来自 GodotSteam + Steam Multiplayer Peer 组合，按你实际选择的插件说明安装。

1. 安装 GodotSteam / Steam Multiplayer Peer 相关 Godot 4 插件到本项目的 `addons/`，以官方安装说明为准。
2. 保留项目根的 `steam_appid.txt`，内容为 `480`，即 Valve 的 Spacewar 测试 App ID。
3. 启动 Steam 客户端并登录。
4. 运行本项目，点 `开始联机游戏`。若 GodotSteam 可用，Steam 状态会显示可用；否则 Steam 按钮会记录缺失原因，本地 ENet 仍可用。
5. A 点 `Host Steam`，创建 lobby 后 UI 会显示 lobby id；B 输入该 id 点 `Join Steam by ID`。
6. 按上面的双开测试清单验证战斗同步。

Steam lobby metadata 会写入 `wasd_lab=steamworks_slime_v1` 和 `lab_version=1`，用于把本实验 lobby 从 Spacewar 公共 lobby 池里区分出来。

## 文件结构

- `scripts/steamworks_lab.gd`：主场景、三页街机 UI、页面 / 按钮动效、玩家生成、host 权威同步、射击链路、滚动背景与战斗接线。
- `scripts/ui_style.gd`：lab 专用 UI 色板、Theme、Panel / Button / Input 等 StyleBox 工具。
- `scripts/battle_director.gd`：战斗核心。权威端：刷怪波次 / tier 缩放 / boss / 障碍物 / 主动道具调度、圆-圆判伤、buff 状态机与时停；client 端：快照镜像重建、敌弹 volley 视觉、玩家弹视觉消隐。
- `scripts/enemy.gd` / `scripts/enemy_bullet.gd`：三种敌人（直冲 / 炮手 / 掠射）与暖色敌弹。
- `scripts/boss.gd`：每 2 分钟的 boss（瞄准扇 + 环形弹、enrage）。
- `scripts/obstacle.gd`：可打碎的下落岩块（seed 形状 + 按损伤显示裂纹）。
- `scripts/active_pickup.gd`：可拾取主动道具，host 生成并通过快照镜像到 client。
- `scripts/battle_hud.gd`：血心 / 胶囊主动槽 / 存活时间 / Tier / boss 血条 / 观战角标 / 动效结算面板。
- `scripts/buff_panel.gd`：三选一强化面板（含等待、超时倒计时和入退场动效）。
- `scripts/burst_effect.gd`：通用爆碎特效。
- `scripts/slime_body.gd`：无骨骼软体史莱姆（弹簧膜 + Catmull-Rom 轮廓），带战场移动边界 clamp。
- `scripts/slime_player.gd`：玩家实体包装，含 3 血 / 无敌帧 / 观战 / 快照扩展。
- `scripts/slime_bullet.gd`：玩家视觉子弹（膜锚定分裂），带伤害 / 穿透 / 速度字段。
- `scripts/expression_wheel.gd`：按住 `T` 的表情轮盘（径向展开 / 收回与选中扇区反馈）。
- `scripts/network_session.gd`：统一 host / join / leave / RPC 同步入口（输入 / 快照 / 射击 / 主动道具 / 表情 / phase / buff / volley / 重开）。
- `scripts/transport_adapter.gd`：本地 ENet 与可选 GodotSteam adapter。
- `tests/battle_smoke.gd`：单机战斗 headless 回归。
- `tests/net_host_smoke.gd` / `tests/net_client_smoke.gd`：双进程 ENet 联机 headless 回归。

## 故障提示

- `GodotSteam singleton is not installed`：未安装 GodotSteam，先用本地 ENet 路径验证。
- `SteamMultiplayerPeer is missing`：当前 Steam 插件组合不含高层 multiplayer peer，换用支持该类的版本或追加对应 GDExtension。
- `Steam is available, but the user is not logged on`：Steam 客户端未登录或未通过 App ID 启动。
- Host 只显示 1 个玩家、Client 显示 0 个玩家：说明 lobby 可能加入成功，但 Steam P2P peer 没连上。观察左侧日志是否出现 `Steam P2P peer added`；如果出现 `same account` 提示，说明同一 Steam 账号双开无法形成第二个真实 P2P peer，请用另一台设备 / 另一个账号测 Steam 路径，本机同步先用 `Host Local` / `Join Local` 验证。
- `Failed to host local ENet server`：端口可能被占用，换端口或关闭旧实例。
- 两端冻结后一直不恢复：看是否有玩家停在三选一没选（联机下 20 秒会自动选）；若有人中途掉线，host 会自动剔除其待选状态并恢复。
- Windows 下两个 **headless** Godot 实例共用同一项目目录时，后启动的实例可能因 `.godot` 缓存锁报 `File not found`：headless 联机回归请给 client 用一份项目目录副本（图形模式双开同一项目不受影响）。
