class_name PKSurfaceRule
extends PKPlacementRule
## The kind of surface ([member PKBuildable.surface]: floor, wall, ceiling) and stacking
## ([member PKBuildable.stackable], [member PKBuildable.supports_on_top]).
## Reasons: [code]wrong_surface[/code], [code]cannot_stack[/code].

## Normals closer than this to up are floors, to down ceilings, the rest walls (degrees).
@export var floor_angle := 45.0


func check(context: PKPlacementContext) -> StringName:
	var buildable := context.buildable
	if context.snapped_to_socket:
		return &""
	var slope := rad_to_deg(context.normal.normalized().angle_to(Vector3.UP))
	match buildable.surface:
		PKBuildable.Surface.FLOOR:
			if slope > 90.0:
				return &"wrong_surface"
		PKBuildable.Surface.WALL:
			if slope <= floor_angle or slope >= 180.0 - floor_angle:
				return &"wrong_surface"
		PKBuildable.Surface.CEILING:
			if slope < 180.0 - floor_angle:
				return &"wrong_surface"
	for support in context.get_supports():
		if not buildable.stackable or (support.buildable != null and not support.buildable.supports_on_top):
			return &"cannot_stack"
	return &""
