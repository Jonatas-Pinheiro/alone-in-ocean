class_name PKAutotile
extends RefCounted
## Autotiling for pieces that join their neighbours (roads, fences, pipes, walls on a grid):
## which of the four neighbours connect, and which shape and turn to show.
## The build nodes do it by themselves for buildables with [member PKBuildable.variant_scenes];
## call it yourself to draw shapes your own way.
## [codeblock]
## var mask := PKAutotile.mask_of(builder.layout, placement, &"road", 32.0)
## var shape := PKAutotile.shape_of(mask)   # {"shape": "corner", "angle": 90.0}
## [/codeblock]
## Bits of the mask: 1 = +X (east), 2 = +Z (south, 2D down), 4 = -X, 8 = -Z.
## Canonical shapes (angle 0): end towards +X, straight along X, corner +X and +Z,
## t +X, +Z and -X, cross all four. [code]angle[/code] turns them clockwise seen from above,
## like [member PKPlacement.angle].

const EAST := 1
const SOUTH := 2
const WEST := 4
const NORTH := 8
const SHAPES := ["single", "end", "straight", "corner", "t", "cross"]

const _CANONICAL := {"single": 0, "end": 1, "straight": 5, "corner": 3, "t": 7, "cross": 15}
const _DIRECTIONS := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]


## Which neighbours of [param placement], [param step] world units away, carry [param tag].
static func mask_of(layout: PKLayout, placement: PKPlacement, tag: StringName, step: float) -> int:
	var mask := 0
	var center := placement.get_box().center
	for side in 4:
		var point: Vector3 = center + _DIRECTIONS[side] * step
		var other := layout.piece_at_plane(point)
		if other != null and other != placement and other.buildable != null and other.buildable.has_tag(tag):
			mask |= 1 << side
	return mask


## The shape name and the turn (degrees) that draw [param mask].
static func shape_of(mask: int) -> Dictionary:
	var count := 0
	for side in 4:
		if mask & (1 << side):
			count += 1
	var shape := "single"
	match count:
		1:
			shape = "end"
		2:
			shape = "straight" if mask == 5 or mask == 10 else "corner"
		3:
			shape = "t"
		4:
			shape = "cross"
	var canonical: int = _CANONICAL[shape]
	for turn in 4:
		if rotate_mask(canonical, turn) == mask:
			return {"shape": shape, "angle": turn * 90.0}
	return {"shape": shape, "angle": 0.0}


## Turns a mask by [param quarter_turns] clockwise (east goes south).
static func rotate_mask(mask: int, quarter_turns: int) -> int:
	var turns := posmod(quarter_turns, 4)
	return ((mask << turns) | (mask >> (4 - turns))) & 15
