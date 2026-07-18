# WASD Test Lab

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。本文档是 `output/test_lab` 实验入口与本地素材约定的权威说明；新增或重做实验时同步对应 `scenes/`、`scripts/`、`tools/` 与预览截图。

这是一个 Godot 小实验沙盒，用来快速测试 UI、素材、交互和截图流程。它不是正式 `client/` 项目。

打开 `project.godot`，或直接运行该 Godot 项目。默认启动场景是 `res://scenes/test_lab_index.tscn`，里面挂当前已有实验入口。

## 目录约定

- `scenes/`：单个测试场景。
- `scripts/`：场景脚本和一次性生成脚本。
- `shaders/`：测试场景使用的 Godot shader 资源。
- `assets/`：测试场景使用的源素材。
- `data/`：实验专用的 JSON 配置与组合规则；不与正式 `client/data/` 共享 schema 或运行时加载器。
- `tools/`：截图 / 捕获脚本。
- `screenshots/`：生成的预览图。

## 新增测试

1. 在 `scenes/` 下新增场景。
2. 如需脚本，放到 `scripts/`。
3. 在 `scripts/test_lab_index.gd` 的实验清单里登记按钮名称、标签和场景路径；索引会把按钮放进滚动区。
4. 只有入口需要独立静态布局时，才通过 Godot 场景 API / 生成脚本修改 `scenes/test_lab_index.tscn`。

## 当前实验

- `neon_geometry_combat_test.tscn`：原创暗空霓虹几何战斗美术实验，借鉴高对比矢量弹幕、轮廓分型与构筑可视化原则，但不复刻任何参考作品的具体飞船、UI、图标或特效。玩家「裂锥体」使用带黑色负形裂缝的琥珀双前叉、五边形热核和紫色悬浮稳定器；断环猎体以始终朝向攻击方向的品红主缺口、错相内环和短程楔弹建立捕食读法；三轴炮体把一条青色长轴锁为主炮，另两轴作为不等长供能臂，发射慢速红色断环弹。WASD / 方向键移动、鼠标瞄准、按住左键射击，`R` 重置，`Esc` 返回索引。场地中央的折射棱芯通过折线吸收、部署波、侧模块展开、三枪口结构和升级准星，把单发裂针切换成 `-10° / 0° / +10°` 三向弹幕。背景使用确定性三层星点 / 几何残片 / 轨道弧、宽幅星云、右下画外环状星体和断角传感器边框；单位采用“极暗底板 → 实体色面 → 暗缝分段 → 高饱和热边 → 小面积白热芯”的材质层级。玩家运动带固定为 14 点，三类弹体各自保存固定 10 点环形历史：玩家弹形成金白枪线与紫色丝带，楔弹形成红色燕尾短迹，断环弹形成节奏化空心弧列。玩家、两类怪物、48 + 48 发弹池和 64 个 VFX 槽仍全部由 typed GDScript 与 `CanvasItem` draw API 构建；同一 VFX 池复用 shard / pulse / spark / glyph / lens / burst 六类表现，叠加宽透明能量盘、白热接触核、hit-stop、后坐、定向碎片、单位专属崩解、世界层微震和屏幕闪光，不增加节点。确定性捕获提供 CHARGE / CONTACT / AFTERMATH 三阶段，CONTACT 让三组三向枪线汇聚到三轴炮体的唯一白热命中点，同时保留上层猎体预警、楔弹和断环弹可读性；不依赖位图、HDR Bloom、嵌入式 `Image` 或 `PackedByteArray`。Round 0–4 的截图、参考映射、六维批评与每轮回归记录见 [`NEON_GEOMETRY_VISUAL_ITERATIONS.md`](NEON_GEOMETRY_VISUAL_ITERATIONS.md)。该实验只验证纯暗空霓虹方向的动态读图、弹幕分型与构筑反馈，不修改正式 `client/` 的美术或战斗系统。
- `ai_universal_tile_test.tscn`：AI 驱动通用 Tile 场景工作流的独立 PoC，场景配置采用实验 schema v2，美术方向为正俯视、原创粗轮廓平涂卡通。`assets/ai_tiles/abandoned_marble_conservatory/` 只保留最终的 128×128 `marble_floor_01.png`、`tree_01.png`、`wood_cabinet_01.png` 与 `style_pack.json`；三类素材均为全不透明、完整覆盖单格且彼此互斥的 Tile，不再把透明树 / 木柜叠在地板 Base 上。`data/ai_universal_tile_test.json` 以固定 seed 在 6×4 网格中生成 18 格大理石地板、3 格树和 3 格木柜，每格只允许一种 Tile；树与木柜使用与单格边界一致的整格碰撞。运行时提供四个可独立显隐的图层开关，鼠标悬停显示格坐标、tile id、tags、碰撞和交互标志，`R` 使用下一确定性 seed 重新生成，`Esc` 返回索引。PNG 通过 `Image.load()` 创建运行时纹理，不把 `.godot/imported` 当首次预览依赖，也不把 `ImageTexture` / `PackedByteArray` 写入 `.tscn`。三类素材分别由内置 `imagegen` 生成，木柜因首图木纹偏写实做了一次定向重生；全程未切换到 CLI 或需要 API key 的 fallback。`style_pack.json` 保存每张最终素材的精确提示词、生成方式和修订记录。该实验只验证“Style Pack → 三类全格原子 Tile → schema v2 场景 manifest → Godot 确定性互斥组合”的最小闭环，不代表正式 `client/` 已集成，也未覆盖透明对象叠层、多格 footprint、地形过渡 / autotile、批量变体生产、完整编辑器或运行时 AI。
- `mycelium_growth_test.tscn`：2D 虫苔 / 菌毯地表效果实验，参考《星际争霸2》虫族 creep 风格。`MyceliumPatch` 用固定 seed 在铺满房间的矩形画布上生成多个 creep 源（菌瘤），`mycelium_substrate.gdshader` 在 `vertex()` 里从局部顶点自算 UV，把各源圆盘距离场用 smooth-union 软并集融合成连续菌毯，再叠 FBM 肉质凹凸、深色凹坑、脊状血管、湿润高光，并用多频噪声扰动边界算出明亮品红、带手指状凸起的推进边缘；源半径随 growth 错峰由 0 长到 max，模拟从结节向外扩散融合。`mycelium_strand.gdshader` 画少量根暗尖亮的边缘须 runner，发光瘤状结节由脚本在源中心叠加绘制。鼠标位置作为局部活化焦点，左键加速生长，`Space` 在生长 / 枯萎目标间切换，`R` 重新生成一组菌毯，`Esc` 返回实验索引。实验不保存 PNG、`ImageTexture` 或嵌入式纹理到 `.tscn`。
- `orthographic_3d_test.tscn`：3D 正交美术切片。摄像机使用 45 度 yaw 与 30 度仰角，让 XZ 平面的等距方格在屏幕上接近 2:1 菱形；场景包含可移动玩家胶囊、鼠标瞄准、低矮缓存箱、墙体、柱子、信标、分组网格、外场底板、程序天空、远景背板与局部点光，用于观察真 3D 深度遮挡、灯光和当前 2D 菱形地图方案的差异。场景节点已保存进 `.tscn`，可直接在编辑器里选择和调整；`create_orthographic_3d_test_scene.gd` 只用于重新生成该测试场景。
- `slime_room_shooter_3d.tscn`：3D 史莱姆房间射击实验。WASD / 方向键控制史莱姆在房间内移动，鼠标射线投射到 XZ 地面决定朝向，按住鼠标左键使用 24 发轻量对象池连续射击。史莱姆软体参考 `output/steamworks_lab/scripts/slime_body.gd`：`SlimeMembrane/EdgeRig` 用 24 个 `Marker3D` 保存带 3 / 5 组宽波瓣的静止边缘，每段经 4 次 centripetal Catmull-Rom 采样形成 96 段连续低矮轮廓，再沿 6 层纬线生成唯一一份运行时 `ArrayMesh`；`Surface`、`WetCoat`、`FacePaint`、`OutlineShell` 四个渲染层共享这份网格和同一套弹簧 / 阻尼 / 邻点平滑 / 面积压力 / 移动惯性求解，不复制软体模拟。软糖卡通外观沿用 2D 实验的薄荷主体、蓝绿内馅和浅亮边配色：不透明 `Surface` 合成纵向明暗与有上限的滞后内馅，`WetCoat` 只叠窄湿润高光，暗墨绿反壳建立清晰剪影；程序化圆眼、瞳孔、反光、嘴和弱腮红贴合动态膜面，脸始终朝镜头而瞳孔追踪鼠标。`ContactLayer` 下的胶脚和柔和阴影固定在玩法根中心，随整体压扁但不跟射击前倾；史莱姆自己的弱补光也随角色移动。开火时前缘 3~5 个膜点先局部鼓包，两肩与后缘短暂压缩，受限速度沿邻点传播到后缘回弹；整体只做一次落地压扁、轻微向前送出和纵向余震，连续射击按压力上限叠加，碰撞根节点与接触层始终不后退。视觉场景采用原创“余烬地窖”弹幕房：近俯视正交镜头、48 块深色石砖、模块墙、封闭铁门、旧地毯、地牢射击靶、边缘木箱与两个暖色火盆构成封闭战斗房；弹丸保留带亮芯的拉长枪火，枪口使用黄绿色胶体圆环与三颗小胶滴组成的短促“啵”喷发。`slime_room_shooter_3d_smoke.gd` 覆盖四层共享网格、固定接触层、四方向镜头脸 / 瞳孔、内馅限幅、自然发射 / 后缘回弹、瞄准方向和池化发射；`capture_slime_room_shooter_3d.gd` 在移动连射与胶体喷发状态生成预览截图，`create_slime_room_shooter_3d_scene.gd` 是场景结构与程序化材质的权威生成入口。
- `soft_body_cell_test.tscn`：2D 软体边缘细胞实验。细胞膜由一圈程序控制点绘制，运行时使用弹簧回弹、邻点平滑、面积压力和矩形障碍物排斥力来测试压扁、回弹和保持体积；核心判定仍是简化圆形避让，避免把每个边缘点做成真实刚体。
- `emotion_blob_test.tscn`：发光气态软体「情绪团」实验。`EmotionBlob`（`emotion_blob.gd`）持一个挂 `emotion_blob.gdshader` 的 `ColorRect`，shader 用角向正弦波瓣 + `fbm` 气态扰动算会呼吸变形的软体轮廓，分层渲染外围辉光晕 / 团身气态星云 / 明亮核心；内置喜悦 / 愤怒 / 悲伤 / 平静四套情绪 profile（配色 + 形变 + 律动），切换时把运行时参数向目标 profile 平滑 lerp，实现颜色 / 形状 / 动态的平滑过渡。喜悦暖金圆润上浮、愤怒炽红不规则尖刺高频颤、悲伤冷蓝纵向泪滴下沉、平静青绿柔和慢呼吸。`Space` / 鼠标左键 / `→` 切下一情绪，`1`~`4` 直选，鼠标位置作为局部焦点，`Esc` 返回索引。封面截图取喜悦态。
- `ink_test.tscn`：中国水墨画风「水墨角色」实验。`InkField`（`ink_field.gd`）持一个铺满屏幕、挂 `ink_wash.gdshader` 的 `ColorRect`，把一组抽象墨团角色（1 玩家 + N 敌人）作为 `ink_chars` 数组传入 shader。shader 用 `smin` 软并集距离场把各角色圆盘融成连续墨场，fbm 域扭曲做毛笔不规则轮廓与渗墨；把覆盖度（墨 vs 纸）与墨色明度（焦墨↔淡墨）分离，叠浓淡斑驳、积墨湿边、双向拉伸飞白枯笔，并合成到米白宣纸（纤维纹 + 四角压暗）底。玩家居中、半径大、慢速 lissajous 游移并带一条拖尾笔锋；敌人较小、环绕、各自漂移 / 缓慢绕行。经典黑墨、非交互自动循环，`Esc` 返回索引。纯过程化 canvas_item shader，无 SubViewport / 反馈缓冲。
- `cloud_mist_test.tscn`：升腾「云雾团」粒子实验。**用粒子系统实现**（区别于其他纯 shader 实验）。`CloudMist`（`cloud_mist.gd`）用两层 `CPUParticles2D`（核心烟柱 + 外缘稀薄烟絮）从底部中心向上发射，配升腾初速 + 浮力 gravity + spread + 旋转 + `scale_amount_curve` 扩张 + `color_ramp` 先显后淡出，做出翻卷上升、越升越淡的白烟羽。每个粒子贴一张**运行时程序生成**的烟团贴图（径向羽化 × `FastNoiseLite` fbm 不规则 + 球面假光照给体积，顶亮底灰），`ImageTexture` 不写入 `.tscn`。harness 用运行时生成的 `GradientTexture2D` 铺亮色渐变天空底；`preprocess` 预热保证截图即见成形烟柱。经典白烟、非交互自动循环，`Esc` 返回索引。选 CPUParticles2D 是因 gl_compatibility 下带窗口截图更稳定。
- `advanced_cell_test.tscn`：骨骼蒙皮「复杂细胞」实验，**用节点系统让动画易控制**（在 soft_body_cell 基础上升级）。`AdvancedCell`（`advanced_cell.gd`）代码构建 `Skeleton2D` + 一圈径向 `Bone2D` 作为可动画的骨骼控制结构，`AnimationPlayer` 关键帧（代码生成 `Animation` + `AnimationLibrary`）驱动各骨的径向位置；膜 `Polygon2D` 每帧由骨骼半径用角向高斯加权平滑重建（蒙皮跟随骨骼形变），核 / 细胞器漂移脉动在 `_process` 常开。4 套动画 `idle`（循环呼吸）/ `pseudopod`（伪足伸缩）/ `divide`（收腰双叶 + 双核分列的有丝分裂）/ `engulf`（两片膜包拢吞噬橙色食物粒）由按键触发（`1`~`4`，`Space` 顺次），动作 `animation_finished` 后自动回 idle，`Esc` 返回索引。场景里放一颗圆形「石块」障碍物：膜每帧重建后用**射线-圆近交点**把朝向障碍物的膜半径截断在障碍物近表面，使膜贴壁凹陷（而非越过障碍物把它包进膜内），接触弧叠一条压力高亮线；**左键可拖动细胞撞向障碍物**实时看挤压形变。按 `B` 可开关骨架调试显示（中心枢纽 + 各骨辐条 / 关节 / 序号），直观看到骨骼如何驱动膜形变；封面截图取分裂态并显示骨架。工程上膜采用"每帧由骨骼变换重建"而非引擎 Polygon2D 蒙皮权重，规避 gl_compatibility 代码蒙皮难调试，节点系统可控性不变。

## Neon Geometry Combat 验证

以下命令均从仓库根目录运行；先把 PowerShell 变量 `$godot` 设置为 Godot Bridge 使用的同一 Godot 4.7.1 stable 可执行文件。

```powershell
# Test Lab 默认入口与实验场景启动
py -3 tools/godot_bridge.py --project output/test_lab headless-boot
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/neon_geometry_combat_test.tscn

# 角色、敌人、三类弹体、构筑切换、死亡重生与池容量 smoke
& $godot --headless --path output/test_lab --script res://tools/neon_geometry_combat_smoke.gd

# 一次捕获 CHARGE / CONTACT / AFTERMATH 三阶段与 CONTACT canonical 预览
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_neon_geometry_combat_test.gd
```

## AI Universal Tile Scene 验证

以下命令均从仓库根目录运行；先把 PowerShell 变量 `$godot` 设置为本机 Godot 4.7.1 stable 可执行文件路径。

```powershell
# Test Lab 默认入口 headless boot
py -3 tools/godot_bridge.py --project output/test_lab headless-boot

# 显式加载实验场景
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/ai_universal_tile_test.tscn

# 数据、素材、确定性布局、metadata、碰撞、圆角代码皮肤与图层 smoke
& $godot --headless --path output/test_lab --script res://tools/ai_universal_tile_smoke.gd

# 带窗口捕获最终预览
& $godot --path output/test_lab --script res://tools/capture_ai_universal_tile_test.gd

# manifest / scene config 语法
py -3 -m json.tool output/test_lab/assets/ai_tiles/abandoned_marble_conservatory/style_pack.json
py -3 -m json.tool output/test_lab/data/ai_universal_tile_test.json

# 三张最终素材存在且没有把图片数据嵌进场景；rg 退出码 1 表示无匹配
Get-Item -LiteralPath 'output/test_lab/assets/ai_tiles/abandoned_marble_conservatory/marble_floor_01.png', 'output/test_lab/assets/ai_tiles/abandoned_marble_conservatory/tree_01.png', 'output/test_lab/assets/ai_tiles/abandoned_marble_conservatory/wood_cabinet_01.png' -ErrorAction Stop
$embedded = rg -n -F -- 'PackedByteArray' output/test_lab/scenes/ai_universal_tile_test.tscn
if ($LASTEXITCODE -gt 1) { exit $LASTEXITCODE }
$embedded
$embedded = rg -n -F -- 'sub_resource type="Image"' output/test_lab/scenes/ai_universal_tile_test.tscn
if ($LASTEXITCODE -gt 1) { exit $LASTEXITCODE }
$embedded
```

三张源 PNG 保持原样；`universal_tile_grid.gd` 只负责 24 个逻辑 cell、确定性错落排序与材质参数，两类视觉已拆到 `shaders/universal_tile_obstacle_frame.gdshader` 和 `shaders/universal_tile_floor.gdshader`。障碍 Shader 在 `vertex()` 中向外扩展 11px，并把 UV 重映射回中央完整 128×128 原图；外侧依次绘制约 3px 右下接触阴影、6px 深色厚基座、2.5px 同色相中间层和 1.25px 方向性受光唇边。两档静态程序化噪声提供 0.8px / 0.35px 的局部厚薄和缺口，基座仅以最大 0.6px、5.2 秒周期做克制呼吸；9 秒局部受光会被噪声切断，不形成完整旋转光圈。地板继续使用接缝底衬、2px 对称出血和 3.5px 源图内采样消除黑缝，原先发白的独立框线改为 2.5px 低对比内边与 1px 柔和受光层；动画以格子世界坐标形成 5.6 秒连续斜向呼吸场，宽度变化不超过 0.35px。视觉外框约 150×150，但节点中心、逻辑格、鼠标坐标与碰撞仍保持完整 128×128。截图工具支持 `--capture-time=<秒>` 冻结两类 Shader 的任意动画时间，默认相位保持确定性，并关闭 collision / metadata 调试覆盖层。

## 位图 UI 素材注意事项

- `.tscn` 文件要保持轻量，不要保存生成 PNG、`ImageTexture` 或大段 `PackedByteArray`。
- 不要把 `.godot/imported` 缓存当成首次预览的唯一来源；缓存被删时外部纹理引用可能暂时失效。
- 当前位图按钮场景用 tool 脚本从 `assets/bitmap_ai` 读取 PNG 供编辑器 / 截图预览，并在保存前清掉运行时纹理，避免把图片数据写进场景。
- 如果场景文件突然变大，先检查是否出现了 `sub_resource type="Image"` 或 `PackedByteArray`。
