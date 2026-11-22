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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_controls()
	resized.connect(_layout_panel)
	GameSettings.settings_changed.connect(_sync_controls)
	_sync_controls()


func set_mobile_controls(controls: Control) -> void:
	_mobile_controls = controls
	_update_mobile_controls_visibility()


func set_available(available: bool) -> void:
	settings_button.visible = available
	if not available and GameSettings.is_settings_open():
		_close(false)


func _create_controls() -> void:
	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "⚙"
	settings_button.tooltip_text = "Configurações (F2 / Touchpad)"
	settings_button.custom_minimum_size = Vector2(44.0, 42.0)
	settings_button.focus_mode = Control.FOCUS_ALL
	settings_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	settings_button.offset_left = -58.0
	settings_button.offset_right = -12.0
	settings_button.offset_top = 10.0
	settings_button.offset_bottom = 54.0
	settings_button.add_theme_font_size_override("font_size", 23)
	settings_button.add_theme_stylebox_override("normal", _button_style(Color(0.04, 0.12, 0.18, 0.88)))
	settings_button.add_theme_stylebox_override("hover", _button_style(Color(0.08, 0.25, 0.32, 0.96)))
	settings_button.pressed.connect(_toggle)
	add_child(settings_button)

	_overlay = Control.new()
	_overlay.name = "SettingsModal"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.005, 0.018, 0.025, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.name = "SettingsPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_overlay.add_child(_panel)
	var panel_column := VBoxContainer.new()
	panel_column.add_theme_constant_override("separation", 8)
	_panel.add_child(panel_column)

	var title := Label.new()
	title.text = "CONFIGURAÇÕES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	panel_column.add_child(title)
	var instructions := Label.new()
	instructions.text = "F2 / Touchpad para abrir ou fechar · Setas, D-pad e Tab para navegar"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_font_size_override("font_size", 11)
	instructions.add_theme_color_override("font_color", Color(0.68, 0.84, 0.9))
	panel_column.add_child(instructions)
	panel_column.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_column.add_child(_scroll)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 7)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(options)

	_shadows_toggle = _make_toggle("Sombras ativas")
	_shadows_toggle.toggled.connect(GameSettings.set_shadows_enabled)
	options.add_child(_shadows_toggle)
	options.add_child(_make_label("Resolução 3D"))
	_render_scale_option = _make_option(["100% · nativa", "75% · desempenho", "50% · desempenho máximo"])
	_render_scale_option.item_selected.connect(_on_render_scale_selected)
	options.add_child(_render_scale_option)

	_names_toggle = _make_toggle("Exibir nomes dos outros jogadores")
	_names_toggle.toggled.connect(GameSettings.set_show_player_names)
	options.add_child(_names_toggle)
	_hud_visible_toggle = _make_toggle("Exibir HUD")
	_hud_visible_toggle.toggled.connect(GameSettings.set_hud_visible)
	options.add_child(_hud_visible_toggle)
	options.add_child(_make_label("Tamanho geral da HUD"))
	_hud_scale_option = _make_option(["80% · compacta", "100% · normal", "120% · ampliada"])
	_hud_scale_option.item_selected.connect(_on_hud_scale_selected)
	options.add_child(_hud_scale_option)

	_mobile_controls_hint = _make_label("Botões móveis")
	options.add_child(_mobile_controls_hint)
	_mobile_scale_option = _make_option(["Botões 80%", "Botões 100%", "Botões 120%"])
	_mobile_scale_option.item_selected.connect(_on_mobile_scale_selected)
	options.add_child(_mobile_scale_option)
	_mobile_edit_toggle = _make_toggle("Editar posição dos botões móveis")
	_mobile_edit_toggle.toggled.connect(_on_mobile_edit_toggled)
	options.add_child(_mobile_edit_toggle)
	var mobile_hint := _make_label("Ative, feche o painel e arraste cada botão. Joystick, mira, hotbar e áreas interativas ficam protegidos.")
	mobile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mobile_hint.add_theme_font_size_override("font_size", 10)
	options.add_child(mobile_hint)
	var reset_layout := Button.new()
	reset_layout.text = "Restaurar posição dos botões"
	reset_layout.focus_mode = Control.FOCUS_ALL
	reset_layout.pressed.connect(_reset_mobile_layout)
	options.add_child(reset_layout)

	var close_button := Button.new()
	close_button.text = "Fechar"
	close_button.custom_minimum_size.y = 38.0
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.pressed.connect(func() -> void: _close())
	panel_column.add_child(close_button)
	_layout_panel()


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


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	return label


func _make_toggle(text: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return toggle


func _make_option(items: Array[String]) -> OptionButton:
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_ALL
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		option.add_item(item)
	return option


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
	_mobile_controls.set_menu_open(true)
	opened.emit()
	_sync_controls()
	_shadows_toggle.grab_focus()


func _close(restore_mouse: bool = true) -> void:
	if not GameSettings.is_settings_open():
		return
	_overlay.visible = false
	GameSettings.set_settings_open(false)
	if is_instance_valid(_mobile_controls):
		_mobile_controls.set_menu_open(false)
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
		_mobile_controls.refresh_custom_layout()


func _on_mobile_edit_toggled(enabled: bool) -> void:
	if is_instance_valid(_mobile_controls):
		_mobile_controls.set_edit_mode(enabled)


func _reset_mobile_layout() -> void:
	GameSettings.reset_mobile_button_positions()
	if is_instance_valid(_mobile_controls):
		_mobile_controls.refresh_custom_layout()


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
