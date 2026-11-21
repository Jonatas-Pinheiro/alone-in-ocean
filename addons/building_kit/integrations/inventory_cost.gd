class_name PKInventoryCost
extends PKCost
## Costs paid from Inventory Kit containers (bag, hotbar...), in one atomic transaction:
## the items are taken from every container at once or not at all, and refunds only happen
## when everything fits (or, with [member PKBuilder.refund_overflow], what does not fit is
## reported so you can drop it in the world). Nothing is ever duplicated or lost.
## [codeblock]
## builder.cost_handler = PKInventoryCost.make([bag, hotbar])
## [/codeblock]
## The kit does not need Inventory Kit to load: this class finds it by name at run time.

## IKContainer instances, taken from in this order; refunds go to the first with room.
var containers: Array = []


static func make(p_containers: Array) -> PKInventoryCost:
	var cost := PKInventoryCost.new()
	cost.containers = p_containers.duplicate()
	for container in cost.containers:
		if container != null and container.has_signal("changed"):
			container.changed.connect(cost.changed.emit)
	return cost


## True when Inventory Kit is in the project.
static func is_available() -> bool:
	return _transaction_script() != null


func is_free() -> bool:
	return false


func count(item_id: StringName) -> int:
	var total := 0
	for container in containers:
		if container != null:
			total += int(container.count(item_id))
	return total


func pay(cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	if not can_pay(cost):
		return false
	var transaction: Object = _new_transaction()
	if transaction == null:
		return false
	for item_id in cost:
		var left := int(cost[item_id])
		for container in containers:
			if left <= 0:
				break
			var take := mini(left, int(container.count(item_id)))
			if take > 0:
				transaction.remove(container, item_id, take)
				left -= take
	return transaction.commit().ok


func can_refund(items: Dictionary) -> bool:
	return _plan_refund(items, false) != null


func refund(items: Dictionary) -> bool:
	if items.is_empty():
		return true
	var transaction: Object = _plan_refund(items, false)
	return transaction != null and transaction.commit().ok


func refund_partial(items: Dictionary) -> Dictionary:
	if refund(items):
		return {}
	var left := {}
	for item_id in items:
		var amount := int(items[item_id])
		for container in containers:
			if amount <= 0:
				break
			var transaction: Object = _new_transaction()
			transaction.add(container, item_id, amount, true)
			var result: Object = transaction.commit()
			if result.ok:
				amount = int(result.remainder)
		if amount > 0:
			left[item_id] = amount
	return left


func item_name(item_id: StringName) -> String:
	var definition: Object = _definition(item_id)
	if definition == null:
		return super.item_name(item_id)
	var title: String = definition.display_name
	return PKText.t(title if not title.is_empty() else String(item_id))


func item_icon(item_id: StringName) -> Texture2D:
	var definition: Object = _definition(item_id)
	return definition.icon if definition != null else null


# Tries every way to fit the refund, item by item, container by container (first that holds
# all of an item), and checks the whole plan on throwaway copies first.
func _plan_refund(items: Dictionary, _partial: bool) -> Object:
	# Fast path: everything in the first container that takes it whole.
	for container in containers:
		var transaction: Object = _new_transaction()
		if transaction == null:
			return null
		for item_id in items:
			transaction.add(container, item_id, int(items[item_id]))
		if not transaction.has_failed():
			return transaction
	# Spread: each item in the first container that fits it.
	var spread: Object = _new_transaction()
	for item_id in items:
		var placed := false
		for container in containers:
			var probe: Object = _new_transaction()
			probe.add(container, item_id, int(items[item_id]))
			if not probe.has_failed():
				spread.add(container, item_id, int(items[item_id]))
				placed = true
				break
		if not placed:
			return null
	return null if spread.has_failed() else spread


func _definition(item_id: StringName) -> Object:
	for container in containers:
		if container != null and container.database != null and container.database.has_item(item_id):
			return container.database.get_item(item_id)
	return null


func _new_transaction() -> Object:
	var script := _transaction_script()
	return script.new() if script != null else null


static var _cached_script: Script


static func _transaction_script() -> Script:
	if _cached_script != null:
		return _cached_script
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == &"IKTransaction":
			_cached_script = load(entry.path)
			return _cached_script
	return null
