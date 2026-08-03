# 数据配表编辑器

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`；改数据集边界、保存事务、契约登记或测试义务时同步 ADR、数据/locale 手册、AI 导航、测试策略、知识索引和 AI 记忆。
>
> 对应 ADR #180。本文档描述 Godot 4.7.1 编辑器内“数据配表”主界面、数据集目录、搜索、草稿、事务保存和契约登记边界。

## 职责与边界

“数据配表”是 `client/` 的 editor-only 配置工作台，统一编辑普通 `client/data/` JSON、全部数据 CSV 和 `client/locale/strings.csv`。它不进入运行时、不改变 `DataLoader` 的读取协议，release preset 会排除整个插件和 `client/scripts/editor/`。

以下来源由专用工具或生成流程负责，既不能在数据配表中编辑，也不能进入全局搜索：

- `client/data/_contracts.json`：由 `tools/sync_contracts.py` 生成。
- `client/data/modules/*.json`、`module_templates.json`、`module_tile_catalog.json`：由“Module JSON”负责。
- `client/data/visual_effects.json`、`presentation_profiles.json`：由“VFX 效果库”负责。

`module_worlds.json` 是普通世界配置，属于数据配表。左侧快捷按钮只切换到两个专用主界面，不读取其数据。

## 代码地图

| 路径 | 职责 |
|------|------|
| `client/addons/data_table_editor/data_table_editor_plugin.gd` | 注册“数据配表”中央主界面 |
| `client/addons/data_table_editor/data_table_editor_main_screen.gd` | 左侧导航、表格、递归属性、文案联动、搜索和保存 UI |
| `client/addons/data_table_editor/data_table_property_editor.gd` | Dictionary / Array / 标量递归编辑器 |
| `client/addons/data_table_editor/data_table_catalog.json` | 声明数据集、格式、分区、主键、locale 关联、契约键和排除来源 |
| `client/scripts/editor/data_table_catalog.gd` | 目录加载与全量来源覆盖检查 |
| `client/scripts/editor/data_table_document.gd` | JSON/CSV 文档、CRUD、TSV、Undo/Redo、locale、草稿和稳定序列化 |
| `client/scripts/editor/data_search_index.gd` | 1–8 层递归内存索引、AND 查询、排序和筛选 |
| `client/scripts/editor/data_table_transaction.gd` | hash 检查、备份、临时写入、回滚与崩溃恢复 |
| `client/scripts/editor/data_table_contract_bridge.gd` | 调用受控的契约 register/unregister CLI |
| `client/scripts/editor/project_data_validation_bridge.gd` | 数据配表与 Module JSON 共用的项目数据校验入口 |
| `client/addons/data_table_editor/data_table_editor_self_test.gd` | 模型、搜索、编辑、草稿与事务 smoke |

## 数据集目录

`data_table_catalog.json` 是编辑器的声明式路由表。每项至少包含稳定 `id`、中文 `label`、`group`、`res://` 路径与 `json` / `csv` 格式；JSON 可声明多个 `sections[].path`，CSV 使用根级 `primary_keys`。可选字段：

- `primary_keys`：单主键或复合键，用于记录定位和搜索结果。
- `dataset_defaults.default_template_mode / field_type_mode`：目录级默认采用首条记录生成空模板并从当前值推断编辑类型；数据集或分区可用 `default_template` 覆盖空表模板。
- `field_rules`：按 `field.path` / `array[].path` 声明类型、`min` / `max` 或枚举覆盖；编辑与 TSV 粘贴在写入文档前执行。
- `references`：声明跨表、locale 或 contract 目标；`contract:*` 字段直接使用生成契约中的既有值下拉，并在文档模型层拒绝未登记的代码原语，最终权威仍是通用引用扫描与 `DataLoader` 全项目校验。
- `contract_key`：只允许绑定受控内容契约。
- `locale_fields`：记录内的 `name_key` / `desc_key` 等本地化引用。
- `preview: "skill"`：复用 `SkillDescriptionFormatter` 显示默认能力倍率下的中英文实时描述。

目录加载时递归扫描 `client/data/` 的 JSON/CSV，并额外检查 `strings.csv`。任何新来源如果既未登记为可编辑数据集，也未登记为专用/生成来源，`data-table-editor-smoke` 会失败。此门禁防止新表静默漏出一站式工具。

## 编辑流程

左侧数据集、中央工作区和右侧递归属性区之间使用两条可拖动分隔线，grabber 常驻显示且最小抓取厚度为 16 px，并分别保留 150 / 420 / 260 px 的最小可用宽度。中央区域显示顶层标量列，可排序、筛选和直接编辑；列标题分隔线支持拖动调宽，最小宽度为 88 px，同一编辑器会话内按数据集、分区和列结构保留布局；`Ctrl+V` 从当前单元格起按 TSV 行列批量写入现有记录。CSV 加载会拒绝未加引号而产生额外列的非法记录，保存时原样复用所有未修改记录，只对真实变更的记录做规范编码，因此单纯选择或打开只读 Diff 不会制造格式噪声或截断逗号后的内容。右侧属性树的“字段 / 类型 / 值”列共用同一套列头拖动逻辑，最小列宽为 64 px；属性树继续递归处理嵌套对象、数组和不同形态的数组元素，空数组新增项使用对象兜底，非空数组根据首项生成默认结构。

新增、复制、删除与字段编辑进入文档级 100 步 Undo/Redo。已有主键只读，重命名必须“复制为新 ID → 修正引用 → 删除旧记录”；复合键创建时按字段顺序用 `/` 分隔。删除前由 `DataSearchIndex.references_to()` 扫描跨表精确引用；仍被引用时拒绝删除。经全局与当前草稿确认无人引用的专属 locale 行和对应内容契约随删除进入同一保存事务。

`locale_fields` 在右侧显示中文与英文输入框，写入 `strings.csv` 的同一文档会话。技能描述用真实配置、占位符和能力缩放 resolver 预览，不维护第二套格式化公式。

## 全局搜索

`DataSearchIndex` 只加载目录拥有的数据。它按记录递归展开最多 8 层 Dictionary/Array，为每个叶值记录数据集、格式、源文件、分区、记录 ID、字段路径、字段名、类型和值摘要；locale key 对应的 `zh_CN` / `en` 文案会并入记录上下文。

查询为大小写不敏感字面匹配，空格分隔的词按 AND 处理。排序优先级为精确记录 ID/值、ID/值前缀、精确字段名、普通包含；随后按数据集、分区、记录和字段路径稳定排序。可按数据集、JSON/CSV 和 string/number/boolean/null 筛选。首版没有正则和全局替换。双击或回车会打开数据集、分区、记录并选中递归字段。

插件启动、项目文件系统刷新、外部变化和成功保存后全量重建索引；当前数据规模不需要持久缓存。

## 草稿、冲突和保存事务

每次修改自动写入 `user://data_table_editor/drafts/<dataset_id>.json`，内容包含源文件 hash、locale hash、数据、列头、locale 修改和待处理契约。项目根目录的 `draft/` / `DRAFT/` 永远不参与。

重新打开数据集时：

- hash 匹配：可恢复或放弃草稿。
- hash 不匹配：必须明确选择是否恢复冲突草稿；保存时再次明确选择“以草稿替换”。
- 默认保存：磁盘 hash 变化立即失败，不静默覆盖。

保存由 `DataTableTransaction` 执行：恢复未完成 journal、检查 hash、把所有目标备份到 `user://`、写相邻临时文件、提升为正式文件、运行契约钩子，再通过独立 Godot headless 进程调用 `DataLoader.validate_project_data()`。任一步失败都会恢复本事务全部文件，保留草稿并返回诊断。`ProjectDataValidationBridge` 同时供模块 baker 使用，避免两套验证行为漂移。

## 受控契约登记

`tools/sync_contracts.py` 提供：

```text
py -3 tools/sync_contracts.py --register <contract_key> <id> --meaning <含义> [--dry-run]
py -3 tools/sync_contracts.py --unregister <contract_key> <id> [--dry-run]
```

只允许 `character_ids`、`game_modes`、`skill_ids`、`hero_passive_ids`、`gear_mod_ids` 和 `world_event_ids`，并校验各自前缀。effect、status、targeting、slot 等代码原语不能从配表工具创建，只能选择词表既有值。CLI 以一次可回滚的原子写入同时更新 `docs/词表与契约.md`、`_contracts.json` 和生成常量；数据配表保存又把这些文件纳入外层事务快照。

## 测试与排障

最小回归命令：

```text
py -3 tools/godot_bridge.py --project client data-table-editor-smoke
py -3 tools/test_sync_contracts.py
py -3 tools/sync_contracts.py --check
py -3 tools/godot_bridge.py --project client headless-boot
```

`data-table-editor-smoke` 覆盖目录完整性、深层/多态搜索、排除源、CRUD、TSV、Undo/Redo、locale、技能预览、草稿、外部冲突和回滚。UI 的实际可读性、Excel 粘贴手感、双语联改、搜索定位与冲突确认属于 L5，必须由人工在 Godot 编辑器执行。

常见故障：

- “unregistered project data source”：在目录登记为可编辑数据集，或明确登记为生成/专用来源。
- 保存后回滚：查看对话框中的 headless `DataLoader` 诊断，修正 schema、契约或跨表引用；草稿仍在 `user://`。
- 契约登记失败：确认 key 属于内容白名单、ID 前缀合法、ID 未重复；代码原语必须先走正式设计/实现流程。
- 搜索没有新内容：确认文件已保存，并触发 Godot 文件系统扫描；未保存草稿不会污染磁盘索引。
