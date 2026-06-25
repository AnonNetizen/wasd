---
name: "source-command-update-memory"
description: "显式触发 AI 记忆更新（长期索引 + current_state.json + 会话日志的兜底入口）。"
---

# source-command-update-memory

Use this skill when the user asks to run the migrated source command `update-memory`.

## Command Template

# /update-memory

## 用途

按规则 14-B / ADR #15 / ADR #19 / ADR #44，AI 应当**主动更新** `docs/AI记忆/项目记忆.md`、`docs/AI记忆/current_state.json` 与会话日志。本命令是显式兜底——用户觉得"AI 这次没自动更新记忆"或"我想检查一下记忆是否同步"时调用。

## 步骤

1. **读现状**：
   - `docs/AI记忆/项目记忆.md`（看长期快照 / ADR 数 / 文件入口是否过期）
   - `docs/AI记忆/current_state.json`（看最新 ADR / 待决策 / 下一步 / 最近验证是否过期）
   - `docs/决策记录.md`（最新 ADR 编号）
   - `docs/游戏设计文档.md` 版本号
   - `docs/CICD规划.md` 项数
   - 最近 git commit log
2. **对照检查**：
   - 项目记忆中"项目快照"版本是否与设计文档一致？
   - "既定决策"条数是否与 ADR 表一致？
   - "工具链"是否反映了当前工具/CI 状态？
   - `current_state.json` 的 `latest_adr` 是否等于 ADR 最新编号？
   - `current_state.json` 的 `open_decisions` 是否等于 `docs/修改建议.md`？
   - `current_state.json` 的 `next_actions` / `last_verified` 是否过期？
   - 第 6 节"近期对话脉络"是否包含今日的实质性变更？
3. **修订**：
   - 同位置内容用**覆盖**而非追加（自动瘦身）
   - 第 6 节单日条目超过 1 行 → 折叠为「日期 | 摘要 | 日志链接」
   - 7+ 天前条目 → 周聚合；30+ 天 → 月聚合
4. **覆盖更新当前状态**：写 `docs/AI记忆/current_state.json`，不追加历史。
5. **写当日会话日志**：`docs/AI记忆/会话日志/<YYYY-MM-DD>.md`（输入/产出/决策/验证）。
6. **行数检查**：项目记忆主文件保持 ≤ 200 行；超 → 立即按瘦身规则压缩。
7. **运行校验**：`python tools/docs_health_check.py`。

## 节制原则（避免成本失控）

- 只记**结论 + 关键参数 + 文件指针**，不复述完整对话
- 单次更新量目标 < 1KB
- 历史细节归会话日志，短期状态归 `current_state.json`，主索引精简

## 不触发条件

- 单纯 typo 修正
- 不涉及决策的纯实现工作（在会话日志记一笔即可）
- 已在自动更新流程中刚刚改过

## 不要做

- 按 `AGENTS.md` 的 AI Git 提交策略判断；单独记忆维护通常属于细微改动不自动 commit，若属于大更改收尾则随本次任务提交
- 不要改 ADR / 规则 / 设计文档（那些是更新的"输入"）
- 不要把历史细节往主索引塞（违反瘦身规则）

## 相关
- 规则 14-B
- ADR #15 / #19 / #44
- 项目记忆第 9 节"更新约定"
