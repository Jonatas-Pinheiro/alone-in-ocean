class_name PKNearbyRule
extends PKPlacementRule
## A piece with a tag must be within some cells (a house next to a road, a shop within 6
## cells of a market square). Without [member tag] the rule reads
## [member PKBuildable.needs_nearby_tag] and [member PKBuildable.nearby_cells]; give a tag to
## add more requirements in [member PKBuildable.rules]. The 2D build node draws these areas
## of influence while placing. Reason: [member reason] ([code]needs_nearby[/code]).

## Tag to look for (empty: the buildable's own fields).
@export var tag: StringName = &""
## How far, in cells (1 = touching).
@export var cells := 1
## Reason given when nothing is near enough.
@export var reason: StringName = &"needs_nearby"


static func make(p_tag: StringName, p_cells: int, p_reason: StringName = &"needs_nearby") -> PKNearbyRule:
	var rule := PKNearbyRule.new()
	rule.tag = p_tag
	rule.cells = p_cells
	rule.reason = p_reason
	return rule


## Every "must be near" requirement of [param buildable], as [code][{"tag", "cells"}][/code].
static func requirements_of(buildable: PKBuildable) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if buildable == null:
		return found
	if not buildable.needs_nearby_tag.is_empty():
		found.append({"tag": buildable.needs_nearby_tag, "cells": buildable.nearby_cells})
	for rule in buildable.rules:
		if rule is PKNearbyRule and rule.enabled and not rule.tag.is_empty():
			found.append({"tag": rule.tag, "cells": rule.cells})
	return found


func check(context: PKPlacementContext) -> StringName:
	var wanted := tag if not tag.is_empty() else context.buildable.needs_nearby_tag
	if wanted.is_empty():
		return &""
	var distance := cells if not tag.is_empty() else context.buildable.nearby_cells
	var cell := context.get_grid().cell_size if context.get_grid() != null else Vector3.ONE
	var unit := minf(cell.x, cell.z)
	var reach := (distance - 1) * unit + 0.25 * unit
	var box := context.placement.get_box().grown(reach)
	for piece in context.get_layout().overlapping(box, -1, context.ignore):
		if piece.buildable != null and piece.buildable.has_tag(wanted):
			return &""
	for other in context.batch:
		if other != context.placement and other.buildable != null and other.buildable.has_tag(wanted) and other.get_box().overlaps(box):
			return &""
	return reason
