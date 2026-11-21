extends Control

signal movement_changed(value: Vector2)
signal look_changed(delta: Vector2)
signal action_held(action: StringName, pressed: bool)
signal action_pressed(action: StringName)

const JOYSTICK_ICON := preload("res://Assets/UI/Kenney/InputPrompts/Generic/Default/generic_joystick.png")
const FINGER_ICON := preload("res://Assets/UI/Kenney/InputPrompts/Generic/Default/generic_button_finger.png")
const UP_ICON := preload("res://Assets/UI/Kenney/InputPrompts/Generic/Default/generic_stick_up.png")
const BUTTON_WIDTH := 70.0
const BUTTON_HEIGHT := 48.0
const STICK_RADIUS := 54.0

var touch_enabled := false
var _move_touch_id := -1
var _look_touch_id := -1
var _move_value := Vector2.ZERO
var _buttons: Dictionary = {}
var _captions: Dictionary = {}
var _reserved_controls: Array = []
var _menu_open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_enabled = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	visible = touch_enabled
	if not touch_enabled:
		return

	_create_button(&"place", "Colocar", FINGER_ICON, "Confirmar construção")
	_create_button(&"jump", "Pular", UP_ICON, "Pular")
	_create_button(&"interact", "Usar", FINGER_ICON, "Coletar recurso apontado")
	_create_button(&"sprint", "Correr", JOYSTICK_ICON, "Segure para correr")
	resized.connect(_layout_buttons)
	_layout_buttons()


func set_reserved_controls(controls: Array) -> void:
	_reserved_controls = controls


func set_menu_open(open: bool) -> void:
	_menu_open = open
	for button: Button in _buttons.values():
		button.visible = not open
	for caption: Label in _captions.values():
		caption.visible = not open
	queue_redraw()


func _create_button(action: StringName, label: String, icon: Texture2D, hint: String) -> void:
	var button := Button.new()
	button.name = "Touch_%s" % String(action)
	button.text = ""
	button.icon = _fit_icon(icon, 18)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.035, 0.07, 0.11, 0.70)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.08, 0.20, 0.28, 0.88)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.38, 0.48, 0.95)))
	var caption := Label.new()
	caption.name = "Caption"
	caption.text = label
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 8)
	caption.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.96))
	caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(button)
	add_child(caption)
	_buttons[action] = button
	_captions[action] = caption

	if action == &"jump" or action == &"sprint":
		button.button_down.connect(func() -> void: action_held.emit(action, true))
		button.button_up.connect(func() -> void: action_held.emit(action, false))
	else:
		button.pressed.connect(func() -> void: action_pressed.emit(action))


func _fit_icon(texture: Texture2D, maximum_size: int) -> Texture2D:
	if texture == null:
		return null
	var source_image := texture.get_image()
	if source_image == null or source_image.is_empty():
		return texture
	var image := source_image.duplicate() as Image
	var longest_side := maxi(image.get_width(), image.get_height())
	if longest_side <= maximum_size:
		return texture
	var ratio := float(maximum_size) / float(longest_side)
	var width := maxi(1, roundi(float(image.get_width()) * ratio))
	var height := maxi(1, roundi(float(image.get_height()) * ratio))
	image.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.78, 0.91, 1.0, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _layout_buttons() -> void:
	if _buttons.is_empty():
		return
	var two_columns := size.x >= 200.0
	var gap := 8.0
	var button_width := minf(BUTTON_WIDTH, maxf(48.0, (size.x - 24.0 - gap) * 0.5)) if two_columns else minf(BUTTON_WIDTH, maxf(44.0, size.x - 16.0))
	var button_height := BUTTON_HEIGHT
	var right := size.x - 10.0
	var positions: Dictionary = {}
	if two_columns:
		var left_col := maxf(8.0, right - button_width * 2.0 - gap)
		var upper_row := size.y - button_height * 2.0 - gap - 12.0
		positions[&"place"] = Vector2(left_col, upper_row)
		positions[&"jump"] = Vector2(right - button_width, upper_row)
		positions[&"interact"] = Vector2(left_col, size.y - button_height - 12.0)
		positions[&"sprint"] = Vector2(right - button_width, size.y - button_height - 12.0)
	else:
		var x := maxf(8.0, right - button_width)
		var index := 0
		for action: StringName in [&"place", &"jump", &"interact", &"sprint"]:
			positions[action] = Vector2(x, size.y - 12.0 - (index + 1) * button_height - index * 6.0)
			index += 1
	for action: StringName in _buttons:
		var button: Button = _buttons[action]
		var button_position: Vector2 = positions[action]
		button.custom_minimum_size = Vector2(button_width, button_height)
		button.offset_left = button_position.x
		button.offset_top = button_position.y
		button.offset_right = button_position.x + button_width
		button.offset_bottom = button_position.y + button_height
		var caption: Label = _captions[action]
		caption.offset_left = button_position.x
		caption.offset_top = button_position.y + button_height - 16.0
		caption.offset_right = button_position.x + button_width
		caption.offset_bottom = button_position.y + button_height
	queue_redraw()


func _draw() -> void:
	if not touch_enabled or size.y <= 0.0 or _menu_open:
		return
	var center := _stick_center()
	var radius := _stick_radius()
	draw_circle(center, radius + 7.0, Color(0.02, 0.05, 0.08, 0.27))
	draw_circle(center, radius, Color(0.08, 0.16, 0.22, 0.42))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.82, 0.92, 0.98, 0.42), 2.0, true)
	var knob_center := center + _move_value * (radius - 16.0)
	draw_circle(knob_center, 23.0, Color(0.13, 0.33, 0.43, 0.78))
	draw_arc(knob_center, 23.0, 0.0, TAU, 32, Color(0.92, 0.97, 1.0, 0.58), 1.5, true)
	draw_texture_rect(JOYSTICK_ICON, Rect2(knob_center - Vector2(10, 10), Vector2(20, 20)), false, Color(0.98, 0.99, 1.0, 0.9))


func _input(event: InputEvent) -> void:
	if not touch_enabled or _menu_open:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _is_reserved(touch.position):
				return
			if _move_touch_id < 0 and _is_in_stick_zone(touch.position):
				_move_touch_id = touch.index
				_update_move(touch.position)
				get_viewport().set_input_as_handled()
			elif _look_touch_id < 0 and touch.position.x > _look_zone_start():
				_look_touch_id = touch.index
				get_viewport().set_input_as_handled()
		else:
			if touch.index == _move_touch_id:
				_move_touch_id = -1
				_move_value = Vector2.ZERO
				movement_changed.emit(Vector2.ZERO)
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif touch.index == _look_touch_id:
				_look_touch_id = -1
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _move_touch_id:
			_update_move(drag.position)
			get_viewport().set_input_as_handled()
		elif drag.index == _look_touch_id:
			look_changed.emit(drag.relative)
			get_viewport().set_input_as_handled()


func _is_in_stick_zone(position: Vector2) -> bool:
	var center := _stick_center()
	var radius := _stick_radius()
	return position.x >= maxf(6.0, center.x - radius - 24.0) and position.x <= center.x + radius + 18.0 and position.y >= center.y - radius - 18.0 and position.y <= size.y - 8.0


func _update_move(position: Vector2) -> void:
	var center := _stick_center()
	_move_value = ((position - center) / _stick_radius()).limit_length(1.0)
	movement_changed.emit(_move_value)
	queue_redraw()


func _stick_center() -> Vector2:
	return Vector2(minf(86.0, size.x * 0.25), size.y - 88.0)


func _stick_radius() -> float:
	return minf(STICK_RADIUS, maxf(24.0, size.x * 0.19))


func _look_zone_start() -> float:
	var center := _stick_center()
	return maxf(size.x * 0.42, center.x + _stick_radius() + 18.0)


func _is_reserved(position: Vector2) -> bool:
	for button: Button in _buttons.values():
		if is_instance_valid(button) and button.get_global_rect().has_point(position):
			return true
	for control: Control in _reserved_controls:
		if is_instance_valid(control) and control.visible and control.get_global_rect().has_point(position):
			return true
	return false
