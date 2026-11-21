class_name PKLayout
extends RefCounted
## Every placed piece, with fast queries (overlaps, picking, sockets nearby, counts).
## Held by a [PKBuilder]; change it through the builder so costs, undo and signals follow.

## Size of the buckets of the spatial index, in world units.
var bucket_size := 4.0

var _pieces := {}  # uid -> PKPlacement
var _buckets := {}  # Vector2i -> Array[int]
var _indexed := {}  # uid -> {"keys", "id", "tags", "supports"} as indexed (to unindex)
var _dependents := {}  # uid -> {uid: true} of the pieces that rest on it
var _count_id := {}  # buildable id -> count
var _count_tag := {}  # tag -> count
var _sorted: Array[PKPlacement] = []
var _sorted_dirty := false
var _next_uid := 1


func size() -> int:
	return _pieces.size()


func has(uid: int) -> bool:
	return _pieces.has(uid)


func get_piece(uid: int) -> PKPlacement:
	return _pieces.get(uid)


## Every piece, in the order they were placed (a copy: safe to change the layout while
## going through it).
func get_all() -> Array[PKPlacement]:
	if _sorted_dirty:
		_sorted.clear()
		var uids := _pieces.keys()
		uids.sort()
		for uid in uids:
			_sorted.append(_pieces[uid])
		_sorted_dirty = false
	return _sorted.duplicate()


func get_next_uid() -> int:
	return _next_uid


func set_next_uid(value: int) -> void:
	_next_uid = maxi(value, 1)


## Adds a piece (gives it a uid if it has none) and returns its uid.
func add(placement: PKPlacement) -> int:
	if placement.uid <= 0:
		placement.uid = _next_uid
	_next_uid = maxi(_next_uid, placement.uid + 1)
	_pieces[placement.uid] = placement
	_index(placement)
	_sorted_dirty = true
	return placement.uid


func remove(uid: int) -> PKPlacement:
	var placement: PKPlacement = _pieces.get(uid)
	if placement == null:
		return null
	_unindex(uid)
	_pieces.erase(uid)
	_sorted_dirty = true
	return placement


## Call after changing a placed piece (pose, supports, buildable).
func refresh(uid: int) -> void:
	if _pieces.has(uid):
		_unindex(uid)
		_index(_pieces[uid])


func clear() -> void:
	_pieces.clear()
	_buckets.clear()
	_indexed.clear()
	_dependents.clear()
	_count_id.clear()
	_count_tag.clear()
	_sorted.clear()
	_sorted_dirty = false
	_next_uid = 1


func count_of(buildable_id: StringName) -> int:
	return int(_count_id.get(buildable_id, 0))


func count_tagged(tag: StringName) -> int:
	return int(_count_tag.get(tag, 0))


## Uids of the pieces that rest directly on [param uid].
func dependents_of(uid: int) -> Array[int]:
	var result: Array[int] = []
	for other in _dependents.get(uid, {}):
		result.append(other)
	result.sort()
	return result


## Pieces whose bucket touches [param aabb] (a broad first pass).
func near(aabb: AABB) -> Array[PKPlacement]:
	var found := {}
	for key in _keys_of(aabb):
		for uid in _buckets.get(key, []):
			found[uid] = true
	var pieces: Array[PKPlacement] = []
	var uids := found.keys()
	uids.sort()
	for uid in uids:
		pieces.append(_pieces[uid])
	return pieces


## Pieces of the same [param layer] whose box overlaps [param box] (-1 = any layer).
func overlapping(box: PKBox, layer := -1, ignore: Array = []) -> Array[PKPlacement]:
	var result: Array[PKPlacement] = []
	for placement in near(box.get_aabb()):
		if ignore.has(placement.uid):
			continue
		if layer >= 0 and placement.buildable != null and placement.buildable.layer != layer:
			continue
		if placement.get_box().overlaps(box):
			result.append(placement)
	return result


## The piece at [param point]: the highest one whose box contains it (2D picking).
func piece_at(point: Vector3, margin := 0.0) -> PKPlacement:
	var best: PKPlacement = null
	var best_score := -INF
	for placement in near(AABB(point - Vector3.ONE * 0.01, Vector3.ONE * 0.02)):
		var box := placement.get_box()
		if box.has_point(point, margin) or (box.half.y < 0.6 and _plane_has(box, point, margin)):
			var score := box.get_aabb().end.y + placement.buildable.layer * 100.0 if placement.buildable != null else 0.0
			if score > best_score:
				best_score = score
				best = placement
	return best


## The piece on the top of the pile at [param point], on the ground plane (2D picking).
func piece_at_plane(point: Vector3, margin := 0.0) -> PKPlacement:
	var best: PKPlacement = null
	var best_score := -INF
	var probe := AABB(Vector3(point.x, -100000.0, point.z) - Vector3(0.01, 0, 0.01), Vector3(0.02, 200000.0, 0.02))
	for placement in near(probe):
		var box := placement.get_box()
		if _plane_has(box, point, margin):
			var layer := placement.buildable.layer if placement.buildable != null else 0
			var score := layer * 100000.0 + box.get_aabb().end.y
			if score > best_score:
				best_score = score
				best = placement
	return best


## The first piece hit by a ray, as [code]{"piece": PKPlacement, "distance": float}[/code]
## (empty when nothing is hit).
func raycast(origin: Vector3, direction: Vector3, max_distance := 1000.0) -> Dictionary:
	var best := {}
	var reach := AABB(origin, Vector3.ZERO).expand(origin + direction.normalized() * max_distance)
	for placement in near(reach):
		var distance := placement.get_box().ray_distance(origin, direction.normalized())
		if distance >= 0.0 and distance <= max_distance and (best.is_empty() or distance < best.distance):
			best = {"piece": placement, "distance": distance}
	return best


## Sockets of placed pieces within [param radius] of [param point]:
## [code][{"piece", "socket", "position", "angle"}][/code], nearest first.
func sockets_near(point: Vector3, radius: float, ignore: Array = []) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for placement in near(AABB(point - Vector3.ONE * (radius + 4.0), Vector3.ONE * (radius + 4.0) * 2.0)):
		if ignore.has(placement.uid) or placement.buildable == null:
			continue
		for socket in placement.buildable.sockets:
			var world := placement.to_world(socket.position)
			var distance := world.distance_to(point)
			if distance <= radius:
				found.append({"piece": placement, "socket": socket, "position": world,
					"angle": placement.world_angle(socket.angle), "distance": distance})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.distance < b.distance if not is_equal_approx(a.distance, b.distance) else a.piece.uid < b.piece.uid)
	return found


## Pieces that rest on [param uid] (directly).
func resting_on(uid: int) -> Array[PKPlacement]:
	var result: Array[PKPlacement] = []
	for other in dependents_of(uid):
		if _pieces.has(other):
			result.append(_pieces[other])
	return result


func _plane_has(box: PKBox, point: Vector3, margin: float) -> bool:
	var flat := point
	flat.y = box.center.y
	return box.has_point(flat, margin)


func _index(placement: PKPlacement) -> void:
	var keys := _keys_of(placement.get_box().get_aabb())
	var tags: Array[StringName] = placement.buildable.tags.duplicate() if placement.buildable != null else []
	_indexed[placement.uid] = {"keys": keys, "id": placement.buildable_id, "tags": tags, "supports": placement.supports.duplicate()}
	for key in keys:
		if not _buckets.has(key):
			_buckets[key] = []
		_buckets[key].append(placement.uid)
	_count_id[placement.buildable_id] = count_of(placement.buildable_id) + 1
	for tag in tags:
		_count_tag[tag] = count_tagged(tag) + 1
	for support in placement.supports:
		if not _dependents.has(support):
			_dependents[support] = {}
		_dependents[support][placement.uid] = true


func _unindex(uid: int) -> void:
	var entry: Dictionary = _indexed.get(uid, {})
	if entry.is_empty():
		return
	for key in entry.keys:
		var bucket: Array = _buckets.get(key, [])
		bucket.erase(uid)
		if bucket.is_empty():
			_buckets.erase(key)
	_count_id[entry.id] = count_of(entry.id) - 1
	if _count_id[entry.id] <= 0:
		_count_id.erase(entry.id)
	for tag in entry.tags:
		_count_tag[tag] = count_tagged(tag) - 1
		if _count_tag[tag] <= 0:
			_count_tag.erase(tag)
	for support in entry.supports:
		var set: Dictionary = _dependents.get(support, {})
		set.erase(uid)
		if set.is_empty():
			_dependents.erase(support)
	_indexed.erase(uid)


func _keys_of(aabb: AABB) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	var start := Vector2i(floori(aabb.position.x / bucket_size), floori(aabb.position.z / bucket_size))
	var finish := Vector2i(floori(aabb.end.x / bucket_size), floori(aabb.end.z / bucket_size))
	# Huge boxes (a ray across the map) would touch thousands of buckets: clamp the sweep.
	if (finish.x - start.x) * (finish.y - start.y) > 4096:
		for key: Vector2i in _buckets:
			if key.x >= start.x and key.x <= finish.x and key.y >= start.y and key.y <= finish.y:
				keys.append(key)
		return keys
	for x in range(start.x, finish.x + 1):
		for z in range(start.y, finish.y + 1):
			keys.append(Vector2i(x, z))
	return keys
