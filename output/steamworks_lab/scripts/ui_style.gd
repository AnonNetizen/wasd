class_name SteamLabUiStyle
extends RefCounted

const BG_COLOR := Color(0.025, 0.037, 0.038, 1.0)
const PANEL_COLOR := Color(0.043, 0.065, 0.062, 0.94)
const PANEL_DARK_COLOR := Color(0.021, 0.029, 0.031, 0.96)
const PANEL_BORDER_COLOR := Color(0.28, 0.82, 0.58, 0.58)
const TEXT_COLOR := Color(0.90, 0.98, 0.91, 0.96)
const MUTED_TEXT_COLOR := Color(0.55, 0.68, 0.62, 0.86)
const SLIME_COLOR := Color(0.40, 0.96, 0.58, 1.0)
const CYAN_COLOR := Color(0.32, 0.88, 0.94, 1.0)
const AMBER_COLOR := Color(1.0, 0.74, 0.28, 1.0)
const CORAL_COLOR := Color(1.0, 0.38, 0.34, 1.0)
const DISABLED_COLOR := Color(0.25, 0.31, 0.29, 0.62)


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14

	theme.set_color("font_color", "Label", TEXT_COLOR)
	theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.46))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	theme.set_color("font_color", "Button", TEXT_COLOR)
	theme.set_color("font_hover_color", "Button", Color(0.97, 1.0, 0.86, 1.0))
	theme.set_color("font_pressed_color", "Button", Color(0.04, 0.08, 0.06, 1.0))
	theme.set_color("font_disabled_color", "Button", Color(0.47, 0.55, 0.51, 0.76))
	theme.set_font_size("font_size", "Button", 15)
	theme.set_stylebox("normal", "Button", button_style(PANEL_COLOR, PANEL_BORDER_COLOR))
	theme.set_stylebox("hover", "Button", button_style(Color(0.07, 0.16, 0.12, 0.98), SLIME_COLOR, 2))
	theme.set_stylebox("pressed", "Button", button_style(Color(0.39, 0.92, 0.56, 0.96), Color(0.92, 1.0, 0.72, 1.0), 2))
	theme.set_stylebox("disabled", "Button", button_style(Color(0.08, 0.10, 0.10, 0.64), DISABLED_COLOR))
	theme.set_stylebox("focus", "Button", focus_style())

	theme.set_color("font_color", "LineEdit", TEXT_COLOR)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED_TEXT_COLOR)
	theme.set_color("caret_color", "LineEdit", AMBER_COLOR)
	theme.set_stylebox("normal", "LineEdit", input_style(false))
	theme.set_stylebox("focus", "LineEdit", input_style(true))
	theme.set_stylebox("read_only", "LineEdit", input_style(false))

	theme.set_stylebox("panel", "PanelContainer", panel_style(PANEL_COLOR, PANEL_BORDER_COLOR, 8, 1))
	theme.set_stylebox("separator", "HSeparator", separator_style())
	return theme


static func apply_panel(panel: PanelContainer, variant: String = "panel") -> void:
	match variant:
		"hero":
			panel.add_theme_stylebox_override("panel", panel_style(Color(0.035, 0.052, 0.050, 0.96), SLIME_COLOR, 8, 2, 0.38))
		"section":
			panel.add_theme_stylebox_override("panel", panel_style(Color(0.038, 0.055, 0.056, 0.90), Color(0.22, 0.52, 0.45, 0.52), 7, 1, 0.20))
		"danger":
			panel.add_theme_stylebox_override("panel", panel_style(Color(0.070, 0.042, 0.044, 0.94), CORAL_COLOR, 8, 2, 0.28))
		_:
			panel.add_theme_stylebox_override("panel", panel_style(PANEL_COLOR, PANEL_BORDER_COLOR, 8, 1))


static func apply_button(button: Button, primary: bool = false) -> void:
	if primary:
		button.add_theme_stylebox_override("normal", button_style(Color(0.10, 0.28, 0.18, 0.98), SLIME_COLOR, 2, 0.32))
		button.add_theme_stylebox_override("hover", button_style(Color(0.16, 0.42, 0.25, 1.0), Color(0.88, 1.0, 0.68, 1.0), 2, 0.42))
		button.add_theme_stylebox_override("pressed", button_style(Color(0.72, 1.0, 0.44, 1.0), Color(0.98, 1.0, 0.80, 1.0), 2, 0.30))
		button.add_theme_color_override("font_pressed_color", Color(0.04, 0.09, 0.04, 1.0))
	else:
		button.add_theme_stylebox_override("normal", button_style(PANEL_COLOR, PANEL_BORDER_COLOR))
		button.add_theme_stylebox_override("hover", button_style(Color(0.07, 0.14, 0.13, 0.98), CYAN_COLOR, 2, 0.24))
		button.add_theme_stylebox_override("pressed", button_style(Color(0.38, 0.88, 0.86, 0.94), Color(0.90, 1.0, 0.95, 1.0), 2, 0.22))


static func apply_input(input: LineEdit) -> void:
	input.add_theme_stylebox_override("normal", input_style(false))
	input.add_theme_stylebox_override("focus", input_style(true))
	input.add_theme_color_override("font_color", TEXT_COLOR)
	input.add_theme_color_override("font_placeholder_color", MUTED_TEXT_COLOR)


static func panel_style(
	fill_color: Color,
	border_color: Color,
	corner_radius: int,
	border_width: int,
	shadow_alpha: float = 0.24
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style


static func button_style(
	fill_color: Color,
	border_color: Color,
	border_width: int = 1,
	shadow_alpha: float = 0.18
) -> StyleBoxFlat:
	var style := panel_style(fill_color, border_color, 7, border_width, shadow_alpha)
	style.content_margin_left = 16.0
	style.content_margin_top = 8.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 8.0
	return style


static func input_style(focused: bool) -> StyleBoxFlat:
	var style := panel_style(
		PANEL_DARK_COLOR,
		AMBER_COLOR if focused else Color(0.18, 0.40, 0.36, 0.70),
		6,
		2 if focused else 1,
		0.16
	)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style


static func focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = AMBER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style


static func separator_style() -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = Color(0.24, 0.76, 0.55, 0.46)
	style.thickness = 1
	return style
