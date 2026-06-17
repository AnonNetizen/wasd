# TODO（未来任务清单）

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md`。
> 本文档是项目未来任务的人工可读清单；更新任务优先级、完成状态或新增跨系统任务时，常见联动为 `docs/AI记忆/current_state.json`、`docs/AI记忆/项目记忆.md`、当日会话日志、必要时 `docs/AI导航.md` 与 `docs/修改建议.md`。

---

## 0. 维护边界

- 本文档记录“未来要做什么”和大致顺序，适合人和 AI 接力。
- `docs/AI记忆/current_state.json` 只放当前阶段、下一步和最近验证，是机器可读当前状态。
- `docs/修改建议.md` 只放尚未决策的设计提案，不当作执行任务清单。
- MVP 专属里程碑仍以 `MinimumViableProduct/docs/开发计划.md` 为准；本文档只记录跨完整项目 / 跨阶段的总任务。
- 完成任务后把勾选项移到“已完成摘要”或删去，并在会话日志写一笔。

---

## 1. 当前优先级（P0）

- [ ] 补齐 CI / pre-commit 阶段 1 后续项：commitlint、本地 pre-commit hook、增量 watch。
- [ ] 继续正式项目 F3 数据 / 契约闭环：在已补 DataLoader schema 回归测试、weapons 和 relics 边界后，继续扩展 enemies 等后续内容数据 schema。

## 2. 下一批任务（P1）

- [ ] 完成正式项目 F3 数据 / 契约闭环：把已落地 schema 继续扩展到敌人等后续内容数据。
- [ ] 深化接入强 `SaveManager`：`meta` 局外成长业务、`run` 暂停退出续局快照、暂停菜单保存退出、主菜单继续游戏和存档迁移测试。
- [ ] 实现暂停菜单“保存并退出”和主菜单“继续游戏”流程，加载后恢复玩家、敌人、子弹、掉落、经验、遗物、RNG、GameClock 和 UI 恢复点。
- [ ] 实现 `MetaProgressionSystem`：结算奖励、账号等级、永久升级购买、解锁授予、`ModifierEngine` 注入。
- [ ] 扩展 `client/data/growth_pools.json` 内容：在属性奖励样例后，评估遗物、主动强化、回血、刷新 / 跳过 / banish 等候选类型。
- [ ] 决策待定项 E：升级选项池内容是否包含遗物、属性、主动强化、回血、刷新 / 跳过 / banish。

## 3. 中期任务（P2）

- [ ] 实现基础玩家、输入、自动射击、子弹、敌人、刷怪和对象池，进入完整项目 M1 / M2 可玩闭环。
- [ ] 建立 L1 GUT 单测框架，优先覆盖 `RNG`、`GameClock`、`GameState`、`SaveManager`、`ModifierEngine`、`Combat`。
- [ ] 录制第一批黄金回放：`golden_basic_run`、`golden_pause_resume`、`golden_full_death`、`golden_relic_synergy`。
- [ ] 实现本地化导入与运行时语言切换，确保 `strings.csv` 中 `zh_CN` / `en` 可直接验证。
- [ ] 建立基础 UI：主菜单、HUD、暂停菜单、设置菜单、升级选择、结算、局外成长界面。
- [ ] 建立首批数据内容：基础武器、3~5 个遗物、1 个主动道具、1 个消耗品、2 种机关，并在默认角色数据上扩展起始内容字段。

## 4. 长期积压（P3）

- [ ] 平衡 sim：实现 `AIPlayer` 接口与 headless 批量模拟，输出胜率、存活时长、构筑强度报表。
- [ ] 局外成长扩展为多页成长树：前置节点、互斥分支、重置 / 退款规则、挑战驱动解锁。
- [ ] 内容生产流水线：加敌人 / 加遗物 / 加局外成长节点的 schema、模板、自动校验和示例数据。
- [ ] 音频与美术资源规范落地：Bus 配置、SFX / BGM id、占位美术替换策略。
- [ ] 发版前完整 L5 手动回归 checklist，覆盖输入设备插拔、语言切换、存档迁移、回放重现和性能预算。

## 5. 阻塞 / 待决策

- [ ] A：松开瞄准输入是否停火。
- [ ] B：是否提供自动瞄准 / 鼠标瞄准。
- [ ] C：大地图引导方式：软边界 / 兴趣点。
- [ ] D：子弹手感：初期提速 / 弹道宽容。
- [ ] E：升级选项池内容。

## 6. 已完成摘要

- [x] MVP M1~M5：独立 Godot 项目、固定玩家、四方向射击、敌人、失败重开、手柄试验、集中数值配置、GM 调试工具和用户确认的 MVP 验证收口。
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
