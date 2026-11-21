class_name PKText
extends RefCounted
## Every text Building & Placement Kit shows to players goes through here, so it can be
## translated or reworded with Godot's translation system (template:
## [code]addons/building_kit/translations/building_kit.csv[/code], English and French included).

## Player text for each refusal reason. Add your own rules' reasons here:
## [code]PKText.reason_texts[&"too_close_to_fire"] = "Too close to the fire."[/code]
static var reason_texts := {
	&"overlap": "Something is in the way.",
	&"out_of_bounds": "Outside the building area.",
	&"wrong_zone": "You cannot build here.",
	&"too_steep": "The ground is too steep.",
	&"wrong_surface": "This goes on another kind of surface.",
	&"cannot_stack": "This cannot go on top of that.",
	&"needs_foundation": "Needs a foundation.",
	&"limit_reached": "You have built as many of these as you can.",
	&"needs_nearby": "Needs a neighbour of the right kind.",
	&"cannot_afford": "Not enough resources.",
	&"no_room": "No room in your bag for the refund.",
	&"no_socket": "Aim at a matching snap point.",
	&"no_surface": "Aim at the ground.",
	&"supports_others": "Other pieces rest on it.",
	&"not_found": "There is nothing there.",
	&"nothing_to_undo": "Nothing to undo.",
	&"cannot_rotate": "This piece cannot turn.",
	&"no_buildable": "Pick something to build first.",
	&"bad_save": "This save could not be read.",
	&"save_too_new": "This save comes from a newer version.",
	&"too_many": "That is too many pieces at once.",
	&"unstable": "Too far from a support: it would fall.",
	&"no_upgrade": "This piece cannot be upgraded.",
	&"indestructible": "This piece cannot be damaged.",
	&"not_damaged": "Nothing to repair.",
	&"empty_blueprint": "Select pieces first.",
}

## Names of the modes, for the mode bar.
static var mode_names := {
	0: "Build",
	1: "Move",
	2: "Demolish",
	3: "Select",
	4: "Upgrade",
	5: "Repair",
}


static func t(text: String) -> String:
	if text.is_empty():
		return text
	return String(TranslationServer.translate(text))


## What to tell the player about a refusal ("" for none).
static func reason(id: StringName) -> String:
	if id.is_empty():
		return ""
	return t(reason_texts.get(id, String(id).capitalize()))


static func mode_name(mode: int) -> String:
	return t(mode_names.get(mode, "Build"))


## "4 Wood log, 2 Stone" with the names of [param cost_handler] ("Free" for nothing).
static func cost_text(cost: Dictionary, cost_handler: PKCost) -> String:
	if cost.is_empty():
		return t("Free")
	var parts := PackedStringArray()
	for item_id in cost:
		var name := cost_handler.item_name(item_id) if cost_handler != null else String(item_id)
		parts.append("%d %s" % [int(cost[item_id]), name])
	return ", ".join(parts)
