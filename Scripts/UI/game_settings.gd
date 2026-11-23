extends Node

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_RENDER_SCALE := 1.0
const MIN_RENDER_SCALE := 0.5
const MAX_RENDER_SCALE := 1.0

var shadows_enabled := true
var render_scale := DEFAULT_RENDER_SCALE
var show_player_names := true
var hud_visible := true
var hud_scale := 1.0
var mobile_button_scale := 1.0
var mobile_button_positions: Dictionary = {}
var settings_open := false
var inventory_open := false
var build_menu_open := false


func _ready() -> void:
	_load_settings()
	_ensure_settings_action()
	_apply_render_scale()
	_apply_shadows_to_scene()
	_apply_names_to_scene()


func apply_current_scene_preferences() -> void:
	_apply_shadows_to_scene()
	_apply_names_to_scene()


func set_settings_open(open: bool) -> void:
	settings_open = open


func is_settings_open() -> bool:
	return settings_open


func set_inventory_open(open: bool) -> void:
	inventory_open = open


func is_inventory_open() -> bool:
	return inventory_open


func set_build_menu_open(open: bool) -> void:
	build_menu_open = open


func is_build_menu_open() -> bool:
	return build_menu_open


func is_gameplay_ui_open() -> bool:
	return settings_open or inventory_open or build_menu_open


func set_shadows_enabled(enabled: bool) -> void:
	if shadows_enabled == enabled:
		_apply_shadows_to_scene()
		return
	shadows_enabled = enabled
	_save_settings()
	_apply_shadows_to_scene()
	settings_changed.emit()


func apply_shadow_preference(light: Light3D) -> void:
	if is_instance_valid(light):
		light.shadow_enabled = shadows_enabled


func set_render_scale(scale: float) -> void:
	var next_scale := clampf(scale, MIN_RENDER_SCALE, MAX_RENDER_SCALE)
	if is_equal_approx(render_scale, next_scale):
		_apply_render_scale()
		return
	render_scale = next_scale
	_save_settings()
	_apply_render_scale()
	settings_changed.emit()


func set_show_player_names(show: bool) -> void:
	if show_player_names == show:
		_apply_names_to_scene()
		return
	show_player_names = show
	_save_settings()
	_apply_names_to_scene()
	settings_changed.emit()


func should_show_name_for_player(is_local_player: bool) -> bool:
	return show_player_names and not is_local_player


func apply_player_name_visibility(player: Node, is_local_player: bool) -> void:
	if is_instance_valid(player) and player.has_method("set_name_tag_visible"):
		player.call("set_name_tag_visible", should_show_name_for_player(is_local_player))


func set_hud_visible(show: bool) -> void:
	if hud_visible == show:
		return
	hud_visible = show
	_save_settings()
	settings_changed.emit()


func set_hud_scale(scale: float) -> void:
	var next_scale := clampf(scale, 0.8, 1.2)
	if is_equal_approx(hud_scale, next_scale):
		return
	hud_scale = next_scale
	_save_settings()
	settings_changed.emit()


func set_mobile_button_scale(scale: float) -> void:
	var next_scale := clampf(scale, 0.8, 1.2)
	if is_equal_approx(mobile_button_scale, next_scale):
		return
	mobile_button_scale = next_scale
	_save_settings()
	settings_changed.emit()


func set_mobile_button_position(action: StringName, normalized_position: Vector2) -> void:
	var position := normalized_position.clamp(Vector2.ZERO, Vector2.ONE)
	mobile_button_positions[String(action)] = position
	_save_settings()


func get_mobile_button_position(action: StringName) -> Vector2:
	var value: Variant = mobile_button_positions.get(String(action), Vector2(-1.0, -1.0))
	return value as Vector2 if value is Vector2 else Vector2(-1.0, -1.0)


func reset_mobile_button_positions() -> void:
	mobile_button_positions.clear()
	_save_settings()
	settings_changed.emit()


func _apply_render_scale() -> void:
	var root_viewport := get_tree().root
	root_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root_viewport.scaling_3d_scale = render_scale


func _apply_shadows_to_scene() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		_apply_shadows_recursive(scene)


func _apply_shadows_recursive(node: Node) -> void:
	if node is Light3D:
		(node as Light3D).shadow_enabled = shadows_enabled
	for child in node.get_children():
		_apply_shadows_recursive(child)


func _apply_names_to_scene() -> void:
	for node in get_tree().get_nodes_in_group("players"):
		if node.has_method("set_name_tag_visible"):
			var is_local := int(node.get("owner_peer_id")) == multiplayer.get_unique_id()
			apply_player_name_visibility(node, is_local)


func _ensure_settings_action() -> void:
	const ACTION := &"settings_menu"
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var keyboard := InputEventKey.new()
	keyboard.physical_keycode = KEY_F2
	InputMap.action_add_event(ACTION, keyboard)
	var controller := InputEventJoypadButton.new()
	controller.button_index = JOY_BUTTON_MISC1
	InputMap.action_add_event(ACTION, controller)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	shadows_enabled = bool(config.get_value("graphics", "shadows_enabled", shadows_enabled))
	render_scale = clampf(float(config.get_value("graphics", "render_scale", render_scale)), MIN_RENDER_SCALE, MAX_RENDER_SCALE)
	show_player_names = bool(config.get_value("hud", "show_player_names", show_player_names))
	hud_visible = bool(config.get_value("hud", "visible", hud_visible))
	hud_scale = clampf(float(config.get_value("hud", "scale", hud_scale)), 0.8, 1.2)
	mobile_button_scale = clampf(float(config.get_value("mobile", "button_scale", mobile_button_scale)), 0.8, 1.2)
	var saved_positions: Variant = config.get_value("mobile", "button_positions", {})
	if saved_positions is Dictionary:
		mobile_button_positions = (saved_positions as Dictionary).duplicate(true)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "shadows_enabled", shadows_enabled)
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("hud", "show_player_names", show_player_names)
	config.set_value("hud", "visible", hud_visible)
	config.set_value("hud", "scale", hud_scale)
	config.set_value("mobile", "button_scale", mobile_button_scale)
	config.set_value("mobile", "button_positions", mobile_button_positions.duplicate(true))
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Não foi possível salvar as configurações locais (erro %d)." % error)
