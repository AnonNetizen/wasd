# Neon Geometry Combat：参考驱动视觉迭代记录

日期：2026-07-18

本记录只覆盖 `output/test_lab` 的程序化几何实验。Round 0 为初始基线，Round 1–3 完成材质、战斗反馈与可读性收束；Round 4 在不复制具体造型的前提下，使用 Nova Drift 官方实机截图提炼出的亮度层级、轨迹组织、体量对比和事件构图原则，追加全时高强霓虹验证。

| 阶段 | 截图 | 本轮目标 |
|---|---|---|
| Round 0 | [`neon_geometry_combat_test_round0.png`](screenshots/neon_geometry_combat_test_round0.png) | 固定基线：薄描边、单色面、事件反馈弱 |
| Round 1 | [`neon_geometry_combat_test_round1.png`](screenshots/neon_geometry_combat_test_round1.png) | 暗壳、分面、方向性高光、热芯、局部环境染色 |
| Round 2 | [`neon_geometry_combat_test_round2.png`](screenshots/neon_geometry_combat_test_round2.png) | hit-stop、枪口爆闪、冲击星芒、折射涟漪、三阶段预警 |
| Round 3 | [`neon_geometry_combat_test_round3.png`](screenshots/neon_geometry_combat_test_round3.png) | 放大玩家、移动残影、准星去单位化、命中遮挡收敛、构图重排 |
| Round 4 | [`CHARGE`](screenshots/neon_geometry_combat_test_round4_charge.png) / [`CONTACT`](screenshots/neon_geometry_combat_test_round4_contact.png) / [`AFTERMATH`](screenshots/neon_geometry_combat_test_round4_aftermath.png) | 全时能量体积、固定长尾、体量差、空间锚点和三阶段事件构图 |

## 六维批评与结果

| 维度 | Round 0 基线 | Round 1 批评 | Round 2 批评 | Round 3 结果 |
|---|---|---|---|---|
| 轮廓识别 | 阵营色成立，但断环和三轴主要靠细线，玩家内部结构压过主轮廓 | 断环壳片有效，玩家仍偏暗且像切面宝石 | 强预警明确了断环朝向；三轴在命中环下局部被遮挡 | 玩家放大并提高主面亮度；三轴命中特效缩小；准星改为开放式刻度，不再使用闭合小单位语法 |
| 材质层次 | 所有对象共用亮填充和等宽白边，呈亚克力塑料感 | 暗壳、实体主面和热芯生效，但内部高亮仍偏多 | 环境染色和事件光加入后已有能量体积，右侧事件一度过密 | 保留暗壳—中亮主面—少量热边—白热芯四级亮度，玩家金色主体稳定高于背景 |
| 攻击预警 | 左侧扇形太暗，方向和阶段都不明确 | 未充分改善，列为 Round 2 的首要问题 | 分层填充、粗危险边、收缩刻度、扫线和延伸虚线使真实攻击方向清楚 | 填充降低约 17%，危险外沿和箭弹核心仍保持最高可读性；捕获状态固定在后段预警 |
| 弹体区分 | 三类弹体已有颜色差异，但都依赖尖角/重复描边 | 玩家弹改为琥珀实体脊，敌楔使用暗红实体面 | 三类弹体可在交火帧中同时辨认，红环残影仍等权 | 红环残影逐级缩小、降亮；敌楔拖尾减重；玩家弹继续保持实心长针和紫色渐缩尾 |
| 画面构图 | 玩家在下、双敌在上，但中央空、右侧偏重 | 材质改善未改变事件布局 | 左预警与右命中形成对角平衡，但右侧局部叠加过密 | 玩家上移并加入对角移动轨迹，左预警、中央三叉弹线、右命中形成清晰的三段阅读路径 |
| 动态反馈 | 单帧几乎只有飞行弹体，看不到攻击阶段 | 材质变厚，但仍不能证明攻击节奏 | 单帧已能看到预警、飞行、命中和衰减；新增 hit-stop、后坐、镜头微震与六类固定池 VFX | 延长后坐可见窗口，命中改为方向性星芒/碎片，三种单位具有不同崩解模式；hit-stop 由 smoke 的状态断言验证 |

## Round 4：Nova Drift 参考映射与批评

参考只取自 [Nova Drift 官方 press kit](https://novadrift.io/presskit.html) 的实机截图，不保存或复用其资产：

- [`1.png`](https://novadrift.io/img/1.png)：提炼“白热核心 → 饱和色层 → 宽透明外晕”和悬殊体量。
- [`2.png`](https://novadrift.io/img/2.png)：提炼轨迹汇向单一碰撞焦点与宽幅运动带。
- [`5.png`](https://novadrift.io/img/5.png)：提炼等距弹流形成全屏攻击丝带，而非孤立弹丸。
- [`6.png`](https://novadrift.io/img/6.png)：提炼扇形攻击覆盖角和由粗到细的长尾。
- [`10.png`](https://novadrift.io/img/10.png)：提炼分段实体、暗缝和节奏化空心弹列。

Round 3 的优势是轮廓、阵营和危险预警稳定，差距是辉光仍贴着轮廓、弹尾偏短、背景缺乏空间质量块，确定性截图也没有让枪线与命中点真正汇聚。Round 4 的实现与结果如下：

| 维度 | Round 4 改动 | 验收结果 |
|---|---|---|
| 轮廓识别 | 玩家、猎体、炮体视觉尺寸分别约提高 15%、20%、28%；三轴炮体成为最大实体质量块 | 25% 缩放仍能一眼分辨三个单位，实体体量没有改变命中半径 |
| 材质层次 | 提高实体色面与暗缝对比，扩大常态阵营色外晕，仅 CONTACT 命中使用大面积白热峰值 | 50% 缩放下品红板块、青色三轴和琥珀玩家仍有独立材质读法，未退回等宽白边塑料感 |
| 攻击预警 | 预警移到独立最上层，加入近黑隔离底、实体危险边、辉光与终点刻度 | CONTACT / AFTERMATH 中长尾和命中效果都未吞没左侧扇形预警 |
| 弹体区分 | 弹体使用固定 10 点历史：金紫实体枪线、红色燕尾短迹、红色空心弧列 | 25% 缩放仍能区分玩家连续枪线、扇面楔弹和炮体断环弹；尾迹亮度低于弹头 |
| 画面构图 | 玩家位于下方偏中、双敌形成不等边三角；三组三向枪线连续汇向右上炮体；右下画外环状星体建立尺度 | CONTACT 只有炮体命中是白热峰值，左侧预警与右侧空间锚点形成稳定平衡 |
| 动态反馈 | 捕获固定 CHARGE / CONTACT / AFTERMATH 三状态，分别表现能量汇聚、白热接触与扩散衰减 | 三张截图的攻击阶段可直接比较；hit-stop、重生和池容量仍由 smoke 验证 |

## 每轮回归

- Round 1：主脚本 `--check-only` 通过；专用 combat smoke 全通过；固定 48/48 弹池、64 VFX 槽与零子节点保持不变。
- Round 2：主脚本 `--check-only` 通过；专用 combat smoke 全通过；新增 VFX 仍复用 64 个字典槽。
- Round 3：actor、主脚本与 smoke 脚本 `--check-only` 通过；专用 smoke 新增 hit-stop、五类以上并发 VFX 和 reset 清理断言并全通过。
- Round 4：弹体脚本、主脚本、捕获工具与 smoke `--check-only` 通过；专用 smoke 覆盖三阶段接口、14 点玩家轨迹、10 点弹体轨迹、reset 清空、48/48/64 容量与零子节点。连续两次捕获的三阶段 PNG 和 CONTACT canonical SHA-256 完全一致。

静态对比图用于审查轮廓、材质、预警、弹体和构图。hit-stop 的时间暂停不能由单帧直接证明，因此保留为自动状态断言和实际运行手感检查项，不用截图替代时间行为证据。

Round 3 独立视觉审查未发现 P0/P1 问题。Round 4 在 100%、50% 与 25% 尺度复核轮廓、材质、预警、弹体、构图和动态阶段后，同样未发现高优先级视觉问题。可接受的剩余风险是：单帧无法评价 hit-stop 的主观时长，全时高强霓虹在更高弹幕压力下仍可能出现疲劳；两项不影响本实验当前的固定池、读图和确定性截图验收。
