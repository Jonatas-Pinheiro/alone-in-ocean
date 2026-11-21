extends CanvasLayer

const MOBILE_CONTROLS_SCRIPT := preload("res://Scripts/UI/mobile_controls.gd")
const ICON_HEALTH := preload("res://Assets/UI/status_health.svg")
const ICON_HUNGER := preload("res://Assets/UI/status_hunger.svg")
const ICON_THIRST := preload("res://Assets/UI/status_thirst.svg")
const ICON_STAMINA := preload("res://Assets/UI/status_stamina.svg")

var _root: Control
var _player: SurvivalPlayer
var _bars: Dictionary = {}
var _inventory_label: Label
var _status_panel: PanelContainer
var _mobile_controls: Control
var _eat_button: Button
var _drink_button: Button
var _build_button: Button
var _build_menu: PanelContainer
var _build_grid: GridContainer
var _build_system: Node


func _ready() -> void:
	layer = 5
	_build_interface()
	_create_mobile_controls()


func _process(_delta: float) -> void:
	var local_id := multiplayer.get_unique_id()
	if not is_instance_valid(_player) or _player.owner_peer_id != local_id:
		_player = _find_local_player(local_id)

	_root.visible = _player != null
	_mobile_controls.visible = _player != null and bool(_mobile_controls.get("touch_enabled"))
	if _player == null:
		return

	_bars[&"health"].value = _player.health
	_bars[&"hunger"].value = _player.hunger
	_bars[&"thirst"].value = _player.thirst
	_bars[&"stamina"].value = _player.stamina
	_inventory_label.text = "M %02d  P %02d  S %02d   Comida %d  Água %d" % [
		_player.wood_count,
		_player.plastic_count,
		_player.scrap_count,
		_player.food_count,
		_player.water_count,
	]
	_eat_button.visible = _mobile_controls.touch_enabled and _player.food_count > 0 and _player.hunger < 98.0
	_drink_button.visible = _mobile_controls.touch_enabled and _player.water_count > 0 and _player.thirst < 98.0
	_update_build_system()


func _find_local_player(peer_id: int) -> SurvivalPlayer:
	for node in get_tree().get_nodes_in_group("players"):
		if node is SurvivalPlayer and node.owner_peer_id == peer_id:
			return node as SurvivalPlayer
	return null


func _build_interface() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_status_panel = PanelContainer.new()
	_status_panel.position = Vector2(12.0, 12.0)
	_status_panel.custom_minimum_size = Vector2(188.0, 0.0)
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_theme_stylebox_override("panel", _panel_style())
	_status_panel.add_theme_constant_override("margin_left", 8)
	_status_panel.add_theme_constant_override("margin_right", 8)
	_status_panel.add_theme_constant_override("margin_top", 7)
	_status_panel.add_theme_constant_override("margin_bottom", 7)
	_root.add_child(_status_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_child(column)
	_bars[&"health"] = _make_stat_row(column, "Vida", ICON_HEALTH, Color(0.92, 0.25, 0.28))
	_bars[&"hunger"] = _make_stat_row(column, "Fome", ICON_HUNGER, Color(0.98, 0.62, 0.18))
	_bars[&"thirst"] = _make_stat_row(column, "Sede", ICON_THIRST, Color(0.25, 0.68, 0.98))
	_bars[&"stamina"] = _make_stat_row(column, "Estamina", ICON_STAMINA, Color(0.40, 0.88, 0.48))

	_inventory_label = Label.new()
	_inventory_label.add_theme_font_size_override("font_size", 9)
	_inventory_label.add_theme_color_override("font_color", Color(0.85, 0.91, 0.96, 0.9))
	_inventory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_inventory_label)

	var consumables := HBoxContainer.new()
	consumables.add_theme_constant_override("separation", 4)
	consumables.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(consumables)
	_eat_button = _make_consumable_button("Comer", "eat")
	_drink_button = _make_consumable_button("Beber", "drink")
	consumables.add_child(_eat_button)
	consumables.add_child(_drink_button)

	_build_button = Button.new()
	_build_button.text = "Construir"
	_build_button.custom_minimum_size = Vector2(96.0, 36.0)
	_build_button.focus_mode = Control.FOCUS_NONE
	_build_button.tooltip_text = "Abrir menu compacto de construção"
	_build_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_build_button.offset_left = -108.0
	_build_button.offset_right = -12.0
	_build_button.offset_top = 12.0
	_build_button.offset_bottom = 48.0
	_build_button.add_theme_font_size_override("font_size", 12)
	_build_button.add_theme_stylebox_override("normal", _button_style(Color(0.04, 0.12, 0.18, 0.82)))
	_build_button.add_theme_stylebox_override("hover", _button_style(Color(0.08, 0.25, 0.32, 0.94)))
	_build_button.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.38, 0.48, 0.98)))
	_build_button.visible = false
	_build_button.pressed.connect(_toggle_build_menu)
	_root.add_child(_build_button)

	_build_menu = PanelContainer.new()
	_build_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_build_menu.offset_left = -204.0
	_build_menu.offset_right = -12.0
	_build_menu.offset_top = 56.0
	_build_menu.offset_bottom = 192.0
	_build_menu.add_theme_stylebox_override("panel", _panel_style())
	_build_menu.add_theme_constant_override("margin_left", 7)
	_build_menu.add_theme_constant_override("margin_right", 7)
	_build_menu.add_theme_constant_override("margin_top", 7)
	_build_menu.add_theme_constant_override("margin_bottom", 7)
	_build_menu.visible = false
	_root.add_child(_build_menu)
	_root.resized.connect(_layout_build_menu)

	var menu_column := VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 5)
	_build_menu.add_child(menu_column)
	var menu_title := Label.new()
	menu_title.text = "Peças"
	menu_title.add_theme_font_size_override("font_size", 11)
	menu_column.add_child(menu_title)
	_build_grid = GridContainer.new()
	_build_grid.columns = 2
	_build_grid.add_theme_constant_override("h_separation", 5)
	_build_grid.add_theme_constant_override("v_separation", 5)
	menu_column.add_child(_build_grid)
	var rotate_button := Button.new()
	rotate_button.text = "Girar peça"
	rotate_button.custom_minimum_size = Vector2(0.0, 28.0)
	rotate_button.focus_mode = Control.FOCUS_NONE
	rotate_button.add_theme_font_size_override("font_size", 10)
	rotate_button.pressed.connect(_rotate_build_piece)
	menu_column.add_child(rotate_button)
	_layout_build_menu()


func _create_mobile_controls() -> void:
	_mobile_controls = MOBILE_CONTROLS_SCRIPT.new()
	_mobile_controls.name = "MobileControls"
	_root.add_child(_mobile_controls)
	_mobile_controls.movement_changed.connect(_on_touch_movement)
	_mobile_controls.look_changed.connect(_on_touch_look)
	_mobile_controls.action_held.connect(_on_touch_action_held)
	_mobile_controls.action_pressed.connect(_on_touch_action_pressed)
	_mobile_controls.set_reserved_controls([_status_panel, _build_button, _build_menu])


func _make_stat_row(parent: VBoxContainer, title: String, icon_texture: Texture2D, fill_color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.modulate = fill_color
	icon.custom_minimum_size = Vector2(15.0, 15.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = title
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(145.0, 9.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.tooltip_text = title
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _bar_style(Color(0.025, 0.045, 0.06, 0.82)))
	bar.add_theme_stylebox_override("fill", _bar_style(fill_color))
	row.add_child(bar)
	return bar


func _make_consumable_button(label: String, action: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(54.0, 22.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.06, 0.13, 0.17, 0.86)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.10, 0.24, 0.28, 0.96)))
	button.pressed.connect(func() -> void:
		if _player != null:
			_player.call("_request_survival_action", action)
	)
	return button


func _update_build_system() -> void:
	var scene := get_tree().current_scene
	var setup := scene.get_node_or_null("BuildingKitSetup") if scene != null else null
	var candidate: Node = setup.get("build_system") as Node if setup != null else null
	if candidate != _build_system:
		_build_system = candidate
		_build_menu.visible = false
		_mobile_controls.set_menu_open(false)
		_build_button.visible = _build_system != null
		if _build_system != null:
			_rebuild_build_menu()
	if _build_system == null or scene == null:
		return

	var native_hud := scene.get_node_or_null("BuildingHUDLayer/PKBuildHUD") as PKBuildHUD
	if native_hud != null:
		native_hud.catalog_panel.visible = false
		native_hud.catalog_panel.button_size = Vector2(64.0, 68.0)
		native_hud.info_panel.visible = false
		native_hud.mode_bar.position = Vector2(12.0, 132.0)


func _rebuild_build_menu() -> void:
	for child in _build_grid.get_children():
		child.queue_free()
	if _build_system == null:
		return
	var catalog: PKCatalog = _build_system.get("catalog") as PKCatalog
	if catalog == null:
		return
	for buildable: PKBuildable in catalog.buildables:
		if buildable == null or not buildable.in_catalog:
			continue
		var button := Button.new()
		button.text = buildable.get_title()
		button.tooltip_text = buildable.description
		button.custom_minimum_size = Vector2(82.0, 34.0)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(_select_buildable.bind(buildable))
		_build_grid.add_child(button)


func _toggle_build_menu() -> void:
	if _build_system == null:
		return
	_build_menu.visible = not _build_menu.visible
	_mobile_controls.set_menu_open(_build_menu.visible)


func _layout_build_menu() -> void:
	if _build_menu == null:
		return
	if _root.size.x < 440.0:
		_build_menu.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_build_menu.offset_left = -112.0
		_build_menu.offset_right = 112.0
		_build_menu.offset_top = -164.0
		_build_menu.offset_bottom = -12.0
	else:
		_build_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_build_menu.offset_left = -204.0
		_build_menu.offset_right = -12.0
		_build_menu.offset_top = 56.0
		_build_menu.offset_bottom = 192.0


func _select_buildable(buildable: PKBuildable) -> void:
	if _build_system == null:
		return
	_build_system.set_mode(PKBuildController.Mode.BUILD)
	_build_system.select_buildable(buildable)
	_build_menu.visible = false
	_mobile_controls.set_menu_open(false)


func _rotate_build_piece() -> void:
	if _build_system != null:
		_build_system.rotate_piece(1)


func _on_touch_movement(value: Vector2) -> void:
	if _player != null:
		_player.set_touch_move(value)


func _on_touch_look(delta: Vector2) -> void:
	if _player != null:
		_player.apply_touch_look(delta)


func _on_touch_action_held(action: StringName, pressed: bool) -> void:
	if _player == null:
		return
	match action:
		&"jump":
			_player.set_touch_jump(pressed)
		&"sprint":
			_player.set_touch_sprint(pressed)


func _on_touch_action_pressed(action: StringName) -> void:
	if action == &"interact" and _player != null:
		_player.call("_try_collect_pickup")
	elif action == &"place" and _build_system != null:
		_build_system.call("submit_touch_action")


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.075, 0.82)
	style.border_color = Color(0.67, 0.83, 0.91, 0.24)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.72, 0.86, 0.94, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style
