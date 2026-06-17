# Doc: MinimumViableProduct/docs/代码/mvp_client.md
extends Node2D

const CONFIG_PATH := "res://data/mvp_config.json"
const DEBUG_TOOLS_PATH := "res://scripts/debug_tools.gd"
const DEFAULT_MAX_HP := 3

var config: Dictionary = {}
var ui_config: Dictionary = {}
var max_hp: int = DEFAULT_MAX_HP
var hp: int = DEFAULT_MAX_HP
var elapsed_seconds: float = 0.0
var kill_count: int = 0
var aim_direction_name: String = ""
var game_over: bool = false

@onready var background: Node2D = $Background
@onready var player: Node2D = $Player
@onready var spawner: Node2D = $Spawner
@onready var enemies: Node2D = $Enemies
@onready var status_label: Label = $HUD/StatusLabel
@onready var game_over_panel: ColorRect = $HUD/GameOverPanel
@onready var game_over_label: Label = $HUD/GameOverPanel/GameOverLabel


func _ready() -> void:
	config = _load_config()
	_apply_config()
	player.global_position = get_viewport_rect().size * 0.5
	player.connect("aim_changed", Callable(self, "_on_player_aim_changed"))
	player.connect("damage_taken", Callable(self, "_on_player_damage_taken"))
	spawner.connect("enemy_spawned", Callable(self, "_on_enemy_spawned"))
	status_label.add_theme_color_override("font_color", Color(0.82, 0.95, 1.0))
	status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	status_label.add_theme_constant_override("shadow_offset_x", 2)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.add_theme_font_size_override("font_size", 18)
	game_over_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.76))
	game_over_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	game_over_label.add_theme_constant_override("shadow_offset_x", 3)
	game_over_label.add_theme_constant_override("shadow_offset_y", 3)
	game_over_label.add_theme_font_size_override("font_size", 26)
	_setup_debug_tools()
	aim_direction_name = player.call("get_aim_direction_name")
	_update_hud()


func _process(delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().reload_current_scene()
		return

	elapsed_seconds += delta
	_update_hud()


func _on_player_aim_changed(direction_name: String) -> void:
	aim_direction_name = direction_name
	_update_hud()


func _on_player_damage_taken(amount: int) -> void:
	if game_over:
		return

	hp = max(0, hp - amount)
	if hp <= 0:
		_trigger_game_over()
	else:
		_update_hud()


func _on_enemy_spawned(enemy: Node) -> void:
	if enemy.has_signal("killed"):
		enemy.connect("killed", Callable(self, "_on_enemy_killed"))


func _on_enemy_killed() -> void:
	if game_over:
		return

	kill_count += 1
	_update_hud()


func _trigger_game_over() -> void:
	game_over = true
	player.call("set_active", false)
	spawner.call("set_spawning_enabled", false)
	_clear_live_enemies()
	game_over_panel.visible = true
	game_over_label.text = _get_string("game_over_template", "GAME OVER\nSurvived %.1fs  |  Kills %d\nPress Enter / Space / gamepad A to restart") % [elapsed_seconds, kill_count]
	_update_hud()


func _clear_live_enemies() -> void:
	for enemy in enemies.get_children():
		enemy.queue_free()


func get_debug_stats() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"time": elapsed_seconds,
		"kills": kill_count,
		"enemy_count": enemies.get_child_count(),
		"spawning": spawner.get("spawning_enabled"),
		"game_over": game_over,
	}


func debug_set_hp(new_hp: int) -> void:
	if game_over:
		game_over = false
		game_over_panel.visible = false
		player.call("set_active", true)
		spawner.call("set_spawning_enabled", true)

	hp = clampi(new_hp, 0, max_hp)
	if hp <= 0:
		_trigger_game_over()
	else:
		_update_hud()


func debug_damage_player(amount: int) -> void:
	_on_player_damage_taken(max(0, amount))


func debug_heal_player(amount: int) -> void:
	debug_set_hp(hp + max(0, amount))


func debug_spawn_enemies(count: int) -> int:
	if game_over:
		return 0
	if not spawner.has_method("spawn_enemy_now"):
		return 0

	return int(spawner.call("spawn_enemy_now", max(1, count)))


func debug_clear_enemies(count_as_kills: bool = false) -> int:
	var cleared_count: int = enemies.get_child_count()
	for enemy in enemies.get_children():
		enemy.queue_free()
	if count_as_kills:
		kill_count += cleared_count
	_update_hud()
	return cleared_count


func debug_set_spawning_enabled(enabled: bool) -> void:
	if game_over and enabled:
		return

	spawner.call("set_spawning_enabled", enabled)
	_update_hud()


func _update_hud() -> void:
	var status: String = _get_string("status_failed", "failed") if game_over else _get_string("status_fighting", "fighting")
	status_label.text = _get_string("hud_template", "WASD MVP  |  %s\nHP %d/%d  |  Time %.1fs  |  Kills %d\nAim %s  |  Arrow keys / D-pad / sticks aim, Enter/Space/A restarts") % [status, hp, max_hp, elapsed_seconds, kill_count, aim_direction_name]


func _load_config() -> Dictionary:
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("[MvpMain] %s not found, using script defaults" % CONFIG_PATH)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("[MvpMain] %s must contain a JSON object, using script defaults" % CONFIG_PATH)
		return {}

	var loaded_config: Dictionary = parsed
	return loaded_config


func _apply_config() -> void:
	var player_config: Dictionary = _get_config_section("player")
	ui_config = _get_config_section("ui")
	max_hp = max(1, _get_int(player_config, "max_hp", max_hp))
	hp = max_hp

	if player.has_method("apply_config"):
		player.call("apply_config", player_config, _get_config_section("weapon"), _get_config_section("input"))
	if spawner.has_method("apply_config"):
		spawner.call("apply_config", _get_config_section("spawner"), _get_config_section("enemy"))
	if background.has_method("apply_config"):
		background.call("apply_config", _get_config_section("background"))


func _get_config_section(section_name: String) -> Dictionary:
	var section: Variant = config.get(section_name, {})
	if not (section is Dictionary):
		push_warning("[MvpMain] config.%s must be an object, using defaults" % section_name)
		return {}

	var section_config: Dictionary = section
	return section_config


func _get_int(section: Dictionary, key: String, default_value: int) -> int:
	var value: Variant = section.get(key, default_value)
	if value is int or value is float:
		return int(value)

	push_warning("[MvpMain] config.%s must be a number, using %d" % [key, default_value])
	return default_value


func _get_string(key: String, default_value: String) -> String:
	var value: Variant = ui_config.get(key, default_value)
	if value is String and not String(value).is_empty():
		return value

	push_warning("[MvpMain] config.ui.%s must be a non-empty string, using default" % key)
	return default_value


func _setup_debug_tools() -> void:
	if not _is_debug_tools_enabled():
		return

	var debug_script: Script = load(DEBUG_TOOLS_PATH) as Script
	if debug_script == null:
		push_warning("[MvpMain] debug tools script is missing")
		return

	var debug_tools: CanvasLayer = CanvasLayer.new()
	debug_tools.name = "DebugTools"
	debug_tools.set_script(debug_script)
	add_child(debug_tools)
	if debug_tools.has_method("setup"):
		debug_tools.call("setup", self)


func _is_debug_tools_enabled() -> bool:
	return OS.is_debug_build() or OS.has_feature("dev_tools")
