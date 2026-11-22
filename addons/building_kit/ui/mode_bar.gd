class_name PKModeBar
extends PanelContainer
## Mode buttons, floor controls, and touch actions for the building interface.

var system: Node
var show_touch_buttons := true
var _mode_buttons: Array[Button] = []
var _tools: HBoxContainer
var _undo: Button
var _rotate: Button
var _flip: Button
var _cancel: Button
var _level_down: Button
var _level_label: Label
var _level_up: Button
var _level_box: HBoxContainer
var _pad := false

const MODE_KEYS := ["1", "2", "3", "4", "5", "6"]
const MODE_LABELS := ["Co", "Mo", "De", "Se", "Ap", "Re"]


func _ready() -> void:
	name = "PKModeBar"
	_tools = $Rows/Tools
	_level_box = $Rows/Tools/LevelBox
	_level_down = $Rows/Tools/LevelBox/LevelDown
	_level_label = $Rows/Tools/LevelBox/LevelLabel
	_level_up = $Rows/Tools/LevelBox/LevelUp
	_undo = $Rows/Tools/Undo
	_rotate = $Rows/Tools/Rotate
	_flip = $Rows/Tools/Flip
	_cancel = $Rows/Tools/Cancel
	var group := ButtonGroup.new()
	for mode in PKBuildController.Mode.size():
		var button: Button = get_node("Rows/Modes/Mode%d" % mode)
		button.button_group = group
		_mode_buttons.append(button)
		button.pressed.connect(func() -> void:
			if system != null: system.set_mode(mode))
	_level_down.pressed.connect(func() -> void:
		if system != null: system.set_level(system.controller.level - 1))
	_level_up.pressed.connect(func() -> void:
		if system != null: system.set_level(system.controller.level + 1))
	_undo.pressed.connect(func() -> void:
		if system != null: system.undo())
	_rotate.pressed.connect(func() -> void:
		if system != null: system.rotate_piece(1))
	_flip.pressed.connect(func() -> void:
		if system != null: system.flip_piece())
	_cancel.pressed.connect(func() -> void:
		if system != null: system.cancel())


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
	if system == null or _mode_buttons.is_empty(): return
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
