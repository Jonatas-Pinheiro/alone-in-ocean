extends CanvasLayer

var _root: Control
var _player: SurvivalPlayer
var _hunger_bar: ProgressBar
var _thirst_bar: ProgressBar
var _health_bar: ProgressBar
var _inventory_label: Label
var _hint_label: Label


func _ready() -> void:
	layer = 5
	_build_interface()


func _process(_delta: float) -> void:
	var local_id := multiplayer.get_unique_id()
	if not is_instance_valid(_player) or _player.owner_peer_id != local_id:
		_player = _find_local_player(local_id)

	_root.visible = _player != null
	if _player == null:
		return

	_hunger_bar.value = _player.hunger
	_thirst_bar.value = _player.thirst
	_health_bar.value = _player.health
	_inventory_label.text = "Madeira %d   Plástico %d   Metal %d\nComida %d   Água %d" % [
		_player.wood_count,
		_player.plastic_count,
		_player.scrap_count,
		_player.food_count,
		_player.water_count,
	]
	_hint_label.text = "E: coletar    F: comer    G: beber"


func _find_local_player(peer_id: int) -> SurvivalPlayer:
	for node in get_tree().get_nodes_in_group("players"):
		if node is SurvivalPlayer and node.owner_peer_id == peer_id:
			return node as SurvivalPlayer
	return null


func _build_interface() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 44.0)
	panel.custom_minimum_size = Vector2(300.0, 0.0)
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)

	_hunger_bar = _make_bar(column, "Fome")
	_thirst_bar = _make_bar(column, "Sede")
	_health_bar = _make_bar(column, "Saúde")

	_inventory_label = Label.new()
	_inventory_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_inventory_label)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_hint_label)


func _make_bar(parent: VBoxContainer, title: String) -> ProgressBar:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 58.0
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(210.0, 16.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	return bar
