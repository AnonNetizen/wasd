# Doc: docs/代码/visual_effects.md
@tool
extends Control
## Central VFX Library browser, preview stage, validator, and safe creation workflow.

const VFX_CATALOG_STORE := preload("res://addons/vfx_library/vfx_catalog_store.gd")
const VFX_PREVIEW_STAGE := preload("res://addons/vfx_library/vfx_preview_stage.gd")
const VFX_TEMPLATE_FACTORY := preload("res://addons/vfx_library/vfx_template_factory.gd")
const EFFECT_DOMAINS := [
	"ui",
	"actor",
	"combat",
	"skill",
	"status",
	"pickup",
	"environment",
	"screen",
]
const EFFECT_SPACES := ["attached", "world", "ground", "screen", "ui"]
const EFFECT_LIFECYCLES := ["one_shot", "loop", "state"]
const QUALITY_OPTIONS := ["low", "medium", "high"]
const INSTANCE_COUNTS := [1, 8, 32, 64]
const PREVIEW_SCALES := [0.25, 0.5, 1.0]
const SPEED_OPTIONS := [0.25, 0.5, 1.0]
const TECHNIQUE_FILTERS := [
	"animation_player",
	"animation_tree",
	"tween",
	"curve",
	"flipbook",
	"gpu_particles",
	"cpu_particles",
	"shader",
	"geometry",
	"cross_system",
]
const TEMPLATE_NAMES := [
	"OneShot",
	"AttachedLoop",
	"GroundTelegraph",
	"UITransition",
	"ScreenOverlay",
	"GeometryComposite",
	"Particle",
	"Flipbook",
	"Shader",
	"AnimationTreeStateful",
]
const EFFECT_PROPERTY_NAMES := ["effect_id", "vfx_effect_id"]
const PROFILE_PROPERTY_NAMES := ["profile_id", "presentation_profile_id"]

var editor_interface: EditorInterface
var undo_redo: EditorUndoRedoManager

var _store: RefCounted
var _template_factory: RefCounted
var _preview_stage: SubViewportContainer
var _mode_option: OptionButton
var _search_edit: LineEdit
var _domain_option: OptionButton
var _technique_option: OptionButton
var _space_option: OptionButton
var _lifecycle_option: OptionButton
var _entry_list: ItemList
var _details: RichTextLabel
var _results: RichTextLabel
var _copy_button: Button
var _variant_button: Button
var _apply_button: Button
var _pause_button: Button
var _timeline: HSlider

var _create_dialog: ConfirmationDialog
var _create_id_edit: LineEdit
var _create_template_option: OptionButton
var _create_domain_option: OptionButton
var _create_space_option: OptionButton
var _create_lifecycle_option: OptionButton
var _create_mode := "new"

var _picker_dialog: ConfirmationDialog
var _picker_search: LineEdit
var _picker_list: ItemList
var _picker_kind := "effect"
var _picker_callback: Callable
var _preview_quality := "high"
var _preview_reduced_motion := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_store = VFX_CATALOG_STORE.new() as RefCounted
	_template_factory = VFX_TEMPLATE_FACTORY.new() as RefCounted
	_build_ui()
	call_deferred("refresh_library")


func refresh_library() -> void:
	if _store == null:
		return
	var result: Dictionary = _store.call("reload") as Dictionary
	_refresh_filters()
	_refresh_entry_list()
	if bool(result.get("ok", false)):
		_report_info(
			"Loaded %d effects and %d presentation profiles." % [
				int(result.get("effects", 0)),
				int(result.get("profiles", 0)),
			]
		)
	else:
		_report_result("Reload", result)


func open_picker(kind: String, current_id: String, callback: Callable) -> void:
	_picker_kind = "profile" if kind == "profile" else "effect"
	_picker_callback = callback
	_picker_search.text = ""
	_refresh_picker_items(current_id)
	if editor_interface != null:
		editor_interface.set_main_screen_editor("VFX Library")
	call_deferred("_show_picker")


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_build_toolbar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	split.add_child(_build_browser())
	split.add_child(_build_preview_panel())
	add_child(root)

	_build_create_dialog()
	_build_picker_dialog()


func _build_toolbar() -> Control:
	var toolbar := HBoxContainer.new()
	toolbar.add_child(_make_button("Reload", refresh_library))
	toolbar.add_child(_make_button("Validate", _on_validate_pressed))
	toolbar.add_child(VSeparator.new())
	toolbar.add_child(_make_button("New Effect…", _on_new_pressed))
	_variant_button = _make_button("Create Variant…", _on_variant_pressed)
	toolbar.add_child(_variant_button)
	toolbar.add_child(VSeparator.new())
	_copy_button = _make_button("Copy ID", _on_copy_id_pressed)
	toolbar.add_child(_copy_button)
	_apply_button = _make_button("Apply to Selected", _on_apply_to_selected_pressed)
	toolbar.add_child(_apply_button)
	return toolbar


func _build_browser() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(330.0, 0.0)
	var title := Label.new()
	title.text = "Catalog"
	title.add_theme_font_size_override("font_size", 18)
	panel.add_child(title)

	_mode_option = _make_option(["Effects", "Profiles"], ["effect", "profile"])
	_mode_option.item_selected.connect(_on_filter_changed)
	panel.add_child(_mode_option)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search ID, name, or tag"
	_search_edit.text_changed.connect(_on_search_changed)
	panel.add_child(_search_edit)

	var filters := GridContainer.new()
	filters.columns = 2
	filters.add_child(_make_label("Domain"))
	_domain_option = _make_option(["All"], [""])
	_domain_option.item_selected.connect(_on_filter_changed)
	filters.add_child(_domain_option)
	filters.add_child(_make_label("Technique"))
	_technique_option = _make_option(["All"], [""])
	_technique_option.item_selected.connect(_on_filter_changed)
	filters.add_child(_technique_option)
	filters.add_child(_make_label("Space"))
	_space_option = _make_option(["All"], [""])
	_space_option.item_selected.connect(_on_filter_changed)
	filters.add_child(_space_option)
	filters.add_child(_make_label("Lifecycle"))
	_lifecycle_option = _make_option(["All"], [""])
	_lifecycle_option.item_selected.connect(_on_filter_changed)
	filters.add_child(_lifecycle_option)
	panel.add_child(filters)

	_entry_list = ItemList.new()
	_entry_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entry_list.select_mode = ItemList.SELECT_SINGLE
	_entry_list.item_selected.connect(_on_entry_selected)
	_entry_list.item_activated.connect(_on_entry_activated)
	panel.add_child(_entry_list)
	return panel


func _build_preview_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_stage = VFX_PREVIEW_STAGE.new() as SubViewportContainer
	panel.add_child(_preview_stage)

	var playback_row := HBoxContainer.new()
	playback_row.add_child(_make_button("Replay", _on_replay_pressed))
	_pause_button = _make_button("Pause", _on_pause_pressed)
	playback_row.add_child(_pause_button)
	playback_row.add_child(_make_label("Speed"))
	var speed_option := _make_numeric_option(SPEED_OPTIONS, "×")
	speed_option.select(2)
	speed_option.item_selected.connect(_on_speed_changed.bind(speed_option))
	playback_row.add_child(speed_option)
	playback_row.add_child(_make_label("Scale"))
	var scale_option := _make_numeric_option(PREVIEW_SCALES, "×")
	scale_option.select(2)
	scale_option.item_selected.connect(_on_scale_changed.bind(scale_option))
	playback_row.add_child(scale_option)
	playback_row.add_child(_make_label("Instances"))
	var count_option := OptionButton.new()
	for instance_count: int in INSTANCE_COUNTS:
		count_option.add_item(str(instance_count))
		count_option.set_item_metadata(count_option.item_count - 1, instance_count)
	count_option.item_selected.connect(_on_instance_count_changed.bind(count_option))
	playback_row.add_child(count_option)
	panel.add_child(playback_row)

	var policy_row := HBoxContainer.new()
	policy_row.add_child(_make_label("Background"))
	var background_option := _make_option(
		["Dark", "Combat", "Light"],
		["dark", "mid", "light"]
	)
	background_option.item_selected.connect(
		_on_background_changed.bind(background_option)
	)
	policy_row.add_child(background_option)
	policy_row.add_child(_make_label("Target"))
	var target_option := _make_option(
		[
			"Dummy",
			"Player",
			"Chaser",
			"Swarm",
			"Stalker",
			"Bulwark",
			"Spitter",
			"UI Container",
		],
		[
			"dummy",
			"player",
			"enemy_chaser",
			"enemy_swarm",
			"enemy_stalker",
			"enemy_bulwark",
			"enemy_spitter",
			"ui_container",
		]
	)
	target_option.item_selected.connect(_on_target_changed.bind(target_option))
	policy_row.add_child(target_option)
	policy_row.add_child(_make_label("Quality"))
	var quality_option := _make_option(
		["Low", "Medium", "High"],
		QUALITY_OPTIONS
	)
	quality_option.select(2)
	quality_option.item_selected.connect(_on_quality_changed.bind(quality_option))
	policy_row.add_child(quality_option)
	var reduced_check := CheckBox.new()
	reduced_check.text = "Reduced Motion"
	reduced_check.toggled.connect(_on_reduced_motion_toggled)
	policy_row.add_child(reduced_check)
	panel.add_child(policy_row)

	var timeline_row := HBoxContainer.new()
	timeline_row.add_child(_make_button("CHARGE", _on_phase_pressed.bind("charge")))
	timeline_row.add_child(_make_button("CONTACT", _on_phase_pressed.bind("contact")))
	timeline_row.add_child(_make_button("AFTERMATH", _on_phase_pressed.bind("aftermath")))
	_timeline = HSlider.new()
	_timeline.min_value = 0.0
	_timeline.max_value = 1.0
	_timeline.step = 0.01
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.value_changed.connect(_on_timeline_changed)
	timeline_row.add_child(_timeline)
	panel.add_child(timeline_row)

	var lower_split := HSplitContainer.new()
	lower_split.custom_minimum_size = Vector2(0.0, 150.0)
	_details = RichTextLabel.new()
	_details.fit_content = false
	_details.scroll_active = true
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower_split.add_child(_details)
	_results = RichTextLabel.new()
	_results.fit_content = false
	_results.scroll_active = true
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower_split.add_child(_results)
	panel.add_child(lower_split)
	return panel


func _build_create_dialog() -> void:
	_create_dialog = ConfirmationDialog.new()
	_create_dialog.title = "New VFX Effect"
	_create_dialog.min_size = Vector2i(520, 330)
	_create_dialog.confirmed.connect(_on_create_confirmed)
	var form := GridContainer.new()
	form.columns = 2
	form.add_child(_make_label("Stable ID"))
	_create_id_edit = LineEdit.new()
	_create_id_edit.placeholder_text = "combat_my_effect"
	form.add_child(_create_id_edit)
	form.add_child(_make_label("Template"))
	_create_template_option = _make_option(
		TEMPLATE_NAMES,
		TEMPLATE_NAMES
	)
	form.add_child(_create_template_option)
	form.add_child(_make_label("Domain"))
	_create_domain_option = _make_option(EFFECT_DOMAINS, EFFECT_DOMAINS)
	form.add_child(_create_domain_option)
	form.add_child(_make_label("Space"))
	_create_space_option = _make_option(EFFECT_SPACES, EFFECT_SPACES)
	form.add_child(_create_space_option)
	form.add_child(_make_label("Lifecycle"))
	_create_lifecycle_option = _make_option(EFFECT_LIFECYCLES, EFFECT_LIFECYCLES)
	form.add_child(_create_lifecycle_option)
	var note := Label.new()
	note.text = (
		"The wizard generates formal PackedScenes, built-in Godot nodes, and catalog "
		+ "entries only. It never creates arbitrary _draw() code or editor-only dependencies."
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_make_label(""))
	form.add_child(note)
	_create_dialog.add_child(form)
	add_child(_create_dialog)


func _build_picker_dialog() -> void:
	_picker_dialog = ConfirmationDialog.new()
	_picker_dialog.title = "Choose from VFX Library"
	_picker_dialog.min_size = Vector2i(560, 520)
	_picker_dialog.confirmed.connect(_on_picker_confirmed)
	var content := VBoxContainer.new()
	_picker_search = LineEdit.new()
	_picker_search.placeholder_text = "Search ID or name"
	_picker_search.text_changed.connect(_on_picker_search_changed)
	content.add_child(_picker_search)
	_picker_list = ItemList.new()
	_picker_list.custom_minimum_size = Vector2(520.0, 420.0)
	_picker_list.item_activated.connect(_on_picker_item_activated)
	content.add_child(_picker_list)
	_picker_dialog.add_child(content)
	add_child(_picker_dialog)


func _refresh_filters() -> void:
	var selected_domain: String = _selected_option_string(_domain_option)
	var selected_technique: String = _selected_option_string(_technique_option)
	var selected_space: String = _selected_option_string(_space_option)
	var selected_lifecycle: String = _selected_option_string(_lifecycle_option)
	_replace_option_items(_domain_option, ["All"] + EFFECT_DOMAINS, [""] + EFFECT_DOMAINS)
	_replace_option_items(
		_technique_option,
		["All"] + TECHNIQUE_FILTERS,
		[""] + TECHNIQUE_FILTERS
	)
	_replace_option_items(_space_option, ["All"] + EFFECT_SPACES, [""] + EFFECT_SPACES)
	_replace_option_items(
		_lifecycle_option,
		["All"] + EFFECT_LIFECYCLES,
		[""] + EFFECT_LIFECYCLES
	)
	_select_option_by_metadata(_domain_option, selected_domain)
	_select_option_by_metadata(_technique_option, selected_technique)
	_select_option_by_metadata(_space_option, selected_space)
	_select_option_by_metadata(_lifecycle_option, selected_lifecycle)


func _refresh_entry_list(preferred_id: String = "") -> void:
	if _entry_list == null:
		return
	var previous_id: String = preferred_id
	if previous_id.is_empty():
		previous_id = _selected_entry_id()
	_entry_list.clear()
	var mode: String = _selected_option_string(_mode_option)
	var entries: Array[Dictionary] = _store_entries(mode)
	var filtered: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if _matches_filters(entry, mode):
			filtered.append(entry)
	filtered.sort_custom(_sort_entry_by_id)
	for entry: Dictionary in filtered:
		var entry_id: String = String(entry.get("id", ""))
		var editor_name: String = String(entry.get("editor_name", entry_id))
		var label := "%s  —  %s" % [entry_id, editor_name]
		_entry_list.add_item(label)
		var item_index: int = _entry_list.item_count - 1
		_entry_list.set_item_metadata(item_index, {"kind": mode, "id": entry_id})
		_entry_list.set_item_tooltip(item_index, _entry_tooltip(entry, mode))
		if entry_id == previous_id:
			_entry_list.select(item_index)
	if not _entry_list.get_selected_items().is_empty():
		_on_entry_selected(_entry_list.get_selected_items()[0])
	elif _entry_list.item_count > 0:
		_entry_list.select(0)
		_on_entry_selected(0)
	else:
		_clear_selection_view()


func _matches_filters(entry: Dictionary, mode: String) -> bool:
	var search_text: String = _search_edit.text.strip_edges().to_lower()
	if not search_text.is_empty():
		var haystack := "%s %s %s" % [
			String(entry.get("id", "")).to_lower(),
			String(entry.get("editor_name", "")).to_lower(),
			" ".join(_string_array(entry.get("tags", []))).to_lower(),
		]
		if not haystack.contains(search_text):
			return false
	if mode == "profile":
		return true
	var domain: String = _selected_option_string(_domain_option)
	var technique: String = _selected_option_string(_technique_option)
	var space: String = _selected_option_string(_space_option)
	var lifecycle: String = _selected_option_string(_lifecycle_option)
	if not domain.is_empty() and String(entry.get("domain", "")) != domain:
		return false
	if not space.is_empty() and String(entry.get("space", "")) != space:
		return false
	if not lifecycle.is_empty() and String(entry.get("lifecycle", "")) != lifecycle:
		return false
	if not technique.is_empty() and not _string_array(entry.get("tags", [])).has(technique):
		return false
	return true


func _on_entry_selected(index: int) -> void:
	if index < 0 or index >= _entry_list.item_count:
		return
	var metadata: Dictionary = _entry_list.get_item_metadata(index) as Dictionary
	var kind: String = String(metadata.get("kind", "effect"))
	var entry_id: String = String(metadata.get("id", ""))
	var entry: Dictionary = (
		_store.call("effect_by_id", entry_id) as Dictionary
		if kind == "effect"
		else _store.call("profile_by_id", entry_id) as Dictionary
	)
	_show_details(entry, kind)
	_copy_button.disabled = entry_id.is_empty()
	_variant_button.disabled = kind != "effect" or entry.is_empty()
	_apply_button.disabled = entry_id.is_empty()
	if kind == "effect":
		_preview_effect(entry)
	else:
		_preview_profile(entry)


func _on_entry_activated(_index: int) -> void:
	_on_replay_pressed()


func _preview_profile(profile: Dictionary) -> void:
	var bindings_value: Variant = profile.get("bindings", profile.get("cues", {}))
	if not bindings_value is Dictionary:
		_preview_stage.call("clear_preview")
		return
	var bindings: Dictionary = bindings_value as Dictionary
	for cue: Variant in bindings.keys():
		var effect_id: String = _binding_effect_id(bindings.get(cue))
		var effect: Dictionary = _store.call("effect_by_id", effect_id) as Dictionary
		if not effect.is_empty():
			_preview_effect(effect)
			return
	_preview_stage.call("clear_preview")


func _preview_effect(base_entry: Dictionary) -> void:
	var resolved_entry: Dictionary = _resolve_quality_variant(base_entry)
	if _preview_reduced_motion:
		var reduced_value: Variant = resolved_entry.get("reduced_motion", {})
		var reduced: Dictionary = (
			reduced_value as Dictionary if reduced_value is Dictionary else {}
		)
		var mode: String = String(reduced.get("mode", "same"))
		if mode == "suppress_optional":
			_preview_stage.call("clear_preview")
			_report_info(
				"Reduced-motion preview suppresses optional effect %s." % base_entry.get("id", "")
			)
			return
		if mode == "variant":
			var variant_id: String = String(reduced.get("effect_id", ""))
			var variant: Dictionary = _store.call("effect_by_id", variant_id) as Dictionary
			if not variant.is_empty():
				resolved_entry = variant
	_report_preview(_preview_stage.call("preview", resolved_entry) as Dictionary)


func _resolve_quality_variant(base_entry: Dictionary) -> Dictionary:
	var variants_value: Variant = base_entry.get("quality_variants", {})
	if not variants_value is Dictionary:
		return base_entry
	var variant_id: String = String(
		(variants_value as Dictionary).get(_preview_quality, "")
	)
	if variant_id.is_empty():
		return base_entry
	var variant: Dictionary = _store.call("effect_by_id", variant_id) as Dictionary
	return base_entry if variant.is_empty() else variant


func _show_details(entry: Dictionary, kind: String) -> void:
	_details.clear()
	if entry.is_empty():
		return
	_details.append_text("%s\n\n" % String(entry.get("id", "")))
	if kind == "effect":
		_details.append_text(
			"Domain: %s\nKind: %s\nSpace: %s\nLifecycle: %s\nDuration: %.3fs\n" % [
				entry.get("domain", ""),
				entry.get("kind", ""),
				entry.get("space", ""),
				entry.get("lifecycle", ""),
				float(entry.get("duration", 0.0)),
			]
		)
		_details.append_text("Tags: %s\n" % ", ".join(_string_array(entry.get("tags", []))))
		_details.append_text("Resource: %s\n" % entry.get("resource_path", ""))
	else:
		_details.append_text(
			"Parent: %s\nBindings: %d\n" % [
				entry.get("parent", entry.get("parent_id", "—")),
				_profile_binding_count(entry),
			]
		)
	_details.append_text("\n%s" % JSON.stringify(entry, "  ", false, true))


func _on_validate_pressed() -> void:
	var result: Dictionary = _store.call("validate_all") as Dictionary
	_report_result("Validate", result)


func _on_new_pressed() -> void:
	_create_mode = "new"
	_create_dialog.title = "New VFX Effect"
	_create_id_edit.text = ""
	_create_template_option.disabled = false
	_create_domain_option.disabled = false
	_create_space_option.disabled = false
	_create_lifecycle_option.disabled = false
	_create_dialog.popup_centered()
	_create_id_edit.grab_focus()


func _on_variant_pressed() -> void:
	var source_id: String = _selected_entry_id()
	if source_id.is_empty() or _selected_option_string(_mode_option) != "effect":
		return
	_create_mode = "variant"
	_create_dialog.title = "Create VFX Variant"
	_create_id_edit.text = "%s_variant" % source_id
	_create_template_option.disabled = true
	_create_domain_option.disabled = true
	_create_space_option.disabled = true
	_create_lifecycle_option.disabled = true
	_create_dialog.popup_centered()
	_create_id_edit.select_all()
	_create_id_edit.grab_focus()


func _on_create_confirmed() -> void:
	var effect_id: String = _create_id_edit.text.strip_edges()
	if not _valid_id(effect_id):
		_report_error("Create failed: ID must match ^[a-z][a-z0-9_]*$.")
		return
	if not (_store.call("effect_by_id", effect_id) as Dictionary).is_empty():
		_report_error("Create failed: effect ID already exists: %s" % effect_id)
		return
	var scene_result: Dictionary
	var entry: Dictionary
	if _create_mode == "variant":
		var source: Dictionary = _store.call(
			"effect_by_id",
			_selected_entry_id()
		) as Dictionary
		if source.is_empty():
			_report_error("Create failed: source effect no longer exists.")
			return
		scene_result = _template_factory.call(
			"duplicate_scene",
			String(source.get("resource_path", "")),
			effect_id
		) as Dictionary
		if bool(scene_result.get("ok", false)):
			entry = _store.call(
				"duplicate_effect_entry",
				source,
				effect_id,
				String(scene_result.get("resource_path", ""))
			) as Dictionary
	else:
		var template_name: String = _selected_option_string(_create_template_option)
		scene_result = _template_factory.call(
			"create_scene",
			effect_id,
			template_name
		) as Dictionary
		if bool(scene_result.get("ok", false)):
			entry = _new_effect_entry(effect_id, template_name, scene_result)
	if not bool(scene_result.get("ok", false)):
		_report_result("Create Scene", scene_result)
		return
	var append_result: Dictionary = _store.call("append_effect", entry) as Dictionary
	if not bool(append_result.get("ok", false)):
		_template_factory.call(
			"remove_new_scene",
			String(scene_result.get("resource_path", ""))
		)
		_report_result("Register Catalog Entry", append_result)
		return
	if editor_interface != null:
		editor_interface.get_resource_filesystem().scan()
	refresh_library()
	_refresh_entry_list(effect_id)
	_report_info("Created and registered effect: %s" % effect_id)


func _new_effect_entry(
	effect_id: String,
	template_name: String,
	scene_result: Dictionary
) -> Dictionary:
	var domain: String = _selected_option_string(_create_domain_option)
	var space: String = _selected_option_string(_create_space_option)
	var lifecycle: String = _selected_option_string(_create_lifecycle_option)
	var kind := "screen_overlay" if template_name == "ScreenOverlay" else "spawned_scene"
	var tags: Array[String] = _template_tags(template_name)
	return {
		"id": effect_id,
		"editor_name": effect_id,
		"domain": domain,
		"kind": kind,
		"resource_path": String(scene_result.get("resource_path", "")),
		"space": space,
		"lifecycle": lifecycle,
		"duration": float(scene_result.get("duration", 0.36)),
		"high_frequency": false,
		"quality_variants": {},
		"reduced_motion": {"mode": "same"},
		"tags": tags,
		"preview": {
			"background": "dark",
			"checkpoint": "contact",
			"scale": 1.0,
		},
	}


func _template_tags(template_name: String) -> Array[String]:
	match template_name:
		"AnimationTreeStateful":
			return ["animation_player", "animation_tree"]
		"GeometryComposite":
			return ["animation_player", "geometry", "gpu_particles", "shader"]
		"GroundTelegraph":
			return ["animation_player", "geometry", "gpu_particles"]
		"Particle":
			return ["animation_player", "gpu_particles"]
		"Flipbook":
			return ["animation_player", "flipbook"]
		"Shader":
			return ["animation_player", "shader"]
		_:
			return ["animation_player"]


func _on_copy_id_pressed() -> void:
	var entry_id: String = _selected_entry_id()
	if entry_id.is_empty():
		return
	DisplayServer.clipboard_set(entry_id)
	_report_info("Copied ID: %s" % entry_id)


func _on_apply_to_selected_pressed() -> void:
	var entry_id: String = _selected_entry_id()
	if entry_id.is_empty() or editor_interface == null:
		return
	var edited_object: Object = editor_interface.get_inspector().get_edited_object()
	if edited_object == null:
		_report_error("Apply failed: the Inspector has no edited object.")
		return
	var mode: String = _selected_option_string(_mode_option)
	var property_names: Array = (
		EFFECT_PROPERTY_NAMES if mode == "effect" else PROFILE_PROPERTY_NAMES
	)
	var property_name: String = _first_property(edited_object, property_names)
	if property_name.is_empty():
		_report_error("Apply failed: selected object has no writable %s ID property." % mode)
		return
	var previous_value: Variant = edited_object.get(property_name)
	if undo_redo != null:
		undo_redo.create_action("Apply VFX Library Reference")
		undo_redo.add_do_property(edited_object, property_name, entry_id)
		undo_redo.add_undo_property(edited_object, property_name, previous_value)
		undo_redo.commit_action()
	else:
		edited_object.set(property_name, entry_id)
	if edited_object is Resource:
		(edited_object as Resource).emit_changed()
	_report_info("Applied %s to the Inspector selection." % entry_id)


func _on_replay_pressed() -> void:
	_report_preview(_preview_stage.call("replay") as Dictionary)


func _on_pause_pressed() -> void:
	var paused: bool = _pause_button.text == "Pause"
	_pause_button.text = "Resume" if paused else "Pause"
	_preview_stage.call("set_paused", paused)


func _on_speed_changed(_index: int, option: OptionButton) -> void:
	_preview_stage.call("set_speed", float(option.get_item_metadata(option.selected)))


func _on_scale_changed(_index: int, option: OptionButton) -> void:
	_preview_stage.call(
		"set_preview_scale",
		float(option.get_item_metadata(option.selected))
	)


func _on_instance_count_changed(_index: int, option: OptionButton) -> void:
	_report_preview(
		_preview_stage.call(
			"set_instance_count",
			int(option.get_item_metadata(option.selected))
		) as Dictionary
	)


func _on_background_changed(_index: int, option: OptionButton) -> void:
	_preview_stage.call(
		"set_background",
		String(option.get_item_metadata(option.selected))
	)


func _on_target_changed(_index: int, option: OptionButton) -> void:
	_report_preview(
		_preview_stage.call(
			"set_preview_target",
			String(option.get_item_metadata(option.selected))
		) as Dictionary
	)


func _on_quality_changed(_index: int, option: OptionButton) -> void:
	_preview_quality = String(option.get_item_metadata(option.selected))
	_preview_stage.call("set_quality", _preview_quality)
	_repreview_selection()


func _on_reduced_motion_toggled(enabled: bool) -> void:
	_preview_reduced_motion = enabled
	_preview_stage.call("set_reduced_motion", enabled)
	_repreview_selection()


func _repreview_selection() -> void:
	var selected_items: PackedInt32Array = _entry_list.get_selected_items()
	if not selected_items.is_empty():
		_on_entry_selected(selected_items[0])


func _on_phase_pressed(phase: String) -> void:
	_preview_stage.call("seek_phase", phase)
	match phase:
		"charge":
			_timeline.set_value_no_signal(0.15)
		"contact":
			_timeline.set_value_no_signal(0.5)
		"aftermath":
			_timeline.set_value_no_signal(0.85)


func _on_timeline_changed(value: float) -> void:
	_preview_stage.call("seek_ratio", value)


func _on_filter_changed(_index: int) -> void:
	var is_effect: bool = _selected_option_string(_mode_option) == "effect"
	_domain_option.disabled = not is_effect
	_technique_option.disabled = not is_effect
	_space_option.disabled = not is_effect
	_lifecycle_option.disabled = not is_effect
	_refresh_entry_list()


func _on_search_changed(_value: String) -> void:
	_refresh_entry_list()


func _show_picker() -> void:
	_picker_dialog.popup_centered()
	_picker_search.grab_focus()


func _refresh_picker_items(preferred_id: String = "") -> void:
	_picker_list.clear()
	var search_text: String = _picker_search.text.strip_edges().to_lower()
	var entries: Array[Dictionary] = _store_entries(_picker_kind)
	var sorted_entries: Array[Dictionary] = []
	sorted_entries.assign(entries)
	sorted_entries.sort_custom(_sort_entry_by_id)
	for entry: Dictionary in sorted_entries:
		var entry_id: String = String(entry.get("id", ""))
		var editor_name: String = String(entry.get("editor_name", entry_id))
		if not search_text.is_empty():
			var haystack := ("%s %s" % [entry_id, editor_name]).to_lower()
			if not haystack.contains(search_text):
				continue
		_picker_list.add_item("%s  —  %s" % [entry_id, editor_name])
		var index: int = _picker_list.item_count - 1
		_picker_list.set_item_metadata(index, entry_id)
		if entry_id == preferred_id:
			_picker_list.select(index)
	if _picker_list.get_selected_items().is_empty() and _picker_list.item_count > 0:
		_picker_list.select(0)


func _on_picker_search_changed(_value: String) -> void:
	_refresh_picker_items()


func _on_picker_item_activated(_index: int) -> void:
	_picker_dialog.get_ok_button().emit_signal("pressed")


func _on_picker_confirmed() -> void:
	var selected_items: PackedInt32Array = _picker_list.get_selected_items()
	if selected_items.is_empty() or not _picker_callback.is_valid():
		return
	var selected_id: String = String(
		_picker_list.get_item_metadata(selected_items[0])
	)
	_picker_callback.call(selected_id)


func _selected_entry_id() -> String:
	if _entry_list == null:
		return ""
	var selected_items: PackedInt32Array = _entry_list.get_selected_items()
	if selected_items.is_empty():
		return ""
	var metadata_value: Variant = _entry_list.get_item_metadata(selected_items[0])
	if not metadata_value is Dictionary:
		return ""
	return String((metadata_value as Dictionary).get("id", ""))


func _clear_selection_view() -> void:
	_details.clear()
	_preview_stage.call("clear_preview")
	_copy_button.disabled = true
	_variant_button.disabled = true
	_apply_button.disabled = true


func _report_preview(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_report_result("Preview", result)


func _report_result(action: String, result: Dictionary) -> void:
	_results.clear()
	var ok: bool = bool(result.get("ok", false))
	_results.append_text("%s %s.\n" % [action, "succeeded" if ok else "failed"])
	for error_message: String in _messages(result, "errors"):
		_results.append_text("• %s\n" % error_message)
	for warning_message: String in _messages(result, "warnings"):
		_results.append_text("△ %s\n" % warning_message)
	if not ok:
		for message: String in _messages(result, "errors"):
			printerr("[vfx-library] %s" % message)


func _report_info(message: String) -> void:
	_results.clear()
	_results.append_text(message)
	print("[vfx-library] %s" % message)


func _report_error(message: String) -> void:
	_results.clear()
	_results.append_text(message)
	printerr("[vfx-library] %s" % message)


func _entry_tooltip(entry: Dictionary, kind: String) -> String:
	if kind == "profile":
		return "%s\n%d cue bindings" % [
			entry.get("id", ""),
			_profile_binding_count(entry),
		]
	return "%s\n%s · %s · %s\n%s" % [
		entry.get("id", ""),
		entry.get("domain", ""),
		entry.get("space", ""),
		entry.get("lifecycle", ""),
		entry.get("resource_path", ""),
	]


func _profile_binding_count(entry: Dictionary) -> int:
	var value: Variant = entry.get("bindings", entry.get("cues", {}))
	return (value as Dictionary).size() if value is Dictionary else 0


func _binding_effect_id(value: Variant) -> String:
	if value is String:
		return String(value)
	if value is Dictionary:
		var binding: Dictionary = value as Dictionary
		return String(binding.get("effect_id", binding.get("effect", "")))
	return ""


func _first_property(object: Object, candidates: Array) -> String:
	for property: Dictionary in object.get_property_list():
		var property_name: String = String(property.get("name", ""))
		if candidates.has(property_name):
			return property_name
	return ""


func _store_entries(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var value: Variant = (
		_store.get("effects") if kind == "effect" else _store.get("profiles")
	)
	if not value is Array:
		return result
	for entry_value: Variant in value as Array:
		if entry_value is Dictionary:
			result.append(entry_value as Dictionary)
	return result


func _messages(result: Dictionary, key: String) -> PackedStringArray:
	var value: Variant = result.get(key, PackedStringArray())
	if value is PackedStringArray:
		return value as PackedStringArray
	var messages := PackedStringArray()
	if value is Array:
		for message: Variant in value as Array:
			messages.append(String(message))
	return messages


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		result.append(String(item))
	return result


func _make_option(labels: Array, values: Array) -> OptionButton:
	var option := OptionButton.new()
	for index: int in range(labels.size()):
		option.add_item(String(labels[index]))
		var metadata: Variant = values[index] if index < values.size() else labels[index]
		option.set_item_metadata(index, metadata)
	return option


func _make_numeric_option(values: Array, suffix: String) -> OptionButton:
	var option := OptionButton.new()
	for value: Variant in values:
		option.add_item("%s%s" % [value, suffix])
		option.set_item_metadata(option.item_count - 1, value)
	return option


func _make_button(label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.pressed.connect(callback)
	return button


func _make_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	return label


func _replace_option_items(option: OptionButton, labels: Array, values: Array) -> void:
	option.clear()
	for index: int in range(labels.size()):
		option.add_item(String(labels[index]))
		option.set_item_metadata(index, values[index])


func _select_option_by_metadata(option: OptionButton, value: Variant) -> void:
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return
	option.select(0)


func _selected_option_string(option: OptionButton) -> String:
	if option == null or option.item_count == 0 or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func _sort_entry_by_id(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("id", "")) < String(right.get("id", ""))


func _valid_id(value: String) -> bool:
	var expression := RegEx.new()
	return (
		not value.is_empty()
		and expression.compile("^[a-z][a-z0-9_]*$") == OK
		and expression.search(value) != null
	)
