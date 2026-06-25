# Doc: docs/代码/warzone_director.md
# Authority: docs/AI协作/工作包/F10-WarzoneDirector.md, docs/游戏设计文档.md §7.3
class_name WarzoneDirector
extends RefCounted


var _configured: bool = false
var _director_id: String = ""
var _mode_id: String = ""
var _mutation_id: String = ""
var _phases: Array[Dictionary] = []
var _encounters: Dictionary = {}
var _interest_points: Array[Dictionary] = []


func configure(target_mode: String, data: Dictionary, _waves: Array[Dictionary]) -> void:
	_configured = false
	_director_id = ""
	_mode_id = target_mode
	_mutation_id = ""
	_phases.clear()
	_encounters.clear()
	_interest_points.clear()
	if data.is_empty():
		return

	_director_id = String(data.get("id", ""))
	_mode_id = String(data.get("mode_id", target_mode))
	_mutation_id = String(data.get("mutation_id", ""))
	var raw_phases: Array = data.get("phases", []) if data.get("phases", []) is Array else []
	for raw_phase: Variant in raw_phases:
		if raw_phase is Dictionary:
			_phases.append((raw_phase as Dictionary).duplicate(true))

	var raw_encounters: Array = data.get("encounters", []) if data.get("encounters", []) is Array else []
	for raw_encounter: Variant in raw_encounters:
		if not raw_encounter is Dictionary:
			continue
		var encounter: Dictionary = (raw_encounter as Dictionary).duplicate(true)
		var encounter_id: String = String(encounter.get("id", ""))
		if not encounter_id.is_empty():
			_encounters[encounter_id] = encounter

	var raw_points: Array = data.get("interest_points", []) if data.get("interest_points", []) is Array else []
	for raw_point: Variant in raw_points:
		if raw_point is Dictionary:
			_interest_points.append((raw_point as Dictionary).duplicate(true))

	_configured = not _director_id.is_empty()


func is_configured() -> bool:
	return _configured


func is_wave_enabled(wave_id: String, elapsed: float) -> bool:
	if not _configured:
		return true
	if wave_id.is_empty():
		return false
	var phase: Dictionary = current_phase(elapsed)
	if phase.is_empty():
		return false
	var wave_ids: Array = phase.get("wave_ids", []) if phase.get("wave_ids", []) is Array else []
	return wave_ids.has(wave_id)


func current_phase(elapsed: float) -> Dictionary:
	if not _configured:
		return {}
	for phase_index: int in range(_phases.size()):
		var phase: Dictionary = _phases[phase_index]
		var start_time: float = float(phase.get("start_time", 0.0))
		var end_time: float = float(phase.get("end_time", 0.0))
		var is_last_phase: bool = phase_index == _phases.size() - 1
		if elapsed >= start_time and (elapsed < end_time or (is_last_phase and elapsed <= end_time)):
			return phase.duplicate(true)
	return {}


func interest_points_for_layout(layout_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _configured:
		return result
	for point: Dictionary in _interest_points:
		var point_layout_id: String = String(point.get("map_layout_id", ""))
		if not point_layout_id.is_empty() and point_layout_id != layout_id:
			continue
		result.append(point.duplicate(true))
	return result


func debug_summary(elapsed: float) -> Dictionary:
	var phase: Dictionary = current_phase(elapsed)
	return {
		"configured": _configured,
		"director_id": _director_id,
		"mode_id": _mode_id,
		"mutation_id": _mutation_id,
		"phase_id": String(phase.get("id", "")),
		"pressure_tag": String(phase.get("pressure_tag", "")),
		"wave_ids": _string_array(phase.get("wave_ids", [])),
		"encounter_ids": _string_array(phase.get("encounter_ids", [])),
		"interest_point_ids": _interest_point_ids(),
	}


func _interest_point_ids() -> Array[String]:
	var ids: Array[String] = []
	for point: Dictionary in _interest_points:
		var point_id: String = String(point.get("id", ""))
		if not point_id.is_empty():
			ids.append(point_id)
	return ids


func _string_array(data: Variant) -> Array[String]:
	var values: Array[String] = []
	if not data is Array:
		return values
	for item: Variant in data as Array:
		var text: String = String(item)
		if not text.is_empty():
			values.append(text)
	return values
