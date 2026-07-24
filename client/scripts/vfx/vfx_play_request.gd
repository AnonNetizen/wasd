# Doc: docs/代码/visual_effects.md
class_name VfxPlayRequest
extends RefCounted
## Typed presentation-only payload passed from semantic feedback controllers to VfxHost.


const VFX_ANCHORS := preload("res://scripts/contracts/vfx_anchors.gd")

var owner: Node = null
var anchor: String = VFX_ANCHORS.CENTER
var world_position: Vector2 = Vector2.ZERO
var use_world_position: bool = false
var rotation: float = 0.0
var scale_value: Vector2 = Vector2.ONE
var follow_owner: bool = true
var seed: int = 0
var payload: Dictionary = {}


static func from_context(context: Dictionary) -> VfxPlayRequest:
	var request := VfxPlayRequest.new()
	var raw_owner: Variant = context.get("owner", context.get("target"))
	if raw_owner is Node:
		request.owner = raw_owner as Node
	request.anchor = String(context.get("anchor", VFX_ANCHORS.CENTER))
	var raw_position: Variant = context.get("world_position")
	if raw_position is Vector2:
		request.world_position = raw_position as Vector2
		request.use_world_position = true
	request.rotation = float(context.get("rotation", 0.0))
	var raw_scale: Variant = context.get("scale", Vector2.ONE)
	if raw_scale is Vector2:
		request.scale_value = raw_scale as Vector2
	elif raw_scale is float or raw_scale is int:
		request.scale_value = Vector2.ONE * float(raw_scale)
	request.follow_owner = bool(context.get("follow_owner", true))
	request.seed = int(context.get("seed", 0))
	request.payload = context.duplicate(true)
	return request


func clone() -> VfxPlayRequest:
	var result := VfxPlayRequest.new()
	result.owner = owner
	result.anchor = anchor
	result.world_position = world_position
	result.use_world_position = use_world_position
	result.rotation = rotation
	result.scale_value = scale_value
	result.follow_owner = follow_owner
	result.seed = seed
	result.payload = payload.duplicate(true)
	return result
