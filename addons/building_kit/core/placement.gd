class_name PKPlacement
extends RefCounted
## One piece in the world (placed), or a proposed pose for one (the ghost).
##
## Positions use 3D coordinates even in 2D: X and Z are the ground plane (2D X and Y), Y is
## up. [member angle] is in degrees, clockwise seen from above (2D [code]rotation_degrees[/code];
## the 3D node uses [code]rotation.y = -deg_to_rad(angle)[/code]).

## Unique number of a placed piece (0 = not placed yet).
var uid := 0
var buildable: PKBuildable
## Kept apart from [member buildable] so saves of removed pieces stay readable.
var buildable_id: StringName = &""
## Origin of the piece: centre of its footprint, on the ground.
var position := Vector3.ZERO
var angle := 0.0
var flipped := false
## Up direction of the piece (the surface normal when it is aligned to it).
var up := Vector3.UP
## Grid cell of the footprint's first corner, when placed on the grid.
var cell := Vector3i.ZERO
var on_grid := false
## Uid of the piece whose socket this one snapped to (0 = none).
var parent_uid := 0
## Uids of the pieces this one rests on or hangs from.
var supports: Array[int] = []
## True when it stands on the ground / terrain (it does not fall when supports go).
var grounded := true
## What was really paid for it, {item_id: amount}: refunds are based on it.
var paid: Dictionary = {}
## Stability from 0 to 1 (computed by the builder, see [member PKBuilder.stability_enabled]).
var stability := 1.0
## Hit points left (-1 = full, see [member PKBuildable.max_health]).
var health := -1.0
## Your own data, saved with the piece.
var data: Dictionary = {}
## Size of a cell of the grid it was laid out with (to size the box). Set by the builder.
var cell_size := Vector3.ONE


static func make(p_buildable: PKBuildable, p_position := Vector3.ZERO, p_angle := 0.0, p_flipped := false) -> PKPlacement:
	var placement := PKPlacement.new()
	placement.buildable = p_buildable
	placement.buildable_id = p_buildable.id if p_buildable != null else &""
	placement.position = p_position
	placement.angle = p_angle
	placement.flipped = p_flipped
	return placement


func duplicate_pose() -> PKPlacement:
	var copy := PKPlacement.new()
	copy.uid = uid
	copy.buildable = buildable
	copy.buildable_id = buildable_id
	copy.position = position
	copy.angle = angle
	copy.flipped = flipped
	copy.up = up
	copy.cell = cell
	copy.on_grid = on_grid
	copy.parent_uid = parent_uid
	copy.supports = supports.duplicate()
	copy.grounded = grounded
	copy.paid = paid.duplicate()
	copy.data = data.duplicate(true)
	copy.cell_size = cell_size
	copy.stability = stability
	copy.health = health
	return copy


## The rotation of the piece, without the flip.
func get_basis() -> Basis:
	var yaw := Basis(Vector3.UP, -deg_to_rad(angle))
	var normal := up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	if normal.is_equal_approx(Vector3.UP):
		return yaw
	if normal.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI) * yaw
	if absf(normal.y) < 0.7:
		# On a wall: local Y along the normal, local -Z towards the sky (a painting stays upright).
		var up_on_wall := (Vector3.UP - normal * normal.dot(Vector3.UP)).normalized()
		var z := -up_on_wall
		var x := normal.cross(z)
		return Basis(x, normal, z) * yaw
	return Basis(Quaternion(Vector3.UP, normal)) * yaw


## Full transform for a 3D node (the flip mirrors local X).
func get_transform() -> Transform3D:
	var basis := get_basis()
	if flipped:
		basis = basis * Basis.from_scale(Vector3(-1, 1, 1))
	return Transform3D(basis, position)


## World size of the box of this piece (see [member PKBuildable.size]).
func get_size() -> Vector3:
	if buildable == null:
		return Vector3.ONE
	if buildable.size != Vector3.ZERO:
		return buildable.size
	var height := buildable.height if buildable.height > 0.0 else cell_size.y
	return Vector3(buildable.cells.x * cell_size.x, height, buildable.cells.y * cell_size.z)


func get_box() -> PKBox:
	var basis := get_basis()
	var offset := Vector3(0, get_size().y * 0.5, 0)
	if buildable != null:
		var box_offset := buildable.box_offset
		if flipped:
			box_offset.x = -box_offset.x
		offset += box_offset
	return PKBox.make(position + basis * offset, get_size() * 0.5, basis)


## A point of the piece (local, Y up, Z forward) in world space.
func to_world(local: Vector3) -> Vector3:
	if flipped:
		local.x = -local.x
	return position + get_basis() * local


## Facing of a local angle in world degrees.
func world_angle(local_angle: float) -> float:
	return wrapf(angle + (-local_angle if flipped else local_angle), 0.0, 360.0)


## Top of the box (where pieces on top stand).
func get_top() -> float:
	var aabb := get_box().get_aabb()
	return aabb.end.y


## Hit points now (the maximum when undamaged, 0 for pieces without health).
func get_health() -> float:
	if buildable == null or buildable.max_health <= 0.0:
		return 0.0
	return buildable.max_health if health < 0.0 else health


func is_damaged() -> bool:
	return buildable != null and buildable.max_health > 0.0 and health >= 0.0 and health < buildable.max_health


func get_title() -> String:
	return buildable.get_title() if buildable != null else String(buildable_id)


func to_dict() -> Dictionary:
	var entry := {
		"uid": uid,
		"id": String(buildable_id),
		"pos": [position.x, position.y, position.z],
		"angle": angle,
	}
	if flipped:
		entry["flip"] = true
	if not up.is_equal_approx(Vector3.UP):
		entry["up"] = [up.x, up.y, up.z]
	if on_grid:
		entry["cell"] = [cell.x, cell.y, cell.z]
	if parent_uid != 0:
		entry["parent"] = parent_uid
	if not supports.is_empty():
		entry["supports"] = Array(supports)
	if not grounded:
		entry["grounded"] = false
	if not paid.is_empty():
		var paid_out := {}
		for item_id in paid:
			paid_out[String(item_id)] = int(paid[item_id])
		entry["paid"] = paid_out
	if health >= 0.0:
		entry["hp"] = health
	if not data.is_empty():
		entry["data"] = data.duplicate(true)
	return entry


static func from_dict(entry: Dictionary) -> PKPlacement:
	var placement := PKPlacement.new()
	placement.uid = int(entry.get("uid", 0))
	placement.buildable_id = StringName(str(entry.get("id", "")))
	placement.position = _vector(entry.get("pos", []), Vector3.ZERO)
	placement.angle = float(entry.get("angle", 0.0))
	placement.flipped = bool(entry.get("flip", false))
	placement.up = _vector(entry.get("up", []), Vector3.UP)
	if entry.has("cell"):
		var cell_values: Vector3 = _vector(entry.cell, Vector3.ZERO)
		placement.cell = Vector3i(roundi(cell_values.x), roundi(cell_values.y), roundi(cell_values.z))
		placement.on_grid = true
	placement.parent_uid = int(entry.get("parent", 0))
	for support in entry.get("supports", []):
		placement.supports.append(int(support))
	placement.grounded = bool(entry.get("grounded", true))
	var paid_in: Variant = entry.get("paid", {})
	if paid_in is Dictionary:
		for item_id in paid_in:
			placement.paid[StringName(str(item_id))] = int(paid_in[item_id])
	placement.health = float(entry.get("hp", -1.0))
	var data_in: Variant = entry.get("data", {})
	if data_in is Dictionary:
		placement.data = data_in.duplicate(true)
	return placement


static func _vector(values: Variant, fallback: Vector3) -> Vector3:
	if values is Array and values.size() >= 3:
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return fallback
