@tool
extends Control

const ASSET_DIR := "res://assets/bitmap_ai"
const PREVIEW_PATHS := {
	"PreviewRow/NormalColumn/NormalPreview": "ai_hive_button_normal.png",
	"PreviewRow/HoverColumn/HoverPreview": "ai_hive_button_hover.png",
	"PreviewRow/PressedColumn/PressedPreview": "ai_hive_button_pressed.png",
	"PreviewRow/DisabledColumn/DisabledPreview": "ai_hive_button_disabled.png",
}

func _ready() -> void:
	_apply_textures()

func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_EDITOR_POST_SAVE:
		call_deferred("_apply_textures")
	elif what == NOTIFICATION_EDITOR_PRE_SAVE:
		_clear_textures()

func _apply_textures() -> void:
	var normal := _load_image_texture("%s/ai_hive_button_normal.png" % ASSET_DIR)
	var hover := _load_image_texture("%s/ai_hive_button_hover.png" % ASSET_DIR)
	var pressed := _load_image_texture("%s/ai_hive_button_pressed.png" % ASSET_DIR)
	var disabled := _load_image_texture("%s/ai_hive_button_disabled.png" % ASSET_DIR)

	var button := get_node_or_null("InteractiveButtonFrame/InteractiveTextureButton") as TextureButton
	if button != null:
		button.texture_normal = normal
		button.texture_hover = hover
		button.texture_pressed = pressed
		button.texture_disabled = disabled

	for preview_path in PREVIEW_PATHS:
		_set_texture_rect(preview_path, _load_image_texture("%s/%s" % [ASSET_DIR, PREVIEW_PATHS[preview_path]]))

func _clear_textures() -> void:
	var button := get_node_or_null("InteractiveButtonFrame/InteractiveTextureButton") as TextureButton
	if button != null:
		button.texture_normal = null
		button.texture_hover = null
		button.texture_pressed = null
		button.texture_disabled = null

	for preview_path in PREVIEW_PATHS:
		_set_texture_rect(preview_path, null)

func _set_texture_rect(path: NodePath, texture: Texture2D) -> void:
	var rect := get_node_or_null(path) as TextureRect
	if rect != null:
		rect.texture = texture

func _load_image_texture(path: String) -> ImageTexture:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("Failed to load bitmap button texture: %s (%s)" % [path, error])
		return ImageTexture.new()
	return ImageTexture.create_from_image(image)
