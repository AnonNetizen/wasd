# F7 SettingsLocalizationUI 工作包

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是正式项目 F7 设置 / 本地化 / UI 栈稳定化的低 token 工作包；改 F7 范围、必读文件、验收命令或可改文件时，必须同步 `docs/AI协作/README.md`、`docs/AI协作/上下文预算.md`、`docs/AI导航.md`、`docs/AI知识库索引.md`、`docs/_kb_index.json`、`docs/AI记忆/current_state.json`。

---

## 目标

在 F4/F5/F6 已有标题、HUD、暂停、升级、结算和局外成长界面的基础上，把玩家可见 UI 与可调偏好推进到正式可维护状态：

- 建立正式设置入口和设置面板，让玩家能查看 / 修改已接线生效的语言、音量、回放 / 隐私和输入相关设置；未接线设置项先不显示。
- `Settings` 从内存态推进到 `user://settings.cfg` 持久化，支持默认值、范围校验、损坏配置回退和后续迁移边界。
- `Localization` 支持运行时切换 `zh_CN` / `en`，常驻 UI 在语言变化后刷新，不需要重启游戏。
- `UIManager` 栈行为更稳定：统一返回 / 关闭、焦点、暂停叠层、设置面板从标题和暂停菜单进入后的恢复路径。
- 业务输入只通过生成 action、`InputService` 与归一化 intent；GUIDE 只允许由 `InputService` 直接访问，重绑定保存为独立 GUIDE 配置，不硬编码键盘、手柄按钮或手柄轴。
- 历史 F6 方向曾要求死亡结算页不提供局外购买入口；ADR #117 后标题旧 `MetaProgressionPanel` 已删除，当前局外装配入口为 Gear Mod 面板。

F7 的核心是“玩家能可靠调整偏好，并且 UI 在语言、暂停和栈切换下不破”，不是重做视觉风格、批量扩内容或实现复杂商店。

## 必读

1. `docs/AI协作/快速开工.md`
2. `docs/AI记忆/current_state.json`
3. 当前平台编码规则入口
4. `docs/正式项目工作规划.md` F7 段
5. `docs/游戏设计文档.md` §9.4 / §9.5 / §9.14
6. `docs/测试策略.md` 与设置 / 本地化 / UI 栈相关段落
7. `docs/代码文档规范.md`
8. `docs/代码/settings.md`
9. `docs/代码/localization.md`
10. `docs/代码/ui_manager.md`
11. `docs/代码/gameplay_runtime.md`
12. `client/locale/README.md`
13. `client/locale/strings.csv`
14. `docs/词表与契约.md` §5 / §6 / §7

只在新增设置 key、输入 action、GUIDE context、语言列、UI 栈元数据、公共 API 或测试义务变化时，补读对应 ADR、GDD 更完整段落和目标模块源码。输入变化先读 `docs/代码/input_service.md`；不要默认扫描整个 GUIDE addon。

## 建议拆分

1. **F7 现状审计与入口收口**：列出现有 TitleMenu / PauseMenu / GameplayHud / LevelUpPanel / GameOverPanel 的语言刷新、焦点、关闭路径和设置入口缺口；先不改大 UI。
2. **Settings 持久化首片（已落地）**：`Settings` 写入 `user://settings.cfg`，加载时归一化默认值，损坏配置回退到默认值；设置存档不得混进 `SaveManager` 的 `meta` / `run`。
3. **设置面板正式场景（首片已落地）**：新增 `client/scenes/ui/settings_panel.tscn` 和脚本，从标题菜单与暂停菜单进入；当前玩家可见控件覆盖语言、主音量 / 音乐 / 音效、屏幕震动、回放记录、数据收集和基础输入绑定。ADR #148 已把 `gameplay.screen_shake` 接入 Phantom Camera 玩家受伤震屏，关闭时立即停止并抑制后续震动。全屏 / 垂直同步、松开瞄准停火、自动瞄准和失焦暂停等其他未接线项暂时隐藏。
4. **运行时语言切换（核心 UI 已落地）**：设置面板修改 `general.locale` 后，`Localization` 切换 Godot locale；标题、暂停、设置、HUD、升级、结算和局外成长面板会订阅 `Localization.locale_changed`，用各自缓存的运行时数据刷新已有 label / button / 数据驱动重复项，并在 `_exit_tree()` 断开订阅。
5. **GUIDE 输入重绑定（ADR #151）**：键鼠 / 手柄 action 由 `InputService` 统一捕获和保存，移动 / 瞄准输出 Vector2 intent；设置面板按设备显示一组 slot，冲突提供替换 / 取消，保留安全关闭兜底并支持恢复默认。`Settings` schema v2 只迁移 v1 `input.*`，绑定权威为 `user://input_bindings.tres`。
6. **UIManager 栈与焦点首片（已落地）**：`UIManager` 统一监听 `ui_back`，只请求栈顶节点的 `request_close()`，不盲目出栈；`push()` 后统一给新 UI 设置默认焦点，复杂 UI 可实现 `grab_default_focus()`。已覆盖标题 / 暂停设置面板、标题局外成长面板和暂停菜单返回路径；后续可继续扩展更完整焦点环、手柄导航和输入捕获 UX。
7. **自动验证**：新增或扩展 headless smoke，覆盖设置 roundtrip、语言切换、标题 / 暂停入口打开设置面板、关闭后 UI 栈恢复，以及不破坏 `runtime-smoke` / `save-smoke`；当前 Gear Mod UI 变化追加 `gear-mod-smoke`。

## 可改文件

- `client/scripts/autoload/settings.gd`
- `client/scripts/autoload/localization.gd`
- `client/scripts/autoload/ui_manager.gd`
- `client/scenes/ui/` 中设置面板和必要 UI 场景
- `client/scripts/ui/` 中标题、暂停、HUD、升级、结算、局外成长面板的刷新 / 入口 / 焦点逻辑
- `client/project.godot` 的 GUIDE / InputService autoload、Localization 或窗口设置相关配置
- `client/locale/strings.csv` 与 `.translation` 导入产物
- `client/tools/` 与 `tools/godot_bridge.py`（新增 F7 smoke / settings smoke 入口）
- `docs/代码/settings.md`
- `docs/代码/localization.md`
- `docs/代码/ui_manager.md`
- `docs/代码/gameplay_runtime.md`
- `client/locale/README.md`
- `docs/AI导航.md`、`docs/AI记忆/current_state.json`、当日会话日志

## 禁止事项

- 不把玩家设置写进 `SaveManager` 的 `meta` / `run` kind；设置只属于 `Settings` / `user://settings.cfg`。
- 不硬编码玩家可见文本；新增文本必须走 `client/locale/strings.csv` 并补齐 `zh_CN` / `en`。
- 不硬编码键盘键位、手柄按钮或轴；业务层只消费生成 action 和 `InputService` intent。
- 不直接读写 `get_tree().paused`，暂停仍由 `GameState` / `UIManager` 协调。
- 不直接 `add_child` 长期 UI；稳定 UI 结构优先 `.tscn`，脚本只做绑定、刷新和 signal 编排。动态创建仅限数据驱动重复控件。
- 不重做整套视觉风格、不扩展完整成长树、不做云设置、不做多语言新增列、不提前做复杂无障碍系统。
- 不把 F7 设置菜单变成局外成长购买入口；ADR #117 后旧购买入口已删除，当前局外装配集中在标题 `GearModPanel`。

## 验收命令

- `python tools/sync_contracts.py --check`
- `python tools/validate_data.py`
- `python tools/test_data_loader_schema.py`
- `python tools/lint_gdscript_rules.py`
- `python tools/lint_project_rules.py`
- `python tools/test_project_rules_lint.py`
- `python tools/lint_semantic_rules.py`
- `python tools/test_semantic_rules_lint.py`
- `python tools/godot_bridge.py --project client headless-boot`
- `python tools/godot_bridge.py --project client runtime-smoke`
- 历史 `meta-smoke` 已退役；当前跨局装配相关改动跑 `python tools/godot_bridge.py --project client gear-mod-smoke`
- `python tools/godot_bridge.py --project client save-smoke`
- `python tools/godot_bridge.py --project client settings-smoke`
- `python -m json.tool docs/AI记忆/current_state.json`
- `python -m json.tool docs/_kb_index.json`
- `python tools/docs_health_check.py`
- `git diff --check -- . ":(exclude)draft/**" ":(exclude)DRAFT/**"`

## 完成定义

- 标题菜单和暂停菜单都能进入正式设置面板，关闭后回到正确 UI / 游戏状态。
- 语言、音量、回放记录、数据收集和基础输入绑定有第一版可见控件，并通过 `Settings` 读写；未接线生效的显示 / 玩法设置不显示给玩家。输入绑定首片覆盖键盘主绑定、共用键位提示和恢复输入默认，完整手柄重绑定仍待后续切片。
- `Settings` 配置能保存、重启后读取、损坏时回退默认值，并不污染玩家进度存档。
- `zh_CN` / `en` 可在运行时切换，核心常驻 UI 文案刷新，不显示裸 key；`settings-smoke` 覆盖 SettingsPanel、TitleMenu、PauseMenu、GameplayHud、LevelUpPanel 与 GameOverPanel 的既有实例刷新；Gear Mod 面板由 `gear-mod-smoke` 覆盖。
- UI 栈的 push / pop / pause / focus / back 行为有 headless smoke 或明确手动 checklist 覆盖；当前 `runtime-smoke` 已覆盖标题 / 暂停设置面板与局外成长面板的焦点和 `ui_back` 关闭路径。
- F4 / F5 / F6 既有 smoke 继续通过，特别是暂停续局、死亡结算、标题局外成长入口不回归。
- `client/locale/README.md`、`docs/代码/` 模块文档、`docs/AI导航.md` 与 AI 记忆同步。
