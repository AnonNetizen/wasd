extends SceneTree

# 联机 client 端 headless smoke（先启动 net_host_smoke.gd）：
#   godot --headless --path output/steamworks_lab --script res://tests/net_client_smoke.gd

const TEST_PORT: int = 24568
const JOIN_DELAY_SECONDS: float = 0.5
const READY_CHECK_SECONDS: float = 1.0
const SYNC_WAIT_SECONDS: float = 9.5


func _init() -> void:
	call_deferred("_run")


func _wait_seconds(seconds: float) -> void:
	var frame_count := ceili(seconds * 60.0)
	for index in range(frame_count):
		await process_frame


func _run() -> void:
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	root.add_child(main_scene)
	await process_frame
	await _wait_seconds(JOIN_DELAY_SECONDS)
	var session: Node = main_scene.get("_session")
	session.call("join_local", "127.0.0.1", TEST_PORT)
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
