# ModLoader 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `ModLoader` 本地包接口的代码契约权威；改 manifest、patch 白名单、动态 Gear Mod id、媒体边界、环境指纹、加载顺序或测试义务时必须同步本文档、GDD、AI 导航、数据手册与测试策略；只有达到重大决策门槛时才同步 ADR。

## 职责

- 扫描 `user://mods/<package_id>/mod.json`，按 `load_order`、`id` 稳定加载 manifest v2。
- 在合并前独立校验每个包的 Gear Mod 结构、ID 所有权、patch 目标、双语 locale 与安全路径；坏玩法包整体禁用，基础游戏和其他包继续。
- 在扫描时把玩法 patch、locale 与媒体解码成不可变内存快照；本次加载周期内不再读取包文件。
- 为 DataLoader 提供只读包级 payload 和最终 JSON/CSV append，为 Save/Replay 提供精确 `mod_environment`。
- 注册本地图片与非循环 SFX；坏媒体只记录诊断并回退，不禁用玩法包。
- 不执行脚本、场景、Shader 或二进制插件，不允许本地包扩展 stat、trigger、condition、action、status、enemy、pool、RNG 等核心契约。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 制作本地 Gear Mod 包 | 本文档“Manifest v2”与“数据 patch” |
| 排查包被禁用 | `package_statuses()` 与“包级隔离” |
| 接图片或音效 | “媒体注册表”与 `docs/代码/audio_manager.md` |
| 校验 Run / Replay 环境 | `mod_environment()`、`validate_environment()` |
| 修改 schema / 白名单 | `client/scripts/autoload/mod_loader.gd` 与 DataLoader 文档 |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/mod_loader.gd` | manifest v2、包快照、诊断、媒体和环境 API |
| `client/scripts/autoload/data_loader.gd` | 逐包最终参数 / 跨表校验与合并 |
| `client/scripts/autoload/localization.gd` | 把快照 locale rows 注册为运行时 Translation |
| `client/scripts/autoload/audio_manager.gd` | 注册和播放包内非循环 SFX |
| `client/tools/mod_loader_v2_smoke.gd` | manifest v2、隔离、媒体、locale、环境专项 smoke |
| `tools/godot_bridge.py` | `mod-loader-smoke` 隔离入口 |

## 场景 / 节点结构

无场景。`ModLoader` 是最早注册的 autoload；DataLoader、Localization 与 AudioManager 只读取其快照。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| 启动扫描 | 创建 / 扫描 `user://mods`，目录名排序后解析 manifest | `_ready()`、`reload_packages()` |
| 包级校验 | 校验 v2、namespace、允许 patch、Gear Mod 组件和内置效果原语 | `package_statuses()` |
| 快照 | 读取 JSON / CSV，解码媒体，计算排除 locale / 媒体的 `gameplay_hash` | `package_gameplay_payloads()` |
| 最终校验 | DataLoader 对每个启用包做参数和跨表校验；失败包调用禁用接口后继续 | `disable_package()` |
| 下游注册 | Localization 重建包 Translation；AudioManager 重建包 SFX | `mods_reloaded` |
| 主菜单重载 | 仅无活动 Run / Replay 时重新扫描 | `set_runtime_activity()`、`can_reload_packages()` |

## 公共 API

| 名称 | 输出 / 作用 | 约束 |
|------|-------------|------|
| `reload_packages() -> bool` | 重新扫描并发出 `mods_reloaded` | 活动 Run / Replay 返回 `false`，保留现有快照 |
| `set_runtime_activity(run_active, replay_active)` | 设置重载门 | 由正式流程接线，不自行查询业务模块 |
| `can_reload_packages() -> bool` | 当前能否显式重载 | 只在主菜单应为 true |
| `enabled_mod_count() -> int` | 已启用玩法包数量 | 不含 disabled / invalid 包 |
| `package_statuses() -> Array[Dictionary]` | `{id,name,version,enabled,status,diagnostics}` | 稳定排序、深拷贝，主菜单面板只读 |
| `diagnostics() -> Array[String]` | 全局诊断副本 | 同时输出 `[ModLoader]` warning |
| `contract_extensions(key) -> Array[String]` | 动态 `gear_mod_ids` / `locale_prefixes` | 其他核心契约一律拒绝 |
| `package_gameplay_payloads() -> Array[Dictionary]` | `{id,mods,reward_pool_contributions,drop_rows}` | 仅启用包、稳定顺序、深拷贝；供 DataLoader 逐包校验 |
| `package_locale_rows() -> Array[Dictionary]` | 双语 locale rows 深拷贝 | 供 Localization 重建运行时 Translation |
| `apply_json_mods(path, base)` | 向 `gear_mods.json` 指定数组追加快照条目 | 不覆盖基础记录 |
| `apply_csv_mods(path, base)` | 向掉落表 / locale 追加快照行 | 不覆盖基础记录 |
| `mod_environment() -> Array[Dictionary]` | `{id,version,gameplay_hash}` | 与包执行顺序一致，精确用于 Run / Replay |
| `validate_environment(expected) -> Dictionary` | `{ok,reason}` | 数量、顺序、id、version、hash 任一不符即失败 |
| `has_image_asset(id)` / `image_texture(id)` | 查询 / 返回运行时 `ImageTexture` | 缺失返回 false / null，由 UI 使用内置图标 |
| `media_audio_entries()` | `{id,package_id,stream,max_polyphony}` | 只返回解码成功的非循环 SFX |

`disable_package(package_id, reason)` 是 DataLoader 的启动期隔离接口：移除该包玩法 / 媒体并更新只读状态，不用于活动局内动态卸载。

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `mods_reloaded` | 无 | 成功重扫，或 DataLoader 禁用坏包后 |
| `reload_rejected` | `reason` | 活动 Run / Replay 拒绝重载时 |

## Manifest v2

```json
{
  "schema_version": 2,
  "id": "example_pack",
  "name": "Example Pack",
  "version": "1.0.0",
  "enabled": true,
  "load_order": 0,
  "contract_extensions": {
    "gear_mod_ids": ["mod_example_pack_guardian_cell"],
    "locale_prefixes": ["mod_example_pack_"]
  },
  "data_patches": [
    {
      "type": "json_array_append",
      "target": "gear_mods.json",
      "path": "data/gear_mods.json",
      "array_key": "mods"
    },
    {
      "type": "csv_append",
      "target": "strings.csv",
      "path": "data/strings.csv"
    }
  ],
  "media_assets": [
    {
      "id": "mod_example_pack_guardian_icon",
      "type": "image",
      "path": "media/guardian.png"
    },
    {
      "id": "mod_example_pack_guardian_sfx",
      "type": "sfx",
      "path": "media/guardian.ogg",
      "max_polyphony": 4
    }
  ]
}
```

- `id` 必须是目录同名 snake_case；所有动态 Gear Mod、locale 与媒体 id 必须以 `mod_<package_id>_` 开头。
- 本地 Gear Mod 只能使用 `id/name_key/desc_key/rarity/default_unlocked/codex_icon_path/placement_sfx_id/components`；`default_unlocked` 只能为 true 或省略，禁止 `unlock_rule_id`。`placement_sfx_id` 必须引用同包已验证、namespaced 的非循环 SFX；媒体失败时从合并定义删除该字段并静音回退，不禁用玩法内容。
- `components[]` 只允许官方 `modifier`、`program`、`board_rule`；program 的 trigger / condition / action 必须来自生成契约。参数与跨表引用由 DataLoader 最终校验。
- `codex_icon_path` 填媒体 id，不填文件路径；必须指向本包有效 image。缺图、坏图或越权 id 会从快照移除并回退内置图标，不禁用玩法包。

## 数据 patch

| 类型 | 允许目标 | 作用 |
|------|----------|------|
| `json_array_append` | `gear_mods.json.mods` | 新增包拥有的 Gear Mod 定义 |
| `json_array_append` | `gear_mods.json.reward_pool_contributions` | 向官方奖励池贡献本包 Gear Mod |
| `csv_append` | `gear_mod_drop_tables.csv` | 为本包 Gear Mod 增加官方敌人掉落 |
| `csv_append` | `strings.csv` | 增加 namespaced `zh_CN` / `en` 文案 |

路径必须是包目录内的 `/` 分隔相对路径；拒绝绝对路径、`..`、反斜杠、协议和盘符。append 不能覆盖基础记录。

### 玩法 patch 资源预算

| 对象 | 上限 |
|------|------|
| `mod.json` | 256 KiB |
| 单个 JSON / CSV patch 文件 | 1 MiB |
| 单包全部 patch 声明 | 4 MiB；同一文件被多个 append 声明复用时按每次声明重复计费，防止反复解析 / 深拷贝绕过预算 |
| JSON | 最大深度 32、最多 50,000 个 value 节点 |
| CSV | 最多 10,000 个非空数据行、每行（含 header）最多 64 列 |

预算在内容进入缓存和 DataLoader 前执行；JSON 节点在加入待校验栈时即计数，待处理结构本身也不会越过 50,000 节点上限。任一玩法 patch 超限都会沿用现有 `invalid` 包级隔离，不保留部分 patch，也不影响基础数据或其他包。

## 包级隔离与环境指纹

- 每个包先独立解析与校验，再进入基础数据合并；manifest、资源预算、玩法 schema、ID 所有权或跨表失败会把该包标为 `invalid`。
- patch 内容在扫描时深拷贝缓存；磁盘变化必须等主菜单显式 `reload_packages()` 才可见。
- `gameplay_hash` 覆盖包拥有的 Gear Mod id、玩法 components、掉落与奖励池贡献；locale、图片、音频、`codex_icon_path` 与 `placement_sfx_id` 不影响玩法 hash。
- Run / Replay 必须保存 `mod_environment()`；环境缺失、版本或 hash 不符由 Save / Replay 阻止继续，不把文件当损坏档隔离。

## 媒体注册表

| 类型 | 格式 | 单文件限制 | 额外限制 |
|------|------|------------|----------|
| image | PNG / WebP / JPEG | 4 MiB | 最大 1024×1024，返回 `ImageTexture` |
| sfx | Ogg Vorbis / MP3 / WAV | 8 MiB | 最长 30 秒、强制非循环，由 AudioManager 播放 |

每包最多 128 项媒体、总大小最多 64 MiB。扩展名、真实文件头、解码结果、安全路径和命名空间都会校验。媒体失败只进入诊断并回退为空，不改变 `gameplay_hash`，也不禁用玩法包。

## 依赖

- 上游：Godot `DirAccess`、`FileAccess`、`JSON`、运行时图片 / 音频解码和生成契约。
- 下游：DataLoader、Localization、AudioManager、SaveManager、Replay、主菜单 Mod 面板。
- 禁止依赖：GameplayEffectRuntime、业务 UI、网络平台 SDK 或创意工坊下载逻辑。

## 扩展点

- 新本地 Gear Mod 只通过现有组件和效果原语组合；新增底层 primitive 必须进入官方开发、契约和测试流程。
- 新 patch 目标、媒体类型或核心契约扩展必须先改 GDD / ADR / schema / 安全测试，不能由 manifest 自声明打开。
- 创意工坊未来只负责把内容同步到 `user://mods/<package_id>/`，不改变校验与运行时边界。

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| 包显示 invalid | `package_statuses().diagnostics` 的字段路径、namespace 和 primitive id |
| 修改文件后无变化 | 是否在无活动 Run / Replay 的主菜单显式重载 |
| Run / Replay 被阻止 | `validate_environment()` 的 id / version / gameplay_hash 差异 |
| 图标回退 | `codex_icon_path` 是否为本包 image id、文件头与尺寸是否有效 |
| 音效静音 | 媒体诊断、30 秒 / 8 MiB 限制和 AudioManager 注册状态 |
| 本地文案显示 key | strings patch 是否有 namespaced key、`zh_CN` / `en` 是否非空，Localization 是否收到 reload |

## 测试义务

- 必跑 `py -3 tools/godot_bridge.py --project client mod-loader-smoke`。
- 同时跑 ModLoader / AudioManager / Localization 目标 GDScript lint、数据校验和 headless boot。
- 修改玩法 patch 读取边界时覆盖 manifest / 单文件 / 包总字节、JSON 深度 / 节点数和 CSV 行 / 列预算负例。
- 修改 Gear Mod 最终 schema 时补 DataLoader schema 测试；修改环境指纹时补 Save / Replay mismatch 测试。
- 真实本地包安装、主菜单诊断可读性、图片观感、音效质量和中英文 1920×1080 布局保持“待人工验收”。

## 迁移 / 兼容

- 只接受 manifest v2；v1 不迁移、不保留兼容接口。
- 本地 Gear Mod 安装即开放，不写 Meta，也不能声明解锁规则。
- 活动 Run / Replay 不支持热重载。

## 相关文档

- `docs/游戏设计文档.md` §9.21
- `docs/代码/data_loader.md`
- `docs/代码/audio_manager.md`
- `docs/代码/localization.md`
- `docs/测试策略.md`
