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

- [ ] 继续 F9.3 Demo 表现占位规范：核心实体轮廓和音频 cue 计划已落地；下一步继续升级 HUD 提示、玩家受伤反馈、敌人命中 / 死亡反馈的颜色与时长一致性。
- [ ] 补齐 CI / pre-commit 阶段 1 后续项：commitlint、增量 watch。（本地 `.pre-commit-config.yaml` 已落地）

## 2. 下一批任务（P1）

- [ ] 深化接入强 `SaveManager`：在 F5 run 与 F6 meta 首切片后，后续补 profile 迁移样例、更多 meta 字段回归和正式手动存档迁移 checklist。
- [ ] 扩展暂停菜单“保存并退出”和主菜单“继续游戏”流程：首片已恢复玩家、敌人、子弹、掉落、经验、RNG、GameClock、暂停菜单和升级选择面板；后续补遗物、主动道具和正式测试。
- [ ] 扩展 `client/data/growth_pools.json` 内容：在属性奖励样例后，评估遗物、主动强化、回血、刷新 / 跳过 / banish 等候选类型。
- [ ] 决策待定项 E：升级选项池内容是否包含遗物、属性、主动强化、回血、刷新 / 跳过 / banish。

## 3. 中期任务（P2）

- [ ] 实现基础玩家、输入、自动射击、子弹、敌人、刷怪和对象池，进入完整项目 M1 / M2 可玩闭环。
- [ ] 建立 L1 GUT 单测框架，优先覆盖 `RNG`、`GameClock`、`GameState`、`SaveManager`、`ModifierEngine`、`Combat`。
- [ ] 扩展黄金回放：`golden_basic_run`、`golden_pause_resume`、`golden_full_death` 和 `golden_level_up_choice` 已有运行时摘要 + 扩展稳定帧样本 / 场景语义字段版，runner 已有输入播放与 runtime event 播放首片；后续在遗物运行时 / 协同原语存在后补 `golden_relic_synergy` 等更多场景。
- [ ] 实现本地化导入与运行时语言切换，确保 `strings.csv` 中 `zh_CN` / `en` 可直接验证。
- [ ] 建立基础 UI：主菜单、HUD、暂停菜单、设置菜单、升级选择、结算、局外成长界面。
- [ ] 建立首批数据内容：扩展到 3~5 个遗物、更多武器 / 主动道具 / 消耗品和 2 种机关，并保持默认角色起始携带引用可校验。

## 4. 长期积压（P3）

- [ ] 平衡 sim：实现 `AIPlayer` 接口与 headless 批量模拟，输出胜率、存活时长、构筑强度报表。
- [ ] 局外成长扩展为多页成长树：前置节点、互斥分支、重置 / 退款规则、挑战驱动解锁。
- [ ] 内容生产流水线：加敌人 / 加遗物 / 加局外成长节点的 schema、模板、自动校验和示例数据。
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
- [x] 深局外成长设计入口：`client/data/meta_progression.json`、GDD §7.2、词表 §13、ADR #46。
- [x] Stage 1 基础 CI：`.github/workflows/docs-check.yml` 跑契约同步、数据 / locale、文档健康检查和 whitespace diff。
- [x] 10 个项目级 subagents：执行类 3 个 + 创意 / 策略类 7 个，三平台同名配置。
- [x] 数据校验 / 契约同步 / 轻量 Godot Bridge：`tools/validate_data.py`、`tools/sync_contracts.py`、`tools/godot_bridge.py`，CI 接入 sync + validate + docs health。
- [x] 正式项目 F1 工程骨架：`client/project.godot`、最小启动场景、标准目录、正式客户端运行说明和 `FormalClientBoot` 模块文档。
- [x] 正式项目 F2 第一片 autoload 骨架：`DataLoader`、`RNG`、`GameState`、`GameClock` 已注册到 `client/project.godot`，并补齐对应模块文档。
- [x] 正式项目 F2 横向 autoload 骨架：`Settings`、`Localization`、`UIManager`、`Analytics`、`Replay`、`PoolManager`、`SaveManager`、`AudioManager` 已分片落地并可 headless 启动。
- [x] 正式项目 F3 数据 / 契约闭环：`DataLoader`、`tools/validate_data.py`、schema 回归测试和 headless boot 已覆盖正式项目首批数据文件，并新增 F4 最小可玩闭环工作包。
- [x] 正式项目 F5 暂停 / 存档 / 续局：run roundtrip、备份回退、双坏档隔离、v1 -> v2 迁移、坏档提示、暂停 / 升级 UI 恢复点、升级界面暂停菜单叠层和最终手动存档 checklist 已完成。
- [x] 正式项目 F6 局外成长首切片：`MetaProgressionSystem`、死亡结算、`meta` profile roundtrip、升级购买、解锁授予、下一局永久 modifiers 和 `meta-smoke` 已完成。
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
- [x] 设计待决策 B：默认瞄准已改为鼠标相对玩家 / 视口中心方向，方向键 / 手柄右摇杆 / D-pad 作为兜底，玩家和敌人占位表现只做左右朝向。
