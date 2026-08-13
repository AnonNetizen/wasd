# Android EOS Gradle 模板

Godot 4.7.1 生成的 `android/build/` 含约 216 MB 引擎模板库，因此不提交到仓库。构建机先执行：

```powershell
py -3 tools/prepare_android_template.py --godot C:\path\to\Godot.exe
```

脚本会生成自定义 Gradle 模板并幂等加入 EOS SDK AAR、AndroidX 依赖、`EOSSDK.init`、arm64 所需网络权限与登录协议 scheme。真实 Client ID 仅通过 `LOWPOLY_EOS_CLIENT_ID` 环境变量注入；Product/Sandbox/Deployment/Client 配置使用被忽略、仅在导出时临时存在的 `config/eos_config.export.json`，详见 `EOS_SETUP.md`。

项目使用 Forward+，因此 Android 导出预设使用 `minSdk 28`（Android 9），同时高于 EOS Android SDK 所需的 23。导出预设只启用 `arm64-v8a`。
