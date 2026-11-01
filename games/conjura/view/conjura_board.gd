class_name ConjuraBoard
extends Control
## Tablero público de La Conjura: las dos pistas de edictos, el descontento,
## la crisis, el mazo y el gobierno actual. Solo dibuja; se le pasa la vista
## pública (game.view_for(-1)) y los nombres de los jugadores.

const D := preload("res://games/conjura/logic/conjura_defs.gd")
const Edict := ConjuraDefs.Edict

const SLOT_BG := Color(1, 1, 1, 0.06)
const SLOT_BORDER := Color(1, 1, 1, 0.22)
const TEXT := Color("f4f1e8")
const TEXT_DIM := Color("b9b2c6")

var view: Dictionary = {}
var player_names: Array[String] = []
var player_colors: Array[Color] = []
## Pista que se ilumina un momento al promulgar (Edict o -1).
var flash_edict := -1
var flash := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh(p_view: Dictionary) -> void:
	view = p_view
	queue_redraw()


## Ilumina la casilla recién ocupada.
func pulse(edict: int) -> void:
	flash_edict = edict
	flash = 1.0
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		flash = v
		queue_redraw(), 1.0, 0.0, 1.2)


func _font() -> Font:
	return ThemeDB.fallback_font


func _text(pos: Vector2, text: String, font_size: int, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, width: float = -1) -> void:
	draw_string(_font(), pos, text, align, width, font_size, color)


func _draw() -> void:
	if view.is_empty():
		return
	var w := size.x
	var card_w := clampf((w - 80.0) / 6.6, 40.0, 96.0)
	var card_h := card_w * 1.38
	var gap := card_w * 0.12
	var y := 10.0

	_text(Vector2(0, y + 22), "Gobierno", 15, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 30
	_text(Vector2(0, y + 26), _government_text(), 22, TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	y += 50

	y = _track(y, "Guardia Real", D.COLOR_GUARDIA, Edict.GUARDIA, int(view["guardia_edicts"]), D.GUARDIA_TO_WIN, card_w, card_h, gap)
	y += 14
	y = _track(y, "Hermandad de la Sombra", D.COLOR_SOMBRA, Edict.SOMBRA, int(view["sombra_edicts"]), D.SOMBRA_TO_WIN, card_w, card_h, gap)
	y += 22

	# Descontento, crisis y mazos.
	var col_w := w / 3.0
	_meter(Vector2(col_w * 0.5, y), "Descontento", int(view["discontent"]), D.MAX_DISCONTENT, D.COLOR_NEUTRAL)
	_meter(Vector2(col_w * 1.5, y), "Crisis", int(view["crisis"]), D.MAX_CRISIS, Color("e07a3c"))
	_text(Vector2(col_w * 2, y + 16), "Mazo: %d   Descarte: %d" % [view["deck_count"], view["discard_count"]], 15, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, col_w)
	var sombra_cards: int = D.DECK[Edict.SOMBRA] + D.EXTRA_SOMBRA.get(int(view["player_count"]), 0)
	var total: int = D.DECK[Edict.GUARDIA] + sombra_cards + D.DECK[Edict.NEUTRAL]
	_text(Vector2(col_w * 2, y + 40), "(%d edictos: %d G · %d S · %d N)" % [total, D.DECK[Edict.GUARDIA], sombra_cards, D.DECK[Edict.NEUTRAL]], 12, Color(TEXT_DIM, 0.7), HORIZONTAL_ALIGNMENT_CENTER, col_w)


func _government_text() -> String:
	var regent := int(view["regent"])
	var text := "Regente: %s" % _name(regent)
	if int(view["council"]) >= 0 and view["phase"] in [ConjuraGame.Phase.REGENT_DISCARD, ConjuraGame.Phase.COUNCIL_ENACT, ConjuraGame.Phase.CLAIMS, ConjuraGame.Phase.CHOOSE_POWER, ConjuraGame.Phase.USE_POWER]:
		text += "    Consejero: %s" % _name(int(view["council"]))
	elif int(view["nominee"]) >= 0:
		text += "    Nominado: %s" % _name(int(view["nominee"]))
	return text


func _name(pid: int) -> String:
	return player_names[pid] if pid >= 0 and pid < player_names.size() else "—"


## Dibuja una pista de edictos y devuelve la y de debajo.
func _track(y: float, title: String, color: Color, edict: int, filled: int, slots: int, card_w: float, card_h: float, gap: float) -> float:
	var total := slots * card_w + (slots - 1) * gap
	var x0 := (size.x - total) / 2.0
	var panel := Rect2(x0 - 16, y, total + 32, card_h + 58)
	draw_rect(panel, Color(color, 0.12))
	draw_rect(panel, Color(color, 0.5), false, 2.0)
	_text(Vector2(panel.position.x, y + 22), title, 17, color.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER, panel.size.x)
	var cy := y + 32
	for i in slots:
		var rect := Rect2(x0 + i * (card_w + gap), cy, card_w, card_h)
		if i < filled:
			_card(rect, edict, flash if (edict == flash_edict and i == filled - 1) else 0.0)
		else:
			draw_rect(rect, SLOT_BG)
			draw_rect(rect, SLOT_BORDER, false, 1.5)
			var label := _slot_label(edict, i)
			if label != "":
				_text(Vector2(rect.position.x, rect.position.y + card_h * 0.5 + 5), label, 11, Color(TEXT_DIM, 0.9), HORIZONTAL_ALIGNMENT_CENTER, card_w)
		if i == slots - 1:
			_text(Vector2(rect.position.x, rect.end.y + 16), "Victoria", 11, color.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, card_w)
	if edict == Edict.SOMBRA:
		# Desde el 3.er edicto, el Usurpador elegido Consejero gana.
		var mark_x := x0 + D.USURPER_THRESHOLD * (card_w + gap) - gap * 0.5
		draw_line(Vector2(mark_x, cy - 4), Vector2(mark_x, cy + card_h + 4), Color("ffd166"), 2.0)
		_text(Vector2(mark_x + 4, cy + card_h + 16), "Usurpador Consejero = victoria", 11, Color("ffd166"))
	return panel.end.y


func _slot_label(edict: int, index: int) -> String:
	if edict != Edict.SOMBRA:
		return ""
	var number := index + 1
	if number >= D.POWER_FROM and number < D.SOMBRA_TO_WIN:
		return "Poder"
	return ""


func _card(rect: Rect2, edict: int, glow: float) -> void:
	ConjuraArt.draw_edict(self, rect, edict, rect.size.x >= 60.0, glow)


func _meter(center: Vector2, title: String, value: int, maximum: int, color: Color) -> void:
	_text(Vector2(center.x - 100, center.y + 14), title, 15, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 200)
	var spacing := 26.0
	var x0 := center.x - (maximum - 1) * spacing / 2.0
	for i in maximum:
		var p := Vector2(x0 + i * spacing, center.y + 34)
		if i < value:
			draw_circle(p, 9, color)
		else:
			draw_arc(p, 9, 0, TAU, 24, Color(color, 0.6), 2.0)
