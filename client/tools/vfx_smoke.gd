extends Node
## Focused runtime coverage for the visual-effect registry, policy, host, and pooling.


const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")

var _failures: Array[String] = []
var _original_quality: String = "high"
var _original_screen_flashes: bool = true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_original_quality = String(
		Settings.get_value(SETTINGS_KEYS.VIDEO_VFX_QUALITY, "high")
	)
	_original_screen_flashes = bool(
		Settings.get_value(SETTINGS_KEYS.ACCESSIBILITY_SCREEN_FLASHES, true)
	)

	_expect(VisualEffects.effect_ids().size() == 19, "catalog should expose 19 effects")
	_expect(
		VisualEffects.profile_ids().size() == 13,
		"catalog should expose 13 presentation profiles"
	)
	_expect(
		not VisualEffects.resolve_binding(
			"presentation_player_default",
			"hit"
		).is_empty(),
		"profile inheritance should preserve the gameplay hit cue"
	)
	_expect(
		not VisualEffects.resolve_binding(
			"presentation_player_default",
			"hurt"
		).is_empty(),
		"profile should resolve its local hurt cue"
	)
	_expect(
		not VisualEffects.resolve_binding(
			"presentation_skill_overdrive",
			"skill_failed"
		).is_empty(),
		"profile inheritance should preserve the skill-failure cue"
	)
	_expect(
		not VisualEffects.resolve_binding(
			"presentation_pickup_default",
			"pickup_attract"
		).is_empty(),
		"pickup attraction should expose a replaceable profile cue"
	)
	var defeat_binding: Dictionary = VisualEffects.resolve_binding(
		"presentation_enemy_default",
		"defeat"
	)
	_expect(
		(defeat_binding.get("effects", []) as Array).size() == 2,
		"enemy defeat should include target animation and detached aftermath"
	)
	_expect(
		not VisualEffects.resolve_binding(
			"presentation_enemy_exploder",
			"enemy_attack_telegraph"
		).is_empty(),
		"exploder profile should resolve its circular attack telegraph"
	)
	_expect(
		not VisualEffects.resolve_binding(
			"presentation_enemy_melee",
			"enemy_attack_telegraph"
		).is_empty(),
		"melee profile should resolve its directional wedge telegraph"
	)
	_expect(
		not VisualEffects.resolve_binding(
			"presentation_enemy_charge",
			"enemy_attack_telegraph"
		).is_empty(),
		"charge profile should resolve its lane telegraph"
	)
	_expect(
		not VisualEffects.resolve_binding(
			"presentation_enemy_exploder",
			"enemy_attack_impact"
		).is_empty(),
		"exploder profile should resolve its detached impact effect"
	)
	_expect_export_exclusions()

	_expect(
		not VisualEffects.current_policy().has("reduced_motion"),
		"runtime policy should not expose retired reduced motion"
	)
	var standard_flash: Dictionary = VisualEffects.resolved_effect(
		"screen_player_damage_flash"
	)
	_expect(
		String(standard_flash.get("id", "")) == "screen_player_damage_flash",
		"screen flash should resolve to the standard effect"
	)
	_expect(
		VisualEffects.allows_effect(
			VisualEffects.resolved_effect("skill_cast_default")
		),
		"standard motion should allow optional spawned effects"
	)
	_expect(
		VisualEffects.allows_effect(
			VisualEffects.resolved_effect("environment_hazard_telegraph")
		),
		"standard motion should preserve gameplay-boundary effects"
	)
	var enemy_telegraph: Dictionary = VisualEffects.resolved_effect(
		"enemy_spawn_telegraph"
	)
	_expect(
		String(enemy_telegraph.get("id", "")) == "enemy_spawn_telegraph"
		and VisualEffects.allows_effect(enemy_telegraph),
		"enemy-spawn boundary should use the standard telegraph"
	)
	var damage_scene: PackedScene = load(
		"res://scenes/gameplay/damage_number.tscn"
	) as PackedScene
	var damage_number: DamageNumber = damage_scene.instantiate() as DamageNumber
	add_child(damage_number)
	var damage_number_position := Vector2(40.0, 40.0)
	damage_number.configure(damage_number_position, 10.0, false, false)
	_expect(
		is_equal_approx(float(damage_number.get("_duration")), 0.52),
		"damage numbers should use the standard duration"
	)
	damage_number.set("_remaining", 0.26)
	damage_number.call("_update_visual")
	_expect(
		not damage_number.global_position.is_equal_approx(damage_number_position),
		"damage numbers should retain their standard vertical drift"
	)
	damage_number.queue_free()
	var weapon_system := WeaponSystem.new()
	add_child(weapon_system)
	var modifier_lifecycle_counts: Array[int] = [0, 0, 0]
	weapon_system.temporary_modifier_started.connect(
		func(_snapshot: Dictionary) -> void:
			modifier_lifecycle_counts[0] += 1
	)
	weapon_system.temporary_modifier_refreshed.connect(
		func(_snapshot: Dictionary) -> void:
			modifier_lifecycle_counts[1] += 1
	)
	weapon_system.temporary_modifier_expired.connect(
		func(_snapshot: Dictionary) -> void:
			modifier_lifecycle_counts[2] += 1
	)
	var temporary_modifiers: Array[Dictionary] = [{
		"stat": "damage",
		"type": "mult",
		"value": 1.1,
	}]
	weapon_system.apply_temporary_modifiers(temporary_modifiers, 0.1)
	weapon_system.apply_temporary_modifiers(temporary_modifiers, 0.1)
	weapon_system.call("_update_temporary_modifiers", 0.11)
	_expect(
		modifier_lifecycle_counts == [1, 1, 1],
		"temporary modifier presentation lifecycle should start, refresh, then end once"
	)
	weapon_system.queue_free()
	Settings.set_value(SETTINGS_KEYS.ACCESSIBILITY_SCREEN_FLASHES, false)
	_expect(
		not VisualEffects.allows_effect(standard_flash),
		"screen-flash policy should suppress tagged screen effects"
	)
	Settings.set_value(SETTINGS_KEYS.ACCESSIBILITY_SCREEN_FLASHES, true)

	var host := VfxHost.new()
	host.name = "VfxHost"
	var ground_layer := Node2D.new()
	ground_layer.name = "GroundVfxLayer"
	host.add_child(ground_layer)
	var world_layer := Node2D.new()
	world_layer.name = "WorldVfxLayer"
	host.add_child(world_layer)
	var screen_layer := CanvasLayer.new()
	screen_layer.name = "ScreenFeedbackLayer"
	host.add_child(screen_layer)
	var screen_root := Control.new()
	screen_root.name = "Root"
	screen_layer.add_child(screen_root)
	add_child(host)
	_expect(host.register_declared_pools(), "host should register every catalog pool")
	_expect(
		PoolManager.has_pool(POOL_IDS.VFX_WEAPON_MUZZLE_FLASH),
		"high-frequency muzzle flash should have its dedicated pool"
	)
	var owner := Node2D.new()
	owner.name = "Owner"
	add_child(owner)
	var anchors := Node2D.new()
	anchors.name = "VfxAnchors"
	owner.add_child(anchors)
	var center := Node2D.new()
	center.name = "Center"
	anchors.add_child(center)

	var attached_request := VfxPlayRequest.from_context({
		"owner": owner,
		"anchor": "center",
		"scale": 1.2,
		"tint": "#ffd35cff",
	})
	var attached_handle: VfxHandle = host.play(
		"skill_cast_default",
		attached_request
	)
	_expect(attached_handle != null, "host should play an attached composite")
	if attached_handle != null:
		_expect(attached_handle.is_active(), "attached handle should start active")
		var attached_instance: Node = attached_handle.instance()
		_expect(
			attached_instance != null and attached_instance.get_parent() == center,
			"attached effect should use the stable center anchor"
		)
		attached_handle.cancel(true)
		_expect(not attached_handle.is_active(), "cancel should close the attached handle")

	var actor_scene: PackedScene = load(
		"res://scenes/gameplay/actors/characters/character_default.tscn"
	) as PackedScene
	var actor: Node = actor_scene.instantiate()
	add_child(actor)
	var target_handle: VfxHandle = host.play(
		"actor_player_hurt_flash",
		VfxPlayRequest.from_context({"owner": actor})
	)
	_expect(
		target_handle != null and target_handle.is_active(),
		"target animation should return a tracked active handle"
	)
	host.cancel_owner(actor)
	_expect(
		target_handle != null and not target_handle.is_active(),
		"cancel_owner should cancel target animations"
	)
	var aftermath_handle: VfxHandle = host.play(
		"actor_enemy_defeat_afterimage",
		VfxPlayRequest.from_context({
			"owner": actor,
			"world_position": actor.global_position,
		})
	)
	var aftermath_instance: Node = (
		aftermath_handle.instance() if aftermath_handle != null else null
	)
	_expect(
		aftermath_instance != null
		and aftermath_instance.get_parent() == world_layer,
		"defeat aftermath should detach into the world layer"
	)

	PoolManager.clear_pool(POOL_IDS.HIT_SPARK)
	var hit_request := VfxPlayRequest.from_context({
		"world_position": Vector2(24.0, -12.0),
	})
	var hit_handle: VfxHandle = host.play("combat_hit_default", hit_request)
	_expect(hit_handle != null, "host should play a pooled hit effect")
	_expect(
		PoolManager.active_count(POOL_IDS.HIT_SPARK) == 1,
		"pooled hit effect should be active after play"
	)
	if hit_handle != null:
		hit_handle.cancel(true)
	_expect(
		PoolManager.active_count(POOL_IDS.HIT_SPARK) == 0,
		"pooled hit effect should return after cancel"
	)
	_expect(
		PoolManager.available_count(POOL_IDS.HIT_SPARK) >= 1,
		"pooled hit effect should remain reusable"
	)

	host.cancel_all()
	PoolManager.clear_pool(POOL_IDS.HIT_SPARK)
	PoolManager.clear_pool(POOL_IDS.DAMAGE_NUMBER)
	PoolManager.clear_pool(POOL_IDS.VFX_WEAPON_MUZZLE_FLASH)
	_restore_settings()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[vfx-smoke] PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[vfx-smoke] %s" % failure)
	get_tree().quit(1)


func _restore_settings() -> void:
	Settings.set_value(SETTINGS_KEYS.VIDEO_VFX_QUALITY, _original_quality)
	Settings.set_value(
		SETTINGS_KEYS.ACCESSIBILITY_SCREEN_FLASHES,
		_original_screen_flashes
	)


func _expect_export_exclusions() -> void:
	var export_config: String = FileAccess.get_file_as_string(
		"res://export_presets.cfg"
	)
	_expect(
		export_config.contains("addons/vfx_library/*"),
		"release export should exclude the VFX Library editor plugin"
	)
	_expect(
		export_config.contains("tools/vfx_resource_baker.gd"),
		"release export should exclude the VFX resource baker"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
