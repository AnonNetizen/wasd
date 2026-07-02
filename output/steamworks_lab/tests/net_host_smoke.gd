extends SceneTree

# 联机 host 端 headless smoke（与 net_client_smoke.gd 配对使用）：
#   godot --headless --path output/steamworks_lab --script res://tests/net_host_smoke.gd

const TEST_PORT: int = 24568
const HOST_LIFETIME_SECONDS: int = 15


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	root.add_child(main_scene)
	await process_frame
	var session: Node = main_scene.get("_session")
	session.call("host_local", TEST_PORT)
	var max_players := 0
	for second in range(HOST_LIFETIME_SECONDS):
		await create_timer(1.0).timeout
		var players: Dictionary = main_scene.call("player_nodes")
		max_players = maxi(max_players, players.size())

	var failures := 0
	var director: Node = main_scene.get("_director")
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
	print("[net-host-smoke] %s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)
