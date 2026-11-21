
extends Node

const SERVER_ID := 1
const PORT := 7000
const MAX_PLAYERS := 8

const PLAYER_SCENE = preload("res://Scenes/Player/Player.tscn")

var peer: ENetMultiplayerPeer
var spawned_players: Dictionary = {}


func _ready() -> void:
	# O NetworkManager sempre pertence ao servidor.
	set_multiplayer_authority(SERVER_ID)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --------------------------------------------------
# CONEXÃO
# --------------------------------------------------

func create_host() -> int:
	if peer != null:
		return ERR_ALREADY_IN_USE

	peer = ENetMultiplayerPeer.new()

	var error := peer.create_server(PORT, MAX_PLAYERS)

	if error != OK:
		peer = null
		return error

	multiplayer.multiplayer_peer = peer
	_disable_local_building()

	# O anfitrião é o jogador de ID 1.
	spawn_player(SERVER_ID)

	print("Servidor iniciado na porta ", PORT)

	return OK


func join_game(ip: String) -> int:
	if peer != null:
		return ERR_ALREADY_IN_USE

	peer = ENetMultiplayerPeer.new()

	var error := peer.create_client(ip, PORT)

	if error != OK:
		peer = null
		return error

	multiplayer.multiplayer_peer = peer
	_disable_local_building()

	print("Conectando ao servidor: ", ip)

	return OK


func disconnect_game() -> void:
	_clear_spawned_players()

	multiplayer.multiplayer_peer = null
	peer = null

	print("Desconectado.")


# --------------------------------------------------
# CRIAÇÃO DOS JOGADORES
# --------------------------------------------------

func spawn_player(id: int) -> void:
	var world := get_parent()

	if world == null:
		push_error("NetworkManager não possui um nó World como pai.")
		return

	if world.has_node(str(id)):
		return

	var player: Node3D
	if id == SERVER_ID:
		var initial_player := world.get_node_or_null("Player")
		if initial_player is CharacterBody3D:
			player = initial_player
			player.name = str(id)

	if player == null:
		player = PLAYER_SCENE.instantiate()
		player.name = str(id)
		player.set("owner_peer_id", id)
		player.set_multiplayer_authority(SERVER_ID, true)
		world.add_child(player)

	# Identifica quem pode enviar comandos para este personagem.
	player.set("owner_peer_id", id)

	# A autoridade física e de rede permanece no servidor.
	player.set_multiplayer_authority(SERVER_ID, true)
	if player.is_node_ready():
		player.call("configure_owner_peer_id", id)

	# Distribui os jogadores em posições diferentes.
	var slot := id - 1

	player.position = Vector3(
		float(slot % 4) * 2.0,
		1.0,
		floori(float(slot) / 4.0) * 2.0
	)

	spawned_players[id] = true

	print("Personagem criado: ", id)


@rpc("authority", "call_local", "reliable")
func spawn_player_rpc(id: int) -> void:
	spawn_player(id)


func remove_player(id: int) -> void:
	var world := get_parent()

	if world == null:
		return

	var player = world.get_node_or_null(str(id))

	if player != null:
		player.queue_free()

	spawned_players.erase(id)

	print("Personagem removido: ", id)


@rpc("authority", "call_local", "reliable")
func remove_player_rpc(id: int) -> void:
	remove_player(id)


# --------------------------------------------------
# EVENTOS DE REDE
# --------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return

	print("Jogador conectado: ", id)

	# Cria o novo personagem em todas as instâncias.
	spawn_player_rpc.rpc(id)

	# Envia os personagens existentes ao novo cliente.
	spawn_player_rpc.rpc_id(id, SERVER_ID)

	for existing_id in multiplayer.get_peers():
		if existing_id != id:
			spawn_player_rpc.rpc_id(id, existing_id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return

	print("Jogador desconectado: ", id)

	remove_player_rpc.rpc(id)


func _on_connected() -> void:
	print("Conectado ao anfitrião!")


func _on_connection_failed() -> void:
	print("Falha na conexão!")

	_clear_spawned_players()

	multiplayer.multiplayer_peer = null
	peer = null


func _on_server_disconnected() -> void:
	print("Conexão com o anfitrião perdida!")

	_clear_spawned_players()

	multiplayer.multiplayer_peer = null
	peer = null


# --------------------------------------------------
# LIMPEZA
# --------------------------------------------------

func _clear_spawned_players() -> void:
	for id in spawned_players.keys():
		remove_player(id)


func _disable_local_building() -> void:
	var world := get_parent()
	if world == null:
		return
	var bootstrap := world.get_node_or_null("BuildingKitSetup")
	if bootstrap != null and bootstrap.has_method("disable_for_multiplayer"):
		bootstrap.call_deferred("disable_for_multiplayer")


# --------------------------------------------------
# ATALHOS TEMPORÁRIOS DE TESTE
# F6 = Criar servidor
# F7 = Entrar como cliente
# --------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_F6:
		print("Iniciando servidor... ", create_host())

	elif event.keycode == KEY_F7:
		print("Conectando ao servidor... ", join_game("127.0.0.1"))
