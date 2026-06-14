---
description: 跑词表→代码常量同步流水线（GDD 9.19 / ADR #28）。
---

# /sync-contracts

按以下流水线方向跑同步并校验：

```text
docs/词表与契约.md -> tools/sync_contracts.py -> client/data/_contracts.json + client/scripts/contracts/*.gd
```

## 步骤

1. 核对 `docs/词表与契约.md` 是否有未保存改动；有则提示用户保存后再跑。
2. 跑 `python tools/sync_contracts.py`。
3. 跑 `python tools/sync_contracts.py --check`。
4. 脚本会同时生成 `_contracts.json` 与 `client/scripts/contracts/*.gd`。
5. 若有改动，按 `AGENTS.md` 的 AI Git 提交策略判断是否自动 commit；只 stage 本次同步生成文件。

## 失败处理

- 未登记 id：引导用户先在 `docs/词表与契约.md` 登记。
- 生成文件被手改：恢复生成文件后重跑。
- `outdated generated artifact`：重跑同步即可。
