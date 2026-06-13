---
description: 交互式创建一个新遗物条目。套用 docs/AI协作/任务模板/加遗物.md，自动检查词表、黄金样例、locale。
arguments: relic-name-or-concept
---

# /new-relic <概念>

使用方式：`/new-relic 锋利弹头` 或 `/new-relic 让命中后分裂出 2 颗追踪弹`。

## 流程

1. 读任务模板：`docs/AI协作/任务模板/加遗物.md`。
2. 理解用户描述，把效果拆成 modifiers（数值类）或 behaviors（行为类）。
3. 查 `docs/词表与契约.md` 第 1~3 节，确认 stat / effect / behavior.event id 已登记；破限内容额外查第 12 节。
4. 生成 id：`relic_<lowercase_snake_case>`，避免与已有冲突。
5. 生成 locale key：`<id>_name` / `<id>_desc`。
6. 写入 `client/data/relics.json` 与 `client/locale/strings.csv`。
7. 如可用，跑 `pre-commit run --files client/data/relics.json client/locale/strings.csv`。
8. 报告新增 id / key，并提示是否需要让 `balancer` 跑回放对照。

## 边界

- 需要新 effect 原语时停下，提示用户走“加效果原语”模板。
- 需要新 capability / 破限 strategy 时停下，提示用户先走设计评审与词表登记。
- 不为某个遗物写 id 特判；破限必须 capability / primitive 化。
- 用户没说清效果时反问 1~2 个具体问题。
- 批量遗物优先交给 `data-author` subagent。
