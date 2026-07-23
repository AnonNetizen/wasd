# Module Authoring Pipeline 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 ADR #154 的模块 JSON 制作主源、单向 TSCN 烘焙、审核门禁与发布边界权威；修改 JSON schema、中央主编辑区、图块目录、生成场景结构、审核状态或 CLI 时必须同步 F13 工作包、数据手册、测试策略、AI 导航与 ModuleWorldManager 文档。

## 1. 单向职责

- 制作层：`client/data/modules/<id>.json` schema v2 是布局与表现的唯一制作主源；`module_templates.json` 独立管理 role、tags、source、allowed rotations、review status 与 gameplay approval hash；`module_tile_catalog.json` 把稳定、AI 可读的 `tile_id` 映射到共享 Godot TileSet。
- 编辑层：内部 `Module JSON` 中央主编辑区只读取、校验和原子保存 JSON，不打开、不修改、不反向解析模块 TSCN。人工和 AI 可以编辑同一份可审查、可合并的数据。
- 烘焙层：`ModuleSceneBaker` 严格执行 `JSON → client/scenes/generated/modules/<id>/rotation_0.tscn`，每个模块只生成一份规范朝向场景。生成场景提交入库、禁止手改；`module-bake-check` 从 JSON 和图块目录在内存重建规范指纹，不信任 TSCN 自报 hash，并拒绝遗留的其他方向文件。
- 运行层：JSON 继续负责 assignment、导航、inactive-slot placement 查询、map hash、回放与 run v4 兼容；运行开始时按 module id 预加载本次 assignment 用到的唯一规范场景，九个 `ModuleChunk` 只挂载缓存的 `PackedScene` 实例，再对场景根节点应用 0/90/180/270° 正交旋转、方形枢轴补偿和封边方向反映射。

不存在 TSCN→JSON 入口。`--scene`、`--migrate-json`、scene inspection、模块专用 `ModuleBakedData` TRES 和运行时 pattern 应用都已删除。

## 2. JSON 与审核契约

- 模块固定 11×11 格、每格 160 px；`terrain_rows` 必须恰好 11 行，每行 11 个合法 cell token。
- `visual_layers` 固定包含 `ground`、`obstacles`、`decoration`。Ground / Obstacles 使用默认 `tile_id` 加稀疏按格覆盖；Decoration 使用稀疏格列表。视觉格支持稳定 `tile_id`、0/90/180/270° 旋转与水平/垂直翻转。
- placement 坐标和 footprint 必须为整数格、在界内并完全落在 floor；四边 socket 由边缘 floor 自动推导，JSON 不重复存储。
- 图块目录只暴露稳定 id；Godot source id、atlas 坐标和 alternative id 是目录的实现细节。首阶段共享 TileSet 位于 `client/resources/modules/module_placeholder_tileset.tres`。
- Save 只要求结构合法，因此语义未完成的 candidate 可以保存；Validate、Bake 和 Approve 必须通过完整语义校验。
- `approved_gameplay_hash` 只覆盖 terrain、派生 socket、placement、role、tags 与 allowed rotations。上述内容变化会把 approved 降为 candidate；纯表现变化保持 approved，但完整 bake hash 会变化，过期生成场景仍会令 check、提交和发布失败。
- map hash 使用与 schema v1 等价的 gameplay projection；`visual_layers`、图块目录和生成场景均不进入玩法 hash。

## 3. 中央主编辑区工作流

Godot 编辑器启用 `client/addons/module_authoring/plugin.cfg` 后，会在与 `2D`、`3D`、`Script` 同级的中央主编辑区出现 `Module JSON` 入口。界面使用左侧工具、中间 11×11 画布、右侧属性 / 校验页的可拖动三栏布局，并提供模块列表、socket / footprint / 错误覆盖层、四向预览、新建和复制；首版不提供重命名、删除或自动合并。

主编辑区使用本地 Undo/Redo、dirty 标记与显式 Save。保存采用确定性格式和原子替换，并比较打开时的磁盘 hash；若 AI 或其他工具已在外部修改 JSON，编辑器禁止静默覆盖，用户必须 Reload 或明确放弃本地修改。切换到其他主编辑器只隐藏界面，不丢失当前文档状态；Save 不自动 Bake。

主编辑区操作：

- `Save`：保存结构合法 JSON。
- `Validate`：执行完整模块、图块、placement、连通和注册策略校验。
- `Bake`：成功 Validate 后生成当前模块唯一的规范朝向 TSCN。
- `Approve`：成功 Validate 与 Bake 后写入 gameplay approval hash 并设为 approved。

## 4. CLI 与生成场景

```powershell
python tools/godot_bridge.py --project client module-bake
python tools/godot_bridge.py --project client module-bake --module module_start_cross
python tools/godot_bridge.py --project client module-bake-check
python tools/godot_bridge.py --project client module-bake-check --module module_start_cross
python tools/godot_bridge.py --project client module-bake-smoke
python tools/godot_bridge.py --project client module-json-editor-smoke
```

每个模块只生成 `rotation_0.tscn`。场景含预填充的 Ground、Obstacles、Decoration，合并后的基础地形碰撞，四个可独立启停的规范方向边缘封锁视觉 / 碰撞子树，以及 module id、固定 0°、gameplay hash、visual hash、baker schema 和规范朝向 placement 快照。allowed rotations 仍限制 assignment 可选方向，但不再扩增生成物。运行时旋转整个生成场景并做 11×11 方形枢轴补偿，同时把世界封边方向反映射到规范子树；不会创建 TileMap、合并碰撞或重算边界。

`module-bake-check` 是无写入门禁：检查 JSON v2、图块引用、允许旋转、审核状态、唯一规范生成物、遗留方向文件和场景规范指纹；生成物缺失 / 过期或人工改动 TSCN，即使保留原 metadata 也会失败。

## 5. 发布边界

相关 JSON、注册表、图块目录、共享 TileSet、baker、编辑器主界面或生成场景变化时，pre-commit 条件式运行 `module-bake-check`；普通无关提交不启动 Godot。

release export 包含模块 JSON、图块目录、共享 TileSet 和 `scenes/generated/modules/`，排除 `addons/module_authoring/`、`scripts/editor/` 与 bake runner。运行时不依赖 editor plugin、authoring script 或 JSON→场景构建代码。
