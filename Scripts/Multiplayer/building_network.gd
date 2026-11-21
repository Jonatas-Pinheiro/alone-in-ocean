extends Node

const SERVER_ID := 1
const MAX_BUILD_DISTANCE := 8.0
const MAX_ACTIONS_PER_SECOND := 10

var build_system: NetworkedBuildSystem
var _network_manager: Node
var _pending_snapshot: Dictionary = {}
var _pending_snapshot_peers: Dictionary = {}
var _request_rates: Dictionary = {}


func _ready() -> void:
	_network_manager = get_parent().get_node_or_null("NetworkManager")


func register_build_system(system: NetworkedBuildSystem) -> void:
	build_system = system
	build_system.network = self
	if not _pending_snapshot.is_empty():
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot.clear()
	if multiplayer.is_server():
		for peer_id in _pending_snapshot_peers.keys():
			_send_snapshot_to_peer(int(peer_id))
	_pending_snapshot_peers.clear()


func unregister_build_system(system: NetworkedBuildSystem) -> void:
	if build_system == system:
		build_system.network = null
		build_system = null


func send_snapshot_to_peer(peer_id: int) -> void:
	if build_system == null:
		_pending_snapshot_peers[peer_id] = true
		return
	_send_snapshot_to_peer(peer_id)


func _send_snapshot_to_peer(peer_id: int) -> void:
	if build_system == null or not multiplayer.is_server():
		return
	apply_authoritative_snapshot.rpc_id(peer_id, build_system.to_data())


func request_action(action: String, payload: Dictionary) -> void:
	if build_system == null:
		return
	if multiplayer.is_server():
		_handle_action(SERVER_ID, action, payload)
	elif multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		request_action_rpc.rpc_id(SERVER_ID, action, payload)
	else:
		build_system.message.emit("A sessão ainda não está conectada.", true)


@rpc("any_peer", "call_remote", "reliable")
func request_action_rpc(action: String, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_handle_action(sender_id, action, payload)


func _handle_action(sender_id: int, action: String, payload: Dictionary) -> void:
	if build_system == null or _network_manager == null:
		_report_result(sender_id, false, "O sistema de construção ainda está iniciando.")
		return
	if not _network_manager.is_session_active() or not _is_authorized_peer(sender_id):
		_report_result(sender_id, false, "Jogador não autorizado.")
		return
	if payload.size() > 8 or not _allow_request(sender_id):
		_report_result(sender_id, false, "Muitas ações em pouco tempo.")
		return
	var player := get_parent().get_node_or_null(str(sender_id)) as Node3D
	if player == null:
		_report_result(sender_id, false, "Seu personagem ainda não apareceu no mundo.")
		return

	var result: PKResult
	match action:
		"place":
			result = _place_from_request(player, payload)
		"remove":
			result = _remove_from_request(player, payload)
		"repair":
			result = _repair_from_request(player, payload)
		_:
			_report_result(sender_id, false, "Ação de construção desconhecida.")
			return

	if not result.ok:
		_report_result(sender_id, false, _reason_message(result.reason))
		return

	# O servidor envia o estado canônico. Isso também acerta os UIDs dos clientes
	# e mantém late joiners iguais ao anfitrião.
	apply_authoritative_snapshot.rpc(build_system.to_data())
	_report_result(sender_id, true, "Construção sincronizada.")


func _place_from_request(player: Node3D, payload: Dictionary) -> PKResult:
	var buildable_id := StringName(str(payload.get("buildable_id", "")))
	var buildable: PKBuildable = build_system.catalog.get_buildable(buildable_id)
	if buildable == null or not buildable.in_catalog:
		return PKResult.failure(&"unknown_piece")
	var position_value: Variant = payload.get("position", Vector3.INF)
	var normal_value: Variant = payload.get("normal", Vector3.UP)
	if not position_value is Vector3 or not normal_value is Vector3:
		return PKResult.failure(&"invalid_position")
	var position: Vector3 = position_value
	var normal: Vector3 = normal_value
	if not position.is_finite() or not normal.is_finite() or position.distance_to(player.global_position) > MAX_BUILD_DISTANCE:
		return PKResult.failure(&"too_far")
	if normal.length_squared() < 0.001:
		normal = Vector3.UP
	var angle := float(payload.get("angle", 0.0))
	if not is_finite(angle):
		return PKResult.failure(&"invalid_position")
	var hit_uid := int(payload.get("hit_uid", 0))
	if hit_uid != 0 and not build_system.builder.layout.has(hit_uid):
		return PKResult.failure(&"not_found")
	var flipped := bool(payload.get("flipped", false))
	var aim := PKAim.at(position, normal.normalized(), hit_uid)
	var preview := build_system.builder.preview(buildable, aim, angle, flipped)
	if not preview.valid:
		return PKResult.failure(preview.reason)
	return build_system.builder.place(preview)


func _remove_from_request(player: Node3D, payload: Dictionary) -> PKResult:
	var uid := int(payload.get("uid", 0))
	var placement: PKPlacement = build_system.builder.layout.get_piece(uid)
	if placement == null:
		return PKResult.failure(&"not_found")
	if player.global_position.distance_to(placement.position) > MAX_BUILD_DISTANCE:
		return PKResult.failure(&"too_far")
	return build_system.builder.remove(uid)


func _repair_from_request(player: Node3D, payload: Dictionary) -> PKResult:
	var uid := int(payload.get("uid", 0))
	var placement: PKPlacement = build_system.builder.layout.get_piece(uid)
	if placement == null:
		return PKResult.failure(&"not_found")
	if player.global_position.distance_to(placement.position) > MAX_BUILD_DISTANCE:
		return PKResult.failure(&"too_far")
	return build_system.builder.repair(uid)


func _is_authorized_peer(peer_id: int) -> bool:
	if peer_id == SERVER_ID:
		return _network_manager.is_session_active() and multiplayer.is_server()
	return multiplayer.is_server() and multiplayer.get_peers().has(peer_id)


func _allow_request(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var rate: Dictionary = _request_rates.get(peer_id, {"started": now, "count": 0})
	if now - int(rate.started) >= 1000:
		rate = {"started": now, "count": 0}
	rate.count = int(rate.count) + 1
	_request_rates[peer_id] = rate
	return int(rate.count) <= MAX_ACTIONS_PER_SECOND


func _reason_message(reason: StringName) -> String:
	match reason:
		&"too_far":
			return "A construção está longe demais."
		&"not_found":
			return "A peça não existe mais."
		&"supports_others":
			return "Remova primeiro as peças que dependem desta estrutura."
		&"not_damaged":
			return "Esta peça não precisa de reparo."
		&"unknown_piece":
			return "Essa peça não faz parte do catálogo da partida."
		_:
			return "Ação recusada: %s." % PKText.reason(reason)


func _report_result(peer_id: int, succeeded: bool, message: String) -> void:
	if peer_id == SERVER_ID:
		if build_system != null:
			build_system.message.emit(message, not succeeded)
	elif multiplayer.is_server() and multiplayer.get_peers().has(peer_id):
		action_result.rpc_id(peer_id, succeeded, message)


@rpc("authority", "call_remote", "reliable")
func action_result(_succeeded: bool, message: String) -> void:
	if build_system != null:
		build_system.message.emit(message, not _succeeded)


@rpc("authority", "call_remote", "reliable")
func apply_authoritative_snapshot(data: Dictionary) -> void:
	if build_system == null:
		_pending_snapshot = data.duplicate(true)
		return
	_apply_snapshot(data)


func _apply_snapshot(data: Dictionary) -> void:
	if build_system == null:
		_pending_snapshot = data.duplicate(true)
		return
	var result := build_system.load_data(data)
	if not result.ok:
		push_error("Snapshot de construção inválido: %s" % result.reason)
