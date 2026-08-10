# 任务模板：加一个 Gear Mod

> **AI 修改说明**：修改本任务模板前先读 `docs/AI协作/文档维护指南.md`。本模板管官方与本地 Gear Mod 的数据制作流程；入口变化必须同步四平台 `/new-gear-mod`、`data-author`、规则、`docs/AI协作/README.md`、`docs/AI协作/上下文预算.md` 与 `AGENTS.md`。

## 必读（按顺序）

1. 当前平台编码规则入口的 Gear Mod / 通用效果程序规则
2. `docs/词表与契约.md` 的 stat、trigger、condition、action、status、enemy、pool 与 Gear Mod 组件契约
3. `client/data/README.md` 的 `gear_mods v6`、槽位-stat 支持矩阵和掉落字段
4. `client/locale/README.md` 的 name / desc、占位符与本地包双语规则
5. `client/data/gear_mods.json` 的复合组件样例
6. 制作本地包时再读 `docs/代码/mod_loader.md`

## 核心约束

- Gear Mod 使用 `components[]`，可任意组合 `modifier`、`program`、`board_rule`；每个组件必须有 Mod 内唯一的 `component_id`。
- `modifier` 只允许 `hero` / `weapon` 槽，并且 stat 必须出现在该槽的支持矩阵中。
- `program` 只能组合已登记的 trigger、condition 与 action；不得按内容 id 写业务分支。
- `board_rule` 只承载受支持的棋盘语义，首版纯占格使用 `occupy_only`。
- 官方内容 id 使用 `gear_mod_<snake_case>`；本地包 id 必须以 `mod_<package_id>_` 开头。
- 本地包不能声明解锁规则，安装即开放；不能新增核心 stat、trigger、condition、action、status、enemy、pool、RNG 等 id，也不能携带脚本、场景或 Shader。
- 玩家可见文案必须补齐 `zh_CN` / `en`；结构化效果预览必须来自组件数据，不在译文里复制可调数值。

## 步骤

1. 明确目标是官方内容还是 manifest v2 本地包，生成符合所有权规则且不冲突的 id。
2. 把概念拆成一个或多个组件，并为每项分配稳定、唯一、可读的 `component_id`。
3. 查词表：所有核心 id 必须已经登记；缺少通用原语时先走「加效果原语」任务，不要在内容任务中扩展核心契约。
4. 校验每个 `modifier` 的槽位-stat 组合；不支持时改设计或先扩展官方支持矩阵。
5. 添加 `name_key` / `desc_key` 与 `zh_CN` / `en`。官方内容写 `client/locale/strings.csv`；本地包写包内 locale。两种语言占位符必须一致。
6. 官方内容追加到 `client/data/gear_mods.json`；本地内容追加到包内 `mods[]`，且不得覆盖基础记录。
7. 需要掉落时追加官方 `gear_mod_drop_tables.csv` 或本地包允许的掉落 CSV；需要奖励池时追加官方 pool 或本地 `reward_pool_contributions[]`。
8. 可选媒体只登记包内安全相对路径：图片 PNG/WebP/JPEG，单文件不超过 4 MiB 且最大 1024×1024；非循环 SFX Ogg Vorbis/MP3/WAV，单文件不超过 8 MiB 且最长 30 秒。每包最多 128 项媒体、总文件大小不超过 64 MiB；媒体无效只触发图标/静音回退，不得改变玩法定义。
9. 运行 contracts、data/schema、Gear Mod smoke；本地包另跑 ModLoader 的 ID 所有权、坏包隔离、掉落/奖励贡献、媒体与 gameplay hash 测试。

## 自检

- [ ] `components[]` 非空，`component_id` 在本 Mod 内唯一
- [ ] `modifier` 槽位与 stat 支持矩阵匹配
- [ ] trigger / condition / action / status / enemy / pool 均来自官方契约
- [ ] 没有按内容 id 的代码分支，也没有脚本、场景或 Shader
- [ ] 官方与本地 id 所有权正确；本地包未声明解锁规则或覆盖基础记录
- [ ] `zh_CN` / `en` 齐全且占位符一致，结构化预览与数据一致
- [ ] 掉落和奖励池引用有效
- [ ] 数据、schema 与对应 smoke 通过

## 不需要做的

- 单纯新增官方条目或合法本地包时不改 Runtime、DataLoader schema、ADR 或 GDD。
- 媒体观感、音效质量、真实安装流程与 1920×1080 中英文布局由人工验收；AI 只做自动校验与整理 checklist。
