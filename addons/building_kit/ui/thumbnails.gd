class_name PKThumbnails
extends Node
## Renders catalog icons from the pieces' own scenes, at run time, one per frame, for the
## buildables without an [member PKBuildable.icon]. Nothing runs in the editor. Without a
## renderer (headless) no icon is made and the catalog shows the piece's colour instead.

## An icon is ready for [param id].
signal icon_ready(id: StringName, texture: Texture2D)

@export var icon_size := 128
## Direction the camera looks from (3D pieces).
@export var view_direction := Vector3(1.0, 0.9, 1.3)
## Icons rendered together (one small viewport each).
@export var batch_size := 8

var _cache := {}
var _queue: Array[PKBuildable] = []
var _busy := false
var _cell_size := Vector3.ONE


## The icon of [param buildable]: its own icon, a rendered one, or null (queued).
func get_icon(buildable: PKBuildable, cell_size := Vector3.ONE) -> Texture2D:
	if buildable == null:
		return null
	if buildable.icon != null:
		return buildable.icon
	if _cache.has(buildable.id):
		return _cache[buildable.id]
	_cell_size = cell_size
	if not _queue.has(buildable) and DisplayServer.get_name() != "headless":
		_queue.append(buildable)
		if not _busy:
			_busy = true
			_render_next.call_deferred()
	return null


## Renders up to [member batch_size] icons at once (each in its own small viewport).
func _render_next() -> void:
	if _queue.is_empty() or not is_inside_tree():
		_busy = false
		return
	_busy = true
	var batch: Array[PKBuildable] = []
	while not _queue.is_empty() and batch.size() < batch_size:
		batch.append(_queue.pop_front())
	var pending := [batch.size()]
	for buildable in batch:
		_render_one(buildable, pending)
	while pending[0] > 0:
		await get_tree().process_frame
	_render_next()


func _render_one(buildable: PKBuildable, pending: Array) -> void:
	var texture := await _render(buildable)
	if texture != null:
		_cache[buildable.id] = texture
		icon_ready.emit(buildable.id, texture)
	pending[0] -= 1


func _render(buildable: PKBuildable) -> Texture2D:
	if buildable.scene == null:
		return null
	var instance := buildable.scene.instantiate()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(icon_size, icon_size)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# No MSAA on the web: WebGL multisampled render targets cost a lot for a 128 px icon.
	viewport.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_4X
	add_child(viewport)
	if instance is Node3D:
		viewport.own_world_3d = true
		var world := Node3D.new()
		viewport.add_child(world)
		world.add_child(instance)
		_disable(instance)
		var bounds := _bounds(instance)
		var camera := Camera3D.new()
		camera.fov = 30.0
		var radius := maxf(bounds.size.length() * 0.5, 0.1)
		var center := bounds.get_center()
		camera.position = center + view_direction.normalized() * radius / sin(deg_to_rad(15.0)) * 1.05
		world.add_child(camera)
		camera.look_at(center)
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, 35, 0)
		world.add_child(light)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
		environment.environment.ambient_light_energy = 0.7
		world.add_child(environment)
	elif instance is Node2D:
		var holder := Node2D.new()
		viewport.add_child(holder)
		holder.add_child(instance)
		var size := Vector2(buildable.cells) * Vector2(_cell_size.x, _cell_size.z)
		var scale := icon_size * 0.8 / maxf(maxf(size.x, size.y), 1.0)
		holder.scale = Vector2(scale, scale)
		holder.position = Vector2(icon_size, icon_size) * 0.5
	else:
		instance.free()
		viewport.queue_free()
		return null
	for i in 3:
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _disable(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is VisualInstance3D:
			var box: AABB = (current as VisualInstance3D).get_global_transform() * (current as VisualInstance3D).get_aabb()
			result = box if first else result.merge(box)
			first = false
		stack.append_array(current.get_children())
	return result if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
