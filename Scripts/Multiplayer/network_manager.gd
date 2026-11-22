extends Node

signal local_player_ready(player: CharacterBody3D)
signal player_list_changed
signal session_started
signal session_ended

const SERVER_ID := 1
const PORT := 7000
const MAX_PLAYERS := 8
const PLAYER_SCENE: PackedScene = preload("res://Scenes/Player/Player.tscn")
const SESSION_INTERFACE_SCENE: PackedScene = preload("res://Scenes/UI/SessionInterface.tscn")

var peer: ENetMultiplayerPeer
var spawned_players: Dictionary = {}
var peer_names: Dictionary = {}
var spawn_slots: Dictionary = {}
var _local_name := "Sobrevivente"
var _offline_session := false
var _session_active := false
var _lobby_layer: CanvasLayer
var _lobby_panel: PanelContainer
var _name_input: LineEdit
var _address_input: LineEdit
var _status_label: Label
var _session_panel: PanelContainer
var _session_label: Label
var _players_label: Label
var _chat_panel: PanelContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _chat_button: Button
var _chat_lines: Array[String] = []
var _chat_rate: Dictionary = {}


func _ready() -> void:
	set_multiplayer_authority(SERVER_ID)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_create_session_ui()
	_show_lobby("Escolha como jogar.")


func _exit_tree() -> void:
	if peer != null:
		peer.close()


# -----------------------------------------------------------------------------
# SESSÃO
# -----------------------------------------------------------------------------

func create_host(player_name: String = "Sobrevivente") -> int:
	if peer != null or _offline_session:
		return ERR_ALREADY_IN_USE

	_local_name = _clean_name(player_name)
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1)
	if error != OK:
		peer = null
		_show_lobby("Não foi possível abrir a sessão (erro %d)." % error)
		return error

	multiplayer.multiplayer_peer = peer
	_offline_session = false
	_session_active = true
	peer_names.clear()
	spawn_slots.clear()
	peer_names[SERVER_ID] = _local_name
	spawn_slots[SERVER_ID] = 0
	spawn_player(SERVER_ID, 0)
	_refresh_session_ui()
	session_started.emit()
	print("Sessão criada na porta UDP ", PORT)
	return OK


func start_offline(player_name: String = "Sobrevivente") -> int:
	if peer != null or _offline_session:
		return ERR_ALREADY_IN_USE
	_local_name = _clean_name(player_name)
	_offline_session = true
	_session_active = true
	peer_names.clear()
	spawn_slots.clear()
	peer_names[SERVER_ID] = _local_name
	spawn_slots[SERVER_ID] = 0
	spawn_player(SERVER_ID, 0)
	_refresh_session_ui()
	session_started.emit()
	return OK


func join_game(address: String, player_name: String = "Sobrevivente") -> int:
	if peer != null or _offline_session:
		return ERR_ALREADY_IN_USE
	var host := address.strip_edges()
	if host.is_empty():
		host = "127.0.0.1"
	_local_name = _clean_name(player_name)
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(host, PORT)
	if error != OK:
		peer = null
		_show_lobby("Endereço inválido ou conexão indisponível (erro %d)." % error)
		return error
	multiplayer.multiplayer_peer = peer
	_session_active = true
	_set_status("Conectando a %s:%d…" % [host, PORT])
	return OK


func disconnect_game() -> void:
	if peer == null and not _offline_session:
		return
	_end_session("Você saiu da sessão.")


func is_session_active() -> bool:
	return _session_active


func is_offline_session() -> bool:
	return _offline_session


func get_player_name(peer_id: int) -> String:
	return str(peer_names.get(peer_id, "Sobrevivente %d" % peer_id))


func _end_session(message: String) -> void:
	_clear_spawned_players()
	peer_names.clear()
	spawn_slots.clear()
	_chat_lines.clear()
	_chat_rate.clear()
	_session_active = false
	_offline_session = false
	var old_peer := peer
	peer = null
	multiplayer.multiplayer_peer = null
	if old_peer != null:
		old_peer.close()
	session_ended.emit()
	_show_lobby(message)
	player_list_changed.emit()


func _on_connected() -> void:
	_set_status("Conectado; entrando no mundo…")
	register_player_name.rpc_id(SERVER_ID, _local_name)


func _on_connection_failed() -> void:
	_end_session("Falha ao conectar. Confira o IP, a porta UDP 7000 e o firewall.")


func _on_server_disconnected() -> void:
	_end_session("A conexão com o anfitrião foi encerrada.")


# -----------------------------------------------------------------------------
# JOGADORES E NOMES
# -----------------------------------------------------------------------------

func spawn_player(id: int, spawn_slot: int) -> void:
	var world := get_parent()
	if world == null:
		push_error("NetworkManager precisa ser filho do nó World.")
		return
	if world.has_node(str(id)):
		return

	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	if player == null:
		push_error("Não foi possível instanciar a cena de jogador.")
		return
	player.name = str(id)
	player.owner_peer_id = id
	player.display_name = get_player_name(id)
	player.set_multiplayer_authority(SERVER_ID, true)
	spawn_slots[id] = spawn_slot
	player.position = _spawn_position(spawn_slot)
	world.add_child(player)
	spawned_players[id] = true
	player_list_changed.emit()
	print("Jogador criado: %s (%d)" % [player.display_name, id])
	if id == multiplayer.get_unique_id():
		local_player_ready.emit(player)
	_refresh_session_ui()


@rpc("authority", "call_local", "reliable")
func spawn_player_rpc(id: int, spawn_slot: int) -> void:
	spawn_player(id, spawn_slot)


func remove_player(id: int) -> void:
	var world := get_parent()
	if world == null:
		return
	var player := world.get_node_or_null(str(id))
	if player != null:
		player.queue_free()
	spawned_players.erase(id)
	spawn_slots.erase(id)
	player_list_changed.emit()
	_refresh_session_ui()


@rpc("authority", "call_local", "reliable")
func remove_player_rpc(id: int) -> void:
	remove_player(id)


@rpc("any_peer", "call_remote", "reliable")
func register_player_name(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= SERVER_ID or not multiplayer.get_peers().has(sender_id):
		return
	var clean_name := _clean_name(player_name)
	peer_names[sender_id] = clean_name
	_apply_player_name(sender_id, clean_name)
	sync_player_name.rpc(sender_id, clean_name)
	player_list_changed.emit()
	_refresh_session_ui()


@rpc("authority", "call_remote", "reliable")
func sync_player_name(id: int, player_name: String) -> void:
	peer_names[id] = _clean_name(player_name)
	_apply_player_name(id, str(peer_names[id]))
	player_list_changed.emit()
	_refresh_session_ui()


func _apply_player_name(id: int, player_name: String) -> void:
	var player := get_parent().get_node_or_null(str(id))
	if player != null and player.has_method("set_display_name"):
		player.call("set_display_name", player_name)


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Novo jogador conectado: ", id)
	var new_slot := _allocate_spawn_slot(id)
	spawn_player_rpc.rpc(id, new_slot)
	spawn_player_rpc.rpc_id(id, SERVER_ID, int(spawn_slots.get(SERVER_ID, 0)))
	if peer_names.has(SERVER_ID):
		sync_player_name.rpc_id(id, SERVER_ID, str(peer_names[SERVER_ID]))
	for existing_id in multiplayer.get_peers():
		if existing_id == id:
			continue
		spawn_player_rpc.rpc_id(id, existing_id, int(spawn_slots.get(existing_id, 0)))
		if peer_names.has(existing_id):
			sync_player_name.rpc_id(id, existing_id, str(peer_names[existing_id]))
	var building_network := get_parent().get_node_or_null("BuildingNetwork")
	if building_network != null:
		building_network.send_snapshot_to_peer(id)
	player_list_changed.emit()
	_refresh_session_ui()


func _allocate_spawn_slot(peer_id: int) -> int:
	if spawn_slots.has(peer_id):
		return int(spawn_slots[peer_id])
	var used: Dictionary = {}
	for value in spawn_slots.values():
		used[int(value)] = true
	for slot in range(1, MAX_PLAYERS):
		if not used.has(slot):
			spawn_slots[peer_id] = slot
			return slot
	return 0


func _spawn_position(slot: int) -> Vector3:
	if slot <= 0:
		return Vector3(0.0, 1.0, 0.0)
	var raft_positions: Array[Vector2] = [
		Vector2(-1.0, -1.0), Vector2(0.0, -1.0), Vector2(1.0, -1.0),
		Vector2(-1.0, 0.0), Vector2(1.0, 0.0),
		Vector2(-1.0, 1.0), Vector2(0.0, 1.0)
	]
	var offset := raft_positions[posmod(slot - 1, raft_positions.size())]
	return Vector3(offset.x, 1.0, offset.y)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Jogador desconectado: ", id)
	remove_player_rpc.rpc(id)
	peer_names.erase(id)
	player_list_changed.emit()
	_refresh_session_ui()


func _clear_spawned_players() -> void:
	for id in spawned_players.keys().duplicate():
		remove_player(int(id))


func _clean_name(value: String) -> String:
	var result := value.strip_edges().replace("\n", " ").replace("\r", " ")
	if result.is_empty():
		result = "Sobrevivente"
	return result.substr(0, 20)


func _is_valid_player(peer_id: int) -> bool:
	if peer_id == SERVER_ID:
		return _session_active
	return multiplayer.is_server() and multiplayer.get_peers().has(peer_id)


# -----------------------------------------------------------------------------
# CHAT DA SESSÃO
# -----------------------------------------------------------------------------

func _send_chat() -> void:
	var text := _chat_input.text.strip_edges()
	_chat_input.clear()
	if text.is_empty():
		return
	text = text.substr(0, 180)
	if multiplayer.is_server():
		_broadcast_chat(SERVER_ID, _local_name, text)
	elif multiplayer.has_multiplayer_peer():
		request_chat.rpc_id(SERVER_ID, text)


@rpc("any_peer", "call_remote", "reliable")
func request_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not _is_valid_player(sender_id):
		return
	var now := Time.get_ticks_msec()
	var state: Dictionary = _chat_rate.get(sender_id, {"start": now, "count": 0})
	if now - int(state.start) >= 1000:
		state = {"start": now, "count": 0}
	state.count = int(state.count) + 1
	_chat_rate[sender_id] = state
	if int(state.count) > 4:
		return
	var clean_text := text.strip_edges().replace("\n", " ").replace("\r", " ").substr(0, 180)
	if clean_text.is_empty():
		return
	_broadcast_chat(sender_id, get_player_name(sender_id), clean_text)


func _broadcast_chat(sender_id: int, sender_name: String, text: String) -> void:
	_append_chat(sender_name, text)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_chat.rpc(sender_id, sender_name, text)


@rpc("authority", "call_remote", "reliable")
func sync_chat(_sender_id: int, sender_name: String, text: String) -> void:
	_append_chat(sender_name, text)


func _append_chat(sender_name: String, text: String) -> void:
	_chat_lines.append("%s: %s" % [sender_name, text])
	while _chat_lines.size() > 8:
		_chat_lines.pop_front()
	if _chat_log != null:
		_chat_log.text = "\n".join(_chat_lines)
		_chat_log.scroll_to_line(_chat_log.get_line_count())


func _open_chat() -> void:
	if not _session_active:
		return
	_chat_panel.visible = true
	_chat_input.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_chat() -> void:
	_chat_panel.visible = false
	if _session_active and get_parent().has_node(str(multiplayer.get_unique_id())):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# -----------------------------------------------------------------------------
# INTERFACE
# -----------------------------------------------------------------------------

func _create_session_ui() -> void:
	_lobby_layer = SESSION_INTERFACE_SCENE.instantiate() as CanvasLayer
	_lobby_layer.name = "SessionInterface"
	add_child(_lobby_layer)
	var root := _lobby_layer.get_node("Root") as Control
	_lobby_panel = root.get_node("LobbyPanel") as PanelContainer
	_name_input = root.get_node("LobbyPanel/LobbyMenu/NameInput") as LineEdit
	_address_input = root.get_node("LobbyPanel/LobbyMenu/AddressInput") as LineEdit
	_status_label = root.get_node("LobbyPanel/LobbyMenu/StatusLabel") as Label
	_session_panel = root.get_node("SessionPanel") as PanelContainer
	_session_label = root.get_node("SessionPanel/SessionBox/SessionLabel") as Label
	_players_label = root.get_node("SessionPanel/SessionBox/PlayersLabel") as Label
	_chat_panel = root.get_node("ChatPanel") as PanelContainer
	_chat_button = root.get_node("SessionPanel/SessionBox/SessionButtons/ChatButton") as Button
	_chat_log = root.get_node("ChatPanel/ChatBox/ChatLog") as RichTextLabel
	_chat_input = root.get_node("ChatPanel/ChatBox/ChatInputRow/ChatInput") as LineEdit
	var host_button := root.get_node("LobbyPanel/LobbyMenu/HostButton") as Button
	var join_button := root.get_node("LobbyPanel/LobbyMenu/JoinButton") as Button
	var offline_button := root.get_node("LobbyPanel/LobbyMenu/OfflineButton") as Button
	var leave_button := root.get_node("SessionPanel/SessionBox/SessionButtons/LeaveButton") as Button
	var send_button := root.get_node("ChatPanel/ChatBox/ChatInputRow/SendButton") as Button
	_lobby_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_session_panel.add_theme_stylebox_override("panel", _make_panel_style())
	(root.get_node("ChatPanel") as PanelContainer).add_theme_stylebox_override("panel", _make_panel_style())
	(root.get_node("LobbyPanel/LobbyMenu") as VBoxContainer).add_theme_constant_override("separation", 12)
	(root.get_node("LobbyPanel/LobbyMenu/Title") as Label).add_theme_font_size_override("font_size", 28)
	(root.get_node("LobbyPanel/LobbyMenu/Subtitle") as Label).add_theme_color_override("font_color", Color(0.68, 0.84, 0.9))
	(root.get_node("ChatPanel/ChatBox/ChatTitle") as Label).add_theme_font_size_override("font_size", 18)
	host_button.pressed.connect(func() -> void: create_host(_name_input.text))
	join_button.pressed.connect(func() -> void: join_game(_address_input.text, _name_input.text))
	offline_button.pressed.connect(func() -> void: start_offline(_name_input.text))
	_chat_button.pressed.connect(_open_chat)
	leave_button.pressed.connect(disconnect_game)
	_chat_input.text_submitted.connect(func(_text: String) -> void: _send_chat(); _close_chat())
	send_button.pressed.connect(func() -> void: _send_chat(); _close_chat())
	player_list_changed.connect(_refresh_session_ui)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.09, 0.14, 0.96)
	style.border_color = Color(0.18, 0.58, 0.72, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style


func _show_lobby(message: String) -> void:
	if _lobby_panel == null:
		return
	_lobby_panel.visible = true
	_session_panel.visible = false
	_chat_panel.visible = false
	_status_label.text = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _refresh_session_ui() -> void:
	if _session_panel == null:
		return
	_session_panel.visible = _session_active and get_parent().has_node(str(multiplayer.get_unique_id()))
	if not _session_panel.visible:
		return
	_lobby_panel.visible = false
	_session_label.text = "Sessão %s · porta UDP %d" % ["online" if peer != null else "local", PORT]
	var names: Array[String] = []
	for id in spawned_players.keys():
		names.append(get_player_name(int(id)))
	names.sort()
	_players_label.text = "Jogadores (%d/%d):\n%s" % [spawned_players.size(), MAX_PLAYERS, ", ".join(names)]


func _input(event: InputEvent) -> void:
	if GameSettings.is_settings_open():
		return
	if not _session_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T and not _chat_panel.visible:
			_open_chat()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and _chat_panel.visible:
			_close_chat()
			get_viewport().set_input_as_handled()
