class_name PKBuildHUD
extends Control

const INFO_COST_ENTRY_SCENE: PackedScene = preload("res://addons/building_kit/ui/info_cost_entry.tscn")
## The whole building interface in one node: mode bar (top), catalog (bottom), an info box
## (piece, cost or drag total, why the ghost is red, controls) and short messages.
## [codeblock]
## var hud_scene := preload("res://addons/building_kit/ui/build_hud.tscn")
## var hud := hud_scene.instantiate()
## $CanvasLayer.add_child(hud)
## hud.bind($PKBuildSystem3D)   # or a PKBuildSystem2D
## [/codeblock]
## Every part is a separate class (PKCatalogPanel, PKModeBar) if you want to lay them out yourself.

## Seconds a message stays on screen.
@export var message_time := 2.6

var system: Node
var catalog_panel: PKCatalogPanel
var mode_bar: PKModeBar
var info_panel: PanelContainer
var info_title: Label
var info_cost: HBoxContainer
var info_status: Label
var info_hint: Label
var info_detail: Label
var blueprint_button: Button
var toast: Label
var _crosshair: Control
var _toast_time := 0.0
var _gamepad := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = PKUIStyle.make_theme()
	_crosshair = $Crosshair
	catalog_panel = $PKCatalogPanel
	mode_bar = $PKModeBar
	info_panel = $InfoPanel
	info_title = $InfoPanel/InfoColumn/InfoTitle
	info_cost = $InfoPanel/InfoColumn/InfoCost
	info_status = $InfoPanel/InfoColumn/InfoStatus
	info_detail = $InfoPanel/InfoColumn/InfoDetail
	blueprint_button = $InfoPanel/InfoColumn/BlueprintButton
	info_hint = $InfoPanel/InfoColumn/InfoHint
	toast = $Toast
	blueprint_button.pressed.connect(func() -> void:
		if system != null:
			system.controller.save_selection_as_blueprint()
	)
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_title.add_theme_font_size_override(&"font_size", 18)
	info_title.add_theme_color_override(&"font_color", PKUIStyle.accent)
	info_cost.add_theme_constant_override(&"separation", 4)
	info_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_detail.add_theme_font_size_override(&"font_size", 13)
	info_detail.add_theme_color_override(&"font_color", PKUIStyle.muted_text)
	blueprint_button.focus_mode = Control.FOCUS_NONE
	blueprint_button.visible = false
	info_hint.add_theme_font_size_override(&"font_size", 12)
	info_hint.add_theme_color_override(&"font_color", PKUIStyle.muted_text)
	info_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override(&"font_size", 17)
	toast.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	toast.add_theme_constant_override(&"outline_size", 6)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.modulate.a = 0.0


func bind(p_system: Node) -> void:
	system = p_system
	catalog_panel.bind(system)
	mode_bar.bind(system)
	system.controller.preview_changed.connect(_refresh_info)
	system.mode_changed.connect(func(_m: int) -> void: _refresh_info())
	system.selection_changed.connect(func(_uid: int) -> void: _refresh_info())
	system.controller.hover_changed.connect(func(_uid: int) -> void: _refresh_info())
	system.costs_changed.connect(_refresh_info)
	system.blueprint_changed.connect(func(_b: PKBlueprint) -> void: _refresh_info())
	system.level_changed.connect(func(_l: int) -> void: _refresh_info())
	system.upgraded.connect(func(_p: PKPlacement, _f: PKBuildable) -> void: _refresh_info())
	system.damaged.connect(func(_p: PKPlacement, _a: float) -> void: _refresh_info())
	system.repaired.connect(func(_p: PKPlacement, _c: Dictionary) -> void: _refresh_info())
	system.message.connect(show_message)
	_refresh_info()


func show_message(text: String, error := false) -> void:
	if text.is_empty():
		return
	toast.text = text
	toast.add_theme_color_override(&"font_color", PKUIStyle.bad if error else PKUIStyle.good)
	toast.modulate.a = 1.0
	_toast_time = message_time


func get_cursor_screen_position() -> Vector2:
	return system.get_cursor_screen_position()


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)
	if _crosshair != null:
		_crosshair.visible = system != null and system.is_virtual_cursor()
		if _crosshair.visible:
			var mark := _crosshair.get_node("CrosshairMark") as Control
			mark.position = get_cursor_screen_position() - mark.size * 0.5


func _input(event: InputEvent) -> void:
	if GameSettings.is_settings_open():
		return
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4)
	var desk := event is InputEventKey or event is InputEventMouseButton
	if pad != _gamepad and (pad or desk):
		_gamepad = pad
		mode_bar.set_gamepad_hints(pad)
		_refresh_info()


func _refresh_info() -> void:
	if system == null:
		return
	var controller: PKBuildController = system.controller
	var builder: PKBuilder = system.builder
	_clear_cost_entries()
	info_status.text = ""
	info_status.remove_theme_color_override(&"font_color")
	info_detail.text = ""
	blueprint_button.visible = false
	var piece := controller.get_active_buildable()
	match controller.mode:
		PKBuildController.Mode.BUILD:
			if controller.blueprint != null:
				_describe_blueprint(controller, builder)
				return
			if piece == null:
				info_title.text = PKText.t("Pick something to build")
				info_hint.text = _hint(["[ ] / Tab", "D-pad"])
				return
			info_title.text = piece.get_title()
			var cost := piece.cost
			var count := 1
			if controller.drag != null and controller.drag.valid_count > 0:
				cost = controller.drag.total_cost
				count = controller.drag.valid_count
			_show_cost(cost, builder, count)
			var reason: StringName = &""
			if controller.drag != null:
				reason = controller.drag.first_reason()
				if controller.drag.get_invalid_count() > 0:
					info_status.text = PKText.t("%d can't be built: %s") % [controller.drag.get_invalid_count(), PKText.reason(reason)]
			elif controller.preview != null and not controller.preview.valid:
				info_status.text = PKText.reason(controller.preview.reason)
			if not info_status.text.is_empty():
				info_status.add_theme_color_override(&"font_color", PKUIStyle.bad)
			if builder.stability_enabled and controller.preview != null and (controller.preview.valid or controller.preview.reason == &"unstable"):
				info_detail.text = PKText.t("Stability: %d%%") % roundi(controller.preview.placement.stability * 100.0)
			var lines := PackedStringArray()
			lines.append(PKText.t("Click: build · Right click: cancel") if not _gamepad else PKText.t("A: build · B: cancel"))
			if piece.can_rotate:
				lines.append(PKText.t("R / Shift+R: rotate (Ctrl: fine)") if not _gamepad else PKText.t("RB / LB: rotate"))
			if piece.can_flip:
				lines.append(PKText.t("F: flip") if not _gamepad else PKText.t("Y: flip"))
			if piece.can_tilt:
				lines.append(PKText.t("T: tilt") if not _gamepad else PKText.t("R3: tilt"))
			if piece.drag != PKBuildable.Drag.NONE:
				lines.append(PKText.t("Hold and drag to build several"))
			info_hint.text = "\n".join(lines)
		PKBuildController.Mode.MOVE:
			if controller.moving_uid != 0:
				info_title.text = PKText.t("Moving: %s") % (piece.get_title() if piece != null else "")
				if controller.preview != null and not controller.preview.valid:
					info_status.text = PKText.reason(controller.preview.reason)
					info_status.add_theme_color_override(&"font_color", PKUIStyle.bad)
				info_hint.text = PKText.t("Click: put down · R: rotate · Right click: put back") if not _gamepad else PKText.t("A: put down · RB: rotate · B: put back")
			else:
				info_title.text = PKText.mode_name(controller.mode)
				_describe_hover(builder, controller.hover_uid, false)
				info_hint.text = PKText.t("Click a piece to pick it up") if not _gamepad else PKText.t("A: pick up")
		PKBuildController.Mode.DEMOLISH:
			info_title.text = PKText.mode_name(controller.mode)
			_describe_hover(builder, controller.hover_uid, true)
			info_hint.text = PKText.t("Click a piece to demolish it") if not _gamepad else PKText.t("A: demolish")
		PKBuildController.Mode.SELECT:
			info_title.text = PKText.mode_name(controller.mode)
			var count := controller.get_selection().size()
			_describe_hover(builder, controller.hover_uid if controller.hover_uid != 0 else controller.selected_uid, false)
			if count > 1:
				info_status.text = PKText.t("%d pieces selected") % count
				info_status.remove_theme_color_override(&"font_color")
			blueprint_button.visible = count > 0
			blueprint_button.text = PKText.t("Save as blueprint") + ("" if _gamepad else " (B)")
			info_hint.text = PKText.t("Click: select · Shift+click: add · Drag: box") if not _gamepad else PKText.t("A: select")
		PKBuildController.Mode.UPGRADE:
			info_title.text = PKText.mode_name(controller.mode)
			var hovered := builder.layout.get_piece(controller.hover_uid)
			_describe_hover(builder, controller.hover_uid, false)
			if hovered != null and hovered.buildable.upgrade_to != null:
				info_status.text = "%s → %s" % [hovered.get_title(), hovered.buildable.upgrade_to.get_title()]
				_show_cost(hovered.buildable.get_upgrade_cost(), builder, 1)
				var refused := builder.can_upgrade(hovered.uid)
				if not refused.is_empty():
					info_detail.text = PKText.reason(refused)
			elif hovered != null:
				info_detail.text = PKText.reason(&"no_upgrade")
			info_hint.text = PKText.t("Click a piece to upgrade it") if not _gamepad else PKText.t("A: upgrade")
		PKBuildController.Mode.REPAIR:
			info_title.text = PKText.mode_name(controller.mode)
			_describe_hover(builder, controller.hover_uid, false)
			var hovered := builder.layout.get_piece(controller.hover_uid)
			if hovered != null and hovered.is_damaged():
				_add_cost_entry(PKText.t("Repair:"), PKUIStyle.muted_text)
				_show_cost(builder.repair_cost(hovered.uid), builder, 1)
			elif hovered != null:
				info_detail.text = PKText.reason(&"not_damaged")
			info_hint.text = PKText.t("Click a damaged piece to repair it") if not _gamepad else PKText.t("A: repair")


func _describe_blueprint(controller: PKBuildController, builder: PKBuilder) -> void:
	var blueprint := controller.blueprint
	info_title.text = "%s (%d)" % [blueprint.title, blueprint.size()]
	var drag := controller.drag
	_show_cost(drag.total_cost if drag != null and drag.valid_count > 0 else blueprint.get_cost(builder.catalog), builder, 1)
	if drag != null and drag.get_invalid_count() > 0:
		info_status.text = PKText.t("%d can't be built: %s") % [drag.get_invalid_count(), PKText.reason(drag.first_reason())]
		info_status.add_theme_color_override(&"font_color", PKUIStyle.bad)
	info_hint.text = PKText.t("Click: build it all · R: quarter turn · Right click: cancel") if not _gamepad else PKText.t("A: build · RB: turn · B: cancel")


func _describe_hover(builder: PKBuilder, uid: int, refund: bool) -> void:
	var piece := builder.layout.get_piece(uid)
	if piece == null:
		info_status.text = PKText.t("Point at a piece")
		info_status.add_theme_color_override(&"font_color", PKUIStyle.muted_text)
		return
	info_status.text = piece.get_title()
	var details := PackedStringArray()
	if piece.buildable != null and piece.buildable.max_health > 0.0:
		details.append(PKText.t("Health: %d / %d") % [ceili(piece.get_health()), roundi(piece.buildable.max_health)])
	if builder.stability_enabled:
		details.append(PKText.t("Stability: %d%%") % roundi(piece.stability * 100.0))
	info_detail.text = "  ·  ".join(details)
	var falling := builder.dependents_of(uid).size()
	if refund:
		_add_cost_entry(PKText.t("Refund:"), PKUIStyle.muted_text)
		_show_cost(builder.refund_for(uid), builder, 1, false)
	if falling > 0:
		info_status.text += "  " + PKText.t("(+%d resting on it)") % falling


func _clear_cost_entries() -> void:
	for child in info_cost.get_children():
		child.queue_free()


func _add_cost_entry(text: String, color: Color = PKUIStyle.text_color, icon: Texture2D = null) -> void:
	var entry := INFO_COST_ENTRY_SCENE.instantiate() as HBoxContainer
	var icon_node := entry.get_node("Icon") as TextureRect
	icon_node.texture = icon
	icon_node.visible = icon != null
	var text_node := entry.get_node("Value") as Label
	text_node.text = text
	text_node.add_theme_color_override(&"font_color", color)
	info_cost.add_child(entry)


func _show_cost(cost: Dictionary, builder: PKBuilder, count: int, check := true) -> void:
	var handler := builder.cost_handler
	if count > 1:
		_add_cost_entry("×%d" % count, PKUIStyle.muted_text)
	if cost.is_empty():
		_add_cost_entry(PKText.t("Free"), PKUIStyle.muted_text)
		return
	for item_id in cost:
		var amount := int(cost[item_id])
		var texture := handler.item_icon(item_id)
		var text := "%d" % amount if texture != null else "%d %s" % [amount, handler.item_name(item_id)]
		if check and not handler.is_free():
			text += " / %d" % handler.count(item_id)
		var color := PKUIStyle.text_color if not check or handler.count(item_id) >= amount else PKUIStyle.bad
		_add_cost_entry(text, color, texture)


func _hint(keys: Array) -> String:
	return PKText.t("Choose a piece below (%s)") % (keys[1] if _gamepad else keys[0])
