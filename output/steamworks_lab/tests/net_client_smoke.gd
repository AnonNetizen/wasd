extends SceneTree

# 联机 client 端 headless smoke（先启动 net_host_smoke.gd）：
#   py -3 tools/steamworks_lab_toolchain.py smoke --suite enet

const TEST_PORT: int = 24568
const JOIN_DELAY_SECONDS: float = 0.5
const READY_CHECK_SECONDS: float = 1.0
const SYNC_WAIT_SECONDS: float = 8.0
const SETTINGS_PATH: String = "user://net_client_smoke_settings.cfg"
const SAVE_PATH: String = "user://net_client_smoke_save.cfg"


func _init() -> void:
	call_deferred("_run")


func _wait_seconds(seconds: float) -> void:
	var frame_count := ceili(seconds * 60.0)
	for index in range(frame_count):
		await process_frame


func _run() -> void:
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	main_scene.set("_settings_config_path", SETTINGS_PATH)
	main_scene.set("_save_config_path", SAVE_PATH)
	root.add_child(main_scene)
	await process_frame
	await _wait_seconds(JOIN_DELAY_SECONDS)
	var session: Node = main_scene.get("_session")
	session.call("join_local", "127.0.0.1", _test_port())
	await _wait_seconds(READY_CHECK_SECONDS)

	var failures := 0
	if main_scene.get("_director") == null:
		print("[net-client-smoke] PASS waits in ready room before host launch")
	else:
		print("[net-client-smoke] FAIL battle started before host launch")
		failures += 1

	await _wait_seconds(SYNC_WAIT_SECONDS)

	var local_id := int(session.call("local_peer_id"))
	if local_id > 1:
		print("[net-client-smoke] PASS joined as peer %d" % local_id)
	else:
		print("[net-client-smoke] FAIL still peer %d (no connection)" % local_id)
		failures += 1

	var players: Dictionary = main_scene.call("player_nodes")
	if players.has(1) and players.has(local_id):
		print("[net-client-smoke] PASS host and local players mirrored")
	else:
		print("[net-client-smoke] FAIL players missing (have %s)" % str(players.keys()))
		failures += 1

	var director: Node = main_scene.get("_director")
	if director == null:
		print("[net-client-smoke] FAIL director missing")
		failures += 1
	else:
		if bool(director.call("is_authority")):
			print("[net-client-smoke] FAIL client should not be authority")
			failures += 1
		else:
			print("[net-client-smoke] PASS client is non-authority mirror")
		var enemies: Dictionary = director.get("_enemies")
		if enemies.size() > 0:
			print("[net-client-smoke] PASS enemies mirrored from snapshot (%d)" % enemies.size())
		else:
			print("[net-client-smoke] FAIL no mirrored enemies")
			failures += 1
		var state: Dictionary = director.call("battle_state")
		if float(state.get("time", 0.0)) > 1.0:
			print("[net-client-smoke] PASS battle clock synced (%.1f)" % float(state.get("time", 0.0)))
		else:
			print("[net-client-smoke] FAIL battle clock not synced")
			failures += 1
	print("[net-client-smoke] %s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)


func _test_port() -> int:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] != "--net-smoke-port":
			continue
		var raw_port := String(args[index + 1])
		if raw_port.is_valid_int():
			var parsed_port := int(raw_port)
			if parsed_port >= 1024 and parsed_port <= 65_535:
				return parsed_port
	return TEST_PORT
