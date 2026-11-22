extends Node

const SERVER_ID := 1
const DAY_DURATION_SECONDS := 12.0 * 60.0
const NIGHT_DURATION_SECONDS := 12.0 * 60.0
const CYCLE_DURATION_SECONDS := DAY_DURATION_SECONDS + NIGHT_DURATION_SECONDS
const START_TIME_MINUTES := 6 * 60
const SYNC_INTERVAL_SECONDS := 1.0
const DAY_SKY: Texture2D = preload("res://kenney_skyboxes/Skyboxes/skybox-day.png")
const NIGHT_SKY: Texture2D = preload("res://kenney_skyboxes/Skyboxes/skybox-night.png")
const DAY_AMBIENT_COLOR := Color(0.72, 0.82, 0.96)
const NIGHT_AMBIENT_COLOR := Color(0.12, 0.17, 0.30)
const SUN_MAX_ENERGY := 3.027

var _network_manager: Node
var _sun: DirectionalLight3D
var _world_environment: WorldEnvironment
var _panorama_material: PanoramaSkyMaterial
var _elapsed_seconds := 0.0
var _session_active := false
var _sync_timer := 0.0
var _last_hud_second := -1

var _hud: CanvasLayer
var _clock_panel: PanelContainer
var _time_label: Label
var _countdown_label: Label
var _phase_bar: ProgressBar


func _ready() -> void:
	set_multiplayer_authority(SERVER_ID)
	_network_manager = get_parent().get_node_or_null("NetworkManager")
	_sun = get_parent().get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	_world_environment = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _world_environment != null and _world_environment.environment != null:
		var sky := _world_environment.environment.sky
		if sky != null:
			_panorama_material = sky.sky_material as PanoramaSkyMaterial
	GameSettings.apply_current_scene_preferences()
	_bind_hud()
	GameSettings.settings_changed.connect(_on_game_settings_changed)
	_apply_world_state()
	_update_hud()


func _process(delta: float) -> void:
	var session_is_active := _network_manager != null \
		and _network_manager.has_method("is_session_active") \
		and bool(_network_manager.call("is_session_active"))
	var session_changed := session_is_active != _session_active
	if session_changed:
		_session_active = session_is_active
		if _session_active:
			# Toda sessão começa ao amanhecer; o anfitrião mantém o relógio canônico.
			_elapsed_seconds = 0.0
			_sync_timer = SYNC_INTERVAL_SECONDS
		else:
			_sync_timer = 0.0
			_update_hud_visibility()

	if not _session_active:
		if session_changed:
			_apply_world_state()
			_update_hud()
			_last_hud_second = int(floor(_elapsed_seconds))
		return

	_elapsed_seconds = fposmod(_elapsed_seconds + delta, CYCLE_DURATION_SECONDS)
	_apply_world_state()
	var hud_second := int(floor(_elapsed_seconds))
	if hud_second != _last_hud_second:
		_last_hud_second = hud_second
		_update_hud()

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL_SECONDS:
			_sync_timer = fposmod(_sync_timer, SYNC_INTERVAL_SECONDS)
			if not multiplayer.get_peers().is_empty():
				_receive_clock.rpc(_elapsed_seconds)


func _on_game_settings_changed() -> void:
	_update_hud_visibility()


func _update_hud_visibility() -> void:
	if _hud != null:
		_hud.visible = _session_active and GameSettings.hud_visible


@rpc("authority", "call_remote", "unreliable")
func _receive_clock(server_elapsed_seconds: float) -> void:
	if not is_finite(server_elapsed_seconds):
		return
	_elapsed_seconds = fposmod(server_elapsed_seconds, CYCLE_DURATION_SECONDS)
	_apply_world_state()
	_last_hud_second = int(floor(_elapsed_seconds))
	_update_hud()


func _apply_world_state() -> void:
	var cycle_progress := _elapsed_seconds / CYCLE_DURATION_SECONDS
	var daylight := maxf(0.0, sin(TAU * cycle_progress))
	var is_day := _elapsed_seconds < DAY_DURATION_SECONDS

	if _sun != null:
		# O sol cruza o céu durante os 12 minutos de dia e fica abaixo do horizonte à noite.
		_sun.rotation_degrees = Vector3(-360.0 * cycle_progress, 0.0, 0.0)
		_sun.light_energy = SUN_MAX_ENERGY * daylight
		if _sun.shadow_enabled != GameSettings.shadows_enabled:
			GameSettings.apply_shadow_preference(_sun)

	if _panorama_material != null:
		var target_sky := DAY_SKY if is_day else NIGHT_SKY
		if _panorama_material.panorama != target_sky:
			_panorama_material.panorama = target_sky
		_panorama_material.energy_multiplier = lerpf(0.35, 1.0, daylight) if is_day else 0.5

		if _world_environment != null and _world_environment.environment != null:
			var environment := _world_environment.environment
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = NIGHT_AMBIENT_COLOR.lerp(DAY_AMBIENT_COLOR, daylight)
			environment.ambient_light_energy = lerpf(0.35, 0.9, daylight)


func _update_hud() -> void:
	if _time_label == null:
		return

	var elapsed_game_minutes := int(floor(_elapsed_seconds))
	var clock_minutes := posmod(START_TIME_MINUTES + elapsed_game_minutes, 24 * 60)
	var hour := int(clock_minutes / 60)
	var minute := clock_minutes % 60
	var is_day := _elapsed_seconds < DAY_DURATION_SECONDS
	_time_label.text = "%s  |  %02d:%02d" % ["DIA" if is_day else "NOITE", hour, minute]

	var seconds_until_change := DAY_DURATION_SECONDS - _elapsed_seconds \
		if is_day else CYCLE_DURATION_SECONDS - _elapsed_seconds
	var rounded_seconds := int(ceil(seconds_until_change))
	var transition_name := "Anoitece" if is_day else "Amanhece"
	_countdown_label.text = "%s em %02d:%02d" % [
		transition_name,
		int(rounded_seconds / 60),
		rounded_seconds % 60,
	]
	_phase_bar.value = seconds_until_change


func _bind_hud() -> void:
	_hud = get_parent().get_node_or_null("DayNightHUD") as CanvasLayer
	if _hud == null:
		push_warning("DayNightHUD.tscn não foi instanciada na cena World.")
		return
	_clock_panel = _hud.get_node("ClockPanel") as PanelContainer
	_time_label = _hud.get_node("ClockPanel/ClockColumn/TimeLabel") as Label
	_countdown_label = _hud.get_node("ClockPanel/ClockColumn/CountdownLabel") as Label
	_phase_bar = _hud.get_node("ClockPanel/ClockColumn/PhaseBar") as ProgressBar
	_clock_panel.add_theme_stylebox_override("panel", _clock_panel_style())
	_clock_panel.add_theme_constant_override("margin_left", 12)
	_clock_panel.add_theme_constant_override("margin_right", 12)
	_clock_panel.add_theme_constant_override("margin_top", 8)
	_clock_panel.add_theme_constant_override("margin_bottom", 8)
	get_viewport().size_changed.connect(_layout_clock_panel)
	_layout_clock_panel()


func _clock_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.09, 0.14, 0.94)
	style.border_color = Color(0.18, 0.58, 0.72, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _layout_clock_panel() -> void:
	if _clock_panel == null:
		return
	if get_viewport().size.x < 680.0:
		_clock_panel.offset_left = -318.0
		_clock_panel.offset_right = -70.0
	else:
		_clock_panel.offset_left = -252.0
		_clock_panel.offset_right = -16.0
