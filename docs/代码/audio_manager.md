# AudioManager 模块文档

> **AI 修改说明**：修改本文档前先读 `docs/AI协作/文档维护指南.md` 与 `docs/代码文档规范.md`。
> 本文档是 `AudioManager` 的代码契约权威；改公共 API、signal、音频 id 校验、Bus 路由、播放生命周期或测试义务时必须同步本文档、`docs/AI导航.md`、`client/README.md` 与 `docs/测试策略.md`。

## 职责

- `AudioManager` 是完整项目的音频统一入口，负责 SFX / voice / music 的注册、播放请求、Bus 路由、音量设置同步和最小运行时诊断。
- 本模块负责阻止业务代码直接调用 `AudioStreamPlayer.play()`，后续战斗、UI、道具等系统只能通过 `AudioManager.play_sfx()` / `play_music()` 发声。
- 当前 F2 切片不负责实际音频资源清单、音频导入规范、完整 cross-fade 曲线、同 id ducking 策略或与 `PoolManager` 的真实音频播放器池集成；这些在音频内容 / F7 UI / F9 打磨阶段补齐。

## 阅读方式

| 你想做什么 | 先看哪里 |
|------------|----------|
| 接入新音效 / BGM 播放 | 本文档“公共 API”“数据与契约” |
| 修改音量设置联动 | `client/scripts/autoload/audio_manager.gd` 与 `docs/代码/settings.md` |
| 增加新音频 id 前缀 | `docs/词表与契约.md` §10，随后跑 `tools/sync_contracts.py` |
| 排查启动时无声 / Bus 异常 | 本文档“故障排查” |

## 代码位置

| 路径 | 作用 |
|------|------|
| `client/scripts/autoload/audio_manager.gd` | AudioManager autoload 实现 |
| `client/project.godot` | 注册 `AudioManager` autoload |
| `client/default_bus_layout.tres` | 默认音频 Bus 配置：`Master` / `Music` / `SFX` / `UI` |
| `client/scripts/contracts/audio_ids.gd` | 自动生成的音频 id 前缀常量 |
| `client/scripts/contracts/settings_keys.gd` | 自动生成的音量设置 key 常量 |
| `client/scripts/boot/formal_client_boot.gd` | F2 启动 smoke 输出音频前缀、已注册流数量和 Bus 状态 |

## 场景 / 节点结构

`AudioManager` 是 autoload 节点。启动后会创建一个内部 `AudioStreamPlayer` 子节点：

```text
AudioManager
└── MusicPlayer
```

SFX 播放时会临时创建 `AudioStreamPlayer` 子节点，播放结束后自动释放。当前没有外部 `.tscn` 结构。

## 运行流程

| 阶段 | 发生什么 | 关键 API / signal |
|------|----------|-------------------|
| `_ready()` | 校验 `Master` / `Music` / `SFX` / `UI` Bus 存在，创建 `MusicPlayer`，同步音量设置，订阅 `Settings.setting_changed` | `sync_volumes()`、`volume_synced` |
| 注册资源 | 调用方注册 SFX 或 music 音频流 | `register_sfx()`、`register_music()` |
| 播放 SFX | 校验 id 前缀与注册状态，创建播放器，设置 Bus / 音量 / pitch / polyphony，播放并记录 active 列表 | `play_sfx()`、`sfx_play_requested` |
| 播放 Music | 校验 `music_` 前缀与注册状态，复用 `MusicPlayer` 播放当前音乐 | `play_music()`、`music_play_requested` |
| 停止 | 停止当前 music 或所有 SFX，并释放临时播放器 | `stop_music()`、`stop_all_sfx()`、`playback_stopped` |

## 公共 API

| 名称 | 输入 | 输出 | 约束 |
|------|------|------|------|
| `registered_audio_prefixes()` | 无 | `Array[String]` | 来自 `AudioIds.PREFIXES`，当前是前缀白名单而非具体资源表 |
| `registered_sfx_count()` | 无 | `int` | 已注册 SFX / voice 流数量 |
| `registered_music_count()` | 无 | `int` | 已注册 music 流数量 |
| `registered_stream_count()` | 无 | `int` | SFX + music 总数 |
| `required_buses_ready()` | 无 | `bool` | 检查 `Master` / `Music` / `SFX` / `UI` |
| `missing_bus_count()` | 无 | `int` | 启动校验时缺失的 Bus 数量，非 0 表示项目 Bus 配置错误 |
| `register_sfx(audio_id, stream, max_polyphony)` | `String`、`AudioStream`、`int` | `bool` | `audio_id` 必须以 `sfx_player_` / `sfx_enemy_` / `sfx_pickup_` / `sfx_ui_` / `voice_` 开头 |
| `register_music(audio_id, stream)` | `String`、`AudioStream` | `bool` | `audio_id` 必须以 `music_` 开头 |
| `play_sfx(audio_id, opts)` | `String`、`Dictionary` | `bool` | 未注册 stream 会 fail-fast 返回 `false`；`opts` 支持 `bus`、`volume_db`、`pitch_scale`、`max_polyphony` |
| `play_music(audio_id, fade)` | `String`、`float` | `bool` | 当前 F2 只保留 fade 参数和 API 形态，真实淡入淡出后续补 |
| `stop_music()` | 无 | `void` | 停止当前 music |
| `stop_all_sfx()` | 无 | `void` | 停止并释放所有临时 SFX 播放器 |
| `sync_volumes()` | 无 | `void` | 从 `Settings` 读取 `audio.master` / `audio.music` / `audio.sfx` 并写入 Bus |

## Signal / Event

| 名称 | 参数 | 触发时机 |
|------|------|----------|
| `sfx_registered` | `audio_id, max_polyphony` | 成功注册 SFX / voice 流 |
| `music_registered` | `audio_id` | 成功注册 music 流 |
| `sfx_play_requested` | `audio_id, player` | SFX 播放器创建并开始播放 |
| `music_play_requested` | `audio_id` | Music 播放请求开始 |
| `volume_synced` | `bus_name, linear_value, volume_db` | 任一音量 Bus 同步完成 |
| `playback_stopped` | `audio_id` | SFX 播放结束或 music 被停止 |

## 数据与契约

- 音频 id 前缀权威在 `docs/词表与契约.md` §10；代码引用自动生成的 `client/scripts/contracts/audio_ids.gd`。
- 当前契约是前缀白名单：`sfx_player_`、`sfx_enemy_`、`sfx_pickup_`、`sfx_ui_`、`music_`、`voice_`。
- 音量设置 key 来自 `SettingsKeys.AUDIO_MASTER`、`AUDIO_MUSIC`、`AUDIO_SFX`。
- 未知前缀、空 stream、未注册 stream 都返回 `false` 并输出 `[AudioManager]` 前缀错误。

## F9 Demo Cue 计划

F9.3 先建立 Demo 占位音频 id 计划，不在没有资源时强行播放音频。具体 id 不写入 `docs/词表与契约.md` 的前缀表，避免污染生成的 `AudioIds.PREFIXES`。

| cue id | 类型 | 触发点 | 当前状态 |
|--------|------|--------|----------|
| `sfx_player_shoot` | SFX | 基础武器发射 | 已在 `weapons.json.fire_audio_id` 声明；等待资源注册后由武器系统播放 |
| `sfx_player_hurt` | SFX | 玩家实际受到伤害 | 计划 id；需走 `AudioManager.play_sfx()`，不得直接创建播放器 |
| `sfx_enemy_hit` | SFX | 敌人受到非致命伤害 | 计划 id；应配合命中反馈，注意 polyphony 上限 |
| `sfx_enemy_die` | SFX | 敌人死亡反馈开始 | 计划 id；可比 hit 音量更低或更短，避免密集刷屏刺耳 |
| `sfx_pickup_orb` | SFX | 经验球收集反馈开始 | 计划 id；适合较低音量和短尾音 |
| `sfx_ui_click` | SFX | 通用 UI 确认 / 按钮点击 | 计划 id；暂停、设置、局外升级可复用 |
| `sfx_ui_levelup` | SFX | 升级选择面板出现或选择生效 | 计划 id；优先用于选择生效，避免面板弹出和选择双响 |
| `music_run_loop` | Music | 标准生存模式游玩中 | 计划 id；真实播放需先注册 music stream |
| `music_boss` | Music | Boss / 精英阶段 | 预留 id；当前 Demo 无 Boss 闭环，不接入播放 |

接入顺序建议：

1. 先补真实或生成的占位音频资源注册切片，验证 `AudioManager.register_sfx()` / `register_music()` 计数和 Bus 路由。
2. 再从低风险 UI cue 开始播放，例如 `sfx_ui_click` / `sfx_ui_levelup`。
3. 最后接入高频 gameplay cue，例如射击、敌人命中和拾取；这些必须有 polyphony / 节流策略，避免实体密度上升后造成音频噪声。

## 依赖

- 上游依赖：`Settings`、`client/default_bus_layout.tres`、`client/scripts/contracts/audio_ids.gd`、`client/scripts/contracts/settings_keys.gd`、Godot `AudioServer`。
- 下游调用方：后续 `Combat`、`UIManager`/UI 场景、道具 / 拾取 / 敌人反馈、结算与菜单音乐。
- 禁止依赖：业务模块不得直接持有长期 `AudioStreamPlayer` 并自行 `play()`；音频 id 不得绕过词表前缀。

## 扩展点

- 新增具体 SFX：先确认 id 前缀已登记，再通过资源加载切片调用 `register_sfx()`。
- 新增 BGM：使用 `music_` 前缀并调用 `register_music()`。
- 后续可把 SFX 临时播放器迁移到 `PoolManager` 池，但公共 API 不变。
- 后续可补完整 fade / ducking / max_polyphony 溢出策略；行为变化需补 L1 测试。

## 常见改动入口

| 你想改什么 | 主要文件 | 同步文档 | 验证方式 |
|------------|----------|----------|----------|
| 新增音频 id 前缀 | `docs/词表与契约.md` | 本文档、AI 导航 | `tools/sync_contracts.py`、`tools/sync_contracts.py --check` |
| 改音量设置联动 | `audio_manager.gd`、`settings.gd` | 本文档、Settings 文档 | headless boot，后续 GUT |
| 接入实际音频资源 | 后续资源加载脚本 / 数据文件 | 本文档、`client/data/README.md` 或音频资源规范 | headless boot + 手动听感 |
| 改播放生命周期 | `audio_manager.gd` | 本文档、测试策略 | L1 + headless boot |

## 故障排查

| 现象 | 优先检查 |
|------|----------|
| headless 启动报未知 AudioManager | `client/project.godot` autoload 是否注册 |
| `play_sfx()` 返回 `false` | id 前缀是否在 `audio_ids.gd`，stream 是否已注册 |
| `play_music()` 返回 `false` | id 是否以 `music_` 开头，music stream 是否已注册 |
| 音量变化无效 | `Settings` 中 `audio.master` / `audio.music` / `audio.sfx` 是否变化，`required_buses_ready()` 是否为 true，`client/default_bus_layout.tres` 是否包含 Music / SFX / UI |
| 业务代码绕过 AudioManager | 搜索 `AudioStreamPlayer.play()`，只允许在 `audio_manager.gd` 内部出现 |

## 测试义务

- 当前切片必跑 L0 契约 / 数据 / 文档检查和 L2 headless boot。
- 后续引入 GUT 后，`AudioManager` 需要覆盖 id 前缀拒绝、注册空 stream 拒绝、注册计数、音量同步、SFX polyphony 上限、music 切换和停止行为。
- 接入真实音频资源后需要补手动听感回归：音量条独立可调，暂停 / UI 音效不误走 Music Bus。

## 迁移 / 兼容

- 当前不影响存档、数据 schema 或回放格式。
- 未来若录制回放需要记录音频事件，必须通过 `Replay.record_decision()` 或专门的非玩法诊断通道，不得让音频播放影响确定性。

## 相关文档

- `docs/游戏设计文档.md` §9.17
- `docs/决策记录.md` ADR #27
- `docs/词表与契约.md` §10
- `docs/测试策略.md`
- `docs/代码/settings.md`
- `docs/代码/pool_manager.md`
