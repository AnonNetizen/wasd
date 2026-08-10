# Doc: docs/代码/module_world_manager.md
class_name ModuleChunkStreamingController
extends RefCounted
## Pure coordinator for preloaded generated scenes and scene-authored ModuleChunk reuse.
## Assignment, map hashing, snapshot wire and world state remain owned by ModuleWorldManager.


enum PrepareError {
	NONE,
	LOAD_FAILED,
	ROOT_INVALID,
	METADATA_STALE,
	EMPTY,
}


class Configure extends RefCounted:
	var generated_scene_paths_by_id: Dictionary = {}
	var chunk_pool: Array[ModuleChunk] = []
	var expected_chunk_count: int = 0


class PreparedAssignment extends RefCounted:
	var _is_valid: bool = false
	var _error_code: int = PrepareError.NONE
	var _template_id: String = ""
	var _scene_cache: Dictionary = {}


	func is_valid() -> bool:
		return _is_valid


	func error_code() -> int:
		return _error_code


	func template_id() -> String:
		return _template_id


	func scene_count() -> int:
		return _scene_cache.size()


	func has_scene(template_id_value: String) -> bool:
		return _scene_cache.has(template_id_value)


	func _succeed(scene_cache: Dictionary) -> void:
		_is_valid = true
		_error_code = PrepareError.NONE
		_template_id = ""
		_scene_cache = scene_cache.duplicate()


	func _fail(error_value: int, template_id_value: String = "") -> void:
		_is_valid = false
		_error_code = error_value
		_template_id = template_id_value
		_scene_cache.clear()


	func _cache_copy() -> Dictionary:
		return _scene_cache.duplicate()


class StreamRequest extends RefCounted:
	var center_coord: Vector2i = Vector2i(-1, -1)
	var pinned_coords: Array[Vector2i] = []
	var columns: int = 0
	var rows: int = 0
	var active_radius: int = 0
	var cell_size: float = 1.0
	var world_origin: Vector2 = Vector2.ZERO
	var assignment_provider: Callable = Callable()
	var masked_edges_provider: Callable = Callable()


class StreamChange extends RefCounted:
	var _activated: Array[Vector2i] = []
	var _deactivated: Array[Vector2i] = []
	var _configure_failed: Array[Vector2i] = []
	var _pool_exhausted_count: int = 0


	func activated_coords() -> Array[Vector2i]:
		return _copy_coords(_activated)


	func deactivated_coords() -> Array[Vector2i]:
		return _copy_coords(_deactivated)


	func configure_failed_coords() -> Array[Vector2i]:
		return _copy_coords(_configure_failed)


	func pool_exhausted_count() -> int:
		return _pool_exhausted_count


	func _append_activated(module_coord: Vector2i) -> void:
		_activated.append(module_coord)


	func _append_deactivated(module_coord: Vector2i) -> void:
		_deactivated.append(module_coord)


	func _append_configure_failed(module_coord: Vector2i) -> void:
		_configure_failed.append(module_coord)


	func _increment_pool_exhausted() -> void:
		_pool_exhausted_count += 1


	func _copy_coords(source: Array[Vector2i]) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		result.append_array(source)
		return result


var _generated_scene_paths_by_id: Dictionary = {}
var _packed_scene_cache: Dictionary = {}
var _active_chunks: Dictionary = {}
var _chunk_pool: Array[ModuleChunk] = []


## Reconfiguration always clears live mounts before replacing cache and pool inputs.
## The returned bool reports whether the supplied scene-authored pool has the
## requested exact size; callers retain their existing diagnostic wording.
func configure(configuration: Configure) -> bool:
	clear_active()
	_generated_scene_paths_by_id = (
		configuration.generated_scene_paths_by_id.duplicate()
	)
	_packed_scene_cache.clear()
	_chunk_pool.clear()
	for chunk: ModuleChunk in configuration.chunk_pool:
		_chunk_pool.append(chunk)
	if _chunk_pool.size() != configuration.expected_chunk_count:
		return false
	for chunk: ModuleChunk in _chunk_pool:
		chunk.clear()
	return true


func has_valid_generated_scene_paths(template_ids: Array[String]) -> bool:
	if template_ids.is_empty():
		return false
	for template_id: String in template_ids:
		var configured_value: Variant = _generated_scene_paths_by_id.get(
			template_id
		)
		if configured_value is PackedScene:
			continue
		if (
			not configured_value is String
			or not ResourceLoader.exists(
				String(configured_value),
				"PackedScene"
			)
		):
			return false
	return true


## Builds an isolated candidate cache. Live cache and mounted chunks are not
## changed until commit_prepared() is called by the owner after all validation.
func prepare_assignment(
	assignment_entries: Array[Dictionary]
) -> PreparedAssignment:
	var prepared := PreparedAssignment.new()
	var candidate_cache: Dictionary = {}
	for entry: Dictionary in assignment_entries:
		var template_id: String = String(entry.get("template_id", ""))
		if candidate_cache.has(template_id):
			continue
		var packed: PackedScene = _load_generated_scene(template_id)
		if packed == null:
			prepared._fail(PrepareError.LOAD_FAILED, template_id)
			return prepared
		var probe: Node = packed.instantiate()
		if not probe is GeneratedModuleScene:
			if probe != null:
				probe.free()
			prepared._fail(PrepareError.ROOT_INVALID, template_id)
			return prepared
		var generated: GeneratedModuleScene = probe as GeneratedModuleScene
		var metadata_valid: bool = (
			generated.baker_schema_version
			== GeneratedModuleScene.BAKER_SCHEMA_VERSION
			and generated.module_id == template_id
			and generated.module_rotation_degrees == 0
		)
		generated.free()
		if not metadata_valid:
			prepared._fail(PrepareError.METADATA_STALE, template_id)
			return prepared
		candidate_cache[template_id] = packed
	if candidate_cache.is_empty():
		prepared._fail(PrepareError.EMPTY)
		return prepared
	prepared._succeed(candidate_cache)
	return prepared


func commit_prepared(prepared: PreparedAssignment) -> bool:
	if prepared == null or not prepared.is_valid():
		return false
	_packed_scene_cache = prepared._cache_copy()
	return true


## Unmounts every no-longer-desired chunk first, then mounts desired slots in
## global y -> x order. Individual pool/configure failures preserve successes.
func refresh(request: StreamRequest) -> StreamChange:
	var change := StreamChange.new()
	var desired_coords: Dictionary = _desired_coords(request)
	for module_coord: Vector2i in active_module_coords():
		if desired_coords.has(module_coord):
			continue
		var chunk: ModuleChunk = _active_chunks.get(module_coord) as ModuleChunk
		if chunk != null:
			change._append_deactivated(module_coord)
			chunk.clear()
		_active_chunks.erase(module_coord)

	var failed_chunks: Dictionary = {}
	for row_index: int in range(request.rows):
		for column_index: int in range(request.columns):
			var module_coord := Vector2i(column_index, row_index)
			if (
				not desired_coords.has(module_coord)
				or _active_chunks.has(module_coord)
			):
				continue
			var available_chunk: ModuleChunk = _available_chunk(failed_chunks)
			if available_chunk == null:
				change._increment_pool_exhausted()
				continue
			if not _mount_chunk(available_chunk, module_coord, request):
				available_chunk.clear()
				failed_chunks[available_chunk] = true
				change._append_configure_failed(module_coord)
				continue
			_active_chunks[module_coord] = available_chunk
			change._append_activated(module_coord)
	return change


func clear_active() -> Array[Vector2i]:
	var deactivated: Array[Vector2i] = active_module_coords()
	for module_coord: Vector2i in deactivated:
		var chunk: ModuleChunk = _active_chunks.get(module_coord) as ModuleChunk
		if chunk != null:
			chunk.clear()
	_active_chunks.clear()
	return deactivated


func clear_cache() -> void:
	_packed_scene_cache.clear()


func active_module_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for module_coord: Vector2i in _active_chunks.keys():
		result.append(module_coord)
	result.sort_custom(_coord_row_major_less)
	return result


func is_module_active(module_coord: Vector2i) -> bool:
	return _active_chunks.has(module_coord)


func active_count() -> int:
	return _active_chunks.size()


func chunk_pool_size() -> int:
	return _chunk_pool.size()


func preloaded_scene_count() -> int:
	return _packed_scene_cache.size()


func has_preloaded_scene(template_id: String) -> bool:
	return _packed_scene_cache.has(template_id)


func _load_generated_scene(template_id: String) -> PackedScene:
	var configured_value: Variant = _generated_scene_paths_by_id.get(
		template_id
	)
	if configured_value is PackedScene:
		return configured_value as PackedScene
	if configured_value is String:
		return ResourceLoader.load(
			String(configured_value),
			"PackedScene"
		) as PackedScene
	return null


func _desired_coords(request: StreamRequest) -> Dictionary:
	var result: Dictionary = {}
	if _is_coord_valid(request.center_coord, request.columns, request.rows):
		var active_radius: int = maxi(request.active_radius, 0)
		for row_offset: int in range(-active_radius, active_radius + 1):
			for column_offset: int in range(
				-active_radius,
				active_radius + 1
			):
				var module_coord: Vector2i = (
					request.center_coord
					+ Vector2i(column_offset, row_offset)
				)
				if _is_coord_valid(
					module_coord,
					request.columns,
					request.rows
				):
					result[module_coord] = true
	for module_coord: Vector2i in request.pinned_coords:
		if _is_coord_valid(module_coord, request.columns, request.rows):
			result[module_coord] = true
	return result


func _available_chunk(excluded_chunks: Dictionary) -> ModuleChunk:
	for chunk: ModuleChunk in _chunk_pool:
		if (
			not excluded_chunks.has(chunk)
			and not _active_chunks.values().has(chunk)
		):
			return chunk
	return null


func _mount_chunk(
	chunk: ModuleChunk,
	module_coord: Vector2i,
	request: StreamRequest
) -> bool:
	var entry: Dictionary = {}
	if request.assignment_provider.is_valid():
		var raw_entry: Variant = request.assignment_provider.call(module_coord)
		if raw_entry is Dictionary:
			entry = raw_entry as Dictionary
	var masked_edges: Array = []
	if request.masked_edges_provider.is_valid():
		var raw_edges: Variant = request.masked_edges_provider.call(
			module_coord
		)
		if raw_edges is Array:
			masked_edges = raw_edges as Array
	var template_id: String = String(entry.get("template_id", ""))
	var generated_scene: PackedScene = _packed_scene_cache.get(
		template_id
	) as PackedScene
	return chunk.configure(
		generated_scene,
		module_coord,
		int(entry.get("rotation", 0)),
		masked_edges,
		request.cell_size,
		request.world_origin
	)


func _is_coord_valid(
	module_coord: Vector2i,
	columns: int,
	rows: int
) -> bool:
	return (
		module_coord.x >= 0
		and module_coord.y >= 0
		and module_coord.x < columns
		and module_coord.y < rows
	)


func _coord_row_major_less(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or left.y == right.y and left.x < right.x
