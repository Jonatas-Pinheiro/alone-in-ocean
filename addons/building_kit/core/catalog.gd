class_name PKCatalog
extends Resource
## Every [PKBuildable] of your game. Saves find pieces here by id; the catalog panel shows
## them by category, in this order.

@export var buildables: Array[PKBuildable] = []:
	set(value):
		buildables = value
		_index.clear()

## Names of the categories for the interface, {category: "Walls"} (missing: capitalized id).
@export var category_names: Dictionary = {}

var _index := {}


static func make(p_buildables: Array[PKBuildable]) -> PKCatalog:
	var catalog := PKCatalog.new()
	catalog.buildables = p_buildables
	return catalog


func add(buildable: PKBuildable) -> void:
	buildables.append(buildable)
	_index.clear()


func has_buildable(id: StringName) -> bool:
	return get_buildable(id) != null


func get_buildable(id: StringName) -> PKBuildable:
	if _index.size() != buildables.size():
		_index.clear()
		for buildable in buildables:
			if buildable != null and not _index.has(buildable.id):
				_index[buildable.id] = buildable
	return _index.get(id)


## Categories in the order they first appear.
func get_categories() -> Array[StringName]:
	var categories: Array[StringName] = []
	for buildable in buildables:
		if buildable != null and buildable.in_catalog and not categories.has(buildable.category):
			categories.append(buildable.category)
	return categories


func in_category(category: StringName) -> Array[PKBuildable]:
	var result: Array[PKBuildable] = []
	for buildable in buildables:
		if buildable != null and buildable.category == category:
			result.append(buildable)
	return result


func category_title(category: StringName) -> String:
	return PKText.t(category_names.get(category, String(category).capitalize()))


## Problems worth fixing (empty ids, duplicates, sockets that attach to nothing...).
func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	var seen := {}
	var socket_types := {}
	for buildable in buildables:
		if buildable == null:
			issues.append("Empty slot in the catalog.")
			continue
		for socket in buildable.sockets:
			if socket != null:
				socket_types[socket.type] = true
	for buildable in buildables:
		if buildable == null:
			continue
		if buildable.id.is_empty():
			issues.append("A buildable has no id ('%s')." % buildable.display_name)
		elif seen.has(buildable.id):
			issues.append("Two buildables use the id '%s'." % buildable.id)
		seen[buildable.id] = true
		if buildable.cells.x < 1 or buildable.cells.y < 1:
			issues.append("'%s': cells must be at least 1 × 1." % buildable.id)
		if buildable.uses(PKBuildable.Snap.SOCKET):
			var attaches := false
			for socket in buildable.sockets:
				if socket != null and not socket.snaps_to.is_empty():
					attaches = true
					for target in socket.snaps_to:
						if not socket_types.has(target):
							issues.append("'%s': socket type '%s' is not on any piece." % [buildable.id, target])
			if not attaches:
				issues.append("'%s' snaps to sockets but none of its sockets has snaps_to." % buildable.id)
	return issues
