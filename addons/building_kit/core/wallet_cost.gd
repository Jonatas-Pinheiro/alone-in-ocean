class_name PKWalletCost
extends PKCost
## Costs paid from a plain dictionary of amounts ({&"gold": 500}): money in a city builder,
## or a quick prototype without an inventory.
## [codeblock]
## var wallet := PKWalletCost.make({&"gold": 500})
## wallet.icons[&"gold"] = preload("res://icons/gold.png")
## builder.cost_handler = wallet
## [/codeblock]

var amounts: Dictionary = {}
## Optional names and icons for the interface, {item_id: String / Texture2D}.
var names: Dictionary = {}
var icons: Dictionary = {}
## Most of each item the wallet can hold, {item_id: max} (refunds beyond are refused).
var limits: Dictionary = {}


static func make(p_amounts := {}) -> PKWalletCost:
	var wallet := PKWalletCost.new()
	wallet.amounts = p_amounts.duplicate()
	return wallet


func is_free() -> bool:
	return false


func count(item_id: StringName) -> int:
	return int(amounts.get(item_id, 0))


func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for item_id in cost:
		amounts[item_id] = count(item_id) - int(cost[item_id])
	if not cost.is_empty():
		changed.emit()
	return true


func can_refund(items: Dictionary) -> bool:
	for item_id in items:
		if limits.has(item_id) and count(item_id) + int(items[item_id]) > int(limits[item_id]):
			return false
	return true


func refund(items: Dictionary) -> bool:
	if not can_refund(items):
		return false
	for item_id in items:
		amounts[item_id] = count(item_id) + int(items[item_id])
	if not items.is_empty():
		changed.emit()
	return true


func refund_partial(items: Dictionary) -> Dictionary:
	var left := {}
	for item_id in items:
		var amount := int(items[item_id])
		var room := amount if not limits.has(item_id) else clampi(int(limits[item_id]) - count(item_id), 0, amount)
		amounts[item_id] = count(item_id) + room
		if room < amount:
			left[item_id] = amount - room
	changed.emit()
	return left


func item_name(item_id: StringName) -> String:
	return PKText.t(names.get(item_id, String(item_id).capitalize()))


func item_icon(item_id: StringName) -> Texture2D:
	return icons.get(item_id)
