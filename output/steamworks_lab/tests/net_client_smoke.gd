extends SceneTree

# 联机 client 端 headless smoke（先启动 net_host_smoke.gd）：
#   godot --headless --path output/steamworks_lab --script res://tests/net_client_smoke.gd

const TEST_PORT: int = 24568
const JOIN_DELAY_SECONDS: float = 0.5
const SYNC_WAIT_SECONDS: float = 9.5


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	root.add_child(main_scene)
	await process_frame
	await create_timer(JOIN_DELAY_SECONDS).timeout
	var session: Node = main_scene.get("_session")
	session.call("join_local", "127.0.0.1", TEST_PORT)
	await create_timer(SYNC_WAIT_SECONDS).timeout

	var failures := 0
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
