---
description: 交互式创建一个新遗物条目。套用 docs/AI协作/任务模板/加遗物.md，自动检查词表、黄金样例、locale。
arguments: relic-name-or-concept
---

# /new-relic <概念>

使用方式：`/new-relic 锋利弹头` 或 `/new-relic 让命中后分裂出 2 颗追踪弹`。

## 流程（按"加遗物.md"任务模板）

1. **读任务模板**：`docs/AI协作/任务模板/加遗物.md`
2. **理解用户描述**，把效果拆成：
   - **数值类 → `modifiers`**：`{ stat, type(add/mult), value }`
   - **行为类 → `behaviors`**：`{ event, effect, params }`
3. **查词表**（`docs/词表与契约.md` 第 1~3 节；破限内容额外查第 12 节）：
    - 涉及的 stat / effect / behavior.event id 是否**已登记**？
    - 未登记 → 停下来，提示用户走"加效果原语"任务模板，由主对话实现
    - 若突破默认规则（栏位、瞄准、开火、移动、摄像机等），是否声明了 `tag_limit_break` 与 capability？
4. **生成 id**：`relic_<lowercase_snake_case>`，避免与已有冲突
5. **生成 locale key**：`<id>_name` / `<id>_desc`（占位符 `{value}` 用于动态数值）
6. **写入**：
   - `client/data/relics.json` 末尾追加（参照黄金样例结构）
   - `client/locale/strings.csv` 加两行（zh_CN + en；缺任一语言时 AI 自动补首版译文）
7. **跑 hook 校验**（如果可用）：`pre-commit run --files client/data/relics.json client/locale/strings.csv`
8. **报告**：列出新增的 id / key、并提示是否需要让 `balancer` 跑回放对照（一般遗物加新条目不影响黄金回放）

## 边界

- 如果遇到"需要新 effect 原语"：**停**，引导用户用 `加效果原语` 模板（涉及代码 + ADR + 词表登记）
- 如果遇到"需要新 capability / 破限 strategy"：**停**，引导用户先走设计评审与词表登记
- 如果用户没说清效果 → 反问 1~2 个具体问题（"伤害是 +30% 还是 +1.5？"）
- 不要一次加多个遗物（用户要批量时用 `data-author` subagent）

## 不要做

- 不写 `.gd` 代码
- 不改规则 / ADR
- 按 `AGENTS.md` 的 AI Git 提交策略判断是否自动 commit；只提交本次遗物相关数据 / locale / 词表 / 生成文件
- 不擅自加未登记 id
- 不为某个遗物写 id 特判；破限必须 capability / primitive 化

## 相关
- 任务模板：`docs/AI协作/任务模板/加遗物.md`
- subagent: `data-author`（批量场景）/ `contract-validator`（id 合规性）
