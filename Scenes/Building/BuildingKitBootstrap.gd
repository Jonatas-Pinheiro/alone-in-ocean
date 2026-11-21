extends Node3D
const BUILDING_CATALOG = preload("res://Scenes/Building/BuildingCatalog.gd")
## Inicializa o catálogo, o sistema 3D e a interface do Building & Placement Kit.
## Anexe este script a um Node3D filho do nó raiz da cena principal.

@export_group("Referências da cena")
@export var player_camera: Camera3D
@export var raft_root: Node3D

@export_group("Construção")
@export var grid_cell_size := Vector3.ONE
## O pivot do Raft deve ficar no centro da plataforma. -0.5 alinha o centro
## de uma célula de 1 m ao pivot quando o tamanho das peças é 3 x 3 células.
@export var grid_origin_offset := Vector3(-0.5, 0.0, -0.5)
@export_flags_3d_physics var terrain_mask: int = 1
@export_flags_3d_physics var placed_piece_layer: int = 2
@export var aim_from_screen_center := true
@export var show_building_hud := true

@export_group("Caixas de validação")
## AABB de colisão lógica da rampa. Não muda a malha de Ramp.tscn.
@export var ramp_bounds := Vector3(3.0, 3.0, 3.0)
## AABB de colisão lógica do teto. Não muda a malha de Ceiling.tscn.
@export var ceiling_bounds := Vector3(3.0, 0.3, 3.0)

var build_system: PKBuildSystem3D
var build_hud: PKBuildHUD
var hud_layer: CanvasLayer


func _ready() -> void:
	# Aguarda a árvore de cena terminar de inicializar antes de adicionar nós.
	call_deferred("_initialize_building_kit")


func _initialize_building_kit() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		push_error("Building Kit: não foi possível encontrar a raiz da cena.")
		return

	if raft_root == null:
		push_error("Building Kit: atribua Raft Root no Inspector.")
		return

	if player_camera == null:
		player_camera = get_viewport().get_camera_3d()
	if player_camera == null:
		push_error("Building Kit: atribua a Camera3D do jogador no Inspector.")
		return

	# As peças ainda não são replicadas; permitir construção aqui criaria estados diferentes por peer.
	if _is_online_multiplayer():
		push_warning("Building Kit: construção desativada em multiplayer até a replicação de peças ser implementada.")
		return

	var catalog: PKCatalog = BUILDING_CATALOG.create_catalog(ramp_bounds, ceiling_bounds)
	var catalog_issues := catalog.validate()
	if not catalog_issues.is_empty():
		for issue: String in catalog_issues:
			push_error("Building Kit / Catálogo: " + issue)
		return

	build_system = PKBuildSystem3D.new()
	build_system.name = "PKBuildSystem3D"
	build_system.catalog = catalog
	build_system.camera = player_camera
	build_system.grid_cell_size = grid_cell_size
	build_system.grid_origin = raft_root.global_position + grid_origin_offset
	build_system.terrain_mask = terrain_mask
	build_system.piece_layer = placed_piece_layer
	build_system.aim_from_screen_center = aim_from_screen_center
	build_system.show_grid = true
	build_system.input_enabled = true
	build_system.top_level = true
	build_system.transform = Transform3D.IDENTITY

	# O sistema fica em coordenadas globais, como o raycast da câmera e o catálogo.
	# As peças são mantidas dentro do próprio sistema.
	scene_root.add_child(build_system)

	if show_building_hud:
		hud_layer = CanvasLayer.new()
		hud_layer.name = "BuildingHUDLayer"
		scene_root.add_child(hud_layer)

		build_hud = PKBuildHUD.new()
		hud_layer.add_child(build_hud)
		build_hud.bind(build_system)


func disable_for_multiplayer() -> void:
	if build_system != null:
		build_system.input_enabled = false
		build_system.queue_free()
		build_system = null
	if hud_layer != null:
		hud_layer.queue_free()
		hud_layer = null
	build_hud = null


func _is_online_multiplayer() -> bool:
	var active_peer := multiplayer.multiplayer_peer
	return active_peer != null and not (active_peer is OfflineMultiplayerPeer)
