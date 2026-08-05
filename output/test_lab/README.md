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

- `organic_vfx_pipeline_selection_test.tscn`：独立的“有机心象脉冲”非几何 VFX 管线选型墙，不修改正式 `client/`、`visual_effects.json` 或 VFX catalog。A / B / C / D 依次比较 AI 灰度序列帧、绘制纹理粒子、灰度有机流场 + 流动 / 溶解 Shader，以及三者混合合成；四套候选共享冷静青 `#68BCDD`、愤怒粉 `#ED2F72`、白热高光、48 px 核心半径、72 px 最大装饰外延和 `CHARGE 0–0.48s / CONTACT 0.48–0.64s / AFTERMATH 0.64–1.20s / REST 1.20–1.44s` 时间轴。每张卡同时提供裁切的 2.5× 细节视窗和完整 1× 实战尺寸；`A / Space / R` 控制自动、暂停和复位，`C` 固定三阶段，`P` 切换主配色，`B` 切换暗底 / 低对比意识层 / 拥挤战斗背景，`1–4 / 0` 聚焦候选或回到总览，`D` 只显示不计入效果画面的 48 px 诊断圈。三张 1254×1254 黑底灰度源 PNG 由内置 ImageGen 生成并通过 `Image.load()` 外部加载；`style_pack.json` 保存精确提示词、尺寸和 SHA-256，4×4 图集按归一化 UV 与四舍五入单元边界运行时使用，不依赖 `.godot/imported`。候选主体不使用 `_draw()`、`Polygon2D`、`Line2D` 或正式库 Ring / Wedge / Ray 原语；`organic_vfx_pipeline_selection_smoke.gd` 覆盖资产 / manifest、统一接口与时间轴、绝对时间定位、粒子清理、节点稳定、交互状态和非几何源码门禁，截图脚本生成总览及三阶段共四张 1280×760 预览。1× 可读性、三阶段语义、有机质感、动态自然度、战斗背景表现，以及最终选择 A / B / C / D 或两种组合均保持“待用户人工验收”。
- `player_slime_fusion_test.tscn`：正式玩家改造前的独立人工门禁原型，不修改 `client/`。实战样本固定 `r=25`，旁边同时显示 `r=12` 的正式史莱姆子弹尺寸参考；两份 4.35× 放大样本常驻展示“冷静主 / 愤怒副”和“愤怒主 / 冷静副”，每个碎片只向史莱姆视觉提供一个 primary，当前为冷静 `#68BCDD`、愤怒 `#ED2F72`。每个玩家史莱姆只有 20 个环形控制点，每角固定 5 次有界二次曲线采样，最终共享 100 点边界给 `Body / Outline / WetRim`；外缘由 3 px 主碎片色边叠 1 px 主色提亮湿润边，单点速度、径向 / 切向位移、邻点速度与位移差、面积压力及最终轮缘都受限，开火和受击冲击只分散到连续 5 点，包含最宽轮缘的最终 extent 不得超过 25 px。`player_slime_dual_vortex.gdshader` 从角色本地 `VERTEX` 坐标生成 50/50 双涡旋：主 / 副智能碎片各用自身 primary，主色流顺时针、副色流逆时针；内部轮缘、外部 Outline 和中心到 38 px 枪口的常驻双端渐隐短束统一使用主碎片 primary，不再读取 secondary / accent，也不使用 `SCREEN_UV`、眼睛、箭头或长瞄准线。场景默认自动移动、开火、受击和交换实际样本；WASD / 方向键移动，左键或 `F` 开火，`H` 受击，`X` 交换实际样本主副，`Space` 暂停，`T` 切换自动演示，`R` 复位，`Esc` 返回索引。`player_slime_fusion_smoke.gd` 检查 20 / 100 点契约、仅两个 primary 运行时槽、主色轮缘 / 光束、3 / 1 px 轮缘宽度、25 px 轮缘上限、面积 / 转角 / 邻点连续性、连续移动 / 开火 / 受击、暂停冻结、五点冲击、38 px 光束、节点 / 材质稳定与固定步进确定性；`capture_player_slime_fusion.gd` 以固定步进和离开常驻光束的体内像素探针生成预览。双涡旋是否明确读成两股气、交换是否可辨、光束方向、动态尖点和与 12 px 子弹的实战区分均保持“待用户人工验收”；用户明确确认前不得接入正式 `client/`。
- `anchored_star_enemies_test.tscn`：三个自动移动的圆形敌人共享同一个 `ShaderMaterial`，内部程序化星点和星云只从 `SCREEN_UV` 采样；敌人的圆形 Polygon 只充当移动遮罩，因此敌人位移不会拖动星空，而是像三个窗口滑过同一片固定空间。三种半径和敌对轮缘色用于区分个体，运动轨迹与背景坐标标记用于观察位移，星点只做亮度闪烁而不平移 / 旋转。`Space` 暂停 / 继续，`R` 复位，`Esc` 返回索引。`anchored_star_enemies_smoke.gd` 自动检查三个敌人、共享材质、`SCREEN_UV` 锚定、实际位移和暂停冻结；`capture_anchored_star_enemies.gd` 在确定性时间点生成预览图。圆形敌人辨识度、透视感和星空密度仍待用户人工验收。
- `slime_cross_2d_test.tscn`：把史莱姆软体方法迁移到 2D 十字架凹形轮廓的独立实验。十字架由 20 个顺序轮廓点直接组成长竖干、宽横臂与四个内凹角；静止轮廓与动态轮廓都使用有界二次圆角，曲线只在相邻边构成的局部范围内弯曲，不再因 Catmull-Rom 动态过冲生成尖刺。运行时除弹簧、阻尼、邻点相对形状保持和面积压力外，还对速度与“相对静止轮廓的位移”分别做邻点扩散，让局部冲击以宽波方式传播而不是由单点领先；点击冲击也统一朝物体内部施力。绘制层以暗色反边、薄荷胶体、深青内馅、湿润高光与内部气泡建立 2D 史莱姆材质。调试骨架默认开启：紫线 / 紫圈表示静止轮廓与静止点，黄色连线 / 黄点表示动态弹簧与普通控制点，粉点表示四个内凹控制点，青色辐条表示中心骨架，静止点到动态点的青线表示当前位移；`D` 或底部按钮可隐藏 / 显示。左键点击任意边缘施加局部冲击，`Space` 压扁，`R` 复原，`A` 切换自动脉冲，`Esc` 返回索引。`slime_cross_2d_smoke.gd` 自动检查调试层开关、20 点 / 4 凹角契约、横臂与竖干比例、凹角净距、局部形变、面积保持、动态最大转角、相邻位移连续性、连续多次冲击、回弹和整体压扁；`capture_slime_cross_2d.gd` 生成开启骨架的左横臂受击阶段预览。首版“静止好、运动出现尖尖”的人工反馈已用于本次修正，最终十字辨识度、果冻质感和动态观感仍待用户复验。
- `slime_cross_perspective_test.tscn`：保留 `slime_cross_2d_test` 的 20 点凹形十字轮廓、四个内凹角、有界二次圆角、弹簧 / 阻尼 / 邻点保形、位移扩散与面积压力，只把薄荷胶体、内馅、高光和气泡替换为 `anchored_star_enemies_test` 原样复用的 `anchored_star_window.gdshader`。动态圆角边界每帧同步到一个固定 `Polygon2D + ShaderMaterial`，十字仅作为会移动、会形变的窗口；内容只从 `SCREEN_UV` 采样，因此星空不跟随十字平移或局部形变。十字沿小幅轨迹移动以暴露固定空间读法，局部冲击和整体压扁继续验证轮廓动态；`Space` 暂停移动，`F` 压扁，`R` 复原，`A` 切换自动脉冲，`D` 切换原调试骨架，左键冲击边缘，`Esc` 返回索引。`slime_cross_perspective_smoke.gd` 检查原始 20 点 / 4 凹角与比例、100 点动态圆角 Shader 遮罩、填充跟随形变、同一 Shader 资源、`SCREEN_UV` 锚定、整体位移、局部响应和面积保持；`capture_slime_cross_perspective.gd` 以固定步进生成确定性受击预览，并扫描远离轮缘的横臂内部亮像素，空白 / 透明 Shader 输出会直接失败。十字轮廓辨识度、深空间透视感、星空密度、移动时的窗口读法和边缘颜色仍待用户人工验收。
- `slime_book_perspective_test.tscn`：沿用史莱姆十字的单一闭合软体骨架、弹簧 / 阻尼 / 邻点保形、位移扩散、面积压力和动态圆角遮罩，但把 20 个静止控制点改排成左右镜像的摊开书本轮廓。顶端书脊凹口、底部书脊尖点、中央书脊线和两条页缘引导线随同一软体形变，帮助宽轮廓读成一本打开但不翻页的书；没有独立页层、翻页状态或 3D 曲面。内部继续直接复用 `anchored_star_window.gdshader`，只从 `SCREEN_UV` 采样固定空间星空。`Space` 暂停整体移动，`F` 压扁，`R` 复原，`A` 切换自动脉冲，`D` 切换骨架，左键冲击页缘，`Esc` 返回索引。`slime_book_perspective_smoke.gd` 检查 20 点单轮廓、书脊特征、左右静止对称、页宽比例、100 点动态 Shader 遮罩、整体位移、局部形变与面积保持；`capture_slime_book_perspective.gd` 以固定步进生成左页受击预览，并分别扫描左右页内部亮像素。书本辨识度、书脊线强弱、透视内容读法和边缘配色仍待用户人工验收。
- `slime_apple_perspective_test.tscn`：继续复用史莱姆十字的 20 点单闭环软体、动态圆角遮罩与 `anchored_star_window.gdshader`，只把静止轮廓改排成近圆果腹、顶部凹肩、短果柄和一片外伸叶子组成的苹果剪影。果柄与叶片都是同一外轮廓的一部分，不创建独立节点；成品绘制只含四层外轮缘和 Shader 填充，刻意不绘制叶脉、分割线、装饰线、内部标记或继承的调试骨架。`Space` 暂停整体移动，`F` 压扁，`R` 复原，`A` 切换自动脉冲，左键冲击边缘，`Esc` 返回索引。`slime_apple_perspective_smoke.gd` 检查 20 点单轮廓、果腹宽高、凹肩、果柄、叶片、底部圆度、零内部线、100 点 Shader 遮罩、整体位移、局部形变与面积保持；`capture_slime_apple_perspective.gd` 以固定步进生成右侧受击预览，并分别扫描左右果肉内部亮像素。苹果辨识度、叶片大小、轮缘配色与固定空间透视读法仍待用户人工验收。
- `svg_curve_pear_test.tscn`：按用户提供的第二版梨 SVG 原位替换旧双轮廓来源；净化后的 `assets/svg_curve/pear_source.svg` 保持原 `d` 路径与 `translate(189.226660,627.553395) scale(0.054699,-0.054699)` 坐标变换，只有一个闭合 `<path>`。轻量导入器将它直接转换为一个权威 `Curve2D + Path2D`，固定等距细分同时供内部三角化和边缘生成：内部 `ArrayMesh` 共用 `anchored_star_window.gdshader`，边缘由唯一一个无 Shader 的闭合 `Line2D` 绘制，`Line2D.width` 可在 2–30px 内独立调整而不改变内部拓扑。专用控制层默认显示 SVG 的 30 个唯一锚点和 58 个三次 Bézier 控制柄：黄色为锚点，青色为入柄，粉色为出柄，并以同色辅助线连接所属锚点；导入器为闭合复制的第 31 个末点不会重复显示。整条矢量只做平移以观察 `SCREEN_UV` 固定空间内容，没有内外双轮廓、弹簧、面积压力、质点、局部形变、背景线或非诊断装饰线。`Space` 暂停移动，`Q / E` 调细 / 调粗边缘，`D` 隐藏 / 显示控制层，`R` 复原，`Esc` 返回索引。`svg_curve_pear_smoke.gd` 检查单闭合路径、唯一 Path2D / Line2D / 控制层、锚点 / 控制柄数量、显示切换隔离、填充面积、材质分层、边宽范围、整体位移和零软体依赖；`capture_svg_curve_pear.gd` 先隐藏控制层探测内部与边，再显示控制层分别探测三类点色并生成确定性预览。控制点布局可读性、边宽 / 边色、梨形辨识度和固定空间透视读法仍待用户人工验收。
- `bullet_vfx_selection_test.tscn`：六种原创胶质子弹候选的 1280×760 动态选择墙。泪核胶珠、十字胶籽、缺口胶环、圆头胶囊、三瓣胶冠、棱面胶矢统一复用“深色反边 → 胶体外壳 → 深色内馅 → 湿润高光”材质层，只改变轮廓；每种都以完全相同的几何同时展示玩家白色和敌方红色版本。每张卡包含 4× 静态特写，以及玩家 `r=8 / 520 px/s`、敌人 `r=5 / 280 px/s` 的 1× 飞行 / 短拖尾 / 命中循环。弹丸只使用整体缩放、轴向压缩和少量相位形变，不复制十字架的完整软体求解，也不创建命中特效子节点。`Space` 暂停，`R` 重置，`D` 显示判定圆，`T` 切换拖尾，`B` 切换纯暗 / 低对比网格 / 低饱和意识层背景，`Esc` 返回索引。`bullet_vfx_selection_smoke.gd` 自动检查六种候选、红白同形、主体边界、红色主面积、固定拖尾上限、命中清尾、无节点累积和确定性重置；`capture_bullet_vfx_selection.gd` 生成总览图。最终辨识度、胶质感、阵营区分、拖尾是否误导判定及十字方案是否像治疗符号均待用户人工选型。
- `tear_core_bullet_focus_test.tscn`：用户选定 01 泪核胶珠后的 1280×760 专用放大检查场景。左右以同等尺寸超大展示玩家白弹和敌方红弹，标出反边 / 胶体 / 内馅（内核）/ 高光四层配色；底部保留玩家 `r=8 / 520 px/s` 与敌人 `r=5 / 280 px/s` 的 1× 实战飞行和命中循环。`H` 在超大弹体与超大命中效果之间切换；`Space / R / D / T / B / Esc` 分别暂停、重置、判定圆、拖尾、三档背景和返回索引。`tear_core_bullet_focus_smoke.gd` 检查超大红白同形、放大尺寸、真实 r / 速度、轮廓边界、有界拖尾、无节点命中与重置清理；`capture_tear_core_bullet_focus.gd` 生成确定性放大总览图。材质层次、轮廓辨识度、高速读法和红白区分仍待用户人工验收。
- `tear_core_material_switcher_test.tscn`：锁定泪核轮廓和圆形判定的 1280×760 七材质专场。顶部真实下拉菜单按固定顺序提供胶质基准、水晶玻璃、金属珐琅、哑光陶瓷、能量电浆、墨液烟雾和矿石晶核，默认水晶玻璃；切换时不重建节点，而是同步更新左右超大红白特写及底部玩家 `r=8 / 520 px/s`、敌人 `r=5 / 280 px/s` 的飞行 / 拖尾 / 命中样本。所有材质共享泪核几何与阵营主色，内部细节限制在判定圆内；`R` 保留当前材质，`H / D / T / B / Space / Esc` 延续泪核专场控制。`tear_core_material_switcher_smoke.gd` 检查七项菜单与默认项、唯一诊断签名、红白同形、样式同步、真实 r / 速度、主体边界、有界拖尾、命中 / 重置无残留，以及多轮切换节点数稳定；`capture_tear_core_material_switcher.gd` 固定生成默认水晶玻璃总览。材质辨识度、阵营可读性、透明背景干扰、高速读法、拖尾判定误导与下拉操作均待用户人工选型。
- `glow_orb_bullet_focus_test.tscn`：独立的 1280×760 四节点史莱姆边圆球子弹专场，不替换既有胶质与材质实验。每颗弹体固定使用东 / 南 / 西 / 北四个 `Node2D` 边缘控制点，按 Steamworks Slime Lab 的软体边缘方法以 centripetal Catmull-Rom 插值为 64 点闭合轮廓，再统一绘制内部平色和略亮的同阵营边色；玩家白弹与敌方红弹严格共享几何，只替换双色配色。当前路径不使用 Shader、纹理、渐变、局部高光、黑边或外发光，四个控制节点在飞行、命中和重置时保持稳定。左右展示超大红白弹体，底部继续演示玩家 `r=8 / 520 px/s` 与敌人 `r=5 / 280 px/s` 的实战飞行、双色短拖尾和命中。`H / D / T / B / Space / R / Esc` 分别切换超大弹体 / 命中、判定圆、拖尾、三档背景、暂停、重置和返回索引。`glow_orb_bullet_focus_smoke.gd` 检查每样本恰好四个基数方向控制节点、64 点平滑边界、红白同形、内外色差、无 Shader / 高光 / 外发光、真实半径 / 速度、有界拖尾、无动态特效节点和重置清理；`capture_glow_orb_bullet_focus.gd` 固定生成总览图，并分别探测红白内部与边缘像素，空渲染或内外同色会直接失败。最终边宽、内外色差、敌方 `r=5` 高速读法和拖尾判定误导仍待用户人工验收。
- `polygon_book_test.tscn`：通用 Polygon 素材管线的翻开书本验证场景。`assets/polygon_art/open_book_source.png` 是由提示词模板生成、再用 Godot 归一为纯 `#ff00ff` 键色背景的制作输入；运行时不读取它。编译器不包含书、书页或书脊专用标识，只从源图提取一个连通外轮廓、manifest 可选的主 `linear_band` 标志性结构及各区域的参考颜色，再自行重建共享节点、受保护共边和清晰大面。`linear_band` 由任意 `axis` / `cross_axis` 定义方向，当前 schema v3 支持零或一个主结构带；`data/polygon_imports/_linear_band_asset.template.json` 是带结构素材的 manifest 起点，书本 manifest 只是把主结构带配置成纵向书脊、把三个区域命名为左页 / 书脊 / 右页。自动 smoke 还会把同一源图旋转后用横向结构带和完全不同的区域名重新编译，确认核心算法不依赖书本坐标或语义。

  `data/polygon_prompt_templates/source_image_v1.json` 是通用生图提示词模板，要求对象仅凭外轮廓即可辨认、主体保持单一连通、使用少量硬边大色面，并拒绝阴影、纹理、悬空碎片和纯色洋红以外的背景；内部标志性结构按 manifest 可选。`polygon_prompt_builder.gd` 会把每项素材的对象描述、轮廓要点、可选结构、配色与禁用项填入模板；生成图只提供形状和颜色参考，最终点和块仍由工具构建。

  `data/polygon_art_style.json` 使用 `shape_guided` 构建模式，固定 256×256 分析分辨率、3px RDP、48–80 目标面数 / 160 硬上限、8px 最短轮廓边、80px² 最小面面积、6px 最小面高度，以及与具体物体无关的 `surface_*` / `secondary_*` / `accent_warm` / `outline` 色板角色。Style Profile 内的颜色只是缺省值；素材可在 manifest 中用同一组角色声明自身色板，编译结果保存实际色板。每个面除保留语义 `palette_role` 外，还会根据该角色、源图采样色和 Style Profile 的明暗 / 色相阶梯确定一个 `display_color`；工具以共享边建立面邻接图，优先给相邻面选择不同色阶，并把最小可见 RGB 色差作为编译硬约束。这样三角形既承担造型也承担明暗分面，而不是大量拓扑共用少数平色。轮廓清理与细分仍必须满足面积和高度门槛，坏拓扑会直接令编译失败，不通过增加细碎面、共色或隐藏小面掩盖。当前书本产出 48 面、32 个共享逻辑顶点、14 个轮廓节点；书脊源图检测宽度约 3px，工具构建宽度为 20px，并由两条受保护边围成 3 个明确面。

  `PolygonAsset2D` 的通用职责只包含网格加载、逐面显示色、`generation_progress` 按面顺序生成和 `dissolve_progress` 按面顺序消散。通用运行时、通用 Shader、调试网格和 manifest 模板不再提供速度输入、移动形变、软体弹簧或移动染色；敌人的世界位移由持有素材的玩法节点自行负责，视觉素材保持稳定。`motion_profile` 只保留生命周期色阶绑定和物体专属适配器需要的语义区域 / 局部轴，不能用于通用移动动画。`polygon_asset.gdshader` 不含翻页、开箱、挥动或敌人移动等物体语义算法。

  翻页属于书本自己的 `PolygonBookAnimator` 和 `polygon_book_page_turn.gdshader`：书本 manifest 通过 `custom_animation.adapter = book_page_turn` 选择它，适配器只负责翻页进度、折痕点位和页面色变，同时保留通用 Shader 的生成与消散契约。每个原始平色面仍只展开一次，统一生成一个单层 `ArrayMesh` surface，不复制底层或覆盖层。书本场景自动依次演示通用生成、静止、书本专用翻页、通用消散和复原；`A` 关闭 / 重启自动演示，`G` 手动生成，`Space` 手动翻页，`C` 手动消散 / 复原，`M` 切网格、`O` 切源图、`R` 重置、`Esc` 返回索引。`polygon_asset_smoke.gd` 分别断言通用运行时不含翻页或移动形变算法、相邻面的显示色差达到 Style Profile 下限，以及翻页 API 只存在于书本适配器。最终风格、标志性结构辨识度、轮廓可读性和动画观感仍为待用户人工验收。
- `polygon_apple_test.tscn`：无主结构带的通用素材验证。`apple_source.png` 由内置 imagegen 以纯洋红背景生成并由 Godot 归一键色；苹果 manifest 使用 `feature_guides: []`、独立红 / 绿角色色板、单一 `apple` 区域和空 `custom_animation`。工具只提取连通外轮廓与参考颜色，自行生成 48 个清晰面、35 个逻辑点和 20 个轮廓节点；果柄与叶片依靠外轮廓与大色面辨认，没有伪造贯穿苹果的结构带。场景不再移动或变形苹果，只自动演示生成、静态逐面配色、消散和复原；截图条带保存生命周期的确定性阶段。`A`、`G`、`C`、`M`、`O`、`R`、`Esc` 控制含义与书本场景对应，`polygon_apple_asset_smoke.gd` 额外验证无特征编译、manifest 色板覆盖、相邻面色差、显示色多样性、静态位置、单层无纹理运行时和确定性输出。最终苹果轮廓与逐面配色质感仍待用户人工验收。
- `shader_lab.tscn`：可长期扩展的全屏 2D Shader 背景实验场。控制器从注册表填充 Shader 选择器，并以统一的 `animation_time` / `motion_speed` / `effect_intensity` / `pattern_scale` / `gameplay_mix` / `viewport_aspect` uniform 契约驱动外部 `canvas_item` Shader；参数只在本次运行内按“Shader + 预设”组合保留，不写存档。首批“旋转星云穿行”用五层程序化星点、低频星云、纵深缩放和缓慢旋转表现向镜头推进；“水火双流体涡旋”用两组反向域扭曲 FBM 场形成冷水 / 热火与蒸汽交界。两者都提供高冲击展示预设和压暗、降低中心活动的游戏预设，后者用于保护居中角色及青 / 红 / 白功能色可读性。面板可调速度、强度和纹理尺度，并显示实时 FPS；`1` / `2` 直选，`Tab` 切 Shader，`M` 切预设，`Space` 暂停，`R` 重置，`H` 隐藏面板，`Esc` 返回索引。纯过程化实现不依赖贴图、SubViewport、反馈缓冲或内置 `TIME`；`shader_lab_smoke.gd` 覆盖资源、共享 uniform、预设、会话参数、暂停 / 恢复、重置、面板和宽高比，`capture_shader_lab.gd` 确定性生成四张展示 / 游戏预览。
- `neon_geometry_combat_test.tscn`：原创暗空霓虹几何战斗美术实验，借鉴高对比矢量弹幕、轮廓分型与构筑可视化原则，但不复刻任何参考作品的具体飞船、UI、图标或特效。玩家「裂锥体」使用带黑色负形裂缝的琥珀双前叉、五边形热核和紫色悬浮稳定器；断环猎体以始终朝向攻击方向的品红主缺口、错相内环和短程楔弹建立捕食读法；三轴炮体把一条青色长轴锁为主炮，另两轴作为不等长供能臂，发射慢速红色断环弹。WASD / 方向键移动、鼠标瞄准、按住左键射击，`R` 重置，`Esc` 返回索引。场地中央的折射棱芯通过折线吸收、部署波、侧模块展开、三枪口结构和升级准星，把单发裂针切换成 `-10° / 0° / +10°` 三向弹幕。背景使用确定性三层星点 / 几何残片 / 轨道弧、宽幅星云、右下画外环状星体和断角传感器边框；单位采用“极暗底板 → 实体色面 → 暗缝分段 → 高饱和热边 → 小面积白热芯”的材质层级。玩家运动带固定为 14 点，三类弹体各自保存固定 10 点环形历史：玩家弹形成金白枪线与紫色丝带，楔弹形成红色燕尾短迹，断环弹形成节奏化空心弧列。玩家、两类怪物、48 + 48 发弹池和 64 个 VFX 槽仍全部由 typed GDScript 与 `CanvasItem` draw API 构建；同一 VFX 池复用 shard / pulse / spark / glyph / lens / burst 六类表现，叠加宽透明能量盘、白热接触核、hit-stop、后坐、定向碎片、单位专属崩解、世界层微震和屏幕闪光，不增加节点。确定性捕获提供 CHARGE / CONTACT / AFTERMATH 三阶段，CONTACT 让三组三向枪线汇聚到三轴炮体的唯一白热命中点，同时保留上层猎体预警、楔弹和断环弹可读性；不依赖位图、HDR Bloom、嵌入式 `Image` 或 `PackedByteArray`。Round 0–4 的截图、参考映射、六维批评与每轮回归记录见 [`NEON_GEOMETRY_VISUAL_ITERATIONS.md`](NEON_GEOMETRY_VISUAL_ITERATIONS.md)。该实验只验证纯暗空霓虹方向的动态读图、弹幕分型与构筑反馈，不修改正式 `client/` 的美术或战斗系统。
- `ai_universal_tile_test.tscn`：AI 驱动通用 Tile 场景工作流的独立 PoC，场景配置采用实验 schema v2，美术方向为正俯视、原创粗轮廓平涂卡通。`assets/ai_tiles/abandoned_marble_conservatory/` 只保留最终的 128×128 `marble_floor_01.png`、`tree_01.png`、`wood_cabinet_01.png` 与 `style_pack.json`；三类素材均为全不透明、完整覆盖单格且彼此互斥的 Tile，不再把透明树 / 木柜叠在地板 Base 上。`data/ai_universal_tile_test.json` 以固定 seed 在 6×4 网格中生成 18 格大理石地板、3 格树和 3 格木柜，每格只允许一种 Tile；树与木柜使用与单格边界一致的整格碰撞。运行时提供四个可独立显隐的图层开关，鼠标悬停显示格坐标、tile id、tags、碰撞和交互标志，`R` 使用下一确定性 seed 重新生成，`Esc` 返回索引。PNG 通过 `Image.load()` 创建运行时纹理，不把 `.godot/imported` 当首次预览依赖，也不把 `ImageTexture` / `PackedByteArray` 写入 `.tscn`。三类素材分别由内置 `imagegen` 生成，木柜因首图木纹偏写实做了一次定向重生；全程未切换到 CLI 或需要 API key 的 fallback。`style_pack.json` 保存每张最终素材的精确提示词、生成方式和修订记录。该实验只验证“Style Pack → 三类全格原子 Tile → schema v2 场景 manifest → Godot 确定性互斥组合”的最小闭环，不代表正式 `client/` 已集成，也未覆盖透明对象叠层、多格 footprint、地形过渡 / autotile、批量变体生产、完整编辑器或运行时 AI。
- `mycelium_growth_test.tscn`：2D 虫苔 / 菌毯地表效果实验，参考《星际争霸2》虫族 creep 风格。`MyceliumPatch` 用固定 seed 在铺满房间的矩形画布上生成多个 creep 源（菌瘤），`mycelium_substrate.gdshader` 在 `vertex()` 里从局部顶点自算 UV，把各源圆盘距离场用 smooth-union 软并集融合成连续菌毯，再叠 FBM 肉质凹凸、深色凹坑、脊状血管、湿润高光，并用多频噪声扰动边界算出明亮品红、带手指状凸起的推进边缘；源半径随 growth 错峰由 0 长到 max，模拟从结节向外扩散融合。`mycelium_strand.gdshader` 画少量根暗尖亮的边缘须 runner，发光瘤状结节由脚本在源中心叠加绘制。鼠标位置作为局部活化焦点，左键加速生长，`Space` 在生长 / 枯萎目标间切换，`R` 重新生成一组菌毯，`Esc` 返回实验索引。实验不保存 PNG、`ImageTexture` 或嵌入式纹理到 `.tscn`。
- `orthographic_3d_test.tscn`：3D 正交美术切片。摄像机使用 45 度 yaw 与 30 度仰角，让 XZ 平面的等距方格在屏幕上接近 2:1 菱形；场景包含可移动玩家胶囊、鼠标瞄准、低矮缓存箱、墙体、柱子、信标、分组网格、外场底板、程序天空、远景背板与局部点光，用于观察真 3D 深度遮挡、灯光和当前 2D 菱形地图方案的差异。场景节点已保存进 `.tscn`，可直接在编辑器里选择和调整；`create_orthographic_3d_test_scene.gd` 只用于重新生成该测试场景。
- `slime_room_shooter_3d.tscn`：3D 史莱姆房间射击实验。WASD / 方向键控制史莱姆在房间内移动，鼠标射线投射到 XZ 地面决定朝向，按住鼠标左键使用 24 发轻量对象池连续射击。史莱姆软体参考 `output/steamworks_lab/scripts/slime_body.gd`：`SlimeMembrane/EdgeRig` 用 24 个 `Marker3D` 保存带 3 / 5 组宽波瓣的静止边缘，每段经 4 次 centripetal Catmull-Rom 采样形成 96 段连续低矮轮廓，再沿 6 层纬线生成唯一一份运行时 `ArrayMesh`；`Surface`、`WetCoat`、`FacePaint`、`OutlineShell` 四个渲染层共享这份网格和同一套弹簧 / 阻尼 / 邻点平滑 / 面积压力 / 移动惯性求解，不复制软体模拟。软糖卡通外观沿用 2D 实验的薄荷主体、蓝绿内馅和浅亮边配色：不透明 `Surface` 合成纵向明暗与有上限的滞后内馅，`WetCoat` 只叠窄湿润高光，暗墨绿反壳建立清晰剪影；程序化圆眼、瞳孔、反光、嘴和弱腮红贴合动态膜面，脸始终朝镜头而瞳孔追踪鼠标。`ContactLayer` 下的胶脚和柔和阴影固定在玩法根中心，随整体压扁但不跟射击前倾；史莱姆自己的弱补光也随角色移动。开火时前缘 3~5 个膜点先局部鼓包，两肩与后缘短暂压缩，受限速度沿邻点传播到后缘回弹；整体只做一次落地压扁、轻微向前送出和纵向余震，连续射击按压力上限叠加，碰撞根节点与接触层始终不后退。视觉场景采用原创“余烬地窖”弹幕房：近俯视正交镜头、48 块深色石砖、模块墙、封闭铁门、旧地毯、地牢射击靶、边缘木箱与两个暖色火盆构成封闭战斗房；弹丸保留带亮芯的拉长枪火，枪口使用黄绿色胶体圆环与三颗小胶滴组成的短促“啵”喷发。`slime_room_shooter_3d_smoke.gd` 覆盖四层共享网格、固定接触层、四方向镜头脸 / 瞳孔、内馅限幅、自然发射 / 后缘回弹、瞄准方向和池化发射；`capture_slime_room_shooter_3d.gd` 在移动连射与胶体喷发状态生成预览截图，`create_slime_room_shooter_3d_scene.gd` 是场景结构与程序化材质的权威生成入口。
- `slime_tombstone_test.tscn`：把 3D 史莱姆的软体美术方法迁移到非圆形墓碑轮廓的独立实验。`SlimeTombstone/EdgeRig` 用 18 个 `Marker3D` 保存“固定碑底 + 直立碑身 + 拱顶”轮廓，每段经 3 次 centripetal Catmull-Rom 采样形成连续外边；运行时以弹簧、阻尼、邻点形状保持、面积压力和独立深度回弹更新唯一 `ArrayMesh`，`Surface`、`WetCoat`、`OutlineShell` 三层共享该网格。底部控制点使用低移动权重，局部冲击只让命中附近的碑身向内凹、侧缘传波并回弹；`Space` 施加整体压扁，`R` 复原，`A` 切换自动脉冲，鼠标左键可在碑面任意位置施力，`Esc` 返回索引。材质沿用史莱姆的“本体 + 内馅 + 湿润高光 + 反壳描边”结构，但换成幽绿胶石配色，并以程序裂纹和随动态膜面移动的 `RIP` 标记保留墓碑读法；背景刚性墓碑用于对照。`slime_tombstone_smoke.gd` 自动检查非圆形轮廓、三层共享网格、局部形变、碑底锚定、面积保持和回弹收敛；`capture_slime_tombstone_test.gd` 生成局部受击阶段预览，最终轮廓辨识度、胶体/石材比例与动态观感仍待用户人工验收。
- `soft_body_cell_test.tscn`：2D 软体边缘细胞实验。细胞膜由一圈程序控制点绘制，运行时使用弹簧回弹、邻点平滑、面积压力和矩形障碍物排斥力来测试压扁、回弹和保持体积；核心判定仍是简化圆形避让，避免把每个边缘点做成真实刚体。
- `emotion_blob_test.tscn`：发光气态软体「情绪团」实验。`EmotionBlob`（`emotion_blob.gd`）持一个挂 `emotion_blob.gdshader` 的 `ColorRect`，shader 用角向正弦波瓣 + `fbm` 气态扰动算会呼吸变形的软体轮廓，分层渲染外围辉光晕 / 团身气态星云 / 明亮核心；内置喜悦 / 愤怒 / 悲伤 / 平静四套情绪 profile（配色 + 形变 + 律动），切换时把运行时参数向目标 profile 平滑 lerp，实现颜色 / 形状 / 动态的平滑过渡。喜悦暖金圆润上浮、愤怒炽红不规则尖刺高频颤、悲伤冷蓝纵向泪滴下沉、平静青绿柔和慢呼吸。`Space` / 鼠标左键 / `→` 切下一情绪，`1`~`4` 直选，鼠标位置作为局部焦点，`Esc` 返回索引。封面截图取喜悦态。
- `ink_test.tscn`：中国水墨画风「水墨角色」实验。`InkField`（`ink_field.gd`）持一个铺满屏幕、挂 `ink_wash.gdshader` 的 `ColorRect`，把一组抽象墨团角色（1 玩家 + N 敌人）作为 `ink_chars` 数组传入 shader。shader 用 `smin` 软并集距离场把各角色圆盘融成连续墨场，fbm 域扭曲做毛笔不规则轮廓与渗墨；把覆盖度（墨 vs 纸）与墨色明度（焦墨↔淡墨）分离，叠浓淡斑驳、积墨湿边、双向拉伸飞白枯笔，并合成到米白宣纸（纤维纹 + 四角压暗）底。玩家居中、半径大、慢速 lissajous 游移并带一条拖尾笔锋；敌人较小、环绕、各自漂移 / 缓慢绕行。经典黑墨、非交互自动循环，`Esc` 返回索引。纯过程化 canvas_item shader，无 SubViewport / 反馈缓冲。
- `cloud_mist_test.tscn`：升腾「云雾团」粒子实验。**用粒子系统实现**（区别于其他纯 shader 实验）。`CloudMist`（`cloud_mist.gd`）用两层 `CPUParticles2D`（核心烟柱 + 外缘稀薄烟絮）从底部中心向上发射，配升腾初速 + 浮力 gravity + spread + 旋转 + `scale_amount_curve` 扩张 + `color_ramp` 先显后淡出，做出翻卷上升、越升越淡的白烟羽。每个粒子贴一张**运行时程序生成**的烟团贴图（径向羽化 × `FastNoiseLite` fbm 不规则 + 球面假光照给体积，顶亮底灰），`ImageTexture` 不写入 `.tscn`。harness 用运行时生成的 `GradientTexture2D` 铺亮色渐变天空底；`preprocess` 预热保证截图即见成形烟柱。经典白烟、非交互自动循环，`Esc` 返回索引。选 CPUParticles2D 是因 gl_compatibility 下带窗口截图更稳定。
- `advanced_cell_test.tscn`：骨骼蒙皮「复杂细胞」实验，**用节点系统让动画易控制**（在 soft_body_cell 基础上升级）。`AdvancedCell`（`advanced_cell.gd`）代码构建 `Skeleton2D` + 一圈径向 `Bone2D` 作为可动画的骨骼控制结构，`AnimationPlayer` 关键帧（代码生成 `Animation` + `AnimationLibrary`）驱动各骨的径向位置；膜 `Polygon2D` 每帧由骨骼半径用角向高斯加权平滑重建（蒙皮跟随骨骼形变），核 / 细胞器漂移脉动在 `_process` 常开。4 套动画 `idle`（循环呼吸）/ `pseudopod`（伪足伸缩）/ `divide`（收腰双叶 + 双核分列的有丝分裂）/ `engulf`（两片膜包拢吞噬橙色食物粒）由按键触发（`1`~`4`，`Space` 顺次），动作 `animation_finished` 后自动回 idle，`Esc` 返回索引。场景里放一颗圆形「石块」障碍物：膜每帧重建后用**射线-圆近交点**把朝向障碍物的膜半径截断在障碍物近表面，使膜贴壁凹陷（而非越过障碍物把它包进膜内），接触弧叠一条压力高亮线；**左键可拖动细胞撞向障碍物**实时看挤压形变。按 `B` 可开关骨架调试显示（中心枢纽 + 各骨辐条 / 关节 / 序号），直观看到骨骼如何驱动膜形变；封面截图取分裂态并显示骨架。工程上膜采用"每帧由骨骼变换重建"而非引擎 Polygon2D 蒙皮权重，规避 gl_compatibility 代码蒙皮难调试，节点系统可控性不变。

## Organic Mind VFX Pipeline Selection 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 可执行文件。截图命令需要正常渲染窗口，其他门禁均可 headless 执行。

```powershell
# 生成轻量场景、正式扫描 Test Lab、显式加载场景和索引入口
& $godot --headless --path output/test_lab --script res://scripts/create_organic_vfx_pipeline_selection_scene.gd
py -3 tools/godot_bridge.py --project output/test_lab headless-boot
& $godot --headless --path output/test_lab --quit-after 8 res://scenes/organic_vfx_pipeline_selection_test.tscn
& $godot --headless --path output/test_lab --quit-after 8 res://scenes/test_lab_index.tscn

# 外部素材 / manifest、四候选统一契约、绝对时间、粒子清理、节点稳定和非几何门禁
& $godot --headless --path output/test_lab --script res://tools/organic_vfx_pipeline_selection_smoke.gd

# 生成总览、CHARGE、CONTACT、AFTERMATH 四张 1280×760 预览
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_organic_vfx_pipeline_selection.gd
```

## Shader Lab 验证

以下命令均从仓库根目录运行；`$godot` 指向项目配置使用的 Godot 4.7.1 stable 可执行文件。

```powershell
# Test Lab 入口与 Shader Lab 显式加载
py -3 tools/godot_bridge.py --project output/test_lab headless-boot
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/shader_lab.tscn

# 共享 uniform、选择 / 预设、基础参数、暂停 / 重置和宽高比 smoke
& $godot --headless --path output/test_lab --script res://tools/shader_lab_smoke.gd

# 在 1280×760 生成星空 / 水火各自的展示版与游戏版截图
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_shader_lab.gd

# 16:9 人工性能与宽高比验收
& $godot --resolution 1920x1080 --path output/test_lab res://scenes/shader_lab.tscn
```

新增背景 Shader 时，把外部 `.gdshader` 放入 `shaders/`，实现上述六个共享 uniform，再在 `shader_lab.gd` 的 `SHADER_DEFINITIONS` 注册名称、说明和两套基础预设；统一面板、会话参数、暂停与截图入口无需复制。

## Anchored Star Enemies 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 可执行文件。

```powershell
# 生成轻量场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_anchored_star_enemies_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/anchored_star_enemies_test.tscn

# 三敌人、共享材质、SCREEN_UV 锚定、位移与暂停冻结
& $godot --headless --path output/test_lab --script res://tools/anchored_star_enemies_smoke.gd

# 在 1280×760 的确定性时间点生成预览图
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_anchored_star_enemies.gd
```

## Polygon Asset Pipeline 验证

以下命令均从仓库根目录运行；`$godot` 指向项目配置使用的 Godot 4.7.1 stable 可执行文件。源图生成后只需执行一次键色归一，日常修改 Style Profile 或 manifest 时从编译命令开始。

```powershell
# 制作输入键色归一；只改与洋红键色足够接近的背景像素
& $godot --headless --path output/test_lab --script res://tools/normalize_polygon_source.gd -- --source=res://assets/polygon_art/open_book_source.png
& $godot --headless --path output/test_lab --script res://tools/normalize_polygon_source.gd -- --source=res://assets/polygon_art/apple_source.png

# 通用提示词模板 + 素材 manifest → 可直接交给 imagegen 的生图提示词
& $godot --headless --path output/test_lab --script res://tools/build_polygon_prompt.gd -- --manifest=res://data/polygon_imports/open_book.json
& $godot --headless --path output/test_lab --script res://tools/build_polygon_prompt.gd -- --manifest=res://data/polygon_imports/apple.json

# 通用 manifest → Polygon JSON 编译
& $godot --headless --path output/test_lab --script res://tools/polygon_asset_compiler.gd -- --manifest=res://data/polygon_imports/open_book.json
& $godot --headless --path output/test_lab --script res://tools/polygon_asset_compiler.gd -- --manifest=res://data/polygon_imports/apple.json

# Test Lab 版本 / 入口、实验场景显式加载
py -3 tools/godot_bridge.py --project output/test_lab godot-version
py -3 tools/godot_bridge.py --project output/test_lab export-tree
py -3 tools/godot_bridge.py --project output/test_lab headless-boot
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/polygon_book_test.tscn
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/polygon_apple_test.tscn

# 编译确定性、schema、拓扑、色板、区域、锚点、碰撞与运行时约束
& $godot --headless --path output/test_lab --script res://tools/polygon_asset_smoke.gd
& $godot --headless --path output/test_lab --script res://tools/polygon_apple_asset_smoke.gd

# 1280×760 自动生成静态对比、通用生命周期条带、翻页中段与翻页条带截图
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_polygon_book_test.gd
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_polygon_apple_test.gd

# 确认场景没有嵌入位图数据；rg 退出码 1 表示无匹配
$embedded = rg -n -F -- 'PackedByteArray' output/test_lab/scenes/polygon_book_test.tscn
if ($LASTEXITCODE -gt 1) { exit $LASTEXITCODE }
$embedded
$embedded = rg -n -F -- 'sub_resource type="Image"' output/test_lab/scenes/polygon_book_test.tscn
if ($LASTEXITCODE -gt 1) { exit $LASTEXITCODE }
$embedded
```

新素材若只依赖连通外轮廓，复制 `data/polygon_imports/_silhouette_asset.template.json`；若有一条贯穿主体的连续结构带，复制 `_linear_band_asset.template.json`。填写提示词变量、源图、角色色板、区域名、`motion_profile`、锚点与碰撞策略；默认 `custom_animation` 为空，只有确实需要物体语义动作时才增加独立适配器和专用 Shader，不能把动作写回通用运行时。当前通用 schema v3 支持零或一个主连续结构带；需要多个独立结构或闭合内部轮廓时应新增通用 feature 类型，不能把对象名称写进编译器。运行时素材的权威输入是 `data/polygon_assets/*.polygon.json`、`polygon_asset_2d.gd` 与外部 shader；源 PNG 只作为制作证据和 Lab 对照。Style Profile、提示词模板与 schema v3 都是 Test Lab 私有实验约定，不自动成为正式项目契约。

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

## Slime Tombstone 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
# 生成 / 更新结构化场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_slime_tombstone_test_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/slime_tombstone_test.tscn

# 任意墓碑轮廓、共享动态网格、局部形变、碑底锚定、面积压力与回弹
& $godot --headless --path output/test_lab --script res://tools/slime_tombstone_smoke.gd

# 1280×760 局部受击阶段预览
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_slime_tombstone_test.gd
```

## Dual-Vortex Player Slime Gate 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。该实验是正式玩家接入前的独立门禁，自动验证通过后仍必须等待用户人工确认。

```powershell
# 生成 / 更新轻量场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_player_slime_fusion_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/player_slime_fusion_test.tscn

# 20 / 100 点拓扑、25 px extent、面积 / 曲率 / 邻点连续性、双色 Shader、五点冲击、暂停与稳定资源
& $godot --headless --path output/test_lab --script res://tools/player_slime_fusion_smoke.gd

# 1280×760 固定步进预览；工具会在常驻光束之外探测两份放大样本体内，空渲染直接失败
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_player_slime_fusion.gd

# 连续运行两次捕获后用 Get-FileHash 对比 SHA-256，哈希必须一致
Get-FileHash -LiteralPath 'output/test_lab/screenshots/player_slime_fusion_test.png' -Algorithm SHA256
```

人工门禁只由用户执行：检查双涡旋是否明确读成两股气、两份放大样本的主 / 副交换是否可辨、38 px 短束是否清楚指向枪口、连续移动 / 开火 / 受击时是否出现突出节点，以及 1× 玩家是否会与 `r=12` 史莱姆子弹混淆。该结论当前为“待人工验收”；未经用户明确确认，不创建 ADR #183，也不修改正式 Player、正式数据、正式场景或黄金回放。

## 2D Slime Cross 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
# 生成 / 更新结构化场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_slime_cross_2d_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/slime_cross_2d_test.tscn

# 凹形轮廓、横臂 / 竖干、动态曲率、位移连续性、回弹与压扁
& $godot --headless --path output/test_lab --script res://tools/slime_cross_2d_smoke.gd

# 1280×760 左横臂受击阶段预览
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_slime_cross_2d.gd
```

## Slime Cross Perspective Window 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
# 生成 / 更新结构化场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_slime_cross_perspective_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/slime_cross_perspective_test.tscn

# 原十字轮廓、动态圆角遮罩、SCREEN_UV Shader、位移、形变与面积保持
& $godot --headless --path output/test_lab --script res://tools/slime_cross_perspective_smoke.gd

# 1280×760 固定时间与局部受击预览
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_slime_cross_perspective.gd
```

## Slime Book Perspective Window 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
# 生成 / 更新结构化场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_slime_book_perspective_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/slime_book_perspective_test.tscn

# 单一 20 点书本轮廓、书脊特征、左右对称、动态 Shader 遮罩与软体响应
& $godot --headless --path output/test_lab --script res://tools/slime_book_perspective_smoke.gd

# 1280×760 固定步进左页受击预览；同时探测左右页内部可见内容
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_slime_book_perspective.gd
```

## Slime Apple Perspective Window 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
# 生成 / 更新结构化场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_slime_apple_perspective_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/slime_apple_perspective_test.tscn

# 单一 20 点苹果轮廓、零内部线、动态 Shader 遮罩与软体响应
& $godot --headless --path output/test_lab --script res://tools/slime_apple_perspective_smoke.gd

# 1280×760 固定步进右侧受击预览；同时探测左右果肉内部可见内容
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_slime_apple_perspective.gd
```

## SVG Curve Pear Perspective Window 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
# 生成 / 更新轻量场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_svg_curve_pear_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/svg_curve_pear_test.tscn

# 单一闭合 Curve2D、30 锚点 / 58 控制柄、内部 Shader、可调边与零软体依赖
& $godot --headless --path output/test_lab --script res://tools/svg_curve_pear_smoke.gd

# 1280×760 固定时间预览；分别探测内部、边色、锚点、入柄与出柄
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_svg_curve_pear.gd
```

## Jelly Bullet VFX Selection 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
# 生成结构化场景并显式加载
& $godot --headless --path output/test_lab --script res://scripts/create_bullet_vfx_selection_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/bullet_vfx_selection_test.tscn

# 六种候选、红白同形、主体边界、红色主面积、拖尾和无节点累积
& $godot --headless --path output/test_lab --script res://tools/bullet_vfx_selection_smoke.gd

# 1280×760 确定性总览图
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_bullet_vfx_selection.gd
```

## Tear Core Bullet Focus 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
& $godot --headless --path output/test_lab --script res://scripts/create_tear_core_bullet_focus_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/tear_core_bullet_focus_test.tscn
& $godot --headless --path output/test_lab --script res://tools/tear_core_bullet_focus_smoke.gd
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_tear_core_bullet_focus.gd
```

## Tear Core Material Switcher 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
& $godot --headless --path output/test_lab --script res://scripts/create_tear_core_material_switcher_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/tear_core_material_switcher_test.tscn
& $godot --headless --path output/test_lab --script res://tools/tear_core_material_switcher_smoke.gd
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_tear_core_material_switcher.gd
```

## Shader Gradient Orb Bullet Focus 验证

以下命令均从仓库根目录运行；`$godot` 指向 Godot 4.7.1 stable 的 console 可执行文件。

```powershell
& $godot --headless --path output/test_lab --script res://scripts/create_glow_orb_bullet_focus_scene.gd
& $godot --headless --path output/test_lab --quit-after 2 res://scenes/glow_orb_bullet_focus_test.tscn
& $godot --headless --path output/test_lab --script res://tools/glow_orb_bullet_focus_smoke.gd
& $godot --resolution 1280x760 --path output/test_lab --script res://tools/capture_glow_orb_bullet_focus.gd
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

# 调试：反转障碍绘制顺序，融合正确时应与正常截图哈希一致
& $godot --path output/test_lab --script res://tools/capture_ai_universal_tile_test.gd -- --reverse-obstacle-order

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

三张源 PNG 保持原样；`universal_tile_grid.gd` 只负责 24 个逻辑 cell、确定性错落排序与材质参数，两类视觉已拆到 `shaders/universal_tile_obstacle_frame.gdshader` 和 `shaders/universal_tile_floor.gdshader`。障碍 Shader 在 `vertex()` 中向外扩展 11px，并把 UV 重映射回中央完整 128×128 原图；外侧依次绘制约 3px 右下接触阴影、6px 深色厚基座、2.5px 同色相中间层和 1.25px 方向性受光唇边。相邻障碍会收到左 / 右 / 上 / 下邻接遮罩：外框以半开像素所有权裁止于逻辑边界，11px 端帽渐变为双方色层的对称混色，图片内侧各贡献约 2px、合计约 4px 的共享手绘接缝。接缝使用同一 canonical pair key、相位与世界坐标噪声，静态起伏不超过 0.35px、呼吸不超过 0.2px，因此翻转障碍绘制顺序也会生成完全一致的像素。非相邻外框继续保留最大 0.6px / 5.2 秒材质呼吸和被噪声切断的 9 秒局部受光。地板继续使用接缝底衬、2px 对称出血、3.5px 源图内采样、2.5px 低对比内边与 1px 柔和受光层，并以格子世界坐标形成 5.6 秒连续斜向呼吸场。视觉外框约 150×150，但节点数、节点中心、逻辑格、鼠标坐标与完整 128×128 碰撞保持不变。截图工具支持 `--capture-time=<秒>` 冻结动画，也支持 `--reverse-obstacle-order` 验证融合与绘制顺序无关；默认相位保持确定性，并关闭 collision / metadata 调试覆盖层。

## 位图 UI 素材注意事项

- `.tscn` 文件要保持轻量，不要保存生成 PNG、`ImageTexture` 或大段 `PackedByteArray`。
- 不要把 `.godot/imported` 缓存当成首次预览的唯一来源；缓存被删时外部纹理引用可能暂时失效。
- 当前位图按钮场景用 tool 脚本从 `assets/bitmap_ai` 读取 PNG 供编辑器 / 截图预览，并在保存前清掉运行时纹理，避免把图片数据写进场景。
- 如果场景文件突然变大，先检查是否出现了 `sub_resource type="Image"` 或 `PackedByteArray`。
