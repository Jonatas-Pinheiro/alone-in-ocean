class_name PKSupportRule
extends PKPlacementRule
## [member PKBuildable.needs_foundation]: the piece must rest on, or snap to, a piece tagged
## with one of [member PKBuildable.foundation_tags], or a piece that itself needed one (a wall
## on a wall on a foundation). Reason: [code]needs_foundation[/code].


func check(context: PKPlacementContext) -> StringName:
	var buildable := context.buildable
	if not buildable.needs_foundation:
		return &""
	for support in context.get_supports():
		if support.buildable == null:
			continue
		if support.buildable.needs_foundation:
			return &""
		for tag in buildable.foundation_tags:
			if support.buildable.has_tag(tag):
				return &""
	return &"needs_foundation"
