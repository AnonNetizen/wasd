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

- `mycelium_growth_test.tscn`：2D 虫苔 / 菌毯地表效果实验，参考《星际争霸2》虫族 creep 风格。`MyceliumPatch` 用固定 seed 在铺满房间的矩形画布上生成多个 creep 源（菌瘤），`mycelium_substrate.gdshader` 在 `vertex()` 里从局部顶点自算 UV，把各源圆盘距离场用 smooth-union 软并集融合成连续菌毯，再叠 FBM 肉质凹凸、深色凹坑、脊状血管、湿润高光，并用多频噪声扰动边界算出明亮品红、带手指状凸起的推进边缘；源半径随 growth 错峰由 0 长到 max，模拟从结节向外扩散融合。`mycelium_strand.gdshader` 画少量根暗尖亮的边缘须 runner，发光瘤状结节由脚本在源中心叠加绘制。鼠标位置作为局部活化焦点，左键加速生长，`Space` 在生长 / 枯萎目标间切换，`R` 重新生成一组菌毯，`Esc` 返回实验索引。实验不保存 PNG、`ImageTexture` 或嵌入式纹理到 `.tscn`。
- `orthographic_3d_test.tscn`：3D 正交美术切片。摄像机使用 45 度 yaw 与 30 度仰角，让 XZ 平面的等距方格在屏幕上接近 2:1 菱形；场景包含可移动玩家胶囊、鼠标瞄准、低矮缓存箱、墙体、柱子、信标、分组网格、外场底板、程序天空、远景背板与局部点光，用于观察真 3D 深度遮挡、灯光和当前 2D 菱形地图方案的差异。场景节点已保存进 `.tscn`，可直接在编辑器里选择和调整；`create_orthographic_3d_test_scene.gd` 只用于重新生成该测试场景。
- `soft_body_cell_test.tscn`：2D 软体边缘细胞实验。细胞膜由一圈程序控制点绘制，运行时使用弹簧回弹、邻点平滑、面积压力和矩形障碍物排斥力来测试压扁、回弹和保持体积；核心判定仍是简化圆形避让，避免把每个边缘点做成真实刚体。
- `emotion_blob_test.tscn`：发光气态软体「情绪团」实验。`EmotionBlob`（`emotion_blob.gd`）持一个挂 `emotion_blob.gdshader` 的 `ColorRect`，shader 用角向正弦波瓣 + `fbm` 气态扰动算会呼吸变形的软体轮廓，分层渲染外围辉光晕 / 团身气态星云 / 明亮核心；内置喜悦 / 愤怒 / 悲伤 / 平静四套情绪 profile（配色 + 形变 + 律动），切换时把运行时参数向目标 profile 平滑 lerp，实现颜色 / 形状 / 动态的平滑过渡。喜悦暖金圆润上浮、愤怒炽红不规则尖刺高频颤、悲伤冷蓝纵向泪滴下沉、平静青绿柔和慢呼吸。`Space` / 鼠标左键 / `→` 切下一情绪，`1`~`4` 直选，鼠标位置作为局部焦点，`Esc` 返回索引。封面截图取喜悦态。
- `ink_test.tscn`：中国水墨画风「水墨角色」实验。`InkField`（`ink_field.gd`）持一个铺满屏幕、挂 `ink_wash.gdshader` 的 `ColorRect`，把一组抽象墨团角色（1 玩家 + N 敌人）作为 `ink_chars` 数组传入 shader。shader 用 `smin` 软并集距离场把各角色圆盘融成连续墨场，fbm 域扭曲做毛笔不规则轮廓与渗墨；把覆盖度（墨 vs 纸）与墨色明度（焦墨↔淡墨）分离，叠浓淡斑驳、积墨湿边、双向拉伸飞白枯笔，并合成到米白宣纸（纤维纹 + 四角压暗）底。玩家居中、半径大、慢速 lissajous 游移并带一条拖尾笔锋；敌人较小、环绕、各自漂移 / 缓慢绕行。经典黑墨、非交互自动循环，`Esc` 返回索引。纯过程化 canvas_item shader，无 SubViewport / 反馈缓冲。
- `cloud_mist_test.tscn`：升腾「云雾团」粒子实验。**用粒子系统实现**（区别于其他纯 shader 实验）。`CloudMist`（`cloud_mist.gd`）用两层 `CPUParticles2D`（核心烟柱 + 外缘稀薄烟絮）从底部中心向上发射，配升腾初速 + 浮力 gravity + spread + 旋转 + `scale_amount_curve` 扩张 + `color_ramp` 先显后淡出，做出翻卷上升、越升越淡的白烟羽。每个粒子贴一张**运行时程序生成**的烟团贴图（径向羽化 × `FastNoiseLite` fbm 不规则 + 球面假光照给体积，顶亮底灰），`ImageTexture` 不写入 `.tscn`。harness 用运行时生成的 `GradientTexture2D` 铺亮色渐变天空底；`preprocess` 预热保证截图即见成形烟柱。经典白烟、非交互自动循环，`Esc` 返回索引。选 CPUParticles2D 是因 gl_compatibility 下带窗口截图更稳定。
- `advanced_cell_test.tscn`：骨骼蒙皮「复杂细胞」实验，**用节点系统让动画易控制**（在 soft_body_cell 基础上升级）。`AdvancedCell`（`advanced_cell.gd`）代码构建 `Skeleton2D` + 一圈径向 `Bone2D` 作为可动画的骨骼控制结构，`AnimationPlayer` 关键帧（代码生成 `Animation` + `AnimationLibrary`）驱动各骨的径向位置；膜 `Polygon2D` 每帧由骨骼半径用角向高斯加权平滑重建（蒙皮跟随骨骼形变），核 / 细胞器漂移脉动在 `_process` 常开。4 套动画 `idle`（循环呼吸）/ `pseudopod`（伪足伸缩）/ `divide`（收腰双叶 + 双核分列的有丝分裂）/ `engulf`（两片膜包拢吞噬橙色食物粒）由按键触发（`1`~`4`，`Space` 顺次），动作 `animation_finished` 后自动回 idle，`Esc` 返回索引。场景里放一颗圆形「石块」障碍物：膜每帧重建后用**射线-圆近交点**把朝向障碍物的膜半径截断在障碍物近表面，使膜贴壁凹陷（而非越过障碍物把它包进膜内），接触弧叠一条压力高亮线；**左键可拖动细胞撞向障碍物**实时看挤压形变。封面截图取细胞贴壁凹陷态。工程上膜采用"每帧由骨骼变换重建"而非引擎 Polygon2D 蒙皮权重，规避 gl_compatibility 代码蒙皮难调试，节点系统可控性不变。

## 位图 UI 素材注意事项

- `.tscn` 文件要保持轻量，不要保存生成 PNG、`ImageTexture` 或大段 `PackedByteArray`。
- 不要把 `.godot/imported` 缓存当成首次预览的唯一来源；缓存被删时外部纹理引用可能暂时失效。
- 当前位图按钮场景用 tool 脚本从 `assets/bitmap_ai` 读取 PNG 供编辑器 / 截图预览，并在保存前清掉运行时纹理，避免把图片数据写进场景。
- 如果场景文件突然变大，先检查是否出现了 `sub_resource type="Image"` 或 `PackedByteArray`。
