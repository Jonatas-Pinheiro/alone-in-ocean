class_name PKPreview
extends RefCounted
## A proposed piece: where it would go and whether it may be built ([method PKBuilder.preview]).
## The ghost is drawn from it, green when [member valid], red otherwise.

var placement: PKPlacement
var valid := false
## Why it may not be built (&"" when valid). See [method PKText.reason].
var reason: StringName = &""
var cost: Dictionary = {}
var normal := Vector3.UP
var snapped_to_socket := false
## The socket it snapped to: {"piece", "socket", "position", "angle"} (empty if none).
var target_socket: Dictionary = {}
## Uids ignored by the checks (the piece being moved).
var ignore: Array = []


func get_buildable() -> PKBuildable:
	return placement.buildable if placement != null else null
