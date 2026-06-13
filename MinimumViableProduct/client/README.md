# MVP Client

> **AI 修改说明**：修改本文档前先读 `MinimumViableProduct/README.md` 与 `MinimumViableProduct/docs/MVP设计说明.md`。
> 本目录存放 MVP 独立客户端代码；改客户端结构时必须同步 MVP 文档，不得顺手修改根目录 `client/`。

---

当前已建立 MVP 独立 Godot 4.6.3 项目骨架，入口场景为 `res://scenes/main.tscn`。

M4 已实现玩家受伤、失败状态、HUD 计时 / 击杀数，以及失败后重开。M4.5 已接入手柄 D-pad / 摇杆瞄准与手柄 A 重开。当前 MVP 已具备一轮可玩闭环，下一步是 M5 复盘。

当前视觉采用无贴图的几何霓虹占位风格：深色网格背景、四方向刷怪通道、中心准星、带描边的玩家 / 敌人和带拖尾感的子弹。目标是让 MVP 在没有正式美术资源前也具备可读性和基本观感。

## 预计结构

```text
MinimumViableProduct/client/
├── project.godot
├── scenes/
│   ├── main.tscn
│   ├── player.tscn
│   ├── bullet.tscn
│   └── enemy.tscn
├── scripts/
│   ├── main.gd
│   ├── background.gd
│   ├── aim_input.gd
│   ├── player.gd
│   ├── weapon.gd
│   ├── bullet.gd
│   ├── enemy.gd
│   └── spawner.gd
└── data/
    └── README.md
```

当前 `main.gd` 同时承担轻量 GameSession 职责；如果 M5 复盘认为 MVP 还要继续扩展，再考虑拆出 `game_session.gd` 与 `mvp_config.json`。

## 运行方式

1. 用 Godot 4.6.3 打开 `MinimumViableProduct/client/project.godot`。
2. 运行主场景 `res://scenes/main.tscn`。
3. 当前 M4.5 会显示玩家、方向指示、自动发射的子弹、四方向敌人、HP、时间、击杀数和失败面板。

## 客户端约束

- 只服务 MVP，不代表完整项目最终架构。
- 玩家不移动；不要实现 WASD 移动。
- 方向键、手柄 D-pad、左摇杆和右摇杆只改变四方向射击朝向。
- 敌人只从四方向刷新。
- M3 敌人按上、右、下、左的固定顺序循环刷新，不使用随机数。
- 子弹命中敌人会销毁敌人与子弹；击杀计数留到 M4。
- 敌人触碰玩家会扣 1 点 HP；HP 归零后停止刷怪和射击，显示失败面板。
- 失败后按 Godot 内置 `ui_accept`（Enter / Space / 手柄 A）重开当前场景。
- 视觉全部由 `_draw()` 和基础 UI 节点生成，当前不依赖图片 / 字体 / shader 资源。
- 当前方向输入使用 Godot 内置 InputMap action：`ui_up` / `ui_down` / `ui_left` / `ui_right`；MVP 运行时把方向键、手柄 D-pad、左摇杆、右摇杆都绑定到这组 action。
- 若某个实现经验值得进入完整项目，先写入 `MinimumViableProduct/docs/经验记录.md`，再决定是否升级到根目录 ADR。
