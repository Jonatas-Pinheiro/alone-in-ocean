class_name PKSlopeRule
extends PKPlacementRule
## Floor pieces refuse ground steeper than [member PKBuildable.max_slope_degrees].
## Pieces snapped to a socket or aligned to the surface are not concerned.
## Reason: [code]too_steep[/code].


func check(context: PKPlacementContext) -> StringName:
	var buildable := context.buildable
	if context.snapped_to_socket or buildable.align_to_normal or buildable.surface != PKBuildable.Surface.FLOOR:
		return &""
	var slope := rad_to_deg(context.normal.normalized().angle_to(Vector3.UP))
	return &"too_steep" if slope > buildable.max_slope_degrees + 0.01 else &""
