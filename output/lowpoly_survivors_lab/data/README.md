# Lowpoly Survivors Lab 平衡数据

`balance.json` 是此独立实验唯一的平衡配置。`run` 使用秒和米；实体 `health`、`damage`、`speed`、`radius` 均必须为正数。`pool` 是各敌人类型的池容量，常规敌人的全局活跃上限仍由 `regular_enemy_cap` 控制。

稳定内容 ID 为 `pulse_rifle`、`orbital_drone`、`ion_pulse`、`enemy_small`、`enemy_flying`、`enemy_large`、`enemy_fox_mech` 与 `final_boss`。加载器会拒绝缺少字段、非法范围、阶段不连续、未知敌人 ID 或不存在的资源路径。

`animations` 使用语义状态（`idle`、`move`、`attack` / `fire`、`hit`、`death`）映射各 GLB 内的真实动画名；Boss 额外提供三种攻击状态。`player.animation_profile` 与各敌人的 `animation_profile` 必须引用有效配置。

`weapons.pulse_rifle.visual_length` 以米定义手持枪械的目标最长边；运行时会根据 GLB 实际包围盒自动归一化模型比例。

`model_yaw_degrees` 修正外部 GLB 的视觉前向轴；当前 Quaternius 角色以 `+Z` 为正面，因此统一旋转 180° 对齐 Godot `look_at()` 的 `-Z` 前向。

`network` 集中定义联机人数、20 Hz 输入、10 Hz 世界快照、1 Hz 完整检查点、60 秒重连宽限、兴趣半径、目标锁定时间和按开局人数锁定的难度倍率。业务层不得用平台常量覆盖这些值；加载器会拒绝人数超过 4、非法频率、非正宽限期或缺失的 1–4 人倍率。
