# DataLoader 模块文档

> 权威范围：本页记录正式数据读取、schema、Mod overlay、诊断与指纹边界。字段定义以 `client/data/schemas/catalog.json` 及对应 schema 为准；约定字符串以 `docs/词表与契约.md` 为准。

## 职责与边界

`DataLoader` 是 `client/data/` 的公开读取门面，负责：

- 加载 JSON / CSV、包装稳定的 `路径:字段:期望` 诊断，并维护 `schema_counts()`。
- 读取 `_contracts.json`，提供 `contracts()`、`contract_values()` 与 `has_contract_value()`。
- 在正式读取 API 上应用 Mod overlay，并在合并后隔离坏包。
- 为跨文件语义规则建立 locale、词表、资源与内容 ID 索引。
- 输出技能与 Gear Mod 的稳定玩法指纹 payload。

它不解释玩法、不改数值、不保存存档，也不拥有 Replay、RNG、UI 或热重载生命周期。

## 声明式 schema

`client/data/schemas/catalog.json` 按稳定顺序登记每个正式 JSON / CSV 数据源及 `modules/*.json`。schema 只校验仓库内正式数据：直接读取 `res://data/`，不接受 Mod overlay，也不进入玩法指纹。

项目实现一个确定性 JSON Schema 兼容子集：

- 标准关键字：`type`、`required`、`properties`、`additionalProperties`、`items`、`enum`、`const`、字符串长度 / pattern、数组长度、数值上下界和本地 `$ref`。
- 项目扩展：`x-wasd-order`、`x-wasd-ref`、`x-wasd-csv`、`x-wasd-unique-by`、`x-wasd-removed-field`、`x-wasd-relation`、`x-wasd-semantic-rules`、`x-wasd-error`、`x-wasd-count-key`。
- 未知 keyword、无效本地引用、未知 relation / CSV parser / semantic handler 一律 fail fast。
- Python 与 GDScript 解释器都返回有序 `{ok, errors, counts}`，共同消费 `client/tests/fixtures/schema_conformance.json`。

结构、类型、必填、枚举、范围和可声明引用属于 schema。模块图连通性、效果程序、内容预算、动态资源检查及 Mod 合并语义属于少量 semantic handler；同一不变量不得同时在 schema、handler 和专项 validator 中重复维护。

## 公共契约

| API | 可观察行为 |
|-----|------------|
| `validate_project_data()` | 保持既有调用方式、诊断格式与确定性顺序；成功后正式 catalog 也必须通过 |
| `schema_counts()` | 返回上次校验的深拷贝计数；键名保持兼容 |
| `load_json()` / `load_csv()` | 正式读取门面；解析成功后才应用 Mod overlay，contracts 例外 |
| `reload_contracts()` / `contracts()` | 重新加载基础契约，并只在允许的契约上合并 Mod 扩展 |
| `gear_mod_gameplay_fingerprint_payload()` | 返回稳定、可哈希的 Gear Mod 数据；schema 文件不参与 |
| `effect_gameplay_fingerprint_payload()` | 返回稳定、可哈希的效果数据；schema 文件不参与 |
| `mod_diagnostics()` | 返回 ModLoader 提供的诊断副本 |

Meta v4、Run v20、Replay v10、数据指纹和兼容拒绝策略不由本模块迁移或放宽。

## 所有权

| 路径 | 所有权 |
|------|--------|
| `client/scripts/autoload/data_loader.gd` | 公开门面、Mod-aware 顺序、诊断、计数和语义编排 |
| `client/scripts/data/data_source_reader.gd` | 单次物理读取与解析；无 Mod、无缓存、无错误输出 |
| `client/scripts/data/data_reference_index_builder.gd` | 从调用方提供的值建立引用索引 |
| `client/scripts/data/declarative_schema_validator.gd` | GDScript schema 子集解释器 |
| `client/scripts/data/declarative_data_catalog.gd` | GDScript 正式 catalog runner |
| `tools/declarative_schema.py` | Python schema 子集解释器 |
| `tools/project_schema_catalog.py` | Python 正式 catalog runner |
| `client/data/schemas/` | 有序 catalog 与正式数据 schema |

新增数据源时只登记一次 catalog；新增 semantic rule ID 时先登记词表并同步生成契约常量。

## 风险归属与最低验证

| 风险 | 权威证据 |
|------|----------|
| schema 解释器关键字、顺序或诊断 | 共享 conformance fixture + `unit/schema` 目标 GUT |
| 正式数据内容或 catalog | contracts check + `validate_data.py` + 快速 schema runner |
| Mod overlay / 坏包隔离 | ModLoader 专项测试或 smoke；声明式 catalog 不重复覆盖 |
| 跨文件图、效果程序、资源存在性 | 对应 semantic handler 聚焦测试 |
| 启动接线 / autoload | 一次 formal headless boot |
| 指纹内容 | 指纹 builder 目标测试；只有稳定摘要有意改变才跑黄金回放 |

常用入口：

```powershell
python tools/sync_contracts.py --check
python tools/validate_data.py
python tools/test_data_loader_schema.py
python tools/godot_bridge.py --project client gut --test-dir unit/schema
python tools/godot_bridge.py --project client headless-boot
```

不得再为每个字段复制仓库、启动 validator 子进程或建立逐 validator 全矩阵。修改某个 semantic handler，只追加该 handler 的代表性正反例。

## 故障排查

- Python 与 Godot 诊断不一致：先在共享 fixture 中缩成最小复现，再同步两端解释器。
- catalog 通过但运行时失败：检查该规则是否应归 semantic handler、资源检查或 Mod 合并阶段。
- Mod 数据被正式 schema 拒绝：确认调用方没有把 overlay 结果传给 declarative catalog。
- 指纹意外变化：检查 schema / fixture 是否错误进入 payload builder；它们必须完全排除。

## 相关文档

- `docs/词表与契约.md`
- `docs/测试策略.md`
- `client/data/README.md`
- `docs/代码/mod_loader.md`
