extends Control

signal close_requested
signal slot_pressed(index: int)

@onready var panel: PanelContainer = $CenterPanel
@onready var grid: GridContainer = $CenterPanel/PanelColumn/SlotsScroll/SlotsGrid
@onready var close_button: Button = $CenterPanel/PanelColumn/Header/CloseButton

var _slots: Array[InventorySlot] = []

func _ready() -> void:
	_slots = [
		$CenterPanel/PanelColumn/SlotsScroll/SlotsGrid/SlotWood,
		$CenterPanel/PanelColumn/SlotsScroll/SlotsGrid/SlotPlastic,
		$CenterPanel/PanelColumn/SlotsScroll/SlotsGrid/SlotScrap,
		$CenterPanel/PanelColumn/SlotsScroll/SlotsGrid/SlotFood,
		$CenterPanel/PanelColumn/SlotsScroll/SlotsGrid/SlotWater,
	]
	for slot: InventorySlot in _slots:
		slot.slot_pressed.connect(_on_slot_pressed)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel()

func set_items(counts: Array[int], selected_slot: int) -> void:
	if _slots.is_empty():
		return
	var names: Array[String] = ["Madeira", "Plástico", "Sucata", "Comida", "Água"]
	for index in range(_slots.size()):
		var amount := counts[index] if index < counts.size() else 0
		_slots[index].set_item_data(names[index], amount, index == selected_slot)

func open_screen() -> void:
	show()
	_layout_panel()
	if not _slots.is_empty():
		_slots[0].grab_focus()

func close_screen() -> void:
	hide()

func _on_slot_pressed(index: int) -> void:
	slot_pressed.emit(index)

func _layout_panel() -> void:
	if panel == null or not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var compact := viewport_size.x < 700.0
	grid.columns = 2 if compact else 5
	var panel_width := minf(920.0, maxf(300.0, viewport_size.x - 24.0))
	var panel_height := minf(540.0, maxf(340.0, viewport_size.y - 24.0))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5
	var slot_width := 132.0 if not compact else minf(150.0, (panel_width - 52.0) * 0.5)
	var slot_height := 124.0 if not compact else 116.0
	for slot: InventorySlot in _slots:
		slot.custom_minimum_size = Vector2(slot_width, slot_height)
