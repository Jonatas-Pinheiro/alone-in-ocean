class_name PKAim
extends RefCounted
## Where the player points: a point, the normal of the surface there, and the piece under it
## (0 = the ground or nothing). The build nodes make one from the mouse, the gamepad cursor or
## a touch; your own code can make one for a bot or a level script.

var position := Vector3.ZERO
var normal := Vector3.UP
## Uid of the placed piece under the cursor (0 = terrain).
var hit_uid := 0
## False when the cursor points at nothing (the sky): nothing can be built.
var has_hit := true


static func at(p_position: Vector3, p_normal := Vector3.UP, p_hit_uid := 0) -> PKAim:
	var aim := PKAim.new()
	aim.position = p_position
	aim.normal = p_normal
	aim.hit_uid = p_hit_uid
	return aim


static func nothing() -> PKAim:
	var aim := PKAim.new()
	aim.has_hit = false
	return aim
