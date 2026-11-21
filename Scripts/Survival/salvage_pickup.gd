extends Area3D
class_name SalvagePickup

const SERVER_ID := 1

@export var pickup_id := 0
@export var resource_kind: StringName = &"wood"
@export_range(1, 99, 1) var amount := 1
@export var base_y := -3.85
@export var bob_phase := 0.0
@export var drift_velocity := Vector3.ZERO
@export var lifetime := 180.0

@onready var visual: MeshInstance3D = $Visual

var _elapsed := 0.0


func _init() -> void:
	_create_state_synchronizer()


func _enter_tree() -> void:
	set_multiplayer_authority(SERVER_ID, true)


func _ready() -> void:
	add_to_group("salvage_pickups")
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	material.albedo_color = _color_for_kind()
	visual.material_override = material


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_elapsed += delta
	var next_position := global_position
	next_position.x += drift_velocity.x * delta
	next_position.z += drift_velocity.z * delta
	next_position.y = base_y + sin(_elapsed * 1.8 + bob_phase) * 0.12
	global_position = next_position
	rotation.y += delta * 0.45

	if _elapsed >= lifetime:
		queue_free()


func _color_for_kind() -> Color:
	match resource_kind:
		&"wood":
			return Color(0.48, 0.28, 0.12)
		&"plastic":
			return Color(0.12, 0.72, 0.82)
		&"scrap":
			return Color(0.55, 0.58, 0.62)
		&"food":
			return Color(0.86, 0.32, 0.14)
		&"water":
			return Color(0.18, 0.38, 0.95)
	return Color.WHITE


func _create_state_synchronizer() -> void:
	var config := SceneReplicationConfig.new()
	for path in [^".:position", ^".:rotation"]:
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "PickupSynchronizer"
	synchronizer.root_path = NodePath("..")
	synchronizer.replication_config = config
	synchronizer.replication_interval = 0.12
	synchronizer.set_multiplayer_authority(SERVER_ID)
	add_child(synchronizer)
