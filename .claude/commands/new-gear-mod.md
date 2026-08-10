---
description: 交互式创建一个新的 Gear Mod 条目或本地 Gear Mod 包条目。套用 docs/AI协作/任务模板/加GearMod.md，检查组件、效果契约、槽位-stat、locale 与掉落/奖励池贡献。
argument-hint: gear-mod-name-or-concept
allowed-tools: Bash, Read, Edit, Grep, Glob
---

# /new-gear-mod <概念>

用户参数：$ARGUMENTS

使用方式：`/new-gear-mod 后坐力阻尼器` 或 `/new-gear-mod 受击时获得超量护盾并周期生成敌人`。

## 流程

1. 读 `docs/AI协作/任务模板/加GearMod.md`。
2. 确认目标是官方内容还是本地包；官方 id 使用 `gear_mod_<snake_case>`，本地包 id 必须使用 `mod_<package_id>_<snake_case>`。
3. 把效果拆成任意组合的 `components[]`：`modifier`、`program`、`board_rule`；每项都有 Mod 内唯一 `component_id`。
4. 查 `docs/词表与契约.md`，只使用已登记的 stat、trigger、condition、action、status、enemy、pool 等核心 id。需要新原语时停止并转主对话走“加效果原语”。
5. 对 `modifier` 严格检查 `hero` / `weapon` 槽与 stat 的支持矩阵；禁止生成“校验通过但运行时无效”的组合。
6. 补齐 `zh_CN` / `en` 的名称与结构化效果描述；官方内容写 `client/locale/strings.csv`，本地包写包内 locale。
7. 按目标写入 `client/data/gear_mods.json`，或写入 manifest v2 本地包的 `mods[]`；本地包不得声明解锁规则、脚本、场景、Shader 或自定义核心 id。
8. 需要时追加官方掉落 CSV / 奖励池，或本地包允许的掉落与 `reward_pool_contributions[]`；本地包不得覆盖基础记录。
9. 跑 contracts、data/schema 与 Gear Mod smoke；本地包另跑 ModLoader 包隔离、媒体与 gameplay hash 校验。

## 边界

- 不为内容 id 写业务分支；只组合内置效果原语。
- 本地图片/音效只登记安全相对路径；图片允许 PNG/WebP/JPEG，非循环 SFX 允许 Ogg Vorbis/MP3/WAV，超限或损坏媒体只回退，不改变玩法数据。
- 批量 Gear Mod 优先交给 `data-author`；新原语、DataLoader schema 或 Runtime 代码交主对话。

## 相关

- 任务模板：`docs/AI协作/任务模板/加GearMod.md`
- subagent：`data-author`（数据）/ `contract-validator`（契约）/ `balancer`（回放与平衡）
