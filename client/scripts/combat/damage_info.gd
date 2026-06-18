# Doc: docs/代码/combat.md
# Authority: docs/游戏设计文档.md §9.15.1, docs/词表与契约.md §9
class_name DamageInfo
extends RefCounted


var amount: float = 0.0
var damage_type: String = ""
var source: Node = null
var target: Node = null
var source_team: String = ""
var target_team: String = ""
var flags: PackedStringArray = []


func setup(
	damage_amount: float,
	type_id: String,
	damage_source: Node,
	damage_target: Node,
	source_team_id: String = "",
	target_team_id: String = "",
	damage_flags: PackedStringArray = PackedStringArray()
) -> DamageInfo:
	amount = maxf(damage_amount, 0.0)
	damage_type = type_id
	source = damage_source
	target = damage_target
	source_team = source_team_id
	target_team = target_team_id
	flags = damage_flags.duplicate()
	return self
