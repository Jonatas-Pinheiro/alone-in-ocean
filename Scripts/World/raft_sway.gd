extends Node3D

@onready var raft_visual: MeshInstance3D = $Floor/MeshInstance3D
var _elapsed := 0.0
var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3.ZERO

func _ready() -> void:
	_rest_position = raft_visual.position
	_rest_rotation = raft_visual.rotation

func _process(delta: float) -> void:
	_elapsed += delta
	raft_visual.position = _rest_position + Vector3(0.0, sin(_elapsed * 0.72) * 0.025, 0.0)
	raft_visual.rotation = _rest_rotation + Vector3(
		sin(_elapsed * 0.51) * deg_to_rad(0.8),
		0.0,
		sin(_elapsed * 0.67 + 0.7) * deg_to_rad(0.65)
	)
