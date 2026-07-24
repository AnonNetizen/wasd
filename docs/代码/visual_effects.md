# Visual Effects 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是视觉效果 catalog、profile、运行时 Host、角色表现控制器和编辑器视觉库的代码契约权威；改 schema、公开 API、挂点、生命周期、对象池或编辑器新增流程时必须同步本文档。

## 职责与边界

- `VisualEffects` autoload 只加载、索引和解析 `visual_effects.json` / `presentation_profiles.json`，并发布玩家表现策略；它不持有当前战斗世界。
- 每局 `VfxHost` 管理地面、世界和屏幕层，负责实例化、附着、取消、完成与回池；`GameplayFeedbackController` 把业务 cue 解析成视觉、音频和相机反馈。
- 角色表现由 `ActorPresentationController + AnimationPlayer` 承接；玩家 / 敌人业务脚本不再维护受击颜色计时、死亡缩放插值或直接生成命中反馈。
- 正式效果是可继承、可编辑的 `PackedScene` 或受控 target-animation preset。程序几何只能作为 Ring、Arc、Wedge、RectTelegraph、RayBurst、ShockRing、RibbonTrail、ShardBurst、SegmentedShell、FocusTicks 等组合模板内部骨架，不能作为 catalog 裸资源。
- 当前不引入离线 3D、AI / DCC 预渲染或节点式 VFX Graph；命中停顿字段只保留数据接口，不驱动 `GameClock`。

## 代码与数据地图

| 路径 | 作用 |
|------|------|
| `client/data/visual_effects.json` | 效果目录、资源、空间、生命周期、质量与 reduced-motion 策略 |
| `client/data/presentation_profiles.json` | 稳定 profile、父级继承与 cue 绑定 |
| `client/scripts/autoload/visual_effects.gd` | 只读注册表与策略解析 |
| `client/scripts/vfx/` | request、handle、ref、preset、实例生命周期与精选几何骨架 |
| `client/scripts/gameplay/presentation/` | `VfxHost`、语义反馈路由、角色表现控制器 |
| `client/scenes/vfx/composites/` | 正式组合效果场景 |
| `client/resources/vfx/presets/` | target-animation preset |
| `client/resources/vfx/curves/` | 飘字位移、透明度与缩放等可复用节奏 Curve；业务只采样，不手写插值曲线 |
| `client/shaders/vfx/` | 共享 CanvasItem shader |
| `client/addons/vfx_library/` | editor-only“VFX 效果库”主界面、预览、Inspector 与向导 |
| `client/tools/vfx_resource_baker.gd` | 首批组合场景 / preset、死亡残影和子弹 RibbonTrail 的确定性资源生成器 |
| `client/tools/vfx_smoke.gd` | catalog、策略、挂点、播放、取消和回池 smoke |

## 数据契约

`visual_effects.json.effects[]` 必填：

| 字段 | 说明 |
|------|------|
| `id` / `editor_name` | 英文稳定主键与中文编辑器显示名；筛选、复制和绑定始终使用原始 `id`，效果 id 不要求生成代码常量 |
| `domain` | `ui/actor/combat/skill/status/pickup/environment/screen` |
| `kind` | `spawned_scene/target_animation/screen_overlay` |
| `resource_path` | 正式 `res://` 资源；不得指向 addon 或 `output/test_lab` |
| `space` | `attached/world/ground/screen/ui` |
| `lifecycle` | `one_shot/loop/state` |
| `duration` | 秒；循环 / 状态效果仍需给编辑器预览窗口 |
| `high_frequency` | 高频为 `true` 时必须同时登记合法 `pool_id` |
| `quality_variants` | `low/medium/high -> effect_id`；空对象表示复用自身 |
| `reduced_motion` | `same`、`variant` 或 `suppress_optional`；可选效果会跳过，`gameplay_boundary` 必须保留；`runtime_adaptive=true` 表示资源内部切换为静态/≤100 ms 淡出 |
| `tags` / `preview` | 技术 / 读法标签与背景、检查点、尺度 |

可选池字段为 `pool_id`、`prewarm`、`max_size`。当前保留 `hit_spark`、`damage_number`，枪口效果使用 `vfx_weapon_muzzle_flash` 独立高频池。低质量只能移除装饰，不得隐藏攻击边界、阵营或状态读法。

`presentation_profiles.json.profiles[]` 以 `id` 为主键，可用可选 `editor_name` 提供中文编辑器显示名，并通过 `parent_profile_id` 继承。缺少 `editor_name` 时编辑器回退显示原始 `id`；子 profile 以 cue 为粒度覆盖父绑定。绑定可含 `effects[]`、`audio_id`、`camera_feedback_id`、`screen_effect_id` 和预留 `hit_stop_profile_id`。cue、anchor、domain、space、lifecycle、quality 等固定词进入生成契约。

## 公开 API

### `VisualEffects`

| API | 返回 | 说明 |
|-----|------|------|
| `effect(effect_id)` | `Dictionary` | 未解析的目录条目副本 |
| `profile(profile_id)` | `Dictionary` | 合并父级后的 profile |
| `resolve_binding(profile_id, cue)` | `Dictionary` | 解析单个语义 cue |
| `resolved_effect(effect_id)` | `Dictionary` | 应用质量 / reduced-motion variant |
| `current_policy()` | `Dictionary` | 质量、reduced motion、闪屏、震屏 |
| `allows_effect(effect_data)` | `bool` | 当前策略是否允许播放 |

设置变化会发出 `policy_changed(policy)`；注册表重载发出 `catalog_reloaded(effect_count, profile_count)`。

### `VfxHost`

| API | 说明 |
|-----|------|
| `play(effect_id, request = null) -> VfxHandle` | 解析策略和空间后播放 |
| `cancel_owner(owner)` | 实体回池 / 移除前取消其附着表现 |
| `cancel_all()` | 对局清理时终止全部活动效果 |
| `register_declared_pools()` | 对局启动时登记 catalog 中声明的高频效果池 |
| `declared_pool_requests()` | 返回去重后的 pool id / prewarm 请求，供同步或分帧加载入口执行 |

`VfxPlayRequest` 只携带 owner、anchor、world position、rotation、scale、seed 和表现 payload。`VfxHandle.cancel(immediate)` 是外部唯一取消入口。

### 效果实例

组合场景实现 `configure(VfxPlayRequest)`、`play()`、`cancel(immediate := false)`、`finished`、`_pool_reset()`、`_pool_release()`。效果不得调用 `Combat`、修改玩法状态或自行驱动音频；完成后的回池 / 释放由 Host 决定。

## 场景与挂点

`PlayerBase` / `EnemyBase` 固定继承：

```text
Presentation
└── AnimationPlayer
VfxAnchors
├── Center
├── Ground
├── Overhead
├── Status
└── Forward
    └── Muzzle
```

专属继承场景可调挂点位置，但不得删除或改名。attached 跟随挂点；world 脱离实体变换；ground 使用玩法系统提供的真实 footprint / 位置；screen 挂到 `ScreenFeedbackLayer`。

## 技术边界

- `AnimationPlayer` 是组合效果与 UI 转场默认时间轴，必须有 `RESET`。
- `AnimationTree` 只用于角色 / HUD 的持续多状态切换，动画仍来自 `AnimationPlayer`。
- Tween 只处理运行时动态终值，由组件持有并在取消 / 回池时 kill。
- Curve 是共享节奏资产；业务脚本不得散落手写插值曲线。
- SpriteFrames / atlas 序列帧可用，但本轮不生成离线预渲染素材。
- 共享 `ShaderMaterial` preset 视为只读；运行时参数使用副本或实例参数。
- 独立表现随机只使用 `RNG.vfx`，不得消耗 gameplay RNG。

## 编辑器流程

Godot 的“VFX 效果库”主界面使用中文显示名称与中文操作文案，但稳定 ID、资源路径、JSON 字段和枚举 metadata 保持原值。它支持按领域、技术、空间、生命周期与标签筛选；预览玩家、五种敌人、测试假人和 UI 容器；切换挂点、背景、25/50/100% 尺度、正常/减少动态效果、质量、1/8/32/64 实例及“蓄力（CHARGE）/ 接触（CONTACT）/ 余波（AFTERMATH）”。Inspector 为 `VfxEffectRef` / `PresentationProfileRef` 提供同一选择器，主界面可应用到当前选中项。

新建向导要求分别填写英文稳定 ID 与中文名称，只允许 OneShot、AttachedLoop、GroundTelegraph、UITransition、ScreenOverlay、GeometryComposite、Particle、Flipbook、Shader、AnimationTreeStateful 模板；会创建资源、登记效果目录、校验并可派生 Profile 变体。插件在 release preset 中排除。

## 接入语义

- 真实伤害才生成命中火花 / 飘字；玩家有效受伤才触发震屏与屏幕反馈。
- 玩家 / 敌人受击闪色为 0.16 秒；敌人死亡结算、掉落和移出活跃组即时发生，0.18 秒退场后回池。
- 技能成功 / 失败、Overdrive 临时强化生命周期、状态 applied/restored/expired、武器发射、拾取、机关预警 / 激活均通过内容数据的 profile cue 接线；角色、敌人、技能、武器和机关不回退到硬编码 profile，除非数据缺失且使用文档声明的默认值。
- 子弹的 `RibbonTrail` 是可复用、带共享 Shader 的精选程序几何组件，历史点在每次 acquire / release 时清空；敌人退场同时生成 world-space `actor_enemy_defeat_afterimage`，实体 0.18 秒回池后残影仍可独立完成 0.45 秒余韵。
- `WeaponSystem.active_temporary_modifiers()` 是续局重建持续表现的权威状态。

## 验证

- `python tools/validate_data.py`
- `python tools/sync_contracts.py --check`
- `python tools/godot_bridge.py --project client vfx-bake`
- `python tools/godot_bridge.py --project client vfx-smoke`
- `python tools/godot_bridge.py --project client actor-scene-smoke`
- `python tools/godot_bridge.py --project client runtime-smoke`
- `python tools/godot_bridge.py --project client headless-boot`

编辑器人工验收使用固定“蓄力（CHARGE）/ 接触（CONTACT）/ 余波（AFTERMATH）”、25% 尺度、正常 / 减少动态效果和 1/8/32/64 实例组合；性能 benchmark 只在用户当次明确要求时运行。

## 相关文档

- `docs/游戏设计文档.md` §9.24
- `docs/决策记录.md` ADR #158
- `docs/词表与契约.md` §8、§11、§16
- `docs/代码/ui_effects.md`
- `docs/代码/ui_manager.md`
- `docs/代码/gameplay_runtime.md`
- `docs/测试策略.md`
