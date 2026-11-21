class_name PKInput
extends RefCounted
## The kit's input actions and the keys shared by the 2D and 3D build nodes.
## Actions are only added when your project does not define them, so you can rebind every
## one of them in Project Settings > Input Map.
##
## Defaults: R / RB rotate, Shift+R / LB rotate back (hold Ctrl for fine steps, or Shift +
## wheel), F / Y flip, T tilt (6 directions), 1-6 modes (X cycles), Ctrl+Z / Back undo,
## Page Up / Page Down floor levels (D-pad up goes up),
## [ ] / D-pad left-right previous / next piece, Tab / D-pad up-down next category,
## A / Enter confirm, B / Esc / right click cancel, left stick or arrows move the cursor.

const ACTIONS := [
	&"pk_confirm", &"pk_cancel", &"pk_rotate", &"pk_rotate_back", &"pk_flip", &"pk_tilt",
	&"pk_undo", &"pk_mode_build", &"pk_mode_move", &"pk_mode_demolish", &"pk_mode_select",
	&"pk_mode_upgrade", &"pk_mode_repair", &"pk_level_up", &"pk_level_down", &"pk_save_blueprint",
	&"pk_mode_next", &"pk_next_piece", &"pk_previous_piece", &"pk_next_category",
	&"pk_cursor_left", &"pk_cursor_right", &"pk_cursor_up", &"pk_cursor_down",
]


static func ensure_actions() -> void:
	var defaults := {
		&"pk_confirm": [_key(KEY_ENTER), _key(KEY_KP_ENTER), _pad(JOY_BUTTON_A)],
		&"pk_cancel": [_key(KEY_ESCAPE), _pad(JOY_BUTTON_B)],
		&"pk_rotate": [_key(KEY_R), _pad(JOY_BUTTON_RIGHT_SHOULDER)],
		&"pk_rotate_back": [_key(KEY_R, true), _pad(JOY_BUTTON_LEFT_SHOULDER)],
		&"pk_flip": [_key(KEY_F), _pad(JOY_BUTTON_Y)],
		&"pk_tilt": [_key(KEY_T), _pad(JOY_BUTTON_RIGHT_STICK)],
		&"pk_undo": [_key(KEY_Z, false, true), _pad(JOY_BUTTON_BACK)],
		&"pk_mode_build": [_key(KEY_1)],
		&"pk_mode_move": [_key(KEY_2)],
		&"pk_mode_demolish": [_key(KEY_3)],
		&"pk_mode_select": [_key(KEY_4)],
		&"pk_mode_upgrade": [_key(KEY_5)],
		&"pk_mode_repair": [_key(KEY_6)],
		&"pk_level_up": [_key(KEY_PAGEUP), _pad(JOY_BUTTON_DPAD_UP)],
		&"pk_level_down": [_key(KEY_PAGEDOWN)],
		&"pk_save_blueprint": [_key(KEY_B)],
		&"pk_mode_next": [_pad(JOY_BUTTON_X)],
		&"pk_next_piece": [_key(KEY_BRACKETRIGHT), _pad(JOY_BUTTON_DPAD_RIGHT)],
		&"pk_previous_piece": [_key(KEY_BRACKETLEFT), _pad(JOY_BUTTON_DPAD_LEFT)],
		&"pk_next_category": [_key(KEY_TAB), _pad(JOY_BUTTON_DPAD_DOWN)],
		&"pk_cursor_left": [_key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		&"pk_cursor_right": [_key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		&"pk_cursor_up": [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		&"pk_cursor_down": [_key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
	}
	for action in defaults:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.3)
		for event in defaults[action]:
			InputMap.action_add_event(action, event)


## Handles the keys that do not depend on 2D or 3D. Returns true when [param event] was used.
static func handle_common(event: InputEvent, controller: PKBuildController) -> bool:
	if event is InputEventMouseButton and event.pressed and event.shift_pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		controller.rotate(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1, event.ctrl_pressed)
		return true
	if event.is_echo():
		return false
	var fine := event is InputEventWithModifiers and (event as InputEventWithModifiers).ctrl_pressed
	if event.is_action_pressed(&"pk_undo", false, true):
		controller.undo()
	elif event.is_action_pressed(&"pk_rotate_back", false, true):
		controller.rotate(-1, fine)
	elif event.is_action_pressed(&"pk_rotate"):
		controller.rotate(1, fine)
	elif event.is_action_pressed(&"pk_flip"):
		controller.flip()
	elif event.is_action_pressed(&"pk_tilt"):
		controller.tilt()
	elif event.is_action_pressed(&"pk_mode_build"):
		controller.set_mode(PKBuildController.Mode.BUILD)
	elif event.is_action_pressed(&"pk_mode_move"):
		controller.set_mode(PKBuildController.Mode.MOVE)
	elif event.is_action_pressed(&"pk_mode_demolish"):
		controller.set_mode(PKBuildController.Mode.DEMOLISH)
	elif event.is_action_pressed(&"pk_mode_select"):
		controller.set_mode(PKBuildController.Mode.SELECT)
	elif event.is_action_pressed(&"pk_mode_upgrade"):
		controller.set_mode(PKBuildController.Mode.UPGRADE)
	elif event.is_action_pressed(&"pk_mode_repair"):
		controller.set_mode(PKBuildController.Mode.REPAIR)
	elif event.is_action_pressed(&"pk_level_up") and controller.max_level > 0:
		controller.set_level(controller.level + 1)
	elif event.is_action_pressed(&"pk_level_down") and controller.max_level > 0:
		controller.set_level(controller.level - 1)
	elif event.is_action_pressed(&"pk_save_blueprint") and controller.mode == PKBuildController.Mode.SELECT:
		controller.save_selection_as_blueprint()
	elif event.is_action_pressed(&"pk_mode_next"):
		controller.set_mode(((controller.mode + 1) % PKBuildController.Mode.size()) as PKBuildController.Mode)
	elif event.is_action_pressed(&"pk_next_piece"):
		cycle_piece(controller, 1)
	elif event.is_action_pressed(&"pk_previous_piece"):
		cycle_piece(controller, -1)
	elif event.is_action_pressed(&"pk_next_category"):
		cycle_category(controller, -1 if event is InputEventWithModifiers and event.shift_pressed else 1)
	elif event.is_action_pressed(&"pk_cancel"):
		controller.cancel()
	else:
		return false
	return true


## Picks the next (or previous) piece of the catalog.
static func cycle_piece(controller: PKBuildController, direction: int) -> void:
	var pieces := controller.builder.catalog.buildables.filter(func(b: PKBuildable) -> bool: return b != null and b.in_catalog)
	if pieces.is_empty():
		return
	var index := pieces.find(controller.buildable)
	index = posmod(index + direction, pieces.size()) if index >= 0 else (0 if direction > 0 else pieces.size() - 1)
	controller.select_buildable(pieces[index])


## Picks the first piece of the next category.
static func cycle_category(controller: PKBuildController, direction: int) -> void:
	var catalog := controller.builder.catalog
	var categories := catalog.get_categories()
	if categories.is_empty():
		return
	var current := categories.find(controller.buildable.category) if controller.buildable != null else -1
	var next := categories[posmod(current + direction, categories.size())]
	var pieces := catalog.in_category(next).filter(func(b: PKBuildable) -> bool: return b.in_catalog)
	if not pieces.is_empty():
		controller.select_buildable(pieces[0])


## Movement of the virtual cursor from the stick or the arrows (length 0..1).
static func cursor_vector() -> Vector2:
	return Input.get_vector(&"pk_cursor_left", &"pk_cursor_right", &"pk_cursor_up", &"pk_cursor_down")


static func _key(code: Key, shift := false, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	return event


static func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event
