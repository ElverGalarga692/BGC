extends RulesCapture
## Capturas del reglamento en PDF de La Conjura (ver rules_capture.gd).
##
## Partida a 7. En la pantalla solo Ana es una persona (los demás son IAs),
## así que se ve su rol y sus decisiones secretas sin la cortina de «Pasa el
## dispositivo». Se busca una semilla en la que Ana sea de la Sombra y le
## toque ser Regente, Consejera y usar un poder secreto.

const G := preload("res://games/conjura/logic/conjura_game.gd")
const Phase := ConjuraGame.Phase
const SECRET_POWERS := [ConjuraDefs.Power.ESPIAR, ConjuraDefs.Power.AUGURIO, ConjuraDefs.Power.PESQUISA]
const ANA := 0

## Si es false, se cierra la animación de los votos antes de la captura.
var _keep_vote_reveal := false
## Si es false, se quita la ventana con el resultado de un poder.
var _keep_result := false


func _init() -> void:
	game_id = "conjura"
	player_count = 7
	screen_ai_seats.assign(range(1, 7))


func _new_game() -> GameBase:
	return ConjuraGame.new()


func _new_ai(pid: int) -> Object:
	return ConjuraAI.new(pid, PlayerInfo.AILevel.NORMAL, seed_value + pid)


func _screen_scene() -> PackedScene:
	return preload("res://games/conjura/conjura.tscn")


## La pantalla solo enseña el rol al empezar una partida nueva: si la
## partida ya va avanzada, esa ventana sobra. Y la animación de los votos
## solo se quiere en su captura.
func _on_screen_loaded(n: int) -> void:
	var drop := ["info"] if n > 0 else []
	if not _keep_result:
		drop.append("result")
	_screen._private_queue = _screen._private_queue.filter(func(e): return not e["kind"] in drop)
	if not _keep_vote_reveal:
		_screen._vote_reveal.visible = false
	_screen._refresh()


func _acts(g, pid: int) -> bool:
	return pid in g.players_to_act()


func _secret_power_by_ana(n: int) -> bool:
	if n == 0 or action_type(n) != G.USE_POWER or int(_history[n - 1]["player"]) != ANA:
		return false
	return true


func _good_seed() -> bool:
	var g := fresh_game() as ConjuraGame
	if g.roles[ANA] != ConjuraDefs.Role.SOMBRA:
		return false
	var needs := {"regent": false, "council": false, "power": false}
	for n in range(1, _history.size() + 1):
		g.submit(GameAction.from_dict(_history[n - 1]))
		if g.phase == Phase.REGENT_DISCARD and g.regent == ANA:
			needs["regent"] = true
		if g.phase == Phase.COUNCIL_ENACT and g.council == ANA:
			needs["council"] = true
		if _secret_power_by_ana(n) and g.knowledge[ANA].size() > 0:
			needs["power"] = true
	return not needs.values().has(false)


func _prepare() -> void:
	for i in 300:
		if _good_seed():
			print("Semilla elegida: ", seed_value)
			return
		seed_value += 1
		_history = play_full_game()
	push_warning("No se encontró una semilla con todo; se usa la última")


func _shoot_all() -> void:
	# 1. Al empezar: Ana ve su rol en secreto.
	await load_state(0)
	await shot("01_rol")

	# 2. Nominación con Ana de Regente.
	var nominate := find(func(g, _n): return g.phase == Phase.NOMINATE and g.regent == ANA)
	await load_state(nominate)
	await shot("02_nominar")

	# 3. Votación (Ana aún no ha votado) y revelación de los votos.
	var vote := find(func(g, _n): return g.phase == Phase.VOTE and _acts(g, ANA), 1)
	await load_state(vote)
	await shot("03_votar")
	var reveal := find(func(g, n): return n > 0 and action_type(n) == G.VOTE and g.phase != Phase.VOTE, vote)
	_keep_vote_reveal = true
	await load_state(reveal, 1, {}, 1.5)
	await shot("04_votos")
	_keep_vote_reveal = false

	# 4. Legislatura: Ana como Regente y como Consejera.
	var discard := find(func(g, _n): return g.phase == Phase.REGENT_DISCARD and g.regent == ANA)
	if discard >= 0:
		await load_state(discard)
		await shot("05_regente")
	var enact := find(func(g, _n): return g.phase == Phase.COUNCIL_ENACT and g.council == ANA)
	if enact >= 0:
		await load_state(enact)
		await shot("06_consejero")

	# 5. Declaraciones (le toca a Ana) y unas que no cuadran.
	var claim := find(func(g, _n): return g.phase == Phase.CLAIMS and _acts(g, ANA))
	if claim >= 0:
		await load_state(claim)
		await shot("07_declarar")
	var lie := find(func(g, n):
		return n > 0 and action_type(n) == G.CLAIM and g.phase != Phase.CLAIMS \
			and not g.claims_consistent(g.governments[-1]))
	if lie >= 0:
		await load_state(lie)
		await shot("08_mentira")

	# 6. Poderes: elegir, usar y ver el resultado en secreto.
	var choose := find(func(g, _n): return g.phase == Phase.CHOOSE_POWER and g.council == ANA)
	if choose < 0:
		choose = find(func(g, _n): return g.phase == Phase.CHOOSE_POWER)
	await load_state(choose)
	await shot("09_elegir_poder")
	var use := find(func(g, _n): return g.phase == Phase.USE_POWER and g.council == ANA)
	if use < 0:
		use = find(func(g, _n): return g.phase == Phase.USE_POWER)
	await load_state(use)
	await shot("10_usar_poder")
	var result := find(func(_g, n): return _secret_power_by_ana(n))
	if result >= 0:
		_keep_result = true
		await load_state(result, 1)
		await shot("11_resultado_poder")
		_keep_result = false

	# 7. Crisis (tres votaciones fallidas).
	var crisis := find(func(g, n):
		return n > 0 and action_type(n) == G.VOTE and not g.governments.is_empty() \
			and g.governments[-1].get("crisis", false) and g.phase == Phase.NOMINATE)
	if crisis >= 0:
		await load_state(crisis, 3)
		await shot("12_crisis")

	# 8. Partida avanzada y final.
	var late := find(func(g, _n):
		return g.phase == Phase.NOMINATE and g.guardia_edicts + g.sombra_edicts >= 5)
	if late < 0:
		late = maxi(0, _history.size() - 4)
	await load_state(late)
	await shot("13_avanzada")
	await load_state(_history.size(), 3)
	await shot("14_final")

	# 9. Varias personas en el mismo equipo: cortina de «Pasa el dispositivo».
	screen_ai_seats.clear()
	await load_state(vote)
	await shot("15_cortina")
	_screen._overlay_stage = "show"
	_screen._render_overlay()
	await settle(0.4)
	await shot("16_cortina_mostrar")
