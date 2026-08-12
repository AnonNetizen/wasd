extends SmokeHarness


const MODULE_MINIMAP_SCRIPT := preload(
	"res://scripts/gameplay/module_minimap.gd"
)
const MODULE_PLACEMENT_TYPES := preload(
	"res://scripts/contracts/module_placement_types.gd"
)
const WORLD_EVENT_KINDS := preload(
	"res://scripts/contracts/world_event_kinds.gd"
)


func test_configure_keeps_registered_markers_for_unvisited_modules() -> void:
	var minimap: ModuleMinimap = MODULE_MINIMAP_SCRIPT.new()
	add_child_autofree(minimap)
	minimap.configure({
		"columns": 7,
		"rows": 7,
		"visited_slots": [Vector2i(1, 1), Vector2i(2, 2)],
		"interactable_markers": [
			_marker(Vector2i(1, 1), MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE),
			_marker(
				Vector2i(1, 1),
				MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_GOLD_SHRINE
			),
			_marker(Vector2i(2, 2), MODULE_PLACEMENT_TYPES.MODULE_PLACE_TELEPORTER),
			_marker(Vector2i(2, 2), MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT),
			_marker(
				Vector2i(3, 3),
				MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE
			),
			_marker(Vector2i(2, 2), MODULE_PLACEMENT_TYPES.MODULE_PLACE_HAZARD),
		],
	})

	assert_eq(minimap.interactable_markers().size(), 4)
	assert_eq(minimap.marker_kinds_at(Vector2i(1, 1)), [
		ModuleMinimap.MarkerKind.REWARD_CACHE,
		ModuleMinimap.MarkerKind.SHRINE,
	])
	assert_eq(minimap.marker_kinds_at(Vector2i(2, 2)), [
		ModuleMinimap.MarkerKind.TELEPORTER,
	])
	assert_eq(minimap.marker_kinds_at(Vector2i(3, 3)), [
		ModuleMinimap.MarkerKind.BEACON,
	])


func test_world_event_kinds_distinguish_shrines_from_beacons() -> void:
	var minimap: ModuleMinimap = MODULE_MINIMAP_SCRIPT.new()
	add_child_autofree(minimap)
	minimap.configure({
		"visited_slots": [
			Vector2i(0, 0),
			Vector2i(1, 0),
			Vector2i(2, 0),
			Vector2i(3, 0),
		],
		"interactable_markers": [
			_marker(
				Vector2i(0, 0),
				MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_BLOOD_SHRINE
			),
			_marker(
				Vector2i(1, 0),
				MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_SURVIVAL
			),
			_marker(
				Vector2i(2, 0),
				MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_CAPTURE
			),
			_marker(
				Vector2i(3, 0),
				MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE
			),
		],
	})

	assert_eq(minimap.marker_kinds_at(Vector2i(0, 0)), [
		ModuleMinimap.MarkerKind.SHRINE,
	])
	assert_eq(minimap.marker_kinds_at(Vector2i(1, 0)), [
		ModuleMinimap.MarkerKind.BEACON,
	])
	assert_eq(minimap.marker_kinds_at(Vector2i(2, 0)), [
		ModuleMinimap.MarkerKind.BEACON,
	])
	assert_eq(minimap.marker_kinds_at(Vector2i(3, 0)), [
		ModuleMinimap.MarkerKind.BEACON,
	])


func _marker(
	slot: Vector2i,
	placement_type: String,
	world_event_kind: String = ""
) -> Dictionary:
	var marker: Dictionary = {
		"slot": {"x": slot.x, "y": slot.y},
		"type": placement_type,
	}
	if not world_event_kind.is_empty():
		marker["world_event_kind"] = world_event_kind
	return marker
