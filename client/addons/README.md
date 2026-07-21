# Godot 编辑器插件

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档记录正式 `client/` 项目内固定版本编辑器插件的来源、许可、本地补丁与升级流程；变更插件版本或维护策略时同步 `client/README.md`、`CREDITS.md`、`docs/决策记录.md` 与 AI 记忆。

这些插件作为项目共享开发依赖直接入库并在 `project.godot` 中启用。插件不会自动更新；仓库内版本属于项目维护型 fork，修改时遵守项目 GDScript lint 与验证规则，同时保留上游版权与许可证。

## 固定版本

| 插件 | 版本 | Godot | 官方来源 | 发布包 SHA-256 | 许可 |
|------|------|-------|----------|------------------|------|
| `@icons` | `1.4.0` | `>= 4.6` | [Asset Store](https://store.godotengine.org/asset/voxy/at-icons/) / [源码标签](https://github.com/Voxybuns/at-icons/tree/v1.4.0) | `057D108C8FA714C3C2D07257D9FC4C3E0C55BF2B78B84886EABC33115145CEF1` | MIT；见 `at-icons/LICENSE.txt` |
| `Script-IDE` | `2.2.3` | `>= 4.5` | [Asset Store](https://store.godotengine.org/asset/maran23/script-ide/) / [源码标签](https://github.com/Maran23/script-ide/tree/2.2.3) | `FFF9581655DA6DDDF35400C9A38D5F9773406C762A84917259998ADDD6F0A6AB` | MIT；见 `script-ide/LICENSE` |

## 入库边界

- `@icons` 只保留发布包的 `addons/at-icons/`；不入库包根部的独立 `@icons picker.html` 或上游网页开发源码。
- `@icons` 的 SVG 配套 `.import` 文件属于发布包必需内容，和图标一起提交。
- `Script-IDE` 只保留发布包的 `addons/script-ide/`。
- 两个插件只通过 `[editor_plugins]` 加载，不增加游戏运行时 autoload 或公共 API。

## 本地补丁

- `@icons`：为 dock 场景实例补充显式 `Control` 类型，统一被触碰声明的空格风格，并清理 `icon_browser.tscn` 上游行尾空白以通过仓库 whitespace 检查。
- `Script-IDE`：将普通成员移到 `@onready` 成员之前，并为上游缺失返回类型的方法补充 `-> void`；不改变插件行为。
- 不为插件添加 lint 忽略、目录排除或 warning 白名单。

## 手工升级

1. 从官方 Asset Store 下载目标发布包，记录版本与 SHA-256，禁止直接用仓库默认分支覆盖。
2. 在仓库外临时目录解压，只比较本表声明的 addon 子目录、许可证与 `plugin.cfg`。
3. 审查上游差异后更新 vendored 文件，重新应用或重写本地类型与段落顺序补丁；不得覆盖项目内其他改动。
4. 更新本文件、Credits、ADR 与 AI 记忆中的版本、哈希和补丁说明。
5. 运行完整 pre-commit、Godot 正式项目 headless boot、headless editor 加载及交互验收后再提交。
