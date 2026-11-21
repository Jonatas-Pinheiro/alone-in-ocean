class_name PKBoundsRule
extends PKPlacementRule
## Grid pieces must stay inside [member PKGrid.bounds] (when the grid has bounds), and every
## piece inside [member PKBuilder.world_bounds] (when set). Reason: [code]out_of_bounds[/code].


func check(context: PKPlacementContext) -> StringName:
	var placement := context.placement
	var grid := context.get_grid()
	if placement.on_grid and grid != null and not grid.contains(placement.cell, context.buildable, placement.angle):
		return &"out_of_bounds"
	var bounds := context.builder.world_bounds
	if bounds.size != Vector3.ZERO and not bounds.grow(0.001).encloses(placement.get_box().get_aabb()):
		return &"out_of_bounds"
	return &""
