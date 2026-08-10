# Doc: docs/代码/gameplay_runtime.md
class_name ModifierStack
extends RefCounted
## Pure, ordered modifier layers shared by gameplay stat owners.


const LAYER_PERSISTENT: String = "persistent"
const LAYER_GEAR: String = "gear"
const LAYER_TEMPORARY: String = "temporary"
const LAYER_ORDER: Array[String] = [
	LAYER_PERSISTENT,
	LAYER_GEAR,
	LAYER_TEMPORARY,
]
const ANONYMOUS_SOURCE: String = "anonymous"
const RESTORED_TOTALS_SOURCE: String = "__restored_totals__"
const TOTAL_ADDITIONS: String = "additions"
const TOTAL_MULTIPLIERS: String = "multipliers"

var _base_values: Dictionary = {}
var _sources_by_layer: Dictionary = {}


func _init() -> void:
	_reset_layers()


func configure(base_values: Dictionary) -> void:
	_base_values = base_values.duplicate(true)
	_reset_layers()


func append_modifiers(
	layer_id: String,
	modifiers: Array,
	source_id: String = ANONYMOUS_SOURCE
) -> void:
	if not _is_known_layer(layer_id):
		return
	var appended_modifiers: Array[Dictionary] = _copy_modifiers(modifiers)
	if appended_modifiers.is_empty():
		return
	var normalized_source: String = _normalize_source_id(source_id)
	var sources: Dictionary = _sources_by_layer[layer_id] as Dictionary
	if sources.has(normalized_source):
		var raw_existing_modifiers: Variant = sources[normalized_source]
		if raw_existing_modifiers is Array:
			(raw_existing_modifiers as Array).append_array(appended_modifiers)
			return
	sources[normalized_source] = appended_modifiers


func replace_source(
	layer_id: String,
	source_id: String,
	modifiers: Array
) -> void:
	if not _is_known_layer(layer_id):
		return
	var sources: Dictionary = _sources_by_layer[layer_id] as Dictionary
	sources[_normalize_source_id(source_id)] = _copy_modifiers(modifiers)


func replace_layer(
	layer_id: String,
	modifiers: Array,
	source_id: String = ANONYMOUS_SOURCE
) -> void:
	if not _is_known_layer(layer_id):
		return
	clear_layer(layer_id)
	var copied_modifiers: Array[Dictionary] = _copy_modifiers(modifiers)
	if copied_modifiers.is_empty():
		return
	var sources: Dictionary = _sources_by_layer[layer_id] as Dictionary
	sources[_normalize_source_id(source_id)] = copied_modifiers


func remove_source(layer_id: String, source_id: String) -> bool:
	if not _is_known_layer(layer_id):
		return false
	var sources: Dictionary = _sources_by_layer[layer_id] as Dictionary
	var normalized_source: String = _normalize_source_id(source_id)
	if not sources.has(normalized_source):
		return false
	sources.erase(normalized_source)
	return true


func clear_layer(layer_id: String) -> void:
	if not _is_known_layer(layer_id):
		return
	_sources_by_layer[layer_id] = {}


func value(stat_id: String, default_value: float = 0.0) -> float:
	var base_value: float = float(_base_values.get(stat_id, default_value))
	var persistent_totals: PackedFloat64Array = _stat_totals_for_layer(
		LAYER_PERSISTENT,
		stat_id
	)
	var gear_totals: PackedFloat64Array = _stat_totals_for_layer(
		LAYER_GEAR,
		stat_id
	)
	var added_value: float = (
		persistent_totals[0]
		+ gear_totals[0]
	)
	var multiplier: float = (
		persistent_totals[1]
		* gear_totals[1]
	)
	var temporary_sources: Dictionary = (
		_sources_by_layer[LAYER_TEMPORARY] as Dictionary
	)
	for raw_modifiers: Variant in temporary_sources.values():
		for raw_modifier: Variant in _modifiers_or_empty(raw_modifiers):
			if not raw_modifier is Dictionary:
				continue
			var modifier: Dictionary = raw_modifier as Dictionary
			if String(modifier.get("stat", "")) != stat_id:
				continue
			var modifier_type: String = String(modifier.get("type", ""))
			if modifier_type == "add":
				added_value += float(modifier.get("value", 0.0))
			elif modifier_type == "mult":
				multiplier *= float(modifier.get("value", 1.0))
	return (base_value + added_value) * multiplier


func materialized_values() -> Dictionary:
	var result: Dictionary = {}
	for raw_stat_id: Variant in _base_values.keys():
		var raw_base_value: Variant = _base_values[raw_stat_id]
		if raw_base_value is int or raw_base_value is float:
			var stat_id: String = String(raw_stat_id)
			result[stat_id] = value(stat_id)
	for layer_id: String in LAYER_ORDER:
		var sources: Dictionary = _sources_by_layer[layer_id] as Dictionary
		for raw_modifiers: Variant in sources.values():
			for raw_modifier: Variant in _modifiers_or_empty(raw_modifiers):
				if not raw_modifier is Dictionary:
					continue
				var modifier: Dictionary = raw_modifier as Dictionary
				var stat_id: String = String(modifier.get("stat", ""))
				if (
					String(modifier.get("type", "")) == "add"
					and not stat_id.is_empty()
					and not result.has(stat_id)
				):
					result[stat_id] = value(stat_id)
	return result


func layer_totals(layer_id: String) -> Dictionary:
	var additions: Dictionary = {}
	var multipliers: Dictionary = {}
	if not _is_known_layer(layer_id):
		return {
			TOTAL_ADDITIONS: additions,
			TOTAL_MULTIPLIERS: multipliers,
		}
	var sources: Dictionary = _sources_by_layer[layer_id] as Dictionary
	for raw_modifiers: Variant in sources.values():
		for raw_modifier: Variant in _modifiers_or_empty(raw_modifiers):
			if not raw_modifier is Dictionary:
				continue
			var modifier: Dictionary = raw_modifier as Dictionary
			var stat_id: String = String(modifier.get("stat", ""))
			var modifier_type: String = String(modifier.get("type", ""))
			if modifier_type == "add":
				additions[stat_id] = (
					float(additions.get(stat_id, 0.0))
					+ float(modifier.get("value", 0.0))
				)
			elif modifier_type == "mult":
				multipliers[stat_id] = (
					float(multipliers.get(stat_id, 1.0))
					* float(modifier.get("value", 1.0))
				)
	return {
		TOTAL_ADDITIONS: additions,
		TOTAL_MULTIPLIERS: multipliers,
	}


func restore_layer_totals(layer_id: String, totals: Dictionary) -> void:
	if not _is_known_layer(layer_id):
		return
	clear_layer(layer_id)
	var restored_modifiers: Array[Dictionary] = []
	var additions: Dictionary = _dictionary_or_empty(
		totals.get(TOTAL_ADDITIONS, {})
	)
	for raw_stat_id: Variant in additions.keys():
		restored_modifiers.append({
			"stat": String(raw_stat_id),
			"type": "add",
			"value": float(additions[raw_stat_id]),
		})
	var multipliers: Dictionary = _dictionary_or_empty(
		totals.get(TOTAL_MULTIPLIERS, {})
	)
	for raw_stat_id: Variant in multipliers.keys():
		restored_modifiers.append({
			"stat": String(raw_stat_id),
			"type": "mult",
			"value": float(multipliers[raw_stat_id]),
		})
	if restored_modifiers.is_empty():
		return
	var sources: Dictionary = _sources_by_layer[layer_id] as Dictionary
	sources[RESTORED_TOTALS_SOURCE] = restored_modifiers


func _reset_layers() -> void:
	_sources_by_layer = {
		LAYER_PERSISTENT: {},
		LAYER_GEAR: {},
		LAYER_TEMPORARY: {},
	}


func _is_known_layer(layer_id: String) -> bool:
	return _sources_by_layer.has(layer_id)


func _normalize_source_id(source_id: String) -> String:
	return ANONYMOUS_SOURCE if source_id.is_empty() else source_id


func _copy_modifiers(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for raw_modifier: Variant in raw_value as Array:
		if raw_modifier is Dictionary:
			result.append((raw_modifier as Dictionary).duplicate(true))
	return result


func _modifiers_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return raw_value as Array
	return []


func _stat_totals_for_layer(
	layer_id: String,
	stat_id: String
) -> PackedFloat64Array:
	var added_value: float = 0.0
	var multiplier: float = 1.0
	var sources: Dictionary = _sources_by_layer[layer_id] as Dictionary
	for raw_modifiers: Variant in sources.values():
		for raw_modifier: Variant in _modifiers_or_empty(raw_modifiers):
			if not raw_modifier is Dictionary:
				continue
			var modifier: Dictionary = raw_modifier as Dictionary
			if String(modifier.get("stat", "")) != stat_id:
				continue
			var modifier_type: String = String(modifier.get("type", ""))
			if modifier_type == "add":
				added_value += float(modifier.get("value", 0.0))
			elif modifier_type == "mult":
				multiplier *= float(modifier.get("value", 1.0))
	return PackedFloat64Array([added_value, multiplier])


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}
