# EOS Development Sandbox 配置

本页只服务于独立实验 `Lowpoly Survivors Lab`。正式项目、Steamworks Lab 和生产 EOS 资源不复用这里的 Product、Sandbox、Deployment 或 Client。

## Developer Portal

1. 登录 [Epic Developer Portal](https://dev.epicgames.com/portal/)，新建 Product：`Lowpoly Survivors Lab`。
2. 在该 Product 中保留 Development Sandbox，并创建 Dev Deployment。
3. 启用 Epic Online Services 的 Connect、Lobby 与 P2P。登录方式仅使用 Connect Device ID；不接入 Epic Account Services、好友、语音、统计、成就或公开匹配。
4. 创建专用 Client Policy，只开放此原型所需操作：Connect Device ID 登录、Lobby 创建/搜索/加入/更新/离开，以及 P2P 收发、连接接受和 Relay。不要授予账号、好友、商业化、玩家数据写入或管理权限。
5. 创建 Client，并把它绑定到上述最小权限 Policy 和 Dev Deployment。记录 Product ID、Sandbox ID、Deployment ID、Client ID、Client Secret；为 P2P 配置一枚 64 位十六进制 Encryption Key。
6. 在数据使用与权限页面确认该内部原型没有申请额外权限。正式公开发行前仍需另行完成隐私政策、账号删除、品牌审核与生产监控，本实验不覆盖这些事项。

Portal 的页面名称可能随 EOS 后台版本调整。执行这些步骤需要项目所有者本人完成 Epic 登录与 MFA；不要把登录会话、恢复码或 MFA 内容发到仓库或聊天日志。

## 本地配置

复制模板并填写真实值：

```powershell
Copy-Item config/eos_config.example.json config/eos_config.local.json
```

`config/eos_config.local.json` 已被 `.gitignore` 排除，Windows/Android 导出预设也显式排除它。程序不会把凭据写入日志、对局检查点或 FakeTransport 测试数据。若配置缺失、占位、网络不可用或 SDK 初始化失败，联机按钮显示诊断信息，但离线单人仍可开始。

导出真实联机测试包时，另复制为同样被 Git 忽略、但会被导出打包的注入文件：

```powershell
Copy-Item config/eos_config.local.json config/eos_config.export.json
```

导出结束后可删除 `config/eos_config.export.json`。桌面调试也可用 `LOWPOLY_EOS_CONFIG_PATH` 指向仓库外的 JSON；Android 安装包无法依赖开发机环境变量，因此必须使用导出注入文件。EOS 的 Client Secret 不是可安全保存在消费端的长期秘密，本原型只给最小权限 Development Client 使用，绝不能复用生产 Client。

Android 自定义 Gradle 模板还需要通过环境变量注入公开 Client ID：

```powershell
$env:LOWPOLY_EOS_CLIENT_ID = "你的 Client ID"
py -3 tools/prepare_android_template.py --godot G:\Godot\Godot.exe
```

Client Secret 和 Encryption Key 不应写入 Gradle 脚本、AndroidManifest、资源文件或命令行历史；生产级移动客户端还需要后续独立安全设计，本内部原型不构成凭据保护方案。

## Development Sandbox 验证顺序

1. 先导出并运行两个 Windows x64 实例：创建六位房间码、加入、准备、锁房、正常战斗、普通重连、房主迁移。
2. 安装 Android arm64 debug APK，完成 Windows ↔ Android 建房、战斗、Android 接任房主和原房主回连。
3. 在升级三选一期间断网，确认 60 秒内恢复原槽位；超过 60 秒只移除掉线玩家，不代选卡。
4. 真机人工检查横屏安全区、触屏摇杆/菜单/升级卡、后台切换、网络切换、温度和中端机 30 FPS。

自动 smoke 始终使用 `FakeTransport`，不会验证 Epic 后台资源、移动网络、NAT/Relay 或真机性能。
