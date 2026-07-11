extends SceneTree

# Steam App ID / 初始化边界 headless smoke：
#   godot --headless --path output/steamworks_lab --script res://tests/steam_config_smoke.gd -- --disable-steam

const NETWORK_SESSION_SCRIPT := preload("res://scripts/network_session.gd")
const TRANSPORT_SCRIPT := preload("res://scripts/transport_adapter.gd")

const EXPECTED_STEAM_APP_ID: int = 4_955_670

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[steam-config-smoke] PASS %s" % label)
	else:
		_failures += 1
		print("[steam-config-smoke] FAIL %s" % label)


func _run() -> void:
	_check(TRANSPORT_SCRIPT.configured_app_id() == EXPECTED_STEAM_APP_ID, "ProjectSettings uses App ID 4955670")
	_check(TRANSPORT_SCRIPT.development_app_id() == EXPECTED_STEAM_APP_ID, "steam_appid.txt matches App ID 4955670")
	_check(TRANSPORT_SCRIPT.app_id_configuration_is_valid(), "development and runtime App ID sources agree")
	_check(bool(ProjectSettings.get_setting("steam/restart_through_client", false)), "export builds request Steam relaunch")
	_check(
		TRANSPORT_SCRIPT.should_restart_through_client(true, true, true),
		"export template with enabled restart method requests Steam relaunch"
	)
	_check(
		not TRANSPORT_SCRIPT.should_restart_through_client(false, true, true),
		"editor run does not request Steam relaunch"
	)
	_check(
		not TRANSPORT_SCRIPT.should_restart_through_client(true, false, true),
		"disabled restart setting skips Steam relaunch"
	)
	_check(
		not TRANSPORT_SCRIPT.should_restart_through_client(true, true, false),
		"missing restart method skips Steam relaunch"
	)

	_check(TRANSPORT_SCRIPT.steam_init_result_succeeded(true), "boolean init success is accepted")
	_check(not TRANSPORT_SCRIPT.steam_init_result_succeeded(false), "boolean init failure is rejected")
	_check(TRANSPORT_SCRIPT.steam_init_result_succeeded({"status": 0}), "dictionary init success is accepted")
	_check(not TRANSPORT_SCRIPT.steam_init_result_succeeded({"status": 1}), "dictionary init failure is rejected")

	_check(
		TRANSPORT_SCRIPT.lobby_metadata_is_compatible(
			TRANSPORT_SCRIPT.LAB_MARKER_VALUE,
			TRANSPORT_SCRIPT.LAB_VERSION_VALUE
		),
		"matching lobby marker and protocol version are accepted"
	)
	_check(
		not TRANSPORT_SCRIPT.lobby_metadata_is_compatible("wrong_marker", TRANSPORT_SCRIPT.LAB_VERSION_VALUE),
		"lobby marker mismatch is rejected"
	)
	_check(
		not TRANSPORT_SCRIPT.lobby_metadata_is_compatible(TRANSPORT_SCRIPT.LAB_MARKER_VALUE, "999"),
		"lobby protocol version mismatch is rejected"
	)
	_check(
		TRANSPORT_SCRIPT.steam_disabled_from_args(PackedStringArray(["--disable-steam"])),
		"offline smoke can disable Steam explicitly"
	)

	var adapter := TRANSPORT_SCRIPT.new() as Node
	root.add_child(adapter)
	await process_frame
	_check(not bool(adapter.call("steam_available")), "disabled Steam is unavailable")
	_check(
		String(adapter.call("steam_diagnostics")).begins_with("Steam integration is disabled"),
		"disabled Steam reports deterministic offline diagnostics"
	)
	adapter.set("_pending_join", true)
	adapter.set("_active_lobby_id", "123456")
	adapter.call("_on_lobby_joined", 123456, 0, false, 2)
	_check(not bool(adapter.get("_pending_join")), "failed Steam lobby join clears pending state")
	_check(String(adapter.get("_active_lobby_id")) == "", "failed Steam lobby join clears adapter lobby id")
	adapter.queue_free()

	var session := NETWORK_SESSION_SCRIPT.new() as Node
	root.add_child(session)
	await process_frame
	session.set("_active_transport", "steam")
	session.set("_steam_connection_pending", true)
	session.call("_on_steam_failed", "simulated Steam connection failure")
	_check(String(session.call("active_transport")) == "offline", "Steam connection failure restores offline transport")
	_check(String(session.call("lobby_id")) == "", "Steam connection failure clears lobby id")
	session.queue_free()

	if _failures == 0:
		print("[steam-config-smoke] ALL PASS")
	else:
		print("[steam-config-smoke] %d FAILURES" % _failures)
	quit(1 if _failures > 0 else 0)
