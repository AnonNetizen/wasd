# Doc: docs/代码/platform_services.md
# Authority: docs/游戏设计文档.md §9.22, docs/决策记录.md ADR #84
class_name PlatformServicesAutoload
extends Node


signal provider_changed(provider: String, available: bool)
signal achievement_requested(achievement_id: String, accepted: bool)
signal rich_presence_changed(key: String, value: String, accepted: bool)
signal overlay_requested(target: String, accepted: bool)
signal multiplayer_requested(request: Dictionary, accepted: bool)

const CAP_ACHIEVEMENTS: String = "achievements"
const CAP_LOBBIES: String = "lobbies"
const CAP_MULTIPLAYER: String = "multiplayer"
const CAP_OVERLAY: String = "overlay"
const CAP_RICH_PRESENCE: String = "rich_presence"
const CAP_STATS: String = "stats"
const CAP_USER_IDENTITY: String = "user_identity"
const PROVIDER_NONE: String = "none"
const PROVIDER_STEAM: String = "steam"

const CAPABILITY_KEYS: Array[String] = [
	CAP_ACHIEVEMENTS,
	CAP_LOBBIES,
	CAP_MULTIPLAYER,
	CAP_OVERLAY,
	CAP_RICH_PRESENCE,
	CAP_STATS,
	CAP_USER_IDENTITY,
]
const PREFERRED_PROVIDER: String = PROVIDER_STEAM

var _active_provider: String = PROVIDER_NONE
var _capabilities: Dictionary = {}
var _diagnostics: Array[String] = []
var _rich_presence: Dictionary = {}
var _achievement_requests: Array[Dictionary] = []
var _multiplayer_requests: Array[Dictionary] = []
var _overlay_requests: Array[Dictionary] = []
var _provider_available: bool = false


func _ready() -> void:
	reload_backend()


func reload_backend() -> void:
	_reset_capabilities()
	_diagnostics.clear()
	_active_provider = PROVIDER_NONE
	_provider_available = false
	_add_diagnostic("steam provider is reserved but no Steamworks adapter is connected")
	provider_changed.emit(_active_provider, _provider_available)


func preferred_provider() -> String:
	return PREFERRED_PROVIDER


func active_provider() -> String:
	return _active_provider


func is_available() -> bool:
	return _provider_available


func supports(capability: String) -> bool:
	return bool(_capabilities.get(capability, false))


func capabilities() -> Dictionary:
	return _capabilities.duplicate()


func diagnostics() -> Array[String]:
	return _diagnostics.duplicate()


func platform_user() -> Dictionary:
	return {
		"provider": _active_provider,
		"available": _provider_available,
		"user_id": "",
		"display_name": "",
	}


func rich_presence() -> Dictionary:
	return _rich_presence.duplicate()


func achievement_requests() -> Array[Dictionary]:
	return _duplicate_request_list(_achievement_requests)


func multiplayer_requests() -> Array[Dictionary]:
	return _duplicate_request_list(_multiplayer_requests)


func overlay_requests() -> Array[Dictionary]:
	return _duplicate_request_list(_overlay_requests)


func unlock_achievement(achievement_id: String) -> bool:
	if achievement_id.strip_edges().is_empty():
		_add_diagnostic("achievement id must be non-empty", true)
		achievement_requested.emit(achievement_id, false)
		return false

	var accepted: bool = _provider_available and supports(CAP_ACHIEVEMENTS)
	_achievement_requests.append({
		"id": achievement_id,
		"action": "unlock",
		"accepted": accepted,
		"provider": _active_provider,
		"tick": _current_tick(),
	})
	if not accepted:
		_add_diagnostic("achievement unlock ignored because platform achievements are unavailable: %s" % achievement_id)
	achievement_requested.emit(achievement_id, accepted)
	return accepted


func store_stats() -> bool:
	var accepted: bool = _provider_available and supports(CAP_STATS)
	if not accepted:
		_add_diagnostic("store_stats ignored because platform stats are unavailable")
	return accepted


func set_rich_presence(key: String, value: String) -> bool:
	var normalized_key: String = key.strip_edges()
	if normalized_key.is_empty():
		_add_diagnostic("rich presence key must be non-empty", true)
		rich_presence_changed.emit(key, value, false)
		return false

	_rich_presence[normalized_key] = value
	var accepted: bool = _provider_available and supports(CAP_RICH_PRESENCE)
	if not accepted:
		_add_diagnostic("rich presence stored locally only because platform rich presence is unavailable: %s" % normalized_key)
	rich_presence_changed.emit(normalized_key, value, accepted)
	return accepted


func clear_rich_presence(key: String) -> bool:
	var normalized_key: String = key.strip_edges()
	if _rich_presence.has(normalized_key):
		_rich_presence.erase(normalized_key)
	var accepted: bool = _provider_available and supports(CAP_RICH_PRESENCE)
	rich_presence_changed.emit(normalized_key, "", accepted)
	return accepted


func clear_all_rich_presence() -> bool:
	_rich_presence.clear()
	return _provider_available and supports(CAP_RICH_PRESENCE)


func show_overlay(target: String = "") -> bool:
	var accepted: bool = _provider_available and supports(CAP_OVERLAY)
	_overlay_requests.append({
		"target": target,
		"accepted": accepted,
		"provider": _active_provider,
		"tick": _current_tick(),
	})
	if not accepted:
		_add_diagnostic("overlay request ignored because platform overlay is unavailable: %s" % target)
	overlay_requested.emit(target, accepted)
	return accepted


func create_lobby(max_members: int, metadata: Dictionary = {}) -> bool:
	return _record_multiplayer_request("create_lobby", {
		"max_members": max_members,
		"metadata": metadata.duplicate(true),
	}, CAP_LOBBIES)


func join_lobby(lobby_id: String) -> bool:
	return _record_multiplayer_request("join_lobby", {"lobby_id": lobby_id}, CAP_LOBBIES)


func leave_lobby() -> bool:
	return _record_multiplayer_request("leave_lobby", {}, CAP_LOBBIES)


func invite_friend(friend_id: String) -> bool:
	return _record_multiplayer_request("invite_friend", {"friend_id": friend_id}, CAP_LOBBIES)


func _record_multiplayer_request(action: String, payload: Dictionary, required_capability: String = CAP_MULTIPLAYER) -> bool:
	var accepted: bool = _provider_available and supports(required_capability)
	var request: Dictionary = {
		"action": action,
		"payload": payload.duplicate(true),
		"accepted": accepted,
		"required_capability": required_capability,
		"provider": _active_provider,
		"tick": _current_tick(),
	}
	_multiplayer_requests.append(request)
	if not accepted:
		_add_diagnostic("multiplayer request ignored because platform capability is unavailable: %s (%s)" % [action, required_capability])
	multiplayer_requested.emit(request.duplicate(true), accepted)
	return accepted


func _reset_capabilities() -> void:
	_capabilities.clear()
	for capability: String in CAPABILITY_KEYS:
		_capabilities[capability] = false


func _duplicate_request_list(requests: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for request: Dictionary in requests:
		result.append(request.duplicate(true))
	return result


func _current_tick() -> int:
	if has_node("/root/GameClock"):
		return int(get_node("/root/GameClock").call("tick"))
	return 0


func _add_diagnostic(message: String, warn: bool = false) -> void:
	if not _diagnostics.has(message):
		_diagnostics.append(message)
	if warn:
		push_warning("[PlatformServices] %s" % message)
