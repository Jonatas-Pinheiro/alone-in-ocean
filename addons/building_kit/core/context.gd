class_name PKPlacementContext
extends RefCounted
## Everything a [PKPlacementRule] needs to judge one proposed piece.

var builder: PKBuilder
var buildable: PKBuildable
## The proposed pose (not placed yet: uid 0, or the uid of the piece being moved).
var placement: PKPlacement
## Normal of the surface under the cursor (UP on a grid or in 2D).
var normal := Vector3.UP
## True when the pose comes from a socket ([member PKPlacement.parent_uid] is the piece).
var snapped_to_socket := false
## Uids the rules ignore (the piece being moved).
var ignore: Array = []
## The other pieces proposed in the same drag (they must not overlap each other either).
var batch: Array[PKPlacement] = []


func get_layout() -> PKLayout:
	return builder.layout


func get_grid() -> PKGrid:
	return builder.grid


## Zones under the footprint (one per covered cell on a grid, one in free placement).
func get_zones() -> Array[StringName]:
	return builder.zones_under(placement)


## The pieces this one rests on or hangs from (computed by the builder).
func get_supports() -> Array[PKPlacement]:
	var result: Array[PKPlacement] = []
	for uid in placement.supports:
		var support := builder.layout.get_piece(uid)
		if support == null:
			for other in batch:  # a piece of the same blueprint
				if other.uid == uid:
					support = other
		if support != null:
			result.append(support)
	return result
