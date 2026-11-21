class_name PKStabilityRule
extends PKPlacementRule
## With [member PKBuilder.stability_enabled], refuses pieces whose stability would be under
## [member PKBuilder.min_stability] (too far from the ground). Reason: [code]unstable[/code].


func check(context: PKPlacementContext) -> StringName:
	var builder := context.builder
	if not builder.stability_enabled:
		return &""
	return &"unstable" if context.placement.stability < builder.min_stability - 0.0001 else &""
