# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5.2, docs/决策记录.md ADR #169
class_name RewardChoiceController
extends Node


const REWARD_CHOICE_TRIGGERS := preload(
	"res://scripts/contracts/reward_choice_triggers.gd"
)
const MIN_CANDIDATE_COUNT: int = 2
const MAX_CANDIDATE_COUNT: int = 5

var _active_request: Dictionary = {}
var _pools: Dictionary = {}


func configure(data: Dictionary) -> bool:
	var raw_pools: Variant = data.get("pools")
	if not raw_pools is Array:
		return false
	var parsed_pools: Dictionary = {}
	for raw_pool: Variant in raw_pools as Array:
		if not raw_pool is Dictionary:
			return false
		var pool: Dictionary = raw_pool as Dictionary
		var pool_id: String = String(pool.get("id", ""))
		var entries: Variant = pool.get("entries")
		if pool_id.is_empty() or parsed_pools.has(pool_id) or not entries is Array:
			return false
		parsed_pools[pool_id] = (entries as Array).duplicate(true)
	_pools = parsed_pools
	clear()
	return true


func request_choice(
	pool_id: String,
	trigger_id: String,
	candidate_count: int,
	level: int
) -> Dictionary:
	if not _active_request.is_empty():
		return _failure("busy")
	if candidate_count < MIN_CANDIDATE_COUNT or candidate_count > MAX_CANDIDATE_COUNT:
		return _failure("invalid_candidate_count")
	if not REWARD_CHOICE_TRIGGERS.VALUES.has(trigger_id):
		return _failure("invalid_trigger")
	if not _pools.has(pool_id):
		return _failure("unknown_pool")

	var available: Array[Dictionary] = []
	for raw_entry: Variant in _pools[pool_id] as Array:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		if int(entry.get("min_level", 1)) <= level:
			available.append(entry.duplicate(true))
	available.sort_custom(_sort_entries_by_id)
	if available.size() < candidate_count:
		return _failure("insufficient_candidates")
	for entry: Dictionary in available:
		if int(entry.get("weight", 0)) <= 0:
			return _failure("invalid_weight")

	var choices: Array[Dictionary] = []
	while choices.size() < candidate_count:
		var weights: Array[int] = []
		for entry: Dictionary in available:
			weights.append(int(entry.get("weight", 0)))
		var selected: Variant = RNG.ui_choice.weighted_pick(available, weights)
		if not selected is Dictionary:
			return _failure("selection_failed")
		var selected_entry: Dictionary = selected as Dictionary
		choices.append(selected_entry.duplicate(true))
		available.erase(selected_entry)
	choices.sort_custom(_sort_entries_by_id)
	_active_request = {
		"pool_id": pool_id,
		"trigger_id": trigger_id,
		"candidate_count": candidate_count,
		"choices": choices.duplicate(true),
	}
	return {
		"ok": true,
		"reason": "",
		"pool_id": pool_id,
		"trigger_id": trigger_id,
		"candidate_count": candidate_count,
		"choices": choices.duplicate(true),
	}


func resolve(choice_id: String) -> Dictionary:
	if _active_request.is_empty():
		return _failure("not_active")
	for choice: Dictionary in _typed_entries(_active_request.get("choices", [])):
		if String(choice.get("id", "")) != choice_id:
			continue
		var request_snapshot: Dictionary = _active_request.duplicate(true)
		clear()
		return {
			"ok": true,
			"reason": "",
			"pool_id": String(request_snapshot.get("pool_id", "")),
			"trigger_id": String(request_snapshot.get("trigger_id", "")),
			"candidate_count": int(
				request_snapshot.get("candidate_count", 0)
			),
			"choices": _typed_entries(request_snapshot.get("choices", [])),
			"choice": choice.duplicate(true),
		}
	return _failure("unknown_choice")


func restore_snapshot(snapshot_data: Dictionary, level: int) -> bool:
	clear()
	var pool_id: String = String(snapshot_data.get("pool_id", ""))
	var trigger_id: String = String(snapshot_data.get("trigger_id", ""))
	var candidate_count: int = int(snapshot_data.get("candidate_count", 0))
	var choice_ids: Array = (
		snapshot_data.get("choice_ids", [])
		if snapshot_data.get("choice_ids", []) is Array
		else []
	)
	if (
		not _pools.has(pool_id)
		or not REWARD_CHOICE_TRIGGERS.VALUES.has(trigger_id)
		or candidate_count < MIN_CANDIDATE_COUNT
		or candidate_count > MAX_CANDIDATE_COUNT
		or choice_ids.size() != candidate_count
	):
		return false
	var entries_by_id: Dictionary = {}
	for entry: Dictionary in _typed_entries(_pools[pool_id]):
		if int(entry.get("min_level", 1)) <= level:
			entries_by_id[String(entry.get("id", ""))] = entry
	var choices: Array[Dictionary] = []
	for raw_choice_id: Variant in choice_ids:
		var choice_id: String = String(raw_choice_id)
		if choice_id.is_empty() or not entries_by_id.has(choice_id):
			clear()
			return false
		choices.append(
			(entries_by_id[choice_id] as Dictionary).duplicate(true)
		)
	if _choice_ids(choices).size() != candidate_count:
		clear()
		return false
	choices.sort_custom(_sort_entries_by_id)
	_active_request = {
		"pool_id": pool_id,
		"trigger_id": trigger_id,
		"candidate_count": candidate_count,
		"choices": choices,
	}
	return true


func snapshot() -> Dictionary:
	if _active_request.is_empty():
		return {}
	return {
		"pool_id": String(_active_request.get("pool_id", "")),
		"trigger_id": String(_active_request.get("trigger_id", "")),
		"candidate_count": int(
			_active_request.get("candidate_count", 0)
		),
		"choice_ids": _choice_ids(
			_typed_entries(_active_request.get("choices", []))
		),
	}


func choices() -> Array[Dictionary]:
	return _typed_entries(_active_request.get("choices", []))


func is_busy() -> bool:
	return not _active_request.is_empty()


func clear() -> void:
	_active_request.clear()


func _failure(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
	}


func _typed_entries(raw_entries: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_entries is Array:
		return result
	for raw_entry: Variant in raw_entries as Array:
		if raw_entry is Dictionary:
			result.append((raw_entry as Dictionary).duplicate(true))
	return result


func _choice_ids(choices: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for choice: Dictionary in choices:
		var choice_id: String = String(choice.get("id", ""))
		if choice_id.is_empty() or seen.has(choice_id):
			continue
		seen[choice_id] = true
		result.append(choice_id)
	return result


func _sort_entries_by_id(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("id", "")) < String(right.get("id", ""))
