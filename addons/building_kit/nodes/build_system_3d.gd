class_name PKBuildSystem3D
extends Node3D

@export var player_camera: Camera3D
## Building in 3D, ready to play: add it to your level, give it a [PKCatalog] and a camera.
## It turns the mouse (or gamepad cursor, or a touch) into aims, shows green / red ghosts,
## spawns the pieces' scenes, and wires everything to a [PKBuilder].
## [codeblock]
## var system := PKBuildSystem3D.new()
## system.catalog = preload("res://building/catalog.tres")
## system.grid_cell_size = Vector3(2, 3, 2)
## add_child(system)
## system.set_cost_handler(PKInventoryCost.make([bag]))
## system.select_buildable(&"foundation")
## [/codeblock]
## The same methods and signals exist on [PKBuildSystem2D].
##
## Pieces get their collision bodies moved to [member piece_layer]; the ground must be on
## [member terrain_mask]. Grid pieces are laid on the terrain (the cursor goes through placed
## pieces), stackable and socket pieces aim at pieces too.

signal placed(placement: PKPlacement, node: Node3D)
signal removed(placement: PKPlacement, refund: Dictionary)
signal moved(placement: PKPlacement, from: PKPlacement)
signal upgraded(placement: PKPlacement, from: PKBuildable)
signal damaged(placement: PKPlacement, amount: float)
signal destroyed(placement: PKPlacement, items: Dictionary)
signal repaired(placement: PKPlacement, cost: Dictionary)
signal rejected(reason: StringName, buildable: PKBuildable)
signal mode_changed(mode: PKBuildController.Mode)
signal buildable_changed(buildable: PKBuildable)
signal blueprint_changed(blueprint: PKBlueprint)
signal selection_changed(uid: int)
signal level_changed(level: int)
## Short player feedback (refusals, refunds). See [member PKBuildController.report_messages].
signal message(text: String, error: bool)
## What the player can afford changed (the catalog greys pieces out again).
signal costs_changed

@export var catalog: PKCatalog
## The camera rays start from (empty: the viewport's camera).
@export var camera: Camera3D
@export_group("Grid")
@export var grid_cell_size := Vector3(1, 1, 1)
@export var grid_origin := Vector3.ZERO
## Snap heights to levels of grid_cell_size.y (else pieces follow the terrain).
@export var snap_height := false
## Use this GridMap's cells (size, position) and its item names as zones.
@export var grid_map: GridMap
## Draw grid lines around the cursor while placing grid pieces.
@export var show_grid := true
@export var grid_color := Color(1, 1, 1, 0.35)
@export_group("Levels")
## Floors the player can switch between (Page Up / Page Down), 0 = no levels.
@export var max_level := 0
## Height of one floor (0 = grid_cell_size.y).
@export var level_height := 0.0
## Hide the pieces above the current floor (and let the cursor through them).
@export var hide_upper_levels := true
@export_group("Physics")
## Layers the cursor hits as ground (terrain, floors, walls of the level).
@export_flags_3d_physics var terrain_mask := 1
## Layer given to the collision bodies of placed pieces.
@export_flags_3d_physics var piece_layer := 2
@export var ray_length := 500.0
## When the ray hits nothing, aim at the horizontal plane through grid_origin (and the floor).
@export var fallback_plane := true
## Rebake this region after building (on a thread, a moment later). See [PKNavigationRebaker].
@export var navigation_region: NavigationRegion3D
@export_group("Input")
## Handle mouse, keyboard, gamepad and touch (off: drive it from your own code).
@export var input_enabled := true
## Aim from the centre of the screen (first-person games) instead of the mouse.
@export var aim_from_screen_center := false
## Gamepad / arrow keys cursor speed, in pixels per second.
@export var cursor_speed := 700.0
@export_group("Look")
@export var valid_color := Color(0.25, 0.95, 0.45, 0.5)
@export var invalid_color := Color(1.0, 0.25, 0.2, 0.5)
## Ghost colour of a valid piece that is barely stable (stability on).
@export var weak_color := Color(1.0, 0.75, 0.15, 0.5)
@export var demolish_color := Color(1.0, 0.2, 0.15, 0.45)
@export var select_color := Color(0.3, 0.65, 1.0, 0.4)
@export var move_color := Color(1.0, 0.8, 0.2, 0.4)
@export var upgrade_color := Color(0.65, 0.45, 1.0, 0.4)
@export var repair_color := Color(0.3, 0.95, 0.8, 0.4)
## Pieces pop in with a little bounce when built.
@export var place_animation := true
## Dust when pieces are demolished or destroyed.
@export var dust := true
@export var dust_color := Color(0.72, 0.66, 0.58, 0.8)
## Where piece scenes are added (empty: this node).
@export var pieces_root: Node3D

var builder: PKBuilder
var controller: PKBuildController
var feedback := PKFeedback.new()
var rebaker := PKNavigationRebaker.new()
## Screen position of the cursor (mouse or virtual cursor).
var cursor_position := Vector2.ZERO
## Show every piece coloured by its stability (red = about to fall).
var stability_view := false:
	set(value):
		stability_view = value
		_refresh_overlays()

var _nodes := {}  # uid -> Node3D
var _variants := {}  # uid -> shape key shown
var _ghosts := []  # pool of {"id": StringName, "node": Node3D}
var _ghost_root := Node3D.new()
var _materials := {}
var _overlay_uids := {}  # uid -> Material applied as overlay
var _grid_mesh: MeshInstance3D
var _area_mesh: MeshInstance3D
var _virtual_cursor := false
var _batches := {}  # buildable id -> _Batch
var _bodyless := 0  # pieces without a collision body (found through their boxes)
var _hidden_by_level := {}


## Copies of one batched buildable, drawn with MultiMesh.
class _Batch:
	var parts: Array = []  # [{"mesh", "material", "transform"}]
	var instances: Array[MultiMeshInstance3D] = []
	var uids: Array[int] = []
	var dirty := true


func _init() -> void:
	builder = PKBuilder.new()
	controller = PKBuildController.new(builder)


func _ready() -> void:
	PKInput.ensure_actions()
	if catalog != null:
		builder.catalog = catalog
	_apply_grid()
	if pieces_root == null:
		pieces_root = self
	controller.max_level = max_level
	_ghost_root.name = "Ghosts"
	add_child(_ghost_root)
	feedback.name = "Feedback"
	add_child(feedback)
	rebaker.name = "NavigationRebaker"
	rebaker.region = navigation_region
	add_child(rebaker)
	_make_grid_mesh()
	_make_area_mesh()
	builder.placed.connect(_on_placed)
	builder.removed.connect(_on_removed)
	builder.moved.connect(_on_moved)
	builder.upgraded.connect(_on_upgraded)
	builder.damaged.connect(_on_damaged)
	builder.destroyed.connect(func(placement: PKPlacement, items: Dictionary) -> void: destroyed.emit(placement, items))
	builder.repaired.connect(func(placement: PKPlacement, cost: Dictionary) -> void:
		feedback.play(&"repair")
		_refresh_overlays()
		repaired.emit(placement, cost))
	builder.rejected.connect(func(reason: StringName, buildable: PKBuildable) -> void:
		feedback.play(&"refuse")
		rejected.emit(reason, buildable))
	builder.reset.connect(_rebuild_all)
	set_cost_handler(builder.cost_handler)
	controller.preview_changed.connect(_draw_ghosts)
	controller.hover_changed.connect(func(_uid: int) -> void: _refresh_overlays())
	controller.selection_changed.connect(func(uid: int) -> void:
		_refresh_overlays()
		selection_changed.emit(uid))
	controller.moving_changed.connect(_on_moving_changed)
	controller.mode_changed.connect(func(mode: PKBuildController.Mode) -> void:
		_refresh_overlays()
		mode_changed.emit(mode))
	controller.buildable_changed.connect(func(buildable: PKBuildable) -> void: buildable_changed.emit(buildable))
	controller.blueprint_changed.connect(func(blueprint: PKBlueprint) -> void: blueprint_changed.emit(blueprint))
	controller.level_changed.connect(_on_level_changed)
	controller.message.connect(func(text: String, error: bool) -> void: message.emit(text, error))
	builder.ground_provider = _ground_at
	cursor_position = get_viewport().get_visible_rect().size * 0.5
	_rebuild_all()


# --- The same API as PKBuildSystem2D ------------------------------------------------------

func select_buildable(value: Variant) -> void:
	controller.select_buildable(value)


func select_blueprint(blueprint: PKBlueprint) -> void:
	controller.select_blueprint(blueprint)


## Who pays: [PKInventoryCost], [PKWalletCost], [PKCallableCost] or your own [PKCost].
func set_cost_handler(handler: PKCost) -> void:
	var old := builder.cost_handler
	if old != null and old.changed.is_connected(_on_costs_changed):
		old.changed.disconnect(_on_costs_changed)
	builder.cost_handler = handler if handler != null else PKCost.new()
	if not builder.cost_handler.changed.is_connected(_on_costs_changed):
		builder.cost_handler.changed.connect(_on_costs_changed)
	_on_costs_changed()


func set_mode(mode: PKBuildController.Mode) -> void:
	controller.set_mode(mode)


func set_level(level: int) -> void:
	controller.set_level(level)


func rotate_piece(direction := 1, fine := false) -> void:
	controller.rotate(direction, fine)
	feedback.play(&"rotate")


func flip_piece() -> void:
	controller.flip()


func undo() -> PKResult:
	return controller.undo()


func cancel() -> void:
	controller.cancel()


func get_node_of(uid: int) -> Node3D:
	return _nodes.get(uid)


## Uid of the piece a node belongs to (0 for none): use it on a collider from your own rays.
func uid_of(node: Node) -> int:
	while node != null and node != self:
		if node.has_meta(&"pk_uid"):
			return int(node.get_meta(&"pk_uid"))
		node = node.get_parent()
	return 0


func to_data() -> Dictionary:
	return builder.to_data()


func load_data(data: Dictionary) -> PKResult:
	return builder.load_data(data)


## The aim under a screen position (mouse, touch).
func aim_at_screen(screen_position: Vector2) -> PKAim:
	var view_camera := _camera()
	if view_camera == null:
		return PKAim.nothing()
	var origin := view_camera.project_ray_origin(screen_position)
	var direction := view_camera.project_ray_normal(screen_position)
	return aim_along(origin, direction)


## The aim along a ray in world space (bots, VR pointers, a first-person camera).
func aim_along(origin: Vector3, direction: Vector3) -> PKAim:
	var hits_pieces := controller.aim_hits_pieces()
	var mask := terrain_mask | (piece_layer if hits_pieces else 0)
	var hit := {}
	if is_inside_tree() and get_world_3d() != null:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * ray_length, mask)
		query.collide_with_areas = false
		hit = get_world_3d().direct_space_state.intersect_ray(query)
	# Pieces without collision shapes are still found through their boxes.
	if hits_pieces and _bodyless > 0:
		var box_hit := builder.layout.raycast(origin, direction, ray_length)
		if not box_hit.is_empty() and (hit.is_empty() or box_hit.distance < origin.distance_to(hit.position) - 0.01):
			var piece: PKPlacement = box_hit.piece
			if _nodes.has(piece.uid) and not _has_body(_nodes[piece.uid]) and not _hidden_by_level.has(piece.uid):
				var point: Vector3 = origin + direction * box_hit.distance
				return PKAim.at(point, _box_normal(piece.get_box(), point), piece.uid)
	# On an upper floor, aim at that floor when nothing nearer is under the cursor.
	var floor_y := grid_origin.y + controller.level * _level_height()
	if controller.level > 0 and absf(direction.y) > 0.0001:
		var t := (floor_y - origin.y) / direction.y
		if t > 0.0 and (hit.is_empty() or (hit.position as Vector3).y < floor_y - 0.05):
			return PKAim.at(origin + direction * t, Vector3.UP)
	if not hit.is_empty():
		return PKAim.at(hit.position, hit.normal, uid_of(hit.collider) if hits_pieces else 0)
	if fallback_plane and absf(direction.y) > 0.0001:
		var t := (floor_y - origin.y) / direction.y
		if t > 0.0:
			return PKAim.at(origin + direction * t, Vector3.UP)
	return PKAim.nothing()


## Aims at a world point (from code): the ground under it.
func aim_at_point(point: Vector3) -> void:
	controller.aim(PKAim.at(point, Vector3.UP))


# --- Input -------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if GameSettings.is_settings_open():
		return
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		_virtual_cursor = false
		cursor_position = event.position
		_update_aim()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			cursor_position = event.position
			_virtual_cursor = false
			if event.pressed:
				controller.press(_current_aim(), event.shift_pressed)
			else:
				controller.release(_current_aim())
			_update_area_mesh()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			controller.cancel()
			_update_area_mesh()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"pk_confirm") and not event is InputEventMouseButton:
		controller.press(_current_aim(), Input.is_key_pressed(KEY_SHIFT))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released(&"pk_confirm") and not event is InputEventMouseButton:
		controller.release(_current_aim())
		_update_area_mesh()
		get_viewport().set_input_as_handled()
		return
	var angle := controller.angle
	if PKInput.handle_common(event, controller):
		if not is_equal_approx(angle, controller.angle):
			feedback.play(&"rotate")
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_flush_batches()
	if not input_enabled:
		return
	var stick := PKInput.cursor_vector()
	if stick.length() > 0.0:
		_virtual_cursor = true
		var size := get_viewport().get_visible_rect().size
		cursor_position = (cursor_position + stick * cursor_speed * delta).clamp(Vector2.ZERO, size)
		_update_aim()
	elif aim_from_screen_center:
		_update_aim()


func _update_aim() -> void:
	controller.aim(_current_aim())
	_update_area_mesh()


func _current_aim() -> PKAim:
	var position := get_viewport().get_visible_rect().size * 0.5 if aim_from_screen_center else cursor_position
	return aim_at_screen(position)


## True while the gamepad / arrows move the cursor (the HUD draws a crosshair there).
func is_virtual_cursor() -> bool:
	return _virtual_cursor


## Screen position of the cursor (for the HUD crosshair).
func get_cursor_screen_position() -> Vector2:
	return cursor_position


# --- Pieces ------------------------------------------------------------------------------

func _on_placed(placement: PKPlacement) -> void:
	var node := _spawn(placement)
	_notify_neighbors(placement)
	feedback.play(&"place")
	if place_animation and node != null and not placement.buildable.batch_render:
		_pop(node)
	rebaker.request()
	placed.emit(placement, node)


func _on_removed(placement: PKPlacement, refund: Dictionary) -> void:
	_despawn(placement)
	_notify_neighbors(placement)
	feedback.play(&"demolish")
	if dust:
		_dust(placement)
	rebaker.request()
	_refresh_overlays()
	removed.emit(placement, refund)


func _on_moved(placement: PKPlacement, from: PKPlacement) -> void:
	var node: Node3D = _nodes.get(placement.uid)
	if node != null:
		node.transform = placement.get_transform()
		node.visible = true
	_mark_batch(placement)
	_notify_neighbors(from)
	_notify_neighbors(placement)
	feedback.play(&"place")
	rebaker.request()
	moved.emit(placement, from)


func _on_upgraded(placement: PKPlacement, from: PKBuildable) -> void:
	var stand_in := placement.duplicate_pose()
	stand_in.buildable = from
	stand_in.buildable_id = from.id
	_despawn(stand_in)
	var node := _spawn(placement)
	if place_animation and node != null and not placement.buildable.batch_render:
		_pop(node)
	feedback.play(&"upgrade")
	rebaker.request()
	_refresh_overlays()
	upgraded.emit(placement, from)


func _on_damaged(placement: PKPlacement, amount: float) -> void:
	var node: Node3D = _nodes.get(placement.uid)
	if node != null and not placement.buildable.batch_render and placement.get_health() > 0.0:
		var tween := node.create_tween()
		var base := placement.get_transform().origin
		for i in 3:
			tween.tween_property(node, "position", base + Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05)), 0.04)
		tween.tween_property(node, "position", base, 0.04)
	_refresh_overlays()
	damaged.emit(placement, amount)


func _on_moving_changed(uid: int) -> void:
	for piece_uid in _nodes:
		var placement := builder.layout.get_piece(piece_uid)
		_nodes[piece_uid].visible = piece_uid != uid and not _hidden_by_level.has(piece_uid)
		if placement != null and placement.buildable.batch_render:
			_mark_batch(placement)
	_refresh_overlays()


func _on_level_changed(level: int) -> void:
	_apply_level_visibility()
	level_changed.emit(level)


func _rebuild_all() -> void:
	for uid in _nodes:
		_nodes[uid].queue_free()
	_nodes.clear()
	_variants.clear()
	_overlay_uids.clear()
	_hidden_by_level.clear()
	_bodyless = 0
	for batch: _Batch in _batches.values():
		batch.uids.clear()
		batch.dirty = true
	for placement in builder.layout.get_all():
		_spawn(placement)
	for placement in builder.layout.get_all():
		if placement.buildable != null and placement.buildable.has_variants():
			_update_variant(placement)
	_apply_level_visibility()
	rebaker.request()
	controller.refresh()


func _spawn(placement: PKPlacement) -> Node3D:
	var buildable := placement.buildable
	var node: Node3D
	if buildable != null and buildable.batch_render:
		node = _batch_body(placement)
		_batch_of(buildable).uids.append(placement.uid)
		_mark_batch(placement)
	elif buildable != null and buildable.has_variants():
		node = Node3D.new()
	else:
		node = _instantiate(buildable)
	node.name = "%s_%d" % [placement.buildable_id, placement.uid]
	node.set_meta(&"pk_uid", placement.uid)
	_set_piece_layer(node)
	pieces_root.add_child(node)
	node.transform = placement.get_transform()
	_nodes[placement.uid] = node
	if buildable != null and buildable.has_variants():
		_update_variant(placement)
	if not _has_body(node):
		_bodyless += 1
		node.set_meta(&"pk_bodyless", true)
	if node.has_method(&"pk_placed"):
		node.call(&"pk_placed", self, placement)
	if hide_upper_levels and max_level > 0 and _above_level(placement):
		_hide_for_level(placement.uid, node)
	return node


func _despawn(placement: PKPlacement) -> void:
	var node: Node3D = _nodes.get(placement.uid)
	_nodes.erase(placement.uid)
	_variants.erase(placement.uid)
	_overlay_uids.erase(placement.uid)
	_hidden_by_level.erase(placement.uid)
	if placement.buildable != null and _batches.has(placement.buildable.id):
		var batch: _Batch = _batches[placement.buildable.id]
		batch.uids.erase(placement.uid)
		batch.dirty = true
	if node != null:
		if node.has_meta(&"pk_bodyless"):
			_bodyless -= 1
		node.queue_free()


func _notify_neighbors(placement: PKPlacement) -> void:
	var box := placement.get_box()
	var area := box.get_aabb().grow(maxf(grid_cell_size.x, grid_cell_size.z) * 0.6)
	for other in builder.layout.near(area):
		if other.buildable != null and other.buildable.has_variants():
			_update_variant(other)
		var node: Node3D = _nodes.get(other.uid)
		if node != null and node.has_method(&"pk_neighbors_changed"):
			node.call(&"pk_neighbors_changed", self)


## Autotiling: shows the scene of the shape the neighbours make.
func _update_variant(placement: PKPlacement) -> void:
	var holder: Node3D = _nodes.get(placement.uid)
	if holder == null:
		return
	var buildable := placement.buildable
	var step := minf(grid_cell_size.x, grid_cell_size.z) * maxf(buildable.cells.x, 1)
	var shape := PKAutotile.shape_of(PKAutotile.mask_of(builder.layout, placement, buildable.autotile_tag, step))
	var key := "%s_%d" % [shape.shape, int(shape.angle)]
	if _variants.get(placement.uid, "") == key:
		return
	_variants[placement.uid] = key
	for child in holder.get_children():
		if not child.name.begins_with("PK"):
			child.queue_free()
	var scene: PackedScene = buildable.variant_scenes.get(shape.shape, buildable.scene)
	var visual: Node3D = scene.instantiate() if scene != null else _default_piece(buildable)
	# The holder carries the piece's own angle; the shape turns in world space.
	visual.rotation.y = -deg_to_rad(shape.angle - placement.angle)
	holder.add_child(visual)
	_set_piece_layer(visual)
	if _hidden_by_level.has(placement.uid):
		_clear_layers(visual)


func _instantiate(buildable: PKBuildable) -> Node3D:
	if buildable != null and buildable.scene != null:
		var instance := buildable.scene.instantiate()
		if instance is Node3D:
			return instance
		instance.free()
	return _default_piece(buildable)


func _default_piece(buildable: PKBuildable) -> Node3D:
	var placement := PKPlacement.make(buildable)
	placement.cell_size = builder.grid.cell_size
	var size := placement.get_size()
	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = buildable.color if buildable != null else Color.GRAY
	box.material = material
	mesh.mesh = box
	var offset := Vector3(0, size.y * 0.5, 0) + (buildable.box_offset if buildable != null else Vector3.ZERO)
	mesh.position = offset
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = offset
	body.add_child(shape)
	return body


func _set_piece_layer(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = piece_layer
	for child in node.get_children():
		_set_piece_layer(child)


func _has_body(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child in node.get_children():
		if _has_body(child):
			return true
	return false


func _pop(node: Node3D) -> void:
	var size := node.scale
	node.scale = size * 0.82
	var tween := node.create_tween()
	tween.tween_property(node, "scale", size * 1.06, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", size, 0.1)


func _dust(placement: PKPlacement) -> void:
	if not is_inside_tree():
		return
	var box := placement.get_box()
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.amount = clampi(int(box.half.x * box.half.z * 24.0) + 10, 10, 48)
	particles.lifetime = 0.9
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = box.half
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 2.0
	particles.gravity = Vector3(0, -2.5, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	particles.mesh = mesh
	var fade := Gradient.new()
	fade.set_color(0, dust_color)
	fade.set_color(1, Color(dust_color, 0.0))
	particles.color_ramp = fade
	add_child(particles)
	particles.global_position = box.center
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


# --- MultiMesh batches -------------------------------------------------------------------

func _batch_of(buildable: PKBuildable) -> _Batch:
	if _batches.has(buildable.id):
		return _batches[buildable.id]
	var batch := _Batch.new()
	var sample := _instantiate(buildable)
	_collect_meshes(sample, Transform3D.IDENTITY, batch.parts, true)
	sample.free()
	for part in batch.parts:
		var instance := MultiMeshInstance3D.new()
		instance.name = "PKBatch_%s" % buildable.id
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = part.mesh
		instance.multimesh = multimesh
		instance.material_override = part.material
		pieces_root.add_child(instance)
		batch.instances.append(instance)
	_batches[buildable.id] = batch
	return batch


func _collect_meshes(node: Node, parent: Transform3D, parts: Array, root := false) -> void:
	var transform := parent if root or not node is Node3D else parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		var material := mesh_node.material_override
		if material == null and mesh_node.mesh.get_surface_count() > 0:
			material = mesh_node.mesh.surface_get_material(0)
		parts.append({"mesh": mesh_node.mesh, "material": material, "transform": transform})
	for child in node.get_children():
		_collect_meshes(child, transform, parts)


func _batch_body(placement: PKPlacement) -> Node3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	var size := placement.get_size()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = Vector3(0, size.y * 0.5, 0) + placement.buildable.box_offset
	body.add_child(shape)
	return body


func _mark_batch(placement: PKPlacement) -> void:
	if placement.buildable != null and _batches.has(placement.buildable.id):
		(_batches[placement.buildable.id] as _Batch).dirty = true


## Writes the instance transforms of the batches that changed (once per frame at most).
func _flush_batches() -> void:
	for batch: _Batch in _batches.values():
		if not batch.dirty:
			continue
		batch.dirty = false
		var shown: Array[PKPlacement] = []
		for uid in batch.uids:
			var placement := builder.layout.get_piece(uid)
			if placement != null and uid != controller.moving_uid and not _hidden_by_level.has(uid):
				shown.append(placement)
		for index in batch.instances.size():
			var multimesh := batch.instances[index].multimesh
			var local: Transform3D = batch.parts[index].transform
			multimesh.instance_count = shown.size()
			for i in shown.size():
				multimesh.set_instance_transform(i, shown[i].get_transform() * local)


## Number of copies of [param buildable_id] drawn through MultiMesh (0 when not batched).
func get_batched_count(buildable_id: StringName) -> int:
	_flush_batches()
	if not _batches.has(buildable_id):
		return 0
	var batch: _Batch = _batches[buildable_id]
	return batch.instances[0].multimesh.instance_count if not batch.instances.is_empty() else 0


# --- Levels ------------------------------------------------------------------------------

func _level_height() -> float:
	return level_height if level_height > 0.0 else grid_cell_size.y


func _above_level(placement: PKPlacement) -> bool:
	var top_of_level := grid_origin.y + (controller.level + 1) * _level_height()
	return placement.get_box().get_aabb().position.y >= top_of_level - 0.05


func _apply_level_visibility() -> void:
	for uid in _hidden_by_level.keys():
		var node: Node3D = _nodes.get(uid)
		if node != null:
			node.visible = uid != controller.moving_uid
			_set_piece_layer(node)
	_hidden_by_level.clear()
	if hide_upper_levels and max_level > 0:
		for placement in builder.layout.get_all():
			if _above_level(placement) and _nodes.has(placement.uid):
				_hide_for_level(placement.uid, _nodes[placement.uid])
	for batch: _Batch in _batches.values():
		batch.dirty = true


func _hide_for_level(uid: int, node: Node3D) -> void:
	_hidden_by_level[uid] = true
	node.visible = false
	_clear_layers(node)


func _clear_layers(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = 0
	for child in node.get_children():
		_clear_layers(child)


# --- Ghosts and highlights ---------------------------------------------------------------

func _draw_ghosts() -> void:
	var previews: Array[PKPreview] = []
	if controller.drag != null:
		previews = controller.drag.previews
	elif controller.preview != null:
		previews = [controller.preview]
	var used := 0
	for preview in previews:
		if preview.get_buildable() == null:
			continue
		var ghost := _ghost_for(preview.get_buildable(), used)
		used += 1
		ghost.transform = preview.placement.get_transform()
		ghost.visible = true
		_tint(ghost, ghost_color(preview))
	for i in range(used, _ghosts.size()):
		_ghosts[i].node.visible = false
	_update_grid_mesh(previews)


## Colour of the ghost of [param preview]: red when refused, green when valid, towards amber
## when it is barely stable (stability on).
func ghost_color(preview: PKPreview) -> Color:
	if not preview.valid:
		return invalid_color
	if not builder.stability_enabled:
		return valid_color
	var low := builder.min_stability
	var value := clampf((preview.placement.stability - low) / maxf(1.0 - low, 0.001), 0.0, 1.0)
	return weak_color.lerp(valid_color, value)


func _ghost_for(buildable: PKBuildable, index: int) -> Node3D:
	var id := buildable.id if buildable != null else &""
	if index < _ghosts.size() and _ghosts[index].id == id:
		return _ghosts[index].node
	var node := _make_ghost(buildable)
	if index < _ghosts.size():
		_ghosts[index].node.queue_free()
		_ghosts[index] = {"id": id, "node": node}
	else:
		_ghosts.append({"id": id, "node": node})
	_ghost_root.add_child(node)
	return node


func _make_ghost(buildable: PKBuildable) -> Node3D:
	var source: PackedScene = buildable.variant_scenes.get("single", buildable.scene) if buildable.has_variants() else buildable.scene
	var node: Node3D
	if source != null:
		var instance := source.instantiate()
		if instance is Node3D:
			node = instance
		else:
			instance.free()
			node = _default_piece(buildable)
	else:
		node = _default_piece(buildable)
	_strip_for_ghost(node)
	var footprint := MeshInstance3D.new()
	footprint.name = "PKFootprint"
	var plane := PlaneMesh.new()
	var placement := PKPlacement.make(buildable)
	placement.cell_size = builder.grid.cell_size
	var size := placement.get_size()
	plane.size = Vector2(size.x, size.z)
	footprint.mesh = plane
	footprint.position = Vector3(0, 0.03, 0) + Vector3(buildable.box_offset.x, 0, buildable.box_offset.z)
	footprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(footprint)
	return node


func _strip_for_ghost(node: Node) -> void:
	for child in node.get_children():
		_strip_for_ghost(child)
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is CollisionShape3D:
		node.disabled = true
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is Light3D:
		node.visible = false
	# Ghosts never run game logic (scripts of the piece stay idle).
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _tint(node: Node, color: Color) -> void:
	var material := _ghost_material(color)
	for mesh in _geometry(node):
		mesh.material_override = material


func _ghost_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	if _materials.size() > 96:
		_materials.clear()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b) * 0.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.6
	material.render_priority = 1
	_materials[key] = material
	return material


func _overlay_material(color: Color) -> StandardMaterial3D:
	var key := "overlay_" + color.to_html()
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.grow = true
	material.grow_amount = 0.01
	_materials[key] = material
	return material


## Which pieces get a coloured overlay now, {uid: Color}.
func _wanted_overlays() -> Dictionary:
	var wanted := {}
	if stability_view:
		for placement in builder.layout.get_all():
			wanted[placement.uid] = stability_color(placement.stability)
	for uid in controller.get_selection():
		wanted[uid] = select_color
	if controller.mode == PKBuildController.Mode.REPAIR:
		for placement in builder.layout.get_all():
			if placement.is_damaged():
				wanted[placement.uid] = Color(repair_color, 0.22)
	if controller.hover_uid != 0:
		match controller.mode:
			PKBuildController.Mode.DEMOLISH:
				wanted[controller.hover_uid] = demolish_color
				for piece in builder.dependents_of(controller.hover_uid):
					wanted[piece.uid] = demolish_color
			PKBuildController.Mode.MOVE:
				wanted[controller.hover_uid] = move_color
			PKBuildController.Mode.SELECT:
				wanted[controller.hover_uid] = select_color
			PKBuildController.Mode.UPGRADE:
				wanted[controller.hover_uid] = upgrade_color if builder.can_upgrade(controller.hover_uid).is_empty() else Color(invalid_color, 0.22)
			PKBuildController.Mode.REPAIR:
				wanted[controller.hover_uid] = repair_color
	return wanted


## Red (about to fall) to amber to green (solid), for a stability from 0 to 1.
func stability_color(value: float) -> Color:
	value = clampf(value, 0.0, 1.0)
	var low := Color(invalid_color, 0.6).lerp(Color(weak_color, 0.55), clampf(value * 2.0, 0.0, 1.0))
	return low.lerp(Color(valid_color, 0.45), clampf(value * 2.0 - 1.0, 0.0, 1.0))


func _refresh_overlays() -> void:
	if not is_inside_tree():
		return
	var wanted := _wanted_overlays()
	for uid in _overlay_uids.keys():
		if not wanted.has(uid) and _nodes.has(uid):
			_set_overlay(uid, null)
	_overlay_uids.clear()
	for uid in wanted:
		if _nodes.has(uid):
			var material := _overlay_material(wanted[uid])
			_set_overlay(uid, material)
			_overlay_uids[uid] = material


func _set_overlay(uid: int, material: Material) -> void:
	var node: Node3D = _nodes[uid]
	var placement := builder.layout.get_piece(uid)
	if placement != null and placement.buildable.batch_render:
		# Batched copies have no meshes of their own: a box shows the highlight.
		var marker: MeshInstance3D = node.get_node_or_null(^"PKHighlight")
		if material == null:
			if marker != null:
				marker.queue_free()
			return
		if marker == null:
			marker = MeshInstance3D.new()
			marker.name = "PKHighlight"
			var box := BoxMesh.new()
			box.size = placement.get_size() + Vector3.ONE * 0.04
			marker.mesh = box
			marker.position = Vector3(0, placement.get_size().y * 0.5, 0) + placement.buildable.box_offset
			node.add_child(marker)
		marker.material_override = material
		return
	for mesh in _geometry(node):
		mesh.material_overlay = material


func _geometry(node: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	if node is GeometryInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_geometry(child))
	return found


# --- Grid --------------------------------------------------------------------------------

func _apply_grid() -> void:
	var grid := PKGrid.make(grid_cell_size, grid_origin)
	grid.snap_height = snap_height
	if grid_map != null:
		grid.cell_size = grid_map.cell_size
		grid.origin = grid_map.global_position if grid_map.is_inside_tree() else grid_map.position
		grid.snap_height = true
		builder.zone_provider = _grid_map_zone
	grid_cell_size = grid.cell_size
	builder.grid = grid


func _grid_map_zone(position: Vector3, _cell: Vector3i) -> StringName:
	if grid_map == null or grid_map.mesh_library == null:
		return &""
	var below := position - Vector3(0, grid_map.cell_size.y * 0.5, 0)
	var item := grid_map.get_cell_item(grid_map.local_to_map(grid_map.to_local(below)))
	if item == GridMap.INVALID_CELL_ITEM:
		return &"empty"
	return StringName(grid_map.mesh_library.get_item_name(item).to_lower())


func _ground_at(point: Vector3) -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {"position": point, "normal": Vector3.UP}
	var floor_y := grid_origin.y + controller.level * _level_height()
	if controller.level > 0:
		return {"position": Vector3(point.x, floor_y, point.z), "normal": Vector3.UP}
	var top := point + Vector3.UP * 50.0
	var query := PhysicsRayQueryParameters3D.create(top, point + Vector3.DOWN * 50.0, terrain_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": Vector3(point.x, floor_y, point.z), "normal": Vector3.UP} if fallback_plane else {}
	return {"position": hit.position, "normal": hit.normal}


func _make_grid_mesh() -> void:
	_grid_mesh = MeshInstance3D.new()
	_grid_mesh.name = "PKGridLines"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	_grid_mesh.mesh = plane
	_grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = GRID_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_grid_mesh.material_override = material
	_grid_mesh.visible = false
	add_child(_grid_mesh)


## A flat box under the selection rectangle being dragged.
func _make_area_mesh() -> void:
	_area_mesh = MeshInstance3D.new()
	_area_mesh.name = "PKSelectionBox"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_area_mesh.mesh = box
	_area_mesh.material_override = _overlay_material(Color(select_color, 0.25))
	_area_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_area_mesh.visible = false
	add_child(_area_mesh)


func _update_area_mesh() -> void:
	if _area_mesh == null:
		return
	var corners := controller.get_selection_box()
	if corners.is_empty():
		_area_mesh.visible = false
		return
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	_area_mesh.visible = true
	_area_mesh.global_position = Vector3((a.x + b.x) * 0.5, minf(a.y, b.y) + 0.1, (a.z + b.z) * 0.5)
	_area_mesh.scale = Vector3(maxf(absf(a.x - b.x), 0.05), 0.2, maxf(absf(a.z - b.z), 0.05))


func _update_grid_mesh(previews: Array[PKPreview]) -> void:
	if _grid_mesh == null:
		return
	var buildable := controller.get_active_buildable()
	if not show_grid or previews.is_empty() or buildable == null or not buildable.uses(PKBuildable.Snap.GRID) or previews[0].snapped_to_socket:
		_grid_mesh.visible = false
		return
	var center := previews[previews.size() - 1].placement.position
	var radius := maxf(grid_cell_size.x, grid_cell_size.z) * 4.0
	if previews.size() > 1:
		var first := previews[0].placement.position
		center = (first + center) * 0.5
		radius = maxf(radius, first.distance_to(previews[previews.size() - 1].placement.position) * 0.5 + radius * 0.6)
	_grid_mesh.visible = true
	_grid_mesh.global_position = Vector3(center.x, center.y + 0.02, center.z)
	_grid_mesh.scale = Vector3(radius * 2.0, 1, radius * 2.0)
	var material: ShaderMaterial = _grid_mesh.material_override
	material.set_shader_parameter(&"cell", Vector2(grid_cell_size.x, grid_cell_size.z))
	material.set_shader_parameter(&"origin", Vector2(builder.grid.origin.x, builder.grid.origin.z))
	material.set_shader_parameter(&"line_color", grid_color)


func _camera() -> Camera3D:
	if camera != null:
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _on_costs_changed() -> void:
	controller.refresh()
	costs_changed.emit()


static func _box_normal(box: PKBox, point: Vector3) -> Vector3:
	var local := point - box.center
	var best := Vector3.UP
	var best_score := -INF
	for axis in 3:
		var direction: Vector3 = box.basis[axis]
		var score := absf(local.dot(direction)) / maxf(box.half[axis], 0.0001)
		if score > best_score:
			best_score = score
			best = direction * signf(local.dot(direction))
	return best


const GRID_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec2 cell = vec2(1.0);
uniform vec2 origin = vec2(0.0);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.35);
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = (world.xz - origin) / cell;
	vec2 g = abs(fract(p - 0.5) - 0.5) / fwidth(p);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	float d = length(UV - vec2(0.5)) * 2.0;
	float fade = 1.0 - smoothstep(0.55, 1.0, d);
	ALBEDO = line_color.rgb;
	ALPHA = line * fade * line_color.a;
}
"""
