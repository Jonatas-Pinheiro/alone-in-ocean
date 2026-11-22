extends Control

signal opened
signal closed

var settings_button: Button
var _overlay: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _mobile_controls: Control
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _shadows_toggle: CheckButton
var _names_toggle: CheckButton
var _hud_visible_toggle: CheckButton
var _hud_scale_option: OptionButton
var _render_scale_option: OptionButton
var _mobile_edit_toggle: CheckButton
var _mobile_scale_option: OptionButton
var _mobile_controls_hint: Label


func _ready() -> void:
	settings_button = $SettingsButton
	_overlay = $SettingsModal
	_panel = $SettingsModal/SettingsPanel
	_scroll = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll
	_shadows_toggle = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/ShadowsToggle
	_names_toggle = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/NamesToggle
	_hud_visible_toggle = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/HudVisibleToggle
	_hud_scale_option = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/HudScaleOption
	_render_scale_option = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/RenderScaleOption
	_mobile_edit_toggle = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/MobileEditToggle
	_mobile_scale_option = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/MobileScaleOption
	_mobile_controls_hint = $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/MobileControlsHint

	for label in ["100% · nativa", "75% · desempenho", "50% · desempenho máximo"]:
		_render_scale_option.add_item(label)
	for label in ["80% · compacta", "100% · normal", "120% · ampliada"]:
		_hud_scale_option.add_item(label)
	for label in ["Botões 80%", "Botões 100%", "Botões 120%"]:
		_mobile_scale_option.add_item(label)

	_panel.add_theme_stylebox_override("panel", _panel_style())
	settings_button.add_theme_stylebox_override("normal", _button_style(Color(0.04, 0.12, 0.18, 0.88)))
	settings_button.add_theme_stylebox_override("hover", _button_style(Color(0.08, 0.25, 0.32, 0.96)))
	settings_button.pressed.connect(_toggle)
	_shadows_toggle.toggled.connect(GameSettings.set_shadows_enabled)
	_names_toggle.toggled.connect(GameSettings.set_show_player_names)
	_hud_visible_toggle.toggled.connect(GameSettings.set_hud_visible)
	_render_scale_option.item_selected.connect(_on_render_scale_selected)
	_hud_scale_option.item_selected.connect(_on_hud_scale_selected)
	_mobile_scale_option.item_selected.connect(_on_mobile_scale_selected)
	_mobile_edit_toggle.toggled.connect(_on_mobile_edit_toggled)
	$SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/ResetMobileLayout.pressed.connect(_reset_mobile_layout)
	$SettingsModal/SettingsPanel/PanelColumn/CloseButton.pressed.connect(_close)
	resized.connect(_layout_panel)
	GameSettings.settings_changed.connect(_sync_controls)
	_sync_controls()
	_layout_panel()


func set_mobile_controls(controls: Control) -> void:
	_mobile_controls = controls
	_update_mobile_controls_visibility()


func set_available(available: bool) -> void:
	settings_button.visible = available
	if not available and GameSettings.is_settings_open():
		_close(false)


func _layout_panel() -> void:
	if _panel == null or _scroll == null:
		return
	var width := minf(480.0, maxf(280.0, size.x - 24.0))
	var height := minf(590.0, maxf(280.0, size.y - 24.0))
	_panel.custom_minimum_size = Vector2(width, height)
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -height * 0.5
	_panel.offset_bottom = height * 0.5
	_scroll.custom_minimum_size = Vector2(width - 48.0, maxf(115.0, height - 290.0))


func _toggle() -> void:
	if GameSettings.is_settings_open():
		_close()
	else:
		_open()


func _open() -> void:
	if GameSettings.is_settings_open():
		return
	if not _is_mobile():
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.set_settings_open(true)
	_overlay.visible = true
	if is_instance_valid(_mobile_controls):
		_mobile_controls.call("set_menu_open", true)
	opened.emit()
	_sync_controls()
	_shadows_toggle.grab_focus()


func _close(restore_mouse: bool = true) -> void:
	if not GameSettings.is_settings_open():
		return
	_overlay.visible = false
	GameSettings.set_settings_open(false)
	if is_instance_valid(_mobile_controls):
		_mobile_controls.call("set_menu_open", false)
	closed.emit()
	if restore_mouse and not _is_mobile():
		Input.mouse_mode = _previous_mouse_mode


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"settings_menu"):
		return
	if GameSettings.is_settings_open():
		_close()
	else:
		_open()
	get_viewport().set_input_as_handled()


func _on_render_scale_selected(index: int) -> void:
	var scales: Array[float] = [1.0, 0.75, 0.5]
	GameSettings.set_render_scale(scales[clampi(index, 0, scales.size() - 1)])


func _on_hud_scale_selected(index: int) -> void:
	var scales: Array[float] = [0.8, 1.0, 1.2]
	GameSettings.set_hud_scale(scales[clampi(index, 0, scales.size() - 1)])


func _on_mobile_scale_selected(index: int) -> void:
	var scales: Array[float] = [0.8, 1.0, 1.2]
	GameSettings.set_mobile_button_scale(scales[clampi(index, 0, scales.size() - 1)])
	if is_instance_valid(_mobile_controls):
		_mobile_controls.call("refresh_custom_layout")


func _on_mobile_edit_toggled(enabled: bool) -> void:
	if is_instance_valid(_mobile_controls):
		_mobile_controls.call("set_edit_mode", enabled)


func _reset_mobile_layout() -> void:
	GameSettings.reset_mobile_button_positions()
	if is_instance_valid(_mobile_controls):
		_mobile_controls.call("refresh_custom_layout")


func _sync_controls() -> void:
	if _shadows_toggle == null:
		return
	_shadows_toggle.button_pressed = GameSettings.shadows_enabled
	_names_toggle.button_pressed = GameSettings.show_player_names
	_hud_visible_toggle.button_pressed = GameSettings.hud_visible
	_render_scale_option.select(_scale_index(GameSettings.render_scale, [1.0, 0.75, 0.5]))
	_hud_scale_option.select(_scale_index(GameSettings.hud_scale, [0.8, 1.0, 1.2]))
	_mobile_scale_option.select(_scale_index(GameSettings.mobile_button_scale, [0.8, 1.0, 1.2]))
	_update_mobile_controls_visibility()


func _update_mobile_controls_visibility() -> void:
	var mobile := _is_mobile()
	if _mobile_controls_hint != null:
		_mobile_controls_hint.visible = mobile
	if _mobile_scale_option != null:
		_mobile_scale_option.visible = mobile
	if _mobile_edit_toggle != null:
		_mobile_edit_toggle.visible = mobile
	var mobile_hint := $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/MobileHint as Control
	if mobile_hint != null:
		mobile_hint.visible = mobile
	var reset_button := $SettingsModal/SettingsPanel/PanelColumn/SettingsScroll/Options/ResetMobileLayout as Control
	if reset_button != null:
		reset_button.visible = mobile


func _is_mobile() -> bool:
	return _mobile_controls != null and bool(_mobile_controls.get("touch_enabled"))


func _scale_index(value: float, choices: Array[float]) -> int:
	for index in range(choices.size()):
		if is_equal_approx(value, choices[index]):
			return index
	return 0


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.09, 0.14, 0.98)
	style.border_color = Color(0.18, 0.58, 0.72, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.72, 0.88, 0.96, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style
