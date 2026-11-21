extends PKBuildSystem3D
class_name NetworkedBuildSystem

var network: Node


func _process(delta: float) -> void:
	super._process(delta)
	if controller.preview == null or not controller.preview.valid:
		return
	var player := get_parent().get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
	if player != null and player.global_position.distance_to(controller.preview.placement.position) > 8.0:
		controller.preview.valid = false
		controller.preview.reason = &"too_far"
		controller.preview_changed.emit()


func set_mode(mode: PKBuildController.Mode) -> void:
	if mode not in [PKBuildController.Mode.BUILD, PKBuildController.Mode.DEMOLISH, PKBuildController.Mode.REPAIR]:
		message.emit("Este modo ainda não está sincronizado entre jogadores.", true)
		return
	super.set_mode(mode)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		cursor_position = event.position
		_virtual_cursor = false
		if event.pressed:
			_submit_current_action(_current_aim())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pk_confirm") and not event is InputEventMouseButton:
		_submit_current_action(_current_aim())
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _submit_current_action(aim: PKAim) -> void:
	controller.aim(aim)
	if network == null:
		message.emit("O serviço de rede de construção não está disponível.", true)
		return

	match controller.mode:
		PKBuildController.Mode.BUILD:
			if controller.buildable == null:
				controller.press(aim)
				return
			if controller.buildable.drag != PKBuildable.Drag.NONE:
				message.emit("Construção por arrasto não está habilitada nesta sessão.", true)
				return
			if controller.preview == null or not controller.preview.valid:
				if controller.preview != null:
					builder.rejected.emit(controller.preview.reason, controller.buildable)
				return
			var preview := controller.preview
			network.request_action("place", {
				"buildable_id": String(controller.buildable.id),
				"position": preview.placement.position,
				"normal": preview.normal,
				"angle": controller.angle,
				"flipped": controller.flipped,
				"hit_uid": aim.hit_uid
			})
		PKBuildController.Mode.DEMOLISH:
			if controller.hover_uid == 0:
				message.emit("Aponte para uma peça da jangada.", true)
				return
			network.request_action("remove", {"uid": controller.hover_uid})
		PKBuildController.Mode.REPAIR:
			if controller.hover_uid == 0:
				message.emit("Aponte para uma peça da jangada.", true)
				return
			network.request_action("repair", {"uid": controller.hover_uid})
