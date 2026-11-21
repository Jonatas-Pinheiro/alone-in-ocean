class_name PKGrid
extends Resource
## The building grid, the same for 2D and 3D: cells on the ground plane (X, Z; 2D X, Y),
## optional levels in height. The build nodes fill it from a TileMapLayer or a GridMap.
##
## A piece of N × M cells is centred on its footprint, so even sizes sit on cell corners and
## odd sizes on cell centres. Turning it by a quarter swaps N and M and snaps it again around
## the same point: the piece stays aligned and under the cursor.

## Size of a cell: X and Z on the ground, Y = height of a level.
@export var cell_size := Vector3(1, 1, 1)
## World position of the corner of cell (0, 0, 0).
@export var origin := Vector3.ZERO
## Snap heights to levels of [code]cell_size.y[/code] (off: follow the ground).
@export var snap_height := false
## Cells the player may build on, in X / Z (size 0 = no limit).
@export var bounds := Rect2i()


static func make(p_cell_size := Vector3.ONE, p_origin := Vector3.ZERO) -> PKGrid:
	var grid := PKGrid.new()
	grid.cell_size = p_cell_size
	grid.origin = p_origin
	return grid


## 0, 1, 2 or 3 quarter turns for [param angle].
static func quarter_turns(angle: float) -> int:
	return posmod(roundi(angle / 90.0), 4)


## Footprint of [param buildable] in cells once turned by [param angle].
static func turned_cells(buildable: PKBuildable, angle: float) -> Vector2i:
	var cells := buildable.cells if buildable != null else Vector2i.ONE
	return Vector2i(cells.y, cells.x) if quarter_turns(angle) % 2 == 1 else cells


## The cell that contains [param point].
func cell_of(point: Vector3) -> Vector3i:
	var local := point - origin
	return Vector3i(floori(local.x / cell_size.x), floori(local.y / cell_size.y + 0.0001), floori(local.z / cell_size.z))


## Centre of [param cell] on its floor.
func cell_center(cell: Vector3i) -> Vector3:
	return origin + Vector3((cell.x + 0.5) * cell_size.x, cell.y * cell_size.y, (cell.z + 0.5) * cell_size.z)


## Snaps a point to the grid for [param buildable]. Returns
## [code]{"position": Vector3, "cell": Vector3i}[/code], cell = first corner of the footprint.
func snap(point: Vector3, buildable: PKBuildable, angle := 0.0) -> Dictionary:
	var size := turned_cells(buildable, angle)
	var local := point - origin
	var first_x := roundi(local.x / cell_size.x - size.x * 0.5)
	var first_z := roundi(local.z / cell_size.z - size.y * 0.5)
	var level := roundi(local.y / cell_size.y) if snap_height else floori(local.y / cell_size.y + 0.0001)
	var y := origin.y + level * cell_size.y if snap_height else point.y
	var first := Vector3i(first_x, level, first_z)
	return {"position": Vector3(origin.x + (first_x + size.x * 0.5) * cell_size.x, y, origin.z + (first_z + size.y * 0.5) * cell_size.z), "cell": first}


## Position of a piece whose footprint starts at [param first] (see [method snap]).
func position_at(first: Vector3i, buildable: PKBuildable, angle := 0.0) -> Vector3:
	var size := turned_cells(buildable, angle)
	return origin + Vector3((first.x + size.x * 0.5) * cell_size.x, first.y * cell_size.y, (first.z + size.y * 0.5) * cell_size.z)


## Cells covered by a footprint starting at [param first].
func footprint(first: Vector3i, buildable: PKBuildable, angle := 0.0) -> Array[Vector3i]:
	var size := turned_cells(buildable, angle)
	var cells: Array[Vector3i] = []
	for z in size.y:
		for x in size.x:
			cells.append(Vector3i(first.x + x, first.y, first.z + z))
	return cells


## True when the whole footprint is inside [member bounds] (always true without bounds).
func contains(first: Vector3i, buildable: PKBuildable, angle := 0.0) -> bool:
	if bounds.size == Vector2i.ZERO:
		return true
	var size := turned_cells(buildable, angle)
	return bounds.encloses(Rect2i(Vector2i(first.x, first.z), size))
