# WASD Test Lab

这是一个 Godot 小实验沙盒，用来快速测试 UI、素材、交互和截图流程。它不是正式 `client/` 项目。

打开 `project.godot`，或直接运行该 Godot 项目。默认启动场景是 `res://scenes/test_lab_index.tscn`，里面挂当前已有实验入口。

## 目录约定

- `scenes/`：单个测试场景。
- `scripts/`：场景脚本和一次性生成脚本。
- `shaders/`：测试场景使用的 Godot shader 资源。
- `assets/`：测试场景使用的源素材。
- `tools/`：截图 / 捕获脚本。
- `screenshots/`：生成的预览图。

## 新增测试

1. 在 `scenes/` 下新增场景。
2. 如需脚本，放到 `scripts/`。
3. 在 `scenes/test_lab_index.tscn` 里加入口按钮。
4. 在 `scripts/test_lab_index.gd` 里登记按钮路径和场景路径。

## 当前实验

- `mycelium_growth_test.tscn`：2D 虫苔 / 菌毯地表效果实验。`MyceliumPatch` 用固定 seed 生成多个 blob 源，`mycelium_substrate.gdshader` 用 blob field、噪声、湿润高光、边缘渗色和脉动波纹绘制连续紫黑有机地毯；`mycelium_strand.gdshader` 只用于少量边缘触须，孢囊 / 脓包由脚本叠加绘制。鼠标位置作为局部活化焦点，左键加速生长，`Space` 在生长 / 枯萎目标间切换，`R` 重新生成一组虫苔，`Esc` 返回实验索引。实验不保存 PNG、`ImageTexture` 或嵌入式纹理到 `.tscn`。
- `orthographic_3d_test.tscn`：3D 正交美术切片。摄像机使用 45 度 yaw 与 30 度仰角，让 XZ 平面的等距方格在屏幕上接近 2:1 菱形；场景包含可移动玩家胶囊、鼠标瞄准、低矮缓存箱、墙体、柱子、信标、分组网格、外场底板、程序天空、远景背板与局部点光，用于观察真 3D 深度遮挡、灯光和当前 2D 菱形地图方案的差异。场景节点已保存进 `.tscn`，可直接在编辑器里选择和调整；`create_orthographic_3d_test_scene.gd` 只用于重新生成该测试场景。
- `soft_body_cell_test.tscn`：2D 软体边缘细胞实验。细胞膜由一圈程序控制点绘制，运行时使用弹簧回弹、邻点平滑、面积压力和矩形障碍物排斥力来测试压扁、回弹和保持体积；核心判定仍是简化圆形避让，避免把每个边缘点做成真实刚体。

## 位图 UI 素材注意事项

- `.tscn` 文件要保持轻量，不要保存生成 PNG、`ImageTexture` 或大段 `PackedByteArray`。
- 不要把 `.godot/imported` 缓存当成首次预览的唯一来源；缓存被删时外部纹理引用可能暂时失效。
- 当前位图按钮场景用 tool 脚本从 `assets/bitmap_ai` 读取 PNG 供编辑器 / 截图预览，并在保存前清掉运行时纹理，避免把图片数据写进场景。
- 如果场景文件突然变大，先检查是否出现了 `sub_resource type="Image"` 或 `PackedByteArray`。
