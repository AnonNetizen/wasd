# Lowpoly Survivors Lab

一个完全独立于正式客户端、`output/test_lab/` 和 Steamworks Lab 的 Godot 4.7.1 3D 实验项目。支持离线单人与 Windows/Android 1–4 人 EOS 合作；玩家只负责移动，武器自动索敌，在外星基地中坚持到 10:00 并击毁最终蚂蚁机甲。

## 启动与操作

用 Godot 4.7.1 打开本目录的 `project.godot`，或从仓库根目录运行：

```powershell
py -3 tools/godot_bridge.py --project output/lowpoly_survivors_lab headless-boot
```

- `WASD` / 方向键 / 手柄左摇杆：移动
- `Esc` / 手柄 Start：离线暂停；在线仅打开本地菜单，对局不会暂停
- Android：左侧虚拟摇杆移动，右上角打开本地菜单，升级卡可直接触控
- 武器自动寻找目标，不需要射击输入

窗口以 1920×1080 为设计与默认尺寸，可自由缩放；渲染器固定为 Compatibility。

## 实验内容

- 一张约 160×160 米的外星基地地图，中央战区无固定阻挡。
- 玩家会与敌人及外围基地设施发生碰撞；敌群内部使用轻量分离，避免高密度互相卡死。
- 角色、四类敌人与最终 Boss 使用各自 GLB 内置动作，覆盖待机、移动、攻击、受击和死亡；步枪跟随角色手部骨骼。
- 四类常规敌人、三个固定时间点精英与 10:00 最终 Boss。
- 脉冲步枪、轨道无人机、离子脉冲，以及五种被动强化。
- 升级三选一、暂停、胜利、失败、重开与返回标题的完整状态闭环。
- EOS Connect Device ID 游客登录、六位房间码大厅、准备/锁房、P2P Relay、掉线重连和房主迁移。
- 房主权威战斗，20 Hz 输入、10 Hz 兴趣裁剪快照、本地预测/校正、远端插值与每秒可接管检查点。
- UI、弹道、范围提示与特效由 Godot 原生能力生成；短促提示音由代码实时合成，不包含外部音频文件。

## 联机配置

没有本地 EOS 配置、网络不可用或 SDK 初始化失败时，标题页仍可正常进入离线单人。启用真实联机时：

1. 按 [`EOS_SETUP.md`](EOS_SETUP.md) 创建独立 Development Sandbox / Deployment 和最小权限 Client Policy。
2. 复制 `config/eos_config.example.json` 为被忽略的 `config/eos_config.local.json`，只在本机填写真实值。
3. Windows 直接运行项目；Android 先按 [`android/EOS_ANDROID_TEMPLATE.md`](android/EOS_ANDROID_TEMPLATE.md) 生成自定义 Gradle 模板。

真实凭据不会被导出预设打包，也不得写入日志、测试快照或提交记录。

## 项目结构

- `scenes/main.tscn`：固定斜俯视相机、灯光、地面、外缘环境、战斗挂点与 UI/音频入口。
- `scripts/main.gd`：独立 Lab 组合根，接线 `RunDirector`、UI、环境 GLB 与 MultiMesh。
- `scripts/core/`：对局状态、刷怪、角色、武器、对象池和数据校验。
- `scripts/online/`：`OnlineSession`、EOS/Fake 传输、网络协议、预测、重连与迁移。
- `addons/epic-online-services-godot/`：固定 EOSG 2.3.0 / EOS SDK 1.19.1.2，仅含 Windows x64、Android arm64 原生库及所需接口。
- `data/balance.json`：本实验的集中平衡配置。
- `assets/models/`：本实验实际使用的 Poly Pizza / Quaternius CC0 GLB。
- `tests/` 与 `tools/run_smoke.py`：独立 smoke 覆盖与运行入口。

## 验证

从本目录运行完整独立 smoke：

```powershell
py -3 tools/run_smoke.py --suite all
```

从仓库根目录进行正式 headless 启动检查：

```powershell
py -3 tools/godot_bridge.py --project output/lowpoly_survivors_lab headless-boot
```

smoke 成功时退出码为 `0` 且输出精确的 `ALL PASS`；日志中不得出现 `SCRIPT ERROR`、解析错误或资源加载失败。性能、模型比例、镜头遮挡、中文可读性、手柄手感、音效和难度仍需人工验收，不由自动化检查代替。

Windows 导出预设为 `Windows x64`；Android 预设为 `Android arm64`。Android Gradle 构建需要本机先安装并在 Godot 中配置 JDK 17 与 Android SDK。真实 EOS 验证需要 Development Sandbox 凭据，自动 smoke 默认使用 `FakeTransport`，不会访问线上服务。

## 素材与边界

所有外部 3D 模型来自 Poly Pizza 上 Quaternius 发布的 CC0 素材；标题页保留鸣谢，逐模型页面、Public ID、下载日期和 SHA-256 见 `asset_sources.json`，完整声明见 `THIRD_PARTY_NOTICES.md`。

该项目不依赖正式 `client/`，也不修改正式项目的 autoload、数据、locale、词表或公共 API。它不包含存档、局外成长、公开匹配、好友邀请、聊天、语音、专用服务器、Steam 或 iOS 导出。
