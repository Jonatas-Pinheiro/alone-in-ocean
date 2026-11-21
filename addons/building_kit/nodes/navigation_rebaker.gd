class_name PKNavigationRebaker
extends Node
## Rebakes a NavigationRegion3D or NavigationRegion2D after building, on a thread and a moment
## later (several pieces in a row cause one bake). The build systems use one when their
## [code]navigation_region[/code] is set. Pieces must be part of the region's source
## geometry: put the build system's [code]pieces_root[/code] under the region (or use groups).

## Emitted when a bake starts and when it is done.
signal bake_started
signal bake_finished

## Seconds to wait after the last change before baking.
@export var delay := 0.4

var region: Node
## Number of bakes started (for tests and statistics).
var bake_count := 0

var _timer := Timer.new()
var _again := false


func _ready() -> void:
	_timer.one_shot = true
	_timer.timeout.connect(_bake)
	add_child(_timer)


## Asks for a bake: it starts [member delay] seconds after the last request.
func request() -> void:
	if region == null or not is_inside_tree():
		return
	_timer.start(maxf(delay, 0.01))


func is_waiting() -> bool:
	return not _timer.is_stopped()


func _bake() -> void:
	if region == null or not is_instance_valid(region):
		return
	if region.has_method(&"is_baking") and region.is_baking():
		_again = true
		return
	if not region.bake_finished.is_connected(_on_baked):
		region.bake_finished.connect(_on_baked)
	bake_count += 1
	bake_started.emit()
	if region is NavigationRegion3D:
		(region as NavigationRegion3D).bake_navigation_mesh(true)
	elif region is NavigationRegion2D:
		(region as NavigationRegion2D).bake_navigation_polygon(true)


func _on_baked() -> void:
	bake_finished.emit()
	if _again:
		_again = false
		request()
