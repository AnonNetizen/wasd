---
description: 跑词表→代码常量同步流水线（GDD 9.19 / ADR #28），保证 docs/词表与契约.md 改动后 client/data/_contracts.json 与 client/scripts/contracts/*.gd 都更新。
---

# /sync-contracts

按以下流水线方向跑同步并校验：

```
docs/词表与契约.md → tools/sync_contracts.py → client/data/_contracts.json → tools/gen_constants.py → client/scripts/contracts/*.gd
```

## 步骤

1. 先核对 `docs/词表与契约.md` 是否有未保存改动；有 → 提示用户保存后再跑。
2. 跑：
   ```bash
   python tools/sync_contracts.py
   ```
   - 若 `tools/sync_contracts.py` 不存在（当前阶段），向用户说明 ADR #28 已立但脚本待落地，建议手工核对 md 与代码常量后跳过。
3. 跑校验确认生成产物与源 md 一致：
   ```bash
   python tools/sync_contracts.py --check
   ```
4. 若有改动 → `git add` 生成文件并提示用户 commit（不要自动 commit）。

## 失败处理

- 报错"未登记 id" → 引导用户先在 `docs/词表与契约.md` 登记
- 报错"生成文件被手改" → 用 `git checkout` 恢复后重跑
- 报错"源 md 与 _contracts.json SHA 不一致" → 重跑同步即可

## 不要做

- 不要自动 commit
- 不要修改 `docs/词表与契约.md` 内容（这是用户的活）
- 不要绕过 hook 强行提交

## 相关
- 规则 15
- ADR #28
- subagent: `contract-validator`
