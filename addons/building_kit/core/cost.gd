class_name PKCost
extends RefCounted
## Who pays for the pieces. This base class is free building (everything is affordable);
## use [PKInventoryCost] (Inventory Kit containers), [PKWalletCost] (a plain dictionary of
## amounts) or [PKCallableCost] (your own functions), or extend this class.
##
## A cost is a dictionary [code]{item_id: amount}[/code]. [method pay] and [method refund]
## are all or nothing: when they return false, nothing changed.

## Amounts changed (the catalog greys out what is no longer affordable).
signal changed


## True for free building: nothing is taken, so nothing is given back either.
func is_free() -> bool:
	return true


## True when [param cost] can be paid now.
func can_pay(cost: Dictionary) -> bool:
	for item_id in cost:
		if count(item_id) < int(cost[item_id]):
			return false
	return true


## Takes [param cost]. All or nothing.
func pay(_cost: Dictionary) -> bool:
	return true


## True when [param items] can be given back in full (room in the bag...).
func can_refund(_items: Dictionary) -> bool:
	return true


## Gives [param items] back. All or nothing.
func refund(_items: Dictionary) -> bool:
	return true


## Gives back what fits and returns what did not, {item_id: amount} (used when
## [member PKBuilder.refund_overflow] is on).
func refund_partial(items: Dictionary) -> Dictionary:
	return {} if refund(items) else items.duplicate()


## How many of [param item_id] the player has (INF-like 1 << 30 for free building).
func count(_item_id: StringName) -> int:
	return 1 << 30


## Name of an item for the interface.
func item_name(item_id: StringName) -> String:
	return PKText.t(String(item_id).capitalize())


## Icon of an item for the interface (null: the name is shown).
func item_icon(_item_id: StringName) -> Texture2D:
	return null


## The part of [param cost] that is missing, {item_id: amount}.
func missing(cost: Dictionary) -> Dictionary:
	var result := {}
	for item_id in cost:
		var lack := int(cost[item_id]) - count(item_id)
		if lack > 0:
			result[item_id] = lack
	return result
