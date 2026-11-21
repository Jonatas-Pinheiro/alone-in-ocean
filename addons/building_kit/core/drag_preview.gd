class_name PKDragPreview
extends RefCounted
## Several proposed pieces from a drag (a line of fence, a rectangle of floor), from
## [method PKBuilder.drag_preview]. [method PKBuilder.place_many] builds the valid ones,
## paying [member total_cost] at once.

var buildable: PKBuildable
## The blueprint these pieces come from (null for a drag).
var blueprint: PKBlueprint
var previews: Array[PKPreview] = []
## Cost of the valid pieces.
var total_cost: Dictionary = {}
var valid_count := 0
## True when the player can pay for every valid piece.
var affordable := true


func get_invalid_count() -> int:
	return previews.size() - valid_count


## The first reason a piece was refused (&"" when all are valid).
func first_reason() -> StringName:
	for preview in previews:
		if not preview.valid:
			return preview.reason
	return &""
