# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159 / #160
class_name DebugTestArenaController
extends Node


const CONTROL_PANEL_SCENE := preload(
	"res://scenes/debug/debug_test_arena_control_panel.tscn"
)
const TARGET_AI: String = "ai"
const TARGET_STATIONARY: String = "stationary"
const ROLLING_DPS_WINDOW: float = 5.0

@export_group("Arena Layout")
@export var arena_size: Vector2 = Vector2(3200.0, 1760.0)
@export var grid_cell_size: Vector2 = Vector2(160.0, 160.0)
@export var stationary_zone_origin: Vector2 = Vector2(-960.0, 0.0)
@export var ai_zone_origin: Vector2 = Vector2(680.0, 0.0)
@export var spawn_spacing: Vector2 = Vector2(100.0, 112.0)
@export_range(1, 10, 1) var spawn_columns: int = 5
@export_group("Training Target")
@export_range(1.0, 10000000.0, 1.0) var stationary_target_max_hp: float = 1000000.0

var _active_target_label: Label = null
var _control_panel: CanvasLayer = null
var _damage_samples: Array[Dictionary] = []
var _enemy_rows: Array[Dictionary] = []
var _free_skills: bool = false
var _god_mode: bool = false
var _hit_count: int = 0
var _hit_count_label: Label = null
var _last_hit: float = 0.0
var _last_hit_label: Label = null
var _player: Node2D = null
var _rolling_dps_label: Label = null
var _run_loop: Node = null
var _skill_system: Node = null
var _spawn_position: Vector2 = Vector2.ZERO
var _total_damage: float = 0.0
var _total_damage_label: Label = null
var _weapon_system: Node = null


func _ready() -> void:
	_last_hit_label = get_node_or_null(
		"StatsHud/Root/Margin/Panel/Margin/Layout/LastHitLabel"
	) as Label
	_hit_count_label = get_node_or_null(
		"StatsHud/Root/Margin/Panel/Margin/Layout/HitCountLabel"
	) as Label
	_total_damage_label = get_node_or_null(
		"StatsHud/Root/Margin/Panel/Margin/Layout/TotalDamageLabel"
	) as Label
	_rolling_dps_label = get_node_or_null(
		"StatsHud/Root/Margin/Panel/Margin/Layout/RollingDpsLabel"
	) as Label
	_active_target_label = get_node_or_null(
		"StatsHud/Root/Margin/Panel/Margin/Layout/ActiveTargetLabel"
	) as Label
	if (
		_last_hit_label == null
		or _hit_count_label == null
		or _total_damage_label == null
		or _rolling_dps_label == null
		or _active_target_label == null
	):
		push_error("[DebugTestArenaController] missing stats HUD nodes")
		return
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_refresh_stats_hud()


func _exit_tree() -> void:
	if Combat.damage_applied.is_connected(_on_damage_applied):
		Combat.damage_applied.disconnect(_on_damage_applied)
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func _process(_delta: float) -> void:
	_prune_damage_samples()
	_refresh_stats_hud()


func configure(
	run_loop: Node,
	player: Node2D,
	skill_system: Node,
	weapon_system: Node,
	enemy_rows: Array[Dictionary]
) -> void:
	_run_loop = run_loop
	_player = player
	_skill_system = skill_system
	_weapon_system = weapon_system
	_enemy_rows = enemy_rows.duplicate(true)
	_spawn_position = Vector2.ZERO
	_god_mode = false
	_free_skills = false
	reset_damage_stats()
	if not Combat.damage_applied.is_connected(_on_damage_applied):
		Combat.damage_applied.connect(_on_damage_applied)


func activate() -> void:
	open_panel()


func map_layout() -> Dictionary:
	return {
		"id": "debug_test_arena",
		"bounds": {
			"width": arena_size.x,
			"height": arena_size.y,
		},
		"grid": {
			"cell_width": grid_cell_size.x,
			"cell_height": grid_cell_size.y,
		},
		"player_start": {
			"x": 0.0,
			"y": 0.0,
		},
		"safe_radius": 320.0,
		"enemy_spawn_margin": 80.0,
		"pcg": {"hazards": []},
		"manual_hazards": [],
	}


func open_panel() -> void:
	if _control_panel != null and is_instance_valid(_control_panel):
		return
	_control_panel = UIManager.push(
		CONTROL_PANEL_SCENE,
		{"source": "debug_test_arena"}
	) as CanvasLayer
	if _control_panel == null:
		return
	_control_panel.call("configure", self, _enemy_rows)


func close_panel() -> void:
	if UIManager.top() == _control_panel:
		UIManager.pop_expected(_control_panel)
	elif _control_panel != null and is_instance_valid(_control_panel):
		_control_panel.queue_free()
	_control_panel = null


func spawn_targets(
	enemy_id: String,
	target_kind: String,
	count: int
) -> Dictionary:
	if _run_loop == null:
		return {"ok": false, "reason": "run_unavailable", "spawned": 0}
	var normalized_kind: String = (
		TARGET_STATIONARY
		if target_kind == TARGET_STATIONARY
		else TARGET_AI
	)
	var spawn_count: int = clampi(count, 1, 50)
	var spawned: int = 0
	for index: int in range(spawn_count):
		var spawn_position: Vector2 = _target_position(
			normalized_kind,
			index,
			spawn_count
		)
		var spawn_result: Dictionary = _run_loop.call(
			"debug_test_arena_spawn_at",
			enemy_id,
			normalized_kind,
			spawn_position,
			stationary_target_max_hp
		) as Dictionary
		if bool(spawn_result.get("ok", false)):
			spawned += 1
	_refresh_stats_hud()
	return {
		"ok": spawned > 0,
		"reason": "" if spawned > 0 else "spawn_failed",
		"spawned": spawned,
	}


func clear_targets(target_kind: String = "") -> Dictionary:
	if _run_loop == null:
		return {"ok": false, "count": 0}
	var result: Dictionary = _run_loop.call(
		"debug_test_arena_clear_targets",
		target_kind
	) as Dictionary
	_refresh_stats_hud()
	return result


func kill_ai() -> Dictionary:
	if _run_loop == null:
		return {"ok": false, "count": 0}
	return _run_loop.call("debug_test_arena_kill_ai") as Dictionary


func reset_stationary_targets() -> Dictionary:
	if _run_loop == null:
		return {"ok": false, "count": 0}
	return _run_loop.call(
		"debug_test_arena_reset_stationary_targets"
	) as Dictionary


func heal_player() -> void:
	if _player != null and _player.has_method("debug_heal"):
		_player.call("debug_heal", float(_player.call("max_life")))


func set_god_mode(enabled: bool) -> void:
	_god_mode = enabled
	if _player != null and _player.has_method("debug_set_invulnerable"):
		_player.call("debug_set_invulnerable", enabled)


func set_free_skills(enabled: bool) -> void:
	_free_skills = enabled
	if (
		_skill_system != null
		and _skill_system.has_method("debug_set_free_casts")
	):
		_skill_system.call("debug_set_free_casts", enabled)


func refresh_skills() -> void:
	if _skill_system != null and _skill_system.has_method("debug_refresh"):
		_skill_system.call("debug_refresh")
	if _weapon_system != null and _weapon_system.has_method("debug_refresh"):
		_weapon_system.call("debug_refresh")
	if _run_loop != null:
		_run_loop.call("debug_test_arena_clear_projectiles")


func teleport_to_spawn() -> void:
	if _player != null:
		_player.global_position = _spawn_position


func reset_arena() -> void:
	clear_targets("")
	if _run_loop != null:
		_run_loop.call("debug_test_arena_clear_projectiles")
	set_god_mode(false)
	set_free_skills(false)
	refresh_skills()
	if _run_loop != null:
		_run_loop.call("debug_test_arena_reset_player")
	reset_damage_stats()


func reset_after_player_death() -> void:
	clear_targets("")
	if _run_loop != null:
		_run_loop.call("debug_test_arena_clear_projectiles")
	set_god_mode(false)
	set_free_skills(false)
	if _run_loop != null:
		_run_loop.call("debug_test_arena_reset_player")
	refresh_skills()
	reset_damage_stats()
	call_deferred("open_panel")


func reset_damage_stats() -> void:
	_last_hit = 0.0
	_hit_count = 0
	_total_damage = 0.0
	_damage_samples.clear()
	_refresh_stats_hud()


func request_return_to_setup() -> void:
	if _run_loop != null:
		_run_loop.call("debug_test_arena_request_setup")


func request_exit() -> void:
	if _run_loop != null:
		_run_loop.call("debug_test_arena_request_exit")


func damage_stats() -> Dictionary:
	_prune_damage_samples()
	var rolling_damage: float = 0.0
	for sample: Dictionary in _damage_samples:
		rolling_damage += float(sample.get("amount", 0.0))
	return {
		"last_hit": _last_hit,
		"hit_count": _hit_count,
		"total_damage": _total_damage,
		"rolling_dps": rolling_damage / ROLLING_DPS_WINDOW,
		"active_targets": _active_target_count(),
	}


func debug_summary() -> Dictionary:
	return {
		"panel_open": (
			_control_panel != null
			and is_instance_valid(_control_panel)
			and UIManager.top() == _control_panel
		),
		"god_mode": _god_mode,
		"free_skills": _free_skills,
		"damage_stats": damage_stats(),
		"stationary_targets": _target_count(TARGET_STATIONARY),
		"ai_targets": _target_count(TARGET_AI),
		"panel": (
			_control_panel.call("debug_summary")
			if _control_panel != null
			and is_instance_valid(_control_panel)
			and _control_panel.has_method("debug_summary")
			else {}
		),
	}


func _on_damage_applied(
	target: Node,
	info: RefCounted,
	result: Dictionary
) -> void:
	if not bool(result.get("applied", false)):
		return
	if not target.has_meta("debug_test_arena_kind"):
		return
	if _player == null or not _player.has_method("combat_team_id"):
		return
	if String(info.get("source_team")) != String(
		_player.call("combat_team_id")
	):
		return
	var amount: float = maxf(float(result.get("amount", 0.0)), 0.0)
	if amount <= 0.0:
		return
	_last_hit = amount
	_hit_count += 1
	_total_damage += amount
	_damage_samples.append({
		"time": GameClock.now(),
		"amount": amount,
	})
	_refresh_stats_hud()


func _prune_damage_samples() -> void:
	var cutoff: float = GameClock.now() - ROLLING_DPS_WINDOW
	while (
		not _damage_samples.is_empty()
		and float(_damage_samples[0].get("time", 0.0)) < cutoff
	):
		_damage_samples.pop_front()


func _refresh_stats_hud() -> void:
	if _last_hit_label == null:
		return
	var central_label: Label = get_node_or_null(
		"../ActiveWorld/ArenaVisuals/CentralLabel"
	) as Label
	var stationary_label: Label = get_node_or_null(
		"../ActiveWorld/ArenaVisuals/StationaryLabel"
	) as Label
	var ai_label: Label = get_node_or_null(
		"../ActiveWorld/ArenaVisuals/AiLabel"
	) as Label
	if central_label != null:
		central_label.text = tr("ui_debug_test_arena_zone_central")
	if stationary_label != null:
		stationary_label.text = tr(
			"ui_debug_test_arena_zone_stationary"
		)
	if ai_label != null:
		ai_label.text = tr("ui_debug_test_arena_zone_ai")
	var stats: Dictionary = damage_stats()
	_last_hit_label.text = tr(
		"ui_debug_test_arena_stats_last_hit"
	) % _format_number(float(stats.get("last_hit", 0.0)))
	_hit_count_label.text = tr(
		"ui_debug_test_arena_stats_hit_count"
	) % int(stats.get("hit_count", 0))
	_total_damage_label.text = tr(
		"ui_debug_test_arena_stats_total"
	) % _format_number(float(stats.get("total_damage", 0.0)))
	_rolling_dps_label.text = tr(
		"ui_debug_test_arena_stats_dps"
	) % _format_number(float(stats.get("rolling_dps", 0.0)))
	_active_target_label.text = tr(
		"ui_debug_test_arena_stats_targets"
	) % int(stats.get("active_targets", 0))


func _active_target_count() -> int:
	return _target_count(TARGET_STATIONARY) + _target_count(TARGET_AI)


func _target_count(target_kind: String) -> int:
	var count: int = 0
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			enemy.has_meta("debug_test_arena_kind")
			and String(enemy.get_meta("debug_test_arena_kind"))
			== target_kind
		):
			count += 1
	return count


func _target_position(
	target_kind: String,
	index: int,
	spawn_count: int
) -> Vector2:
	var origin: Vector2 = (
		stationary_zone_origin
		if target_kind == TARGET_STATIONARY
		else ai_zone_origin
	)
	var column_count: int = mini(
		maxi(spawn_columns, 1),
		maxi(spawn_count, 1)
	)
	var row_count: int = ceili(
		float(maxi(spawn_count, 1)) / float(column_count)
	)
	var column: int = index % column_count
	var row: int = index / column_count
	var items_in_row: int = mini(
		column_count,
		maxi(spawn_count - row * column_count, 1)
	)
	var centered_column: float = (
		float(column) - float(items_in_row - 1) * 0.5
	)
	var centered_row: float = (
		float(row) - float(row_count - 1) * 0.5
	)
	return origin + Vector2(
		centered_column * spawn_spacing.x,
		centered_row * spawn_spacing.y
	)


func _format_number(value: float) -> String:
	return "%.1f" % value


func _on_locale_changed(_locale: String) -> void:
	_refresh_stats_hud()
