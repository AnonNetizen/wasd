# Module Authoring Pipeline 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 ADR #153 的模块编辑主源、烘焙产物、审核门禁与发布边界权威；修改模块场景结构、烘焙规则、生成路径、审核状态或 CLI 时必须同步 F13 工作包、数据手册、测试策略、AI 导航与 ModuleWorldManager 文档。

## 1. 三层职责

- 编辑层：`client/scenes/modules/<id>.tscn` 是布局与表现主源。根节点挂 `ModuleAuthoringRoot`，固定包含 `Ground`、`Obstacles`、`Decoration` 三个 `TileMapLayer` 和 `Placements` 容器；marker 挂 `ModulePlacementMarker`。
- 烘焙层：`ModuleSceneBaker` 从场景提取 terrain、edge socket 和 placement，生成原路径 `client/data/modules/<id>.json` 与 `client/resources/modules/<id>.tres`。JSON/TRES 都是提交入库、禁止手改的生成物。
- 运行层：JSON 继续负责导航、placement、map hash、回放与 run v4 兼容；`ModuleBakedData` schema v2 为每个允许旋转保存三层 `TileMapPattern`，并为北 / 东 / 南 / 西四条运行时封边预生成 16 种 obstacle pattern 与合并 `ConcavePolygonShape2D`。运行时只按掩码选资源，不重算碰撞；视觉资源不进入玩法 hash。

`module_templates.json` 仍是角色、来源、允许旋转和审核状态的人工策略主源；批准时由工具记录 `approved_source_hash` 作为场景 + 共用 TileSet 的内容锚点。场景或共用 TileSet 内容哈希发生变化后，普通 bake 会把已批准条目降为 `module_review_candidate` 并移除批准锚点；即使旧 TRES 缺失也不能绕过。单纯升级 baker / TRES schema 会刷新过期生成物但不会误判为制作内容变化。只有 `Approve Current` 在成功烘焙后才能重新设为 `module_review_approved`。

## 2. 编辑契约

- 模块固定 11×11 格、每格 160 px；局部 `(0,0)` 格心就是场景原点，TileMapLayer 自身偏移 `(-80,-80)`。
- `Ground` 必须覆盖 121 格且使用占位 TileSet 的 ground tile；`Obstacles` 的格表示 blocked；`Decoration` 不改变玩法地形。
- marker 位置必须吸附到 `cell * 160` 且不得越界或落墙。`placement_type` 来自生成契约，`payload` 只存 type-specific 字段，不重复保存 `cell`。
- 四边 socket 由边缘 floor 格自动推导；不得在场景或 JSON 另维护一份。全部 floor 格必须四方向连通；全 blocked 的 sealed 模块允许没有 socket。
- 第一阶段占位 TileSet 位于 `client/resources/modules/module_placeholder_tileset.tres`，以后替换美术时保持 source id / atlas 坐标契约或同步迁移器。

## 3. 工具入口

Godot 编辑器 `Tools` 菜单提供 `Modules/Bake Current`、`Modules/Bake All`、`Modules/Approve Current`。插件仅在编辑器启用，不注册 autoload。

```powershell
python tools/godot_bridge.py --project client module-bake
python tools/godot_bridge.py --project client module-bake --scene res://scenes/modules/module_start_cross.tscn
python tools/godot_bridge.py --project client module-bake-check
python tools/godot_bridge.py --project client module-bake-smoke
```

`module-bake --migrate-json` 是一次性迁移入口：先用 Godot API 从注册表的旧 JSON 创建完整场景，再要求回烘焙结果与旧 JSON 语义一致；不一致时拒绝覆盖。日常不得重复把 JSON 反向覆盖到人工场景。

## 4. 校验与发布

烘焙检查拒绝非 11×11、缺格、越界 / 未吸附 marker、未知 tile / placement id、placement 落墙、floor / socket 不连通、缺旋转资源、source hash 过期和 approved 内容未重新批准。相关路径触发条件式 pre-commit `module-bake-check`；普通无关提交不会启动 Godot。

release export 排除 `scenes/modules/`、`addons/module_authoring/`、`scripts/editor/` 和 bake runner；生成 JSON、TileSet 与 `resources/modules/*.tres` 正常打包。运行时不依赖 editor plugin 或 authoring script。
