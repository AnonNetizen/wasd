extends SceneTree

# GodotSteam runtime presence smoke. It checks compiled classes without initializing Steam.

const EXPECTED_STEAM_APP_ID: int = 4_955_670
const EXPECTED_GODOTSTEAM_VERSION: String = "4.20"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[steam-runtime-presence-smoke] PASS %s" % label)
	else:
		_failures += 1
		print("[steam-runtime-presence-smoke] FAIL %s" % label)


func _run() -> void:
	_check(Engine.has_singleton("Steam"), "Steam singleton is compiled into the editor")
	_check(ClassDB.class_exists("SteamMultiplayerPeer"), "SteamMultiplayerPeer class is compiled into the editor")
	if Engine.has_singleton("Steam"):
		var steam: Object = Engine.get_singleton("Steam")
		_check(steam.has_method("get_godotsteam_version"), "Steam singleton exposes its GodotSteam version")
		if steam.has_method("get_godotsteam_version"):
			var version := String(steam.call("get_godotsteam_version"))
			_check(version == EXPECTED_GODOTSTEAM_VERSION, "GodotSteam version is 4.20")
	_check(
		int(ProjectSettings.get_setting("steam/initialization/app_data/app_id", 0)) == EXPECTED_STEAM_APP_ID,
		"GodotSteam App ID setting uses 4955670"
	)
	_check(
		not bool(ProjectSettings.get_setting("steam/initialization/processes/initialize_on_startup", true)),
		"GodotSteam automatic initialization is disabled"
	)
	_check(
		not bool(ProjectSettings.get_setting("steam/initialization/processes/embed_callbacks", true)),
		"GodotSteam embedded callbacks are disabled"
	)

	if ClassDB.class_exists("SteamMultiplayerPeer"):
		var peer: Object = ClassDB.instantiate("SteamMultiplayerPeer")
		_check(peer != null, "SteamMultiplayerPeer can be instantiated")
		if peer != null:
			_check(peer.has_method("host_with_lobby"), "SteamMultiplayerPeer has host_with_lobby")
			_check(peer.has_method("connect_to_lobby"), "SteamMultiplayerPeer has connect_to_lobby")
			_check(peer.has_method("add_peer"), "SteamMultiplayerPeer has add_peer")

	if _failures == 0:
		print("[steam-runtime-presence-smoke] ALL PASS")
	else:
		print("[steam-runtime-presence-smoke] %d FAILURES" % _failures)
	quit(1 if _failures > 0 else 0)
