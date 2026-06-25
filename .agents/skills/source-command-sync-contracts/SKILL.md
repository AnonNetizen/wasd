---
name: "source-command-sync-contracts"
description: "跑词表→代码常量同步流水线（GDD 9.19 / ADR"
---

# source-command-sync-contracts

Use this skill when the user asks to run the migrated source command `sync-contracts`.

## Command Template

# /sync-contracts

按以下流水线方向跑同步并校验：

```
docs/词表与契约.md → tools/sync_contracts.py → client/data/_contracts.json + client/scripts/contracts/*.gd
```

## 步骤

1. 先核对 `docs/词表与契约.md` 是否有未保存改动；有 → 提示用户保存后再跑。
2. 跑：
   ```bash
   python tools/sync_contracts.py
   ```
   - 该脚本会同时生成 `_contracts.json` 与 `client/scripts/contracts/*.gd`。
3. 跑校验确认生成产物与源 md 一致：
   ```bash
   python tools/sync_contracts.py --check
   ```
4. 若有改动，按 `AGENTS.md` 的 AI Git 提交策略判断是否自动 commit；只 stage 本次同步生成文件。

## 失败处理

- 报错"未登记 id" → 引导用户先在 `docs/词表与契约.md` 登记
- 报错"生成文件被手改" → 用 `git checkout` 恢复后重跑
- 报错"outdated generated artifact" → 重跑同步即可

## 不要做

- 不要绕过 AI Git 提交策略；细微同步可不提交，大更改随本次任务提交
- 不要修改 `docs/词表与契约.md` 内容（这是用户的活）
- 不要绕过 hook 强行提交

## 相关
- 规则 15
- ADR #28
- subagent: `contract-validator`
