# ModLoader 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `ModLoader` 本地 mod 接口的代码契约权威；改 manifest schema、允许的 patch 类型、动态契约扩展、加载顺序、安全边界或测试义务时必须同步本文档、GDD、ADR、AI 导航、数据手册与测试策略。

## 职责

- 扫描 `user://mods/<mod_id>/mod.json`，加载玩家本地 mod manifest。
- 校验 manifest 的基础字段、数据 patch 声明、允许的动态契约扩展和相对路径安全。
- 向 `DataLoader` 提供 JSON / CSV 数据追加接口，让现有运行时代码继续通过 `DataLoader` 读取合并后的数据。
- 提供 mod 诊断信息和启用数量，供启动日志、调试 UI 和后续设置面板使用。
- 不负责创意工坊下载 / 订阅 / 上传，不执行玩家脚本，不加载任意二进制，不绕过 `DataLoader` schema 校验。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 调整本地 mod manifest | 本文档“数据与契约” |
| 接新数据 patch 类型 | `client/scripts/autoload/mod_loader.gd` 与 `DataLoader` |
| 允许新动态 id 类别 | 本文档、GDD、ADR、`docs/词表与契约.md` 相关章节 |
| 调试 mod 没生效 | 本文档“故障排查” |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/mod_loader.gd` | `ModLoader` autoload 实现 |
| `client/scripts/autoload/data_loader.gd` | 调用 `ModLoader.apply_json_mods()` / `apply_csv_mods()`，并合并允许的动态契约扩展 |
| `client/project.godot` | 注册 `ModLoader` autoload；顺序在 `DataLoader` 之前 |
| `client/tools/l1_smoke.gd` | 临时创建本地 mod，验证 manifest、动态 tag 和 JSON append |

## 场景 / 节点结构

无场景节点。`ModLoader` 通过 `client/project.godot` 的 `[autoload]` 注册为全局单例。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| autoload `_ready()` | 创建 / 扫描 `user://mods` | `reload_mods()` |
| manifest 加载 | 读取每个子目录的 `mod.json` | `_load_mod_directory()` |
| manifest 校验 | 校验 schema、id、patch、动态契约和安全路径 | `_validate_manifest()` |
| 数据读取 | `DataLoader.load_json()` / `load_csv()` 请求合并 patch | `apply_json_mods()` / `apply_csv_mods()` |
| 契约查询 | `DataLoader.contract_values()` 请求允许的动态扩展 id | `contract_extensions()` |
| 重载 | 清空并重扫本地 mod | `mods_reloaded` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `reload_mods()` | 无 | `void` | 重新扫描 `user://mods`；不下载、不联网 |
| `enabled_mod_count()` | 无 | `int` | 返回当前启用 mod 数 |
| `enabled_mods()` | 无 | `Array[Dictionary]` | 返回深拷贝，包含规范化后的 manifest 与 `root_path` |
| `diagnostics()` | 无 | `Array[String]` | 返回 manifest / patch 诊断；同时用 `[ModLoader]` warning 输出 |
| `contract_extensions(contract_key)` | `String` | `Array[String]` | 只返回 manifest 中允许动态扩展的 id |
| `apply_json_mods(resource_path, base_data)` | `String`, `Variant` | `Variant` | 当前只支持顶层数组追加，不覆盖基础数据 |
| `apply_csv_mods(resource_path, base_rows)` | `String`, `Array[Dictionary]` | `Array[Dictionary]` | 当前只支持追加 CSV 行 |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `mods_reloaded` | 无 | `reload_mods()` 完成扫描后 |

## 数据与契约

本地 mod 目录结构：

```text
user://mods/<mod_id>/
  mod.json
  data/
    relics_patch.json
    enemies_patch.csv
    strings_patch.csv
```

`mod.json` 最小结构：

```json
{
  "schema_version": 1,
  "id": "my_first_mod",
  "name": "My First Mod",
  "version": "0.1.0",
  "enabled": true,
  "load_order": 0,
  "contract_extensions": {
    "content_tags": ["mod_my_first_mod_tag"],
    "locale_prefixes": ["mod_my_first_mod_"]
  },
  "data_patches": [
    {
      "type": "json_array_append",
      "target": "relics.json",
      "path": "data/relics_patch.json",
      "array_key": "relics"
    },
    {
      "type": "csv_append",
      "target": "strings.csv",
      "path": "data/strings_patch.csv"
    }
  ]
}
```

### Manifest 字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `schema_version` | int | 当前必须为 `1` |
| `id` | string | mod 自身 id，`snake_case`，必须等于目录名 `<mod_id>`；动态 id 必须以 `mod_<id>_` 开头；重复 id 只启用第一个 |
| `name` | string | 展示名；当前只用于诊断，未来可接 UI |
| `version` | string | mod 版本；当前不做语义版本比较 |
| `enabled` | bool | 可选，默认 true |
| `load_order` | int | 可选，默认 0；数字小的先加载，同序按 id 排序 |
| `contract_extensions` | object | 允许的运行时动态 id 扩展 |
| `data_patches` | array | 数据追加声明 |

### 允许的动态契约扩展

当前只允许这些 key：

| key | 用途 | 约束 |
|-----|------|------|
| `character_ids` | 允许 mod 新增角色 id | 值必须以 `mod_<mod_id>_` 开头 |
| `game_modes` | 允许 mod 新增模式 id | 值必须以 `mod_<mod_id>_` 开头 |
| `content_tags` | 允许 mod 新增内容标签 | 值必须以 `mod_<mod_id>_` 开头 |
| `locale_prefixes` | 允许 mod 新增本地化 key 前缀 | 值必须以 `mod_<mod_id>_` 开头 |

不允许 mod 扩展 `stats`、`effects`、`events`、`damage_types`、`pool_ids`、`audio_prefixes`、`rng_streams`、`save_kinds` 等会要求代码、资源或确定性管线同步变更的核心契约。需要新原语或新底层类型时，必须先进入正式项目开发流程，而不是由玩家数据包直接打开。

### Patch 类型

| 类型 | 字段 | 说明 |
|------|------|------|
| `json_array_append` | `target` / `path` / `array_key` | 读取 mod JSON，把指定顶层数组追加到基础 JSON 的同名数组 |
| `csv_append` | `target` / `path` | 读取 mod CSV，把行追加到基础 CSV 行列表 |

`target` 可写完整资源路径或文件名，如 `res://data/relics.json` / `relics.json`。`path` 必须是 mod 目录内的安全相对路径，禁止 `..`、绝对路径和 `://`。

## 依赖

- 上游依赖：Godot `DirAccess`、`FileAccess`、`JSON`、`RegEx`。
- 下游调用方：`DataLoader`。
- 禁止依赖：不得依赖玩法业务系统、UI、网络平台 SDK 或创意工坊 API。

## 扩展点

- 新数据文件可通过新增 `json_array_append` 或 `csv_append` patch 接入，前提是 `DataLoader` 已有对应 schema。
- 未来可新增 `replace_by_id`、`disable_by_id` 或 patch 优先级，但必须先补 ADR、schema、测试和冲突诊断。
- 未来创意工坊只负责把订阅内容同步到 `user://mods/<mod_id>/`；进入游戏后的加载、校验和禁用仍走 `ModLoader`。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 允许新 patch 类型 | `mod_loader.gd`、`data_loader.gd` | 本文档、GDD、测试策略 | `l1-smoke`、headless boot |
| 允许新动态契约 key | `mod_loader.gd` | 本文档、GDD、ADR、词表说明 | `l1-smoke`、数据校验 |
| 增加 mod UI | 后续 UI 场景 / `Settings` | 本文档、AI 导航、locale README | settings-smoke / runtime-smoke |
| 接创意工坊 | 新平台适配模块 | ADR、GDD、隐私 / 发行文档 | 单独验收，不在本切片 |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 启动日志 `mods=0` | `user://mods/<mod_id>/mod.json` 是否存在、`enabled` 是否为 true |
| manifest 被跳过 | Godot warning 中的 `[ModLoader]` 诊断 |
| 新内容 id 校验失败 | 是否缺 `contract_extensions`，或 id 未以 `mod_<mod_id>_` 开头 |
| 新文案 key 校验失败 | 是否追加了 `strings.csv` patch，或 `locale_prefixes` 未声明 |
| patch 不生效 | `target` 是否匹配目标文件名，`path` 是否安全且文件可读 |

## 测试义务

- 改 `ModLoader` 或 `DataLoader` mod 接口必须跑：
  - `py -3 tools/lint_gdscript_rules.py`
  - `py -3 tools/lint_semantic_rules.py`
  - `py -3 tools/godot_bridge.py --project client l1-smoke`
  - `py -3 tools/godot_bridge.py --project client headless-boot`
- 改 manifest schema 或数据合并规则时，必须扩展 `client/tools/l1_smoke.gd` 或后续 GUT 单测。
- 若 mod patch 改变运行时内容池并影响一局行为，按 `docs/测试策略.md` 判断是否需要重跑或重录黄金回放。

## 迁移 / 兼容

- 当前 manifest schema 为 `1`。未来升级 schema 时必须保留旧 schema 的可诊断失败或迁移说明。
- mod 数据不写入 `SaveManager` 的 `meta` / `run` schema；存档和回放应记录数据指纹，避免加载缺失 mod 的旧局时静默错乱。
- 当前不接创意工坊；未来分发平台不得改变本地 manifest 契约。

## 相关文档

- `docs/游戏设计文档.md` §9.21
- `docs/决策记录.md` ADR #83
- `docs/代码/data_loader.md`
- `client/data/README.md`
- `docs/测试策略.md`
