extends Node
## Autoload "Net": multijugador por red local (LAN).
##
## Modelo: un ANFITRIÓN con autoridad. Los clientes envían sus acciones al
## anfitrión (request_action); el anfitrión las valida con las reglas del
## juego y, si son legales, las reenvía a todos (broadcast_action), que las
## aplican en su propia copia de la partida. Como las partidas son
## deterministas (misma semilla), los dados y los robos salen iguales en
## todos los equipos.
##
## Además, el anfitrión se anuncia por difusión UDP en la red local para que
## los demás encuentren la partida sin escribir la IP.

signal lobby_changed
signal hosts_changed
signal game_started
## Cliente: el anfitrión ha aceptado una acción y hay que aplicarla.
signal action_received(action: Dictionary)
## Anfitrión: un cliente pide hacer una acción.
signal action_requested(action: Dictionary, peer_id: int)
## Cliente: el anfitrión rechazó una acción nuestra.
signal action_rejected(message: String)
## Un jugador se ha ido y una IA ocupa su sitio.
signal seat_replaced(seat: int)
## Se ha perdido la conexión (o no se pudo conectar).
signal disconnected(reason: String)

const PORT := 47810
const DISCOVERY_PORT := 47811
const PROTOCOL := "bgc-1"
const MAX_PLAYERS := 4
const ANNOUNCE_INTERVAL := 1.0
const HOST_TIMEOUT := 3.5

## true mientras hay una sesión de red (sala o partida).
var active := false
var is_host := false
var in_game := false
var game_id := "archipelago"
var my_name := ""
## Plazas de la mesa: [{"peer": id (0 = IA), "name", "ai": nivel}].
var seats: Array = []
## Partidas encontradas en la red: ip -> {"name", "players", "port", "seen"}.
var hosts := {}

var _peer: ENetMultiplayerPeer
var _announcer: PacketPeerUDP
var _listener: PacketPeerUDP
var _announce_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: _fail("No se pudo conectar con el anfitrión."))
	multiplayer.server_disconnected.connect(func() -> void: _fail("El anfitrión ha cerrado la partida."))


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 1


## Plaza (índice de jugador) de este equipo, o -1.
func local_seat() -> int:
	for i in seats.size():
		if seats[i]["peer"] == my_id():
			return i
	return -1


# --- Crear y unirse ------------------------------------------------------------------

func host_game(player_name: String, p_game_id: String = "archipelago", port: int = PORT) -> String:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "No se pudo crear la partida (¿el puerto %d está ocupado?)." % port
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = true
	in_game = false
	game_id = p_game_id
	my_name = player_name
	seats = [{"peer": 1, "name": player_name, "ai": PlayerInfo.AILevel.HUMAN}]
	_announcer = PacketPeerUDP.new()
	_announcer.set_broadcast_enabled(true)
	_announcer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	lobby_changed.emit()
	return ""


func join_game(address: String, player_name: String, port: int = PORT) -> String:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		return "Dirección no válida."
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = false
	in_game = false
	my_name = player_name
	seats = []
	return ""


func leave() -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	_announcer = null
	active = false
	is_host = false
	in_game = false
	seats = []


# --- Buscar partidas en la red ------------------------------------------------------

func start_discovery() -> void:
	stop_discovery()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null  # otro programa ya escucha en este equipo
	hosts.clear()


func stop_discovery() -> void:
	if _listener != null:
		_listener.close()
	_listener = null


## Direcciones IPv4 de este equipo en la red local (para dárselas a otros).
func local_addresses() -> Array[String]:
	var result: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			result.append(ip)
	return result


func _process(delta: float) -> void:
	if _announcer != null and is_host and not in_game:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = ANNOUNCE_INTERVAL
			var msg := {"protocol": PROTOCOL, "name": my_name, "game": game_id, "players": seats.size(), "max": MAX_PLAYERS, "port": PORT}
			_announcer.put_packet(JSON.stringify(msg).to_utf8_buffer())
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data = JSON.parse_string(_listener.get_packet().get_string_from_utf8())
			var ip := _listener.get_packet_ip()
			if data is Dictionary and data.get("protocol") == PROTOCOL:
				data["seen"] = Time.get_ticks_msec()
				changed = changed or not hosts.has(ip)
				hosts[ip] = data
		var now := Time.get_ticks_msec()
		for ip in hosts.keys():
			if now - hosts[ip]["seen"] > HOST_TIMEOUT * 1000:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()


# --- Sala de espera --------------------------------------------------------------------

func _on_connected_to_server() -> void:
	_register.rpc_id(1, my_name, PROTOCOL)


@rpc("any_peer", "reliable")
func _register(player_name: String, protocol: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_kick.rpc_id(sender, "Versión del juego distinta a la del anfitrión.")
	elif in_game:
		_kick.rpc_id(sender, "La partida ya ha empezado.")
	elif seats.size() >= MAX_PLAYERS:
		_kick.rpc_id(sender, "La mesa está llena.")
	else:
		seats.append({"peer": sender, "name": player_name.substr(0, 16), "ai": PlayerInfo.AILevel.HUMAN})
		_sync_lobby()


@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	_fail(reason)


func add_ai(level: int) -> void:
	if is_host and seats.size() < MAX_PLAYERS and not in_game:
		seats.append({"peer": 0, "name": "IA %d" % (seats.size() + 1), "ai": level})
		_sync_lobby()


func remove_seat(index: int) -> void:
	if not is_host or index <= 0 or index >= seats.size() or in_game:
		return
	var peer: int = seats[index]["peer"]
	seats.remove_at(index)
	if peer > 1:
		_kick.rpc_id(peer, "El anfitrión te ha sacado de la mesa.")
	_sync_lobby()


func _sync_lobby() -> void:
	_update_lobby.rpc(seats)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _update_lobby(p_seats: Array) -> void:
	seats = p_seats
	lobby_changed.emit()


## Anfitrión: reparte la partida a todos y empieza.
func start_game() -> void:
	if not is_host or seats.size() < 2:
		return
	in_game = true
	var players: Array = []
	for i in seats.size():
		players.append(PlayerInfo.new(i, seats[i]["name"], PlayerInfo.default_color(i), seats[i]["ai"]).to_dict())
	_start.rpc(game_id, players, BGCRng.random_seed())


@rpc("authority", "call_local", "reliable")
func _start(p_game_id: String, players: Array, seed: int) -> void:
	in_game = true
	game_id = p_game_id
	var infos: Array[PlayerInfo] = []
	for d in players:
		infos.append(PlayerInfo.from_dict(d))
	game_started.emit()
	App.start_network_game(p_game_id, infos, seed, local_seat())


# --- Durante la partida ----------------------------------------------------------------

## Cliente: pide al anfitrión que haga una acción.
func request_action(action: Dictionary) -> void:
	_request.rpc_id(1, action)


@rpc("any_peer", "reliable")
func _request(action: Dictionary) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var seat := -1
	for i in seats.size():
		if seats[i]["peer"] == sender:
			seat = i
	if seat == -1 or int(action.get("player", -1)) != seat:
		reject(sender, "No puedes actuar por otro jugador.")
		return
	action_requested.emit(action, sender)


func reject(peer_id: int, message: String) -> void:
	_rejected.rpc_id(peer_id, message)


@rpc("authority", "reliable")
func _rejected(message: String) -> void:
	action_rejected.emit(message)


## Anfitrión: envía a todos los clientes una acción ya aplicada.
func broadcast_action(action: Dictionary) -> void:
	if is_host and active:
		_apply.rpc(action)


@rpc("authority", "reliable")
func _apply(action: Dictionary) -> void:
	action_received.emit(action)


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	for i in seats.size():
		if seats[i]["peer"] == id:
			if in_game:
				# Una IA ocupa su plaza para que la partida siga.
				seats[i] = {"peer": 0, "name": seats[i]["name"], "ai": PlayerInfo.AILevel.NORMAL}
				_seat_to_ai.rpc(i)
				seat_replaced.emit(i)
			else:
				seats.remove_at(i)
				_sync_lobby()
			return


@rpc("authority", "reliable")
func _seat_to_ai(seat: int) -> void:
	seat_replaced.emit(seat)


func _fail(reason: String) -> void:
	var was_in_game := in_game
	leave()
	disconnected.emit(reason)
	if was_in_game:
		App.go_to_menu(reason)
