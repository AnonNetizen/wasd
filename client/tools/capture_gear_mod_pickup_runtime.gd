extends Node


const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const OUTPUT_PATH: String = (
	"res://tests/screenshots/gear_mod_pickup_runtime.png"
)
const CYAN: Color = Color("68bcdd")
const BOOT_FRAMES: int = 12


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_capture")


func _capture() -> void:
	var run_loop: Node = null
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		run_loop = _find_node_by_name(
			get_tree().root,
			"GameplayRunLoop"
		)
		if run_loop != null:
			break
	if run_loop == null:
		_fail("GameplayRunLoop was not ready for capture")
		return
	var player: Node2D = _find_node_by_name(
		run_loop,
		"Player"
	) as Node2D
	if player == null:
		_fail("Player was not ready for capture")
		return
	var spawn_position: Vector2 = player.global_position + Vector2(120.0, 0.0)
	var spawn_result: Dictionary = run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		spawn_position
	) as Dictionary
	if not bool(spawn_result.get("ok", false)):
		_fail("Gear Mod pickup spawn failed: %s" % spawn_result)
		return
	for _index: int in range(10):
		await get_tree().process_frame
	RenderingServer.force_draw(true)
	RenderingServer.force_sync()
	await get_tree().process_frame
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		_fail("runtime viewport texture is unavailable")
		return
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		_fail("runtime viewport image is unavailable")
		return
	var screen_position: Vector2 = (
		get_viewport().get_canvas_transform() * spawn_position
	)
	var probe_result: Dictionary = _probe_pickup(
		image,
		Vector2i(roundi(screen_position.x), roundi(screen_position.y))
	)
	if int(probe_result.get("cyan_pixels", 0)) < 10:
		_fail("cyan rim probe failed: %s" % probe_result)
		return
	if int(probe_result.get("fill_pixels", 0)) < 8:
		_fail("star-window fill probe failed: %s" % probe_result)
		return
	var cyan_bounds: Rect2i = probe_result.get(
		"cyan_bounds",
		Rect2i()
	) as Rect2i
	if (
		cyan_bounds.size.x < 34
		or cyan_bounds.size.x > 48
		or cyan_bounds.size.y < 34
		or cyan_bounds.size.y > 48
	):
		_fail("40 px CPU extent probe failed: %s" % probe_result)
		return
	var absolute_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	var output_dir: String = absolute_path.get_base_dir()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		output_dir
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("could not create screenshot directory: %s" % directory_error)
		return
	var save_error: Error = image.save_png(absolute_path)
	if save_error != OK:
		_fail("could not save runtime screenshot: %s" % save_error)
		return
	print(
		"[GearModPickupCapture] passed; cyan_pixels=%d fill_pixels=%d cyan_bounds=%s path=%s"
		% [
			int(probe_result.get("cyan_pixels", 0)),
			int(probe_result.get("fill_pixels", 0)),
			str(cyan_bounds),
			absolute_path,
		]
	)
	get_tree().quit(0)


func _probe_pickup(image: Image, center: Vector2i) -> Dictionary:
	var cyan_pixels: int = 0
	var fill_pixels: int = 0
	var minimum := Vector2i(999999, 999999)
	var maximum := Vector2i(-999999, -999999)
	var cyan_minimum := Vector2i(999999, 999999)
	var cyan_maximum := Vector2i(-999999, -999999)
	var image_bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for offset_x: int in range(-32, 33):
		for offset_y: int in range(-32, 33):
			var pixel_position := center + Vector2i(offset_x, offset_y)
			if not image_bounds.has_point(pixel_position):
				continue
			var pixel: Color = image.get_pixelv(pixel_position)
			var cyan_error: float = (
				absf(pixel.r - CYAN.r)
				+ absf(pixel.g - CYAN.g)
				+ absf(pixel.b - CYAN.b)
			)
			var is_cyan: bool = cyan_error < 0.34
			var is_fill: bool = (
				not is_cyan
				and pixel.b > 0.12
				and pixel.r + pixel.g + pixel.b > 0.24
			)
			if not is_cyan and not is_fill:
				continue
			cyan_pixels += 1 if is_cyan else 0
			fill_pixels += 1 if is_fill else 0
			if is_cyan:
				cyan_minimum.x = mini(cyan_minimum.x, pixel_position.x)
				cyan_minimum.y = mini(cyan_minimum.y, pixel_position.y)
				cyan_maximum.x = maxi(cyan_maximum.x, pixel_position.x)
				cyan_maximum.y = maxi(cyan_maximum.y, pixel_position.y)
			minimum.x = mini(minimum.x, pixel_position.x)
			minimum.y = mini(minimum.y, pixel_position.y)
			maximum.x = maxi(maximum.x, pixel_position.x)
			maximum.y = maxi(maximum.y, pixel_position.y)
	var bounds := Rect2i()
	if maximum.x >= minimum.x and maximum.y >= minimum.y:
		bounds = Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	var cyan_bounds := Rect2i()
	if cyan_maximum.x >= cyan_minimum.x and cyan_maximum.y >= cyan_minimum.y:
		cyan_bounds = Rect2i(
			cyan_minimum,
			cyan_maximum - cyan_minimum + Vector2i.ONE
		)
	return {
		"cyan_pixels": cyan_pixels,
		"fill_pixels": fill_pixels,
		"bounds": bounds,
		"cyan_bounds": cyan_bounds,
	}


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	push_error("[GearModPickupCapture] %s" % message)
	get_tree().quit(1)
