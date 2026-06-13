# Pull Request

## 变更概述
<!-- 简述这次 PR 做了什么、为什么 -->

## 变更类型
- [ ] feat（新功能）
- [ ] fix（修 bug）
- [ ] docs（文档）
- [ ] data（数值 / 配置）
- [ ] locale（本地化文本）
- [ ] refactor（重构）
- [ ] perf（性能）
- [ ] chore / ci / test / style / revert

## 关联 Issue / 决策
<!-- 关联 issue 编号；若涉及既定决策，引用 docs/决策记录.md 中的条目 -->

---

## 自检清单（按编码规则）

### 数据驱动 / 反硬编码
- [ ] 没有硬编码可调数值（都在 `client/data/` 即 `res://data/`）
- [ ] 没有硬编码玩家可见文本（都用 `tr("key")`）
- [ ] 没有硬编码按键（走 InputMap action + `Settings`）
- [ ] 约定字符串都来自 `docs/词表与契约.md` 且以**常量/枚举**引用（无裸字符串）

### 系统设计
- [ ] 新遗物 / 道具是**加数据**而非加逻辑分支
- [ ] 玩家偏好都走 `Settings` 单例并能即时生效
- [ ] 关键节点通过 `Analytics` 统一接口埋点（非散落硬编码）
- [ ] 暂停用 `get_tree().paused`，菜单节点 `process_mode=ALWAYS`

### 性能 / 工程
- [ ] 高频实体用了对象池（无频繁 `instantiate` / `queue_free`）
- [ ] 相机保证玩家居中（无 `limit` / `drag margin`）
- [ ] 新代码使用**类型化 GDScript**
- [ ] 复用了 `client/templates/`（即 `res://templates/`）模板

### 数据校验
- [ ] 新增数据照「黄金样例」结构填写
- [ ] 能通过 `DataLoader` 校验

### 文档同步（元规则 19/20/24）
- [ ] 已按 `docs/代码文档规范.md` 判断代码对应文档；必要时更新 `docs/代码/` 模块文档，或在备注说明无需更新
- [ ] 已更新 `docs/AI导航.md` 相关入口
- [ ] 已更新 `docs/决策记录.md`（若涉及决策变更）
- [ ] 已更新 `docs/游戏设计文档.md` / `docs/词表与契约.md`（若涉及设计/契约变更）
- [ ] 已更新当前平台编码规则入口（若涉及新规则；`.codebuddy/`、`.codex/`、`.opencode/` 核心语义保持一致）
- [ ] 已更新 `docs/AI记忆/项目记忆.md`（若涉及重要对话/决策）

---

## 截图 / 录屏（可选）
<!-- UI / 玩法变更建议附图 -->

## 备注
<!-- 评审者需知道的特殊事项 -->
