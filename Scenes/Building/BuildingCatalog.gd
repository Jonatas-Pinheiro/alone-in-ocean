extends RefCounted
class_name BuildingCatalog
## Catálogo completo das quatro peças do Alone in Ocean para o Building & Placement Kit.
## As dimensões `size` são caixas de validação, não alteram a malha das cenas.

const FLOOR_SCENE: PackedScene = preload("res://Scenes/Building/Pieces/Floor.tscn")
const WALL_SCENE: PackedScene = preload("res://Scenes/Building/Pieces/Wall.tscn")
const RAMP_SCENE: PackedScene = preload("res://Scenes/Building/Pieces/Ramp.tscn")
const CEILING_SCENE: PackedScene = preload("res://Scenes/Building/Pieces/Ceiling.tscn")

static func create_catalog(
		ramp_bounds: Vector3 = Vector3(3.0, 3.0, 3.0),
		ceiling_bounds: Vector3 = Vector3(3.0, 0.3, 3.0)
) -> PKCatalog:
	var buildables: Array[PKBuildable] = []

	# PISO: 3 x 3 m, 30 cm de espessura. A origem da cena fica no centro inferior.
	var floor_piece := PKBuildable.make(&"floor", "Piso", Vector2i(3, 3))
	floor_piece.scene = FLOOR_SCENE
	floor_piece.category = &"estrutura"
	floor_piece.size = Vector3(3.0, 0.3, 3.0)
	floor_piece.snap = PKBuildable.Snap.GRID | PKBuildable.Snap.SOCKET
	floor_piece.tags = [&"foundation"]
	floor_piece.rotation_step = 90.0
	var floor_targets: Array[StringName] = [&"floor_edge"]
	floor_piece.sockets = _edge_sockets(
		&"floor_edge", 0.3, 1.5, 1.5, floor_targets,
		PKSocket.Facing.OPPOSITE, false
	)
	buildables.append(floor_piece)

	# PAREDE: malha real de 3 x 3 x 0,3 m. A caixa de validação é 2,7 m
	# de largura para permitir que duas paredes se encontrem em cantos sem falso overlap.
	var wall_piece := PKBuildable.make(&"wall", "Parede", Vector2i(3, 1))
	wall_piece.scene = WALL_SCENE
	wall_piece.category = &"estrutura"
	wall_piece.size = Vector3(2.7, 3.0, 0.3)
	wall_piece.snap = PKBuildable.Snap.SOCKET
	wall_piece.needs_foundation = true
	wall_piece.rotation_step = 90.0
	var wall_targets: Array[StringName] = [&"floor_edge", &"wall_top", &"ceiling_edge"]
	var wall_bottom := PKSocket.make(&"wall_bottom", Vector3.ZERO, 0.0, wall_targets)
	wall_bottom.free_rotation_step = 180.0
	wall_piece.sockets = [
		wall_bottom,
		PKSocket.make(&"wall_top", Vector3(0.0, 3.0, 0.0))
	]
	buildables.append(wall_piece)

	# RAMPA: conecta a borda de um piso à área externa. O socket fica na borda
	# traseira da rampa; a cena deve ter a base no Y=0 e o centro da base no X=0.
	var ramp_piece := PKBuildable.make(&"ramp", "Rampa", Vector2i(3, 3))
	ramp_piece.scene = RAMP_SCENE
	ramp_piece.category = &"estrutura"
	ramp_piece.size = ramp_bounds
	ramp_piece.snap = PKBuildable.Snap.SOCKET
	ramp_piece.needs_foundation = true
	ramp_piece.supports_on_top = false
	ramp_piece.rotation_step = 90.0
	var ramp_targets: Array[StringName] = [&"floor_edge"]
	var ramp_bottom := PKSocket.make(
		&"ramp_bottom",
		Vector3(0.0, 0.0, -ramp_bounds.z * 0.5),
		0.0,
		ramp_targets
	)
	ramp_bottom.free_rotation_step = 90.0
	ramp_piece.sockets = [ramp_bottom]
	buildables.append(ramp_piece)

	# TETO: encaixa sua borda em um socket superior de parede. Também oferece
	# sockets ceiling_edge para que paredes possam ser construídas sobre ele.
	var ceiling_piece := PKBuildable.make(&"ceiling", "Teto", Vector2i(3, 3))
	ceiling_piece.scene = CEILING_SCENE
	ceiling_piece.category = &"estrutura"
	ceiling_piece.size = ceiling_bounds
	ceiling_piece.snap = PKBuildable.Snap.SOCKET
	ceiling_piece.needs_foundation = true
	ceiling_piece.tags = [&"foundation"]
	ceiling_piece.rotation_step = 90.0
	var ceiling_targets: Array[StringName] = [&"wall_top"]
	ceiling_piece.sockets = _edge_sockets(
		&"ceiling_edge", 0.0, ceiling_bounds.x * 0.5,
		ceiling_bounds.z * 0.5, ceiling_targets,
		PKSocket.Facing.SAME, true
	)
	buildables.append(ceiling_piece)

	var catalog := PKCatalog.make(buildables)
	catalog.category_names = {&"estrutura": "Estrutura"}
	return catalog


static func _edge_sockets(
		socket_type: StringName,
		y: float,
		half_x: float,
		half_z: float,
		targets: Array[StringName],
		facing: PKSocket.Facing,
		holds: bool
) -> Array[PKSocket]:
	var result: Array[PKSocket] = []
	var edge_data: Array[Dictionary] = [
		{"position": Vector3(0.0, y, half_z), "angle": 0.0},
		{"position": Vector3(half_x, y, 0.0), "angle": 270.0},
		{"position": Vector3(0.0, y, -half_z), "angle": 180.0},
		{"position": Vector3(-half_x, y, 0.0), "angle": 90.0}
	]
	for edge: Dictionary in edge_data:
		var socket := PKSocket.make(
			socket_type,
			edge["position"],
			float(edge["angle"]),
			targets.duplicate(),
			facing
		)
		socket.holds = holds
		result.append(socket)
	return result
