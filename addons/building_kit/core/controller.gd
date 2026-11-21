class_name PKBuildController
extends RefCounted
## The player's side of building, the same in 2D and 3D: the mode (build, move, demolish,
## select, upgrade, repair), the chosen piece or blueprint, its rotation, the ghost, drags,
## hover, the selection (click, Shift + click, or drag a box) and the floor level.
## The build nodes feed it aims from the mouse, gamepad or touch and draw what it says;
## the interface (catalog, mode bar) talks to it. You rarely need to touch it directly:
## [PKBuildSystem2D] and [PKBuildSystem3D] expose the same methods.

enum Mode { BUILD, MOVE, DEMOLISH, SELECT, UPGRADE, REPAIR }

## The 6 directions [method tilt] cycles through (up first).
const TILTS: Array[Vector3] = [Vector3.UP, Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.DOWN]

signal mode_changed(mode: Mode)
signal buildable_changed(buildable: PKBuildable)
## A blueprint was picked to be put down (null: none).
signal blueprint_changed(blueprint: PKBlueprint)
## The ghost changed (pose, colour, drag).
signal preview_changed
## The piece under the cursor changed (0 = none).
signal hover_changed(uid: int)
## The selection changed; [param uid] is the last piece picked (0 = empty selection).
signal selection_changed(uid: int)
## A piece was picked up to be moved (0 = put down or cancelled).
signal moving_changed(uid: int)
## The list of saved blueprints changed ([member blueprints]).
signal blueprints_changed
## The floor level changed ([member level]).
signal level_changed(level: int)
## A short line for the player (refusals, refunds). [param error] is true for refusals.
signal message(text: String, error: bool)

var builder: PKBuilder
var mode := Mode.BUILD
var buildable: PKBuildable
## The blueprint being put down (instead of [member buildable]).
var blueprint: PKBlueprint
## Player rotation in degrees (clockwise from above).
var angle := 0.0
var flipped := false
var tilt_index := 0
## Step of [method rotate] with [code]fine = true[/code] (free placement only).
var fine_rotation_step := 15.0
## The single ghost (null when there is nothing to show).
var preview: PKPreview
## The ghosts of a drag in progress or of a blueprint (null otherwise).
var drag: PKDragPreview
var hover_uid := 0
## The last piece selected (see [method get_selection] for all of them).
var selected_uid := 0
var moving_uid := 0
## Floor level the player builds on (0 = ground). See [member max_level].
var level := 0
## Highest level (0 = no levels).
var max_level := 0
## Show refusals and refunds through [signal message].
var report_messages := true
## Blueprints the player saved (or you gave), shown in the catalog's Blueprints tab.
var blueprints: Array[PKBlueprint] = []

var _selection: Array[int] = []
var _drag_from: PKAim
var _select_from: PKAim
var _select_additive := false
var _last_aim: PKAim


func _init(p_builder: PKBuilder = null) -> void:
	builder = p_builder if p_builder != null else PKBuilder.new()
	builder.rejected.connect(_on_rejected)
	builder.removed.connect(_on_removed)


func set_mode(value: Mode) -> void:
	if value == mode:
		return
	_cancel_transient()
	mode = value
	if mode != Mode.SELECT:
		clear_selection()
	mode_changed.emit(mode)
	refresh()


## Picks a piece to build (its id or the resource) and switches to the build mode.
## null puts the tool away.
func select_buildable(value: Variant) -> void:
	var picked: PKBuildable = value if value is PKBuildable else (builder.catalog.get_buildable(StringName(value)) if value != null else null)
	_cancel_transient()
	buildable = picked
	if blueprint != null:
		blueprint = null
		blueprint_changed.emit(null)
	flipped = false
	tilt_index = 0
	if picked != null and not picked.can_rotate:
		angle = 0.0
	_enter_build()
	buildable_changed.emit(buildable)
	refresh()


## Picks a blueprint to put down (null puts it away).
func select_blueprint(value: PKBlueprint) -> void:
	_cancel_transient()
	blueprint = value if value != null and not value.is_empty() else null
	buildable = null
	angle = snappedf(angle, 90.0)
	_enter_build()
	blueprint_changed.emit(blueprint)
	buildable_changed.emit(null)
	refresh()


## Turns the ghost by one step ([param direction] -1 turns back). [param fine] uses
## [member fine_rotation_step] for pieces placed freely. Blueprints turn by quarter turns.
func rotate(direction := 1, fine := false) -> void:
	if blueprint != null and mode == Mode.BUILD:
		angle = wrapf(snappedf(angle, 90.0) + 90.0 * signf(direction), 0.0, 360.0)
		refresh()
		return
	var piece := _active_buildable()
	if piece == null:
		return
	var step := builder.rotation_step_of(piece)
	if step <= 0.0:
		_say(&"cannot_rotate", true)
		return
	if fine and piece.uses(PKBuildable.Snap.SURFACE) and not piece.uses(PKBuildable.Snap.GRID):
		step = minf(step, fine_rotation_step)
	angle = wrapf(snappedf(angle, step) + step * signf(direction), 0.0, 360.0)
	refresh()


func flip() -> void:
	var piece := _active_buildable()
	if piece != null and piece.can_flip:
		flipped = not flipped
		refresh()


## Cycles the piece through the 6 directions ([member PKBuildable.can_tilt]).
func tilt() -> void:
	var piece := _active_buildable()
	if piece != null and piece.can_tilt:
		tilt_index = (tilt_index + 1) % TILTS.size()
		refresh()


## Goes up or down one floor level (clamped to 0..[member max_level]).
func set_level(value: int) -> void:
	var clamped := clampi(value, 0, max_level)
	if clamped == level:
		return
	level = clamped
	level_changed.emit(level)
	refresh()


## The player points at [param aim]: updates hover, ghost and drag.
func aim(p_aim: PKAim) -> void:
	_last_aim = p_aim
	var hovered := 0
	if mode != Mode.BUILD and p_aim != null and p_aim.has_hit and moving_uid == 0:
		hovered = p_aim.hit_uid
	if hovered != hover_uid:
		hover_uid = hovered
		hover_changed.emit(hover_uid)
	refresh()


## Recomputes the ghost for the last aim (after a cost or layout change).
func refresh() -> void:
	if blueprint != null and mode == Mode.BUILD and _last_aim != null:
		preview = null
		drag = builder.blueprint_preview(blueprint, _last_aim, angle) if _last_aim.has_hit else null
		preview_changed.emit()
		return
	var piece := _active_buildable()
	var showing := (mode == Mode.BUILD or moving_uid != 0) and piece != null and _last_aim != null
	if not showing:
		if preview != null or drag != null:
			preview = null
			drag = null
			preview_changed.emit()
		return
	if _drag_from != null:
		drag = builder.drag_preview(piece, _drag_from, _last_aim, angle, flipped)
		preview = null
	else:
		drag = null
		var ignore := [moving_uid] if moving_uid != 0 else []
		preview = builder.preview(piece, _last_aim, angle, flipped, ignore, TILTS[tilt_index])
		if moving_uid != 0 and preview.reason == &"cannot_afford":
			# Moving is free.
			preview.reason = builder.check(preview.placement, preview.normal, preview.snapped_to_socket, ignore, [], false)
			preview.valid = preview.reason.is_empty()
	preview_changed.emit()


## The confirm button went down (click, A, tap). [param additive]: Shift is held (adds to
## the selection in the select mode).
func press(p_aim: PKAim = null, additive := false) -> void:
	if p_aim != null:
		aim(p_aim)
	match mode:
		Mode.BUILD:
			if blueprint != null:
				if drag != null:
					var result := builder.place_many(drag)
					if result.ok:
						_say_text(PKText.t("Built: %s") % blueprint.title, false)
				refresh()
				return
			if buildable == null:
				_say(&"no_buildable", true)
				return
			if buildable.drag != PKBuildable.Drag.NONE and _last_aim != null and _last_aim.has_hit:
				_drag_from = _last_aim
				drag = builder.drag_preview(buildable, _drag_from, _last_aim, angle, flipped)
				preview = null
				preview_changed.emit()
			else:
				_place_single()
		Mode.MOVE:
			if moving_uid == 0:
				_pick_up(hover_uid)
			else:
				_put_down()
		Mode.DEMOLISH:
			if hover_uid != 0:
				var result := builder.remove(hover_uid)
				if result.ok:
					_report_refund(result)
				_rehover()
		Mode.SELECT:
			_select_from = _last_aim
			_select_additive = additive
		Mode.UPGRADE:
			if hover_uid != 0:
				var result := builder.upgrade(hover_uid)
				if result.ok:
					_say_text(PKText.t("Upgraded to %s") % result.placements[0].get_title(), false)
				_rehover()
		Mode.REPAIR:
			if hover_uid != 0:
				var result := builder.repair(hover_uid)
				if result.ok:
					_say_text(PKText.t("Repaired for %s") % PKText.cost_text(result.cost, builder.cost_handler), false)
				_rehover()


## The confirm button went up: finishes a drag or a box selection.
func release(p_aim: PKAim = null) -> void:
	if p_aim != null:
		aim(p_aim)
	if mode == Mode.SELECT and _select_from != null:
		var from := _select_from
		_select_from = null
		var to := _last_aim if _last_aim != null else from
		var cell := builder.grid.cell_size if builder.grid != null else Vector3.ONE
		if from.position.distance_to(to.position) > minf(cell.x, cell.z) * 0.5:
			select_area(from.position, to.position, _select_additive)
		elif _select_additive:
			toggle_selection(hover_uid)
		else:
			select_piece(hover_uid)
		return
	if drag == null or _drag_from == null:
		return
	var finished := drag
	drag = null
	_drag_from = null
	if finished.previews.size() == 1 and finished.previews[0].valid:
		builder.place(finished.previews[0])
	else:
		builder.place_many(finished)
	refresh()


## Cancel / right click / B: drops a drag, puts a moved piece back, clears the selection,
## then puts the tool away.
func cancel() -> void:
	if _drag_from != null or moving_uid != 0 or _select_from != null:
		_cancel_transient()
		refresh()
	elif not _selection.is_empty():
		clear_selection()
	elif mode == Mode.BUILD and (buildable != null or blueprint != null):
		select_buildable(null)
	elif mode != Mode.BUILD:
		set_mode(Mode.BUILD)


func undo() -> PKResult:
	_cancel_transient()
	var result := builder.undo()
	refresh()
	return result


# --- Selection ----------------------------------------------------------------------------

## Selects only [param uid] (0 clears the selection).
func select_piece(uid: int) -> void:
	if uid == 0 or not builder.layout.has(uid):
		clear_selection()
		return
	if _selection.size() == 1 and _selection[0] == uid:
		return
	_selection.clear()
	_selection.append(uid)
	selected_uid = uid
	selection_changed.emit(selected_uid)


## Adds [param uid] to the selection, or takes it out.
func toggle_selection(uid: int) -> void:
	if uid == 0 or not builder.layout.has(uid):
		return
	if _selection.has(uid):
		_selection.erase(uid)
	else:
		_selection.append(uid)
	selected_uid = _selection.back() if not _selection.is_empty() else 0
	selection_changed.emit(selected_uid)


## Selects every piece whose centre is inside the box between two corners on the ground.
func select_area(corner_a: Vector3, corner_b: Vector3, additive := false) -> void:
	if not additive:
		_selection.clear()
	var low := Vector2(minf(corner_a.x, corner_b.x), minf(corner_a.z, corner_b.z))
	var high := Vector2(maxf(corner_a.x, corner_b.x), maxf(corner_a.z, corner_b.z))
	var area := AABB(Vector3(low.x, -100000.0, low.y), Vector3(high.x - low.x, 200000.0, high.y - low.y))
	for piece in builder.layout.near(area):
		var center := piece.get_box().center
		if center.x >= low.x and center.x <= high.x and center.z >= low.y and center.z <= high.y and not _selection.has(piece.uid):
			_selection.append(piece.uid)
	selected_uid = _selection.back() if not _selection.is_empty() else 0
	selection_changed.emit(selected_uid)


func clear_selection() -> void:
	if _selection.is_empty() and selected_uid == 0:
		return
	_selection.clear()
	selected_uid = 0
	selection_changed.emit(0)


## Every selected uid, in the order they were picked.
func get_selection() -> Array[int]:
	return _selection.duplicate()


func is_selected(uid: int) -> bool:
	return _selection.has(uid)


## Saves the selection as a new blueprint in [member blueprints] and returns it (null when
## nothing is selected).
func save_selection_as_blueprint(title := "") -> PKBlueprint:
	var made := selection_to_blueprint(title if not title.is_empty() else PKText.t("Blueprint %d") % (blueprints.size() + 1))
	if made == null:
		return null
	add_blueprint(made)
	_say_text(PKText.t("Blueprint saved: %s") % made.title, false)
	return made


func add_blueprint(value: PKBlueprint) -> void:
	if value != null and not blueprints.has(value):
		blueprints.append(value)
		blueprints_changed.emit()


func remove_blueprint(value: PKBlueprint) -> void:
	if blueprints.has(value):
		blueprints.erase(value)
		if blueprint == value:
			select_blueprint(null)
		blueprints_changed.emit()


## The selected pieces as a blueprint ([method PKBuilder.make_blueprint]); null when empty.
func selection_to_blueprint(title := "") -> PKBlueprint:
	if _selection.is_empty():
		_say(&"empty_blueprint", true)
		return null
	return builder.make_blueprint(_selection, title)


# --- Queries ------------------------------------------------------------------------------

## True when the cursor should hit placed pieces (stacking, sockets, other modes); false
## when it should go through them to the ground (grid pieces are laid on the terrain).
func aim_hits_pieces() -> bool:
	if mode != Mode.BUILD and moving_uid == 0:
		return true
	if blueprint != null:
		return false
	var piece := _active_buildable()
	return piece != null and (piece.stackable or piece.uses(PKBuildable.Snap.SOCKET))


## True while the player holds the button to build a line or an area.
func is_dragging() -> bool:
	return drag != null and _drag_from != null


## True while the player drags a selection box ([method get_selection_box] gives its corners).
func is_selecting_area() -> bool:
	return _select_from != null


## The two corners of the selection box being dragged ([] when none).
func get_selection_box() -> Array[Vector3]:
	if _select_from == null or _last_aim == null:
		return []
	return [_select_from.position, _last_aim.position]


## The piece the ghost shows (the chosen one, the one being moved, or the anchor of a blueprint).
func get_active_buildable() -> PKBuildable:
	if blueprint != null and mode == Mode.BUILD:
		return drag.buildable if drag != null else null
	return _active_buildable()


func _active_buildable() -> PKBuildable:
	if moving_uid != 0:
		var piece := builder.layout.get_piece(moving_uid)
		return piece.buildable if piece != null else null
	return buildable if mode == Mode.BUILD else null


func _enter_build() -> void:
	if mode != Mode.BUILD:
		mode = Mode.BUILD
		clear_selection()
		mode_changed.emit(mode)


func _place_single() -> void:
	if preview == null:
		return
	if not preview.valid:
		builder.rejected.emit(preview.reason, buildable)
		return
	builder.place(preview)
	refresh()


func _pick_up(uid: int) -> void:
	var piece := builder.layout.get_piece(uid)
	if piece == null:
		return
	if not builder.layout.resting_on(uid).is_empty():
		builder.rejected.emit(&"supports_others", piece.buildable)
		return
	moving_uid = uid
	angle = piece.angle
	flipped = piece.flipped
	tilt_index = maxi(TILTS.find(piece.up.round()), 0) if not piece.buildable.align_to_normal else 0
	hover_uid = 0
	hover_changed.emit(0)
	moving_changed.emit(uid)
	refresh()


func _put_down() -> void:
	if preview == null:
		return
	if not preview.valid:
		builder.rejected.emit(preview.reason, preview.get_buildable())
		return
	var result := builder.move(moving_uid, preview)
	if result.ok:
		moving_uid = 0
		moving_changed.emit(0)
		refresh()


func _rehover() -> void:
	hover_uid = 0
	hover_changed.emit(0)
	if _last_aim != null:
		aim(_last_aim)


func _cancel_transient() -> void:
	if _drag_from != null:
		drag = null
	_drag_from = null
	_select_from = null
	if moving_uid != 0:
		moving_uid = 0
		moving_changed.emit(0)


func _on_removed(placement: PKPlacement, _refund: Dictionary) -> void:
	if _selection.has(placement.uid):
		_selection.erase(placement.uid)
		selected_uid = _selection.back() if not _selection.is_empty() else 0
		selection_changed.emit(selected_uid)
	if moving_uid == placement.uid:
		moving_uid = 0
		moving_changed.emit(0)


func _on_rejected(reason: StringName, _buildable: PKBuildable) -> void:
	_say(reason, true)


func _say(reason: StringName, error: bool) -> void:
	_say_text(PKText.reason(reason), error)


func _say_text(text: String, error: bool) -> void:
	if report_messages and not text.is_empty():
		message.emit(text, error)


func _report_refund(result: PKResult) -> void:
	if not result.refund.is_empty():
		_say_text(PKText.t("Refund: %s") % PKText.cost_text(result.refund, builder.cost_handler), false)
	if not result.left_behind.is_empty():
		_say_text(PKText.t("No room for: %s") % PKText.cost_text(result.left_behind, builder.cost_handler), true)
