# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §9.4
class_name GameplayHud
extends CanvasLayer


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const STATS_ROW_SCENE: PackedScene = preload("res://scenes/ui/stats_row.tscn")
const UI_EFFECT_BUNDLE_SCENE: PackedScene = preload("res://scenes/ui/effects/ui_effect_bundle.tscn")
const SKILL_ACTIONS: Array[String] = [
	ACTIONS.SKILL_1,
	ACTIONS.SKILL_2,
	ACTIONS.SKILL_3,
	ACTIONS.SKILL_4,
]
const UPGRADE_FEEDBACK_DURATION: float = 1.35
const UPGRADE_FEEDBACK_FADE_RATIO: float = 0.36
const UPGRADE_FEEDBACK_TEXT_COLOR: Color = Color(1.0, 0.82, 0.28)
const UPGRADE_FEEDBACK_TEXT_SHADOW_COLOR: Color = Color(0.05, 0.04, 0.03, 0.92)
const DIFFICULTY_MARKER_NORMAL_RECT: Rect2 = Rect2(-267.0, 189.0, 254.0, 132.0)
const DIFFICULTY_MARKER_STATS_RECT: Rect2 = Rect2(-718.0, 24.0, 254.0, 132.0)
const STATS_PANEL_ROWS: Array[Dictionary] = [
	{"key": "life", "label_key": "ui_stats_life"},
	{"key": "level", "label_key": "ui_stats_level"},
	{"key": "xp", "label_key": "ui_stats_xp"},
	{"key": "kills", "label_key": "ui_stats_kills"},
	{"key": "run_time", "label_key": "ui_stats_run_time"},
	{"key": "enemy_health_multiplier", "label_key": "ui_stats_enemy_health_multiplier"},
	{"key": "enemy_damage_multiplier", "label_key": "ui_stats_enemy_damage_multiplier"},
	{"key": "damage", "label_key": "ui_stats_damage"},
	{"key": "health_regen", "label_key": "ui_stats_health_regen"},
	{"key": "shield", "label_key": "ui_stats_shield"},
	{"key": "overshield", "label_key": "ui_stats_overshield"},
	{"key": "energy", "label_key": "ui_stats_energy"},
	{"key": "armor", "label_key": "ui_stats_armor"},
	{"key": "ability_strength", "label_key": "ui_stats_ability_strength"},
	{"key": "ability_range", "label_key": "ui_stats_ability_range"},
	{"key": "ability_efficiency", "label_key": "ui_stats_ability_efficiency"},
	{"key": "ability_duration", "label_key": "ui_stats_ability_duration"},
	{"key": "fire_rate", "label_key": "ui_stats_fire_rate"},
	{"key": "move_speed", "label_key": "ui_stats_move_speed"},
	{"key": "bullet_speed", "label_key": "ui_stats_bullet_speed"},
	{"key": "bullet_range", "label_key": "ui_stats_bullet_range"},
	{"key": "bullet_count", "label_key": "ui_stats_bullet_count"},
	{"key": "pierce_count", "label_key": "ui_stats_pierce_count"},
	{"key": "crit_chance", "label_key": "ui_stats_crit_chance"},
	{"key": "crit_mult", "label_key": "ui_stats_crit_mult"},
	{"key": "pickup_range", "label_key": "ui_stats_pickup_range"},
	{"key": "luck", "label_key": "ui_stats_luck"},
	{"key": "skill_resource", "label_key": "ui_stats_skill_resource"},
	{"key": "skill_cooldown", "label_key": "ui_stats_skill_cooldown"},
]

var _life_label: Label = null
var _level_label: Label = null
var _kills_label: Label = null
var _xp_label: Label = null
var _time_label: Label = null
var _message_label: RichTextLabel = null
var _module_minimap: Control = null
var _stats_grid: GridContainer = null
var _stats_label_labels: Dictionary = {}
var _stats_panel: PanelContainer = null
var _stats_title_label: Label = null
var _stats_values: Dictionary = {}
var _stats_value_labels: Dictionary = {}
var _stats_panel_requested_visible: bool = false
var _selection_feedback: UISelectionFeedback = null
var _stats_transition: UIPanelTransition = null
var _ui_effect_bundle: Node = null
var _upgrade_feedback_label: Label = null
var _upgrade_feedback_remaining: float = 0.0
var _last_upgrade_feedback_key: String = "ui_upgrade_applied"
var _last_upgrade_name_key: String = ""
var _last_upgrade_resource_key: String = ""
var _last_upgrade_amount: int = 0
var _interaction_binding: String = ""
var _interaction_prompt_generation: int = 0
var _interaction_prompt_visible: bool = false
var _current_life: float = 0.0
var _max_life: float = 0.0
var _composition_label: Label = null
var _dash_bar: ProgressBar = null
var _dash_label: Label = null
var _defense_label: Label = null
var _difficulty_combat_locked: bool = false
var _difficulty_marker: DifficultyMarker = null
var _difficulty_snapshot: Dictionary = {}
var _energy_bar: ProgressBar = null
var _energy_label: Label = null
var _health_bar: ProgressBar = null
var _kills: int = 0
var _level: int = 1
var _overshield_bar: ProgressBar = null
var _shield_bar: ProgressBar = null
var _skill_slot_labels: Array[Label] = []
var _status_label: Label = null
var _xp: int = 0
var _xp_required: int = 0
var _value_feedback: UIValueFeedback = null


func _ready() -> void:
	_life_label = get_node_or_null("Root/Margin/Layout/LifeLabel") as Label
	_kills_label = get_node_or_null("Root/Margin/Layout/KillsLabel") as Label
	_time_label = get_node_or_null("Root/Margin/Layout/TimeLabel") as Label
	_level_label = get_node_or_null("Root/Margin/Layout/LevelLabel") as Label
	_xp_label = get_node_or_null("Root/Margin/Layout/XpLabel") as Label
	_composition_label = get_node_or_null("Root/Margin/Layout/CompositionLabel") as Label
	_defense_label = get_node_or_null("Root/Margin/Layout/Defense/DefenseLabel") as Label
	_health_bar = get_node_or_null("Root/Margin/Layout/Defense/HealthBar") as ProgressBar
	_shield_bar = get_node_or_null("Root/Margin/Layout/Defense/ShieldBar") as ProgressBar
	_overshield_bar = get_node_or_null("Root/Margin/Layout/Defense/OvershieldBar") as ProgressBar
	_energy_bar = get_node_or_null("Root/Margin/Layout/EnergyBar") as ProgressBar
	_energy_label = get_node_or_null("Root/Margin/Layout/EnergyLabel") as Label
	_message_label = get_node_or_null("Root/MessageLabel") as RichTextLabel
	_status_label = get_node_or_null("Root/StatusLabel") as Label
	_dash_bar = get_node_or_null("Root/CombatTray/Dash/DashBar") as ProgressBar
	_dash_label = get_node_or_null("Root/CombatTray/Dash/DashLabel") as Label
	_skill_slot_labels.clear()
	for slot_index: int in range(4):
		var slot_label: Label = get_node_or_null(
			"Root/CombatTray/Skill%d/SkillLabel" % (slot_index + 1)
		) as Label
		if slot_label != null:
			_skill_slot_labels.append(slot_label)
	_stats_panel = get_node_or_null("Root/StatsPanel") as PanelContainer
	_stats_title_label = get_node_or_null("Root/StatsPanel/Margin/Layout/TitleLabel") as Label
	_stats_grid = get_node_or_null("Root/StatsPanel/Margin/Layout/StatsGrid") as GridContainer
	_difficulty_marker = get_node_or_null("Root/DifficultyMarker") as DifficultyMarker
	_upgrade_feedback_label = get_node_or_null("Root/UpgradeFeedbackLabel") as Label
	if _life_label == null or _kills_label == null or _time_label == null or _level_label == null or _xp_label == null:
		push_error("[GameplayHud] missing required scene nodes")
		return
	if (
		_message_label == null
		or _upgrade_feedback_label == null
		or _stats_panel == null
		or _stats_title_label == null
		or _stats_grid == null
		or _difficulty_marker == null
	):
		push_error("[GameplayHud] missing required scene nodes")
		return
	if (
		_composition_label == null
		or _defense_label == null
		or _health_bar == null
		or _shield_bar == null
		or _overshield_bar == null
		or _energy_bar == null
		or _energy_label == null
		or _dash_bar == null
		or _dash_label == null
		or _skill_slot_labels.size() != 4
		or _status_label == null
	):
		push_error("[GameplayHud] missing composition combat HUD nodes")
		return

	_message_label.hide()
	_stats_panel.hide()
	_build_stats_panel_rows()
	_upgrade_feedback_label.hide()
	_configure_upgrade_feedback_style()
	_bind_ui_effects()
	_bind_module_minimap()
	if _module_minimap == null:
		push_error("[GameplayHud] missing scene-authored ModuleMinimap")
		return
	_difficulty_marker.set_snapshot(_difficulty_snapshot, _difficulty_combat_locked)
	_position_difficulty_marker(false)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	if not InputService.bindings_changed.is_connected(_on_input_prompt_changed):
		InputService.bindings_changed.connect(_on_input_prompt_changed)
	if not InputService.device_family_changed.is_connected(_on_input_device_family_changed):
		InputService.device_family_changed.connect(_on_input_device_family_changed)
	_refresh_static_labels()


func _process(delta: float) -> void:
	_refresh_time_label()
	if _upgrade_feedback_remaining <= 0.0:
		return
	_upgrade_feedback_remaining = maxf(_upgrade_feedback_remaining - GameClock.delta_scaled(delta), 0.0)
	_update_upgrade_feedback_visual()
	if _upgrade_feedback_remaining <= 0.0:
		_upgrade_feedback_label.hide()


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)
	if InputService.bindings_changed.is_connected(_on_input_prompt_changed):
		InputService.bindings_changed.disconnect(_on_input_prompt_changed)
	if InputService.device_family_changed.is_connected(_on_input_device_family_changed):
		InputService.device_family_changed.disconnect(_on_input_device_family_changed)


func set_life(current_life: float, max_life: float) -> void:
	var previous_life: float = _current_life
	var changed: bool = not is_equal_approx(_current_life, current_life)
	_current_life = current_life
	_max_life = max_life
	_life_label.text = "%s: %d/%d" % [tr("ui_hud_life"), int(ceilf(_current_life)), int(ceilf(_max_life))]
	if changed and _value_feedback != null:
		_value_feedback.play_value(_life_label, current_life >= previous_life)
	set_defense(current_life, max_life, _shield_bar.value, _shield_bar.max_value, _overshield_bar.value)


func set_composition(name: String, main_color: Color, accent_color: Color) -> void:
	if _composition_label == null:
		return
	_composition_label.text = name
	_composition_label.add_theme_color_override("font_color", main_color)
	_energy_label.add_theme_color_override("font_color", accent_color)
	for slot_label: Label in _skill_slot_labels:
		slot_label.add_theme_color_override("font_color", accent_color)


func set_defense(
	hp: float,
	max_hp: float,
	shield: float,
	max_shield: float,
	overshield: float
) -> void:
	if _health_bar == null:
		return
	_health_bar.max_value = maxf(max_hp, 1.0)
	_health_bar.value = clampf(hp, 0.0, _health_bar.max_value)
	_shield_bar.max_value = maxf(max_shield, 1.0)
	_shield_bar.value = clampf(shield, 0.0, _shield_bar.max_value)
	var overshield_capacity: float = maxf(maxf(max_shield, overshield), 1.0)
	_overshield_bar.max_value = overshield_capacity
	_overshield_bar.value = clampf(overshield, 0.0, overshield_capacity)
	_defense_label.text = "%d / %d  ·  %d + %d" % [
		int(ceilf(hp)),
		int(ceilf(max_hp)),
		int(ceilf(shield)),
		int(ceilf(overshield)),
	]


func set_energy(current: float, maximum: float) -> void:
	if _energy_bar == null:
		return
	_energy_bar.max_value = maxf(maximum, 1.0)
	_energy_bar.value = clampf(current, 0.0, _energy_bar.max_value)
	_energy_label.text = "%d / %d" % [int(ceilf(current)), int(ceilf(maximum))]


func set_skill_slots(slots: Array, summary: Dictionary = {}) -> void:
	for slot_index: int in range(_skill_slot_labels.size()):
		var label: Label = _skill_slot_labels[slot_index]
		if slot_index >= slots.size() or slots[slot_index] is not Dictionary:
			label.text = "—"
			continue
		var slot: Dictionary = slots[slot_index] as Dictionary
		var name_key: String = String(slot.get("name_key", slot.get("skill_id", "")))
		var display_name: String = tr(name_key) if not name_key.is_empty() else "—"
		var binding: String = InputService.prompt_text(
			SKILL_ACTIONS[slot_index]
		)
		var cooldown_remaining: float = float(slot.get("cooldown_remaining", 0.0))
		var energy_cost: float = float(slot.get("energy_cost", 0.0))
		if cooldown_remaining > 0.0:
			label.text = "%s  %s\n%.1f" % [
				binding,
				display_name,
				cooldown_remaining,
			]
		elif energy_cost > 0.0:
			label.text = "%s  %s\n%d" % [
				binding,
				display_name,
				int(ceilf(energy_cost)),
			]
		else:
			label.text = "%s  %s" % [binding, display_name]
	if summary.has("energy"):
		var energy_summary: Dictionary = summary.get("energy", {}) as Dictionary
		set_energy(
			float(energy_summary.get("current", 0.0)),
			float(energy_summary.get("max", 0.0))
		)


func set_dash(cooldown_remaining: float) -> void:
	if _dash_bar == null:
		return
	var dash_capacity: float = maxf(maxf(_dash_bar.max_value, cooldown_remaining), 1.0)
	_dash_bar.max_value = dash_capacity
	_dash_bar.value = clampf(dash_capacity - cooldown_remaining, 0.0, dash_capacity)
	var binding: String = InputService.prompt_text(ACTIONS.DASH)
	_dash_label.text = (
		"%s  ✓" % binding
		if cooldown_remaining <= 0.0
		else "%s  %.1f" % [binding, cooldown_remaining]
	)


func set_statuses(statuses: Array) -> void:
	if _status_label == null:
		return
	var status_parts: PackedStringArray = []
	for raw_status: Variant in statuses:
		if raw_status is not Dictionary:
			continue
		var status: Dictionary = raw_status as Dictionary
		var name_key: String = String(status.get("name_key", status.get("id", "")))
		var status_name: String = tr(name_key) if not name_key.is_empty() else ""
		var stacks: int = int(status.get("stacks", 1))
		var remaining: float = float(status.get("remaining", 0.0))
		if stacks > 1:
			status_name += " ×%d" % stacks
		if remaining > 0.0:
			status_name += "  %.1f" % remaining
		if not status_name.is_empty():
			status_parts.append(status_name)
	_status_label.text = "   ".join(status_parts)
	_status_label.visible = not status_parts.is_empty()


func set_combat_state(state: Dictionary) -> void:
	var composition: Dictionary = state.get("composition", {}) as Dictionary
	if not composition.is_empty():
		set_composition(
			String(composition.get("name", "")),
			_color_from_variant(composition.get("main_color", Color.WHITE), Color.WHITE),
			_color_from_variant(composition.get("accent_color", Color.WHITE), Color.WHITE)
		)
	var defense: Dictionary = state.get("defense", {}) as Dictionary
	if not defense.is_empty():
		set_defense(
			float(defense.get("hp", 0.0)),
			float(defense.get("max_hp", 0.0)),
			float(defense.get("shield", 0.0)),
			float(defense.get("max_shield", 0.0)),
			float(defense.get("overshield", 0.0))
		)
	var energy: Dictionary = state.get("energy", {}) as Dictionary
	if not energy.is_empty():
		set_energy(float(energy.get("current", 0.0)), float(energy.get("max", 0.0)))
	set_skill_slots(_dictionary_array(state.get("skill_slots", [])), {"energy": energy})
	set_dash(float(state.get("dash_cooldown_remaining", 0.0)))
	set_statuses(_dictionary_array(state.get("statuses", [])))


func set_kills(kills: int) -> void:
	var changed: bool = _kills != kills
	_kills = kills
	_kills_label.text = "%s: %d" % [tr("ui_hud_kills"), _kills]
	if changed and _value_feedback != null:
		_value_feedback.play_value(_kills_label)


func set_level(level: int) -> void:
	var changed: bool = _level != level
	_level = level
	_level_label.text = "%s: %d" % [tr("ui_hud_level"), _level]
	if changed and _value_feedback != null:
		_value_feedback.play_value(_level_label)


func set_difficulty_snapshot(snapshot: Dictionary, combat_locked: bool) -> void:
	_difficulty_snapshot = snapshot.duplicate(true)
	_difficulty_combat_locked = combat_locked
	if _difficulty_marker != null:
		_difficulty_marker.set_snapshot(_difficulty_snapshot, _difficulty_combat_locked)
	_refresh_time_label()
	if _stats_panel != null and _stats_panel.visible:
		_refresh_stats_panel()


func set_xp(xp: int, xp_required: int) -> void:
	var changed: bool = _xp != xp
	_xp = xp
	_xp_required = xp_required
	_xp_label.text = "%s: %d/%d" % [tr("ui_hud_xp"), _xp, _xp_required]
	if changed and _value_feedback != null:
		_value_feedback.play_value(_xp_label)


func show_game_over() -> void:
	_interaction_prompt_generation += 1
	_interaction_prompt_visible = false
	_interaction_binding = ""
	_message_label.hide()


func show_upgrade_feedback(name_key: String) -> void:
	_show_feedback("ui_upgrade_applied", name_key)


func show_gear_mod_drop_feedback(name_key: String) -> void:
	_show_feedback("ui_gear_mod_drop_obtained", name_key)


func show_gear_mod_resource_feedback(resource_key: String, amount: int) -> void:
	_show_resource_feedback("ui_gear_mod_resource_obtained", resource_key, amount)


func show_extraction_feedback() -> void:
	_show_feedback("ui_extraction_available", "")


func set_module_world_state(state: Dictionary) -> void:
	if _module_minimap == null or not is_instance_valid(_module_minimap):
		return
	_module_minimap.call("configure", state)


func show_interaction_prompt(binding: String) -> void:
	if _message_label == null:
		return
	_interaction_prompt_generation += 1
	var generation: int = _interaction_prompt_generation
	_interaction_binding = binding
	_interaction_prompt_visible = true
	_message_label.text = tr("ui_interact_open_cache").format({
		"binding": binding,
	})
	_message_label.show()
	if _selection_feedback != null:
		_selection_feedback.play_selection(_message_label)
	_refresh_interaction_prompt_richtext(generation)


func hide_interaction_prompt() -> void:
	if _message_label == null or not _interaction_prompt_visible:
		return
	_interaction_prompt_generation += 1
	_interaction_prompt_visible = false
	_interaction_binding = ""
	_message_label.hide()


func is_interaction_prompt_visible() -> bool:
	return _message_label != null and _message_label.visible and _interaction_prompt_visible


func is_gear_mod_drop_feedback_visible() -> bool:
	return (
		_upgrade_feedback_label != null
		and _upgrade_feedback_label.visible
		and _last_upgrade_feedback_key == "ui_gear_mod_drop_obtained"
	)


func is_gear_mod_resource_feedback_visible() -> bool:
	return (
		_upgrade_feedback_label != null
		and _upgrade_feedback_label.visible
		and _last_upgrade_feedback_key == "ui_gear_mod_resource_obtained"
	)


func _show_feedback(feedback_key: String, name_key: String) -> void:
	_last_upgrade_feedback_key = feedback_key
	_last_upgrade_name_key = name_key
	_last_upgrade_resource_key = ""
	_last_upgrade_amount = 0
	_start_feedback()


func _show_resource_feedback(feedback_key: String, resource_key: String, amount: int) -> void:
	_last_upgrade_feedback_key = feedback_key
	_last_upgrade_name_key = ""
	_last_upgrade_resource_key = resource_key
	_last_upgrade_amount = maxi(amount, 0)
	_start_feedback()


func _start_feedback() -> void:
	_refresh_upgrade_feedback()
	_upgrade_feedback_remaining = UPGRADE_FEEDBACK_DURATION
	_update_upgrade_feedback_visual()
	_upgrade_feedback_label.show()
	if _value_feedback != null:
		_value_feedback.play_value(_upgrade_feedback_label)


func is_upgrade_feedback_visible() -> bool:
	return _upgrade_feedback_label != null and _upgrade_feedback_label.visible


func is_game_over_message_visible() -> bool:
	return _message_label != null and _message_label.visible


func set_stats_panel_visible(is_visible: bool) -> void:
	if _stats_panel == null:
		return
	if is_visible:
		_position_difficulty_marker(true)
	if _stats_panel_requested_visible == is_visible:
		if is_visible:
			_refresh_stats_panel()
		else:
			_position_difficulty_marker(false)
		return
	_stats_panel_requested_visible = is_visible
	if is_visible:
		_stats_panel.show()
		_refresh_stats_panel()
		if _stats_transition != null:
			_stats_transition.play_enter()
		return
	if _stats_transition != null and _stats_panel.visible:
		_stats_transition.play_exit(_finish_stats_panel_hide)
	else:
		_stats_panel.hide()
		_position_difficulty_marker(false)


func set_detailed_stats(stats: Dictionary) -> void:
	_stats_values = stats.duplicate(true)
	if _stats_panel != null and _stats_panel.visible:
		_refresh_stats_panel()


func is_stats_panel_visible() -> bool:
	return (
		_stats_panel != null
		and _stats_panel_requested_visible
		and _stats_panel.visible
	)


func _refresh_static_labels() -> void:
	set_life(_current_life, _max_life)
	set_kills(_kills)
	set_level(_level)
	set_xp(_xp, _xp_required)
	_refresh_time_label()
	if _interaction_prompt_visible:
		show_interaction_prompt(_interaction_binding)
	if _upgrade_feedback_label.visible:
		_refresh_upgrade_feedback()
	if _difficulty_marker != null:
		_difficulty_marker.refresh_locale()
	_refresh_stats_panel()


func _on_input_prompt_changed() -> void:
	if _interaction_prompt_visible:
		show_interaction_prompt(InputService.prompt_text(ACTIONS.INTERACT))


func _refresh_interaction_prompt_richtext(generation: int) -> void:
	var binding_richtext: String = await InputService.prompt_richtext_async(ACTIONS.INTERACT)
	if (
		generation != _interaction_prompt_generation
		or not _interaction_prompt_visible
		or _message_label == null
	):
		return
	_message_label.text = tr("ui_interact_open_cache").format({
		"binding": binding_richtext,
	})


func _on_input_device_family_changed(_device_family: StringName) -> void:
	_on_input_prompt_changed()


func _refresh_time_label() -> void:
	if _time_label == null:
		return
	var elapsed_seconds: float = float(
		_difficulty_snapshot.get("elapsed", 0.0)
	)
	_time_label.text = "%s: %s" % [tr("ui_hud_time"), _format_elapsed(elapsed_seconds)]


func _refresh_upgrade_feedback() -> void:
	if _upgrade_feedback_label == null:
		return
	_upgrade_feedback_label.text = tr(_last_upgrade_feedback_key).format({
		"name": tr(_last_upgrade_name_key),
		"resource": tr(_last_upgrade_resource_key),
		"amount": _last_upgrade_amount,
	})


func _configure_upgrade_feedback_style() -> void:
	_upgrade_feedback_label.add_theme_color_override("font_color", UPGRADE_FEEDBACK_TEXT_COLOR)
	_upgrade_feedback_label.add_theme_color_override("font_shadow_color", UPGRADE_FEEDBACK_TEXT_SHADOW_COLOR)
	_upgrade_feedback_label.add_theme_constant_override("shadow_offset_x", 2)
	_upgrade_feedback_label.add_theme_constant_override("shadow_offset_y", 2)
	_upgrade_feedback_label.modulate = Color.WHITE


func _bind_ui_effects() -> void:
	_ui_effect_bundle = UI_EFFECT_BUNDLE_SCENE.instantiate()
	if _ui_effect_bundle == null:
		push_error("[GameplayHud] failed to instantiate UI effect bundle")
		return
	_ui_effect_bundle.name = &"UIEffects"
	add_child(_ui_effect_bundle)
	_stats_transition = _ui_effect_bundle.get_node_or_null(
		"PanelTransition"
	) as UIPanelTransition
	if _stats_transition != null:
		_stats_transition.configure(_stats_panel)
	_value_feedback = _ui_effect_bundle.get_node_or_null(
		"ValueFeedback"
	) as UIValueFeedback
	_selection_feedback = _ui_effect_bundle.get_node_or_null(
		"SelectionFeedback"
	) as UISelectionFeedback
	var button_feedback: UIButtonFeedback = _ui_effect_bundle.get_node_or_null(
		"ButtonFeedback"
	) as UIButtonFeedback
	if button_feedback != null:
		button_feedback.bind(self)
	var focus_indicator: UIFocusIndicator = _ui_effect_bundle.get_node_or_null(
		"FocusIndicator"
	) as UIFocusIndicator
	if focus_indicator != null:
		focus_indicator.bind(self)


func _finish_stats_panel_hide() -> void:
	if not _stats_panel_requested_visible and _stats_panel != null:
		_stats_panel.hide()
		_position_difficulty_marker(false)


func _bind_module_minimap() -> void:
	_module_minimap = get_node_or_null("Root/ModuleMinimap") as Control


func _position_difficulty_marker(stats_panel_open: bool) -> void:
	if _difficulty_marker == null:
		return
	var target_rect: Rect2 = (
		DIFFICULTY_MARKER_STATS_RECT
		if stats_panel_open
		else DIFFICULTY_MARKER_NORMAL_RECT
	)
	_difficulty_marker.offset_left = target_rect.position.x
	_difficulty_marker.offset_top = target_rect.position.y
	_difficulty_marker.offset_right = target_rect.position.x + target_rect.size.x
	_difficulty_marker.offset_bottom = target_rect.position.y + target_rect.size.y


func _build_stats_panel_rows() -> void:
	_stats_label_labels.clear()
	_stats_value_labels.clear()
	for child: Node in _stats_grid.get_children():
		child.queue_free()
	for row: Dictionary in STATS_PANEL_ROWS:
		var row_key: String = String(row["key"])
		var row_node: HBoxContainer = STATS_ROW_SCENE.instantiate() as HBoxContainer
		if row_node == null:
			push_error("[GameplayHud] failed to instantiate stats row template")
			continue
		row_node.name = "%sRow" % row_key.to_pascal_case()
		var label: Label = row_node.get_node_or_null("NameLabel") as Label
		var value_label: Label = row_node.get_node_or_null("ValueLabel") as Label
		if label == null or value_label == null:
			row_node.queue_free()
			push_error("[GameplayHud] stats row template is missing labels")
			continue
		label.name = "%sLabel" % row_key.to_pascal_case()
		value_label.name = "%sValueLabel" % row_key.to_pascal_case()
		_stats_grid.add_child(row_node)
		_stats_label_labels[row_key] = label
		_stats_value_labels[row_key] = value_label
	_refresh_stats_panel()


func _refresh_stats_panel() -> void:
	if _stats_title_label == null or _stats_grid == null:
		return
	_stats_title_label.text = tr("ui_stats_panel_title")
	for row: Dictionary in STATS_PANEL_ROWS:
		var row_key: String = String(row["key"])
		var label: Label = _stats_label_labels.get(row_key) as Label
		var value_label: Label = _stats_value_labels.get(row_key) as Label
		if label != null:
			label.text = tr(String(row["label_key"]))
		if value_label != null:
			value_label.text = _stats_value_for_row(row_key)


func _update_upgrade_feedback_visual() -> void:
	if _upgrade_feedback_label == null:
		return
	var remaining_ratio: float = clampf(_upgrade_feedback_remaining / UPGRADE_FEEDBACK_DURATION, 0.0, 1.0)
	var alpha: float = 1.0
	if remaining_ratio < UPGRADE_FEEDBACK_FADE_RATIO:
		alpha = remaining_ratio / UPGRADE_FEEDBACK_FADE_RATIO
	_upgrade_feedback_label.modulate = Color(1.0, 1.0, 1.0, alpha)


func _on_locale_changed(_locale: String) -> void:
	_refresh_static_labels()


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for entry: Variant in value:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


func _color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	if value is String and Color.html_is_valid(String(value)):
		return Color.from_string(String(value), fallback)
	return fallback


func _stats_value_for_row(row_key: String) -> String:
	if not _difficulty_snapshot.is_empty():
		match row_key:
			"run_time":
				return _format_elapsed(float(_difficulty_snapshot.get("elapsed", 0.0)))
			"enemy_health_multiplier":
				return "%.2f×" % float(_difficulty_snapshot.get("health_multiplier", 1.0))
			"enemy_damage_multiplier":
				return "%.2f×" % float(_difficulty_snapshot.get("damage_multiplier", 1.0))
	return String(_stats_values.get(row_key, "-"))


func _format_elapsed(elapsed_seconds: float) -> String:
	var whole_seconds: int = maxi(int(floor(maxf(elapsed_seconds, 0.0))), 0)
	return "%02d:%02d" % [floori(float(whole_seconds) / 60.0), whole_seconds % 60]
