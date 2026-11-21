class_name PKCatalogPanel
extends PanelContainer
## The build menu: a tab per category, a button per piece with its icon and cost. Pieces the
## player cannot afford (or has built as many of as allowed) are greyed out. Click or tap a
## piece to pick it; on a gamepad, D-pad left / right picks the previous / next piece and
## D-pad down the next category (keyboard: [ ] and Tab).
## [codeblock]
## var panel := PKCatalogPanel.new()
## add_child(panel)
## panel.bind(build_system)   # a PKBuildSystem2D or PKBuildSystem3D
## [/codeblock]

## The player picked a piece in the panel.
signal piece_chosen(buildable: PKBuildable)
## The pointer or the selection is on a piece (for an info panel).
signal piece_hovered(buildable: PKBuildable)
## The player picked a blueprint in the Blueprints tab.
signal blueprint_chosen(blueprint: PKBlueprint)

## Key of the Blueprints tab in [member _categories].
const BLUEPRINTS := &"__blueprints__"

@export var button_size := Vector2(96, 104)
## Show the "All" tab first.
@export var show_all_tab := false

var system: Node
var thumbnails := PKThumbnails.new()

var _tabs := TabBar.new()
var _row := HBoxContainer.new()
var _scroll := ScrollContainer.new()
var _buttons := {}  # id -> Button
var _categories: Array[StringName] = []
var _category: StringName = &""
var _all := false


func _init() -> void:
	name = "PKCatalogPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.tab_changed.connect(_on_tab_changed)
	_tabs.clip_tabs = false
	box.add_child(_tabs)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, button_size.y + 8)
	box.add_child(_scroll)
	_row.add_theme_constant_override(&"separation", 8)
	_scroll.add_child(_row)
	add_child(thumbnails)
	thumbnails.icon_ready.connect(_on_icon_ready)


## Connects the panel to a build system (2D or 3D) and fills it.
func bind(p_system: Node) -> void:
	system = p_system
	system.buildable_changed.connect(func(_b: PKBuildable) -> void: _sync_selection())
	system.costs_changed.connect(refresh_states)
	system.placed.connect(func(_p: PKPlacement, _n: Node) -> void: refresh_states())
	system.removed.connect(func(_p: PKPlacement, _r: Dictionary) -> void: refresh_states())
	system.controller.blueprints_changed.connect(_on_blueprints_changed)
	system.blueprint_changed.connect(func(_b: PKBlueprint) -> void: _sync_selection())
	rebuild()


## Rebuilds the tabs and buttons (after changing the catalog).
func rebuild() -> void:
	if system == null:
		return
	var catalog: PKCatalog = system.builder.catalog
	_categories = catalog.get_categories()
	_tabs.clear_tabs()
	if show_all_tab:
		_tabs.add_tab(PKText.t("All"))
	for category in _categories:
		_tabs.add_tab(catalog.category_title(category))
	if not system.controller.blueprints.is_empty():
		_categories.append(BLUEPRINTS)
		_tabs.add_tab(PKText.t("Blueprints"))
	_all = show_all_tab
	_category = _categories[0] if not _categories.is_empty() and not show_all_tab else &""
	if _tabs.tab_count > 0:
		_tabs.current_tab = 0
	_fill()


func get_button(id: StringName) -> Button:
	return _buttons.get(id)


func get_current_category() -> StringName:
	return _category


func _on_tab_changed(index: int) -> void:
	_all = show_all_tab and index == 0
	var offset := 1 if show_all_tab else 0
	_category = _categories[index - offset] if not _all and index - offset < _categories.size() and index - offset >= 0 else &""
	_fill()


func _fill() -> void:
	for child in _row.get_children():
		child.queue_free()
	_buttons.clear()
	var catalog: PKCatalog = system.builder.catalog
	if _category == BLUEPRINTS:
		for blueprint in system.controller.blueprints:
			var button := _make_blueprint_button(blueprint)
			_row.add_child(button)
			_buttons[_blueprint_key(blueprint)] = button
		refresh_states()
		_sync_selection()
		return
	var pieces: Array[PKBuildable] = catalog.buildables if _all else catalog.in_category(_category)
	for buildable in pieces:
		if buildable == null or not buildable.in_catalog:
			continue
		var button := _make_button(buildable)
		_row.add_child(button)
		_buttons[buildable.id] = button
	refresh_states()
	_sync_selection()


func _make_button(buildable: PKBuildable) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = button_size
	button.tooltip_text = _tooltip(buildable)
	button.pressed.connect(func() -> void:
		system.select_buildable(buildable)
		piece_chosen.emit(buildable))
	button.mouse_entered.connect(func() -> void: piece_hovered.emit(buildable))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.add_theme_constant_override(&"separation", 2)
	button.add_child(box)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.texture = thumbnails.get_icon(buildable, system.builder.grid.cell_size)
	if icon.texture == null:
		icon.texture = _swatch(buildable.color)
	box.add_child(icon)
	var title := Label.new()
	title.text = buildable.get_title()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 12)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var cost_row := HBoxContainer.new()
	cost_row.name = "Cost"
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_theme_constant_override(&"separation", 3)
	box.add_child(cost_row)
	return button


## A button of the Blueprints tab: title, number of pieces and total cost.
func _make_blueprint_button(blueprint: PKBlueprint) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(button_size.x * 1.25, button_size.y)
	button.set_meta(&"blueprint", blueprint)
	button.pressed.connect(func() -> void:
		system.select_blueprint(blueprint)
		blueprint_chosen.emit(blueprint))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	button.add_child(box)
	var icon := TextureRect.new()
	icon.texture = _blueprint_icon()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var title := Label.new()
	title.text = "%s (%d)" % [blueprint.title, blueprint.size()]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 12)
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var cost_row := HBoxContainer.new()
	cost_row.name = "Cost"
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cost_row)
	return button


static func _blueprint_key(blueprint: PKBlueprint) -> StringName:
	return StringName("__bp_%d" % blueprint.get_instance_id())


static var _blueprint_texture: Texture2D


static func _blueprint_icon() -> Texture2D:
	if _blueprint_texture != null:
		return _blueprint_texture
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.16, 0.36, 0.62))
	for i in range(4, 48, 8):
		image.fill_rect(Rect2i(i, 0, 1, 48), Color(0.4, 0.6, 0.85))
		image.fill_rect(Rect2i(0, i, 48, 1), Color(0.4, 0.6, 0.85))
	image.fill_rect(Rect2i(10, 18, 28, 20), Color(0.92, 0.95, 1.0))
	image.fill_rect(Rect2i(12, 20, 24, 16), Color(0.16, 0.36, 0.62))
	image.fill_rect(Rect2i(20, 26, 8, 10), Color(0.92, 0.95, 1.0))
	_blueprint_texture = ImageTexture.create_from_image(image)
	return _blueprint_texture


func _on_blueprints_changed() -> void:
	var showing := _category
	rebuild()
	if showing == BLUEPRINTS or system.controller.blueprints.size() == 1:
		var index := _categories.find(BLUEPRINTS)
		if index >= 0:
			_tabs.current_tab = index + (1 if show_all_tab else 0)


## Greys out what the player cannot build now and updates the cost colours.
func refresh_states() -> void:
	if system == null:
		return
	var builder: PKBuilder = system.builder
	for id in _buttons:
		var blueprint_button: Button = _buttons[id]
		if is_instance_valid(blueprint_button) and blueprint_button.has_meta(&"blueprint"):
			var blueprint: PKBlueprint = blueprint_button.get_meta(&"blueprint")
			var total := blueprint.get_cost(builder.catalog)
			var affordable := builder.cost_handler.can_pay(total)
			blueprint_button.modulate = Color.WHITE if affordable else Color(0.62, 0.62, 0.66, 0.6)
			blueprint_button.set_meta(&"available", affordable)
			blueprint_button.tooltip_text = "%s
%s %s" % [blueprint.title, PKText.t("Cost:"), PKText.cost_text(total, builder.cost_handler)]
			_fill_cost_dict(blueprint_button.find_child("Cost", true, false), total, builder)
			continue
		var buildable := builder.catalog.get_buildable(id)
		var button: Button = _buttons[id]
		if buildable == null or not is_instance_valid(button):
			continue
		var affordable := builder.can_afford(buildable)
		var capped := buildable.max_count >= 0 and builder.layout.count_of(id) >= buildable.max_count
		button.modulate = Color.WHITE if affordable and not capped else Color(0.62, 0.62, 0.66, 0.6)
		button.set_meta(&"available", affordable and not capped)
		button.tooltip_text = _tooltip(buildable)
		_fill_cost(button.find_child("Cost", true, false), buildable, builder)


func is_available(id: StringName) -> bool:
	var button := get_button(id)
	return button != null and bool(button.get_meta(&"available", true))


func _fill_cost(row: HBoxContainer, buildable: PKBuildable, builder: PKBuilder) -> void:
	_fill_cost_dict(row, buildable.cost, builder)


func _fill_cost_dict(row: HBoxContainer, cost: Dictionary, builder: PKBuilder) -> void:
	if row == null:
		return
	for child in row.get_children():
		child.queue_free()
	if cost.is_empty():
		var free := Label.new()
		free.text = PKText.t("Free")
		free.add_theme_font_size_override(&"font_size", 12)
		free.add_theme_color_override(&"font_color", PKUIStyle.muted_text)
		free.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(free)
		return
	var handler: PKCost = builder.cost_handler
	for item_id in cost:
		var amount := int(cost[item_id])
		var texture := handler.item_icon(item_id)
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(16, 16)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)
		var label := Label.new()
		label.text = str(amount) if texture != null else "%d %s" % [amount, handler.item_name(item_id)]
		label.add_theme_font_size_override(&"font_size", 12)
		label.add_theme_color_override(&"font_color", PKUIStyle.text_color if handler.count(item_id) >= amount else PKUIStyle.bad)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)


func _tooltip(buildable: PKBuildable) -> String:
	var builder: PKBuilder = system.builder
	var lines := PackedStringArray([buildable.get_title()])
	if not buildable.description.is_empty():
		lines.append(PKText.t(buildable.description))
	lines.append("%s %s" % [PKText.t("Cost:"), PKText.cost_text(buildable.cost, builder.cost_handler)])
	if not buildable.cost.is_empty():
		lines.append(PKText.t("Demolish refund: %d%%") % roundi(buildable.refund_percent))
	if buildable.max_count >= 0:
		lines.append(PKText.t("Built: %d / %d") % [builder.layout.count_of(buildable.id), buildable.max_count])
	var missing := builder.cost_handler.missing(buildable.cost)
	if not missing.is_empty():
		lines.append("%s %s" % [PKText.t("Missing:"), PKText.cost_text(missing, builder.cost_handler)])
	return "\n".join(lines)


func _sync_selection() -> void:
	if system == null:
		return
	var current_blueprint: PKBlueprint = system.controller.blueprint
	if current_blueprint != null:
		for id in _buttons:
			var item: Button = _buttons[id]
			if is_instance_valid(item):
				item.set_pressed_no_signal(item.has_meta(&"blueprint") and item.get_meta(&"blueprint") == current_blueprint)
		return
	var current: PKBuildable = system.controller.buildable
	if current != null and current.category != _category and not _all:
		var index := _categories.find(current.category)
		if index >= 0:
			_tabs.current_tab = index + (1 if show_all_tab else 0)  # refills through tab_changed
	for id in _buttons:
		var button: Button = _buttons[id]
		if is_instance_valid(button):
			button.set_pressed_no_signal(current != null and current.id == id)
	if current != null:
		piece_hovered.emit(current)


## A small square of the piece's colour while (or when) no icon can be rendered.
static func _swatch(color: Color) -> Texture2D:
	var image := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(8, 8, 24, 24), color.darkened(0.35))
	image.fill_rect(Rect2i(10, 10, 20, 20), color)
	return ImageTexture.create_from_image(image)


func _on_icon_ready(id: StringName, texture: Texture2D) -> void:
	var button: Button = _buttons.get(id)
	if button == null or not is_instance_valid(button):
		return
	var icon: TextureRect = button.find_child("Icon", true, false)
	if icon != null:
		icon.texture = texture
