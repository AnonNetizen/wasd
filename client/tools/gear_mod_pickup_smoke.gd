extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const PICKUP_SCENE := preload(
	"res://scenes/gameplay/gear_mod_pickup.tscn"
)
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const WORLD_EVENT_IDS := preload(
	"res://scripts/contracts/world_event_ids.gd"
)
const WORLD_EVENT_KINDS := preload(
	"res://scripts/contracts/world_event_kinds.gd"
)
const WORLD_EVENT_REWARD_TYPES := preload(
	"res://scripts/contracts/world_event_reward_types.gd"
)

const BOOT_FRAMES: int = 10
const CPU_SVG_PATH: String = (
	"res://assets/icons/gear_mod_pickup_cpu.svg"
)
const PICKUP_GROUP: String = "active_gear_mod_pickups"

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var run_loop: Node = null
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		run_loop = _find_node_by_name(
			get_tree().root,
			"GameplayRunLoop"
		)
		if run_loop != null:
			break
	_expect(run_loop != null, "formal gameplay run should be ready")
	if run_loop == null:
		_finish()
		return
	var player: Node2D = _find_node_by_name(
		run_loop,
		"Player"
	) as Node2D
	var hud: Node = _find_node_by_name(run_loop, "GameplayHud")
	_expect(player != null, "player should exist for pickup interaction")
	_expect(hud != null, "HUD should exist for pickup prompt")
	if player == null:
		_finish()
		return

	_expect_asset_contract()
	_expect_scene_contract()
	_expect_preview_contract(run_loop)
	await _expect_interaction_contract(run_loop, player, hud)
	_expect_world_event_spawn_contract(run_loop)
	_expect_snapshot_validation_contract(run_loop)
	_release_active_pickups(run_loop)
	_finish()


func _expect_asset_contract() -> void:
	var svg_text: String = FileAccess.get_file_as_string(CPU_SVG_PATH)
	_expect(not svg_text.is_empty(), "formal CPU SVG should be readable")
	_expect(
		svg_text.count("<path ") == 1
		and svg_text.contains("transform=\"translate(0.000000,800.000000) scale(0.100000,-0.100000)\"")
		and svg_text.contains("z\"/>")
		and not svg_text.to_lower().contains("rdf"),
		"formal CPU SVG should keep one closed transformed path without RDF metadata"
	)


func _expect_scene_contract() -> void:
	var pickup: GearModPickup = PICKUP_SCENE.instantiate() as GearModPickup
	_expect(pickup != null, "formal Gear Mod pickup scene should instantiate")
	if pickup == null:
		return
	add_child(pickup)
	var visual: Node2D = pickup.get_node_or_null("Visual") as Node2D
	var icon: Sprite2D = pickup.get_node_or_null(
		"Visual/Icon"
	) as Sprite2D
	_expect(visual != null and icon != null, "pickup should keep one visual-only child hierarchy")
	_expect(
		_find_collision_object(pickup) == null,
		"pickup should not contain physics collision or auto-pickup areas"
	)
	if icon != null:
		_expect(
			is_equal_approx(icon.scale.x, 0.084)
			and is_equal_approx(icon.scale.y, 0.084),
			"CPU icon scale should target the formal 40 px presentation"
		)
		var material: ShaderMaterial = icon.material as ShaderMaterial
		_expect(material != null, "CPU icon should use its dedicated ShaderMaterial")
		if material != null:
			var shader_path: String = material.shader.resource_path
			var outline_color: Color = material.get_shader_parameter(
				"outline_color"
			) as Color
			_expect(
				shader_path == "res://shaders/gear_mod_pickup_star_window.gdshader"
				and is_equal_approx(float(material.get_shader_parameter("star_scale")), 1.8)
				and is_equal_approx(float(material.get_shader_parameter("outline_texels")), 23.8)
				and outline_color.is_equal_approx(Color("68bcdd")),
				"CPU icon should use the fixed-space star window and 2 px cyan rim contract"
			)
	var root_position: Vector2 = pickup.position
	var topology_count: int = _descendant_count(pickup)
	_expect(
		pickup.configure(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			GearModSystem.pickup_config()
		),
		"pickup should accept a known unlocked Mod configuration"
	)
	await get_tree().process_frame
	_expect(
		pickup.position == root_position
		and visual != null
		and not visual.position.is_zero_approx(),
		"hover animation should move only the visual child"
	)
	pickup.call("_pool_release")
	pickup.call("_pool_reset")
	_expect(
		_descendant_count(pickup) == topology_count,
		"pool reset and release should not grow pickup topology"
	)
	pickup.queue_free()


func _expect_preview_contract(run_loop: Node) -> void:
	var preview: Dictionary = GearModSystem.next_grant_preview(
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		-1
	)
	_expect(
		bool(preview.get("ok", false))
		and int(preview.get("display_rank", 0)) == 1
		and is_equal_approx(
			float(((preview.get("modifiers", []) as Array)[0] as Dictionary).get("value", 0.0)),
			1.1
		),
		"next grant preview should expose the full first-tier +10% effect"
	)
	var overflow_preview: Dictionary = GearModSystem.next_grant_preview(
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		GearModSystem.max_rank(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		)
	)
	_expect(
		int(overflow_preview.get("overflow_gold", 0)) == 75,
		"max-rank preview should expose the 75 gold conversion"
	)
	_expect(
		GearModSystem.pickup_config().get("pool_id", "")
		== POOL_IDS.GEAR_MOD_PICKUP,
		"Gear Mod pickup config should reference the registered pool"
	)


func _expect_interaction_contract(
	run_loop: Node,
	player: Node2D,
	hud: Node
) -> void:
	_release_active_pickups(run_loop)
	var start_ranks: Dictionary = _run_ranks(run_loop)
	var far_position: Vector2 = player.global_position + Vector2(100.0, 0.0)
	var spawn_result: Dictionary = run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		far_position
	) as Dictionary
	_expect(bool(spawn_result.get("ok", false)), "debug setup should spawn a Gear Mod pickup")
	_expect(_active_pickup_count(run_loop) == 1, "spawned pickup should remain active")
	await _push_action_once(ACTIONS.INTERACT)
	_expect(
		_active_pickup_count(run_loop) == 1
		and _run_ranks(run_loop) == start_ranks,
		"out-of-range interact should not consume or grant a pickup"
	)
	var pickup: GearModPickup = _first_active_pickup(run_loop)
	if pickup == null:
		return
	player.global_position = pickup.global_position
	for _index: int in range(3):
		await get_tree().process_frame
	_expect(
		_active_pickup_count(run_loop) == 1
		and _run_ranks(run_loop) == start_ranks,
		"standing on a pickup should never collect it automatically"
	)
	run_loop.call("_update_gear_mod_pickup_prompt", pickup)
	var prompt_text: String = _interaction_prompt_text(hud)
	_expect(
		prompt_text.contains(tr("gear_mod_weapon_damage_test_name"))
		and prompt_text.contains("+10%"),
		"pickup prompt should show name, target tier, and full signed effect: %s"
		% prompt_text
	)
	var first_pickup_result: bool = bool(run_loop.call(
		"_try_interact_gear_mod_pickup",
		pickup
	))
	_expect(
		first_pickup_result
		and _active_pickup_count(run_loop) == 0
		and int(_run_ranks(run_loop).get(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			-1
		)) == 0,
		"interact should collect exactly one normal pickup and grant rank one"
	)

	var origin: Vector2 = player.global_position
	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER,
		origin + Vector2(10.0, 0.0)
	)
	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
		origin + Vector2(20.0, 0.0)
	)
	var nearest_candidate: Dictionary = run_loop.call(
		"_nearest_gear_mod_pickup_candidate"
	) as Dictionary
	var nearest_pickup: GearModPickup = nearest_candidate.get(
		"pickup"
	) as GearModPickup
	if nearest_pickup != null:
		run_loop.call("_try_interact_gear_mod_pickup", nearest_pickup)
	var nearest_ranks: Dictionary = _run_ranks(run_loop)
	_expect(
		_active_pickup_count(run_loop) == 1
		and nearest_ranks.has(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER
		)
		and not nearest_ranks.has(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER
		),
		"one interact press should collect only the nearest of multiple pickups"
	)
	_release_active_pickups(run_loop)

	var max_result: Dictionary = run_loop.call(
		"_grant_run_gear_mod",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		5,
		false
	) as Dictionary
	_expect(
		bool(max_result.get("ok", false))
		and int(max_result.get("rank", -1)) == 5,
		"overflow setup should reach the configured maximum rank"
	)
	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		player.global_position
	)
	for _index: int in range(2):
		await get_tree().process_frame
	var overflow_pickup: GearModPickup = _first_active_pickup(run_loop)
	if overflow_pickup != null:
		run_loop.call("_update_gear_mod_pickup_prompt", overflow_pickup)
	_expect(
		_interaction_prompt_text(hud).contains("75"),
		"max-rank pickup prompt should preview the 75 gold conversion: %s"
		% _interaction_prompt_text(hud)
	)
	var gold_before: int = int(run_loop.call("gold_balance"))
	var overflow_collect_result: bool = false
	if overflow_pickup != null:
		player.global_position = overflow_pickup.global_position
		_expect(
			overflow_pickup.can_player_interact(player),
			"overflow pickup should be within interaction radius before collection: pickup=%s player=%s radius_config=%s"
			% [
				str(overflow_pickup.global_position),
				str(player.global_position),
				str(GearModSystem.pickup_config()),
			]
		)
		overflow_collect_result = bool(run_loop.call(
			"_try_interact_gear_mod_pickup",
			overflow_pickup
		))
	var gold_after: int = int(run_loop.call("gold_balance"))
	_expect(
		overflow_collect_result and gold_after == gold_before + 75,
		"max-rank pickup should convert to 75 run gold after interaction: collected=%s before=%d after=%d"
		% [str(overflow_collect_result), gold_before, gold_after]
	)

	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
		player.global_position
	)
	var original_availability: Dictionary = (
		run_loop.get("_content_availability") as Dictionary
	).duplicate(true)
	var locked_availability: Dictionary = original_availability.duplicate(true)
	var available_mods: Array = (
		locked_availability.get(CONTENT_UNLOCK_TYPES.GEAR_MOD, []) as Array
	).duplicate()
	available_mods.erase(
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER
	)
	locked_availability[CONTENT_UNLOCK_TYPES.GEAR_MOD] = available_mods
	run_loop.set("_content_availability", locked_availability)
	var failing_pickup: GearModPickup = _first_active_pickup(run_loop)
	var failed_collect_result: bool = false
	if failing_pickup != null:
		player.global_position = failing_pickup.global_position
		failed_collect_result = bool(run_loop.call(
			"_try_interact_gear_mod_pickup",
			failing_pickup
		))
	_expect(
		not failed_collect_result
		and failing_pickup != null
		and is_instance_valid(failing_pickup)
		and failing_pickup.is_in_group(PICKUP_GROUP),
		"grant failure should leave the pickup active instead of swallowing it"
	)
	run_loop.set("_content_availability", original_availability)
	_release_active_pickups(run_loop)

	var first_node: Node = PoolManager.acquire(POOL_IDS.GEAR_MOD_PICKUP)
	var first_id: int = first_node.get_instance_id() if first_node != null else 0
	if first_node != null:
		PoolManager.release(first_node)
	var reused_node: Node = PoolManager.acquire(POOL_IDS.GEAR_MOD_PICKUP)
	_expect(
		reused_node != null
		and reused_node.get_instance_id() == first_id,
		"pickup pool should reuse an existing node"
	)
	if reused_node != null:
		PoolManager.release(reused_node)


func _expect_world_event_spawn_contract(run_loop: Node) -> void:
	_release_active_pickups(run_loop)
	var ranks_before: Dictionary = _run_ranks(run_loop)
	var event_cases: Array[Dictionary] = [
		{
			"event_id": WORLD_EVENT_IDS.WORLD_EVENT_DEFENSE,
			"source": WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE,
		},
		{
			"event_id": WORLD_EVENT_IDS.WORLD_EVENT_SURVIVAL,
			"source": WORLD_EVENT_KINDS.WORLD_EVENT_KIND_SURVIVAL,
		},
		{
			"event_id": WORLD_EVENT_IDS.WORLD_EVENT_CAPTURE,
			"source": WORLD_EVENT_KINDS.WORLD_EVENT_KIND_CAPTURE,
		},
		{
			"event_id": WORLD_EVENT_IDS.WORLD_EVENT_GOLD_SHRINE,
			"source": WORLD_EVENT_KINDS.WORLD_EVENT_KIND_GOLD_SHRINE,
		},
	]
	for index: int in range(event_cases.size()):
		var event_case: Dictionary = event_cases[index]
		run_loop.call(
			"_on_world_event_reward_requested",
			"pickup_smoke_%d" % index,
			String(event_case.get("event_id", "")),
			{
				"kind": WORLD_EVENT_REWARD_TYPES.WORLD_EVENT_REWARD_GEAR_MOD,
				"source": String(event_case.get("source", "")),
				"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER,
			}
		)
	_expect(
		_active_pickup_count(run_loop) == event_cases.size()
		and _run_ranks(run_loop) == ranks_before,
		"defense, survival, capture, and gold shrine rewards should spawn pickups without immediate grants"
	)
	var split_positions: Array[Vector2] = run_loop.call(
		"_gear_mod_reward_positions",
		Vector2.ZERO,
		2
	) as Array[Vector2]
	_expect(
		split_positions == [Vector2(-28.0, -36.0), Vector2(28.0, -36.0)],
		"two-drop rewards should use the configured left/right spread without RNG"
	)
	_release_active_pickups(run_loop)


func _expect_snapshot_validation_contract(run_loop: Node) -> void:
	var valid_snapshot: Dictionary = run_loop.call(
		"create_run_snapshot"
	) as Dictionary
	var invalid_mod_snapshot: Dictionary = valid_snapshot.duplicate(true)
	invalid_mod_snapshot["gear_mod_pickups"] = [
		{
			"mod_id": "missing_gear_mod",
			"position": {"x": 0.0, "y": 0.0},
		},
	]
	_expect(
		not bool(run_loop.call(
			"_validate_run_gear_mod_pickup_snapshots",
			invalid_mod_snapshot
		)),
		"unknown pickup snapshots should fail run validation"
	)
	var original_availability: Dictionary = (
		run_loop.get("_content_availability") as Dictionary
	).duplicate(true)
	var locked_availability: Dictionary = original_availability.duplicate(true)
	var available_mods: Array = (
		locked_availability.get(CONTENT_UNLOCK_TYPES.GEAR_MOD, []) as Array
	).duplicate()
	available_mods.erase(GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST)
	locked_availability[CONTENT_UNLOCK_TYPES.GEAR_MOD] = available_mods
	run_loop.set("_content_availability", locked_availability)
	var locked_mod_snapshot: Dictionary = valid_snapshot.duplicate(true)
	locked_mod_snapshot["gear_mod_pickups"] = [
		{
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"position": {"x": 0.0, "y": 0.0},
		},
	]
	_expect(
		not bool(run_loop.call(
			"_validate_run_gear_mod_pickup_snapshots",
			locked_mod_snapshot
		)),
		"locked pickup snapshots should fail run validation"
	)
	run_loop.set("_content_availability", original_availability)
	var invalid_position_snapshot: Dictionary = valid_snapshot.duplicate(true)
	invalid_position_snapshot["gear_mod_pickups"] = [
		{
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"position": {"x": INF, "y": 0.0},
		},
	]
	_expect(
		not bool(run_loop.call(
			"_validate_run_gear_mod_pickup_snapshots",
			invalid_position_snapshot
		)),
		"non-finite pickup positions should fail run validation"
	)
	var extra_field_snapshot: Dictionary = valid_snapshot.duplicate(true)
	extra_field_snapshot["gear_mod_pickups"] = [
		{
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"position": {"x": 0.0, "y": 0.0},
			"unexpected": true,
		},
	]
	_expect(
		not bool(run_loop.call(
			"_validate_run_gear_mod_pickup_snapshots",
			extra_field_snapshot
		)),
		"unknown pickup snapshot fields should fail run validation"
	)


func _push_action_once(action_id: String) -> void:
	InputService.set_playback_active(true)
	InputService.inject_playback_value(action_id, true)
	await get_tree().process_frame
	await get_tree().physics_frame
	InputService.inject_playback_value(action_id, false)
	await get_tree().process_frame
	await get_tree().physics_frame
	InputService.set_playback_active(false)


func _run_ranks(run_loop: Node) -> Dictionary:
	var snapshot_data: Dictionary = run_loop.call(
		"create_run_snapshot"
	) as Dictionary
	return (
		(snapshot_data.get("gear_mods", {}) as Dictionary).get(
			"ranks",
			{}
		) as Dictionary
	).duplicate(true)


func _active_pickup_count(run_loop: Node) -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(PICKUP_GROUP):
		if run_loop.is_ancestor_of(node):
			count += 1
	return count


func _first_active_pickup(run_loop: Node) -> GearModPickup:
	for node: Node in get_tree().get_nodes_in_group(PICKUP_GROUP):
		if node is GearModPickup and run_loop.is_ancestor_of(node):
			return node as GearModPickup
	return null


func _release_active_pickups(run_loop: Node) -> void:
	for node: Node in get_tree().get_nodes_in_group(PICKUP_GROUP):
		if run_loop.is_ancestor_of(node):
			PoolManager.release(node)


func _interaction_prompt_text(hud: Node) -> String:
	var label: RichTextLabel = _find_node_by_name(
		hud,
		"MessageLabel"
	) as RichTextLabel
	return label.text if label != null and label.visible else ""


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _find_collision_object(root: Node) -> CollisionObject2D:
	if root is CollisionObject2D:
		return root as CollisionObject2D
	for child: Node in root.get_children():
		var found: CollisionObject2D = _find_collision_object(child)
		if found != null:
			return found
	return null


func _descendant_count(root: Node) -> int:
	var count: int = 0
	for child: Node in root.get_children():
		count += 1 + _descendant_count(child)
	return count


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[GearModPickupSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[GearModPickupSmoke] passed")
		get_tree().quit(0)
		return
	print(
		"[GearModPickupSmoke] failed; failures=%d"
		% _failures.size()
	)
	get_tree().quit(1)
