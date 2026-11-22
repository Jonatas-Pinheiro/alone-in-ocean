extends CanvasLayer

const MOBILE_CONTROLS_SCRIPT := preload("res://Scripts/UI/mobile_controls.gd")
const ICON_HEALTH := preload("res://Assets/UI/status_health.svg")
const ICON_HUNGER := preload("res://Assets/UI/status_hunger.svg")
const ICON_THIRST := preload("res://Assets/UI/status_thirst.svg")
const ICON_STAMINA := preload("res://Assets/UI/status_stamina.svg")
const PICKUP_SOUND := preload("res://Assets/Audio/pickup_chime.wav")
const INVENTORY_NAMES: Array[String] = ["Madeira", "Plástico", "Sucata", "Comida", "Água"]
const UI_REFRESH_INTERVAL := 0.1
const BUILD_SYSTEM_REFRESH_INTERVAL := 0.5


class CenterAimDot extends Control:
	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, 4.0, Color(0.02, 0.04, 0.06, 0.72))
		draw_circle(center, 2.2, Color(1.0, 1.0, 1.0, 0.98))


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
var _inventory_button: Button
var _inventory_panel: PanelContainer
var _inventory_details: Label
var _hotbar_panel: PanelContainer
var _hotbar_buttons: Array[Button] = []
var _last_counts: Array[int] = []
var _selected_hotbar_slot := 0
var _last_selected_hotbar_slot := -1
var _aim_dot: Control
var _pickup_audio: AudioStreamPlayer
var _pickup_feedback: Label
var _pickup_feedback_time := 0.0
var _slot_feedback_tweens: Dictionary = {}
var _ui_refresh_elapsed := 0.0
var _build_system_refresh_elapsed := 0.0


func _ready() -> void:
	layer = 5
	set_process_unhandled_input(true)
	_build_interface()
	_create_mobile_controls()
	_layout_hotbar()


func _process(delta: float) -> void:
	_update_pickup_feedback(delta)
	var local_id := multiplayer.get_unique_id()
	if not is_instance_valid(_player) or _player.owner_peer_id != local_id:
		_player = _find_local_player(local_id)
		_last_counts.clear()

	var has_player := _player != null
	if _root.visible != has_player:
		_root.visible = has_player
	var touch_controls_visible := has_player and bool(_mobile_controls.get("touch_enabled"))
	if _mobile_controls.visible != touch_controls_visible:
		_mobile_controls.visible = touch_controls_visible
	if not has_player:
		return

	_build_system_refresh_elapsed += delta
	if _build_system_refresh_elapsed >= BUILD_SYSTEM_REFRESH_INTERVAL:
		_build_system_refresh_elapsed = fposmod(_build_system_refresh_elapsed, BUILD_SYSTEM_REFRESH_INTERVAL)
		_update_build_system()

	_ui_refresh_elapsed += delta
	if _ui_refresh_elapsed < UI_REFRESH_INTERVAL:
		return
	_ui_refresh_elapsed = fposmod(_ui_refresh_elapsed, UI_REFRESH_INTERVAL)

	_bars[&"health"].value = _player.health
	_bars[&"hunger"].value = _player.hunger
	_bars[&"thirst"].value = _player.thirst
	_bars[&"stamina"].value = _player.stamina
	_inventory_label.text = "M %02d · P %02d · S %02d\nComida %02d · Água %02d" % [
		_player.wood_count,
		_player.plastic_count,
		_player.scrap_count,
		_player.food_count,
		_player.water_count,
	]
	_update_inventory_display()
	var show_eat_button: bool = _mobile_controls.touch_enabled and _player.food_count > 0 and _player.hunger < 98.0
	var show_drink_button: bool = _mobile_controls.touch_enabled and _player.water_count > 0 and _player.thirst < 98.0
	if _eat_button.visible != show_eat_button or _drink_button.visible != show_drink_button:
		_eat_button.visible = show_eat_button
		_drink_button.visible = show_drink_button
		_layout_all()


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
	_build_button.text = "Construir [V]"
	_build_button.custom_minimum_size = Vector2(96.0, 36.0)
	_build_button.focus_mode = Control.FOCUS_NONE
	_build_button.tooltip_text = "Abrir menu de construção (V / OPTIONS)"
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

	_inventory_button = Button.new()
	_inventory_button.text = "Inventário [△]"
	_inventory_button.custom_minimum_size = Vector2(96.0, 36.0)
	_inventory_button.focus_mode = Control.FOCUS_NONE
	_inventory_button.tooltip_text = "Abrir inventário (I / Triângulo)"
	_inventory_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_inventory_button.offset_left = -212.0
	_inventory_button.offset_right = -112.0
	_inventory_button.offset_top = 12.0
	_inventory_button.offset_bottom = 48.0
	_inventory_button.add_theme_font_size_override("font_size", 11)
	_inventory_button.add_theme_stylebox_override("normal", _button_style(Color(0.04, 0.12, 0.18, 0.82)))
	_inventory_button.add_theme_stylebox_override("hover", _button_style(Color(0.08, 0.25, 0.32, 0.94)))
	_inventory_button.pressed.connect(_toggle_inventory)
	_root.add_child(_inventory_button)

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

	var menu_column := VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 5)
	_build_menu.add_child(menu_column)
	var menu_title := Label.new()
	menu_title.text = "Peças · Setas/Tab + Enter"
	menu_title.add_theme_font_size_override("font_size", 9)
	menu_column.add_child(menu_title)
	_build_grid = GridContainer.new()
	_build_grid.columns = 2
	_build_grid.add_theme_constant_override("h_separation", 5)
	_build_grid.add_theme_constant_override("v_separation", 5)
	menu_column.add_child(_build_grid)
	var rotate_button := Button.new()
	rotate_button.text = "Girar peça [R]"
	rotate_button.custom_minimum_size = Vector2(0.0, 28.0)
	rotate_button.focus_mode = Control.FOCUS_ALL
	rotate_button.add_theme_font_size_override("font_size", 10)
	rotate_button.pressed.connect(_rotate_build_piece)
	menu_column.add_child(rotate_button)

	_inventory_panel = PanelContainer.new()
	_inventory_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_inventory_panel.offset_left = -212.0
	_inventory_panel.offset_right = -12.0
	_inventory_panel.offset_top = 56.0
	_inventory_panel.offset_bottom = 214.0
	_inventory_panel.add_theme_stylebox_override("panel", _panel_style())
	_inventory_panel.add_theme_constant_override("margin_left", 10)
	_inventory_panel.add_theme_constant_override("margin_right", 10)
	_inventory_panel.add_theme_constant_override("margin_top", 8)
	_inventory_panel.add_theme_constant_override("margin_bottom", 8)
	_inventory_panel.visible = false
	_root.add_child(_inventory_panel)
	var inventory_column := VBoxContainer.new()
	inventory_column.add_theme_constant_override("separation", 4)
	_inventory_panel.add_child(inventory_column)
	var inventory_title := Label.new()
	inventory_title.text = "Inventário"
	inventory_title.add_theme_font_size_override("font_size", 14)
	inventory_column.add_child(inventory_title)
	_inventory_details = Label.new()
	_inventory_details.add_theme_font_size_override("font_size", 11)
	_inventory_details.add_theme_color_override("font_color", Color(0.85, 0.91, 0.96, 0.96))
	inventory_column.add_child(_inventory_details)
	var inventory_hint := Label.new()
	inventory_hint.text = "F/↑: comer · G/↓: beber · E/□: coletar · Ctrl/○: agachar\nL-stick: mover · R-stick: olhar · ✕: pular · L3: correr\n△: inventário · OPTIONS: construir · L2/R2: itens"
	inventory_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_hint.add_theme_font_size_override("font_size", 9)
	inventory_hint.add_theme_color_override("font_color", Color(0.65, 0.78, 0.84, 0.9))
	inventory_column.add_child(inventory_hint)

	_hotbar_panel = PanelContainer.new()
	_hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar_panel.add_theme_stylebox_override("panel", _panel_style())
	_hotbar_panel.add_theme_constant_override("margin_left", 6)
	_hotbar_panel.add_theme_constant_override("margin_right", 6)
	_hotbar_panel.add_theme_constant_override("margin_top", 5)
	_hotbar_panel.add_theme_constant_override("margin_bottom", 5)
	_root.add_child(_hotbar_panel)
	var hotbar_row := HBoxContainer.new()
	hotbar_row.add_theme_constant_override("separation", 4)
	_hotbar_panel.add_child(hotbar_row)
	for index in range(INVENTORY_NAMES.size()):
		var slot := Button.new()
		slot.name = "HotbarSlot%d" % (index + 1)
		slot.text = "%s\n00" % INVENTORY_NAMES[index]
		slot.custom_minimum_size = Vector2(56.0, 46.0)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.focus_mode = Control.FOCUS_NONE
		slot.add_theme_font_size_override("font_size", 9)
		slot.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.20, 0.27, 0.94)))
		slot.add_theme_stylebox_override("hover", _button_style(Color(0.10, 0.34, 0.43, 0.98)))
		slot.add_theme_stylebox_override("pressed", _button_style(Color(0.13, 0.40, 0.49, 0.98)))
		slot.pressed.connect(_activate_hotbar_slot.bind(index))
		hotbar_row.add_child(slot)
		_hotbar_buttons.append(slot)
	_pickup_feedback = Label.new()
	_pickup_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_feedback.add_theme_font_size_override("font_size", 18)
	_pickup_feedback.add_theme_color_override("font_color", Color(1.0, 0.91, 0.56, 1.0))
	_pickup_feedback.add_theme_color_override("font_outline_color", Color(0.015, 0.035, 0.05, 0.95))
	_pickup_feedback.add_theme_constant_override("outline_size", 4)
	_pickup_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_feedback.visible = false
	_root.add_child(_pickup_feedback)

	_aim_dot = CenterAimDot.new()
	_aim_dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aim_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_dot.z_index = 20
	_root.add_child(_aim_dot)

	_pickup_audio = AudioStreamPlayer.new()
	_pickup_audio.stream = PICKUP_SOUND
	_pickup_audio.volume_db = -8.0
	add_child(_pickup_audio)
	_root.resized.connect(_layout_all)
	_layout_all()


func _create_mobile_controls() -> void:
	_mobile_controls = MOBILE_CONTROLS_SCRIPT.new()
	_mobile_controls.name = "MobileControls"
	_root.add_child(_mobile_controls)
	_mobile_controls.movement_changed.connect(_on_touch_movement)
	_mobile_controls.look_changed.connect(_on_touch_look)
	_mobile_controls.action_held.connect(_on_touch_action_held)
	_mobile_controls.action_pressed.connect(_on_touch_action_pressed)
	_mobile_controls.set_reserved_controls([
		_status_panel, _build_button, _inventory_button, _build_menu,
		_inventory_panel, _hotbar_panel,
	])


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
	var system_changed := candidate != _build_system
	if system_changed:
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
		native_hud.mode_bar.visible = true
		native_hud.catalog_panel.visible = false
		native_hud.info_panel.visible = false
		if system_changed:
			_layout_native_mode_bar()
			_layout_build_menu()
			_layout_inventory_panel()


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
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(_select_buildable.bind(buildable))
		_build_grid.add_child(button)


func _toggle_build_menu() -> void:
	if _build_system == null:
		return
	_inventory_panel.visible = false
	_build_menu.visible = not _build_menu.visible
	_mobile_controls.set_menu_open(_build_menu.visible)
	if _build_menu.visible:
		_focus_first_build_option()


func _focus_first_build_option() -> void:
	for child in _build_grid.get_children():
		var button := child as Button
		if button != null and button.visible:
			button.grab_focus()
			return


func _toggle_inventory() -> void:
	if _player == null:
		return
	_build_menu.visible = false
	_inventory_panel.visible = not _inventory_panel.visible
	_mobile_controls.set_menu_open(_inventory_panel.visible)


func _activate_hotbar_slot(index: int) -> void:
	if _player == null or index < 0 or index >= INVENTORY_NAMES.size():
		return
	_selected_hotbar_slot = index
	if index == 3:
		_player.call("_request_survival_action", "eat")
	elif index == 4:
		_player.call("_request_survival_action", "drink")
	_update_inventory_display()


func _cycle_hotbar(direction: int) -> void:
	var next_slot := posmod(_selected_hotbar_slot + direction, INVENTORY_NAMES.size())
	_selected_hotbar_slot = next_slot
	_update_inventory_display()


func _update_inventory_display() -> void:
	if _player == null:
		return
	var counts: Array[int] = [
		_player.wood_count,
		_player.plastic_count,
		_player.scrap_count,
		_player.food_count,
		_player.water_count,
	]
	if counts == _last_counts and _selected_hotbar_slot == _last_selected_hotbar_slot:
		return
	if not _last_counts.is_empty():
		for index in range(counts.size()):
			var gained := counts[index] - _last_counts[index]
			if gained > 0:
				_show_pickup_feedback(index, gained)
	_last_counts = counts.duplicate()
	_last_selected_hotbar_slot = _selected_hotbar_slot
	_inventory_details.text = "Madeira: %d\nPlástico: %d\nSucata: %d\nComida: %d\nÁgua: %d" % counts
	for index in range(_hotbar_buttons.size()):
		var slot := _hotbar_buttons[index]
		slot.text = "%s\n%02d" % [INVENTORY_NAMES[index], counts[index]]
		slot.tooltip_text = "%s: %d" % [INVENTORY_NAMES[index], counts[index]]
		var color := Color(0.10, 0.34, 0.43, 0.98) if index == _selected_hotbar_slot else Color(0.08, 0.20, 0.27, 0.94)
		slot.add_theme_stylebox_override("normal", _button_style(color))


func _show_pickup_feedback(index: int, amount: int) -> void:
	if index < 0 or index >= _hotbar_buttons.size() or amount <= 0:
		return
	_pickup_feedback.text = "+%d  %s" % [amount, INVENTORY_NAMES[index]]
	_pickup_feedback.visible = true
	_pickup_feedback.modulate = Color.WHITE
	_pickup_feedback_time = 1.15
	if _pickup_audio.playing:
		_pickup_audio.stop()
	_pickup_audio.play()

	var slot := _hotbar_buttons[index]
	var previous_tween := _slot_feedback_tweens.get(index) as Tween
	if previous_tween != null and previous_tween.is_running():
		previous_tween.kill()
	slot.pivot_offset = slot.size * 0.5
	slot.scale = Vector2.ONE
	slot.modulate = Color.WHITE
	var tween := create_tween()
	_slot_feedback_tweens[index] = tween
	tween.tween_property(slot, "scale", Vector2(1.09, 1.09), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(slot, "modulate", Color(1.0, 1.0, 0.68, 1.0), 0.10)
	tween.tween_property(slot, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(slot, "modulate", Color.WHITE, 0.24)


func _update_pickup_feedback(delta: float) -> void:
	if _pickup_feedback_time <= 0.0:
		return
	_pickup_feedback_time = maxf(0.0, _pickup_feedback_time - delta)
	var progress := 1.0 - _pickup_feedback_time / 1.15
	_pickup_feedback.offset_top = 72.0 - progress * 10.0
	_pickup_feedback.offset_bottom = 108.0 - progress * 10.0
	_pickup_feedback.modulate.a = clampf(_pickup_feedback_time / 0.3, 0.0, 1.0)
	if _pickup_feedback_time <= 0.0:
		_pickup_feedback.visible = false


func _layout_all() -> void:
	if _root == null or _status_panel == null:
		return
	_layout_status_panel()
	_layout_action_buttons()
	_layout_native_mode_bar()
	_layout_build_menu()
	_layout_inventory_panel()
	_layout_hotbar()
	_layout_pickup_feedback()


func _layout_status_panel() -> void:
	_status_panel.position = Vector2(12.0, 112.0 if _root.size.x < 680.0 else 12.0)


func _compact_action_top() -> float:
	var status_height := maxf(_status_panel.size.y, _status_panel.get_combined_minimum_size().y)
	return _status_panel.position.y + status_height + 8.0


func _layout_native_mode_bar() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var native_hud := scene.get_node_or_null("BuildingHUDLayer/PKBuildHUD") as PKBuildHUD
	if native_hud == null:
		return
	var mode_bar := native_hud.mode_bar
	mode_bar.visible = true
	mode_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var top := _compact_action_top() + 44.0 if _root.size.x < 680.0 else _compact_action_top()
	mode_bar.position = Vector2(12.0, top)


func _compact_menu_top() -> float:
	var top := _compact_action_top() + 44.0
	var scene := get_tree().current_scene
	if scene == null:
		return top
	var native_hud := scene.get_node_or_null("BuildingHUDLayer/PKBuildHUD") as PKBuildHUD
	if native_hud == null or not native_hud.mode_bar.visible:
		return top
	var bar_height := maxf(native_hud.mode_bar.size.y, native_hud.mode_bar.get_combined_minimum_size().y)
	return native_hud.mode_bar.position.y + bar_height + 8.0


func _layout_action_buttons() -> void:
	if _root.size.x < 680.0:
		var button_width := minf(96.0, maxf(72.0, (_root.size.x - 36.0) * 0.5))
		var top := _compact_action_top()
		_build_button.custom_minimum_size.x = button_width
		_build_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_build_button.offset_left = 12.0
		_build_button.offset_right = 12.0 + button_width
		_build_button.offset_top = top
		_build_button.offset_bottom = top + 36.0
		_inventory_button.custom_minimum_size.x = button_width
		_inventory_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_inventory_button.offset_left = 20.0 + button_width
		_inventory_button.offset_right = 20.0 + button_width * 2.0
		_inventory_button.offset_top = top
		_inventory_button.offset_bottom = top + 36.0
	else:
		_build_button.custom_minimum_size.x = 96.0
		_build_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_build_button.offset_left = -108.0
		_build_button.offset_right = -12.0
		_build_button.offset_top = 112.0
		_build_button.offset_bottom = 148.0
		_inventory_button.custom_minimum_size.x = 96.0
		_inventory_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_inventory_button.offset_left = -212.0
		_inventory_button.offset_right = -112.0
		_inventory_button.offset_top = 112.0
		_inventory_button.offset_bottom = 148.0


func _layout_build_menu() -> void:
	if _build_menu == null:
		return
	if _root.size.x < 680.0:
		var menu_top := _compact_menu_top()
		var menu_width := minf(224.0, maxf(160.0, _root.size.x - 24.0))
		_build_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_build_menu.offset_left = 12.0
		_build_menu.offset_right = 12.0 + menu_width
		_build_menu.offset_top = menu_top
		_build_menu.offset_bottom = menu_top + 152.0
	else:
		_build_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_build_menu.offset_left = -204.0
		_build_menu.offset_right = -12.0
		_build_menu.offset_top = 156.0
		_build_menu.offset_bottom = 292.0


func _layout_inventory_panel() -> void:
	if _inventory_panel == null:
		return
	if _root.size.x < 680.0:
		var panel_top := _compact_menu_top()
		var panel_width := minf(224.0, maxf(160.0, _root.size.x - 24.0))
		_inventory_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_inventory_panel.offset_left = 12.0
		_inventory_panel.offset_right = 12.0 + panel_width
		_inventory_panel.offset_top = panel_top
		_inventory_panel.offset_bottom = panel_top + 168.0
	else:
		_inventory_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_inventory_panel.offset_left = -212.0
		_inventory_panel.offset_right = -12.0
		_inventory_panel.offset_top = 156.0
		_inventory_panel.offset_bottom = 314.0


func _layout_pickup_feedback() -> void:
	if _pickup_feedback == null:
		return
	_pickup_feedback.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pickup_feedback.offset_left = -120.0
	_pickup_feedback.offset_right = 120.0
	_pickup_feedback.offset_top = 72.0
	_pickup_feedback.offset_bottom = 108.0


func _layout_hotbar() -> void:
	if _hotbar_panel == null or _root == null:
		return
	var slot_width := clampf((_root.size.x - 64.0) / 5.0, 32.0, 64.0)
	var panel_width := slot_width * 5.0 + 32.0
	var mobile := _mobile_controls != null and bool(_mobile_controls.get("touch_enabled"))
	var bottom_offset := -136.0 if mobile else -12.0
	_hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar_panel.offset_left = -panel_width * 0.5
	_hotbar_panel.offset_right = panel_width * 0.5
	_hotbar_panel.offset_top = bottom_offset - 56.0
	_hotbar_panel.offset_bottom = bottom_offset
	for slot in _hotbar_buttons:
		slot.custom_minimum_size = Vector2(slot_width, 46.0)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	if event.is_action_pressed("inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_menu"):
		_update_build_system()
		if _build_system != null:
			_toggle_build_menu()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hotbar_previous"):
		_cycle_hotbar(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hotbar_next"):
		_cycle_hotbar(1)
		get_viewport().set_input_as_handled()


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
