# Doc: docs/代码/content_unlock_system.md
# Authority: docs/游戏设计文档.md, docs/决策记录.md
class_name ContentUnlockSystemAutoload
extends Node


signal progression_committed(newly_unlocked: Dictionary)
signal content_unlocked(content_type: String, content_id: String)

const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const CONTENT_UNLOCK_RULE_MODES := preload(
	"res://scripts/contracts/content_unlock_rule_modes.gd"
)
const CONTENT_UNLOCK_PROGRESS_COUNTERS := preload(
	"res://scripts/contracts/content_unlock_progress_counters.gd"
)

const RULES_PATH: String = "res://data/content_unlock_rules.json"
const CHARACTERS_PATH: String = "res://data/characters.json"
const GEAR_MODS_PATH: String = "res://data/gear_mods.json"
const ENEMIES_PATH: String = "res://data/enemies.csv"
const DEFAULT_SLOT: String = "slot_0"
const CONTENT_TYPES: Array[String] = CONTENT_UNLOCK_TYPES.VALUES
const COUNTER_IDS: Array[String] = CONTENT_UNLOCK_PROGRESS_COUNTERS.VALUES
const SUBJECT_COUNTER_IDS: Array[String] = [
	CONTENT_UNLOCK_PROGRESS_COUNTERS.CHARACTER_RUN_COMPLETED,
	CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED,
]

var _entries_by_type: Dictionary = {}
var _rules_by_id: Dictionary = {}
var _meta_payload: Dictionary = {}
var _save_manager_override: Object = null


func _ready() -> void:
	_reload_content_data()
	_reload_meta_payload()
	if not DataLoader.data_reloaded.is_connected(_on_data_reloaded):
		DataLoader.data_reloaded.connect(_on_data_reloaded)


func is_unlocked(content_type: String, content_id: String) -> bool:
	var entry: Dictionary = _content_entry(content_type, content_id)
	if entry.is_empty():
		return false
	if _is_default_unlocked(entry):
		return true
	var progression: Dictionary = _normalized_progression(
		_meta_payload.get("content_progression", {})
	)
	if _is_explicitly_unlocked(progression, content_type, content_id):
		return true
	return false


func build_run_availability_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for content_type: String in CONTENT_TYPES:
		var available_ids: Array[String] = []
		var entries: Dictionary = _entries_for_type(content_type)
		for raw_id: Variant in entries.keys():
			var content_id: String = String(raw_id)
			if is_unlocked(content_type, content_id):
				available_ids.append(content_id)
		available_ids.sort()
		snapshot[content_type] = available_ids
	return snapshot


func requirement_status(content_type: String, content_id: String) -> Dictionary:
	var entry: Dictionary = _content_entry(content_type, content_id)
	if entry.is_empty():
		return {
			"content_type": content_type,
			"id": content_id,
			"valid": false,
			"unlocked": false,
			"complete": false,
			"conditions": [],
		}
	var progression: Dictionary = _normalized_progression(
		_meta_payload.get("content_progression", {})
	)
	return _requirement_status_for_entry(
		content_type,
		entry,
		progression,
		_pending_run_progress_delta()
	)


func codex_entries(content_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries: Dictionary = _entries_for_type(content_type)
	var progression: Dictionary = _normalized_progression(
		_meta_payload.get("content_progression", {})
	)
	var pending_delta: Dictionary = _pending_run_progress_delta()
	for raw_id: Variant in entries.keys():
		var content_id: String = String(raw_id)
		var entry: Dictionary = entries[raw_id] as Dictionary
		var unlocked: bool = is_unlocked(content_type, content_id)
		var normalized: Dictionary = {
			"type": content_type,
			"id": content_id,
			"unlocked": unlocked,
			"requirement": _requirement_status_for_entry(
				content_type,
				entry,
				progression,
				pending_delta
			),
		}
		if not unlocked:
			result.append(normalized)
			continue
		var name_key: String = String(entry.get("name_key", ""))
		var desc_key: String = String(entry.get("desc_key", name_key))
		if desc_key.is_empty():
			desc_key = name_key
		var icon_path: String = String(
			entry.get("codex_icon_path", entry.get("icon_path", ""))
		)
		if not icon_path.is_empty() and not ResourceLoader.exists(icon_path):
			icon_path = ""
		normalized["name_key"] = name_key
		normalized["desc_key"] = desc_key
		normalized["icon_path"] = icon_path
		normalized["default_unlocked"] = _is_default_unlocked(entry)
		normalized["unlock_rule_id"] = String(
			entry.get("unlock_rule_id", "")
		)
		normalized["details"] = _codex_details(content_type, entry)
		result.append(normalized)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("id", "")) < String(right.get("id", ""))
	)
	return result


## Returns the unlocks that the saved, uncommitted Run delta would earn if the
## run ended now. This is a read-only preview and never changes Meta.
func pending_run_preview() -> Dictionary:
	var pending_delta: Dictionary = _pending_run_progress_delta()
	if pending_delta.is_empty() or not _validate_progress_delta(pending_delta):
		return _empty_unlock_result()
	var preview_progression: Dictionary = _normalized_progression(
		_meta_payload.get("content_progression", {})
	)
	_merge_progress_delta(preview_progression, pending_delta)
	return _evaluate_and_record_unlocks(preview_progression)


func commit_run_progress(delta: Dictionary) -> Dictionary:
	var manager: Object = _save_manager()
	if manager == null:
		push_error("[ContentUnlockSystem] SaveManager is unavailable")
		return _commit_result(false, {})
	if not _validate_progress_delta(delta):
		return _commit_result(false, {})

	var has_meta: bool = bool(
		manager.call("has_save", DEFAULT_SLOT, SAVE_KINDS.META)
	)
	var meta_payload: Dictionary = {}
	if has_meta:
		var envelope: Variant = manager.call(
			"load_envelope",
			DEFAULT_SLOT,
			SAVE_KINDS.META
		)
		if not envelope is Dictionary or (envelope as Dictionary).is_empty():
			push_error("[ContentUnlockSystem] existing Meta save could not be loaded")
			return _commit_result(false, {})
		var loaded_payload: Variant = (envelope as Dictionary).get("payload", {})
		if not loaded_payload is Dictionary:
			push_error("[ContentUnlockSystem] Meta payload must be a Dictionary")
			return _commit_result(false, {})
		meta_payload = (loaded_payload as Dictionary).duplicate(true)
	var progression: Dictionary = _normalized_progression(
		meta_payload.get("content_progression", {})
	)
	_merge_progress_delta(progression, delta)
	var newly_unlocked: Dictionary = _evaluate_and_record_unlocks(progression)
	meta_payload["content_progression"] = progression
	if not bool(manager.call("save", DEFAULT_SLOT, SAVE_KINDS.META, meta_payload)):
		push_error("[ContentUnlockSystem] failed to save Meta content progression")
		return _commit_result(false, {})

	_meta_payload = meta_payload.duplicate(true)
	for content_type: String in CONTENT_TYPES:
		for raw_id: Variant in newly_unlocked.get(content_type, []):
			content_unlocked.emit(content_type, String(raw_id))
	progression_committed.emit(newly_unlocked.duplicate(true))
	return _commit_result(true, newly_unlocked)


func _on_data_reloaded() -> void:
	_reload_content_data()


func _reload_content_data() -> void:
	var characters_payload: Variant = DataLoader.load_json(CHARACTERS_PATH)
	var gear_mods_payload: Variant = DataLoader.load_json(GEAR_MODS_PATH)
	var enemy_rows: Array[Dictionary] = DataLoader.load_csv(ENEMIES_PATH)
	var rules_payload: Variant = DataLoader.load_json(RULES_PATH)
	var entries: Dictionary = {
		CONTENT_UNLOCK_TYPES.CHARACTER: {},
		CONTENT_UNLOCK_TYPES.GEAR_MOD: {},
		CONTENT_UNLOCK_TYPES.ENEMY: {},
	}
	if characters_payload is Dictionary:
		_index_entries(
			entries[CONTENT_UNLOCK_TYPES.CHARACTER] as Dictionary,
			(characters_payload as Dictionary).get("characters", [])
		)
	if gear_mods_payload is Dictionary:
		_index_entries(
			entries[CONTENT_UNLOCK_TYPES.GEAR_MOD] as Dictionary,
			(gear_mods_payload as Dictionary).get("mods", [])
		)
	_index_entries(entries[CONTENT_UNLOCK_TYPES.ENEMY] as Dictionary, enemy_rows)
	_entries_by_type = entries

	_rules_by_id.clear()
	if rules_payload is Dictionary:
		for raw_rule: Variant in (rules_payload as Dictionary).get("rules", []):
			if not raw_rule is Dictionary:
				continue
			var rule: Dictionary = raw_rule as Dictionary
			var rule_id: String = String(rule.get("id", ""))
			if not rule_id.is_empty():
				_rules_by_id[rule_id] = rule.duplicate(true)


func _reload_meta_payload() -> void:
	var manager: Object = _save_manager()
	if manager == null:
		_meta_payload = {}
		return
	if not bool(manager.call("has_save", DEFAULT_SLOT, SAVE_KINDS.META)):
		_meta_payload = {}
		return
	var loaded: Variant = manager.call("load", DEFAULT_SLOT, SAVE_KINDS.META)
	_meta_payload = (loaded as Dictionary).duplicate(true) if loaded is Dictionary else {}


func _save_manager() -> Object:
	if _save_manager_override != null:
		return _save_manager_override
	return get_node_or_null("/root/SaveManager")


func _index_entries(target: Dictionary, raw_entries: Variant) -> void:
	if not raw_entries is Array:
		return
	for raw_entry: Variant in raw_entries as Array:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var content_id: String = String(entry.get("id", ""))
		if not content_id.is_empty():
			target[content_id] = entry.duplicate(true)


func _entries_for_type(content_type: String) -> Dictionary:
	if not CONTENT_TYPES.has(content_type):
		return {}
	var entries: Variant = _entries_by_type.get(content_type, {})
	return entries as Dictionary if entries is Dictionary else {}


func _content_entry(content_type: String, content_id: String) -> Dictionary:
	var entries: Dictionary = _entries_for_type(content_type)
	var entry: Variant = entries.get(content_id, {})
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}


func _is_default_unlocked(entry: Dictionary) -> bool:
	if not entry.has("default_unlocked"):
		return true
	var value: Variant = entry.get("default_unlocked")
	if value is bool:
		return value as bool
	if value is String:
		var normalized_value: String = String(value).strip_edges().to_lower()
		# CSV optional fields are present as empty strings. Treat an empty cell like
		# an omitted field so future content stays open unless explicitly locked.
		return normalized_value.is_empty() or normalized_value == "true"
	return false


func _normalized_progression(raw_progression: Variant) -> Dictionary:
	var progression: Dictionary = (
		(raw_progression as Dictionary).duplicate(true)
		if raw_progression is Dictionary
		else {}
	)
	if (
		not progression.has("unlocked")
		or not progression.get("unlocked") is Dictionary
	):
		progression["unlocked"] = {}
	var unlocked: Dictionary = progression.get("unlocked") as Dictionary
	for content_type: String in CONTENT_TYPES:
		var normalized_ids: Array[String] = []
		var raw_ids: Variant = unlocked.get(content_type, [])
		if raw_ids is Array:
			for raw_id: Variant in raw_ids as Array:
				var content_id: String = String(raw_id).strip_edges()
				if not content_id.is_empty() and not normalized_ids.has(content_id):
					normalized_ids.append(content_id)
		if normalized_ids.is_empty():
			unlocked.erase(content_type)
		else:
			normalized_ids.sort()
			unlocked[content_type] = normalized_ids
	progression["unlocked"] = unlocked
	if (
		not progression.has("counters")
		or not progression.get("counters") is Dictionary
	):
		progression["counters"] = {}
	return progression


func _is_explicitly_unlocked(
	progression: Dictionary,
	content_type: String,
	content_id: String
) -> bool:
	var unlocked: Dictionary = progression.get("unlocked", {}) as Dictionary
	var ids: Variant = unlocked.get(content_type, [])
	return ids is Array and (ids as Array).has(content_id)


func _requirement_status_for_entry(
	content_type: String,
	entry: Dictionary,
	progression: Dictionary,
	pending_delta: Dictionary
) -> Dictionary:
	var content_id: String = String(entry.get("id", ""))
	var default_unlocked: bool = _is_default_unlocked(entry)
	var explicit_unlocked: bool = _is_explicitly_unlocked(
		progression,
		content_type,
		content_id
	)
	var rule_id: String = String(entry.get("unlock_rule_id", ""))
	var status: Dictionary = {
		"content_type": content_type,
		"id": content_id,
		"valid": true,
		"default_unlocked": default_unlocked,
		"explicitly_unlocked": explicit_unlocked,
		"rule_id": rule_id,
		"mode": CONTENT_UNLOCK_RULE_MODES.ALL,
		"unlocked": default_unlocked or explicit_unlocked,
		"complete": default_unlocked or explicit_unlocked,
		"conditions": [],
	}
	if default_unlocked or explicit_unlocked:
		return status
	if rule_id.is_empty() or not _rules_by_id.has(rule_id):
		status["valid"] = false
		return status

	var rule: Dictionary = _rules_by_id[rule_id] as Dictionary
	var mode: String = String(
		rule.get("mode", CONTENT_UNLOCK_RULE_MODES.ALL)
	)
	var condition_statuses: Array[Dictionary] = []
	for raw_condition: Variant in rule.get("conditions", []):
		if not raw_condition is Dictionary:
			continue
		var condition: Dictionary = raw_condition as Dictionary
		var counter_id: String = String(condition.get("counter_id", ""))
		var subject_id: String = String(condition.get("subject_id", ""))
		var target: int = int(condition.get("target", 0))
		var current: int = _counter_value(progression, counter_id, subject_id)
		var pending: int = _delta_counter_value(
			pending_delta,
			counter_id,
			subject_id
		)
		condition_statuses.append({
			"counter_id": counter_id,
			"subject_id": subject_id,
			"subject_name_key": _subject_name_key(counter_id, subject_id),
			"current": current,
			"pending": pending,
			"target": target,
			"complete": current >= target,
		})

	var complete: bool = not condition_statuses.is_empty()
	if mode == CONTENT_UNLOCK_RULE_MODES.ANY:
		complete = false
		for condition_status: Dictionary in condition_statuses:
			if bool(condition_status.get("complete", false)):
				complete = true
				break
	else:
		for condition_status: Dictionary in condition_statuses:
			if not bool(condition_status.get("complete", false)):
				complete = false
				break
	status["mode"] = mode
	status["complete"] = complete
	status["conditions"] = condition_statuses
	return status


func _counter_value(
	progression: Dictionary,
	counter_id: String,
	subject_id: String
) -> int:
	var counters: Dictionary = progression.get("counters", {}) as Dictionary
	var raw_value: Variant = counters.get(counter_id, 0)
	if subject_id.is_empty():
		return maxi(0, int(raw_value)) if raw_value is int or raw_value is float else 0
	if not raw_value is Dictionary:
		return 0
	var subject_value: Variant = (raw_value as Dictionary).get(subject_id, 0)
	return maxi(0, int(subject_value)) if subject_value is int or subject_value is float else 0


func _delta_counter_value(
	delta: Dictionary,
	counter_id: String,
	subject_id: String
) -> int:
	var raw_value: Variant = delta.get(counter_id, 0)
	if subject_id.is_empty():
		return maxi(0, int(raw_value)) if raw_value is int else 0
	if not raw_value is Dictionary:
		return 0
	var subject_value: Variant = (raw_value as Dictionary).get(subject_id, 0)
	return maxi(0, int(subject_value)) if subject_value is int else 0


func _pending_run_progress_delta() -> Dictionary:
	var manager: Object = _save_manager()
	if manager == null:
		return {}
	if not bool(manager.call("has_save", DEFAULT_SLOT, SAVE_KINDS.RUN)):
		return {}
	var run_payload: Variant = manager.call("load", DEFAULT_SLOT, SAVE_KINDS.RUN)
	if not run_payload is Dictionary:
		return {}
	var run: Dictionary = run_payload as Dictionary
	if (
		int(run.get("schema_version", 0))
		!= int(manager.call("current_version", SAVE_KINDS.RUN))
		or bool(run.get("legacy_run_incompatible", false))
	):
		return {}
	var raw_delta: Variant = run.get("content_progress_delta", {})
	if not raw_delta is Dictionary:
		return {}
	var delta: Dictionary = raw_delta as Dictionary
	return delta.duplicate(true) if _is_progress_delta_shape_valid(delta) else {}


func _validate_progress_delta(delta: Dictionary) -> bool:
	var is_valid: bool = true
	for raw_counter_id: Variant in delta.keys():
		var counter_id: String = String(raw_counter_id)
		if not COUNTER_IDS.has(counter_id):
			push_error("[ContentUnlockSystem] unknown progress counter: %s" % counter_id)
			is_valid = false
			continue
		var value: Variant = delta[raw_counter_id]
		if SUBJECT_COUNTER_IDS.has(counter_id):
			if not value is Dictionary:
				push_error("[ContentUnlockSystem] counter %s must be a Dictionary" % counter_id)
				is_valid = false
				continue
			for raw_subject_id: Variant in (value as Dictionary).keys():
				var subject_id: String = String(raw_subject_id)
				if not _is_valid_counter_subject(counter_id, subject_id):
					push_error(
						"[ContentUnlockSystem] invalid subject %s for counter %s"
						% [subject_id, counter_id]
					)
					is_valid = false
				if not _is_non_negative_int((value as Dictionary)[raw_subject_id]):
					push_error(
						"[ContentUnlockSystem] counter delta %s.%s must be a non-negative int"
						% [counter_id, subject_id]
					)
					is_valid = false
		elif not _is_non_negative_int(value):
			push_error(
				"[ContentUnlockSystem] counter delta %s must be a non-negative int"
				% counter_id
			)
			is_valid = false
	return is_valid


func _is_progress_delta_shape_valid(delta: Dictionary) -> bool:
	for raw_counter_id: Variant in delta.keys():
		var counter_id: String = String(raw_counter_id)
		if not COUNTER_IDS.has(counter_id):
			return false
		var value: Variant = delta[raw_counter_id]
		if SUBJECT_COUNTER_IDS.has(counter_id):
			if not value is Dictionary:
				return false
			for raw_subject_id: Variant in (value as Dictionary).keys():
				if (
					not _is_valid_counter_subject(counter_id, String(raw_subject_id))
					or not _is_non_negative_int(
						(value as Dictionary)[raw_subject_id]
					)
				):
					return false
		elif not _is_non_negative_int(value):
			return false
	return true


func _is_non_negative_int(value: Variant) -> bool:
	return value is int and int(value) >= 0


func _is_valid_counter_subject(counter_id: String, subject_id: String) -> bool:
	if counter_id == CONTENT_UNLOCK_PROGRESS_COUNTERS.CHARACTER_RUN_COMPLETED:
		return _entries_for_type(CONTENT_UNLOCK_TYPES.CHARACTER).has(subject_id)
	if counter_id == CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED:
		return _entries_for_type(CONTENT_UNLOCK_TYPES.ENEMY).has(subject_id)
	return false


func _merge_progress_delta(progression: Dictionary, delta: Dictionary) -> void:
	var counters: Dictionary = progression.get("counters", {}) as Dictionary
	for counter_id: String in COUNTER_IDS:
		if not delta.has(counter_id):
			continue
		var raw_delta: Variant = delta[counter_id]
		if SUBJECT_COUNTER_IDS.has(counter_id):
			var subject_counts: Dictionary = {}
			if counters.get(counter_id, {}) is Dictionary:
				subject_counts = (counters.get(counter_id, {}) as Dictionary).duplicate(true)
			for raw_subject_id: Variant in (raw_delta as Dictionary).keys():
				var subject_id: String = String(raw_subject_id)
				var increment: int = int((raw_delta as Dictionary)[raw_subject_id])
				if increment > 0:
					subject_counts[subject_id] = maxi(
						0,
						int(subject_counts.get(subject_id, 0))
					) + increment
			if not subject_counts.is_empty():
				counters[counter_id] = subject_counts
			continue
		var increment: int = int(raw_delta)
		if increment > 0:
			counters[counter_id] = maxi(0, int(counters.get(counter_id, 0))) + increment
	progression["counters"] = counters


func _evaluate_and_record_unlocks(progression: Dictionary) -> Dictionary:
	var newly_unlocked: Dictionary = _empty_unlock_result()
	var unlocked: Dictionary = progression.get("unlocked", {}) as Dictionary
	for content_type: String in CONTENT_TYPES:
		var recorded_ids: Array = []
		if unlocked.get(content_type, []) is Array:
			recorded_ids = (unlocked.get(content_type, []) as Array).duplicate()
		for raw_id: Variant in _entries_for_type(content_type).keys():
			var content_id: String = String(raw_id)
			var entry: Dictionary = _content_entry(content_type, content_id)
			if _is_default_unlocked(entry) or recorded_ids.has(content_id):
				continue
			var status: Dictionary = _requirement_status_for_entry(
				content_type,
				entry,
				progression,
				{}
			)
			if bool(status.get("complete", false)):
				recorded_ids.append(content_id)
				(newly_unlocked[content_type] as Array).append(content_id)
		if not recorded_ids.is_empty():
			recorded_ids.sort()
			unlocked[content_type] = recorded_ids
		(newly_unlocked[content_type] as Array).sort()
	progression["unlocked"] = unlocked
	return newly_unlocked


func _codex_details(content_type: String, entry: Dictionary) -> Dictionary:
	match content_type:
		CONTENT_UNLOCK_TYPES.CHARACTER:
			return {
				"base_stats": _dictionary_copy(entry.get("base_stats", {})),
				"passive_id": String(entry.get("passive_id", "")),
				"hero_skill_ids": _array_copy(entry.get("hero_skill_ids", [])),
			}
		CONTENT_UNLOCK_TYPES.GEAR_MOD:
			return {
				"slot": String(entry.get("slot", "")),
				"rarity": String(entry.get("rarity", "")),
				"modifiers": _array_copy(entry.get("modifiers", [])),
			}
		CONTENT_UNLOCK_TYPES.ENEMY:
			return {
				"max_hp": _entry_number(entry.get("max_hp", 0.0)),
				"move_speed": _entry_number(entry.get("move_speed", 0.0)),
				"gold_value_multiplier": _entry_number(
					entry.get("gold_value_multiplier", 0.0)
				),
				"hit_radius": _entry_number(entry.get("hit_radius", 0.0)),
				"separation_radius": _entry_number(
					entry.get("separation_radius", 0.0)
				),
			}
		_:
			return {}


func _subject_name_key(counter_id: String, subject_id: String) -> String:
	if subject_id.is_empty():
		return ""
	var subject_type: String = ""
	if counter_id == CONTENT_UNLOCK_PROGRESS_COUNTERS.CHARACTER_RUN_COMPLETED:
		subject_type = CONTENT_UNLOCK_TYPES.CHARACTER
	elif counter_id == CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED:
		subject_type = CONTENT_UNLOCK_TYPES.ENEMY
	if subject_type.is_empty():
		return ""
	var entry: Dictionary = _content_entry(subject_type, subject_id)
	if entry.is_empty() or not _is_default_unlocked(entry):
		return ""
	return String(entry.get("name_key", ""))


func _dictionary_copy(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _array_copy(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else []


func _entry_number(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return String(value).to_float()


func _empty_unlock_result() -> Dictionary:
	return {
		CONTENT_UNLOCK_TYPES.CHARACTER: [],
		CONTENT_UNLOCK_TYPES.GEAR_MOD: [],
		CONTENT_UNLOCK_TYPES.ENEMY: [],
	}


func _commit_result(saved: bool, newly_unlocked: Dictionary) -> Dictionary:
	var normalized_unlocks: Dictionary = (
		newly_unlocked.duplicate(true)
		if not newly_unlocked.is_empty()
		else _empty_unlock_result()
	)
	var progression: Dictionary = _normalized_progression(
		_meta_payload.get("content_progression", {})
	)
	return {
		"saved": saved,
		"newly_unlocked": normalized_unlocks,
		"counters": (progression.get("counters", {}) as Dictionary).duplicate(true),
	}
