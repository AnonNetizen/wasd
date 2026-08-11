# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #95, ADR #96, ADR #197
class_name EnemyStatusHostRuntime
extends RefCounted


const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")


var _owned_tag_counts: Dictionary = {}
var _status_effect_component: Node = null


func bind(status_effect_component: Node, ability_tag_owner: Node) -> bool:
	_status_effect_component = status_effect_component
	return refresh(ability_tag_owner)


func refresh(ability_tag_owner: Node) -> bool:
	if not _has_valid_status_effect_component():
		_status_effect_component = null
		return false
	_status_effect_component.call(
		"configure_ability_tag_owner",
		ability_tag_owner
	)
	return true


func clear_for_reuse() -> void:
	if _has_valid_status_effect_component():
		_status_effect_component.call("clear", false)
	_owned_tag_counts.clear()


func clear_effects_before_restore() -> void:
	if _has_valid_status_effect_component():
		_status_effect_component.call("clear", false)


func add_owned_tag(tag_id: String) -> bool:
	if not _is_valid_ability_tag(tag_id):
		return false
	_owned_tag_counts[tag_id] = int(
		_owned_tag_counts.get(tag_id, 0)
	) + 1
	return true


func remove_owned_tag(tag_id: String) -> bool:
	if not _owned_tag_counts.has(tag_id):
		return false
	var next_count: int = int(_owned_tag_counts[tag_id]) - 1
	if next_count <= 0:
		_owned_tag_counts.erase(tag_id)
	else:
		_owned_tag_counts[tag_id] = next_count
	return true


func has_owned_tag(tag_id: String) -> bool:
	return int(_owned_tag_counts.get(tag_id, 0)) > 0


func owned_tags() -> Array[String]:
	return _sorted_string_keys(_owned_tag_counts)


func owned_tag_counts_snapshot() -> Dictionary:
	return _owned_tag_counts.duplicate(true)


func apply_status_effect(status_effect: Variant) -> Dictionary:
	if not _has_valid_status_effect_component():
		return {
			"applied": false,
			"reason": "status_component_unavailable",
		}
	return _status_effect_component.call(
		"apply",
		status_effect
	) as Dictionary


func active_statuses() -> Array[String]:
	if not _has_valid_status_effect_component():
		return []
	return _status_effect_component.call(
		"active_statuses"
	) as Array[String]


func status_summary() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_effects: Variant = status_effect_snapshot().get("effects", [])
	if not raw_effects is Array:
		return result
	for raw_effect: Variant in raw_effects as Array:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect as Dictionary
		var status_id: String = String(effect.get("status", ""))
		if status_id.is_empty():
			continue
		result.append({
			"id": status_id,
			"name_key": "status_%s_name" % status_id,
			"stacks": maxi(int(effect.get("stack_count", 1)), 1),
			"remaining": maxf(float(effect.get("remaining", 0.0)), 0.0),
		})
	return result


func status_stat_multiplier(stat_id: String) -> float:
	if (
		not _has_valid_status_effect_component()
		or not _status_effect_component.has_method("stat_multiplier")
	):
		return 1.0
	return maxf(
		float(_status_effect_component.call("stat_multiplier", stat_id)),
		0.0
	)


func status_stack_count(status_id: String) -> int:
	if (
		not _has_valid_status_effect_component()
		or not _status_effect_component.has_method("stack_count")
	):
		return 0
	return int(_status_effect_component.call("stack_count", status_id))


func can_query_incoming_damage_multiplier() -> bool:
	return (
		_has_valid_status_effect_component()
		and _status_effect_component.has_method(
			"incoming_damage_multiplier"
		)
	)


func incoming_damage_multiplier(source_team: String) -> float:
	if not can_query_incoming_damage_multiplier():
		return 1.0
	return maxf(
		float(
			_status_effect_component.call(
				"incoming_damage_multiplier",
				source_team
			)
		),
		0.0
	)


func status_effect_snapshot() -> Dictionary:
	if not _has_valid_status_effect_component():
		return {}
	return _status_effect_component.call("snapshot") as Dictionary


func restore_from_actor_snapshot(snapshot_data: Dictionary) -> void:
	_owned_tag_counts.clear()
	var raw_tag_counts: Variant = snapshot_data.get(
		"owned_tag_counts",
		{}
	)
	var has_owned_tag_snapshot: bool = (
		snapshot_data.has("owned_tag_counts")
		and raw_tag_counts is Dictionary
	)
	if has_owned_tag_snapshot:
		for tag_id: Variant in (raw_tag_counts as Dictionary).keys():
			var count: int = maxi(
				int((raw_tag_counts as Dictionary)[tag_id]),
				0
			)
			if count <= 0:
				continue
			var tag: String = String(tag_id)
			if _is_valid_ability_tag(tag):
				_owned_tag_counts[tag] = count
	else:
		var raw_owned_tags: Variant = snapshot_data.get(
			"owned_tags",
			[]
		)
		has_owned_tag_snapshot = raw_owned_tags is Array
		if raw_owned_tags is Array:
			for tag_id: Variant in raw_owned_tags as Array:
				add_owned_tag(String(tag_id))

	var raw_status_effects: Variant = snapshot_data.get(
		"status_effects",
		{}
	)
	if (
		_has_valid_status_effect_component()
		and raw_status_effects is Dictionary
	):
		_status_effect_component.call(
			"restore_snapshot",
			raw_status_effects,
			not has_owned_tag_snapshot
		)


func _has_valid_status_effect_component() -> bool:
	return (
		_status_effect_component != null
		and is_instance_valid(_status_effect_component)
	)


func _is_valid_ability_tag(tag_id: String) -> bool:
	if tag_id.is_empty():
		return false
	return ABILITY_TAGS.VALUES.has(tag_id)


func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source.keys():
		result.append(String(key))
	result.sort()
	return result
