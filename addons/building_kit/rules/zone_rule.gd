class_name PKZoneRule
extends PKPlacementRule
## [member PKBuildable.allowed_zones] and [member PKBuildable.forbidden_zones]: every cell
## under the piece must be in an allowed zone and none in a forbidden one. Zones come from
## [member PKBuilder.zone_provider] (the build nodes read TileMapLayer custom data or GridMap
## item names). Reason: [code]wrong_zone[/code].


func check(context: PKPlacementContext) -> StringName:
	var buildable := context.buildable
	if buildable.allowed_zones.is_empty() and buildable.forbidden_zones.is_empty():
		return &""
	for zone in context.get_zones():
		if buildable.forbidden_zones.has(zone):
			return &"wrong_zone"
		if not buildable.allowed_zones.is_empty() and not buildable.allowed_zones.has(zone):
			return &"wrong_zone"
	return &""
