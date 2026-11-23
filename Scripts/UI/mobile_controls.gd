extends Control

signal movement_changed(value: Vector2)
signal look_changed(delta: Vector2)
signal action_held(action: StringName, pressed: bool)
signal action_pressed(action: StringName)

const BUTTON_WIDTH := 70.0
const BUTTON_HEIGHT := 48.0
const STICK_RADIUS := 54.0

var touch_enabled := false
var _move_touch_id := -1
var _look_touch_id := -1
var _move_value := Vector2.ZERO
var _buttons: Dictionary = {}
var _reserved_controls: Array = []
var _menu_open := false
var _edit_mode := false
var _button_scale := 1.0
var _dragged_action: StringName = &""
var _drag_touch_id := -1
var _drag_moved := false
var _pending_drag_position := Vector2.ZERO
var _stick_pad: TextureRect
var _stick_nub: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_enabled = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_button_scale = GameSettings.mobile_button_scale
	visible = touch_enabled
	_stick_pad = $JoystickPad
	_stick_nub = $JoystickNub
	_buttons = {
		&"place": $Touch_place,
		&"jump": $Touch_jump,
		&"interact": $Touch_interact,
		&"sprint": $Touch_sprint,
	}
	for action: StringName in _buttons:
		var button := _buttons[action] as Button
		button.visible = touch_enabled
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.add_theme_font_size_override("font_size", 9)
		button.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _button_style(Color(0.035, 0.07, 0.11, 0.70)))
		button.add_theme_stylebox_override("hover", _button_style(Color(0.08, 0.20, 0.28, 0.88)))
		button.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.38, 0.48, 0.95)))
		if action == &"jump" or action == &"sprint":
			button.button_down.connect(func() -> void: action_held.emit(action, true))
			button.button_up.connect(func() -> void: action_held.emit(action, false))
		else:
			button.pressed.connect(func() -> void: action_pressed.emit(action))
	_stick_pad.visible = touch_enabled
	_stick_nub.visible = touch_enabled
	if not touch_enabled:
		return
	resized.connect(_layout_buttons)
	_layout_buttons()
	_update_stick_visual()


func set_reserved_controls(controls: Array) -> void:
	_reserved_controls = controls
	_layout_buttons()


func set_menu_open(open: bool) -> void:
	if open:
		_commit_drag()
		_move_touch_id = -1
		_look_touch_id = -1
		_move_value = Vector2.ZERO
		movement_changed.emit(Vector2.ZERO)
		action_held.emit(&"jump", false)
		action_held.emit(&"sprint", false)
	_menu_open = open
	for button: Button in _buttons.values():
		button.visible = touch_enabled and not open
	_stick_pad.visible = touch_enabled and not open
	_stick_nub.visible = touch_enabled and not open


func set_edit_mode(enabled: bool) -> void:
	_commit_drag()
	_edit_mode = enabled and touch_enabled
	for action: StringName in _buttons:
		var button := _buttons[action] as Button
		button.tooltip_text = "Arraste para mover" if _edit_mode else ""
		var normal_color := Color(0.08, 0.36, 0.47, 0.94) if _edit_mode else Color(0.035, 0.07, 0.11, 0.70)
		button.add_theme_stylebox_override("normal", _button_style(normal_color))


func refresh_custom_layout() -> void:
	_button_scale = GameSettings.mobile_button_scale
	_layout_buttons()
	_update_stick_visual()


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
	button_width = minf(button_width * _button_scale, maxf(44.0, size.x - 16.0))
	var button_height := BUTTON_HEIGHT * _button_scale
	var right := size.x - 10.0
	var positions: Dictionary = {}
	if two_columns:
		var left_col := maxf(_look_zone_start() + 8.0, right - button_width * 2.0 - gap)
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
		var button := _buttons[action] as Button
		var button_position: Vector2 = positions[action]
		var saved_position := GameSettings.get_mobile_button_position(action)
		if saved_position.x >= 0.0:
			button_position = Vector2(saved_position.x * size.x, saved_position.y * size.y)
		button_position = _find_safe_button_position(action, button_position, Vector2(button_width, button_height))
		button.custom_minimum_size = Vector2(button_width, button_height)
		button.offset_left = button_position.x
		button.offset_top = button_position.y
		button.offset_right = button_position.x + button_width
		button.offset_bottom = button_position.y + button_height


func _update_stick_visual() -> void:
	if _stick_pad == null or _stick_nub == null or size.y <= 0.0:
		return
	var center := _stick_center()
	var radius := _stick_radius()
	_stick_pad.position = center - Vector2.ONE * radius
	_stick_pad.size = Vector2.ONE * radius * 2.0
	var knob_center := center + _move_value * (radius - 16.0)
	_stick_nub.size = Vector2(46.0, 46.0)
	_stick_nub.position = knob_center - _stick_nub.size * 0.5


func _input(event: InputEvent) -> void:
	if not touch_enabled or _menu_open:
		return
	if GameSettings.is_gameplay_ui_open():
		return
	if _edit_mode:
		_handle_layout_edit(event)
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
				_update_stick_visual()
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


func _handle_layout_edit(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			for action: StringName in _buttons:
				var button := _buttons[action] as Button
				if button.visible and button.get_global_rect().has_point(touch.position):
					_dragged_action = action
					_drag_touch_id = touch.index
					_drag_moved = false
					_pending_drag_position = Vector2(
						button.offset_left / maxf(size.x, 1.0),
						button.offset_top / maxf(size.y, 1.0)
					)
					get_viewport().set_input_as_handled()
					return
		elif touch.index == _drag_touch_id:
			_commit_drag()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _dragged_action != &"":
		var drag := event as InputEventScreenDrag
		if drag.index == _drag_touch_id:
			_move_dragged_button(drag.relative)
			get_viewport().set_input_as_handled()


func _move_dragged_button(relative: Vector2) -> void:
	var button := _buttons.get(_dragged_action) as Button
	if button == null:
		return
	var previous_position := Vector2(button.offset_left, button.offset_top)
	var next_position := previous_position + relative
	next_position.x = clampf(next_position.x, _look_zone_start() + 8.0, maxf(_look_zone_start() + 8.0, size.x - button.size.x - 8.0))
	next_position.y = clampf(next_position.y, 8.0, maxf(8.0, size.y - button.size.y - 8.0))
	var candidate := Rect2(global_position + next_position, button.size)
	var aim_safe_zone := Rect2(global_position + size * 0.5 - Vector2(36.0, 36.0), Vector2(72.0, 72.0))
	if candidate.intersects(aim_safe_zone):
		return
	for control: Control in _reserved_controls:
		if is_instance_valid(control) and control.visible and candidate.intersects(control.get_global_rect()):
			return
	for action: StringName in _buttons:
		if action == _dragged_action:
			continue
		var other := _buttons[action] as Button
		if other != null and other.visible:
			var other_rect := Rect2(global_position + Vector2(other.offset_left, other.offset_top), other.size)
			if candidate.intersects(other_rect):
				return
	_drag_moved = _drag_moved or not next_position.is_equal_approx(previous_position)
	button.offset_left = next_position.x
	button.offset_top = next_position.y
	button.offset_right = next_position.x + button.size.x
	button.offset_bottom = next_position.y + button.size.y
	_pending_drag_position = Vector2(next_position.x / maxf(size.x, 1.0), next_position.y / maxf(size.y, 1.0))


func _commit_drag() -> void:
	if _dragged_action != &"" and _drag_moved:
		GameSettings.set_mobile_button_position(_dragged_action, _pending_drag_position)
	_dragged_action = &""
	_drag_touch_id = -1
	_drag_moved = false


func _find_safe_button_position(action: StringName, desired: Vector2, button_size: Vector2) -> Vector2:
	var min_x := _look_zone_start() + 8.0
	var max_x := maxf(min_x, size.x - button_size.x - 8.0)
	var max_y := maxf(8.0, size.y - button_size.y - 8.0)
	desired.x = clampf(desired.x, min_x, max_x)
	desired.y = clampf(desired.y, 8.0, max_y)
	if _is_mobile_button_position_safe(action, desired, button_size):
		return desired

	var best_position := Vector2(-1.0, -1.0)
	var best_distance := INF
	var y := 8.0
	while y <= max_y + 0.1:
		var x := min_x
		while x <= max_x + 0.1:
			var candidate := Vector2(x, y)
			if _is_mobile_button_position_safe(action, candidate, button_size):
				var distance := candidate.distance_squared_to(desired)
				if distance < best_distance:
					best_distance = distance
					best_position = candidate
			x += 16.0
		y += 16.0
	return desired if best_position.x < 0.0 else best_position


func _is_mobile_button_position_safe(action: StringName, position: Vector2, button_size: Vector2) -> bool:
	var candidate := Rect2(global_position + position, button_size)
	var aim_safe_zone := Rect2(global_position + size * 0.5 - Vector2(36.0, 36.0), Vector2(72.0, 72.0))
	if candidate.intersects(aim_safe_zone):
		return false
	for control: Control in _reserved_controls:
		if is_instance_valid(control) and control.visible and candidate.intersects(control.get_global_rect()):
			return false
	for other_action: StringName in _buttons:
		if other_action == action:
			continue
		var other := _buttons[other_action] as Button
		if other != null and other.visible:
			var other_rect := Rect2(global_position + Vector2(other.offset_left, other.offset_top), button_size)
			if candidate.intersects(other_rect):
				return false
	return true


func _is_in_stick_zone(position: Vector2) -> bool:
	var center := _stick_center()
	var radius := _stick_radius()
	return position.x >= maxf(6.0, center.x - radius - 24.0) and position.x <= center.x + radius + 18.0 and position.y >= center.y - radius - 18.0 and position.y <= size.y - 8.0


func _update_move(position: Vector2) -> void:
	var center := _stick_center()
	_move_value = ((position - center) / _stick_radius()).limit_length(1.0)
	movement_changed.emit(_move_value)
	_update_stick_visual()


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
