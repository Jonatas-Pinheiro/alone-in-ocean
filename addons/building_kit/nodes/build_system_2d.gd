class_name PKBuildSystem2D
extends Node2D
## Building in 2D (top-down or side games), ready to play: the same methods and signals as
## [PKBuildSystem3D], on a TileMapLayer or a plain grid.
## [codeblock]
## var system := PKBuildSystem2D.new()
## system.catalog = preload("res://building/city_catalog.tres")
## system.tile_map = $Ground          # cell size and zones from the tiles
## add_child(system)
## system.set_cost_handler(PKWalletCost.make({&"gold": 500}))
## [/codeblock]
## 2D positions (x, y) are kept as (x, 0, y) in the core, so rules, saves and tests are the
## same in both worlds. Zones come from the TileMapLayer custom data layer named
## [member zone_layer_name] ("zone": "water", "grass"...). Floor levels ([member max_level])
## are stacked layers: the pieces of the other levels are hidden or dimmed.

signal placed(placement: PKPlacement, node: Node2D)
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
signal message(text: String, error: bool)
signal costs_changed

@export var catalog: PKCatalog
@export_group("Grid")
@export var grid_cell_size := Vector2(32, 32)
@export var grid_origin := Vector2.ZERO
## Use this layer's tile size and position, and its custom data as zones.
@export var tile_map: TileMapLayer
## Name of the TileSet custom data layer that holds zones (String or StringName).
@export var zone_layer_name := "zone"
## Cells where building is allowed, in cells (size 0 = anywhere).
@export var bounds := Rect2i()
@export var show_grid := true
@export var grid_color := Color(1, 1, 1, 0.22)
@export_group("Levels")
## Floor levels (Page Up / Page Down), 0 = none. Each level is its own layer of pieces.
@export var max_level := 0
## Pieces of the levels below the current one are drawn dimmed (off: hidden).
@export var show_lower_levels := true
@export_group("Navigation")
## Rebake this region after building (on a thread, a moment later). See [PKNavigationRebaker].
@export var navigation_region: NavigationRegion2D
@export_group("Input")
@export var input_enabled := true
@export var cursor_speed := 700.0
@export_group("Look")
@export var valid_color := Color(0.3, 1.0, 0.45, 0.6)
@export var invalid_color := Color(1.0, 0.3, 0.25, 0.6)
@export var weak_color := Color(1.0, 0.75, 0.2, 0.6)
@export var demolish_color := Color(1.0, 0.25, 0.2, 0.55)
@export var select_color := Color(0.35, 0.7, 1.0, 0.5)
@export var move_color := Color(1.0, 0.8, 0.25, 0.5)
@export var upgrade_color := Color(0.7, 0.5, 1.0, 0.5)
@export var repair_color := Color(0.3, 0.95, 0.8, 0.5)
## Show the areas of influence ([member PKBuildable.needs_nearby_tag]) while placing.
@export var show_influence := true
@export var influence_color := Color(0.45, 0.85, 1.0, 0.16)
@export var place_animation := true
@export var dust := true
@export var dust_color := Color(0.85, 0.8, 0.7, 0.85)
## Where piece scenes are added (empty: this node). Its y-sort is respected.
@export var pieces_root: Node2D

var builder: PKBuilder
var controller: PKBuildController
var feedback := PKFeedback.new()
var rebaker := PKNavigationRebaker.new()
## Cursor in this node's local coordinates.
var cursor_position := Vector2.ZERO

var _nodes := {}
var _variants := {}
var _ghosts := []
var _ghost_root := Node2D.new()
var _overlay := _Overlay.new()
var _materials := {}
var _tinted := {}  # uid -> true for pieces whose modulate is changed
var _virtual_cursor := false


## Draws the grid near the cursor, footprints, highlights, influence and the selection box.
class _Overlay extends Node2D:
	var system: PKBuildSystem2D
	var boxes: Array = []  # [corners PackedVector2Array, Color]
	var highlights: Array = []
	var areas: Array = []  # [Rect2, Color]

	func _draw() -> void:
		if system == null:
			return
		for entry in areas:
			draw_rect(entry[0], entry[1])
			draw_rect(entry[0], Color(entry[1], minf(entry[1].a * 3.0, 0.8)), false, 2.0)
		system._draw_grid(self)
		for entry in boxes + highlights:
			var points: PackedVector2Array = entry[0]
			var color: Color = entry[1]
			draw_colored_polygon(points, Color(color, color.a * 0.35))
			var outline := points.duplicate()
			outline.append(points[0])
			draw_polyline(outline, color.lightened(0.2), 2.0)
		var corners: Array[Vector3] = system.controller.get_selection_box()
		if not corners.is_empty():
			var a := PKBuildSystem2D.to_2d(corners[0])
			var b := PKBuildSystem2D.to_2d(corners[1])
			var rect := Rect2(a, Vector2.ZERO).expand(b)
			draw_rect(rect, Color(system.select_color, 0.15))
			draw_rect(rect, system.select_color, false, 2.0)


## Default look of a piece without a scene: a coloured box.
class _BoxPiece extends Node2D:
	var size := Vector2(32, 32)
	var color := Color.GRAY

	func _draw() -> void:
		var rect := Rect2(-size * 0.5, size)
		draw_rect(rect.grow(-1.0), color)
		draw_rect(rect.grow(-1.0), color.darkened(0.35), false, 2.0)


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
	_ghost_root.z_index = 10
	add_child(_ghost_root)
	_overlay.name = "Overlay"
	_overlay.system = self
	_overlay.z_index = 9
	add_child(_overlay)
	feedback.name = "Feedback"
	add_child(feedback)
	rebaker.name = "NavigationRebaker"
	rebaker.region = navigation_region
	add_child(rebaker)
	builder.placed.connect(_on_placed)
	builder.removed.connect(_on_removed)
	builder.moved.connect(_on_moved)
	builder.upgraded.connect(_on_upgraded)
	builder.damaged.connect(func(placement: PKPlacement, amount: float) -> void:
		_refresh_overlays()
		damaged.emit(placement, amount))
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
	controller.level_changed.connect(func(level: int) -> void:
		_apply_level_visibility()
		level_changed.emit(level))
	controller.message.connect(func(text: String, error: bool) -> void: message.emit(text, error))
	_rebuild_all()


# --- The same API as PKBuildSystem3D ------------------------------------------------------

func select_buildable(value: Variant) -> void:
	controller.select_buildable(value)


func select_blueprint(blueprint: PKBlueprint) -> void:
	controller.select_blueprint(blueprint)


func set_cost_handler(handler: PKCost) -> void:
	var old := builder.cost_handler
	if old != null and old.changed.is_connected(_on_costs_changed):
		old.changed.disconnect(_on_costs_changed)
	builder.cost_handler = handler if handler != null else PKCost.new()
	if not builder.cost_handler.changed.is_connected(_on_costs_changed):
		builder.cost_handler.changed.connect(_on_costs_changed)
	_on_costs_changed()


func _on_costs_changed() -> void:
	controller.refresh()
	costs_changed.emit()


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


func get_node_of(uid: int) -> Node2D:
	return _nodes.get(uid)


func to_data() -> Dictionary:
	return builder.to_data()


func load_data(data: Dictionary) -> PKResult:
	return builder.load_data(data)


## 2D point (local to this node) to the core's 3D coordinates, and back.
static func to_core(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)


static func to_2d(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


## The aim at a point local to this node (on the current level).
func aim_at_local(point: Vector2) -> PKAim:
	var aim := PKAim.at(to_core(point))
	aim.position.y = controller.level * builder.grid.cell_size.y
	var piece := _piece_on_level(aim.position)
	if piece != null and controller.aim_hits_pieces() and controller.moving_uid != piece.uid:
		aim.hit_uid = piece.uid
		if controller.mode == PKBuildController.Mode.BUILD:
			aim.position.y = piece.get_top()
	return aim


func aim_at_point(point: Vector2) -> void:
	cursor_position = point
	controller.aim(aim_at_local(point))
	_refresh_influence()
	_overlay.queue_redraw()


# --- Input -------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if GameSettings.is_settings_open():
		return
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		_virtual_cursor = false
		aim_at_point(get_local_mouse_position())
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_virtual_cursor = false
			cursor_position = get_local_mouse_position()
			if event.pressed:
				controller.press(aim_at_local(cursor_position), event.shift_pressed)
			else:
				controller.release(aim_at_local(cursor_position))
			_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			controller.cancel()
			_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"pk_confirm") and not event is InputEventMouseButton:
		controller.press(aim_at_local(cursor_position), Input.is_key_pressed(KEY_SHIFT))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released(&"pk_confirm") and not event is InputEventMouseButton:
		controller.release(aim_at_local(cursor_position))
		_overlay.queue_redraw()
		get_viewport().set_input_as_handled()
		return
	var angle := controller.angle
	if PKInput.handle_common(event, controller):
		if not is_equal_approx(angle, controller.angle):
			feedback.play(&"rotate")
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not input_enabled:
		return
	var stick := PKInput.cursor_vector()
	if stick.length() > 0.0:
		_virtual_cursor = true
		var screen := get_global_transform_with_canvas() * cursor_position
		var size := get_viewport().get_visible_rect().size
		screen = (screen + stick * cursor_speed * delta).clamp(Vector2.ZERO, size)
		aim_at_point(get_global_transform_with_canvas().affine_inverse() * screen)


func is_virtual_cursor() -> bool:
	return _virtual_cursor


## Screen position of the cursor (for the HUD crosshair).
func get_cursor_screen_position() -> Vector2:
	return get_global_transform_with_canvas() * cursor_position


# --- Pieces ------------------------------------------------------------------------------

func _on_placed(placement: PKPlacement) -> void:
	var node := _spawn(placement)
	_notify_neighbors(placement)
	feedback.play(&"place")
	if place_animation:
		_pop(node)
	rebaker.request()
	placed.emit(placement, node)


func _on_removed(placement: PKPlacement, refund: Dictionary) -> void:
	_despawn(placement.uid)
	_notify_neighbors(placement)
	feedback.play(&"demolish")
	if dust:
		_dust(placement)
	rebaker.request()
	_refresh_overlays()
	removed.emit(placement, refund)


func _on_moved(placement: PKPlacement, from: PKPlacement) -> void:
	var node: Node2D = _nodes.get(placement.uid)
	if node != null:
		_pose(node, placement)
		node.visible = true
	_notify_neighbors(from)
	_notify_neighbors(placement)
	feedback.play(&"place")
	rebaker.request()
	moved.emit(placement, from)


func _on_upgraded(placement: PKPlacement, from: PKBuildable) -> void:
	_despawn(placement.uid)
	var node := _spawn(placement)
	if place_animation:
		_pop(node)
	feedback.play(&"upgrade")
	_refresh_overlays()
	upgraded.emit(placement, from)


func _on_moving_changed(uid: int) -> void:
	for piece_uid in _nodes:
		_nodes[piece_uid].visible = piece_uid != uid
	_apply_level_visibility()
	_refresh_overlays()


func _rebuild_all() -> void:
	for uid in _nodes:
		_nodes[uid].queue_free()
	_nodes.clear()
	_variants.clear()
	_tinted.clear()
	for placement in builder.layout.get_all():
		_spawn(placement)
	for placement in builder.layout.get_all():
		_notify_neighbors(placement)
	_apply_level_visibility()
	rebaker.request()
	controller.refresh()


func _spawn(placement: PKPlacement) -> Node2D:
	var buildable := placement.buildable
	var node: Node2D = Node2D.new() if buildable != null and buildable.has_variants() else _instantiate(buildable)
	node.name = "%s_%d" % [placement.buildable_id, placement.uid]
	node.set_meta(&"pk_uid", placement.uid)
	pieces_root.add_child(node)
	_pose(node, placement)
	_nodes[placement.uid] = node
	if buildable != null and buildable.has_variants():
		_update_variant(placement)
	if node.has_method(&"pk_placed"):
		node.call(&"pk_placed", self, placement)
	_apply_level_to(placement, node)
	return node


func _despawn(uid: int) -> void:
	var node: Node2D = _nodes.get(uid)
	_nodes.erase(uid)
	_variants.erase(uid)
	_tinted.erase(uid)
	if node != null:
		node.queue_free()


func _pose(node: Node2D, placement: PKPlacement) -> void:
	node.position = to_2d(placement.position)
	node.rotation_degrees = placement.angle
	node.scale = Vector2(-1, 1) if placement.flipped else Vector2.ONE


func _notify_neighbors(placement: PKPlacement) -> void:
	var area := placement.get_box().get_aabb().grow(maxf(grid_cell_size.x, grid_cell_size.y) * 0.6)
	for other in builder.layout.near(area):
		if other.buildable != null and other.buildable.has_variants():
			_update_variant(other)
		var node: Node2D = _nodes.get(other.uid)
		if node != null and node.has_method(&"pk_neighbors_changed"):
			node.call(&"pk_neighbors_changed", self)


## Autotiling: shows the scene of the shape the neighbours make (see [PKAutotile]).
func _update_variant(placement: PKPlacement) -> void:
	var holder: Node2D = _nodes.get(placement.uid)
	if holder == null:
		return
	var buildable := placement.buildable
	var step := minf(grid_cell_size.x, grid_cell_size.y) * maxf(buildable.cells.x, 1)
	var shape := PKAutotile.shape_of(PKAutotile.mask_of(builder.layout, placement, buildable.autotile_tag, step))
	var key := "%s_%d" % [shape.shape, int(shape.angle)]
	if _variants.get(placement.uid, "") == key:
		return
	_variants[placement.uid] = key
	for child in holder.get_children():
		child.queue_free()
	var scene: PackedScene = buildable.variant_scenes.get(shape.shape, buildable.scene)
	var visual: Node2D = scene.instantiate() if scene != null else _instantiate(buildable)
	visual.rotation_degrees = shape.angle - placement.angle
	holder.add_child(visual)


## The variant shape shown for [param uid] ("straight", "corner"... or "" when not autotiled).
func get_variant(uid: int) -> String:
	return String(_variants.get(uid, "")).get_slice("_", 0)


func _instantiate(buildable: PKBuildable) -> Node2D:
	if buildable != null and buildable.scene != null:
		var instance := buildable.scene.instantiate()
		if instance is Node2D:
			return instance
		instance.free()
	var box := _BoxPiece.new()
	var placement := PKPlacement.make(buildable)
	placement.cell_size = builder.grid.cell_size
	var size := placement.get_size()
	box.size = Vector2(size.x, size.z)
	box.color = buildable.color if buildable != null else Color.GRAY
	return box


func _pop(node: Node2D) -> void:
	var size := node.scale
	node.scale = size * 0.8
	var tween := node.create_tween()
	tween.tween_property(node, "scale", size * 1.08, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", size, 0.1)


func _dust(placement: PKPlacement) -> void:
	if not is_inside_tree():
		return
	var box := placement.get_box()
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = 24
	particles.lifetime = 0.7
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(box.half.x, box.half.z)
	particles.spread = 180.0
	particles.initial_velocity_min = 20.0
	particles.initial_velocity_max = 70.0
	particles.gravity = Vector2.ZERO
	particles.damping_min = 40.0
	particles.damping_max = 80.0
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 7.0
	var fade := Gradient.new()
	fade.set_color(0, dust_color)
	fade.set_color(1, Color(dust_color, 0.0))
	particles.color_ramp = fade
	particles.z_index = 8
	add_child(particles)
	particles.position = to_2d(box.center)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


# --- Levels ------------------------------------------------------------------------------

func _level_of(placement: PKPlacement) -> int:
	return roundi(placement.position.y / maxf(builder.grid.cell_size.y, 0.0001))


func _piece_on_level(point: Vector3) -> PKPlacement:
	if max_level <= 0:
		return builder.layout.piece_at_plane(point)
	var best: PKPlacement = null
	var probe := AABB(Vector3(point.x, -100000.0, point.z) - Vector3(0.01, 0, 0.01), Vector3(0.02, 200000.0, 0.02))
	for placement in builder.layout.near(probe):
		if _level_of(placement) == controller.level and placement.get_box().has_point(Vector3(point.x, placement.get_box().center.y, point.z)):
			if best == null or placement.buildable.layer > best.buildable.layer:
				best = placement
	return best


func _apply_level_visibility() -> void:
	for uid in _nodes:
		var placement := builder.layout.get_piece(uid)
		if placement != null:
			_apply_level_to(placement, _nodes[uid])


func _apply_level_to(placement: PKPlacement, node: Node2D) -> void:
	if max_level <= 0:
		return
	var level := _level_of(placement)
	node.visible = placement.uid != controller.moving_uid and (level == controller.level or (show_lower_levels and level < controller.level))
	node.self_modulate = Color(1, 1, 1, 0.35) if level < controller.level else Color.WHITE


# --- Ghosts and highlights ---------------------------------------------------------------

func _draw_ghosts() -> void:
	var previews: Array[PKPreview] = []
	if controller.drag != null:
		previews = controller.drag.previews
	elif controller.preview != null:
		previews = [controller.preview]
	var used := 0
	var boxes := []
	for preview in previews:
		if preview.get_buildable() == null:
			continue
		var ghost := _ghost_for(preview.get_buildable(), used)
		used += 1
		_pose(ghost, preview.placement)
		ghost.visible = true
		var color := ghost_color(preview)
		(ghost.material as ShaderMaterial).set_shader_parameter(&"tint", color)
		boxes.append([_corners(preview.placement), color])
	for i in range(used, _ghosts.size()):
		_ghosts[i].node.visible = false
	_overlay.boxes = boxes
	_refresh_influence()
	_overlay.queue_redraw()


## Ghost colour: red when refused, green when valid, towards amber when barely stable.
func ghost_color(preview: PKPreview) -> Color:
	if not preview.valid:
		return invalid_color
	if not builder.stability_enabled:
		return valid_color
	var low := builder.min_stability
	return weak_color.lerp(valid_color, clampf((preview.placement.stability - low) / maxf(1.0 - low, 0.001), 0.0, 1.0))


## Areas around the pieces this one must be near (a house within N cells of a road...).
func _refresh_influence() -> void:
	var areas := []
	var piece := controller.get_active_buildable()
	if show_influence and piece != null and controller.mode == PKBuildController.Mode.BUILD:
		var unit := minf(grid_cell_size.x, grid_cell_size.y)
		var view := Rect2(cursor_position - Vector2(900, 700), Vector2(1800, 1400))
		var area := AABB(Vector3(view.position.x, -100000.0, view.position.y), Vector3(view.size.x, 200000.0, view.size.y))
		for requirement in PKNearbyRule.requirements_of(piece):
			if int(requirement.cells) <= 1:
				continue  # "touching" needs no area drawn
			var reach: float = (int(requirement.cells) - 1) * unit + unit * 0.5
			for other in builder.layout.near(area):
				if other.buildable != null and other.buildable.has_tag(requirement.tag):
					var aabb := other.get_box().get_aabb().grow(reach)
					areas.append([Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z), influence_color])
	_overlay.areas = areas


func _ghost_for(buildable: PKBuildable, index: int) -> Node2D:
	var id := buildable.id if buildable != null else &""
	if index < _ghosts.size() and _ghosts[index].id == id:
		return _ghosts[index].node
	var source: PackedScene = buildable.variant_scenes.get("single", buildable.scene) if buildable.has_variants() else buildable.scene
	var node: Node2D
	if source != null:
		var instance := source.instantiate()
		if instance is Node2D:
			node = instance
		else:
			instance.free()
			node = _instantiate(buildable)
	else:
		node = _instantiate(buildable)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	var material := ShaderMaterial.new()
	material.shader = _ghost_shader()
	node.material = material
	_share_material(node)
	if index < _ghosts.size():
		_ghosts[index].node.queue_free()
		_ghosts[index] = {"id": id, "node": node}
	else:
		_ghosts.append({"id": id, "node": node})
	_ghost_root.add_child(node)
	return node


func _share_material(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			child.use_parent_material = true
		_share_material(child)


func _ghost_shader() -> Shader:
	if _materials.has(&"shader"):
		return _materials[&"shader"]
	var shader := Shader.new()
	shader.code = GHOST_SHADER
	_materials[&"shader"] = shader
	return shader


func _refresh_overlays() -> void:
	var wanted := {}
	for uid in controller.get_selection():
		wanted[uid] = select_color
	if controller.mode == PKBuildController.Mode.REPAIR:
		for placement in builder.layout.get_all():
			if placement.is_damaged():
				wanted[placement.uid] = Color(repair_color, 0.3)
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
				wanted[controller.hover_uid] = upgrade_color if builder.can_upgrade(controller.hover_uid).is_empty() else Color(invalid_color, 0.3)
			PKBuildController.Mode.REPAIR:
				wanted[controller.hover_uid] = repair_color
	# Only the pieces that change are touched (not the whole city).
	for uid in _tinted.keys():
		if not wanted.has(uid) and _nodes.has(uid):
			_nodes[uid].modulate = Color.WHITE
	_tinted.clear()
	var highlights := []
	for uid in wanted:
		if _nodes.has(uid):
			_nodes[uid].modulate = Color.WHITE.lerp(Color(wanted[uid], 1.0), 0.45)
			_tinted[uid] = true
			highlights.append([_corners(builder.layout.get_piece(uid)), wanted[uid]])
	_overlay.highlights = highlights
	_overlay.queue_redraw()


func _corners(placement: PKPlacement) -> PackedVector2Array:
	var box := placement.get_box()
	var center := to_2d(box.center)
	var x := to_2d(box.basis.x) * box.half.x
	var z := to_2d(box.basis.z) * box.half.z
	return PackedVector2Array([center - x - z, center + x - z, center + x + z, center - x + z])


# --- Grid --------------------------------------------------------------------------------

func _apply_grid() -> void:
	var size := grid_cell_size
	var origin := grid_origin
	if tile_map != null and tile_map.tile_set != null:
		size = Vector2(tile_map.tile_set.tile_size)
		origin = to_local(tile_map.to_global(Vector2.ZERO))
		builder.zone_provider = _tile_zone
	grid_cell_size = size
	var grid := PKGrid.make(Vector3(size.x, 1.0, size.y), to_core(origin))
	grid.bounds = bounds
	builder.grid = grid


func _tile_zone(position: Vector3, _cell: Vector3i) -> StringName:
	if tile_map == null:
		return &""
	var map_cell := tile_map.local_to_map(tile_map.to_local(to_global(to_2d(position))))
	var data := tile_map.get_cell_tile_data(map_cell)
	if data == null:
		return &"empty"
	if tile_map.tile_set.has_custom_data_layer_by_name(zone_layer_name):
		return StringName(str(data.get_custom_data(zone_layer_name)))
	return &""


func _draw_grid(canvas: Node2D) -> void:
	var buildable := controller.get_active_buildable()
	if not show_grid or buildable == null or not buildable.uses(PKBuildable.Snap.GRID):
		return
	var cell := grid_cell_size
	var center := cursor_position
	var reach := 6
	var origin := to_2d(builder.grid.origin)
	var base := Vector2(floorf((center.x - origin.x) / cell.x), floorf((center.y - origin.y) / cell.y))
	for i in range(-reach, reach + 2):
		var x := origin.x + (base.x + i) * cell.x
		var y := origin.y + (base.y + i) * cell.y
		var fade := 1.0 - absf(float(i) - 0.5) / float(reach + 1)
		var color := Color(grid_color, grid_color.a * fade)
		canvas.draw_line(Vector2(x, origin.y + (base.y - reach) * cell.y), Vector2(x, origin.y + (base.y + reach + 1) * cell.y), color, 1.0)
		canvas.draw_line(Vector2(origin.x + (base.x - reach) * cell.x, y), Vector2(origin.x + (base.x + reach + 1) * cell.x, y), color, 1.0)
	if bounds.size != Vector2i.ZERO:
		var rect := Rect2(origin + Vector2(bounds.position) * cell, Vector2(bounds.size) * cell)
		canvas.draw_rect(rect, Color(grid_color, 0.5), false, 2.0)


const GHOST_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.3, 1.0, 0.45, 0.6);
void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(base.rgb, tint.rgb, 0.55), base.a * tint.a);
}
"""
