---
description: 跑项目健康度指标（CICD 4.L），优先执行 AI 知识库与文档健康检查。
---

# /health-check

## 度量项

| 指标 | 目标 |
|------|------|
| 裸字符串率 | 0% |
| 数据驱动覆盖率 | 100% |
| 词表登记率 | 100% |
| 类型化 GDScript 比例 | 100% |
| 文档同步度 | 0 死链 |
| AI 知识库健康度 | 无 error |
| 黄金回放回归通过率 | 100% |
| ADR / 规则 / 设计同步度 | 100% |

## 步骤

1. 先跑 `python tools/sync_contracts.py --check`，确认词表、`_contracts.json` 与 `client/scripts/contracts/*.gd` 同步。
2. 再跑 `python tools/validate_data.py`，校验 `client/data/*.json` / `client/data/*.csv` 与 `client/locale/strings.csv`。
3. 再跑 `python tools/test_data_loader_schema.py`，确认 DataLoader-facing schema 坏样例会 fail-fast。
4. 再跑 `python tools/lint_gdscript_rules.py`，检查第一档 GDScript 项目规则。
5. 再跑 `python tools/lint_project_rules.py`，检查第二档项目规则：数据字段手册覆盖、locale 双语和 release debug/dev_tools 边界。
6. 再跑 `python tools/test_project_rules_lint.py`，确认项目规则 lint 坏样例会 fail-fast。
7. 再跑 `python tools/docs_health_check.py`，收集知识库索引、Markdown 链接、`related_code`、AI 修改说明位置、ADR 矩阵、孤儿文档与同步风险报告。
8. 再优先跑 `tools/health_metrics.py`；若不存在，当前阶段做手动版。
9. 手动版检查 `修改建议.md` 编号唯一、README/GDD 版本一致，并汇总各脚本输出。
10. 输出到 `docs/reports/<YYYY-MM-DD>-health.md`，含未达标项的具体位置。
11. 发现红色项时提示用户立即修，不要自动修；`docs_health_check` report 项只列风险，不当作失败。
