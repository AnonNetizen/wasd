# Godot 插件

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档记录正式 `client/` 项目内固定版本 Godot 插件的来源、许可、本地补丁与升级流程；变更插件版本或维护策略时同步 `client/README.md`、`CREDITS.md`、`docs/决策记录.md` 与 AI 记忆。

外部插件作为项目共享开发依赖直接入库并在 `project.godot` 中启用。插件不会自动更新；仓库内版本属于项目维护型 fork，修改时遵守项目 GDScript lint 与验证规则，同时保留上游版权与许可证。项目自有的 `module_authoring` 也是编辑器插件，但不是第三方依赖，不注册 autoload，release 导出排除；其契约见 `docs/代码/module_authoring_pipeline.md`。

Phantom Camera 的源码架构、公共契约、本项目 2D 接入和故障排查见 `docs/代码/phantom_camera.md`；GUIDE 的插件内部架构与项目输入边界分别见 `docs/代码/guide.md`、`docs/代码/input_service.md`。本文件继续作为所有插件版本、发布包哈希、许可和升级清单的权威。

## 固定版本

| 插件 | 版本 | Godot | 官方来源 | 发布包 SHA-256 | 许可 |
|------|------|-------|----------|------------------|------|
| `@icons` | `1.4.0` | `>= 4.6` | [Asset Store](https://store.godotengine.org/asset/voxy/at-icons/) / [源码标签](https://github.com/Voxybuns/at-icons/tree/v1.4.0) | `057D108C8FA714C3C2D07257D9FC4C3E0C55BF2B78B84886EABC33115145CEF1` | MIT；见 `at-icons/LICENSE.txt` |
| `Script-IDE` | `2.2.3` | `>= 4.5` | [Asset Store](https://store.godotengine.org/asset/maran23/script-ide/) / [源码标签](https://github.com/Maran23/script-ide/tree/2.2.3) | `FFF9581655DA6DDDF35400C9A38D5F9773406C762A84917259998ADDD6F0A6AB` | MIT；见 `script-ide/LICENSE` |
| `Phantom Camera` | `0.11.0.3` | Godot 4.x；本仓已验证 `4.7.1` | [Asset Store](https://store.godotengine.org/asset/ramokz/phantom-camera/) / [源码发布](https://github.com/ramokz/phantom-camera/releases/tag/v0.11.0.3) | `42B4BBD7CE6EFA726ABC6E927328D349887C9343FE53900A5083860C1848749B` | MIT；见 `phantom_camera/LICENSE` |
| `G.U.I.D.E` | `0.14.0` | `>= 4.2`；本仓按 Godot `4.7.1` 维护 | [Asset Library](https://godotengine.org/asset-library/asset/3503) / [源码发布](https://github.com/godotneers/G.U.I.D.E/releases/tag/v0.14.0)，固定 commit `14498eeb947b38a5f8e6cbd58d42b649a36e9346` | `3FAC6BB2D2D0B0D3C655E509519FA0F82048B465B9218433C3366A025CEC027C` | 插件 MIT，见 `guide/LICENSE.md`；Xelu prompts CC0 与 Lato 字体 SIL OFL 1.1 完整 notice 见 `guide/THIRD_PARTY_NOTICES.md` |

## 入库边界

- `@icons` 只保留发布包的 `addons/at-icons/`；不入库包根部的独立 `@icons picker.html` 或上游网页开发源码。
- `@icons` 的 SVG 配套 `.import` 文件属于发布包必需内容，和图标一起提交。
- `Script-IDE` 只保留发布包的 `addons/script-ide/`。
- `Phantom Camera` 只保留发布包的 `addons/phantom_camera/`，不入库 `examples/`；运行时管理器由项目在 `[autoload]` 固定注册，不依赖编辑器插件开关动态改项目。
- `G.U.I.D.E` 只保留发布包的 `addons/guide/`，排除 examples、tests、docs 与 GdUnit4；保留 UID、`.import`、控制器提示资源和许可证。运行时 `GUIDE` 由项目在 `[autoload]` 显式注册，插件开关不得自动增删 autoload。
- `@icons` 与 `Script-IDE` 只提供编辑器能力；`Phantom Camera` 同时提供编辑器面板和游戏运行时 API。
- `G.U.I.D.E` 同时提供编辑器面板和游戏运行时 API，当前正式项目只采用键鼠 / 单通用手柄、context、重绑定和提示；触屏、虚拟摇杆、多设备玩家槽与高级 trigger 未启用。

## 本地补丁

- `@icons`：为 dock 场景实例补充显式 `Control` 类型，统一被触碰声明的空格风格，并清理 `icon_browser.tscn` 上游行尾空白以通过仓库 whitespace 检查。
- `Script-IDE`：将普通成员移到 `@onready` 成员之前，并为上游缺失返回类型的方法补充 `-> void`；不改变插件行为。
- `Phantom Camera`：补齐强类型返回 / 参数与成员顺序，清理 4 个 C# wrapper 的上游行尾空白；将噪声 seed 接入运行时 `RNG.camera_fx` 并为编辑器预览保留确定性本地兜底；移除上游对 `Engine.physics_jitter_fix` 的全局覆写，项目显式保持 `0.5`；修正 `stop(false)` 立即清除噪声；禁用插件自动改 autoload / 重启编辑器；用 `StringName` 签名适配 Godot 4.7.1 的 `Object.is_class()`；核心 GDScript 入口保留指向 `docs/代码/phantom_camera.md` 与 ADR #148 的文件头。
- `G.U.I.D.E`：禁用 editor plugin 自动增删 autoload；按项目规范修复声明顺序、危险类型推断、缺失类型和上游 GDScript 行尾空白；由 Godot 4.7.1 规范化提示素材 `.import` 并补齐 UID；context 同优先级排序由系统时间改为单调启用序号并移除编辑器未使用计时；修复 2D 手柄轴捕获的负方向、detector 全阶段取消 / 测试注入；新增项目适配层可调用的 pressed-state 清理，并在失焦时清理鼠标与手柄按住态；input tracker 在 GUI `Control` 消费事件前从 `_input()` 转发，使全屏 HUD 不会吞掉玩法鼠标瞄准 / 开火，context 继续负责 gameplay / UI 隔离；headless 提示文本回退到物理键码字符串；核心入口保留指向 `docs/代码/guide.md` 与 ADR #151 的文件头。
- 不为插件添加 lint 忽略、目录排除或 warning 白名单。

## 手工升级

1. 从官方 Asset Store 下载目标发布包，记录版本与 SHA-256，禁止直接用仓库默认分支覆盖。
2. 在仓库外临时目录解压，只比较本表声明的 addon 子目录、许可证与 `plugin.cfg`。
3. 审查上游差异后更新 vendored 文件：Phantom Camera 按 `docs/代码/phantom_camera.md` 重放本地补丁；GUIDE 按 `docs/代码/guide.md` 重放 autoload、类型、context 序号、detector 与源码文档头补丁，并核对 `InputService` 使用的 API / signal / 资源序列化兼容；不得覆盖项目内其他改动。
4. 更新本文件、Credits、ADR 与 AI 记忆中的版本、哈希和补丁说明。
5. 运行完整 pre-commit、Godot 正式项目 headless boot、headless editor 加载及交互验收后再提交。
