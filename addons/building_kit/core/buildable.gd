class_name PKBuildable
extends Resource
## Something the player can build: a wall, a road, a bed. One resource per kind of piece.
##
## The only required fields are [member id] and [member scene] (2D or 3D). Without a scene
## the build nodes draw a coloured box, handy to prototype. Saves keep [member id] only, so
## keep it stable once your game is out.
## [codeblock]
## var wall := PKBuildable.new()
## wall.id = &"wood_wall"
## wall.display_name = "Wooden wall"
## wall.category = &"walls"
## wall.scene = preload("res://pieces/wood_wall.tscn")
## wall.cells = Vector2i(2, 1)
## wall.cost = {&"wood_log": 4}
## wall.refund_percent = 50.0
## [/codeblock]

## How the piece finds its place (flags: a piece can use several, tried in order
## SOCKET, GRID, SURFACE).
enum Snap {
	GRID = 1,     ## On the grid (cells), like a city builder or a Minecraft block.
	SURFACE = 2,  ## Anywhere on a surface under the cursor (free placement, furniture).
	SOCKET = 4,   ## On the sockets of placed pieces (walls on floors, roofs on walls).
}

## How dragging builds several pieces at once.
enum Drag {
	NONE,     ## One piece per click.
	LINE,     ## A straight line (walls, fences).
	PATH,     ## An L-shaped path: along X then along Z (roads).
	RECT,     ## A filled rectangle (floors, fields).
	OUTLINE,  ## The border of a rectangle (an enclosure).
}

## Which surfaces the piece can stand on (free and grid placement in 3D).
enum Surface { FLOOR, WALL, CEILING, ANY }

@export_group("Identity")
## Stable identifier, used by saves. Never reuse an id for another piece.
@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
## Catalog tab ("walls", "furniture"...).
@export var category: StringName = &""
@export var icon: Texture2D
## Free tags for your rules ("foundation", "road"...).
@export var tags: Array[StringName] = []
## Shown in the catalog panel. Off for scenery the player may demolish (or move) but not
## build: trees that give wood, rocks that give stone.
@export var in_catalog := true

@export_group("Look and size")
## The piece (Node2D or Node3D scene). Its origin is the centre of its footprint, on the
## ground. Add collision shapes in 3D so pieces can be built on top of it.
@export var scene: PackedScene
## Footprint in cells (X, Z in 3D; X, Y in 2D).
@export var cells := Vector2i.ONE
## Height in world units (3D). 0 = one cell high.
@export var height := 0.0
## Exact box used for overlaps, in world units (0 = cells × cell size × height).
@export var size := Vector3.ZERO
## Offset of that box from the origin (the box sits on the ground by default).
@export var box_offset := Vector3.ZERO
## Pieces only collide with pieces of the same layer (a rug and a table: layers 1 and 0).
@export var layer := 0
## Colour of the box drawn when there is no [member scene].
@export var color := Color(0.75, 0.68, 0.55)
## 3D: draw every copy of this piece with MultiMesh (one draw call per mesh for thousands of
## walls or floor tiles). The scene's meshes are drawn, its scripts and lights are not run;
## each copy still gets a box collision for the cursor and stacking.
@export var batch_render := false
## Autotiling: neighbours tagged like this join up (roads, fences, pipes). See [PKAutotile].
@export var autotile_tag: StringName = &""
## The scene for each shape: "single", "end", "straight", "corner", "t", "cross". Draw each
## shape with its connections towards +X (end), +X/-X (straight), +X/+Z (corner),
## +X/+Z/-X (t). Missing shapes use [member scene].
@export var variant_scenes: Dictionary = {}

@export_group("Placement")
@export_flags("Grid:1", "Surface:2", "Socket:4") var snap: int = Snap.GRID
@export var can_rotate := true
## Degrees per rotation step (0 = the build system's default, 90 on a grid).
@export var rotation_step := 0.0
## Can be turned to face any of the 6 directions (a log, a pipe, a beam): see
## [method PKBuildController.tilt].
@export var can_tilt := false
## Can be mirrored (left / right versions of the same piece).
@export var can_flip := false
## Can be built on top of other pieces (a lamp on a table).
@export var stackable := false
## Other pieces can be built on top of this one.
@export var supports_on_top := true
## Turn the piece to the surface under the cursor (a painting on a wall).
@export var align_to_normal := false
@export var surface := Surface.FLOOR
## Steepest ground the piece accepts, in degrees (FLOOR pieces).
@export_range(0.0, 90.0, 0.5) var max_slope_degrees := 35.0
@export var sockets: Array[PKSocket] = []
@export var drag := Drag.NONE
## When dragging a line, turn each piece along the line.
@export var drag_align := true

@export_group("Rules")
## Must rest on a piece tagged with one of [member foundation_tags] (or snap to one).
@export var needs_foundation := false
@export var foundation_tags: Array[StringName] = [&"foundation"]
## How many of this piece the player may build (-1 = no limit).
@export var max_count := -1
## Zones where the piece may be built (empty = everywhere). See [method PKBuilder.zone_at].
@export var allowed_zones: Array[StringName] = []
@export var forbidden_zones: Array[StringName] = []
## A piece tagged like this must be next to it (a house next to a road). Empty: no need.
@export var needs_nearby_tag: StringName = &""
## How far that piece may be, in cells (1 = touching).
@export var nearby_cells := 1
## Your own rules, checked after the built-in ones.
@export var rules: Array[PKPlacementRule] = []

@export_group("Structure")
## Stability of the piece when it stands on the ground (1 = 100 %). Used when
## [member PKBuilder.stability_enabled] is on: a weak material carries less.
@export_range(0.0, 1.0, 0.01) var strength := 1.0
## Share of the stability lost from the best piece holding it (Valheim style): a wall on a
## wall on a wall gets weaker and weaker.
@export_range(0.0, 1.0, 0.01) var stability_loss := 0.15

@export_group("Upgrade")
## What this piece becomes when upgraded in place (wood -> stone -> metal). Null: no upgrade.
@export var upgrade_to: PKBuildable
## Cost of the upgrade (empty: the cost of [member upgrade_to]).
@export var upgrade_cost: Dictionary = {}

@export_group("Health")
## Hit points (0 = cannot be damaged).
@export var max_health := 0.0
## Share of [member cost] paid for a full repair.
@export_range(0.0, 200.0, 1.0) var repair_cost_percent := 50.0
## Share of what was paid given back when it is destroyed by damage.
@export_range(0.0, 100.0, 1.0) var destroy_refund_percent := 0.0
## Extra items dropped when it is destroyed by damage, {item_id: amount}.
@export var loot: Dictionary = {}

@export_group("Cost")
## Items taken when the piece is built, {item_id: amount}.
@export var cost: Dictionary = {}
## Share of the cost given back when the piece is demolished (undo always gives it all).
@export_range(0.0, 100.0, 1.0) var refund_percent := 50.0

## Anything else your game needs ({"hp": 200}).
@export var properties: Dictionary = {}


static func make(p_id: StringName, p_name := "", p_cells := Vector2i.ONE, p_cost := {}) -> PKBuildable:
	var buildable := PKBuildable.new()
	buildable.id = p_id
	buildable.display_name = p_name if not p_name.is_empty() else String(p_id).capitalize()
	buildable.cells = p_cells
	buildable.cost = p_cost
	return buildable


func uses(mode: int) -> bool:
	return (snap & mode) != 0


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func get_upgrade_cost() -> Dictionary:
	if upgrade_to == null:
		return {}
	return upgrade_cost if not upgrade_cost.is_empty() else upgrade_to.cost


## True when the piece changes scene with its neighbours (autotiling).
func has_variants() -> bool:
	return not autotile_tag.is_empty() and not variant_scenes.is_empty()


func get_title() -> String:
	return PKText.t(display_name if not display_name.is_empty() else String(id).capitalize())


## The cost to give back for [param percent] of [param paid] (rounded down, per item).
static func refund_of(paid: Dictionary, percent: float) -> Dictionary:
	var refund := {}
	for item_id in paid:
		var amount := floori(int(paid[item_id]) * percent / 100.0 + 0.0001)
		if amount > 0:
			refund[item_id] = amount
	return refund


## Sum of several costs.
static func add_costs(a: Dictionary, b: Dictionary, times := 1) -> Dictionary:
	var total := a.duplicate()
	for item_id in b:
		total[item_id] = int(total.get(item_id, 0)) + int(b[item_id]) * times
	return total
