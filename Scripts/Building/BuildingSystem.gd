extends Node3D

const GRID_SIZE := 3.0
const FLOOR_HEIGHT := 0.3
const WATER_SIZE := 200.0
const ROTATION_STEP := PI / 2.0

@export var camera: Camera3D
@export var floor_scene: PackedScene
@export var preview_scene: PackedScene
@export var wall_scene: PackedScene
@export var ramp_scene: PackedScene
@export var ceiling_scene: PackedScene

@onready var water: MeshInstance3D = get_tree().current_scene.get_node("Agua")

var preview: Node3D
var preview_mesh: MeshInstance3D
var preview_box: BoxMesh

var can_build := false
var preview_material: StandardMaterial3D
var last_preview_valid := false

var occupied_bounds: Array[AABB] = []

# 0 = Piso | 1 = Parede | 2 = Escada/Rampa | 3 = Teto
var selected_piece := 0
var rotation_steps := 0


func _ready() -> void:
	if camera == null:
		push_error("BuildingSystem: câmera não definida.")
		return

	if floor_scene == null or preview_scene == null:
		push_error("BuildingSystem: cenas obrigatórias não definidas.")
		return

	_create_preview()


func _process(_delta: float) -> void:
	if preview == null:
		return

	var base_position: Vector3 = _get_grid_position()
	var target_position := base_position + _get_piece_offset()

	preview.global_position = target_position
	preview.global_rotation = _get_piece_rotation()

	can_build = _is_valid_position(target_position)

	_set_preview_color()


func _get_stack_height(x: float, z: float) -> float:
	var max_top := 0.0
	for bounds in occupied_bounds:
		# Verifica se a peça existente está na mesma coluna de grid (com margem de tolerância)
		if absf(bounds.position.x - x) < 1.5 and absf(bounds.position.z - z) < 1.5:
			var top_y := bounds.position.y + bounds.size.y
			if top_y > max_top:
				max_top = top_y
	
	return floorf(max_top / 3.0) * 3.0


func _has_support_below(pos: Vector3) -> bool:
	# Piso no térreo (y <= 0.3) não precisa de suporte (pode colocar sobre a água)
	if selected_piece == 0 and pos.y <= 0.3:
		return true

	var candidate_bounds := _get_piece_bounds(pos)
	var cand_bottom := candidate_bounds.position.y

	for bounds in occupied_bounds:
		var top_y := bounds.position.y + bounds.size.y
		# Verifica se existe uma peça logo abaixo sustentando (com tolerância de altura)
		if absf(top_y - cand_bottom) <= 0.4:
			var overlap_x = minf(candidate_bounds.position.x + candidate_bounds.size.x, bounds.position.x + bounds.size.x) - maxf(candidate_bounds.position.x, bounds.position.x)
			var overlap_z = minf(candidate_bounds.position.z + candidate_bounds.size.z, bounds.position.z + bounds.size.z) - maxf(candidate_bounds.position.z, bounds.position.z)
			var min_overlap := 0.01 if selected_piece == 1 else 0.1

			if overlap_x > min_overlap and overlap_z > min_overlap:
				return true

	return false


func _is_direct_support(candidate: AABB, existing: AABB) -> bool:
	var existing_top := existing.position.y + existing.size.y
	var cand_bottom := candidate.position.y

	# Se os centros forem exatamente iguais, NÃO é suporte, é sobreposição no mesmo lugar!
	if absf(candidate.position.x - existing.position.x) < 0.1 and absf(candidate.position.z - existing.position.z) < 0.1 and absf(candidate.position.y - existing.position.y) < 0.1:
		return false

	# A peça existente precisa estar embaixo da nova peça
	if absf(existing_top - cand_bottom) <= 0.4:
		var overlap_x = minf(candidate.position.x + candidate.size.x, existing.position.x + existing.size.x) - maxf(candidate.position.x, existing.position.x)
		var overlap_z = minf(candidate.position.z + candidate.size.z, existing.position.z + existing.size.z) - maxf(candidate.position.z, existing.position.z)
		if overlap_x > 0.1 and overlap_z > 0.1:
			return true

	return false


func _get_grid_position() -> Vector3:
	var mouse_position := get_viewport().get_mouse_position()

	var origin := camera.project_ray_origin(mouse_position)
	var direction := camera.project_ray_normal(mouse_position)

	var plane_height := 0.0

	if selected_piece == 3: # Teto
		plane_height = _get_piece_offset().y

	var plane := Plane(Vector3.UP, plane_height)
	var intersection = plane.intersects_ray(origin, direction)

	var point: Vector3
	if intersection == null:
		point = Vector3(
			preview.global_position.x,
			FLOOR_HEIGHT / 2.0,
			preview.global_position.z
		)
	else:
		point = intersection

	var snapped_x := snappedf(point.x, GRID_SIZE)
	var snapped_z := snappedf(point.z, GRID_SIZE)

	var base_y := 0.0
	if selected_piece == 1 or selected_piece == 2 or selected_piece == 3:
		base_y = _get_stack_height(snapped_x, snapped_z)

	return Vector3(
		snapped_x,
		base_y,
		snapped_z
	)


func _create_preview() -> void:
	preview = preview_scene.instantiate()
	add_child(preview)

	preview_mesh = preview.find_child(
		"MeshInstance3D", true, false
	) as MeshInstance3D

	if preview_mesh == null or not (preview_mesh.mesh is BoxMesh):
		push_error("BuildingSystem: prévia precisa de um BoxMesh.")
		return

	var duplicated_mesh: BoxMesh = preview_mesh.mesh.duplicate() as BoxMesh
	preview_mesh.mesh = duplicated_mesh
	preview_box = duplicated_mesh

	preview_material = StandardMaterial3D.new()
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.albedo_color = Color(0, 1, 0, 0.4)

	_apply_preview_color(preview)
	_configure_preview_mesh()


func _apply_preview_color(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = preview_material

	for child in node.get_children():
		_apply_preview_color(child)


func _configure_preview_mesh() -> void:
	match selected_piece:
		0: # Piso
			preview_box.size = Vector3(3, 0.3, 3)

		1: # Parede
			preview_box.size = Vector3(3, 3, 0.3)

		2: # Escada / Rampa
			preview_box.size = Vector3(3, 3, 3)

		3: # Teto
			preview_box.size = Vector3(3, 0.3, 3)



func _get_piece_offset() -> Vector3:
	match selected_piece:
		1:
			var angle := rotation_steps * ROTATION_STEP
			return Vector3(
				sin(angle) * 1.5,
				1.65,
				cos(angle) * 1.5
			)

		2: 
			return Vector3(0, 1.47, 0)

		3:
			return Vector3(0, 3.3, 0)

	return Vector3(0, FLOOR_HEIGHT / 2.0, 0)



func _get_piece_rotation() -> Vector3:
	var rotation_y := rotation_steps * ROTATION_STEP

	if selected_piece == 2:
		return Vector3(-PI / 4.0, rotation_y, 0)

	return Vector3(0, rotation_y, 0)


func _get_piece_size() -> Vector3:
	match selected_piece:
		0: return Vector3(3.0, 0.3, 3.0)   # Piso
		1: return Vector3(2.7, 3.0, 0.3)  # Parede
		2: return Vector3(3.0, 3.0, 3.0)   # Escada / Rampa
		3: return Vector3(3.0, 0.3, 3.0)   # Teto

	return Vector3.ZERO


func _get_piece_bounds(pos: Vector3) -> AABB:
	var half_size := _get_piece_size() * 0.5
	var basis := Basis.from_euler(_get_piece_rotation())

	var extents := Vector3(
		absf(basis.x.x) * half_size.x +
		absf(basis.y.x) * half_size.y +
		absf(basis.z.x) * half_size.z,

		absf(basis.x.y) * half_size.x +
		absf(basis.y.y) * half_size.y +
		absf(basis.z.y) * half_size.z,

		absf(basis.x.z) * half_size.x +
		absf(basis.y.z) * half_size.y +
		absf(basis.z.z) * half_size.z
	)

	return AABB(pos - extents, extents * 2.0)


func _get_selected_scene() -> PackedScene:
	match selected_piece:
		0:
			return floor_scene
		1:
			return wall_scene
		2:
			return ramp_scene
		3:
			return ceiling_scene

	return null


func _select_piece(index: int) -> void:
	var scenes: Array[PackedScene] = [
		floor_scene,
		wall_scene,
		ramp_scene,
		ceiling_scene
	]

	if index < 0 or index >= scenes.size():
		return

	if scenes[index] == null:
		push_warning("BuildingSystem: cena da peça não definida.")
		return

	selected_piece = index
	rotation_steps = 0

	_configure_preview_mesh()

	preview.global_rotation = _get_piece_rotation()
	last_preview_valid = not can_build
	_set_preview_color()


func _rotate_piece() -> void:
	rotation_steps = (rotation_steps + 1) % 4
	preview.global_rotation = _get_piece_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_piece(0)
			KEY_2:
				_select_piece(1)
			KEY_3:
				_select_piece(2)
			KEY_4:
				_select_piece(3)
			KEY_R:
				_rotate_piece()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_place_piece()


func _place_piece() -> void:
	if not can_build:
		return

	var selected_scene := _get_selected_scene()

	if selected_scene == null:
		return

	var pos := preview.global_position

	var new_piece = selected_scene.instantiate()
	get_tree().current_scene.add_child(new_piece)

	new_piece.global_position = pos
	new_piece.global_rotation = _get_piece_rotation()

	occupied_bounds.append(_get_piece_bounds(pos))


func _is_valid_position(pos: Vector3) -> bool:
	var water_center := water.global_position
	var half_size := WATER_SIZE / 2.0

	var inside_x := absf(pos.x - water_center.x) <= half_size
	var inside_z := absf(pos.z - water_center.z) <= half_size

	if not inside_x or not inside_z:
		return false

	if camera.global_position.distance_to(pos) > 6.0:
		return false

	# Garante que a peça possui uma estrutura de suporte embaixo (exceto piso no mar)
	if not _has_support_below(pos):
		return false

	var candidate_bounds := _get_piece_bounds(pos)
	var shrunk_candidate := candidate_bounds.grow(-0.05).abs()

	for existing_bounds in occupied_bounds:
		# Permite o contato direto com a peça de suporte logo abaixo (ex: rampa no piso, teto na parede)
		if _is_direct_support(candidate_bounds, existing_bounds):
			continue

		if shrunk_candidate.intersects(existing_bounds):
			return false

	return true


func _set_preview_color() -> void:
	if last_preview_valid == can_build:
		return

	last_preview_valid = can_build

	if can_build:
		preview_material.albedo_color = Color(0, 1, 0, 0.4)
	else:
		preview_material.albedo_color = Color(1, 0, 0, 0.4)
