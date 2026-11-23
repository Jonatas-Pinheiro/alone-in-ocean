extends Button
class_name InventorySlot

signal slot_pressed(index: int)

@export_range(0, 4, 1) var slot_index := 0

@onready var key_label: Label = $Content/TopRow/KeyLabel
@onready var glyph_label: Label = $Content/GlyphLabel
@onready var item_label: Label = $Content/ItemLabel
@onready var quantity_label: Label = $Content/BottomRow/QuantityLabel
@onready var action_label: Label = $Content/BottomRow/ActionLabel

const ITEM_GLYPHS: Array[String] = ["M", "P", "S", "F", "H₂O"]
const KEY_LABELS: Array[String] = ["Z", "X", "C", "F", "G"]
const ACCENT_COLORS: Array[Color] = [
	Color("#c58a4b"),
	Color("#54b7c8"),
	Color("#9ba6ae"),
	Color("#e58b50"),
	Color("#5d9fe8"),
]

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	for control: Control in [key_label, glyph_label, item_label, quantity_label, action_label]:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pressed.connect(func() -> void: slot_pressed.emit(slot_index))
	_update_style(false)

func set_item_data(item_name: String, count: int, selected: bool) -> void:
	if not is_node_ready():
		return
	var safe_index := clampi(slot_index, 0, 4)
	key_label.text = KEY_LABELS[safe_index]
	glyph_label.text = ITEM_GLYPHS[safe_index]
	glyph_label.add_theme_color_override("font_color", ACCENT_COLORS[safe_index])
	item_label.text = item_name
	quantity_label.text = "×%02d" % maxi(0, count)
	if safe_index == 3:
		action_label.text = "F · comer"
	elif safe_index == 4:
		action_label.text = "G · beber"
	else:
		action_label.text = "Selecionar"
	tooltip_text = "%s: %d / 99" % [item_name, maxi(0, count)]
	_update_style(selected)

func _update_style(selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#17313b") if selected else Color("#10242c")
	style.border_color = Color("#80d5e6") if selected else Color("#385762")
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_stylebox_override("focus", style)
