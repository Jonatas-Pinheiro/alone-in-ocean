class_name PKCallableCost
extends PKCost
## Costs handled by your own functions: plug the kit into any economy without writing a class.
## [codeblock]
## var cost := PKCallableCost.new()
## cost.count_function = func(item_id): return my_game.resources.get(item_id, 0)
## cost.pay_function = func(items): return my_game.spend(items)       # true when paid
## cost.refund_function = func(items): my_game.give(items); return true
## builder.cost_handler = cost
## [/codeblock]
## Call [method notify_changed] when amounts change outside the kit, so the catalog updates.

## func(item_id: StringName) -> int
var count_function: Callable
## func(cost: Dictionary) -> bool. Must take all or nothing.
var pay_function: Callable
## func(items: Dictionary) -> bool. Must give all or nothing.
var refund_function: Callable
## Optional: func(item_id) -> String and func(item_id) -> Texture2D.
var name_function: Callable
var icon_function: Callable


func is_free() -> bool:
	return false


func count(item_id: StringName) -> int:
	return int(count_function.call(item_id)) if count_function.is_valid() else 0


func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	var done: bool = bool(pay_function.call(cost)) if pay_function.is_valid() else true
	if done and not cost.is_empty():
		changed.emit()
	return done


func refund(items: Dictionary) -> bool:
	var done: bool = bool(refund_function.call(items)) if refund_function.is_valid() else true
	if done and not items.is_empty():
		changed.emit()
	return done


func item_name(item_id: StringName) -> String:
	return String(name_function.call(item_id)) if name_function.is_valid() else super.item_name(item_id)


func item_icon(item_id: StringName) -> Texture2D:
	return icon_function.call(item_id) if icon_function.is_valid() else null


func notify_changed() -> void:
	changed.emit()
