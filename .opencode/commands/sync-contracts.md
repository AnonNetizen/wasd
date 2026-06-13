---
description: 跑词表→代码常量同步流水线（GDD 9.19 / ADR #28）。
---

# /sync-contracts

按以下流水线方向跑同步并校验：

```text
docs/词表与契约.md -> tools/sync_contracts.py -> client/data/_contracts.json -> tools/gen_constants.py -> client/scripts/contracts/*.gd
```

## 步骤

1. 核对 `docs/词表与契约.md` 是否有未保存改动；有则提示用户保存后再跑。
2. 跑 `python tools/sync_contracts.py`。
3. 跑 `python tools/sync_contracts.py --check`。
4. 若工具不存在，说明 ADR #28 已立但脚本待落地，建议手工核对 md 与代码常量后跳过。
5. 若有改动，提示用户 stage / commit，不要自动 commit。

## 失败处理

- 未登记 id：引导用户先在 `docs/词表与契约.md` 登记。
- 生成文件被手改：恢复生成文件后重跑。
- 源 md 与 `_contracts.json` SHA 不一致：重跑同步即可。
