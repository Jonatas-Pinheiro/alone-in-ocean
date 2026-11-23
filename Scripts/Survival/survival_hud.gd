extends CanvasLayer

const BUILDABLE_BUTTON_SCENE: PackedScene = preload("res://Scenes/UI/BuildableButton.tscn")
const ICON_HEALTH := preload("res://Assets/UI/status_health.svg")
const ICON_HUNGER := preload("res://Assets/UI/status_hunger.svg")
const ICON_THIRST := preload("res://Assets/UI/status_thirst.svg")
const ICON_STAMINA := preload("res://Assets/UI/status_stamina.svg")
const PICKUP_SOUND := preload("res://Assets/Audio/pickup_chime.wav")
const INVENTORY_NAMES: Array[String] = ["Madeira", "Plástico", "Sucata", "Comida", "Água"]
const HOTBAR_SHORT_NAMES: Array[String] = ["Mad", "Plást", "Suc", "Com", "Água"]
const HOTBAR_KEY_LABELS: Array[String] = ["Z", "X", "C", "F", "G"]
const HOTBAR_ACTIONS: Array[StringName] = [&"hotbar_wood", &"hotbar_plastic", &"hotbar_scrap"]
const UI_REFRESH_INTERVAL := 0.1
const BUILD_SYSTEM_REFRESH_INTERVAL := 0.5

var _root: Control
var _settings_menu: Control
var _player: SurvivalPlayer
var _bars: Dictionary = {}
var _status_panel: PanelContainer
var _mobile_controls: Control
var _build_button: Button
var _build_menu: PanelContainer
var _build_grid: GridContainer
var _build_system: Node
var _inventory_button: Button
var _inventory_screen: Control
var _control_hints: PanelContainer
var _hotbar_panel: PanelContainer
var _hotbar_buttons: Array[Button] = []
var _last_counts: Array[int] = []
var _selected_hotbar_slot := 0
var _last_selected_hotbar_slot := -1
var _pickup_audio: AudioStreamPlayer
var _pickup_feedback: Label
var _pickup_feedback_time := 0.0
var _slot_feedback_tweens: Dictionary = {}
var _ui_refresh_elapsed := 0.0
var _build_system_refresh_elapsed := 0.0
var _inventory_previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _build_previous_mouse_mode := Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	layer = 5
	set_process_unhandled_input(true)
	_bind_scene_nodes()
	_connect_scene_signals()
	if not GameSettings.settings_changed.is_connected(_on_game_settings_changed):
		GameSettings.settings_changed.connect(_on_game_settings_changed)
	_layout_all()
	_mobile_controls.call("refresh_custom_layout")

func _process(delta: float) -> void:
	_update_pickup_feedback(delta)
	var local_id := 1
	var network_manager := get_parent().get_node_or_null("NetworkManager")
	if network_manager != null and network_manager.is_session_active():
		local_id = multiplayer.get_unique_id()
	else:
		_player = null
	if not is_instance_valid(_player) or _player.owner_peer_id != local_id:
		_player = _find_local_player(local_id)
		_last_counts.clear()
		_last_selected_hotbar_slot = -1
	var has_player := _player != null
	if not has_player:
		if GameSettings.is_inventory_open():
			_close_inventory(false)
		if GameSettings.is_build_menu_open():
			_close_build_menu(false)
		_root.visible = false
		_settings_menu.call("set_available", false)
		_mobile_controls.visible = false
		return
	_root.visible = GameSettings.hud_visible
	_settings_menu.call("set_available", true)
	var touch_controls_visible := bool(_mobile_controls.get("touch_enabled"))
	_mobile_controls.visible = touch_controls_visible
	_control_hints.visible = not touch_controls_visible
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
	_update_inventory_display()

func _find_local_player(peer_id: int) -> SurvivalPlayer:
	for node in get_tree().get_nodes_in_group("players"):
		if node is SurvivalPlayer and node.owner_peer_id == peer_id:
			return node as SurvivalPlayer
	return null

func _bind_scene_nodes() -> void:
	_root = $HudRoot
	_status_panel = $HudRoot/StatusPanel
	_bars = {
		&"health": $HudRoot/StatusPanel/StatusColumn/HealthRow/HealthBar,
		&"hunger": $HudRoot/StatusPanel/StatusColumn/HungerRow/HungerBar,
		&"thirst": $HudRoot/StatusPanel/StatusColumn/ThirstRow/ThirstBar,
		&"stamina": $HudRoot/StatusPanel/StatusColumn/StaminaRow/StaminaBar,
	}
	_build_button = $HudRoot/BuildButton
	_inventory_button = $HudRoot/InventoryButton
	_build_menu = $HudRoot/BuildMenu
	_build_grid = $HudRoot/BuildMenu/BuildMenuColumn/BuildGrid
	_inventory_screen = $HudRoot/InventoryScreen
	_control_hints = $HudRoot/ControlHints
	_hotbar_panel = $HudRoot/HotbarPanel
	_hotbar_buttons = [
		$HudRoot/HotbarPanel/HotbarRow/HotbarSlot1,
		$HudRoot/HotbarPanel/HotbarRow/HotbarSlot2,
		$HudRoot/HotbarPanel/HotbarRow/HotbarSlot3,
		$HudRoot/HotbarPanel/HotbarRow/HotbarSlot4,
		$HudRoot/HotbarPanel/HotbarRow/HotbarSlot5,
	]
	_pickup_feedback = $HudRoot/PickupFeedback
	_pickup_audio = $PickupAudio
	_mobile_controls = $HudRoot/MobileControls
	_settings_menu = $SettingsMenu
	_status_panel.add_theme_stylebox_override("panel", _panel_style())
	_build_menu.add_theme_stylebox_override("panel", _panel_style())
	_hotbar_panel.add_theme_stylebox_override("panel", _panel_style())
	for panel: PanelContainer in [_status_panel, _build_menu, _hotbar_panel]:
		panel.add_theme_constant_override("margin_left", 8)
		panel.add_theme_constant_override("margin_right", 8)
		panel.add_theme_constant_override("margin_top", 7)
		panel.add_theme_constant_override("margin_bottom", 7)
	_status_panel.add_theme_constant_override("margin_left", 10)
	_status_panel.add_theme_constant_override("margin_right", 10)
	$HudRoot/StatusPanel/StatusColumn.add_theme_constant_override("separation", 4)
	$HudRoot/BuildMenu/BuildMenuColumn/BuildGrid.add_theme_constant_override("h_separation", 6)
	$HudRoot/BuildMenu/BuildMenuColumn/BuildGrid.add_theme_constant_override("v_separation", 6)
	$HudRoot/HotbarPanel/HotbarRow.add_theme_constant_override("separation", 4)
	_build_button.add_theme_font_size_override("font_size", 11)
	_inventory_button.add_theme_font_size_override("font_size", 11)
	_pickup_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_feedback.add_theme_font_size_override("font_size", 18)
	_pickup_feedback.add_theme_color_override("font_color", Color(1.0, 0.91, 0.56, 1.0))
	_pickup_feedback.add_theme_color_override("font_outline_color", Color(0.015, 0.035, 0.05, 0.95))
	_pickup_feedback.add_theme_constant_override("outline_size", 4)
	var bar_colors := {
		&"health": Color(0.92, 0.25, 0.28),
		&"hunger": Color(0.98, 0.62, 0.18),
		&"thirst": Color(0.25, 0.68, 0.98),
		&"stamina": Color(0.40, 0.88, 0.48),
	}
	for key: StringName in _bars:
		var bar := _bars[key] as ProgressBar
		bar.add_theme_stylebox_override("background", _bar_style(Color(0.025, 0.045, 0.06, 0.82)))
		bar.add_theme_stylebox_override("fill", _bar_style(bar_colors[key]))
	for index in range(_hotbar_buttons.size()):
		var slot := _hotbar_buttons[index] as Button
		slot.add_theme_font_size_override("font_size", 9)
		slot.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.20, 0.27, 0.94)))
		slot.add_theme_stylebox_override("hover", _button_style(Color(0.10, 0.34, 0.43, 0.98)))
		slot.add_theme_stylebox_override("pressed", _button_style(Color(0.13, 0.40, 0.49, 0.98)))

func _connect_scene_signals() -> void:
	_build_button.pressed.connect(_toggle_build_menu)
	_inventory_button.pressed.connect(_toggle_inventory)
	$HudRoot/BuildMenu/BuildMenuColumn/RotateButton.pressed.connect(_rotate_build_piece)
	_inventory_screen.connect("close_requested", func() -> void: _close_inventory())
	_inventory_screen.connect("slot_pressed", _select_inventory_slot)
	for index in range(_hotbar_buttons.size()):
		(_hotbar_buttons[index] as Button).pressed.connect(_activate_hotbar_slot.bind(index))
	_mobile_controls.connect("movement_changed", _on_touch_movement)
	_mobile_controls.connect("look_changed", _on_touch_look)
	_mobile_controls.connect("action_held", _on_touch_action_held)
	_mobile_controls.connect("action_pressed", _on_touch_action_pressed)
	_settings_menu.call("set_mobile_controls", _mobile_controls)
	_settings_menu.connect("opened", _on_settings_opened)
	_mobile_controls.call("set_reserved_controls", _get_mobile_reserved_controls())
	_root.resized.connect(_layout_all)

func _get_mobile_reserved_controls() -> Array:
	var controls: Array = [
		_status_panel, _build_button, _inventory_button, _build_menu,
		_inventory_screen, _hotbar_panel, _control_hints,
	]
	if _settings_menu != null:
		var settings_button := _settings_menu.get("settings_button") as Control
		if settings_button != null:
			controls.append(settings_button)
	return controls

func _on_settings_opened() -> void:
	_build_menu.visible = false
	if GameSettings.is_build_menu_open():
		if _build_previous_mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_settings_menu.set("_previous_mouse_mode", Input.MOUSE_MODE_CAPTURED)
		GameSettings.set_build_menu_open(false)
	if _inventory_screen.visible:
		_inventory_screen.call("close_screen")
		GameSettings.set_inventory_open(false)
		if _inventory_previous_mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_settings_menu.set("_previous_mouse_mode", Input.MOUSE_MODE_CAPTURED)
	_mobile_controls.set_menu_open(true)

func _on_game_settings_changed() -> void:
	_layout_all()

func _update_build_system() -> void:
	var scene := get_tree().current_scene
	var setup := scene.get_node_or_null("BuildingKitSetup") if scene != null else null
	var candidate: Node = setup.get("build_system") as Node if setup != null else null
	var system_changed := candidate != _build_system
	if system_changed:
		_build_system = candidate
		if _build_menu.visible:
			_close_build_menu(false)
		if _build_system != null:
			_rebuild_build_menu()
	_build_button.visible = _build_system != null
	if _build_system == null:
		_build_menu.visible = false
		GameSettings.set_build_menu_open(false)
		return
	_hide_native_build_hud()
	_layout_build_menu()
	_mobile_controls.call("set_reserved_controls", _get_mobile_reserved_controls())

func _hide_native_build_hud() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var native_hud := scene.get_node_or_null("BuildingHUDLayer/PKBuildHUD") as Control
	if native_hud == null:
		return
	native_hud.visible = false
	for property_name: String in ["mode_bar", "catalog_panel", "info_panel"]:
		var panel := native_hud.get(property_name) as Control
		if panel != null:
			panel.visible = false

func _rebuild_build_menu() -> void:
	for child in _build_grid.get_children():
		child.queue_free()
	if _build_system == null:
		return
	var catalog: PKCatalog = _build_system.get("catalog") as PKCatalog
	if catalog == null:
		return
	var shortcut_index := 0
	for buildable: PKBuildable in catalog.buildables:
		if buildable == null or not buildable.in_catalog:
			continue
		shortcut_index += 1
		var button := BUILDABLE_BUTTON_SCENE.instantiate() as Button
		button.text = "%s  [%d]" % [buildable.get_title(), shortcut_index]
		button.tooltip_text = buildable.description
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(_select_buildable.bind(buildable))
		_build_grid.add_child(button)

func _toggle_build_menu() -> void:
	if _player == null or GameSettings.is_settings_open() or _build_system == null:
		return
	if _build_menu.visible:
		_close_build_menu(true)
		return
	if _inventory_screen.visible:
		_close_inventory(true)
	_build_previous_mouse_mode = Input.mouse_mode
	_build_menu.visible = true
	GameSettings.set_build_menu_open(true)
	_mobile_controls.set_menu_open(true)
	if not bool(_mobile_controls.get("touch_enabled")):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_focus_first_build_option()

func _close_build_menu(restore_mouse: bool = true) -> void:
	if not _build_menu.visible and not GameSettings.is_build_menu_open():
		return
	_build_menu.visible = false
	GameSettings.set_build_menu_open(false)
	if _mobile_controls != null:
		_mobile_controls.set_menu_open(GameSettings.is_gameplay_ui_open())
	if restore_mouse and _mobile_controls != null and not bool(_mobile_controls.get("touch_enabled")):
		Input.mouse_mode = _build_previous_mouse_mode

func _focus_first_build_option() -> void:
	for child in _build_grid.get_children():
		var button := child as Button
		if button != null and button.visible:
			button.grab_focus()
			return

func _select_buildable_by_index(index: int) -> void:
	var options := _build_grid.get_children()
	if index < 0 or index >= options.size():
		return
	var button := options[index] as Button
	if button == null or not button.visible:
		return
	button.emit_signal("pressed")

func _toggle_inventory() -> void:
	if _player == null or GameSettings.is_settings_open():
		return
	if _inventory_screen.visible:
		_close_inventory(true)
		return
	if _build_menu.visible:
		_close_build_menu(true)
	_inventory_previous_mouse_mode = Input.mouse_mode
	_inventory_screen.call("open_screen")
	GameSettings.set_inventory_open(true)
	_mobile_controls.set_menu_open(true)
	_update_inventory_display()
	if not bool(_mobile_controls.get("touch_enabled")):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_inventory(restore_mouse: bool = true) -> void:
	if not _inventory_screen.visible and not GameSettings.is_inventory_open():
		return
	_inventory_screen.call("close_screen")
	GameSettings.set_inventory_open(false)
	if _mobile_controls != null:
		_mobile_controls.set_menu_open(GameSettings.is_gameplay_ui_open())
	if restore_mouse and _mobile_controls != null and not bool(_mobile_controls.get("touch_enabled")):
		Input.mouse_mode = _inventory_previous_mouse_mode

func _activate_hotbar_slot(index: int) -> void:
	if _player == null or index < 0 or index >= INVENTORY_NAMES.size():
		return
	_selected_hotbar_slot = index
	if index == 3:
		_player.call("_request_survival_action", "eat")
	elif index == 4:
		_player.call("_request_survival_action", "drink")
	_update_inventory_display()

func _select_inventory_slot(index: int) -> void:
	_activate_hotbar_slot(index)

func _cycle_hotbar(direction: int) -> void:
	_selected_hotbar_slot = posmod(_selected_hotbar_slot + direction, INVENTORY_NAMES.size())
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
	_inventory_screen.call("set_items", counts, _selected_hotbar_slot)
	for index in range(_hotbar_buttons.size()):
		var slot := _hotbar_buttons[index]
		slot.text = "%s  %s\n×%02d" % [HOTBAR_KEY_LABELS[index], HOTBAR_SHORT_NAMES[index], counts[index]]
		slot.tooltip_text = "%s [%s]: %d" % [INVENTORY_NAMES[index], HOTBAR_KEY_LABELS[index], counts[index]]
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
	tween.tween_property(slot, "scale", Vector2(1.06, 1.06), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	_layout_build_menu()
	_layout_control_hints()
	_layout_hotbar()
	_layout_pickup_feedback()
	_layout_settings_button()
	_apply_hud_scale()
	if _mobile_controls != null:
		_mobile_controls.call("refresh_custom_layout")

func _layout_status_panel() -> void:
	_status_panel.position = Vector2(12.0, 112.0 if _root.size.x < 680.0 else 12.0)

func _compact_action_top() -> float:
	var status_height := maxf(_status_panel.size.y, _status_panel.get_combined_minimum_size().y)
	return _status_panel.position.y + status_height + 8.0

func _layout_action_buttons() -> void:
	if _root.size.x < 680.0:
		var button_width := maxf(88.0, minf(166.0, (_root.size.x - 36.0) * 0.5))
		var top := _compact_action_top()
		for button: Button in [_build_button, _inventory_button]:
			button.set_anchors_preset(Control.PRESET_TOP_LEFT)
			button.custom_minimum_size.x = button_width
			button.offset_top = top
			button.offset_bottom = top + 38.0
		_build_button.offset_left = 12.0
		_build_button.offset_right = 12.0 + button_width
		_inventory_button.offset_left = 20.0 + button_width
		_inventory_button.offset_right = 20.0 + button_width * 2.0
	else:
		_build_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_build_button.custom_minimum_size.x = 110.0
		_build_button.offset_left = -306.0
		_build_button.offset_right = -196.0
		_build_button.offset_top = 12.0
		_build_button.offset_bottom = 48.0
		_inventory_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_inventory_button.custom_minimum_size.x = 112.0
		_inventory_button.offset_left = -186.0
		_inventory_button.offset_right = -74.0
		_inventory_button.offset_top = 12.0
		_inventory_button.offset_bottom = 48.0

func _layout_build_menu() -> void:
	if _build_menu == null:
		return
	if _root.size.x < 680.0:
		var menu_top := _compact_action_top() + 46.0
		var menu_width := minf(340.0, maxf(180.0, _root.size.x - 24.0))
		_build_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_build_menu.offset_left = 12.0
		_build_menu.offset_right = 12.0 + menu_width
		_build_menu.offset_top = menu_top
		_build_menu.offset_bottom = menu_top + 230.0
	else:
		_build_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_build_menu.offset_left = -330.0
		_build_menu.offset_right = -12.0
		_build_menu.offset_top = 56.0
		_build_menu.offset_bottom = 286.0

func _layout_control_hints() -> void:
	var top := _status_panel.position.y + maxf(_status_panel.size.y, _status_panel.get_combined_minimum_size().y) + 8.0
	var hint_width := minf(360.0, maxf(220.0, _root.size.x - 24.0))
	_control_hints.position = Vector2(12.0, top)
	_control_hints.custom_minimum_size = Vector2(hint_width, 76.0)
	_control_hints.size = Vector2(hint_width, 76.0)

func _layout_settings_button() -> void:
	if _settings_menu == null:
		return
	var button := _settings_menu.get("settings_button") as Button
	if button == null:
		return
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.custom_minimum_size = Vector2(58.0, 36.0)
	button.offset_left = -70.0
	button.offset_right = -12.0
	button.offset_top = 12.0
	button.offset_bottom = 48.0

func _apply_hud_scale() -> void:
	if _root == null or _status_panel == null:
		return
	var scale_factor := GameSettings.hud_scale
	var compact := _root.size.x < 680.0
	_apply_control_scale(_status_panel, scale_factor, Vector2.ZERO)
	_apply_control_scale(_build_button, scale_factor, Vector2(1.0, 0.0) if not compact else Vector2.ZERO)
	_apply_control_scale(_inventory_button, scale_factor, Vector2(1.0, 0.0) if not compact else Vector2.ZERO)
	_apply_control_scale(_build_menu, scale_factor, Vector2(1.0, 0.0) if not compact else Vector2.ZERO)
	_apply_control_scale(_hotbar_panel, scale_factor, Vector2(0.5, 1.0))
	_apply_control_scale(_control_hints, scale_factor, Vector2.ZERO)
	_apply_control_scale(_pickup_feedback, scale_factor, Vector2(0.5, 0.0))
	var settings_button := _settings_menu.get("settings_button") as Control if _settings_menu != null else null
	if settings_button != null:
		_apply_control_scale(settings_button, scale_factor, Vector2(1.0, 0.0))

func _apply_control_scale(control: Control, scale_factor: float, normalized_pivot: Vector2) -> void:
	if not is_instance_valid(control):
		return
	control.pivot_offset = control.size * normalized_pivot
	control.scale = Vector2.ONE * scale_factor

func _layout_hotbar() -> void:
	if _hotbar_panel == null or _root == null:
		return
	var slot_width := clampf((_root.size.x - 32.0) / 5.0, 48.0, 68.0)
	var panel_width := slot_width * 5.0 + 32.0
	var mobile := _mobile_controls != null and bool(_mobile_controls.get("touch_enabled"))
	var bottom_offset := -136.0 if mobile else -10.0
	_hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar_panel.offset_left = -panel_width * 0.5
	_hotbar_panel.offset_right = panel_width * 0.5
	_hotbar_panel.offset_top = bottom_offset - 56.0
	_hotbar_panel.offset_bottom = bottom_offset
	for slot in _hotbar_buttons:
		slot.custom_minimum_size = Vector2(slot_width, 46.0)

func _layout_pickup_feedback() -> void:
	if _pickup_feedback == null:
		return
	_pickup_feedback.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pickup_feedback.offset_left = -120.0
	_pickup_feedback.offset_right = 120.0
	_pickup_feedback.offset_top = 72.0
	_pickup_feedback.offset_bottom = 108.0

func _unhandled_input(event: InputEvent) -> void:
	if _player == null or GameSettings.is_settings_open():
		return
	if event.is_action_pressed(&"inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"build_menu"):
		_update_build_system()
		if _build_system != null:
			_toggle_build_menu()
		get_viewport().set_input_as_handled()
		return
	for index in range(HOTBAR_ACTIONS.size()):
		if event.is_action_pressed(HOTBAR_ACTIONS[index]):
			_activate_hotbar_slot(index)
			get_viewport().set_input_as_handled()
			return
	if _inventory_screen.visible:
		if event.is_action_pressed(&"consume_food"):
			_activate_hotbar_slot(3)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"drink_water"):
			_activate_hotbar_slot(4)
			get_viewport().set_input_as_handled()
			return
	if _build_menu.visible:
		for index in range(4):
			var action := StringName("build_select_%d" % (index + 1))
			if event.is_action_pressed(action):
				_select_buildable_by_index(index)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed(&"hotbar_previous"):
		_cycle_hotbar(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"hotbar_next"):
		_cycle_hotbar(1)
		get_viewport().set_input_as_handled()

func _select_buildable(buildable: PKBuildable) -> void:
	if _build_system == null:
		return
	_build_system.set_mode(PKBuildController.Mode.BUILD)
	_build_system.select_buildable(buildable)
	_close_build_menu(true)

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
	style.bg_color = Color(0.025, 0.055, 0.075, 0.88)
	style.border_color = Color(0.67, 0.83, 0.91, 0.30)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	return style

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.72, 0.86, 0.94, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style

func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style
