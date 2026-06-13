extends Node2D

const MAX_HP := 3

@onready var player: Node2D = $Player
@onready var spawner: Node2D = $Spawner
@onready var status_label: Label = $HUD/StatusLabel
@onready var game_over_panel: ColorRect = $HUD/GameOverPanel
@onready var game_over_label: Label = $HUD/GameOverPanel/GameOverLabel

var hp: int = MAX_HP
var elapsed_seconds: float = 0.0
var kill_count: int = 0
var aim_direction_name: String = "上"
var game_over: bool = false


func _ready() -> void:
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
	game_over_label.text = "GAME OVER\n生存 %.1fs  |  击杀 %d\n按 Enter / Space / 手柄 A 重开" % [elapsed_seconds, kill_count]
	_update_hud()


func _clear_live_enemies() -> void:
	for enemy in $Enemies.get_children():
		enemy.queue_free()


func _update_hud() -> void:
	var status := "战斗中" if not game_over else "已失败"
	status_label.text = "WASD MVP M4  |  %s\nHP %d/%d  |  Time %.1fs  |  Kills %d\nAim %s  |  方向键 / D-pad / 摇杆瞄准，Enter/Space/A 重开" % [status, hp, MAX_HP, elapsed_seconds, kill_count, aim_direction_name]
