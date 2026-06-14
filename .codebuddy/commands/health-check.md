---
description: 跑项目健康度指标（CICD 4.L），优先执行 AI 知识库与文档健康检查，并输出健康度风险。
---

# /health-check

## 度量项（来自 CICD 4.L）

| 指标 | 计算 | 目标 |
|------|------|------|
| 裸字符串率 | 代码中未走 `tr()` 的字符串字面量 / 总字符串 | → 0% |
| 数据驱动覆盖率 | 数据条目 / (数据条目 + 硬编码分支) | → 100% |
| 词表登记率 | 数据中已登记 id / 总 id | = 100% |
| 类型化 GDScript 比例 | 已类型化函数 / 总函数 | → 100% |
| 文档同步度 | 互引文档间死链 / 总链接 | = 0 |
| AI 知识库健康度 | `_kb_index.json`、任务路由、ADR 矩阵、孤儿文档报告 | 无 error |
| 黄金回放回归通过率 | 通过黄金 / 总黄金 | = 100% |
| ADR / 规则 / 设计同步度 | 互引一致 | = 100% |

## 步骤

1. 先跑 `python tools/sync_contracts.py --check`，确认 `docs/词表与契约.md`、`client/data/_contracts.json` 与 `client/scripts/contracts/*.gd` 同步。
2. 再跑 `python tools/validate_data.py`，校验 `client/data/*.json`、`client/locale/strings.csv` 与 MVP config。
3. 再跑 `python tools/docs_health_check.py`，收集：知识库索引、Markdown 链接、`related_code`、AI 修改说明位置、ADR 矩阵、孤儿文档与同步风险报告。
4. 再跑 `tools/health_metrics.py`（若不存在 → 当前阶段继续做**手动版**）。
5. 手动版当前阶段执行：
   - `修改建议.md` 编号唯一
   - `README.md` ↔ `docs/游戏设计文档.md` 版本号一致
   - 汇总 `tools/docs_health_check.py` 输出的 error 与 report
6. 输出到 `docs/reports/<YYYY-MM-DD>-health.md`，含：
   - 时间 / git commit
   - 各指标当前值 + 目标 + 趋势（如有上次报告）
   - **未达标项的具体位置**（文件 + 行号）
7. 如发现严重不健康（红色项）→ 提示用户立即修，不要堆积

## 何时跑

- 每周一例行
- 大改后
- 发版前
- 项目交接前

## 不要做

- 不要自动修不健康项（让用户决定优先级）
- 不要污染源码（只读 + 写报告）
- 不要在指标未达 100% 时阻塞开发（除非用户明确要求）
- `tools/docs_health_check.py` 的 error 视为必须修；report 项只要求列出并解释风险

## 相关
- CICD 规划 4.L
- 测试策略 §1
- `docs/AI协作/文档健康检查.md`
