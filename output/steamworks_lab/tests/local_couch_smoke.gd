extends SceneTree

# Single-process couch co-op headless smoke:
#   py -3 tools/steamworks_lab_toolchain.py smoke --suite local-couch

const BATTLE_DIRECTOR_SCRIPT := preload("res://scripts/battle_director.gd")
const LAB_SAVE_SCRIPT := preload("res://scripts/lab_save.gd")
const LOCAL_INPUT_ROUTER_SCRIPT := preload("res://scripts/local_input_router.gd")

const SETTINGS_PATH: String = "user://local_couch_smoke_settings.cfg"
const SETTINGS_FILE_NAME: String = "local_couch_smoke_settings.cfg"
const RECORD_SAVE_PATH: String = "user://local_couch_smoke_save.cfg"
const RECORD_SAVE_FILE_NAME: String = "local_couch_smoke_save.cfg"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[local-couch-smoke] PASS %s" % label)
	else:
		_failures += 1
		print("[local-couch-smoke] FAIL %s" % label)


func _run() -> void:
	await _check_input_router()
	await _check_main_scene_integration()
	_release_keyboard_actions()
	if _failures == 0:
		print("[local-couch-smoke] ALL PASS")
	else:
		print("[local-couch-smoke] %d FAILURES" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_input_router() -> void:
	var router := LOCAL_INPUT_ROUTER_SCRIPT.new() as Node
	root.add_child(router)
	await process_frame

	router.call("debug_set_connected_devices", _devices([10, 11, 12, 13]))
	router.call("enable_lobby")
	var slots: Array = router.call("slots")
	_check(slots.size() == 4, "P1 plus the first three controllers fill four slots")
	_check(_slot_for_device(slots, 10) == 2, "first controller maps to P2")
	_check(_slot_for_device(slots, 11) == 3, "second controller maps to P3")
	_check(_slot_for_device(slots, 12) == 4, "third controller maps to P4")
	_check(_slot_for_device(slots, 13) == -1, "fifth local device is rejected when all slots are full")
	_check(int(router.call("ignored_controller_count")) == 1, "router exposes one ignored overflow controller")

	router.call("debug_set_input_frame", 1, {
		"move": Vector2.UP,
		"aim": Vector2.RIGHT,
		"fire_held": true,
	})
	router.call("debug_set_input_frame", 2, {
		"move": Vector2(0.10, 0.0),
		"aim": Vector2.RIGHT,
		"fire_held": true,
	})
	router.call("debug_set_input_frame", 3, {
		"move": Vector2.DOWN,
		"aim": Vector2.DOWN,
		"active_item_pressed": true,
	})
	router.call("debug_set_input_frame", 4, {
		"move": Vector2.LEFT,
		"aim": Vector2.LEFT,
		"merge_held": true,
	})
	var keyboard_frame: Dictionary = router.call("input_frame", 1)
	var p2_frame: Dictionary = router.call("input_frame", 2)
	var p3_frame: Dictionary = router.call("input_frame", 3)
	var p4_frame: Dictionary = router.call("input_frame", 4)
	_check(keyboard_frame.get("move", Vector2.ZERO) == Vector2.UP, "P1 debug frame can simulate keyboard movement")
	_check(bool(keyboard_frame.get("fire_held", false)), "P1 debug frame can simulate mouse fire")
	_check(p2_frame.get("move", Vector2.ONE) == Vector2.ZERO, "controller movement below 0.25 deadzone is ignored")
	_check(bool(p2_frame.get("fire_held", false)), "P2 fire stays in P2 frame")
	_check(bool(p3_frame.get("active_item_pressed", false)), "P3 active item stays in P3 frame")
	_check(bool(p4_frame.get("merge_held", false)), "P4 merge stays in P4 frame")
	_check(
		p2_frame.get("aim", Vector2.ZERO) == Vector2.RIGHT
		and p3_frame.get("aim", Vector2.ZERO) == Vector2.DOWN
		and p4_frame.get("aim", Vector2.ZERO) == Vector2.LEFT,
		"three controller aim vectors do not cross slots"
	)
	router.call("debug_set_input_frame", 2, {"aim": Vector2(0.10, 0.0)})
	p2_frame = router.call("input_frame", 2)
	_check(p2_frame.get("aim", Vector2.ZERO) == Vector2.RIGHT, "centered right stick retains its last valid aim")

	router.call("lock_roster")
	router.call("debug_set_connected_devices", _devices([10, 11, 12, 13]))
	_check(int(router.call("slots").size()) == 4, "locked battle roster ignores an extra controller")
	router.call("debug_set_connected_devices", _devices([11, 12]))
	var missing: Array = router.call("missing_slot_ids")
	_check(missing == [2], "disconnect preserves P2 as the lowest missing slot")
	p2_frame = router.call("input_frame", 2)
	_check(
		p2_frame.get("move", Vector2.ONE) == Vector2.ZERO
		and not bool(p2_frame.get("fire_held", true)),
		"missing controller returns a neutral input frame"
	)
	router.call("debug_set_connected_devices", _devices([11, 12, 99]))
	slots = router.call("slots")
	_check((router.call("missing_slot_ids") as Array).is_empty(), "replacement controller restores all missing slots")
	_check(_slot_for_device(slots, 99) == 2, "replacement controller takes over the lowest missing slot")

	router.call("disable")
	router.queue_free()
	await process_frame


func _check_main_scene_integration() -> void:
	_check(_remove_settings_fixture() == OK, "couch settings fixture starts clean")
	_check(_remove_record_fixture() == OK, "couch record fixture starts clean")
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	_check(main_packed != null, "main scene loads for couch integration")
	if main_packed == null:
		return
	var main_scene := main_packed.instantiate() as Node2D
	main_scene.set("_settings_config_path", SETTINGS_PATH)
	main_scene.set("_save_config_path", RECORD_SAVE_PATH)
	root.add_child(main_scene)
	await process_frame
	main_scene.set_physics_process(false)
	var active_settings := main_scene.get("_settings") as RefCounted
	var active_save := main_scene.get("_save") as RefCounted
	_check(
		active_settings != null and String(active_settings.get("_config_path")) == SETTINGS_PATH,
		"couch smoke loads settings from the pre-ready fixture"
	)
	_check(
		active_save != null and String(active_save.get("_config_path")) == RECORD_SAVE_PATH,
		"couch smoke loads records from the pre-ready fixture"
	)

	_check_p1_input_map()
	var router := main_scene.call("local_input_router") as Node
	_check(router != null, "main scene exposes the local input router")
	if router == null:
		main_scene.queue_free()
		await process_frame
		return

	router.call("debug_set_connected_devices", _devices([]))
	main_scene.call("_on_start_couch_pressed")
	await process_frame
	var start_button := main_scene.get("_start_battle_button") as Button
	_check(int(main_scene.call("couch_player_count")) == 1, "couch lobby auto-joins P1")
	_check(start_button != null and start_button.disabled, "couch lobby requires at least one controller")

	router.call("debug_set_connected_devices", _devices([21, 22, 23]))
	await process_frame
	var players: Dictionary = main_scene.call("player_nodes")
	_check(players.size() == 4, "three controllers auto-join P2 through P4")
	_check(start_button != null and not start_button.disabled, "couch lobby becomes startable with a controller")
	_check(_player_appearance_is_unique(players), "P2 through P4 use distinct preset slime and bullet colors")

	main_scene.call("_on_ready_start_battle_pressed")
	await process_frame
	_check(bool(router.call("is_locked")), "starting battle locks the couch roster")
	_check(main_scene.get("_director") != null, "couch battle starts a local authoritative director")
	main_scene.call("_record_game_over_survival_time", {"time": 88.0})
	_check(
		active_save != null
		and is_zero_approx(float(active_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.SINGLE))),
		"couch game over does not change the single-player record"
	)
	_check(
		active_save != null
		and is_equal_approx(
			float(active_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER)),
			88.0
		),
		"couch game over updates only the multiplayer record"
	)
	router.call("debug_set_connected_devices", _devices([21, 22, 23, 24]))
	_check(int(main_scene.call("couch_player_count")) == 4, "controller added after battle start cannot add a fifth player")
	_check(int(router.call("ignored_controller_count")) == 1, "battle router reports the ignored fifth player device")
	var battle_hud := main_scene.get("_battle_hud") as Control
	_check(
		battle_hud != null and String(battle_hud.call("notice_text")).contains("已忽略"),
		"battle HUD visibly tells players that the extra controller was ignored"
	)

	_check_p1_and_controller_inputs(main_scene, router)
	_check_fire_and_active_item(main_scene, router)
	_check_expression_ownership(main_scene, router)
	_check_buff_sequence_and_hud(main_scene, router)
	_check_merge(main_scene, router)
	_check_disconnect_rebind(main_scene, router)

	main_scene.queue_free()
	await process_frame
	_check(_remove_settings_fixture() == OK, "couch settings fixture cleanup succeeds")
	_check(_remove_record_fixture() == OK, "couch record fixture cleanup succeeds")


func _check_p1_input_map() -> void:
	_check(
		_action_has_key("move_up", KEY_W) and _action_has_key("move_up", KEY_UP),
		"P1 move up accepts both W and Up Arrow"
	)
	_check(
		_action_has_key("move_left", KEY_A) and _action_has_key("move_left", KEY_LEFT),
		"P1 move left accepts both A and Left Arrow"
	)
	_check(_action_has_mouse_button("fire", MOUSE_BUTTON_LEFT), "P1 fire uses the left mouse button")
	_check(_action_has_key("active_item", KEY_Q), "P1 active item uses Q")
	_check(_action_has_key("merge", KEY_E), "P1 merge uses E")
	_check(_action_has_key("expression_wheel", KEY_T), "P1 expression wheel uses T")
	_check(_action_has_key("pause_menu", KEY_ESCAPE), "P1 pause uses Esc")


func _check_p1_and_controller_inputs(main_scene: Node2D, router: Node) -> void:
	Input.action_press("move_right", 1.0)
	Input.action_press("fire", 1.0)
	router.call("set_keyboard_aim_direction", Vector2.RIGHT)
	var p1_frame: Dictionary = router.call("input_frame", 1)
	_check(
		(p1_frame.get("move", Vector2.ZERO) as Vector2).x > 0.9
		and p1_frame.get("aim", Vector2.ZERO) == Vector2.RIGHT
		and bool(p1_frame.get("fire_held", false)),
		"P1 public input frame exposes keyboard movement, mouse aim, and fire"
	)
	router.call("debug_set_input_frame", 2, {"move": Vector2.UP, "aim": Vector2.RIGHT})
	router.call("debug_set_input_frame", 3, {"move": Vector2.DOWN, "aim": Vector2.DOWN})
	router.call("debug_set_input_frame", 4, {"move": Vector2.LEFT, "aim": Vector2.LEFT})
	main_scene.call("_update_couch_inputs")
	Input.action_release("move_right")
	Input.action_release("fire")
	var peer_inputs: Dictionary = main_scene.get("_peer_inputs")
	_check((peer_inputs.get(1, Vector2.ZERO) as Vector2).x > 0.9, "P1 action simulation reaches slot 1")
	_check(peer_inputs.get(2, Vector2.ZERO) == Vector2.UP, "P2 movement reaches only slot 2")
	_check(peer_inputs.get(3, Vector2.ZERO) == Vector2.DOWN, "P3 movement reaches only slot 3")
	_check(peer_inputs.get(4, Vector2.ZERO) == Vector2.LEFT, "P4 movement reaches only slot 4")
	var aims: Dictionary = main_scene.get("_aim_direction_by_player")
	_check(
		aims.get(2, Vector2.ZERO) == Vector2.RIGHT
		and aims.get(3, Vector2.ZERO) == Vector2.DOWN
		and aims.get(4, Vector2.ZERO) == Vector2.LEFT,
		"P2 through P4 retain independent right-stick aim"
	)
	var player_one := (main_scene.call("player_nodes") as Dictionary).get(1) as Node
	var target := Vector2(520.0, 480.0)
	if player_one != null:
		var center: Vector2 = player_one.call("body_center")
		target = center + Vector2(120.0, 0.0)
	Input.warp_mouse(target)
	var p1_aim: Vector2 = main_scene.call("_aim_direction_for_player", 1)
	_check(p1_aim.length() > 0.99, "P1 mouse aim resolves to a normalized firing direction")


func _check_fire_and_active_item(main_scene: Node2D, router: Node) -> void:
	main_scene.call("_clear_bullets")
	router.call("debug_set_input_frame", 2, {"aim": Vector2.RIGHT, "fire_held": true})
	router.call("debug_set_input_frame", 3, {"aim": Vector2.DOWN, "fire_held": true})
	router.call("debug_set_input_frame", 4, {"aim": Vector2.LEFT, "fire_held": false})
	main_scene.call("_update_gameplay", 0.01)
	var owner_counts := _bullet_owner_counts(main_scene)
	_check(int(owner_counts.get(2, 0)) == 1, "P2 held fire creates a P2-owned bullet")
	_check(int(owner_counts.get(3, 0)) == 1, "P3 held fire creates a P3-owned bullet simultaneously")
	_check(int(owner_counts.get(4, 0)) == 0, "P4 does not fire without its own trigger")
	var first_total: int = (main_scene.get("_bullets") as Array).size()
	main_scene.call("_update_gameplay", 0.0)
	_check((main_scene.get("_bullets") as Array).size() == first_total, "per-player fire cooldown blocks an immediate repeat")
	main_scene.call("_update_gameplay", 0.19)
	_check((main_scene.get("_bullets") as Array).size() == first_total + 2, "held fire repeats after each player's cooldown")
	var cooldowns: Dictionary = main_scene.get("_fire_cooldown_by_player")
	_check(cooldowns.has(2) and cooldowns.has(3), "fire cooldown state is stored independently by player id")

	router.call("debug_set_input_frame", 2, {"aim": Vector2.RIGHT})
	router.call("debug_set_input_frame", 3, {"aim": Vector2.DOWN})
	var director := main_scene.get("_director") as Node
	director.call("force_grant_active_item", 4, BATTLE_DIRECTOR_SCRIPT.ACTIVE_CLEAR_PULSE)
	router.call("debug_set_input_frame", 4, {"aim": Vector2.LEFT, "active_item_pressed": true})
	main_scene.call("_update_couch_inputs")
	var held_item: Dictionary = director.call("active_item_for_peer", 4)
	_check(not bool(held_item.get("held", true)), "P4 controller active-item press consumes only P4's item")


func _check_expression_ownership(main_scene: Node2D, router: Node) -> void:
	var wheel := main_scene.get("_expression_wheel") as Control
	Input.warp_mouse(Vector2(460.0, 480.0))
	router.call("debug_set_input_frame", 1, {"expression_held": true})
	main_scene.call("_update_couch_inputs")
	if wheel != null:
		wheel.call("_process", 0.0)
	_check(wheel != null and not bool(wheel.call("is_controller_mode")), "P1 expression wheel stays in mouse mode")
	_check(wheel != null and int(wheel.call("selected_index")) >= 0, "P1 mouse selects an expression sector")
	router.call("debug_set_input_frame", 1, {})
	main_scene.call("_update_couch_inputs")

	router.call("debug_set_input_frame", 4, {"aim": Vector2.RIGHT, "expression_held": true})
	main_scene.call("_update_couch_inputs")
	_check(int(main_scene.get("_expression_owner_id")) == 4, "expression wheel records P4 as its controller owner")
	_check(wheel != null and bool(wheel.call("is_open")), "controller expression wheel opens")
	_check(wheel != null and String(wheel.call("controller_context")).contains("P4"), "expression wheel shows its current player and device context")
	_check(wheel != null and int(wheel.call("selected_index")) >= 0, "right stick selects a controller expression")

	var director := main_scene.get("_director") as Node
	director.call("force_grant_active_item", 2, BATTLE_DIRECTOR_SCRIPT.ACTIVE_CLEAR_PULSE)
	router.call("debug_set_input_frame", 2, {
		"move": Vector2.LEFT,
		"active_item_pressed": true,
		"expression_held": true,
	})
	router.call("debug_set_input_frame", 3, {"move": Vector2.UP, "fire_held": true})
	main_scene.call("_update_couch_inputs")
	var peer_inputs: Dictionary = main_scene.get("_peer_inputs")
	var fire_held: Dictionary = main_scene.get("_fire_held_by_player")
	_check(int(main_scene.get("_expression_owner_id")) == 4, "a second player cannot steal an open expression wheel")
	_check(peer_inputs.get(2, Vector2.ZERO) == Vector2.LEFT, "expression wheel does not block another player's movement")
	_check(bool(fire_held.get(3, false)), "expression wheel does not block another player's fire intent")
	var p2_item: Dictionary = director.call("active_item_for_peer", 2)
	_check(not bool(p2_item.get("held", true)), "expression wheel does not block another player's active item")

	router.call("debug_set_input_frame", 2, {})
	router.call("debug_set_input_frame", 3, {})
	router.call("debug_set_input_frame", 4, {"aim": Vector2.RIGHT})
	main_scene.call("_update_couch_inputs")
	var player_four := (main_scene.call("player_nodes") as Dictionary).get(4) as Node
	var expression_label := player_four.get("_expression_label") as Label if player_four != null else null
	_check(int(main_scene.get("_expression_owner_id")) == 0, "releasing Y closes and releases expression ownership")
	_check(expression_label != null and expression_label.visible and expression_label.text != "", "selected expression appears on P4")


func _check_buff_sequence_and_hud(main_scene: Node2D, router: Node) -> void:
	var players: Dictionary = main_scene.call("player_nodes")
	var player_three := players.get(3) as Node
	for hit_index in range(3):
		player_three.set("invuln_remaining", 0.0)
		player_three.call("apply_damage", 1)
	_check(not bool(player_three.get("alive")), "P3 can be marked dead before couch buff selection")
	main_scene.call("_refresh_battle_hud")
	var hud := main_scene.get("_battle_hud") as Control
	_check(hud != null and int(hud.call("player_card_count")) == 4, "couch HUD renders four compact player cards")
	var cards: Array = hud.call("player_cards_state") if hud != null else []
	_check(not _card_alive(cards, 3), "couch HUD marks the dead P3 card")

	var director := main_scene.get("_director") as Node
	director.call("_enter_buff_choice")
	var buff_panel := main_scene.get("_buff_panel") as Control
	_check(buff_panel != null and bool(buff_panel.call("uses_routed_controller_input")), "couch buff panel routes controller input by player slot")
	_check(buff_panel != null and bool(buff_panel.call("mouse_selection_enabled")), "P1 couch buff choice accepts mouse input")
	var option_buttons: Array = buff_panel.get("_option_buttons") if buff_panel != null else []
	var all_focus_disabled := not option_buttons.is_empty()
	for raw_button in option_buttons:
		var option_button := raw_button as Button
		all_focus_disabled = all_focus_disabled and option_button != null and option_button.focus_mode == Control.FOCUS_NONE
	_check(all_focus_disabled, "non-current gamepads cannot trigger focused buff buttons through ui_accept")
	_check(int(main_scene.get("_couch_buff_player_id")) == 1, "buff choices start with the lowest living slot P1")
	var couch_options: Dictionary = main_scene.get("_couch_buff_options")
	_check(not couch_options.has(3), "dead P3 is skipped when buff options are queued")
	var p2_options: PackedInt32Array = couch_options.get(2, PackedInt32Array())
	main_scene.call("_on_buff_option_chosen", 0)
	_check(int(main_scene.get("_couch_buff_player_id")) == 2, "P2 chooses after P1")
	_check(buff_panel != null and not bool(buff_panel.call("mouse_selection_enabled")), "P1 mouse cannot choose for a controller player")
	var controller_buttons: Array = buff_panel.get("_option_buttons") if buff_panel != null else []
	var controller_buttons_ignore_mouse := not controller_buttons.is_empty()
	for raw_button in controller_buttons:
		var controller_button := raw_button as Button
		controller_buttons_ignore_mouse = (
			controller_buttons_ignore_mouse
			and controller_button != null
			and controller_button.mouse_filter == Control.MOUSE_FILTER_IGNORE
		)
	_check(controller_buttons_ignore_mouse, "controller-owned buff choices ignore mouse button presses")

	router.call("debug_set_input_frame", 2, {"move": Vector2.DOWN, "merge_held": true})
	main_scene.call("_update_couch_inputs")
	_check(int(main_scene.get("_couch_buff_player_id")) == 4, "controller direction plus A confirms P2 and skips dead P3")
	if p2_options.size() > 1:
		var p2_stacks: Dictionary = (director.get("_player_buffs") as Dictionary).get(2, {})
		_check(p2_stacks.has(p2_options[1]), "P2 receives the independently selected second buff option")
	else:
		_check(false, "P2 receives three buff options")

	router.call("debug_set_input_frame", 2, {})
	router.call("debug_set_input_frame", 4, {"merge_held": true})
	main_scene.call("_update_couch_inputs")
	_check(int(main_scene.get("_couch_buff_player_id")) == 0, "P4 completes the sequential couch buff flow")
	_check(int(director.get("phase")) == BATTLE_DIRECTOR_SCRIPT.Phase.BATTLE, "battle resumes only after all living players choose")
	router.call("debug_set_input_frame", 4, {})
	player_three.call("revive_full")


func _check_merge(main_scene: Node2D, router: Node) -> void:
	var players: Dictionary = main_scene.call("player_nodes")
	var player_two := players.get(2) as Node
	var player_three := players.get(3) as Node
	var merge_position: Vector2 = main_scene.call("current_world_rect").get_center()
	player_two.call("warp_to", merge_position)
	player_three.call("warp_to", merge_position + Vector2(20.0, 0.0))
	_check(String(main_scene.call("_local_merge_status_text", 2)).contains("A"), "controller player card uses the A merge prompt")
	router.call("debug_set_input_frame", 2, {"merge_held": true})
	router.call("debug_set_input_frame", 3, {"merge_held": true})
	main_scene.call("_update_couch_inputs")
	main_scene.call("_update_merges_authority", 0.81)
	_check(
		bool(main_scene.call("is_peer_merged", 2)) and bool(main_scene.call("is_peer_merged", 3)),
		"P2 and P3 can hold A together to merge"
	)
	_check((main_scene.get("_active_merges") as Dictionary).size() == 1, "simultaneous merge creates exactly one merged slime")
	main_scene.call("_end_merges_for_peer", 2, false)
	router.call("debug_set_input_frame", 2, {})
	router.call("debug_set_input_frame", 3, {})
	main_scene.call("_update_couch_inputs")


func _check_disconnect_rebind(main_scene: Node2D, router: Node) -> void:
	var players: Dictionary = main_scene.call("player_nodes")
	var player_two := players.get(2) as Node
	player_two.set("hp", 2)
	var hp_before := int(player_two.get("hp"))
	var position_before: Vector2 = player_two.call("body_center")
	var director := main_scene.get("_director") as Node
	var buffs_before: Dictionary = (director.get("_player_buffs") as Dictionary).duplicate(true)
	var clock_before := float(director.get("battle_clock"))

	router.call("debug_set_connected_devices", _devices([22, 23]))
	var pause_panel := main_scene.get("_pause_panel") as Control
	_check((router.call("missing_slot_ids") as Array) == [2], "disconnect keeps P2 assigned but missing")
	_check(bool(main_scene.get("_controller_reconnect_blocked")), "disconnect blocks manual resume until a controller returns")
	_check(bool(main_scene.get("_pause_menu_open")), "disconnect opens the global pause menu")
	_check(pause_panel != null and bool(pause_panel.call("is_reconnect_blocked")), "pause panel shows controller reconnect state")
	main_scene.call("_update_gameplay", 1.0)
	_check(is_equal_approx(float(director.get("battle_clock")), clock_before), "global battle clock stays frozen while a controller is missing")
	_check(
		int(player_two.get("hp")) == hp_before
		and (player_two.call("body_center") as Vector2).distance_to(position_before) < 0.1,
		"disconnected P2 keeps health and position"
	)
	_check((director.get("_player_buffs") as Dictionary) == buffs_before, "disconnected P2 keeps per-player buff state")

	router.call("debug_set_connected_devices", _devices([22, 23, 99]))
	var restored_slot := _slot_by_id(router.call("slots"), 2)
	_check(int(restored_slot.get("device_id", -1)) == 99, "an unoccupied controller rebinds to missing P2")
	_check(not bool(main_scene.get("_controller_reconnect_blocked")), "all restored controllers return to ordinary pause state")
	_check(bool(main_scene.get("_pause_menu_open")), "restoring controllers still requires manual resume")
	_check(pause_panel != null and not bool(pause_panel.call("is_reconnect_blocked")), "resume control unlocks after rebind")
	main_scene.call("_close_pause_menu")
	_check(not bool(main_scene.get("_pause_menu_open")), "player manually resumes after every missing controller is restored")
	router.call("debug_set_input_frame", 2, {"move": Vector2.UP, "aim": Vector2.RIGHT})
	main_scene.call("_update_couch_inputs")
	var peer_inputs: Dictionary = main_scene.get("_peer_inputs")
	_check(peer_inputs.get(2, Vector2.ZERO) == Vector2.UP, "replacement controller drives the preserved P2 slot")


func _devices(device_ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_device_id in device_ids:
		var device_id := int(raw_device_id)
		result.append({
			"device_id": device_id,
			"device_name": "Smoke Pad %d" % device_id,
		})
	return result


func _slot_for_device(slots: Array, device_id: int) -> int:
	for raw_slot in slots:
		if not raw_slot is Dictionary:
			continue
		var slot: Dictionary = raw_slot
		if int(slot.get("device_id", -1)) == device_id:
			return int(slot.get("slot_id", -1))
	return -1


func _slot_by_id(slots: Array, slot_id: int) -> Dictionary:
	for raw_slot in slots:
		if raw_slot is Dictionary and int(raw_slot.get("slot_id", -1)) == slot_id:
			return (raw_slot as Dictionary).duplicate(true)
	return {}


func _action_has_key(action_name: StringName, keycode: Key) -> bool:
	if not InputMap.has_action(action_name):
		return false
	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return true
	return false


func _action_has_mouse_button(action_name: StringName, button_index: MouseButton) -> bool:
	if not InputMap.has_action(action_name):
		return false
	for event in InputMap.action_get_events(action_name):
		var mouse_event := event as InputEventMouseButton
		if mouse_event != null and mouse_event.button_index == button_index:
			return true
	return false


func _player_appearance_is_unique(players: Dictionary) -> bool:
	var slime_palettes: Dictionary = {}
	var bullet_palettes: Dictionary = {}
	for player_id in range(2, 5):
		var player := players.get(player_id) as Node
		if player == null:
			return false
		var appearance: Dictionary = player.call("appearance_state")
		if String(appearance.get("name", "")) != "P%d" % player_id:
			return false
		slime_palettes[int(appearance.get("slime_palette_id", -1))] = true
		bullet_palettes[int(appearance.get("bullet_palette_id", -1))] = true
	return slime_palettes.size() == 3 and bullet_palettes.size() == 3


func _bullet_owner_counts(main_scene: Node) -> Dictionary:
	var result: Dictionary = {}
	var bullets: Array = main_scene.get("_bullets")
	for raw_bullet in bullets:
		var bullet := raw_bullet as Node
		if bullet == null or not is_instance_valid(bullet):
			continue
		var owner_id := int(bullet.get("owner_peer_id"))
		result[owner_id] = int(result.get(owner_id, 0)) + 1
	return result


func _card_alive(cards: Array, slot_id: int) -> bool:
	for raw_card in cards:
		if raw_card is Dictionary and int(raw_card.get("slot", -1)) == slot_id:
			return bool(raw_card.get("alive", true))
	return true


func _release_keyboard_actions() -> void:
	for action_name in [
		"move_up",
		"move_down",
		"move_left",
		"move_right",
		"fire",
		"active_item",
		"merge",
		"expression_wheel",
		"pause_menu",
	]:
		if InputMap.has_action(action_name):
			Input.action_release(action_name)


func _remove_record_fixture() -> Error:
	return _remove_user_fixture(RECORD_SAVE_PATH, RECORD_SAVE_FILE_NAME)


func _remove_settings_fixture() -> Error:
	return _remove_user_fixture(SETTINGS_PATH, SETTINGS_FILE_NAME)


func _remove_user_fixture(path: String, file_name: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		return DirAccess.get_open_error()
	return user_dir.remove(file_name)
