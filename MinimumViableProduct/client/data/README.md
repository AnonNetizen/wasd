# MVP Data

> **AI 修改说明**：修改本文档前先读 `MinimumViableProduct/README.md` 与 `MinimumViableProduct/docs/MVP设计说明.md`。
> 本目录存放 MVP 专用数据配置；不要与根目录完整项目的 `client/data/` 混用。

---

## 当前数据文件

| 文件 | 作用 |
|------|------|
| `mvp_config.json` | MVP 专用轻量配置，覆盖玩家生命、输入死区、武器 / 子弹、敌人、刷怪和背景关键可调数值 |

## `mvp_config.json` 字段

| 路径 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `player.max_hp` | int | `3` | 玩家初始 HP 与 HUD 最大 HP |
| `player.damage_flash_seconds` | float | `0.18` | 受伤红色描边持续时间，单位秒 |
| `input.gamepad_deadzone` | float | `0.35` | 手柄摇杆死区，范围建议 `0.0`~`1.0` |
| `weapon.fire_interval` | float | `0.35` | 自动射击间隔，单位秒 |
| `weapon.bullet_speed` | float | `520.0` | 子弹速度，单位像素 / 秒 |
| `weapon.bullet_lifetime` | float | `1.2` | 子弹寿命，单位秒 |
| `weapon.bullet_damage` | int | `1` | 子弹命中敌人造成的伤害 |
| `weapon.bullet_hitbox_radius` | float | `5.0` | 子弹圆形碰撞半径 |
| `weapon.muzzle_distance` | float | `34.0` | 子弹生成点离玩家中心的距离 |
| `enemy.move_speed` | float | `90.0` | 敌人推进速度，单位像素 / 秒 |
| `enemy.hp` | int | `1` | 敌人初始 HP |
| `enemy.contact_damage` | int | `1` | 敌人接触玩家时造成的伤害 |
| `enemy.hit_radius` | float | `29.0` | 敌人距离玩家多近时触发接触伤害 |
| `enemy.collision_radius` | float | `14.0` | 敌人圆形碰撞半径 |
| `spawner.spawn_interval` | float | `1.1` | 刷怪间隔，单位秒 |
| `spawner.spawn_margin` | float | `64.0` | 刷怪点离视口边缘的距离 |
| `spawner.initial_cooldown` | float | `0.2` | 开局第一次刷怪前等待时间，单位秒 |
| `background.grid_size` | int | `48` | 背景网格尺寸 |
| `background.lane_width` | float | `64.0` | 四方向通道高亮宽度 |
| `background.center_outer_radius` | float | `74.0` | 中心外圈半径 |
| `background.center_inner_radius` | float | `52.0` | 中心内圈半径 |
| `background.center_mark_inner` | float | `60.0` | 中心十字标记内端距离 |
| `background.center_mark_outer` | float | `95.0` | 中心十字标记外端距离 |

## 维护约定

- 调 MVP 玩法节奏时优先改 `mvp_config.json`，不要改脚本默认值。
- `main.gd` 启动时读取配置并分发给对应节点；缺字段时使用脚本默认值兜底。
- MVP 暂不引入完整项目 `DataLoader`、JSON Schema 或热重载；若配置格式错误，先以 Godot 启动日志定位。
