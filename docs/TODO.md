# TODO（未来任务清单）

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是项目未来任务的人工可读清单；更新任务优先级、完成状态或新增跨系统任务时，常见联动为 `docs/AI记忆/current_state.json`、`docs/AI记忆/项目记忆.md`、当日会话日志、必要时 `docs/AI导航.md` 与 `docs/修改建议.md`。

---

## 0. 维护边界

- 本文档记录“未来要做什么”和大致顺序，适合人和 AI 接力。
- `docs/AI记忆/current_state.json` 只放当前阶段、下一步和最近验证，是机器可读当前状态。
- `docs/修改建议.md` 只放尚未决策的设计提案，不当作执行任务清单。
- 历史 MVP 已验证完成并移除；本文档只记录完整项目 / 跨阶段的总任务。
- 完成任务后把勾选项移到“已完成摘要”或删去，并在会话日志写一笔。

---

## 1. 当前优先级（P0）

- [ ] 推进 F13 手工房间制短刷图首片：按 `docs/AI协作/工作包/F13-HandcraftedRooms.md` 建立 `rooms.json` / `room_sequences.json`、房间 marker、`RoomManager`、两房间清房开门 / 切房间流程、房间校验和保存恢复 smoke。
- [ ] 补齐 CI / pre-commit 阶段 1 后续项：commitlint、增量 watch。（本地 `.pre-commit-config.yaml` 已落地）

## 2. 下一批任务（P1）

- [ ] 深化接入强 `SaveManager`：在 F11 Gear Mod meta payload 接入后，补更多 meta 字段回归和正式手动存档迁移 checklist。
- [ ] 扩展暂停菜单“保存并退出”和主菜单“继续游戏”流程：首片已恢复玩家、敌人、子弹、掉落、经验、RNG、GameClock、暂停菜单和升级选择面板；后续补遗物、主动道具和正式测试。
- [ ] 扩展 `client/data/growth_pools.json` 内容：在属性奖励样例后，评估遗物、主动强化、回血、刷新 / 跳过 / banish 等候选类型。
- [ ] 决策待定项 E：升级选项池内容是否包含遗物、属性、主动强化、回血、刷新 / 跳过 / banish。

## 3. 中期任务（P2）

- [ ] 实现基础玩家、输入、按住开火、子弹、敌人、刷怪和对象池，进入完整项目 M1 / M2 可玩闭环。
- [ ] 建立 L1 GUT 单测框架，优先覆盖 `RNG`、`GameClock`、`GameState`、`SaveManager`、`ModifierEngine`、`Combat`。
- [ ] 扩展黄金回放：`golden_basic_run`、`golden_pause_resume`、`golden_full_death` 和 `golden_level_up_choice` 已有运行时摘要 + 扩展稳定帧样本 / 场景语义字段版，runner 已有输入播放与 runtime event 播放首片；后续在遗物运行时 / 协同原语存在后补 `golden_relic_synergy` 等更多场景。
- [ ] 实现本地化导入与运行时语言切换，确保 `strings.csv` 中 `zh_CN` / `en` 可直接验证。
- [ ] 建立基础 UI：主菜单、HUD、暂停菜单、设置菜单、升级选择、结算、装备 Mod / 旧局外迁移界面。
- [ ] 建立首批数据内容：扩展到 3~5 个遗物、更多武器 / 主动道具 / 消耗品和 2 种机关，并保持默认角色起始携带引用可校验。

## 4. 长期积压（P3）

- [ ] 平衡 sim：实现 `AIPlayer` 接口与 headless 批量模拟，输出胜率、存活时长、构筑强度报表。
- [ ] 装备 Mod 扩展：更多稀有度、套装 / 标签协同、容量成长、可视化筛选、重置 / 退款规则和挑战驱动解锁。
- [ ] 内容生产流水线：加敌人 / 加遗物 / 加装备 Mod 节点的 schema、模板、自动校验和示例数据。
- [ ] 音频与美术资源规范落地：Bus 配置、SFX / BGM id、占位美术替换策略。
- [ ] 发版前完整 L5 手动回归 checklist，覆盖输入设备插拔、语言切换、存档迁移、回放重现和性能预算。

## 5. 阻塞 / 待决策

- [ ] A：松开瞄准输入是否停火。
- [ ] C：大地图引导方式：软边界 / 兴趣点。
- [ ] D：子弹手感：初期提速 / 弹道宽容。
- [ ] E：升级选项池内容。

## 6. 已完成摘要

- [x] MVP M1~M5：独立 Godot 项目、固定玩家、四方向射击、敌人、失败重开、手柄试验、集中数值配置、GM 调试工具和用户确认的 MVP 验证收口。
- [x] MVP 隔离目录在验证完成后从仓库移除，后续只保留可迁移经验与历史 ADR / 会话记录。
- [x] AI 工作框架搭建完成：开工入口、规则、AI 导航、任务模板、subagents、三平台项目级 skills、知识库、记忆、校验脚本和 AI Git 策略已形成闭环。
- [x] AI 知识库 v2：人工索引、机器索引、术语表、健康检查脚本。
- [x] AI 记忆三层结构：长期索引、机器当前状态、每日会话日志。
- [x] 完整项目数值 / 文案配置入口：`client/data/player.json`、`client/data/README.md`、`client/locale/strings.csv`、`client/locale/README.md`。
- [x] 深局外成长历史入口：GDD §7.2、ADR #46；旧 `meta_progression.json` 已按 ADR #118 删除。
- [x] Stage 1 基础 CI：`.github/workflows/docs-check.yml` 跑契约同步、数据 / locale、文档健康检查和 whitespace diff。
- [x] 10 个项目级 subagents：执行类 3 个 + 创意 / 策略类 7 个，三平台同名配置。
- [x] 数据校验 / 契约同步 / 轻量 Godot Bridge：`tools/validate_data.py`、`tools/sync_contracts.py`、`tools/godot_bridge.py`，CI 接入 sync + validate + docs health。
- [x] 正式项目 F1 工程骨架：`client/project.godot`、最小启动场景、标准目录、正式客户端运行说明和 `FormalClientBoot` 模块文档。
- [x] 正式项目 F2 第一片 autoload 骨架：`DataLoader`、`RNG`、`GameState`、`GameClock` 已注册到 `client/project.godot`，并补齐对应模块文档。
- [x] 正式项目 F2 横向 autoload 骨架：`Settings`、`Localization`、`UIManager`、`Analytics`、`Replay`、`PoolManager`、`SaveManager`、`AudioManager` 已分片落地并可 headless 启动。
- [x] 正式项目 F3 数据 / 契约闭环：`DataLoader`、`tools/validate_data.py`、schema 回归测试和 headless boot 已覆盖正式项目首批数据文件，并新增 F4 最小可玩闭环工作包。
- [x] 正式项目 F5 暂停 / 存档 / 续局：run roundtrip、备份回退、双坏档隔离、v1 -> v2 迁移、坏档提示、暂停 / 升级 UI 恢复点、升级界面暂停菜单叠层和最终手动存档 checklist 已完成。
- [x] 正式项目 F6 局外成长首切片：`MetaProgressionSystem`、死亡结算、`meta` profile roundtrip、升级购买、解锁授予、下一局永久 modifiers 和 `meta-smoke` 已完成。
- [x] F11 装备 Mod / 局外装配规划入口：ADR #115、GDD §7.2、`docs/AI协作/工作包/F11-GearModLoadout.md`、`docs/代码/gear_mod_system.md`、`client/data/README.md` planned schema 已建立；旧 F6 永久升级进入 legacy 迁移范围。
- [x] F11 旧局外成长退役：ADR #117 已删除 `MetaProgressionSystem` autoload、`MetaProgressionPanel`、标题旧入口、死亡旧结算和 `meta-smoke`；ADR #118 已删除旧 `meta_progression.json`、旧 meta 契约、旧文案和旧测试档迁移 / 补偿路径。
- [x] F11 装备 Mod 数据 / 契约首片：登记 `gear_mod_*` id / slot / rarity / resource / stack rule，新增 `gear_mods.json`、`gear_mod_drop_tables.csv`、`gear_mod_fusion_costs.csv`、测试武器伤害 Mod、`gear_mod_dust`、DataLoader / `validate_data` schema 和坏样例回归。
- [x] F11 装备 Mod 运行时首片：新增 `GearModSystem` autoload，支持 `meta.gear_mods` profile、英雄 / 武器两套 loadout、capacity / drain、唯一装备、升级消耗 `gear_mod_dust`、分解返还、`enemy_chaser` 玩家击杀 1% 掉落和开局 modifier snapshot，并新增 `gear-mod-smoke`。
- [x] F11 装备 Mod 最小 UI：标题菜单进入 `GearModPanel`，支持英雄 / 武器两套配置切换、资源 / 容量 / 详情展示、装备 / 卸下 / 升级 / 分解，并由 `gear-mod-smoke` 覆盖按钮流。
- [x] F12 短刷图默认循环规划入口：ADR #120、`docs/AI协作/工作包/F12-ShortLootRuns.md`、GDD、AI 导航、数据手册、Gameplay Runtime 模块文档和测试策略已同步；默认标准模式改为 8-12 分钟短刷图，并暂时屏蔽局内升级 3 选 1。
- [x] F13 手工房间制短刷图规划入口：ADR #127、`docs/AI协作/工作包/F13-HandcraftedRooms.md`、GDD、AI 导航、正式项目规划、测试策略、知识库索引和 AI 记忆已同步；默认下一阶段转向 Godot `.tscn` + marker 的手工房间串联，首片目标是两房间清房开门 / 进入下一房间。
- [x] 正式项目 F7 工作包准备：`docs/AI协作/工作包/F7-SettingsLocalizationUI.md` 已建立为设置 / 本地化 / UI 栈稳定化阶段入口。
- [x] 正式项目 F7 设置 / 本地化 / UI 栈首片：设置持久化、正式设置面板、运行时语言刷新、键盘主输入重绑定、输入反馈 / 恢复默认和 `UIManager` 返回 / 焦点首片已完成。
- [x] 正式项目 F8 工作包准备：`docs/AI协作/工作包/F8-ReplayTestingBalance.md` 已建立为回放 / 测试 / 平衡基线阶段入口。
- [x] 正式项目 F8 当前验收基线：L1 smoke、Replay runner、gameplay 输入录制首片、runner 输入播放首片、runtime event 播放首片、basic / pause-resume / full-death / level-up choice 四条 golden、稳定 RNG 子流 seed 和 schema v2 perf / balance baseline 已完成并通过收口审计。
- [x] 正式项目 F9 工作包准备：`docs/AI协作/工作包/F9-ContentDemoPolish.md` 已建立为内容扩展 / Demo 打磨阶段入口，F8 四条 golden replay 与 perf-probe 保留为回归护栏。
- [x] 正式项目 F9.0 内容盘点：`docs/AI协作/工作包/F9-ContentDemoPolish.md` 已列出当前可复用 runtime / 数据内容、暂不适合作为首片的角色 / 武器 / 遗物 / 主动道具 / 消耗品 / 机关边界、F9.1 推荐小内容包和 Demo 手动 checklist 首版。
- [x] 正式项目 F9.1 小内容首片：新增慢速高血量 `enemy_bulwark`、55 秒后中段刷怪波次、`growth_move_speed_small` / `growth_max_hp_small` 两个三级 `stat_modifier` 升级候选和双语文案；四条 golden replay 仅更新 data fingerprint 并通过 runtime summary rerun，`perf-probe` 仍 pass。
- [x] 正式项目 F9.2 自动化 Demo 前置探针：新增 `f9-demo-smoke` bridge 命令，headless 快进到 55 秒后确认 `enemy_bulwark` / `wave_standard_mid_bulwarks` 出现，覆盖 run snapshot / SaveManager roundtrip、三级成长候选加载和死亡结算记忆余烬链路；人工手感试玩仍待执行。
- [x] 正式项目 F9.2 手动 Demo 试玩 / 手感复核：用户试玩 F9.1 内容后反馈没有问题，因此未改 `enemy_bulwark` / 波次 / 三级成长候选数值。
- [x] 正式项目 F9.3 首个表现占位切片：所有敌人占位三角统一增加暗色轮廓和眼睛描边，提升混战中轮廓可读性；仍使用 `enemies.csv.visual_color` 填充色且不按敌人 id 分支。
- [x] 正式项目 F9.3 Demo 音频 cue 计划：`docs/代码/audio_manager.md` 已记录 `sfx_player_shoot`、玩家受伤、敌人命中 / 死亡、拾取、UI 点击 / 升级和 run / boss BGM 的占位 id 计划及接入顺序；具体 cue id 不写入前缀契约表，后续播放必须走 `AudioManager`。
- [x] 正式项目 F9.3 无音频资源视觉反馈切片：在暂无临时音频资源时，先给子弹和经验球补统一暗色轮廓，使敌人 / 子弹 / 拾取三类核心实体的占位读法一致。
- [x] 正式项目 F9.3 反馈颜色与时长一致性切片：玩家补暗色轮廓并改为 0.16 秒红色受伤闪，敌人命中为 0.16 秒暖白闪、死亡为 0.18 秒橙色放大淡出，升级 HUD 获得提示改为金色文字、暗色阴影和 1.35 秒淡出。
- [x] 正式项目 F9.3 命中火花 / 伤害数字池切片：接入 `hit_spark` 与 `damage_number` 对象池，Combat 成功造成伤害时生成短命火花和漂浮伤害数字，`runtime-smoke` 覆盖池 acquire。
- [x] 正式项目 F9.3 命中反馈人工试玩复核：用户观察后确认飘字密度 / 遮挡没有问题，因此不调火花 / 伤害数字数值，F9.3 视觉占位反馈进入收束。
- [x] 正式项目 F9.4 回归与性能守门审计：基础门禁、核心 smoke、四条 checked-in golden replay runtime rerun 与 `perf-probe` 均通过；未重录 replay，`perf-probe` 仍为 budget pass。
- [x] 正式项目 F9.5 Demo 手动 checklist 与第一轮收口：用户完成完整 demo 复核并确认没问题，F9 第一轮内容 / 表现打磨收口；下一步改为中型系统决策而不是继续追加小内容包。
- [x] F9 收口后新功能建议池：`docs/功能建议池.md` 已建立为 42 项可选新功能菜单，后续由用户手动点名推进，不作为自动路线图。
- [x] 设计待决策 B：默认瞄准已改为鼠标相对玩家 / 视口中心方向，方向键 / 手柄右摇杆 / D-pad 作为兜底，玩家和敌人占位表现只做左右朝向。
