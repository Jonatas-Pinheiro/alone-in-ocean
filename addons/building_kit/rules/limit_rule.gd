class_name PKLimitRule
extends PKPlacementRule
## [member PKBuildable.max_count]: how many of a piece may exist, plus your own limits per
## tag in [member tag_limits] ({&"workbench": 1}). Reason: [code]limit_reached[/code].

## Most pieces with each tag, {tag: count}.
@export var tag_limits: Dictionary = {}


func check(context: PKPlacementContext) -> StringName:
	var buildable := context.buildable
	var layout := context.get_layout()
	if buildable.max_count >= 0:
		var count := layout.count_of(buildable.id) + _batch_before(context, func(p: PKPlacement) -> bool: return p.buildable_id == buildable.id)
		for uid in context.ignore:
			var ignored := layout.get_piece(uid)
			if ignored != null and ignored.buildable_id == buildable.id:
				count -= 1
		if count >= buildable.max_count:
			return &"limit_reached"
	for tag in tag_limits:
		if not buildable.has_tag(tag):
			continue
		var count := layout.count_tagged(tag) + _batch_before(context, func(p: PKPlacement) -> bool: return p.buildable != null and p.buildable.has_tag(tag))
		for uid in context.ignore:
			var ignored := layout.get_piece(uid)
			if ignored != null and ignored.buildable != null and ignored.buildable.has_tag(tag):
				count -= 1
		if count >= int(tag_limits[tag]):
			return &"limit_reached"
	return &""


# Pieces of the same drag that come before this one count too.
func _batch_before(context: PKPlacementContext, matches: Callable) -> int:
	var count := 0
	for other in context.batch:
		if other == context.placement:
			break
		if matches.call(other):
			count += 1
	return count
