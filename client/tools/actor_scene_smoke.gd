extends Node


const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const ENEMY_BASE_PATH: String = "res://scenes/gameplay/actors/enemy_base.tscn"
const ENEMY_SCRIPT := preload("res://scripts/gameplay/enemy.gd")
const GAMEPLAY_RUN_LOOP_SCENE := preload("res://scenes/gameplay/gameplay_run_loop.tscn")
const PLAYER_BASE_PATH: String = "res://scenes/gameplay/actors/player_base.tscn"
const PLAYER_SCRIPT := preload("res://scripts/gameplay/player.gd")

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var characters: Array[Dictionary] = _dictionary_array(
		DataLoader.load_json(DataLoader.CHARACTERS_PATH).get("characters", [])
	)
	var enemies: Array[Dictionary] = DataLoader.load_csv(DataLoader.ENEMIES_PATH)
	_expect(not characters.is_empty(), "character data should not be empty")
	_expect(enemies.size() == 5, "current enemy data should contain five enemies")

	for character: Dictionary in characters:
		_validate_actor_scene(character, PLAYER_BASE_PATH, PLAYER_SCRIPT, true)
	for enemy: Dictionary in enemies:
		_validate_actor_scene(enemy, ENEMY_BASE_PATH, ENEMY_SCRIPT, false)
		_validate_enemy_configuration(enemy)

	var default_scene_path: String = _character_scene_path(
		characters,
		CHARACTER_IDS.CHARACTER_DEFAULT
	)
	_expect(
		not default_scene_path.is_empty(),
		"default new-run character should resolve to a dedicated scene"
	)
	var restored_scene_path: String = _character_scene_path(
		characters,
		CHARACTER_IDS.CHARACTER_DEFAULT
	)
	_expect(
		restored_scene_path == default_scene_path,
		"saved character id should resolve through the same data binding"
	)
	_validate_enemy_pools(enemies)
	_validate_enemy_pool_registration_rollback(enemies)

	if _failures.is_empty():
		print("[actor-scene-smoke] PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[actor-scene-smoke] %s" % failure)
	get_tree().quit(1)


func _validate_actor_scene(
	actor_data: Dictionary,
	expected_base_path: String,
	expected_script: Script,
	is_player: bool
) -> void:
	var actor_id: String = String(actor_data.get("id", ""))
	var scene_path: String = String(actor_data.get("scene_path", ""))
	var actor_scene: PackedScene = load(scene_path) as PackedScene
	_expect(actor_scene != null, "%s should load a PackedScene" % actor_id)
	if actor_scene == null:
		return
	var base_state: SceneState = actor_scene.get_state().get_base_scene_state()
	_expect(base_state != null, "%s should be an inherited scene" % actor_id)
	if base_state != null:
		_expect(
			base_state.get_path() == expected_base_path,
			"%s should inherit %s" % [actor_id, expected_base_path]
		)
	var actor: Node = actor_scene.instantiate()
	_expect(actor is CharacterBody2D, "%s root should be CharacterBody2D" % actor_id)
	_expect(actor.get_script() == expected_script, "%s should keep the base actor script" % actor_id)
	_expect(actor.get_node_or_null("CollisionShape2D") is CollisionShape2D, "%s should have CollisionShape2D" % actor_id)
	_expect(actor.get_node_or_null("Visual") is Node2D, "%s should have a Visual subtree" % actor_id)
	_expect(actor.scene_file_path == scene_path, "%s instance should retain its dedicated scene path" % actor_id)
	if is_player:
		_expect(actor.get_node_or_null("GameplayCameraController") != null, "%s should have GameplayCameraController" % actor_id)
		_expect(actor.get_node_or_null("WeaponSystem") != null, "%s should have WeaponSystem" % actor_id)
	else:
		_expect(actor.get_node_or_null("StatusEffectComponent") != null, "%s should have StatusEffectComponent" % actor_id)
	actor.free()


func _validate_enemy_configuration(enemy_row: Dictionary) -> void:
	var scene_path: String = String(enemy_row.get("scene_path", ""))
	var enemy_scene: PackedScene = load(scene_path) as PackedScene
	if enemy_scene == null:
		return
	var enemy: CharacterBody2D = enemy_scene.instantiate() as CharacterBody2D
	if enemy == null:
		return
	var target := Node2D.new()
	get_tree().root.add_child(target)
	get_tree().root.add_child(enemy)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	var body: Polygon2D = enemy.get_node_or_null("Visual/Body") as Polygon2D
	var collision: CollisionShape2D = enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var original_color: Color = enemy.call("visual_color")
	var original_polygon: PackedVector2Array = body.polygon.duplicate() if body != null else PackedVector2Array()
	enemy.call("configure", _runtime_enemy_data(enemy_row), target, null)
	var configured_color: Color = enemy.call("visual_color")
	_expect(
		configured_color.is_equal_approx(original_color),
		"%s configure should not override scene-authored color" % enemy_row.get("id", "")
	)
	if body != null:
		_expect(
			body.polygon == original_polygon,
			"%s configure should not replace normalized scene geometry" % enemy_row.get("id", "")
		)
	if collision != null and collision.shape is CircleShape2D:
		_expect(
			is_equal_approx(
				(collision.shape as CircleShape2D).radius,
				String(enemy_row.get("hit_radius", "0")).to_float()
			),
			"%s collision radius should remain data-driven" % enemy_row.get("id", "")
		)
	enemy.free()
	target.free()


func _validate_enemy_pools(enemies: Array[Dictionary]) -> void:
	var acquired: Dictionary = {}
	for enemy_row: Dictionary in enemies:
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		var scene_path: String = String(enemy_row.get("scene_path", ""))
		PoolManager.clear_pool(pool_id)
		_expect(
			PoolManager.register_pool(
				pool_id,
				Callable(self, "_instantiate_scene").bind(scene_path),
				4
			),
			"%s pool should register from its dedicated PackedScene" % pool_id
		)
		PoolManager.prewarm(pool_id, 1)
	for enemy_row: Dictionary in enemies:
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		var expected_path: String = String(enemy_row.get("scene_path", ""))
		var enemy: Node = PoolManager.acquire(pool_id)
		_expect(enemy != null, "%s pool should acquire an enemy" % pool_id)
		if enemy == null:
			continue
		_expect(
			enemy.scene_file_path == expected_path,
			"%s pool should not return another enemy scene" % pool_id
		)
		acquired[pool_id] = enemy.get_instance_id()
		PoolManager.release(enemy)
	for enemy_row: Dictionary in enemies:
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		var expected_path: String = String(enemy_row.get("scene_path", ""))
		var enemy: Node = PoolManager.acquire(pool_id)
		_expect(enemy != null, "%s pool should reacquire an enemy" % pool_id)
		if enemy == null:
			continue
		_expect(
			enemy.get_instance_id() == int(acquired.get(pool_id, 0)),
			"%s pool should reuse its own instance" % pool_id
		)
		_expect(
			enemy.scene_file_path == expected_path,
			"%s reused instance should keep its dedicated scene" % pool_id
		)
		PoolManager.release(enemy)
		PoolManager.clear_pool(pool_id)


func _validate_enemy_pool_registration_rollback(enemies: Array[Dictionary]) -> void:
	if enemies.size() < 2:
		return
	var first_enemy: Dictionary = enemies[0].duplicate(true)
	var duplicate_pool_enemy: Dictionary = enemies[1].duplicate(true)
	var pool_id: String = String(first_enemy.get("pool_id", ""))
	duplicate_pool_enemy["pool_id"] = pool_id
	PoolManager.clear_pool(pool_id)
	var run_loop: Node = GAMEPLAY_RUN_LOOP_SCENE.instantiate()
	run_loop.set("_enemy_rows", {
		String(first_enemy.get("id", "first")): first_enemy,
		String(duplicate_pool_enemy.get("id", "duplicate")): duplicate_pool_enemy,
	})
	_expect(
		bool(run_loop.call("_cache_actor_scene", String(first_enemy.get("scene_path", "")))),
		"rollback fixture should cache the first enemy scene"
	)
	_expect(
		not bool(run_loop.call("_register_enemy_pools")),
		"duplicate enemy pool registration should fail"
	)
	_expect(
		not PoolManager.has_pool(pool_id),
		"failed enemy pool registration should roll back earlier pools"
	)
	run_loop.free()


func _instantiate_scene(scene_path: String) -> Node:
	var actor_scene: PackedScene = load(scene_path) as PackedScene
	return actor_scene.instantiate() if actor_scene != null else null


func _runtime_enemy_data(enemy_row: Dictionary) -> Dictionary:
	var ai_profile_id: String = String(enemy_row.get("ai_profile_id", ""))
	var ai_profile: Dictionary = {}
	var profile_data: Variant = DataLoader.load_json(DataLoader.ENEMY_AI_PROFILES_PATH)
	if profile_data is Dictionary:
		for raw_profile: Variant in (profile_data as Dictionary).get("profiles", []):
			if raw_profile is Dictionary and String((raw_profile as Dictionary).get("id", "")) == ai_profile_id:
				ai_profile = (raw_profile as Dictionary).duplicate(true)
				break
	return {
		"id": String(enemy_row.get("id", "")),
		"pool_id": String(enemy_row.get("pool_id", "")),
		"ai_profile_id": ai_profile_id,
		"ai_profile": ai_profile,
		"max_hp": String(enemy_row.get("max_hp", "1")).to_int(),
		"move_speed": String(enemy_row.get("move_speed", "0")).to_float(),
		"contact_damage": String(enemy_row.get("contact_damage", "0")).to_int(),
		"contact_damage_type": String(enemy_row.get("contact_damage_type", "")),
		"exp_reward": String(enemy_row.get("exp_reward", "0")).to_int(),
		"hit_radius": String(enemy_row.get("hit_radius", "1")).to_float(),
		"separation_radius": String(enemy_row.get("separation_radius", "0")).to_float(),
	}


func _character_scene_path(
	characters: Array[Dictionary],
	character_id: String
) -> String:
	for character: Dictionary in characters:
		if String(character.get("id", "")) == character_id:
			return String(character.get("scene_path", ""))
	return ""


func _dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for raw_item: Variant in raw_value as Array:
		if raw_item is Dictionary:
			result.append((raw_item as Dictionary).duplicate(true))
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
