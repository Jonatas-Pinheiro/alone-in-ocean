class_name PKResult
extends RefCounted
## What a build action did: [member ok], or the [member reason] it was refused.

var ok := false
var reason: StringName = &""
## Pieces placed, removed or moved by the action.
var placements: Array[PKPlacement] = []
## Items paid ([method PKBuilder.place]) or given back ([method PKBuilder.remove]).
var cost: Dictionary = {}
var refund: Dictionary = {}
## Items that did not fit in the bag (only with [member PKBuilder.refund_overflow]).
var left_behind: Dictionary = {}
## Saves: ids of pieces that no longer exist in the catalog (kept aside, not lost).
var skipped_ids: Array[StringName] = []


static func success(p_placements: Array[PKPlacement] = []) -> PKResult:
	var result := PKResult.new()
	result.ok = true
	result.placements = p_placements
	return result


static func failure(p_reason: StringName) -> PKResult:
	var result := PKResult.new()
	result.reason = p_reason
	return result


func _to_string() -> String:
	return "PKResult(ok)" if ok else "PKResult(%s)" % reason
