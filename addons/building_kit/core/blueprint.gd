class_name PKBlueprint
extends Resource
## A group of pieces saved together (a hut, a wall section, a block of houses) to be put down
## again in one go: [method PKBuilder.make_blueprint] makes one from placed pieces,
## [method PKBuilder.blueprint_preview] shows it at the cursor, turned by quarter turns, and
## [method PKBuilder.place_many] builds it for its total cost (one undo step).
## Blueprints are plain data: save them with [method to_data] (JSON) or as .tres files.

@export var title := ""
## One entry per piece, the first one is the anchor:
## [code]{"id", "pos" (from the anchor), "angle", "flip", "up", "supports" (entry indices),
## "parent" (entry index or -1), "grounded", "on_grid"}[/code].
@export var entries: Array[Dictionary] = []


func size() -> int:
	return entries.size()


func is_empty() -> bool:
	return entries.is_empty()


## Total cost of every piece, with the buildables of [param catalog].
func get_cost(catalog: PKCatalog) -> Dictionary:
	var total := {}
	for entry in entries:
		var buildable := catalog.get_buildable(StringName(entry.id)) if catalog != null else null
		if buildable != null:
			total = PKBuildable.add_costs(total, buildable.cost)
	return total


## Ids used by the blueprint that [param catalog] does not have.
func missing_ids(catalog: PKCatalog) -> Array[StringName]:
	var missing: Array[StringName] = []
	for entry in entries:
		var id := StringName(entry.id)
		if not catalog.has_buildable(id) and not missing.has(id):
			missing.append(id)
	return missing


func to_data() -> Dictionary:
	var out := []
	for entry in entries:
		var pos: Vector3 = entry.pos
		var up: Vector3 = entry.get("up", Vector3.UP)
		out.append({"id": String(entry.id), "pos": [pos.x, pos.y, pos.z], "angle": entry.angle,
			"flip": entry.get("flip", false), "up": [up.x, up.y, up.z], "supports": Array(entry.get("supports", [])),
			"parent": entry.get("parent", -1), "grounded": entry.get("grounded", true), "on_grid": entry.get("on_grid", false)})
	return {"format": "building_kit_blueprint", "version": 1, "title": title, "entries": out}


static func from_data(data: Dictionary) -> PKBlueprint:
	var blueprint := PKBlueprint.new()
	if data.get("format", "") != "building_kit_blueprint":
		return blueprint
	blueprint.title = str(data.get("title", ""))
	for raw in data.get("entries", []):
		if not raw is Dictionary:
			continue
		var supports: Array[int] = []
		for support in raw.get("supports", []):
			supports.append(int(support))
		blueprint.entries.append({"id": StringName(str(raw.get("id", ""))), "pos": _vector(raw.get("pos", [])),
			"angle": float(raw.get("angle", 0.0)), "flip": bool(raw.get("flip", false)),
			"up": _vector(raw.get("up", [0, 1, 0])), "supports": supports, "parent": int(raw.get("parent", -1)),
			"grounded": bool(raw.get("grounded", true)), "on_grid": bool(raw.get("on_grid", false))})
	return blueprint


static func _vector(values: Variant) -> Vector3:
	if values is Array and values.size() >= 3:
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO
