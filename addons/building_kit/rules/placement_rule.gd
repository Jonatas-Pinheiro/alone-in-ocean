class_name PKPlacementRule
extends Resource
## Base class of placement rules. Override [method check] and return "" when the piece may
## be built there, or a reason id ([code]&"too_close_to_fire"[/code]) when it may not.
## The reason travels in [signal PKBuilder.rejected] and is shown through [method PKText.reason].
## [codeblock]
## class_name NotInWaterRule extends PKPlacementRule
## func check(context: PKPlacementContext) -> StringName:
##     return &"in_water" if context.placement.position.y < 0.0 else &""
## [/codeblock]
## Add your rule to [member PKBuilder.rules] (every piece) or [member PKBuildable.rules] (one piece).

## Turn the rule off without removing it.
@export var enabled := true


func check(_context: PKPlacementContext) -> StringName:
	return &""
