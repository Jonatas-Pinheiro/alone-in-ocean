class_name PKOverlapRule
extends PKPlacementRule
## Pieces of the same layer must not overlap (touching is fine). Reason: [code]overlap[/code].

## Boxes are shrunk by this much before the test, so pieces that only touch are accepted.
@export var tolerance := 0.02


func check(context: PKPlacementContext) -> StringName:
	var box := context.placement.get_box().grown(-tolerance)
	var layer := context.buildable.layer
	if not context.get_layout().overlapping(box, layer, context.ignore).is_empty():
		return &"overlap"
	for other in context.batch:
		if other == context.placement or other.buildable == null or other.buildable.layer != layer:
			continue
		if other.get_box().overlaps(box):
			return &"overlap"
	return &""
