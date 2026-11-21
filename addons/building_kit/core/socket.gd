class_name PKSocket
extends Resource
## A snap point on a [PKBuildable] (Valheim / Rust style building).
##
## Every socket is a point of the piece with a facing. A placed piece offers its sockets to
## the pieces built next to it. A socket whose [member snaps_to] is not empty is also a way
## for its own piece to attach: the piece is moved and turned so that this socket lands on
## a placed socket whose [member type] is listed.
## [codeblock]
## # A wall: its bottom socket attaches onto foundation edges, facing the same way.
## var bottom := PKSocket.make(&"wall_bottom", Vector3.ZERO, 0.0, [&"foundation_edge", &"wall_top"])
## # Its top socket lets another wall or a roof attach on it.
## var top := PKSocket.make(&"wall_top", Vector3(0, 3, 0), 0.0)
## [/codeblock]
## Positions are local to the piece (X right, Y up, Z forward). Angles are in degrees,
## clockwise seen from above, 0 = facing +Z (the same convention as [member PKPlacement.angle]).

## How the attaching piece turns when this socket lands on a target socket.
enum Facing {
	SAME,      ## This socket faces the same way as the target (a wall on a floor edge).
	OPPOSITE,  ## This socket faces the target (two floors edge to edge).
	ANY,       ## Keep the player's rotation (a post on a corner).
}

## Kind of socket, matched against other sockets' [member snaps_to].
@export var type: StringName = &""
@export var position := Vector3.ZERO
## Facing of the socket, degrees clockwise from above (0 = +Z).
@export var angle := 0.0
## Socket types of placed pieces this socket can attach onto. Empty: it only receives.
@export var snaps_to: Array[StringName] = []
@export var facing := Facing.SAME
## When attached, the player can still turn the piece by this step (180 = flip a wall to
## face the other way, 0 = orientation fixed by the socket).
@export var free_rotation_step := 0.0
## The target piece holds this one up: demolishing it brings this one down. Off for pieces
## that stand on the ground by themselves (a foundation next to a foundation).
@export var holds := true


static func make(p_type: StringName, p_position := Vector3.ZERO, p_angle := 0.0,
		p_snaps_to: Array[StringName] = [], p_facing := Facing.SAME) -> PKSocket:
	var socket := PKSocket.new()
	socket.type = p_type
	socket.position = p_position
	socket.angle = p_angle
	socket.snaps_to = p_snaps_to
	socket.facing = p_facing
	return socket


func can_attach_to(target: PKSocket) -> bool:
	return target != null and snaps_to.has(target.type)
