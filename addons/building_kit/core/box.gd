class_name PKBox
extends RefCounted
## An oriented box in world space: the volume a placed piece takes, used for overlaps,
## supports and picking. Built by [method PKPlacement.get_box].

var center := Vector3.ZERO
## Orthonormal axes of the box (no scale).
var basis := Basis.IDENTITY
## Half size along each axis.
var half := Vector3(0.5, 0.5, 0.5)


static func make(p_center: Vector3, p_half: Vector3, p_basis := Basis.IDENTITY) -> PKBox:
	var box := PKBox.new()
	box.center = p_center
	box.half = p_half.abs()
	box.basis = p_basis.orthonormalized()
	return box


## A copy grown by [param amount] on every side (negative shrinks, never below 0).
func grown(amount: float) -> PKBox:
	return PKBox.make(center, (half + Vector3.ONE * amount).max(Vector3.ZERO), basis)


func get_aabb() -> AABB:
	var extent := Vector3.ZERO
	for axis in 3:
		var direction: Vector3 = basis[axis]
		extent += direction.abs() * half[axis]
	return AABB(center - extent, extent * 2.0)


func has_point(point: Vector3, margin := 0.0) -> bool:
	var local := point - center
	for axis in 3:
		if absf(local.dot(basis[axis])) > half[axis] + margin:
			return false
	return true


## Distance along the ray to the box, or -1 when the ray misses it.
func ray_distance(origin: Vector3, direction: Vector3) -> float:
	var near := -INF
	var far := INF
	var delta := center - origin
	for axis in 3:
		var normal: Vector3 = basis[axis]
		var e := normal.dot(delta)
		var f := normal.dot(direction)
		if absf(f) > 0.000001:
			var t1 := (e + half[axis]) / f
			var t2 := (e - half[axis]) / f
			if t1 > t2:
				var swap := t1
				t1 = t2
				t2 = swap
			near = maxf(near, t1)
			far = minf(far, t2)
			if near > far or far < 0.0:
				return -1.0
		elif -e - half[axis] > 0.0 or -e + half[axis] < 0.0:
			return -1.0
	return near if near >= 0.0 else far


## True when the two boxes overlap by more than a hair (touching faces do not count).
## Separating axis test on the 15 axes of two oriented boxes.
func overlaps(other: PKBox, epsilon := 0.001) -> bool:
	var a := [basis.x, basis.y, basis.z]
	var b := [other.basis.x, other.basis.y, other.basis.z]
	var t := other.center - center
	var rotation := []
	var absolute := []
	for i in 3:
		var row := []
		var abs_row := []
		for j in 3:
			var value: float = (a[i] as Vector3).dot(b[j])
			row.append(value)
			abs_row.append(absf(value) + 0.000001)
		rotation.append(row)
		absolute.append(abs_row)
	var tl := Vector3(t.dot(a[0]), t.dot(a[1]), t.dot(a[2]))
	var ha := half
	var hb := other.half
	for i in 3:
		var ra: float = ha[i]
		var rb: float = hb[0] * absolute[i][0] + hb[1] * absolute[i][1] + hb[2] * absolute[i][2]
		if absf(tl[i]) >= ra + rb - epsilon:
			return false
	for j in 3:
		var ra: float = ha[0] * absolute[0][j] + ha[1] * absolute[1][j] + ha[2] * absolute[2][j]
		var rb: float = hb[j]
		var distance: float = absf(tl[0] * rotation[0][j] + tl[1] * rotation[1][j] + tl[2] * rotation[2][j])
		if distance >= ra + rb - epsilon:
			return false
	for i in 3:
		for j in 3:
			var i1 := (i + 1) % 3
			var i2 := (i + 2) % 3
			var j1 := (j + 1) % 3
			var j2 := (j + 2) % 3
			var ra: float = ha[i1] * absolute[i2][j] + ha[i2] * absolute[i1][j]
			var rb: float = hb[j1] * absolute[i][j2] + hb[j2] * absolute[i][j1]
			var distance: float = absf(tl[i2] * rotation[i1][j] - tl[i1] * rotation[i2][j])
			# Cross axes of near-parallel edges are degenerate: skip them.
			var length := ((a[i] as Vector3).cross(b[j])).length()
			if length < 0.0001:
				continue
			if distance >= ra + rb - epsilon * length:
				return false
	return true
