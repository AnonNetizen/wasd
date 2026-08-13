# Lowpoly Survivors Lab 平衡数据

`balance.json` 是此独立实验唯一的平衡配置。`run` 使用秒和米；实体 `health`、`damage`、`speed`、`radius` 均必须为正数。`pool` 是各敌人类型的池容量，常规敌人的全局活跃上限仍由 `regular_enemy_cap` 控制。

稳定内容 ID 为 `pulse_rifle`、`orbital_drone`、`ion_pulse`、`enemy_small`、`enemy_flying`、`enemy_large`、`enemy_fox_mech` 与 `final_boss`。加载器会拒绝缺少字段、非法范围、阶段不连续、未知敌人 ID 或不存在的资源路径。
