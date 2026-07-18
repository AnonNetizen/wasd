extends SceneTree

# 联机 host 端 headless smoke（与 net_client_smoke.gd 配对使用）：
#   py -3 tools/steamworks_lab_toolchain.py smoke --suite enet

const TEST_PORT: int = 24568
const CLIENT_JOIN_TIMEOUT_SECONDS: float = 15.0
const READY_ROOM_OBSERVE_SECONDS: float = 2.0
const BATTLE_WAIT_SECONDS: int = 10
const SETTINGS_PATH: String = "user://net_host_smoke_settings.cfg"
const SAVE_PATH: String = "user://net_host_smoke_save.cfg"


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
	var session: Node = main_scene.get("_session")
	var test_port := _test_port()
	session.call("host_local", test_port)
	if not bool(session.call("is_host")) or String(session.call("active_transport")) != "local":
		print("[net-host-smoke] FAIL could not listen on port %d" % test_port)
		print("[net-host-smoke] 1 FAILURES")
		quit(1)
		return
	print("[net-host-smoke] READY port=%d" % test_port)
	var max_players := 0
	var join_checks := ceili(CLIENT_JOIN_TIMEOUT_SECONDS * 10.0)
	for _check_index in range(join_checks):
		await _wait_seconds(0.1)
		var ready_players: Dictionary = main_scene.call("player_nodes")
		max_players = maxi(max_players, ready_players.size())
		if max_players >= 2:
			break
	if max_players >= 2:
		await _wait_seconds(READY_ROOM_OBSERVE_SECONDS)

	var failures := 0
	if main_scene.get("_director") == null:
		print("[net-host-smoke] PASS ready room waits before battle launch")
	else:
		print("[net-host-smoke] FAIL battle started before ready launch")
		failures += 1

	var director: Node = main_scene.get("_director")
	main_scene.call("_on_ready_start_battle_pressed")
	for second in range(BATTLE_WAIT_SECONDS):
		await _wait_seconds(1.0)
		var battle_players: Dictionary = main_scene.call("player_nodes")
		max_players = maxi(max_players, battle_players.size())
	director = main_scene.get("_director")
	if director == null:
		print("[net-host-smoke] FAIL director missing")
		failures += 1
	else:
		var state: Dictionary = director.call("battle_state")
		if int(state.get("enemy_count", 0)) <= 0:
			print("[net-host-smoke] FAIL no enemies spawned")
			failures += 1
		else:
			print("[net-host-smoke] PASS enemies active (%d)" % int(state.get("enemy_count", 0)))
	if max_players >= 2:
		print("[net-host-smoke] PASS client player joined (peak %d players)" % max_players)
	else:
		print("[net-host-smoke] FAIL expected 2+ players, peak %d" % max_players)
		failures += 1
	var wire_stats: Dictionary = session.call("snapshot_wire_stats")
	var max_chunk_size := int(wire_stats.get("max_chunk_size", 0))
	if (
		int(wire_stats.get("raw_size", 0)) > 0
		and int(wire_stats.get("compressed_size", 0)) > 0
		and int(wire_stats.get("chunk_count", 0)) > 0
		and max_chunk_size <= 900
	):
		print("[net-host-smoke] PASS snapshot wire chunks stay within 900 bytes (%s)" % str(wire_stats))
	else:
		print("[net-host-smoke] FAIL invalid snapshot wire stats: %s" % str(wire_stats))
		failures += 1
	print("[net-host-smoke] %s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
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
