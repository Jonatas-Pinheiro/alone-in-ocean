class_name PKModeBar
extends PanelContainer
## Mode buttons (Build, Move, Demolish, Select, and Upgrade / Repair when the catalog has
## upgrades or health), the floor level when there are several, and Undo, Rotate, Flip and
## Cancel buttons for touch screens. Each button shows its key (keyboard or gamepad,
## following the last input) in its tooltip and as a small number.

var system: Node
var show_touch_buttons := true

var _mode_buttons: Array[Button] = []
var _row := HBoxContainer.new()
## Second row: floor buttons and the touch buttons (Undo, Rotate, Flip, Cancel).
var _tools := HBoxContainer.new()
var _undo := Button.new()
var _rotate := Button.new()
var _flip := Button.new()
var _cancel := Button.new()
var _level_down := Button.new()
var _level_label := Label.new()
var _level_up := Button.new()
var _level_box := HBoxContainer.new()
var _pad := false

const MODE_KEYS := ["1", "2", "3", "4", "5", "6"]
const MODE_LABELS := ["Co", "Mo", "De", "Se", "Ap", "Re"]


func _init() -> void:
	name = "PKModeBar"
	_row.add_theme_constant_override(&"separation", 4)
	_tools.add_theme_constant_override(&"separation", 4)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 4)
	rows.add_child(_row)
	rows.add_child(_tools)
	add_child(rows)
	var group := ButtonGroup.new()
	for mode in PKBuildController.Mode.size():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(42, 32)
		button.pressed.connect(func() -> void: system.set_mode(mode))
		_row.add_child(button)
		_mode_buttons.append(button)
	_level_box.add_theme_constant_override(&"separation", 2)
	for entry in [[_level_down, "-", -1], [_level_up, "+", 1]]:
		var button: Button = entry[0]
		button.text = entry[1]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(30, 34)
		var step: int = entry[2]
		button.pressed.connect(func() -> void: system.set_level(system.controller.level + step))
	_level_box.add_child(_level_down)
	_level_label.custom_minimum_size = Vector2(70, 0)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_box.add_child(_level_label)
	_level_box.add_child(_level_up)
	_level_box.add_child(VSeparator.new())
	_tools.add_child(_level_box)
	for entry in [[_undo, func() -> void: system.undo()], [_rotate, func() -> void: system.rotate_piece(1)],
			[_flip, func() -> void: system.flip_piece()], [_cancel, func() -> void: system.cancel()]]:
		var button: Button = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(34, 28)
		button.add_theme_font_size_override(&"font_size", 13)
		button.pressed.connect(entry[1])
		_tools.add_child(button)


func bind(p_system: Node) -> void:
	system = p_system
	system.mode_changed.connect(func(_m: int) -> void: refresh())
	system.buildable_changed.connect(func(_b: PKBuildable) -> void: refresh())
	system.level_changed.connect(func(_l: int) -> void: refresh())
	refresh()


func set_gamepad_hints(on: bool) -> void:
	if on != _pad:
		_pad = on
		refresh()


func refresh() -> void:
	if system == null:
		return
	var controller: PKBuildController = system.controller
	var mode: int = controller.mode
	var has_upgrades := false
	var has_health := false
	for buildable in system.builder.catalog.buildables:
		if buildable != null:
			has_upgrades = has_upgrades or buildable.upgrade_to != null
			has_health = has_health or buildable.max_health > 0.0
	for index in _mode_buttons.size():
		var button := _mode_buttons[index]
		button.text = MODE_LABELS[index]
		button.tooltip_text = PKText.mode_name(index) + " (%s)" % ("X" if _pad else MODE_KEYS[index])
		button.set_pressed_no_signal(index == mode)
	_mode_buttons[PKBuildController.Mode.UPGRADE].visible = has_upgrades
	_mode_buttons[PKBuildController.Mode.REPAIR].visible = has_health
	_level_box.visible = controller.max_level > 0
	_level_label.text = PKText.t("Floor %d") % controller.level
	_level_down.disabled = controller.level <= 0
	_level_up.disabled = controller.level >= controller.max_level
	_level_down.tooltip_text = PKText.t("Floor down") + " (PgDn)"
	_level_up.tooltip_text = PKText.t("Floor up") + (" (D-pad up)" if _pad else " (PgUp)")
	_undo.text = "↶"
	_undo.tooltip_text = PKText.t("Undo") + (" (Back)" if _pad else " (Ctrl+Z)")
	_rotate.text = "↻"
	_rotate.tooltip_text = PKText.t("Rotate") + (" (RB / LB)" if _pad else " (R / Shift+R)")
	_flip.text = "F"
	_flip.tooltip_text = PKText.t("Flip") + (" (Y)" if _pad else " (F)")
	_cancel.text = "×"
	_cancel.tooltip_text = PKText.t("Cancel") + (" (B)" if _pad else " (Esc)")
	var piece: PKBuildable = controller.get_active_buildable()
	_rotate.visible = show_touch_buttons
	_rotate.disabled = piece == null or (not piece.can_rotate and controller.blueprint == null)
	_flip.visible = show_touch_buttons and piece != null and piece.can_flip
	_cancel.visible = show_touch_buttons


func get_mode_button(mode: int) -> Button:
	return _mode_buttons[mode]
