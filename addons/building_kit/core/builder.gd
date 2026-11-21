class_name PKBuilder
extends RefCounted
## The building system without any node: snapping, rules, costs, demolition, undo, saves.
## [PKBuildSystem2D] and [PKBuildSystem3D] wrap one; you can also drive it from code
## (tests, bots, level scripts, a server).
## [codeblock]
## var builder := PKBuilder.new(catalog)
## builder.grid = PKGrid.make(Vector3(2, 3, 2))
## builder.cost_handler = PKInventoryCost.make([bag])
## var preview := builder.preview(catalog.get_buildable(&"foundation"), PKAim.at(Vector3(3, 0, 1)))
## if preview.valid:
##     builder.place(preview)
## builder.undo()
## var save := builder.to_data()   # JSON-friendly
## [/codeblock]
## Every action emits a signal ([signal placed], [signal removed], [signal moved]) or
## [signal rejected] with the reason.

## A piece was built (also when an undo puts a demolished piece back).
signal placed(placement: PKPlacement)
## A piece was demolished or undone; [param refund] is what the player got back for it.
signal removed(placement: PKPlacement, refund: Dictionary)
## A piece was moved; [param from] holds its old pose.
signal moved(placement: PKPlacement, from: PKPlacement)
## An action was refused (see [method PKText.reason]).
signal rejected(reason: StringName, buildable: PKBuildable)
## [method undo] reverted an action ("place", "remove" or "move").
signal undone(action: String)
## The layout was replaced by [method load_data] or [method clear].
signal reset
## Items of a refund that did not fit ([member refund_overflow] on): drop them in the world.
signal refund_left_behind(items: Dictionary, position: Vector3)
## A piece was upgraded in place ([method upgrade]), or the upgrade was undone.
signal upgraded(placement: PKPlacement, from: PKBuildable)
## A piece took damage ([method damage]).
signal damaged(placement: PKPlacement, amount: float)
## A piece was destroyed by damage, or collapsed with it; [param items] is what it left
## (destroy refund and loot). [signal removed] is emitted too.
signal destroyed(placement: PKPlacement, items: Dictionary)
## A damaged piece was repaired for [param cost].
signal repaired(placement: PKPlacement, cost: Dictionary)

const SAVE_FORMAT := "building_kit"
## Version of the save format written by [method to_data].
const SAVE_VERSION := 1

var catalog: PKCatalog
var layout := PKLayout.new()
var grid := PKGrid.new()
## Rules checked for every piece, in order (the first refusal wins). Built-in rules read
## their settings on the buildables; add your own or remove some.
var rules: Array[PKPlacementRule] = [
	PKBoundsRule.new(), PKZoneRule.new(), PKSlopeRule.new(), PKSurfaceRule.new(),
	PKSupportRule.new(), PKStabilityRule.new(), PKOverlapRule.new(), PKLimitRule.new(), PKNearbyRule.new(),
]
## Who pays. The default builds for free.
var cost_handler: PKCost = PKCost.new()
## func(position: Vector3, cell: Vector3i) -> StringName: the zone at a point (water,
## grass, town...). Set by the build nodes from a TileMapLayer or a GridMap.
var zone_provider: Callable
## func(point: Vector3) -> Dictionary: the ground under a point,
## {"position": Vector3, "normal": Vector3, "uid": int} or {} (used by drags in 3D).
var ground_provider: Callable
## Pieces must stay inside this box (size 0 = anywhere).
var world_bounds := AABB()
## How far from the cursor sockets are looked for, in world units.
var socket_radius := 0.9
## Rotation step when a piece does not set one (degrees).
var default_rotation_step := 90.0
## Free placement snaps positions to this step (0 = no snapping).
var surface_snap := 0.0
## Demolishing a piece also demolishes what rests on it (off: refused with "supports_others").
var demolish_cascade := true
## Refunds that do not fit are partly given and reported by [signal refund_left_behind]
## (off: the demolition is refused with "no_room", so nothing is ever lost).
var refund_overflow := false
## Most actions kept for [method undo].
var undo_limit := 64
## Most pieces in one drag.
var max_drag_pieces := 256
## Keep the saved pieces whose buildable no longer exists and write them back on save.
var keep_unknown_pieces := true
## Structural integrity (Valheim / Rust style): every piece gets a stability from the ground
## up ([member PKBuildable.strength], [member PKBuildable.stability_loss]); pieces under
## [member min_stability] are refused, and demolishing a support brings down what becomes
## too weak. Off: pieces only need something to rest on.
var stability_enabled := false
var min_stability := 0.1

var _undo: Array[Dictionary] = []
var _unknown_entries: Array = []


func _init(p_catalog: PKCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else PKCatalog.new()


# --- Asking -------------------------------------------------------------------------------

## Rotation step of [param buildable] in degrees.
func rotation_step_of(buildable: PKBuildable) -> float:
	if buildable == null or not buildable.can_rotate:
		return 0.0
	return buildable.rotation_step if buildable.rotation_step > 0.0 else default_rotation_step


## The zone at a point ("" without [member zone_provider]).
func zone_at(position: Vector3, cell := Vector3i.ZERO) -> StringName:
	return StringName(zone_provider.call(position, cell)) if zone_provider.is_valid() else &""


## Zones under a piece: one per cell on a grid, the centre otherwise.
func zones_under(placement: PKPlacement) -> Array[StringName]:
	var zones: Array[StringName] = []
	if placement.on_grid and grid != null:
		for cell in grid.footprint(placement.cell, placement.buildable, placement.angle):
			var center := grid.cell_center(cell)
			# The real height of the piece (the grid only snaps heights when asked to).
			center.y = placement.position.y
			zones.append(zone_at(center, cell))
	else:
		var cell := grid.cell_of(placement.position) if grid != null else Vector3i.ZERO
		zones.append(zone_at(placement.position, cell))
	return zones


## What demolishing [param uid] gives back (with what rests on it when cascading).
func refund_for(uid: int) -> Dictionary:
	var total := {}
	for placement in _removal_set(uid):
		total = PKBuildable.add_costs(total, PKBuildable.refund_of(placement.paid, placement.buildable.refund_percent if placement.buildable != null else 100.0))
	return total


func can_afford(buildable: PKBuildable, times := 1) -> bool:
	if buildable == null:
		return false
	return cost_handler.can_pay(PKBuildable.add_costs({}, buildable.cost, times))


## Pieces that would fall if [param uid] went away (not including it).
func dependents_of(uid: int) -> Array[PKPlacement]:
	var removal := _removal_set(uid)
	removal.pop_back()
	return removal


func can_undo() -> bool:
	return not _undo.is_empty()


## Kind of the action [method undo] would revert ("" when none).
func last_action() -> String:
	return _undo.back().type if not _undo.is_empty() else ""


func clear_undo() -> void:
	_undo.clear()


# --- Previews -----------------------------------------------------------------------------

## Where [param buildable] would go for [param aim], and whether it may be built.
## [param angle] is the player's rotation (degrees), [param ignore] uids the checks skip
## (the piece being moved). Tries sockets, then the grid, then the surface.
func preview(buildable: PKBuildable, aim: PKAim, angle := 0.0, flipped := false, ignore: Array = [], tilt := Vector3.UP) -> PKPreview:
	var result := PKPreview.new()
	result.ignore = ignore
	if buildable == null:
		result.placement = PKPlacement.new()
		result.reason = &"no_buildable"
		return result
	flipped = flipped and buildable.can_flip
	if not buildable.can_rotate:
		angle = 0.0
	var placement := PKPlacement.make(buildable, aim.position, angle, flipped)
	placement.cell_size = grid.cell_size if grid != null else Vector3.ONE
	result.placement = placement
	result.cost = buildable.cost.duplicate()
	result.normal = aim.normal if aim.has_hit else Vector3.UP
	if not aim.has_hit:
		result.reason = &"no_surface"
		return result

	if buildable.uses(PKBuildable.Snap.SOCKET) and _try_sockets(result, buildable, aim, angle, flipped, ignore):
		return result
	if buildable.uses(PKBuildable.Snap.GRID) and grid != null:
		var snapped := grid.snap(aim.position, buildable, angle)
		placement.position = snapped.position
		placement.cell = snapped.cell
		placement.on_grid = true
		placement.angle = _grid_angle(buildable, angle)
		placement.up = tilt
	elif buildable.uses(PKBuildable.Snap.SURFACE):
		placement.position = aim.position
		if surface_snap > 0.0:
			placement.position = Vector3(snappedf(aim.position.x, surface_snap), aim.position.y, snappedf(aim.position.z, surface_snap))
		placement.up = aim.normal if buildable.align_to_normal else tilt
	else:
		result.reason = &"no_socket"
		return result
	_set_support(placement, aim.hit_uid, ignore)
	placement.stability = stability_of(placement)
	result.reason = check(placement, result.normal, false, ignore)
	result.valid = result.reason.is_empty()
	return result


## Runs every rule and the cost on a proposed pose. Returns "" when it may be built.
func check(placement: PKPlacement, normal := Vector3.UP, snapped_to_socket := false, ignore: Array = [],
		batch: Array[PKPlacement] = [], check_cost := true) -> StringName:
	var context := PKPlacementContext.new()
	context.builder = self
	context.buildable = placement.buildable
	context.placement = placement
	context.normal = normal
	context.snapped_to_socket = snapped_to_socket
	context.ignore = ignore
	context.batch = batch
	for rule in rules:
		if rule != null and rule.enabled:
			var refused := rule.check(context)
			if not refused.is_empty():
				return refused
	for rule in placement.buildable.rules:
		if rule != null and rule.enabled:
			var refused := rule.check(context)
			if not refused.is_empty():
				return refused
	if check_cost and not cost_handler.can_pay(placement.buildable.cost):
		return &"cannot_afford"
	return &""


## Pieces along a drag from [param from] to [param to] ([member PKBuildable.drag]), on the grid.
func drag_preview(buildable: PKBuildable, from: PKAim, to: PKAim, angle := 0.0, flipped := false) -> PKDragPreview:
	var drag := PKDragPreview.new()
	drag.buildable = buildable
	if buildable == null or grid == null:
		return drag
	if buildable.drag == PKBuildable.Drag.NONE:
		drag.previews.append(preview(buildable, to, angle, flipped))
		return _finish_drag(drag)
	var poses := _drag_poses(buildable, from.position, to.position, angle)
	var batch: Array[PKPlacement] = []
	var running := {}
	for pose in poses:
		var item := PKPreview.new()
		var placement := PKPlacement.make(buildable, pose.position, pose.angle, flipped and buildable.can_flip)
		placement.cell_size = grid.cell_size
		placement.cell = pose.cell
		placement.on_grid = true
		item.placement = placement
		item.cost = buildable.cost.duplicate()
		var hit_uid := from.hit_uid
		if ground_provider.is_valid():
			var ground: Dictionary = ground_provider.call(placement.position)
			if ground.is_empty():
				item.reason = &"no_surface"
				drag.previews.append(item)
				continue
			placement.position.y = ground.position.y if not grid.snap_height else placement.position.y
			item.normal = ground.get("normal", Vector3.UP)
			hit_uid = int(ground.get("uid", 0))
		else:
			placement.position.y = from.position.y if not grid.snap_height else placement.position.y
			item.normal = from.normal
		_set_support(placement, hit_uid, [], batch)
		placement.stability = stability_of(placement, batch)
		item.reason = check(placement, item.normal, false, [], batch, false)
		if item.reason.is_empty():
			var next := PKBuildable.add_costs(running, buildable.cost)
			if cost_handler.can_pay(next):
				running = next
			else:
				item.reason = &"cannot_afford"
				drag.affordable = false
		item.valid = item.reason.is_empty()
		if item.valid:
			batch.append(placement)
		drag.previews.append(item)
	return _finish_drag(drag)


# --- Actions ------------------------------------------------------------------------------

## Builds the piece of [param preview] (checked again first). Pays its cost.
func place(preview_or_placement: Variant, normal := Vector3.UP) -> PKResult:
	var placement: PKPlacement
	var snapped := false
	var ignore: Array = []
	if preview_or_placement is PKPreview:
		placement = preview_or_placement.placement
		normal = preview_or_placement.normal
		snapped = preview_or_placement.snapped_to_socket
		ignore = preview_or_placement.ignore
	else:
		placement = preview_or_placement
	if placement == null or placement.buildable == null:
		return _refuse(&"no_buildable", null)
	var reason := check(placement, normal, snapped, ignore)
	if not reason.is_empty():
		return _refuse(reason, placement.buildable)
	if not cost_handler.pay(placement.buildable.cost):
		return _refuse(&"cannot_afford", placement.buildable)
	var piece := placement.duplicate_pose()
	piece.uid = 0
	piece.paid = {} if cost_handler.is_free() else placement.buildable.cost.duplicate()
	layout.add(piece)
	piece.stability = stability_of(piece)
	_push({"type": "place", "pieces": [piece.duplicate_pose()]})
	placed.emit(piece)
	var result := PKResult.success([piece])
	result.cost = piece.paid.duplicate()
	return result


## Builds [param buildable] at [param position] (snapped like the cursor would be).
func place_at(buildable: PKBuildable, position: Vector3, angle := 0.0, flipped := false, normal := Vector3.UP, hit_uid := 0) -> PKResult:
	var proposed := preview(buildable, PKAim.at(position, normal, hit_uid), angle, flipped)
	if not proposed.valid:
		return _refuse(proposed.reason, buildable)
	return place(proposed)


## Builds every valid piece of a drag, paying for all of them at once (or none).
## One undo step.
func place_many(drag: PKDragPreview) -> PKResult:
	if drag == null or drag.buildable == null:
		return _refuse(&"no_buildable", null)
	if drag.previews.size() > max_drag_pieces:
		return _refuse(&"too_many", drag.buildable)
	var batch: Array[PKPlacement] = []
	var total := {}
	var first_reason: StringName = &""
	for item in drag.previews:
		if not item.valid:
			if first_reason.is_empty():
				first_reason = item.reason
			continue
		var reason := check(item.placement, item.normal, item.snapped_to_socket, item.ignore, batch, false)
		if reason.is_empty():
			batch.append(item.placement)
			total = PKBuildable.add_costs(total, item.placement.buildable.cost)
		elif first_reason.is_empty():
			first_reason = reason
	if batch.is_empty():
		return _refuse(first_reason if not first_reason.is_empty() else &"overlap", drag.buildable)
	if not cost_handler.pay(total):
		return _refuse(&"cannot_afford", drag.buildable)
	var pieces: Array[PKPlacement] = []
	var undo_pieces := []
	var new_uids := {}  # temporary (negative) uids of blueprint pieces -> real ones
	for placement in batch:
		var piece := placement.duplicate_pose()
		piece.uid = 0
		piece.paid = {} if cost_handler.is_free() else piece.buildable.cost.duplicate()
		var supports: Array[int] = []
		for support in piece.supports:
			var real: int = new_uids.get(support, support)
			if layout.has(real):
				supports.append(real)
		piece.supports = supports
		var parent: int = new_uids.get(piece.parent_uid, piece.parent_uid)
		piece.parent_uid = parent if layout.has(parent) else 0
		if supports.is_empty() and not placement.grounded and placement.supports.any(func(uid: int) -> bool: return uid < 0):
			piece.grounded = true
		layout.add(piece)
		if placement.uid < 0:
			new_uids[placement.uid] = piece.uid
		piece.stability = stability_of(piece)
		pieces.append(piece)
		undo_pieces.append(piece.duplicate_pose())
	_push({"type": "place", "pieces": undo_pieces})
	for piece in pieces:
		placed.emit(piece)
	var result := PKResult.success(pieces)
	result.cost = {} if cost_handler.is_free() else total
	return result


## Demolishes a piece, giving back [member PKBuildable.refund_percent] of what was paid
## (or [param refund_percent] when 0 or more). With [member demolish_cascade], what rests on
## it comes down too.
func remove(uid: int, refund_percent := -1.0) -> PKResult:
	var target := layout.get_piece(uid)
	if target == null:
		return _refuse(&"not_found", null)
	var pieces := _removal_set(uid)
	if pieces.size() > 1 and not demolish_cascade:
		return _refuse(&"supports_others", target.buildable)
	var refunds := {}
	var total := {}
	for piece in pieces:
		var percent := refund_percent if refund_percent >= 0.0 else (piece.buildable.refund_percent if piece.buildable != null else 100.0)
		refunds[piece.uid] = PKBuildable.refund_of(piece.paid, percent)
		total = PKBuildable.add_costs(total, refunds[piece.uid])
	var left := {}
	if refund_overflow:
		left = cost_handler.refund_partial(total)
	elif not cost_handler.refund(total):
		return _refuse(&"no_room", target.buildable)
	var undo_pieces := []
	for piece in pieces:
		layout.remove(piece.uid)
		undo_pieces.append(piece.duplicate_pose())
	_apply_weakened()
	_push({"type": "remove", "pieces": undo_pieces, "refund": _given(total, left)})
	for piece in pieces:
		removed.emit(piece, refunds[piece.uid])
	if not left.is_empty():
		refund_left_behind.emit(left, target.position)
	var result := PKResult.success(pieces)
	result.refund = _given(total, left)
	result.left_behind = left
	return result


## Moves a placed piece to the pose of [param preview] (made with [code]ignore = [uid][/code]).
## Free of charge. Pieces that hold others up cannot move.
func move(uid: int, preview: PKPreview) -> PKResult:
	var piece := layout.get_piece(uid)
	if piece == null:
		return _refuse(&"not_found", null)
	if not layout.resting_on(uid).is_empty():
		return _refuse(&"supports_others", piece.buildable)
	var proposed := preview.placement
	var ignore := preview.ignore.duplicate()
	if not ignore.has(uid):
		ignore.append(uid)
	var reason := check(proposed, preview.normal, preview.snapped_to_socket, ignore, [], false)
	if not reason.is_empty():
		return _refuse(reason, piece.buildable)
	var from := piece.duplicate_pose()
	_apply_pose(piece, proposed)
	layout.refresh(uid)
	piece.stability = stability_of(piece)
	_push({"type": "move", "from": from, "to": piece.duplicate_pose()})
	moved.emit(piece, from)
	return PKResult.success([piece])


## Reverts the last action: a build is taken down with a full refund, a demolition is put
## back (taking back what it refunded), a move goes back.
func undo() -> PKResult:
	# Actions whose pieces are gone (destroyed by damage, cleared) are skipped.
	while not _undo.is_empty():
		var action: Dictionary = _undo.back()
		if action.type != "remove" and not _undo_target_exists(action):
			_undo.pop_back()
			continue
		var result: PKResult
		match action.type:
			"place":
				result = _undo_place(action)
			"remove":
				result = _undo_remove(action)
			"move":
				result = _undo_move(action)
			"upgrade":
				result = _undo_upgrade(action)
		if result.ok:
			_undo.pop_back()
			undone.emit(action.type)
		return result
	return _refuse(&"nothing_to_undo", null)


func _undo_target_exists(action: Dictionary) -> bool:
	match action.type:
		"place":
			return action.pieces.any(func(piece: PKPlacement) -> bool: return layout.has(piece.uid))
		"move":
			return layout.has((action.from as PKPlacement).uid)
		"upgrade":
			return layout.has(int(action.uid))
	return true


## Removes every piece without refunds (a new game). Clears undo.
func clear() -> void:
	layout.clear()
	_undo.clear()
	_unknown_entries.clear()
	reset.emit()


# --- Upgrades, health, blueprints ---------------------------------------------------------

## Why [param uid] cannot be upgraded now ("" when it can).
func can_upgrade(uid: int) -> StringName:
	var piece := layout.get_piece(uid)
	if piece == null:
		return &"not_found"
	if piece.buildable == null or piece.buildable.upgrade_to == null:
		return &"no_upgrade"
	var target := piece.buildable.upgrade_to
	var proposed := piece.duplicate_pose()
	proposed.buildable = target
	proposed.buildable_id = target.id
	var box := proposed.get_box().grown(-0.02)
	if not layout.overlapping(box, target.layer, [uid] + layout.dependents_of(uid)).is_empty():
		return &"overlap"
	if not cost_handler.can_pay(piece.buildable.get_upgrade_cost()):
		return &"cannot_afford"
	return &""


## Turns a placed piece into [member PKBuildable.upgrade_to] where it stands (same uid,
## pose, sockets and what rests on it), for [method PKBuildable.get_upgrade_cost].
## Undo gives the cost back.
func upgrade(uid: int) -> PKResult:
	var piece := layout.get_piece(uid)
	if piece == null:
		return _refuse(&"not_found", null)
	var reason := can_upgrade(uid)
	if not reason.is_empty():
		return _refuse(reason, piece.buildable)
	var from := piece.buildable
	var cost := from.get_upgrade_cost()
	if not cost_handler.pay(cost):
		return _refuse(&"cannot_afford", from)
	var health := piece.health
	_set_buildable(piece, from.upgrade_to)
	if not cost_handler.is_free():
		piece.paid = PKBuildable.add_costs(piece.paid, cost)
	if health >= 0.0 and from.max_health > 0.0 and piece.buildable.max_health > 0.0:
		piece.health = health / from.max_health * piece.buildable.max_health
	_push({"type": "upgrade", "uid": uid, "from": from, "cost": {} if cost_handler.is_free() else cost.duplicate(), "health": health})
	upgraded.emit(piece, from)
	var result := PKResult.success([piece])
	result.cost = cost.duplicate()
	return result


## Deals [param amount] damage to a piece with health ([member PKBuildable.max_health]).
## At 0 it is destroyed: what rests on it may collapse, [member PKBuildable.destroy_refund_percent]
## and [member PKBuildable.loot] are given (what does not fit is reported by
## [signal refund_left_behind]). Not undoable.
func damage(uid: int, amount: float) -> PKResult:
	var piece := layout.get_piece(uid)
	if piece == null:
		return _refuse(&"not_found", null)
	if piece.buildable == null or piece.buildable.max_health <= 0.0:
		return _refuse(&"indestructible", piece.buildable)
	piece.health = maxf(piece.get_health() - maxf(amount, 0.0), 0.0)
	damaged.emit(piece, amount)
	if piece.health > 0.0:
		return PKResult.success([piece])
	return _destroy(uid)


## What a full repair of [param uid] costs now.
func repair_cost(uid: int) -> Dictionary:
	var piece := layout.get_piece(uid)
	if piece == null or not piece.is_damaged():
		return {}
	var missing := 1.0 - piece.get_health() / piece.buildable.max_health
	var cost := {}
	for item_id in piece.buildable.cost:
		var amount := ceili(int(piece.buildable.cost[item_id]) * piece.buildable.repair_cost_percent / 100.0 * missing - 0.0001)
		if amount > 0:
			cost[item_id] = amount
	return cost


## Repairs a damaged piece to full health for [method repair_cost].
func repair(uid: int) -> PKResult:
	var piece := layout.get_piece(uid)
	if piece == null:
		return _refuse(&"not_found", null)
	if not piece.is_damaged():
		return _refuse(&"not_damaged", piece.buildable)
	var cost := repair_cost(uid)
	if not cost_handler.pay(cost):
		return _refuse(&"cannot_afford", piece.buildable)
	piece.health = -1.0
	repaired.emit(piece, cost)
	var result := PKResult.success([piece])
	result.cost = cost
	return result


## A blueprint of the pieces [param uids] (they keep their places relative to each other,
## and what holds what). Pieces held by pieces outside the group lose that support.
func make_blueprint(uids: Array, title := "") -> PKBlueprint:
	var pieces: Array[PKPlacement] = []
	for uid in uids:
		var piece := layout.get_piece(uid)
		if piece != null and not pieces.has(piece):
			pieces.append(piece)
	pieces.sort_custom(func(a: PKPlacement, b: PKPlacement) -> bool: return a.uid < b.uid)
	var blueprint := PKBlueprint.new()
	blueprint.title = title
	if pieces.is_empty():
		return blueprint
	# The anchor (first entry) is the first piece standing on the ground.
	var anchor := pieces[0]
	for piece in pieces:
		if piece.grounded:
			anchor = piece
			break
	pieces.erase(anchor)
	pieces.push_front(anchor)
	var index := {}
	for i in pieces.size():
		index[pieces[i].uid] = i
	for piece in pieces:
		var supports: Array[int] = []
		for support in piece.supports:
			if index.has(support):
				supports.append(index[support])
		blueprint.entries.append({
			"id": piece.buildable_id, "pos": piece.position - anchor.position, "angle": piece.angle,
			"flip": piece.flipped, "up": piece.up, "supports": supports,
			"parent": index.get(piece.parent_uid, -1), "grounded": piece.grounded or supports.is_empty(),
			"on_grid": piece.on_grid,
		})
	return blueprint


## The pieces of [param blueprint] put down at [param aim], turned by [param angle] (snapped
## to quarter turns). Build them with [method place_many]: one payment, one undo step.
func blueprint_preview(blueprint: PKBlueprint, aim: PKAim, angle := 0.0) -> PKDragPreview:
	var drag := PKDragPreview.new()
	drag.blueprint = blueprint
	if blueprint == null or blueprint.entries.is_empty():
		return drag
	var turn := wrapf(snappedf(angle, 90.0), 0.0, 360.0)
	var basis := Basis(Vector3.UP, -deg_to_rad(turn))
	var anchor_entry: Dictionary = blueprint.entries[0]
	var anchor_buildable := catalog.get_buildable(StringName(anchor_entry.id))
	drag.buildable = anchor_buildable
	var target := aim.position
	if anchor_buildable != null and bool(anchor_entry.get("on_grid", false)) and grid != null:
		target = grid.snap(aim.position, anchor_buildable, float(anchor_entry.angle) + turn).position
		target.y = aim.position.y
	var batch: Array[PKPlacement] = []
	var valid_indices := {}
	var running := {}
	for i in blueprint.entries.size():
		var entry: Dictionary = blueprint.entries[i]
		var buildable := catalog.get_buildable(StringName(entry.id))
		var item := PKPreview.new()
		var placement := PKPlacement.make(buildable, target + basis * (entry.pos as Vector3), wrapf(float(entry.angle) + turn, 0.0, 360.0), bool(entry.get("flip", false)))
		placement.uid = -(i + 1)
		placement.cell_size = grid.cell_size if grid != null else Vector3.ONE
		placement.up = basis * (entry.get("up", Vector3.UP) as Vector3)
		placement.grounded = bool(entry.get("grounded", true))
		var parent := int(entry.get("parent", -1))
		placement.parent_uid = -(parent + 1) if parent >= 0 else 0
		for support in entry.get("supports", []):
			placement.supports.append(-(int(support) + 1))
		if bool(entry.get("on_grid", false)) and grid != null and buildable != null:
			placement.on_grid = true
			placement.cell = grid.snap(placement.position, buildable, placement.angle).cell
		item.placement = placement
		item.snapped_to_socket = placement.parent_uid != 0
		if buildable == null:
			item.reason = &"no_buildable"
			drag.previews.append(item)
			continue
		item.cost = buildable.cost.duplicate()
		var missing_support := false
		for support in placement.supports:
			if not valid_indices.has(support):
				missing_support = true
		placement.stability = stability_of(placement, batch)
		item.reason = &"needs_foundation" if missing_support else check(placement, Vector3.UP, item.snapped_to_socket, [], batch, false)
		if item.reason.is_empty():
			var next := PKBuildable.add_costs(running, buildable.cost)
			if cost_handler.can_pay(next):
				running = next
			else:
				item.reason = &"cannot_afford"
				drag.affordable = false
		item.valid = item.reason.is_empty()
		if item.valid:
			batch.append(placement)
			valid_indices[placement.uid] = true
		drag.previews.append(item)
	return _finish_drag(drag)


func _set_buildable(piece: PKPlacement, buildable: PKBuildable) -> void:
	piece.buildable = buildable
	piece.buildable_id = buildable.id
	layout.refresh(piece.uid)
	_raise_stability([piece.uid])


func _undo_upgrade(action: Dictionary) -> PKResult:
	var piece := layout.get_piece(action.uid)
	if piece == null:
		return _refuse(&"not_found", null)
	var cost: Dictionary = action.cost
	if not cost_handler.refund(cost):
		return _refuse(&"no_room", piece.buildable)
	var upgraded_to := piece.buildable
	_set_buildable(piece, action.from)
	for item_id in cost:
		piece.paid[item_id] = int(piece.paid.get(item_id, 0)) - int(cost[item_id])
		if piece.paid[item_id] <= 0:
			piece.paid.erase(item_id)
	piece.health = action.health
	upgraded.emit(piece, upgraded_to)
	var result := PKResult.success([piece])
	result.refund = cost.duplicate()
	return result


func _destroy(uid: int) -> PKResult:
	var target := layout.get_piece(uid)
	var pieces := _removal_set(uid)
	var items_of := {}
	var total := {}
	for piece in pieces:
		var items := {}
		if piece.buildable != null:
			items = PKBuildable.add_costs(PKBuildable.refund_of(piece.paid, piece.buildable.destroy_refund_percent), piece.buildable.loot)
		items_of[piece.uid] = items
		total = PKBuildable.add_costs(total, items)
	var left := cost_handler.refund_partial(total) if not total.is_empty() else {}
	for piece in pieces:
		layout.remove(piece.uid)
	_apply_weakened()
	for piece in pieces:
		removed.emit(piece, items_of[piece.uid])
		destroyed.emit(piece, items_of[piece.uid])
	if not left.is_empty():
		refund_left_behind.emit(left, target.position)
	var result := PKResult.success(pieces)
	result.refund = _given(total, left)
	result.left_behind = left
	return result


# --- Saves --------------------------------------------------------------------------------

## The whole layout as JSON-friendly data (pieces by buildable id, with what was paid).
func to_data() -> Dictionary:
	var pieces := []
	for placement in layout.get_all():
		pieces.append(placement.to_dict())
	for entry in _unknown_entries:
		pieces.append(entry.duplicate(true))
	return {"format": SAVE_FORMAT, "version": SAVE_VERSION, "next_uid": layout.get_next_uid(), "pieces": pieces}


func to_json() -> String:
	return JSON.stringify(to_data(), "\t")


## Replaces the layout with saved data. Pieces whose buildable left the catalog are skipped
## (listed in [member PKResult.skipped_ids], and kept aside to be saved again when
## [member keep_unknown_pieces] is on). Clears undo.
func load_data(data: Dictionary) -> PKResult:
	if data.get("format", "") != SAVE_FORMAT or not data.get("pieces") is Array:
		return _refuse(&"bad_save", null)
	if int(data.get("version", 0)) > SAVE_VERSION:
		return _refuse(&"save_too_new", null)
	var loaded: Array[PKPlacement] = []
	var unknown := []
	var skipped: Array[StringName] = []
	var used := {}
	var next_uid := maxi(int(data.get("next_uid", 1)), 1)
	for entry in data.pieces:
		if not entry is Dictionary:
			continue
		var placement := PKPlacement.from_dict(entry)
		if placement.uid <= 0 or used.has(placement.uid):
			placement.uid = 0
		var buildable := catalog.get_buildable(placement.buildable_id) if catalog != null else null
		if buildable == null:
			if not skipped.has(placement.buildable_id):
				skipped.append(placement.buildable_id)
			if keep_unknown_pieces:
				unknown.append(entry.duplicate(true))
			continue
		placement.buildable = buildable
		placement.cell_size = grid.cell_size if grid != null else Vector3.ONE
		if placement.uid > 0:
			used[placement.uid] = true
			next_uid = maxi(next_uid, placement.uid + 1)
		loaded.append(placement)
	for entry in unknown:
		next_uid = maxi(next_uid, int(entry.get("uid", 0)) + 1)
	# Supports that point to skipped pieces are dropped: the piece stays where it was.
	for placement in loaded:
		var kept: Array[int] = []
		for support in placement.supports:
			if used.has(support):
				kept.append(support)
		if kept.size() != placement.supports.size() and kept.is_empty():
			placement.grounded = true
		placement.supports = kept
		if not used.has(placement.parent_uid):
			placement.parent_uid = 0
	layout.clear()
	layout.set_next_uid(next_uid)
	for placement in loaded:
		layout.add(placement)
	refresh_stability()
	_unknown_entries = unknown
	_undo.clear()
	reset.emit()
	var result := PKResult.success(loaded)
	result.skipped_ids = skipped
	return result


func load_json(text: String) -> PKResult:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return _refuse(&"bad_save", null)
	return load_data(json.data)


## Saved pieces whose buildable is missing (kept aside, see [member keep_unknown_pieces]).
func get_unknown_entries() -> Array:
	return _unknown_entries.duplicate(true)


# --- Internal -----------------------------------------------------------------------------

func _refuse(reason: StringName, buildable: PKBuildable) -> PKResult:
	rejected.emit(reason, buildable)
	return PKResult.failure(reason)


func _push(action: Dictionary) -> void:
	_undo.append(action)
	while _undo.size() > undo_limit:
		_undo.pop_front()


func _given(total: Dictionary, left: Dictionary) -> Dictionary:
	var given := {}
	for item_id in total:
		var amount := int(total[item_id]) - int(left.get(item_id, 0))
		if amount > 0:
			given[item_id] = amount
	return given


func _grid_angle(buildable: PKBuildable, angle: float) -> float:
	var step := rotation_step_of(buildable)
	if step <= 0.0:
		return 0.0
	return wrapf(snappedf(angle, step), 0.0, 360.0)


func _set_support(placement: PKPlacement, hit_uid: int, ignore: Array, batch: Array[PKPlacement] = []) -> void:
	placement.supports.clear()
	placement.parent_uid = 0
	placement.grounded = true
	if hit_uid != 0 and (layout.has(hit_uid) or _in_batch(batch, hit_uid) != null) and not ignore.has(hit_uid):
		placement.supports.append(hit_uid)
		placement.grounded = false
		_probe_supports(placement, ignore, batch)


## Adds to the supports of a raised piece every piece right under its bottom face (a floor
## resting on four walls is held by all four).
func _probe_supports(placement: PKPlacement, ignore: Array, batch: Array[PKPlacement] = []) -> void:
	var box := placement.get_box()
	var down := box.basis.y.normalized()
	var probe := PKBox.make(box.center - down * (box.half.y + 0.02),
		Vector3(maxf(box.half.x - 0.04, 0.01), 0.05, maxf(box.half.z - 0.04, 0.01)), box.basis)
	var found := layout.overlapping(probe, -1, ignore)
	for other in batch:
		if other != placement and other.get_box().overlaps(probe):
			found.append(other)
	for other in found:
		if other.uid != placement.uid and not placement.supports.has(other.uid) \
				and (other.buildable == null or other.buildable.supports_on_top):
			placement.supports.append(other.uid)


## Stability of a placed or proposed piece, from its supports (1 on the ground for a full
## strength material). [param gone] lists uids to treat as removed, [param values] overrides
## the stability of some uids (both used while working out a collapse).
func stability_of(placement: PKPlacement, batch: Array[PKPlacement] = [], gone := {}, values := {}) -> float:
	var buildable := placement.buildable
	var strength := buildable.strength if buildable != null else 1.0
	if placement.grounded:
		return strength
	var best := 0.0
	for uid in placement.supports:
		if gone.has(uid):
			continue
		if values.has(uid):
			best = maxf(best, values[uid])
			continue
		var support := layout.get_piece(uid)
		if support == null:
			support = _in_batch(batch, uid)
		if support != null:
			best = maxf(best, support.stability)
	var loss := buildable.stability_loss if buildable != null else 0.0
	return minf(strength, best * (1.0 - loss))


## Works the stability of every piece out again (after a load, or when you change materials).
func refresh_stability() -> void:
	var pending: Array[PKPlacement] = layout.get_all()
	var placed_values := {}
	var rounds := 0
	while not pending.is_empty() and rounds < 64:
		rounds += 1
		var next: Array[PKPlacement] = []
		for piece in pending:
			var ready := piece.grounded
			if not ready:
				ready = true
				for support in piece.supports:
					if layout.has(support) and not placed_values.has(support):
						ready = false
						break
			if ready:
				piece.stability = stability_of(piece)
				placed_values[piece.uid] = true
			else:
				next.append(piece)
		if next.size() == pending.size():
			for piece in next:
				piece.stability = stability_of(piece)
			break
		pending = next


static func _in_batch(batch: Array[PKPlacement], uid: int) -> PKPlacement:
	for other in batch:
		if other.uid == uid:
			return other
	return null


# Sockets: every pair (placed socket, own socket that snaps to it) gives a pose; the nearest
# to the cursor wins, then the one turned closest to the player's rotation, preferring
# poses that are valid.
func _try_sockets(result: PKPreview, buildable: PKBuildable, aim: PKAim, angle: float, flipped: bool, ignore: Array) -> bool:
	var attaching: Array[PKSocket] = []
	for socket in buildable.sockets:
		if socket != null and not socket.snaps_to.is_empty():
			attaching.append(socket)
	if attaching.is_empty():
		return false
	var candidates := []
	for target in layout.sockets_near(aim.position, socket_radius, ignore):
		var target_piece: PKPlacement = target.piece
		if target_piece.buildable != null and not target_piece.buildable.supports_on_top and target.socket.position.y > 0.01:
			continue
		for own in attaching:
			if not own.can_attach_to(target.socket):
				continue
			var own_position := own.position
			var own_angle := own.angle
			if flipped:
				own_position.x = -own_position.x
				own_angle = -own_angle
			var yaw: float
			match own.facing:
				PKSocket.Facing.SAME:
					yaw = target.angle - own_angle
				PKSocket.Facing.OPPOSITE:
					yaw = target.angle + 180.0 - own_angle
				_:
					yaw = angle
			if own.facing != PKSocket.Facing.ANY and own.free_rotation_step > 0.0:
				yaw += snappedf(wrapf(angle - yaw, -180.0, 180.0), own.free_rotation_step)
			yaw = wrapf(yaw, 0.0, 360.0)
			var basis := Basis(Vector3.UP, -deg_to_rad(yaw))
			var position: Vector3 = target.position - basis * own_position
			var turn := absf(wrapf(yaw - angle, -180.0, 180.0))
			candidates.append({"target": target, "yaw": yaw, "position": position,
				"distance": snappedf(target.distance, 0.05), "turn": turn, "own": own})
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.distance, b.distance):
			return a.distance < b.distance
		if not is_equal_approx(a.turn, b.turn):
			return a.turn < b.turn
		return a.target.piece.uid < b.target.piece.uid)
	var chosen: Dictionary = {}
	var chosen_reason: StringName = &""
	var tried := 0
	for candidate in candidates:
		if tried >= 8:
			break
		tried += 1
		var placement := PKPlacement.make(buildable, candidate.position, candidate.yaw, flipped)
		placement.cell_size = result.placement.cell_size
		placement.parent_uid = candidate.target.piece.uid
		if candidate.own.holds:
			placement.supports = [candidate.target.piece.uid]
			placement.grounded = false
			_probe_supports(placement, ignore)
		placement.stability = stability_of(placement)
		var reason := check(placement, Vector3.UP, true, ignore)
		if chosen.is_empty() or (reason.is_empty() and not chosen_reason.is_empty()):
			chosen = candidate
			chosen_reason = reason
			result.placement = placement
		if reason.is_empty():
			break
	result.snapped_to_socket = true
	result.target_socket = chosen.target
	result.normal = Vector3.UP
	result.reason = chosen_reason
	result.valid = chosen_reason.is_empty()
	return true


func _drag_poses(buildable: PKBuildable, from: Vector3, to: Vector3, angle: float) -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	var base_angle := _grid_angle(buildable, angle)
	var start: Vector3i = grid.snap(from, buildable, base_angle).cell
	var finish: Vector3i = grid.snap(to, buildable, base_angle).cell
	var size := PKGrid.turned_cells(buildable, base_angle)
	match buildable.drag:
		PKBuildable.Drag.LINE:
			var along_x := absi(finish.x - start.x) >= absi(finish.z - start.z)
			var line_angle := base_angle
			if buildable.drag_align and buildable.can_rotate:
				# Pieces are long along their local X: turn them along the line.
				var long_x := buildable.cells.x >= buildable.cells.y
				line_angle = (0.0 if along_x else 90.0) if long_x else (90.0 if along_x else 0.0)
			var line_size := PKGrid.turned_cells(buildable, line_angle)
			var first: Vector3i = grid.snap(from, buildable, line_angle).cell
			var last: Vector3i = grid.snap(to, buildable, line_angle).cell
			if along_x:
				_add_run(poses, buildable, first, last.x - first.x, line_size.x, true, line_angle)
			else:
				_add_run(poses, buildable, first, last.z - first.z, line_size.y, false, line_angle)
		PKBuildable.Drag.PATH:
			var angle_x := base_angle
			var angle_z := base_angle
			if buildable.drag_align and buildable.can_rotate:
				angle_x = 0.0
				angle_z = 90.0 if buildable.cells.x != buildable.cells.y else 0.0
			var size_x := PKGrid.turned_cells(buildable, angle_x)
			var size_z := PKGrid.turned_cells(buildable, angle_z)
			_add_run(poses, buildable, start, finish.x - start.x, size_x.x, true, angle_x)
			var corner := Vector3i(start.x + _steps(finish.x - start.x, size_x.x) * size_x.x * signi(finish.x - start.x), start.y, start.z)
			var leg: Array[Dictionary] = []
			_add_run(leg, buildable, corner, finish.z - start.z, size_z.y, false, angle_z)
			for pose in leg.slice(1):
				poses.append(pose)
		PKBuildable.Drag.RECT, PKBuildable.Drag.OUTLINE:
			var nx := _steps(finish.x - start.x, size.x)
			var nz := _steps(finish.z - start.z, size.y)
			var sx := signi(finish.x - start.x) if finish.x != start.x else 1
			var sz := signi(finish.z - start.z) if finish.z != start.z else 1
			for iz in nz + 1:
				for ix in nx + 1:
					if buildable.drag == PKBuildable.Drag.OUTLINE and ix > 0 and ix < nx and iz > 0 and iz < nz:
						continue
					var cell := Vector3i(start.x + ix * size.x * sx, start.y, start.z + iz * size.y * sz)
					poses.append({"cell": cell, "angle": base_angle, "position": grid.position_at(cell, buildable, base_angle)})
		_:
			poses.append({"cell": start, "angle": base_angle, "position": grid.position_at(start, buildable, base_angle)})
	if poses.size() > max_drag_pieces:
		poses.resize(max_drag_pieces)
	for pose in poses:
		pose.position.y = from.y
	return poses


func _steps(delta: int, size: int) -> int:
	return absi(delta) / maxi(size, 1)


func _add_run(poses: Array[Dictionary], buildable: PKBuildable, first: Vector3i, delta: int, size: int, along_x: bool, angle: float) -> void:
	var direction := signi(delta) if delta != 0 else 1
	for i in _steps(delta, size) + 1:
		var cell := first + (Vector3i(i * size * direction, 0, 0) if along_x else Vector3i(0, 0, i * size * direction))
		poses.append({"cell": cell, "angle": angle, "position": grid.position_at(cell, buildable, angle)})


func _finish_drag(drag: PKDragPreview) -> PKDragPreview:
	for item in drag.previews:
		if item.valid:
			drag.valid_count += 1
			drag.total_cost = PKBuildable.add_costs(drag.total_cost, item.cost)
	if drag.buildable != null and drag.buildable.drag == PKBuildable.Drag.NONE:
		drag.affordable = drag.previews.is_empty() or drag.previews[0].reason != &"cannot_afford"
	return drag


# The piece and everything that would fall with it, the piece last. Walks up through the
# pieces resting on what goes (an index, not the whole layout): a piece falls when nothing
# holds it any more, or, with stability on, when it becomes too weak. The new stability of
# the pieces that stay is kept for [method _apply_weakened].
var _weakened := {}


func _removal_set(uid: int) -> Array[PKPlacement]:
	var target := layout.get_piece(uid)
	var result: Array[PKPlacement] = []
	_weakened.clear()
	if target == null:
		return result
	var gone := {uid: true}
	var values := {}
	var queue: Array[int] = layout.dependents_of(uid)
	var visits := 0
	while not queue.is_empty() and visits < 100000:
		visits += 1
		var piece := layout.get_piece(queue.pop_front())
		if piece == null or gone.has(piece.uid) or piece.grounded:
			continue
		var held := false
		for support in piece.supports:
			if not gone.has(support) and layout.has(support):
				held = true
				break
		var value := stability_of(piece, [], gone, values) if held else 0.0
		var falls := not held or (stability_enabled and value < min_stability - 0.0001)
		if falls:
			gone[piece.uid] = true
			values.erase(piece.uid)
			result.append(piece)
			queue.append_array(layout.dependents_of(piece.uid))
		elif value < values.get(piece.uid, piece.stability) - 0.0001:
			values[piece.uid] = value
			queue.append_array(layout.dependents_of(piece.uid))
	# Topmost first, so signals and undo see pieces before what held them.
	result.reverse()
	result.append(target)
	_weakened = values
	return result


func _apply_weakened() -> void:
	for uid in _weakened:
		var piece := layout.get_piece(uid)
		if piece != null:
			piece.stability = _weakened[uid]
	_weakened.clear()


# After an undo or an upgrade: stability may rise again above [param uid].
func _raise_stability(uids: Array) -> void:
	var queue: Array = uids.duplicate()
	var visits := 0
	while not queue.is_empty() and visits < 100000:
		visits += 1
		var piece := layout.get_piece(queue.pop_front())
		if piece == null:
			continue
		var value := stability_of(piece)
		if not is_equal_approx(value, piece.stability) or visits <= uids.size():
			piece.stability = value
			queue.append_array(layout.dependents_of(piece.uid))


func _apply_pose(piece: PKPlacement, pose: PKPlacement) -> void:
	piece.position = pose.position
	piece.angle = pose.angle
	piece.flipped = pose.flipped
	piece.up = pose.up
	piece.cell = pose.cell
	piece.on_grid = pose.on_grid
	piece.parent_uid = pose.parent_uid
	piece.supports = pose.supports.duplicate()
	piece.grounded = pose.grounded
	piece.stability = pose.stability


func _undo_place(action: Dictionary) -> PKResult:
	var pieces: Array[PKPlacement] = []
	var total := {}
	var seen := {}
	for saved in action.pieces:
		for piece in _removal_set(saved.uid):
			if not seen.has(piece.uid):
				seen[piece.uid] = true
				pieces.append(piece)
				total = PKBuildable.add_costs(total, piece.paid)
	if pieces.is_empty():
		return _refuse(&"not_found", null)
	if not cost_handler.refund(total):
		return _refuse(&"no_room", pieces[0].buildable)
	for piece in pieces:
		layout.remove(piece.uid)
	_apply_weakened()
	for piece in pieces:
		removed.emit(piece, piece.paid.duplicate())
	var result := PKResult.success(pieces)
	result.refund = total
	return result


func _undo_remove(action: Dictionary) -> PKResult:
	var restored: Array[PKPlacement] = []
	var pieces: Array = action.pieces.duplicate()
	pieces.reverse()  # holders first
	for saved: PKPlacement in pieces:
		if layout.has(saved.uid):
			return _refuse(&"overlap", saved.buildable)
		var box := saved.get_box().grown(-0.02)
		var layer := saved.buildable.layer if saved.buildable != null else 0
		if not layout.overlapping(box, layer).is_empty():
			return _refuse(&"overlap", saved.buildable)
	var refund: Dictionary = action.refund
	if not cost_handler.pay(refund):
		return _refuse(&"cannot_afford", pieces[0].buildable)
	for saved: PKPlacement in pieces:
		var piece := saved.duplicate_pose()
		layout.add(piece)
		restored.append(piece)
	_raise_stability(restored.map(func(p: PKPlacement) -> int: return p.uid))
	for piece in restored:
		placed.emit(piece)
	var result := PKResult.success(restored)
	result.cost = refund.duplicate()
	return result


func _undo_move(action: Dictionary) -> PKResult:
	var from: PKPlacement = action.from
	var piece := layout.get_piece(from.uid)
	if piece == null:
		return _refuse(&"not_found", null)
	var box := from.get_box().grown(-0.02)
	if not layout.overlapping(box, from.buildable.layer if from.buildable != null else 0, [from.uid]).is_empty():
		return _refuse(&"overlap", piece.buildable)
	var before := piece.duplicate_pose()
	_apply_pose(piece, from)
	layout.refresh(piece.uid)
	moved.emit(piece, before)
	return PKResult.success([piece])
