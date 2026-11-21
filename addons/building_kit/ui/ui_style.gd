class_name PKUIStyle
extends RefCounted
## Colours and boxes of the kit's interface, in one place. Change the static values before
## the HUD is created, or give the HUD your own Theme (it is applied over these).

static var panel_color := Color(0.09, 0.1, 0.13, 0.88)
static var panel_border := Color(1, 1, 1, 0.08)
static var button_color := Color(0.17, 0.19, 0.24, 1.0)
static var button_hover := Color(0.24, 0.27, 0.34, 1.0)
static var accent := Color(0.98, 0.72, 0.28)
static var text_color := Color(0.93, 0.94, 0.96)
static var muted_text := Color(0.66, 0.69, 0.75)
static var good := Color(0.45, 0.9, 0.55)
static var bad := Color(1.0, 0.45, 0.4)
static var corner_radius := 10


static func panel() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = panel_color
	box.border_color = panel_border
	box.set_border_width_all(1)
	box.set_corner_radius_all(corner_radius)
	box.set_content_margin_all(10)
	box.shadow_color = Color(0, 0, 0, 0.25)
	box.shadow_size = 6
	return box


static func button(color: Color, border := Color(0, 0, 0, 0), border_width := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(corner_radius - 3)
	box.set_content_margin_all(6)
	box.border_color = border
	box.set_border_width_all(border_width)
	return box


## A theme for every kit control (labels, buttons, tabs, tooltips).
static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	theme.set_color(&"font_color", &"Label", text_color)
	theme.set_color(&"font_color", &"Button", text_color)
	theme.set_color(&"font_hover_color", &"Button", Color.WHITE)
	theme.set_color(&"font_pressed_color", &"Button", Color(0.1, 0.08, 0.04))
	theme.set_color(&"font_hover_pressed_color", &"Button", Color(0.1, 0.08, 0.04))
	theme.set_stylebox(&"normal", &"Button", button(button_color))
	theme.set_stylebox(&"hover", &"Button", button(button_hover))
	theme.set_stylebox(&"pressed", &"Button", button(accent))
	theme.set_stylebox(&"hover_pressed", &"Button", button(accent.lightened(0.1)))
	theme.set_stylebox(&"disabled", &"Button", button(button_color.darkened(0.3)))
	theme.set_stylebox(&"focus", &"Button", button(Color(0, 0, 0, 0), accent, 2))
	theme.set_stylebox(&"panel", &"PanelContainer", panel())
	theme.set_stylebox(&"panel", &"TooltipPanel", panel())
	theme.set_color(&"font_color", &"TooltipLabel", text_color)
	theme.set_stylebox(&"tab_selected", &"TabBar", button(accent))
	theme.set_stylebox(&"tab_unselected", &"TabBar", button(button_color))
	theme.set_stylebox(&"tab_hovered", &"TabBar", button(button_hover))
	theme.set_stylebox(&"tab_focus", &"TabBar", button(Color(0, 0, 0, 0), accent, 2))
	theme.set_color(&"font_selected_color", &"TabBar", Color(0.1, 0.08, 0.04))
	theme.set_color(&"font_unselected_color", &"TabBar", muted_text)
	theme.set_color(&"font_hovered_color", &"TabBar", Color.WHITE)
	theme.set_constant(&"h_separation", &"TabBar", 6)
	return theme
