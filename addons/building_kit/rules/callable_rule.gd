class_name PKCallableRule
extends PKPlacementRule
## A rule written as a function, for quick checks without a new class:
## [codeblock]
## builder.rules.append(PKCallableRule.make(func(context: PKPlacementContext) -> StringName:
##     return &"too_far" if context.placement.position.length() > 50.0 else &""))
## [/codeblock]

var function: Callable


static func make(p_function: Callable) -> PKCallableRule:
	var rule := PKCallableRule.new()
	rule.function = p_function
	return rule


func check(context: PKPlacementContext) -> StringName:
	if not function.is_valid():
		return &""
	return StringName(function.call(context))
