extends Node

signal clock_updated(is_day: bool, clock_minutes: int, seconds_until_transition: int)

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
var _last_clock_second := -1


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
	_apply_world_state()
	_emit_clock_updated()


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

	if not _session_active:
		if session_changed:
			_apply_world_state()
			_emit_clock_updated()
			_last_clock_second = int(floor(_elapsed_seconds))
		return

	_elapsed_seconds = fposmod(_elapsed_seconds + delta, CYCLE_DURATION_SECONDS)
	_apply_world_state()
	var clock_second := int(floor(_elapsed_seconds))
	if clock_second != _last_clock_second:
		_last_clock_second = clock_second
		_emit_clock_updated()

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL_SECONDS:
			_sync_timer = fposmod(_sync_timer, SYNC_INTERVAL_SECONDS)
			if not multiplayer.get_peers().is_empty():
				_receive_clock.rpc(_elapsed_seconds)


@rpc("authority", "call_remote", "unreliable")
func _receive_clock(server_elapsed_seconds: float) -> void:
	if not is_finite(server_elapsed_seconds):
		return
	_elapsed_seconds = fposmod(server_elapsed_seconds, CYCLE_DURATION_SECONDS)
	_apply_world_state()
	_last_clock_second = int(floor(_elapsed_seconds))
	_emit_clock_updated()


func get_clock_state() -> Dictionary:
	var is_day := _elapsed_seconds < DAY_DURATION_SECONDS
	var clock_minutes := posmod(START_TIME_MINUTES + int(floor(_elapsed_seconds)), 24 * 60)
	var seconds_until_transition := DAY_DURATION_SECONDS - _elapsed_seconds \
		if is_day else CYCLE_DURATION_SECONDS - _elapsed_seconds
	return {
		"is_day": is_day,
		"clock_minutes": clock_minutes,
		"seconds_until_transition": int(ceil(seconds_until_transition)),
	}


func _emit_clock_updated() -> void:
	var state := get_clock_state()
	clock_updated.emit(
		bool(state["is_day"]),
		int(state["clock_minutes"]),
		int(state["seconds_until_transition"])
	)


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
