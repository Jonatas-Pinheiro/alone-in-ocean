extends CharacterBody3D
class_name SurvivalPlayer

## Jogador multiplayer com física autoritativa no servidor.
## Versão otimizada para dispositivos fracos + animações de câmera (só no jogador local).

const SERVER_ID := 1
const MAX_PITCH := PI * 0.49

# --- Rede -------------------------------------------------------------------
const INPUT_KEEPALIVE_TICKS := 6      # reenvia a entrada mesmo sem mudança (protege contra pacote perdido)
const INPUT_EPSILON := 0.0005         # variação mínima de yaw/pitch para enviar
const IDLE_CHECK_TICKS := 10          # parado: só simula a cada N ticks

# --- Mola da câmera (aterrissagem / pulo) -----------------------------------
const SPRING_STIFFNESS := 120.0
const SPRING_DAMPING := 14.0
const MAX_LAND_KICK := 1.2
const LAND_PITCH_FACTOR := 1.5

const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"
const ACTION_FORWARD := &"move_forward"
const ACTION_BACK := &"move_back"
const ACTION_JUMP := &"jump"
const ACTION_INTERACT := &"interact"
const ACTION_EAT := &"consume_food"
const ACTION_DRINK := &"drink_water"
const INTERACTION_RAY_LENGTH := 10.0

const DEFAULT_KEYS := {
	&"move_forward": KEY_W,
	&"move_back": KEY_S,
	&"move_left": KEY_A,
	&"move_right": KEY_D,
	&"jump": KEY_SPACE,
	&"interact": KEY_E,
	&"consume_food": KEY_F,
	&"drink_water": KEY_G,
}

# Só o necessário é replicado, e apenas quando muda (ON_CHANGE).
# Rotação enviada por eixo: o roll da câmera é local e nunca vai pela rede.
const SYNC_PATHS: Array[NodePath] = [
	^".:position",
	^".:rotation:y",
	^"Camera3D:rotation:x",
	^".:grounded",
	^".:hunger",
	^".:thirst",
	^".:health",
	^".:wood_count",
	^".:plastic_count",
	^".:scrap_count",
	^".:food_count",
	^".:water_count",
]

@export_group("Movimento")
@export var speed := 5.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002
@export var acceleration := 40.0
@export var body_model: Node3D

@export_group("Efeitos de câmera")
## Desligue em aparelhos muito fracos.
@export var camera_effects_enabled := true
## 0 = sem efeitos, 1 = efeito completo (útil como opção de acessibilidade).
@export_range(0.0, 1.0, 0.05) var effects_intensity := 1.0
## Metros percorridos por ciclo completo de passos (esquerdo + direito).
@export var bob_stride_length := 1.6
@export var bob_vertical := 0.035
@export var bob_horizontal := 0.02
@export_range(0.0, 5.0, 0.05) var bob_roll_deg := 0.35
## Inclinação da câmera ao andar de lado.
@export_range(0.0, 8.0, 0.1) var strafe_roll_deg := 2.0
## Inclinação máxima ao girar a câmera rápido.
@export_range(0.0, 8.0, 0.1) var turn_roll_deg := 2.5
@export var turn_roll_amount := 0.00002
## Aumento de FOV (graus) ao atingir a velocidade máxima.
@export var fov_kick := 6.0
@export var landing_impact := 0.08
@export var jump_kick := 0.25
## Respiração leve quando parado.
@export var breathing_amount := 0.0025

var owner_peer_id := 0

@export_group("Sobrevivência")
var hunger := 100.0
var thirst := 100.0
var health := 100.0
var wood_count := 0
var plastic_count := 0
var scrap_count := 0
var food_count := 0
var water_count := 0

## Replicado pelo servidor (o cliente não simula física, então não sabe se está no chão).
var grounded := true

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)

@onready var camera: Camera3D = $Camera3D

var _mp: MultiplayerAPI
var _is_local := false
var _is_server := false
var _is_auth := false

var _yaw := 0.0
var _pitch := 0.0

# Entrada validada (usada pela simulação no servidor)
var _in_move := Vector2.ZERO
var _in_yaw := 0.0
var _in_pitch := 0.0
var _in_jump_held := false
var _jump_requested := false

# Anti-flood (servidor)
var _rate_window_start_ms := 0
var _rate_count := 0
var _rate_limit := 120

# Envio só quando muda (cliente)
var _sent_move := Vector2.ZERO
var _sent_yaw := 0.0
var _sent_pitch := 0.0
var _sent_jump := false
var _ticks_since_send := 999

var _idle_ticks := 0

# --- Estado dos efeitos de câmera (somente local) ----------------------------
var _cam_base_pos := Vector3.ZERO
var _base_fov := 75.0
var _fov := 75.0

var _prev_pos := Vector3.ZERO
var _h_speed := 0.0
var _v_speed := 0.0
var _lateral_speed := 0.0

var _bob_phase := 0.0
var _bob_weight := 0.0
var _idle_time := 0.0

var _spring_pos := 0.0
var _spring_vel := 0.0
var _was_grounded := true
var _fall_speed := 0.0

var _strafe_roll := 0.0
var _turn_roll := 0.0
var _look_dx := 0.0


func _init() -> void:
	_create_state_synchronizer()


func _enter_tree() -> void:
	if owner_peer_id == 0:
		var node_name := String(name)

		if node_name.is_valid_int():
			owner_peer_id = node_name.to_int()
		else:
			owner_peer_id = multiplayer.get_unique_id()


func _ready() -> void:
	add_to_group("players")
	_mp = multiplayer
	_rate_limit = Engine.physics_ticks_per_second * 2

	_yaw = rotation.y
	_pitch = camera.rotation.x
	_in_yaw = _yaw
	_in_pitch = _pitch

	_cam_base_pos = camera.position
	_base_fov = camera.fov
	_fov = _base_fov
	_prev_pos = global_position
	_was_grounded = grounded

	_refresh_runtime_state()

	if OS.is_debug_build():
		print(
			"PLAYER: ", name,
			" | Owner: ", owner_peer_id,
			" | Meu ID: ", _mp.get_unique_id(),
			" | Local: ", _is_local,
			" | Authority: ", get_multiplayer_authority()
		)


## Atualiza as flags quando uma cena single-player é adotada como peer do servidor.
func configure_owner_peer_id(peer_id: int) -> void:
	owner_peer_id = peer_id
	if is_node_ready():
		_refresh_runtime_state()


func _refresh_runtime_state() -> void:
	var was_local := _is_local
	_mp = multiplayer
	_is_local = owner_peer_id == _mp.get_unique_id()
	_is_server = _mp.is_server()
	_is_auth = is_multiplayer_authority()

	# Somente o jogador local coleta input; o servidor também simula física.
	set_process(_is_local)
	set_process_unhandled_input(_is_local)
	set_physics_process(_is_local or _is_auth)

	if _is_local:
		_ensure_input_actions()
		camera.make_current()
		if body_model != null:
			body_model.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.current = false
		if was_local:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	if _is_local:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------------------
# SINCRONIZAÇÃO
# ---------------------------------------------------------------------------

func _create_state_synchronizer() -> void:
	var config := SceneReplicationConfig.new()

	for path in SYNC_PATHS:
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(
			path,
			SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
		)

	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "StateSynchronizer"
	synchronizer.root_path = NodePath("..")
	synchronizer.replication_config = config
	synchronizer.replication_interval = 0.0
	synchronizer.set_multiplayer_authority(SERVER_ID)

	add_child(synchronizer)


# ---------------------------------------------------------------------------
# ENTRADA LOCAL
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion

	if motion != null:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_yaw = wrapf(
				_yaw - motion.relative.x * mouse_sensitivity,
				-PI,
				PI
			)

			_pitch = clampf(
				_pitch - motion.relative.y * mouse_sensitivity,
				-MAX_PITCH,
				MAX_PITCH
			)

			_look_dx += motion.relative.x

		return

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event.is_action_pressed(ACTION_INTERACT):
		_try_collect_pickup()
		return

	if event.is_action_pressed(ACTION_EAT):
		_request_survival_action("eat")
		return

	if event.is_action_pressed(ACTION_DRINK):
		_request_survival_action("drink")
		return

	var click := event as InputEventMouseButton

	if click != null and click.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _try_collect_pickup() -> void:
	var ray_from := camera.global_position
	var ray_to := ray_from - camera.global_transform.basis.z * INTERACTION_RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var pickup := result.get("collider") as SalvagePickup
	if pickup != null:
		_request_survival_action("collect", pickup.pickup_id)


func _request_survival_action(action: String, pickup_id: int = -1) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var manager := scene.get_node_or_null("SurvivalManager")
	if manager == null:
		return

	if multiplayer.is_server():
		manager.call("handle_local_action", self, action, pickup_id)
	else:
		manager.rpc_id(SERVER_ID, "request_action", action, pickup_id)


# ---------------------------------------------------------------------------
# VISUAL (por frame) — somente o jogador local
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if rotation.y != _yaw:
		rotation.y = _yaw

	if not camera_effects_enabled:
		camera.rotation = Vector3(_pitch, 0.0, 0.0)
		_look_dx = 0.0
		return

	_update_camera_effects(delta)


func _update_camera_effects(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var k := effects_intensity
	var speed_ratio := clampf(_h_speed / maxf(speed, 0.001), 0.0, 1.5)

	# --- Head bobbing ---------------------------------------------------------
	var moving := grounded and _h_speed > 0.4
	_bob_weight = _damp(_bob_weight, 1.0 if moving else 0.0, 8.0, dt)

	if moving:
		_bob_phase = fposmod(
			_bob_phase + _h_speed * dt * TAU / bob_stride_length,
			TAU
		)

	_idle_time = fposmod(_idle_time + dt, TAU * 10.0)

	var w := _bob_weight * minf(speed_ratio, 1.0)
	var bob_y := sin(_bob_phase * 2.0) * bob_vertical * w
	var bob_x := sin(_bob_phase) * bob_horizontal * w
	var bob_roll := sin(_bob_phase) * deg_to_rad(bob_roll_deg) * w
	var breath := sin(_idle_time * 1.2) * breathing_amount * (1.0 - _bob_weight)

	# --- Pulo / aterrissagem (mola) ------------------------------------------
	if grounded != _was_grounded:
		if grounded:
			_spring_vel -= clampf(_fall_speed * landing_impact, 0.0, MAX_LAND_KICK) * k
			_fall_speed = 0.0
		elif _v_speed > 0.5:
			_spring_vel += jump_kick * k

		_was_grounded = grounded

	if not grounded:
		_fall_speed = maxf(_fall_speed, -_v_speed)

	_spring_vel += (-SPRING_STIFFNESS * _spring_pos - SPRING_DAMPING * _spring_vel) * dt
	_spring_pos += _spring_vel * dt

	# --- Inclinações (roll) ---------------------------------------------------
	# Andar de lado inclina a câmera para o lado do movimento.
	var strafe_norm := clampf(_lateral_speed / maxf(speed, 0.001), -1.0, 1.0)
	_strafe_roll = _damp(_strafe_roll, -strafe_norm * deg_to_rad(strafe_roll_deg), 8.0, dt)

	# Girar rápido inclina a câmera na direção da curva (independente de FPS).
	var look_vel := _look_dx / maxf(delta, 0.001)
	_look_dx = 0.0
	var max_turn := deg_to_rad(turn_roll_deg)
	_turn_roll = _damp(
		_turn_roll,
		clampf(-look_vel * turn_roll_amount, -max_turn, max_turn),
		9.0,
		dt
	)

	var roll := (_strafe_roll + _turn_roll + bob_roll) * k

	# --- Aplicação na câmera (nada disso vai pela rede) ----------------------
	camera.position = _cam_base_pos + Vector3(
		bob_x * k,
		(bob_y + breath) * k + _spring_pos,
		0.0
	)

	camera.rotation = Vector3(
		_pitch + _spring_pos * LAND_PITCH_FACTOR,
		0.0,
		roll
	)

	# --- FOV dinâmico ---------------------------------------------------------
	_fov = _damp(_fov, _base_fov + minf(speed_ratio, 1.0) * fov_kick * k, 6.0, dt)

	if absf(camera.fov - _fov) > 0.02:
		camera.fov = _fov


static func _damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * dt))


# ---------------------------------------------------------------------------
# CICLO FÍSICO
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Somente o dono coleta a entrada.
	if _is_local:
		_push_local_input()

		if camera_effects_enabled:
			_track_motion(delta)

	# Somente o servidor simula a física.
	if _is_auth:
		_simulate(delta)


## Estima velocidades pela variação de posição.
## Funciona igual no host e no cliente (que não simula física).
func _track_motion(delta: float) -> void:
	var pos := global_position
	var d := pos - _prev_pos
	_prev_pos = pos

	# Teletransporte / respawn: ignora o salto.
	if d.length_squared() > 4.0:
		return

	var inv := 1.0 / delta
	var k := 1.0 - exp(-12.0 * delta)
	var right := global_transform.basis.x

	_h_speed = lerpf(_h_speed, Vector2(d.x, d.z).length() * inv, k)
	_v_speed = lerpf(_v_speed, d.y * inv, k)
	_lateral_speed = lerpf(_lateral_speed, d.dot(right) * inv, k)


func _push_local_input() -> void:
	var move := Input.get_vector(
		ACTION_LEFT,
		ACTION_RIGHT,
		ACTION_FORWARD,
		ACTION_BACK
	)

	var jump := Input.is_action_pressed(ACTION_JUMP)

	# O anfitrião aplica sua própria entrada diretamente.
	if _is_server:
		if _is_auth:
			_apply_input(move, _yaw, _pitch, jump)

		return

	# Clientes só enviam entrada quando conectados.
	var peer := _mp.multiplayer_peer

	if peer == null:
		return

	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	# Só envia se algo mudou (ou como "keepalive" periódico).
	_ticks_since_send += 1

	var changed := (
		jump != _sent_jump
		or not move.is_equal_approx(_sent_move)
		or absf(_yaw - _sent_yaw) > INPUT_EPSILON
		or absf(_pitch - _sent_pitch) > INPUT_EPSILON
	)

	if not changed and _ticks_since_send < INPUT_KEEPALIVE_TICKS:
		return

	_sent_move = move
	_sent_yaw = _yaw
	_sent_pitch = _pitch
	_sent_jump = jump
	_ticks_since_send = 0

	submit_input.rpc_id(SERVER_ID, move, _yaw, _pitch, jump)


# ---------------------------------------------------------------------------
# RPC: CLIENTE -> SERVIDOR
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(
	move: Vector2,
	yaw: float,
	pitch: float,
	jump: bool
) -> void:

	if not _is_server or not _is_auth:
		return

	if _mp.get_remote_sender_id() != owner_peer_id:
		return

	var now := Time.get_ticks_msec()

	if now - _rate_window_start_ms >= 1000:
		_rate_window_start_ms = now
		_rate_count = 0

	_rate_count += 1

	if _rate_count > _rate_limit:
		return

	_apply_input(move, yaw, pitch, jump)


func _apply_input(
	move: Vector2,
	yaw: float,
	pitch: float,
	jump: bool
) -> void:

	if not move.is_finite():
		return

	if not is_finite(yaw) or not is_finite(pitch):
		return

	_in_move = move.limit_length(1.0)
	_in_yaw = wrapf(yaw, -PI, PI)
	_in_pitch = clampf(pitch, -MAX_PITCH, MAX_PITCH)

	if jump and not _in_jump_held:
		_jump_requested = true

	_in_jump_held = jump


# ---------------------------------------------------------------------------
# FÍSICA: SOMENTE SERVIDOR
# ---------------------------------------------------------------------------

func _simulate(delta: float) -> void:
	# Jogador parado no chão: pula a simulação na maior parte dos ticks.
	# Uma checagem periódica garante que ele caia se o chão sumir.
	var idle := (
		not _jump_requested
		and _in_move == Vector2.ZERO
		and velocity.is_zero_approx()
		and is_on_floor()
	)

	if idle:
		_idle_ticks += 1

		if _idle_ticks < IDLE_CHECK_TICKS:
			return

	_idle_ticks = 0

	# Só escreve se mudou (evita notificações de transformação à toa).
	if rotation.y != _in_yaw:
		rotation.y = _in_yaw

	if camera.rotation.x != _in_pitch:
		camera.rotation.x = _in_pitch

	if not is_on_floor():
		velocity.y -= gravity * delta

	elif _jump_requested:
		velocity.y = jump_velocity

	_jump_requested = false

	# Equivale a basis * Vector3(x, 0, y), sem alocar vetores temporários.
	var wish := basis.x * _in_move.x + basis.z * _in_move.y
	var step := acceleration * delta

	velocity.x = move_toward(velocity.x, wish.x * speed, step)
	velocity.z = move_toward(velocity.z, wish.z * speed, step)

	move_and_slide()

	var on_floor := is_on_floor()

	if grounded != on_floor:
		grounded = on_floor


# ---------------------------------------------------------------------------
# MAPA DE ENTRADA
# ---------------------------------------------------------------------------

static func _ensure_input_actions() -> void:
	for action in DEFAULT_KEYS:
		if InputMap.has_action(action):
			continue

		InputMap.add_action(action)

		var key_event := InputEventKey.new()
		key_event.physical_keycode = DEFAULT_KEYS[action] as Key

		InputMap.action_add_event(action, key_event)
