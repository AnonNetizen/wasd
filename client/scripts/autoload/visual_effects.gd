# Doc: docs/代码/visual_effects.md
# Authority: docs/游戏设计文档.md §9.24, docs/词表与契约.md §16
class_name VisualEffectsAutoload
extends Node
## Read-only runtime registry for visual effects, presentation profiles, and player policy.


signal catalog_reloaded(effect_count: int, profile_count: int)
signal policy_changed(policy: Dictionary)

const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const VFX_MOTION_POLICIES := preload("res://scripts/contracts/vfx_motion_policies.gd")
const VISUAL_EFFECTS_PATH: String = "res://data/visual_effects.json"
const PRESENTATION_PROFILES_PATH: String = "res://data/presentation_profiles.json"
const MAX_RESOLUTION_DEPTH: int = 16

var _effects: Dictionary = {}
var _profiles: Dictionary = {}


func _ready() -> void:
	reload()
	if not DataLoader.data_reloaded.is_connected(_on_data_reloaded):
		DataLoader.data_reloaded.connect(_on_data_reloaded)
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if DataLoader.data_reloaded.is_connected(_on_data_reloaded):
		DataLoader.data_reloaded.disconnect(_on_data_reloaded)
	if Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.disconnect(_on_setting_changed)


func reload() -> bool:
	var effects_payload: Variant = DataLoader.load_json(VISUAL_EFFECTS_PATH)
	var profiles_payload: Variant = DataLoader.load_json(PRESENTATION_PROFILES_PATH)
	if not effects_payload is Dictionary or not profiles_payload is Dictionary:
		push_error("[VisualEffects] catalog payloads must be dictionaries")
		return false

	var next_effects: Dictionary = {}
	for raw_effect: Variant in (effects_payload as Dictionary).get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var effect_data: Dictionary = raw_effect as Dictionary
		var effect_id: String = String(effect_data.get("id", "")).strip_edges()
		if effect_id.is_empty():
			continue
		next_effects[effect_id] = effect_data.duplicate(true)

	var next_profiles: Dictionary = {}
	for raw_profile: Variant in (profiles_payload as Dictionary).get("profiles", []):
		if not raw_profile is Dictionary:
			continue
		var profile_data: Dictionary = raw_profile as Dictionary
		var profile_id: String = String(profile_data.get("id", "")).strip_edges()
		if profile_id.is_empty():
			continue
		next_profiles[profile_id] = profile_data.duplicate(true)

	_effects = next_effects
	_profiles = next_profiles
	catalog_reloaded.emit(_effects.size(), _profiles.size())
	return true


func effect(effect_id: String) -> Dictionary:
	if not _effects.has(effect_id):
		return {}
	return (_effects[effect_id] as Dictionary).duplicate(true)


func profile(profile_id: String) -> Dictionary:
	return _resolve_profile(profile_id, {}, 0)


func resolve_binding(profile_id: String, cue: String) -> Dictionary:
	var resolved_profile: Dictionary = profile(profile_id)
	var bindings: Dictionary = resolved_profile.get("bindings", {}) as Dictionary
	var raw_binding: Variant = bindings.get(cue)
	if not raw_binding is Dictionary:
		return {}
	return (raw_binding as Dictionary).duplicate(true)


func current_policy() -> Dictionary:
	return {
		"quality": String(
			Settings.get_value(SETTINGS_KEYS.VIDEO_VFX_QUALITY, "high")
		),
		"reduced_motion": bool(
			Settings.get_value(SETTINGS_KEYS.ACCESSIBILITY_REDUCED_MOTION, false)
		),
		"screen_flashes": bool(
			Settings.get_value(SETTINGS_KEYS.ACCESSIBILITY_SCREEN_FLASHES, true)
		),
		"screen_shake": bool(
			Settings.get_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true)
		),
	}


func resolved_effect(effect_id: String) -> Dictionary:
	var current_id: String = effect_id
	var visited: Dictionary = {}
	var policy: Dictionary = current_policy()
	for _depth: int in range(MAX_RESOLUTION_DEPTH):
		if current_id.is_empty() or visited.has(current_id):
			return {}
		visited[current_id] = true
		var current_effect: Dictionary = effect(current_id)
		if current_effect.is_empty():
			return {}

		if bool(policy.get("reduced_motion", false)):
			var reduced_data: Dictionary = current_effect.get("reduced_motion", {}) as Dictionary
			var reduced_mode: String = String(
				reduced_data.get("mode", VFX_MOTION_POLICIES.SAME)
			)
			if reduced_mode == VFX_MOTION_POLICIES.VARIANT:
				var reduced_effect_id: String = String(reduced_data.get("effect_id", ""))
				if not reduced_effect_id.is_empty() and reduced_effect_id != current_id:
					current_id = reduced_effect_id
					continue

		var variants: Dictionary = current_effect.get("quality_variants", {}) as Dictionary
		var quality: String = String(policy.get("quality", "high"))
		var variant_id: String = String(variants.get(quality, ""))
		if not variant_id.is_empty() and variant_id != current_id:
			current_id = variant_id
			continue
		return current_effect
	return {}


func allows_effect(effect_data: Dictionary) -> bool:
	var tags: Array = effect_data.get("tags", []) as Array
	var policy: Dictionary = current_policy()
	var reduced_data: Dictionary = effect_data.get("reduced_motion", {}) as Dictionary
	if (
		bool(policy.get("reduced_motion", false))
		and String(reduced_data.get("mode", VFX_MOTION_POLICIES.SAME))
		== VFX_MOTION_POLICIES.SUPPRESS_OPTIONAL
		and not tags.has("gameplay_boundary")
	):
		return false
	if tags.has("screen_flash") and not bool(policy.get("screen_flashes", true)):
		return false
	return true


func effect_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _effects.keys():
		result.append(String(raw_id))
	result.sort()
	return result


func profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		result.append(String(raw_id))
	result.sort()
	return result


func _resolve_profile(profile_id: String, visiting: Dictionary, depth: int) -> Dictionary:
	if profile_id.is_empty() or depth >= MAX_RESOLUTION_DEPTH or visiting.has(profile_id):
		return {}
	if not _profiles.has(profile_id):
		return {}

	var next_visiting: Dictionary = visiting.duplicate()
	next_visiting[profile_id] = true
	var raw_profile: Dictionary = _profiles[profile_id] as Dictionary
	var result: Dictionary = {}
	var parent_profile_id: String = String(raw_profile.get("parent_profile_id", ""))
	if not parent_profile_id.is_empty():
		result = _resolve_profile(parent_profile_id, next_visiting, depth + 1)

	result["id"] = profile_id
	result["parent_profile_id"] = parent_profile_id
	var merged_bindings: Dictionary = {}
	var inherited_bindings: Variant = result.get("bindings", {})
	if inherited_bindings is Dictionary:
		merged_bindings = (inherited_bindings as Dictionary).duplicate(true)
	var local_bindings: Dictionary = raw_profile.get("bindings", {}) as Dictionary
	for raw_cue: Variant in local_bindings.keys():
		merged_bindings[String(raw_cue)] = (
			local_bindings[raw_cue] as Dictionary
		).duplicate(true)
	result["bindings"] = merged_bindings
	return result


func _on_data_reloaded() -> void:
	reload()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key not in [
		SETTINGS_KEYS.VIDEO_VFX_QUALITY,
		SETTINGS_KEYS.ACCESSIBILITY_REDUCED_MOTION,
		SETTINGS_KEYS.ACCESSIBILITY_SCREEN_FLASHES,
		SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE,
	]:
		return
	policy_changed.emit(current_policy())
