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

1. 先跑 `python tools/docs_health_check.py`，收集知识库索引、Markdown 链接、`related_code`、AI 修改说明位置、ADR 矩阵、孤儿文档与同步风险报告。
2. 再优先跑 `tools/health_metrics.py`；若不存在，当前阶段做手动版。
3. 手动版检查词表/数据交叉、`修改建议.md` 编号唯一、README/GDD 版本一致，并汇总 `tools/docs_health_check.py` 输出。
4. 输出到 `docs/reports/<YYYY-MM-DD>-health.md`，含未达标项的具体位置。
5. 发现红色项时提示用户立即修，不要自动修；`docs_health_check` report 项只列风险，不当作失败。
