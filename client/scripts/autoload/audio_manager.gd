# Doc: docs/代码/audio_manager.md
# Authority: docs/游戏设计文档.md §9.17, docs/决策记录.md ADR #27
extends Node
class_name AudioManagerAutoload


signal sfx_registered(audio_id: String, max_polyphony: int)
signal music_registered(audio_id: String)
signal sfx_play_requested(audio_id: String, player: AudioStreamPlayer)
signal music_play_requested(audio_id: String)
signal volume_synced(bus_name: String, linear_value: float, volume_db: float)
signal playback_stopped(audio_id: String)

const AUDIO_IDS := preload("res://scripts/contracts/audio_ids.gd")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")

const MASTER_BUS: String = "Master"
const MUSIC_BUS: String = "Music"
const SFX_BUS: String = "SFX"
const UI_BUS: String = "UI"
const MIN_VOLUME_DB: float = -80.0
const DEFAULT_SFX_POLYPHONY: int = 8

var _sfx_streams: Dictionary = {}
var _music_streams: Dictionary = {}
var _active_sfx: Dictionary = {}
var _current_music_id: String = ""
var _music_player: AudioStreamPlayer = null
var _missing_bus_count: int = 0


func _ready() -> void:
	_validate_required_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)
	_sync_all_volumes()
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)


func registered_audio_prefixes() -> Array[String]:
	var result: Array[String] = []
	for prefix: String in AUDIO_IDS.PREFIXES:
		result.append(prefix)
	return result


func registered_sfx_count() -> int:
	return _sfx_streams.size()


func registered_music_count() -> int:
	return _music_streams.size()


func registered_stream_count() -> int:
	return registered_sfx_count() + registered_music_count()


func missing_bus_count() -> int:
	return _missing_bus_count


func required_buses_ready() -> bool:
	for bus_name: String in _required_buses():
		if AudioServer.get_bus_index(bus_name) == -1:
			return false
	return true


func is_music_playing() -> bool:
	return _music_player != null and _music_player.playing


func current_music_id() -> String:
	return _current_music_id


func has_stream(audio_id: String) -> bool:
	return _sfx_streams.has(audio_id) or _music_streams.has(audio_id)


func register_sfx(audio_id: String, stream: AudioStream, max_polyphony: int = DEFAULT_SFX_POLYPHONY) -> bool:
	if not _is_sfx_id(audio_id):
		push_error("[AudioManager] audio id is not an SFX/voice id: %s" % audio_id)
		return false
	if stream == null:
		push_error("[AudioManager] cannot register null SFX stream: %s" % audio_id)
		return false

	_sfx_streams[audio_id] = {
		"stream": stream,
		"max_polyphony": maxi(max_polyphony, 1),
	}
	sfx_registered.emit(audio_id, int(_sfx_streams[audio_id]["max_polyphony"]))
	return true


func register_music(audio_id: String, stream: AudioStream) -> bool:
	if not _is_music_id(audio_id):
		push_error("[AudioManager] audio id is not a music id: %s" % audio_id)
		return false
	if stream == null:
		push_error("[AudioManager] cannot register null music stream: %s" % audio_id)
		return false

	_music_streams[audio_id] = stream
	music_registered.emit(audio_id)
	return true


func play_sfx(audio_id: String, opts: Dictionary = {}) -> bool:
	if not _is_sfx_id(audio_id):
		push_error("[AudioManager] unknown or non-SFX audio id: %s" % audio_id)
		return false
	if not _sfx_streams.has(audio_id):
		push_error("[AudioManager] SFX stream is not registered: %s" % audio_id)
		return false

	_prune_finished_sfx(audio_id)
	var sfx_data: Dictionary = _sfx_streams[audio_id]
	var max_polyphony: int = int(opts.get("max_polyphony", sfx_data.get("max_polyphony", DEFAULT_SFX_POLYPHONY)))
	if _active_count(audio_id) >= maxi(max_polyphony, 1):
		return false

	var player := AudioStreamPlayer.new()
	player.name = "%s_player_%d" % [audio_id, _active_count(audio_id)]
	player.bus = String(opts.get("bus", SFX_BUS))
	player.stream = sfx_data["stream"] as AudioStream
	player.volume_db = float(opts.get("volume_db", 0.0))
	player.pitch_scale = float(opts.get("pitch_scale", 1.0))
	player.max_polyphony = maxi(max_polyphony, 1)
	add_child(player)

	if not _active_sfx.has(audio_id):
		_active_sfx[audio_id] = []
	var active_list: Array = _active_sfx[audio_id]
	active_list.append(player)
	player.finished.connect(_on_sfx_finished.bind(audio_id, player))
	player.play()
	sfx_play_requested.emit(audio_id, player)
	return true


func play_music(audio_id: String, fade: float = 0.0) -> bool:
	if not _is_music_id(audio_id):
		push_error("[AudioManager] unknown or non-music audio id: %s" % audio_id)
		return false
	if not _music_streams.has(audio_id):
		push_error("[AudioManager] music stream is not registered: %s" % audio_id)
		return false
	if _music_player == null:
		push_error("[AudioManager] music player is unavailable")
		return false

	# F2 keeps the public API shape; authored fades are implemented in the audio content slice.
	_music_player.stop()
	_music_player.stream = _music_streams[audio_id] as AudioStream
	_music_player.bus = MUSIC_BUS
	_music_player.volume_db = 0.0 if fade <= 0.0 else MIN_VOLUME_DB
	_music_player.play()
	if fade > 0.0:
		_music_player.volume_db = 0.0
	_current_music_id = audio_id
	music_play_requested.emit(audio_id)
	return true


func stop_music() -> void:
	if _music_player == null or _current_music_id.is_empty():
		return

	var stopped_id: String = _current_music_id
	_music_player.stop()
	_current_music_id = ""
	playback_stopped.emit(stopped_id)


func stop_all_sfx() -> void:
	for audio_id: String in _active_sfx.keys():
		var active_list: Array = _active_sfx[audio_id]
		for raw_player: Variant in active_list:
			var player: AudioStreamPlayer = raw_player as AudioStreamPlayer
			if player != null and is_instance_valid(player):
				player.stop()
				player.queue_free()
	_active_sfx.clear()


func sync_volumes() -> void:
	_sync_all_volumes()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == SETTINGS_KEYS.AUDIO_MASTER or key == SETTINGS_KEYS.AUDIO_MUSIC or key == SETTINGS_KEYS.AUDIO_SFX:
		_sync_all_volumes()


func _sync_all_volumes() -> void:
	_set_bus_linear_volume(MASTER_BUS, float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER, 1.0)))
	_set_bus_linear_volume(MUSIC_BUS, float(Settings.get_value(SETTINGS_KEYS.AUDIO_MUSIC, 0.8)))
	_set_bus_linear_volume(SFX_BUS, float(Settings.get_value(SETTINGS_KEYS.AUDIO_SFX, 0.9)))
	_set_bus_linear_volume(UI_BUS, float(Settings.get_value(SETTINGS_KEYS.AUDIO_SFX, 0.9)))


func _set_bus_linear_volume(bus_name: String, linear_value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		push_error("[AudioManager] missing audio bus: %s" % bus_name)
		return

	var normalized_value: float = clampf(linear_value, 0.0, 1.0)
	var volume_db: float = MIN_VOLUME_DB if normalized_value <= 0.0 else linear_to_db(normalized_value)
	AudioServer.set_bus_volume_db(bus_index, volume_db)
	volume_synced.emit(bus_name, normalized_value, volume_db)


func _validate_required_buses() -> void:
	_missing_bus_count = 0
	for bus_name: String in _required_buses():
		if AudioServer.get_bus_index(bus_name) == -1:
			_missing_bus_count += 1
			push_error("[AudioManager] missing required audio bus: %s" % bus_name)


func _required_buses() -> Array[String]:
	return [MASTER_BUS, MUSIC_BUS, SFX_BUS, UI_BUS]


func _on_sfx_finished(audio_id: String, player: AudioStreamPlayer) -> void:
	if _active_sfx.has(audio_id):
		var active_list: Array = _active_sfx[audio_id]
		active_list.erase(player)
		if active_list.is_empty():
			_active_sfx.erase(audio_id)
	if player != null and is_instance_valid(player):
		player.queue_free()
	playback_stopped.emit(audio_id)


func _prune_finished_sfx(audio_id: String) -> void:
	if not _active_sfx.has(audio_id):
		return
	var active_list: Array = _active_sfx[audio_id]
	for index: int in range(active_list.size() - 1, -1, -1):
		var player: AudioStreamPlayer = active_list[index] as AudioStreamPlayer
		if player == null or not is_instance_valid(player) or not player.playing:
			active_list.remove_at(index)
	if active_list.is_empty():
		_active_sfx.erase(audio_id)


func _active_count(audio_id: String) -> int:
	if not _active_sfx.has(audio_id):
		return 0
	var active_list: Array = _active_sfx[audio_id]
	return active_list.size()


func _is_sfx_id(audio_id: String) -> bool:
	return _has_prefix(audio_id, ["sfx_player_", "sfx_enemy_", "sfx_pickup_", "sfx_ui_", "voice_"])


func _is_music_id(audio_id: String) -> bool:
	return _has_prefix(audio_id, ["music_"])


func _has_prefix(audio_id: String, prefixes: Array[String]) -> bool:
	for prefix: String in prefixes:
		if audio_id.begins_with(prefix) and AUDIO_IDS.PREFIXES.has(prefix):
			return true
	return false
