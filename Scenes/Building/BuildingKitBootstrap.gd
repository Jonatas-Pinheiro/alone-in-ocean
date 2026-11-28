extends Node3D

const BUILDING_CATALOG = preload("res://Scenes/Building/BuildingCatalog.gd")

@export_group("Construção")
@export var grid_cell_size := Vector3.ONE
@export var grid_origin_offset := Vector3(-0.5, 0.0, -0.5)
@export_flags_3d_physics var terrain_mask: int = 1
@export_flags_3d_physics var placed_piece_layer: int = 2
@export var aim_from_screen_center := true

@export_group("Caixas de validação")
@export var ramp_bounds := Vector3(3.0, 3.0, 3.0)
@export var ceiling_bounds := Vector3(3.0, 0.3, 3.0)

var build_system: NetworkedBuildSystem
var _player_camera: Camera3D
var _building_network: Node
var _network_manager: Node
var _initializing := false


func _ready() -> void:
	_network_manager = get_parent().get_node_or_null("NetworkManager")
	_building_network = get_parent().get_node_or_null("BuildingNetwork")
	if _network_manager == null:
		push_error("Building Kit: NetworkManager não foi encontrado no World.")
		return
	_network_manager.local_player_ready.connect(_on_local_player_ready)
	_network_manager.session_ended.connect(_on_session_ended)


func _on_local_player_ready(player: CharacterBody3D) -> void:
	_player_camera = player.get_node_or_null("Camera3D") as Camera3D
	if _player_camera == null:
		push_error("Building Kit: o jogador não possui Camera3D.")
		return
	call_deferred("_initialize_building_kit")


func _initialize_building_kit() -> void:
	if _initializing or build_system != null:
		return
	_initializing = true
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null or _player_camera == null:
		_initializing = false
		return

	var raft_root := get_parent().get_node_or_null("Floor") as Node3D
	if raft_root == null:
		push_error("Building Kit: nó Floor (jangada) não foi encontrado.")
		_initializing = false
		return

	var catalog: PKCatalog = BUILDING_CATALOG.create_catalog(ramp_bounds, ceiling_bounds)
	var catalog_issues := catalog.validate()
	if not catalog_issues.is_empty():
		for issue: String in catalog_issues:
			push_error("Building Kit / Catálogo: " + issue)
		_initializing = false
		return

	build_system = NetworkedBuildSystem.new()
	build_system.name = "PKBuildSystem3D"
	build_system.catalog = catalog
	build_system.camera = _player_camera
	build_system.grid_cell_size = grid_cell_size
	build_system.grid_origin = raft_root.global_position + grid_origin_offset
	build_system.terrain_mask = terrain_mask
	build_system.piece_layer = placed_piece_layer
	build_system.aim_from_screen_center = aim_from_screen_center
	build_system.show_grid = true
	build_system.input_enabled = true
	build_system.top_level = true
	build_system.transform = Transform3D.IDENTITY
	scene_root.add_child(build_system)

	if _building_network != null:
		_building_network.register_build_system(build_system)
	_initializing = false


func _on_session_ended() -> void:
	if _building_network != null and build_system != null:
		_building_network.unregister_build_system(build_system)
	if build_system != null:
		build_system.queue_free()
	build_system = null
	_player_camera = null
	_initializing = false
