# Steamworks Slime Lab

独立 Godot 4.7 测试项目，用来验证 Steamworks / GodotSteam 联机链路。它不属于正式 `client/`，也不依赖正式项目的 `PlatformServices`。

第一版功能很窄：每个玩家是一只无骨骼软体史莱姆，使用 WASD 或方向键移动，host 权威同步所有史莱姆位置。没有攻击、存档、正式大厅浏览、好友邀请或成就。

## 运行

```powershell
py -3 tools\godot_bridge.py --project output\steamworks_lab headless-boot
```

也可以用 Godot 4.7 打开 `output/steamworks_lab/project.godot`。默认主场景是 `res://scenes/main.tscn`。

## 本地双开测试

1. 打开第一个实例，点 `Host Local`。
2. 打开第二个实例，地址保持 `127.0.0.1`，端口保持 `24567`，点 `Join Local`。
3. 两边分别用 WASD / 方向键移动，观察两个史莱姆位置同步。
4. 点 `Leave` 或 `Offline` 回到单机测试。

## Steam 测试

GodotSteam / Steamworks 二进制不提交进仓库。要启用 Steam 路径，运行环境需要同时提供 `Steam` singleton 和 `SteamMultiplayerPeer` 类；这可以来自 GodotSteam 对应分发版本，也可以来自 GodotSteam + Steam Multiplayer Peer 组合，按你实际选择的插件说明安装。

1. 安装 GodotSteam / Steam Multiplayer Peer 相关 Godot 4 插件到本项目的 `addons/`，以官方安装说明为准。
2. 保留项目根的 `steam_appid.txt`，内容为 `480`，即 Valve 的 Spacewar 测试 App ID。
3. 启动 Steam 客户端并登录。
4. 运行本项目。若 GodotSteam 可用，Steam 状态会显示可用；否则 Steam 按钮会记录缺失原因，本地 ENet 仍可用。
5. A 点 `Host Steam`，创建 lobby 后 UI 会显示 lobby id。
6. B 在 `Steam lobby id` 输入该 id，点 `Join Steam by ID`。
7. 两边用 WASD / 方向键移动，验证位置同步。

Steam lobby metadata 会写入 `wasd_lab=steamworks_slime_v1` 和 `lab_version=1`，用于把本实验 lobby 从 Spacewar 公共 lobby 池里区分出来。

## 文件结构

- `scripts/slime_body.gd`：从 `output/test_lab/scripts/soft_body_cell.gd` 改造的无骨骼软体史莱姆。
- `scripts/slime_player.gd`：玩家实体包装，把输入转换成软体 follow target，并支持远端插值。
- `scripts/network_session.gd`：统一 host / join / leave / RPC 同步入口。
- `scripts/transport_adapter.gd`：本地 ENet 与可选 GodotSteam adapter。
- `scripts/steamworks_lab.gd`：主场景、测试 UI、玩家生成和 host 权威同步。

## 故障提示

- `GodotSteam singleton is not installed`：未安装 GodotSteam，先用本地 ENet 路径验证。
- `SteamMultiplayerPeer is missing`：当前 Steam 插件组合不含高层 multiplayer peer，换用支持该类的版本或追加对应 GDExtension。
- `Steam is available, but the user is not logged on`：Steam 客户端未登录或未通过 App ID 启动。
- Host 只显示 1 个玩家、Client 显示 0 个玩家：说明 lobby 可能加入成功，但 Steam P2P peer 没连上。观察左侧日志是否出现 `Steam P2P peer added`；如果出现 `same account` 或 `one account after join` 提示，说明同一 Steam 账号双开无法形成第二个真实 P2P peer，请用另一台设备 / 另一个 Steam 账号测 Steam 路径，本机同步先用 `Host Local` / `Join Local` 验证。
- `Failed to host local ENet server`：端口可能被占用，换端口或关闭旧实例。
