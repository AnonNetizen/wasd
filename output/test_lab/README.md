# WASD Test Lab

这是一个 Godot 小实验沙盒，用来快速测试 UI、素材、交互和截图流程。它不是正式 `client/` 项目。

打开 `project.godot`，或直接运行该 Godot 项目。默认启动场景是 `res://scenes/test_lab_index.tscn`，里面挂当前已有实验入口。

## 目录约定

- `scenes/`：单个测试场景。
- `scripts/`：场景脚本和一次性生成脚本。
- `assets/`：测试场景使用的源素材。
- `tools/`：截图 / 捕获脚本。
- `screenshots/`：生成的预览图。

## 新增测试

1. 在 `scenes/` 下新增场景。
2. 如需脚本，放到 `scripts/`。
3. 在 `scenes/test_lab_index.tscn` 里加入口按钮。
4. 在 `scripts/test_lab_index.gd` 里登记按钮路径和场景路径。

## 位图 UI 素材注意事项

- `.tscn` 文件要保持轻量，不要保存生成 PNG、`ImageTexture` 或大段 `PackedByteArray`。
- 不要把 `.godot/imported` 缓存当成首次预览的唯一来源；缓存被删时外部纹理引用可能暂时失效。
- 当前位图按钮场景用 tool 脚本从 `assets/bitmap_ai` 读取 PNG 供编辑器 / 截图预览，并在保存前清掉运行时纹理，避免把图片数据写进场景。
- 如果场景文件突然变大，先检查是否出现了 `sub_resource type="Image"` 或 `PackedByteArray`。
