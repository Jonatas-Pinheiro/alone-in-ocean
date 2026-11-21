extends Node3D
class_name SurvivalManager

const PICKUP_SCENE: PackedScene = preload("res://Scenes/Survival/SalvagePickup.tscn")
const SERVER_ID := 1
const MAX_STACK := 99

@export_group("Referências")
@export var raft_root: Node3D

@export_group("Destroços")
@export_range(1, 30, 1) var initial_pickups := 8
@export_range(1, 40, 1) var max_pickups := 18
@export_range(2.0, 60.0, 1.0) var spawn_interval := 8.0
@export_range(4.0, 20.0, 0.5) var spawn_radius_min := 5.0
@export_range(5.0, 24.0, 0.5) var spawn_radius_max := 15.0
@export var water_level := -3.85
@export_range(3.0, 12.0, 0.5) var interaction_range := 8.0

@export_group("Sobrevivência")
@export_range(0.0, 1.0, 0.005) var hunger_drain_per_second := 0.05
@export_range(0.0, 1.0, 0.005) var thirst_drain_per_second := 0.08
@export_range(0.0, 10.0, 0.1) var damage_per_second_at_zero := 2.0

@onready var pickup_spawner: MultiplayerSpawner = get_parent().get_node("PickupSpawner")

var _rng := RandomNumberGenerator.new()
var _spawn_elapsed := 0.0
var _needs_elapsed := 0.0
var _next_pickup_id := 1
var _network_manager: Node


func _ready() -> void:
	_rng.randomize()
	pickup_spawner.spawn_function = Callable(self, "_spawn_pickup")
	_network_manager = get_parent().get_node_or_null("NetworkManager")
	if _network_manager != null:
		_network_manager.session_started.connect(_on_session_started)
		_network_manager.session_ended.connect(_on_session_ended)


func _on_session_started() -> void:
	if multiplayer.is_server():
		call_deferred("_spawn_initial_pickups")


func _on_session_ended() -> void:
	for node in get_tree().get_nodes_in_group("salvage_pickups"):
		node.queue_free()


func _process(delta: float) -> void:
	if not multiplayer.is_server() or _network_manager == null or not _network_manager.is_session_active():
		return

	_spawn_elapsed += delta
	if _spawn_elapsed >= spawn_interval:
		_spawn_elapsed = 0.0
		_spawn_one_pickup()

	_needs_elapsed += delta
	while _needs_elapsed >= 1.0:
		_needs_elapsed -= 1.0
		_tick_survival(1.0)


func _spawn_initial_pickups() -> void:
	if not multiplayer.is_server() or _network_manager == null or not _network_manager.is_session_active():
		return
	for _index in range(initial_pickups):
		_spawn_one_pickup()


func _spawn_one_pickup() -> void:
	if not multiplayer.is_server() or _network_manager == null or not _network_manager.is_session_active():
		return
	if get_tree().get_nodes_in_group("salvage_pickups").size() >= max_pickups:
		return

	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(spawn_radius_min, spawn_radius_max)
	var origin := raft_root.global_position if raft_root != null else Vector3.ZERO
	var spawn_position := Vector3(
		origin.x + cos(angle) * radius,
		water_level,
		origin.z + sin(angle) * radius
	)
	var drift_angle := _rng.randf_range(0.0, TAU)
	var drift_speed := _rng.randf_range(0.12, 0.42)
	var drift_velocity := Vector3(cos(drift_angle) * drift_speed, 0.0, sin(drift_angle) * drift_speed)
	var resource_kind := _roll_resource_kind()
	var amount := _rng.randi_range(1, 2) if resource_kind == &"wood" else 1

	var spawn_data := {
		"id": _next_pickup_id,
		"kind": String(resource_kind),
		"amount": amount,
		"position": spawn_position,
		"base_y": water_level,
		"phase": _rng.randf_range(0.0, TAU),
		"drift_velocity": drift_velocity,
	}
	_next_pickup_id += 1
	pickup_spawner.spawn(spawn_data)


func _roll_resource_kind() -> StringName:
	var roll := _rng.randf()
	if roll < 0.32:
		return &"wood"
	if roll < 0.54:
		return &"plastic"
	if roll < 0.67:
		return &"scrap"
	if roll < 0.83:
		return &"food"
	return &"water"


func _spawn_pickup(data: Variant) -> Node:
	var pickup: SalvagePickup = PICKUP_SCENE.instantiate()
	pickup.pickup_id = int(data.get("id", 0))
	pickup.resource_kind = StringName(data.get("kind", "wood"))
	pickup.amount = int(data.get("amount", 1))
	pickup.position = data.get("position", Vector3.ZERO)
	pickup.base_y = float(data.get("base_y", water_level))
	pickup.bob_phase = float(data.get("phase", 0.0))
	pickup.drift_velocity = data.get("drift_velocity", Vector3.ZERO)
	return pickup


@rpc("any_peer", "call_remote", "reliable")
func request_action(action: String, pickup_id: int = -1) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var player := _find_player(sender_id)
	if player == null:
		return
	_handle_action(player, action, pickup_id)


func handle_local_action(player: SurvivalPlayer, action: String, pickup_id: int = -1) -> void:
	if not multiplayer.is_server() or player == null:
		return
	_handle_action(player, action, pickup_id)


func _handle_action(player: SurvivalPlayer, action: String, pickup_id: int) -> void:
	match action:
		"collect":
			_collect_pickup(player, pickup_id)
		"eat":
			_consume_food(player)
		"drink":
			_consume_water(player)


func _collect_pickup(player: SurvivalPlayer, pickup_id: int) -> void:
	var pickup := _find_pickup(pickup_id)
	if pickup == null or not pickup.is_inside_tree():
		return

	var camera := player.camera
	var to_pickup := pickup.global_position - camera.global_position
	var distance := to_pickup.length()
	if distance > interaction_range or distance < 0.001:
		return
	if (-camera.global_transform.basis.z).dot(to_pickup / distance) < 0.72:
		return

	match pickup.resource_kind:
		&"wood":
			player.wood_count = mini(player.wood_count + pickup.amount, MAX_STACK)
		&"plastic":
			player.plastic_count = mini(player.plastic_count + pickup.amount, MAX_STACK)
		&"scrap":
			player.scrap_count = mini(player.scrap_count + pickup.amount, MAX_STACK)
		&"food":
			player.food_count = mini(player.food_count + pickup.amount, MAX_STACK)
		&"water":
			player.water_count = mini(player.water_count + pickup.amount, MAX_STACK)

	pickup.queue_free()


func _consume_food(player: SurvivalPlayer) -> void:
	if player.food_count <= 0 or player.hunger >= 100.0:
		return
	player.food_count -= 1
	player.hunger = minf(100.0, player.hunger + 35.0)


func _consume_water(player: SurvivalPlayer) -> void:
	if player.water_count <= 0 or player.thirst >= 100.0:
		return
	player.water_count -= 1
	player.thirst = minf(100.0, player.thirst + 45.0)


func _tick_survival(seconds: float) -> void:
	for node in get_tree().get_nodes_in_group("players"):
		if not node is SurvivalPlayer:
			continue
		var player := node as SurvivalPlayer
		player.hunger = maxf(0.0, player.hunger - hunger_drain_per_second * seconds)
		player.thirst = maxf(0.0, player.thirst - thirst_drain_per_second * seconds)

		if player.hunger <= 0.0 or player.thirst <= 0.0:
			player.health = maxf(0.0, player.health - damage_per_second_at_zero * seconds)
		elif player.health < 100.0 and player.hunger > 20.0 and player.thirst > 20.0:
			player.health = minf(100.0, player.health + 0.25 * seconds)

		if player.health <= 0.0:
			_respawn_player(player)


func _respawn_player(player: SurvivalPlayer) -> void:
	if raft_root != null:
		var horizontal_offset := Vector3(float(player.owner_peer_id % 2) * 0.8, 1.5, float(player.owner_peer_id % 3) * 0.8)
		player.global_position = raft_root.global_position + horizontal_offset
	player.velocity = Vector3.ZERO
	player.health = 55.0
	player.hunger = 50.0
	player.thirst = 50.0
	player.wood_count = floori(player.wood_count * 0.5)
	player.plastic_count = floori(player.plastic_count * 0.5)
	player.scrap_count = floori(player.scrap_count * 0.5)


func _find_player(peer_id: int) -> SurvivalPlayer:
	for node in get_tree().get_nodes_in_group("players"):
		if node is SurvivalPlayer and node.owner_peer_id == peer_id:
			return node as SurvivalPlayer
	return null


func _find_pickup(pickup_id: int) -> SalvagePickup:
	for node in get_tree().get_nodes_in_group("salvage_pickups"):
		if node is SalvagePickup and node.pickup_id == pickup_id:
			return node as SalvagePickup
	return null
