# UI Effects 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是共享 UI 动效组件、MotionRoot 约束与 reduced-motion 行为的代码契约权威。

## 职责

`client/scripts/ui/effects/` 提供可组合的本地 UI 表现，不承载业务状态：

- `UIEffectPlayer`：统一 Tween 所有权、取消与 reduced-motion 时长。
- `UIPanelTransition`：面板淡入 / 淡出，供 `UIManager` 和 HUD 本地播放器使用。
- `UIButtonFeedback` / `UISelectionFeedback` / `UIFocusIndicator`：按钮、选择与手柄焦点。
- `UIToast` / `UIValueFeedback` / `UIScreenAccent`：提示、数值变化与屏幕强调。
- `UIEffectSequence`：串行 / stagger 组合。

`client/scenes/ui/effects/ui_effect_bundle.tscn` 是默认组件包；`UIManager` 给栈 UI 自动安装，HUD 可本地实例化，不进入 UI 栈。

## 动画规则

- Container 内只能动画内部 `MotionRoot` 或可控视觉节点，不改 Container 管理的 size、anchor 和 layout offset。
- 面板进入默认 180ms，退出 140ms；按钮反馈、列表 stagger 保持方案规定范围。
- 运行时动态终值用组件自有 Tween；每次重播先 kill 旧 Tween。
- normal motion 可使用位移、弹性和 stagger；reduced motion 禁用位移、弹性、视差、持续 UI 粒子和循环焦点，替换为瞬时状态或不超过 100ms 的淡入淡出。
- reduced motion 与 `gameplay.screen_shake` 独立，不能暗中修改震屏设置。

## UIManager 集成

栈 UI 按 `ENTERING → ACTIVE → EXITING → REMOVED` 生命周期运行。只有 ACTIVE 栈顶接收输入；退出完成前暂停请求仍有效。`replace()` 等待旧 UI 移除再启动新 UI；`pop_expected()` 去重重复关闭；`clear(true)` 用于加载失败、回标题等硬切。

原生 `ConfirmationDialog` 已替换为 `ConfirmationModal` 正式栈场景。Loading 在正常成功路径等待 `ui_removed` 后激活 gameplay，失败 / 硬切使用 immediate。

## 扩展与验证

新 UI 优先复用共享 bundle；只有持续 HUD 多状态确有需要时才引入 `AnimationTree`。玩家可见文案继续走 locale。

- `python tools/godot_bridge.py --project client ui-manager-smoke`
- `python tools/godot_bridge.py --project client settings-smoke`
- `python tools/godot_bridge.py --project client loading-smoke`
- `python tools/godot_bridge.py --project client runtime-smoke`

人工补充检查中英文长文本、滚动可达性、键鼠 / 手柄焦点与快速连续 push/pop/replace。
