"""Maqueta el reglamento de La Conjura en PDF a partir de las capturas.

Uso: python3 tools/reglas/build_conjura.py <carpeta_capturas> <salida.pdf>
Las capturas las saca tools/reglas/capture_conjura.tscn (ver README).
"""

import os
import sys

from reportlab.lib.units import mm
from reportlab.platypus import CondPageBreak, NextPageTemplate, PageBreak, Spacer

from pdf_common import (
    CONTENT_W, H1, H2, SMALL, RulesDoc, bullets, note, p, screenshot, set_theme, side_by_side,
    table,
)

shots, out = sys.argv[1], sys.argv[2]

# Colores de la pantalla de La Conjura (corte nocturna, morado oscuro).
set_theme("#2a2238", "#1b1724", "#ddd2ea", "#a493b8", heading="#4a3566")


def shot(name):
    return os.path.join(shots, name + ".png")


def have(name):
    return os.path.exists(shot(name))


# Zonas de las capturas de 1600x900: tablero central y ventana privada.
BOARD = (390, 15, 1185, 700)
PRIVATE = (995, 15, 1585, 700)
RIGHT = (1170, 15, 1590, 400)
RESULT = (995, 15, 1585, 300)
CURTAIN = (420, 300, 1180, 640)

story = [NextPageTemplate("page"), PageBreak()]

# --- 1. De un vistazo --------------------------------------------------------
story += [
    p("De un vistazo", H1),
    p("Un juego de roles ocultos y deducción. En la corte, la <b>Guardia Real</b> (la mayoría) "
      "intenta gobernar bien, mientras la <b>Hermandad de la Sombra</b> (la minoría) conspira en "
      "secreto para que su líder, el <b>Usurpador</b>, se haga con el poder. Nadie sabe al principio "
      "en quién confiar: hay que votar, observar y adivinar quién miente."),
    table([
        ["Jugadores", "De 5 a 10. Cualquiera puede ser una IA (fácil, normal o difícil)."],
        ["Gana la Guardia", "Con <b>5 edictos de la Guardia</b> o si <b>destierra al Usurpador</b>."],
        ["Gana la Sombra", "Con <b>6 edictos de la Sombra</b> o si el <b>Usurpador sale elegido "
                           "Consejero</b> cuando ya hay 3 o más edictos de la Sombra."],
        ["Rebelión", "Si el descontento llega a 4, gana la facción con <b>menos</b> edictos "
                     "(si empatan, la Guardia)."],
        ["Modos", "<b>En este equipo</b> (con pantallas privadas para lo secreto) o <b>en red local</b> "
                  "(cada uno ve solo lo suyo)."],
    ], [32 * mm, CONTENT_W - 32 * mm], header=False),
    Spacer(1, 6),
    p("Los roles", H2),
    table([
        ["Jugadores", "Guardia Real", "Hermandad de la Sombra"],
        ["5", "3", "1 + Usurpador"],
        ["6", "4", "1 + Usurpador"],
        ["7", "4", "2 + Usurpador"],
        ["8", "5", "2 + Usurpador"],
        ["9", "5", "3 + Usurpador"],
        ["10", "6", "3 + Usurpador"],
    ], [30 * mm, 50 * mm, CONTENT_W - 80 * mm]),
    Spacer(1, 4),
    *bullets([
        "La <b>Guardia</b> no sabe quién es quién.",
        "Los de la <b>Sombra</b> se conocen entre sí y saben quién es el Usurpador.",
        "El <b>Usurpador</b> conoce a sus aliados solo con 5 o 6 jugadores; con más, no sabe quiénes son.",
    ]),
]

# --- 2. Tu rol y la pantalla -------------------------------------------------
story += [
    PageBreak(),
    p("Tu rol y la pantalla", H1),
    p("Al empezar, cada jugador ve su rol en secreto. Las capturas de este reglamento son de una "
      "partida a 7 en la que <b>Ana</b> es de la Hermandad de la Sombra."),
    screenshot(shot("01_rol"), "Ana ve su rol en la ventana privada: es de la Sombra y conoce a sus "
                               "aliados, David (el Usurpador) y Gael."),
    p("La pantalla tiene tres zonas:"),
    *bullets([
        "<b>Izquierda:</b> los jugadores (con lo que tú sabes de ellos, el cargo de cada uno y su "
        "último voto) y el <b>registro</b> público de todo lo que pasa.",
        "<b>Centro: el tablero.</b> El gobierno actual, la pista de la <b>Guardia Real</b> (5 casillas), "
        "la de la <b>Hermandad de la Sombra</b> (6 casillas; desde la 2.ª dan poder y, a partir de la "
        "3.ª, «Usurpador Consejero = victoria»), el <b>descontento</b> (4), la <b>crisis</b> (3) y el mazo.",
        "<b>Derecha:</b> la fase actual y lo que hay que hacer. Si juegas solo en este equipo, debajo "
        "ves siempre tu rol, tus aliados y <b>lo que sabes</b> (lo que viste como Regente o Consejero "
        "y el resultado de tus poderes).",
    ]),
]

# --- 3. Nominación y votación ------------------------------------------------
story += [
    PageBreak(),
    p("Una ronda (1): nominación y votación", H1),
    p("1. Nominación", H2),
    p("El <b>Regente</b> (cambia cada ronda, en orden) nomina a un <b>Consejero</b>. No puede nominar a "
      "quien fue el <b>último Consejero elegido</b>."),
    screenshot(shot("02_nominar"), "Ana es Regente y elige Consejero. Bruno fue el último Consejero y "
                                   "no aparece en la lista.", width=CONTENT_W * 0.84),
    p("2. Votación", H2),
    p("Todos votan <b>a la vez y en secreto</b> si aprueban el gobierno. Se aprueba con <b>más de la "
      "mitad</b> de los votos (el empate lo rechaza). Los votos se revelan todos juntos al final."),
    side_by_side(
        (shot("03_votar"), "Ana vota en su ventana privada.", PRIVATE),
        (shot("04_votos"), "Se revelan los votos: aprobado 5 a 2.", BOARD)),
]

# --- 4. Legislatura ----------------------------------------------------------
story += [
    PageBreak(),
    p("Una ronda (2): la legislatura", H1),
    p("Si el gobierno se aprueba, se promulga un edicto. <b>Nadie más ve las cartas:</b>"),
    *bullets([
        "El <b>Regente</b> roba <b>3 edictos</b>, descarta 1 en secreto y pasa los otros 2 al Consejero.",
        "El <b>Consejero</b> promulga 1 y descarta el otro.",
    ]),
    side_by_side(
        (shot("05_regente"), "Ana, como Regente, ha robado Sombra, Guardia, Sombra y descarta uno.",
         PRIVATE),
        (shot("06_consejero"), "Más tarde, como Consejera, recibe Guardia y Neutral y promulga uno.",
         PRIVATE)),
    p("Los edictos", H2),
    table([
        ["Edicto", "Cartas", "Efecto"],
        ["De la Guardia", "6", "Avanza la pista de la Guardia Real."],
        ["De la Sombra", "11 (+3 con 6 u 8 jugadores)", "Avanza la pista de la Sombra. Desde el 2.º, "
                                                       "el Consejero gana un poder."],
        ["Neutral", "3", "Sube el descontento del pueblo."],
    ], [32 * mm, 50 * mm, CONTENT_W - 82 * mm], swatches={1: "#4f8fd6", 2: "#b8404f", 3: "#c9a96e"}),
    Spacer(1, 4),
    p("Con 6 u 8 jugadores la Hermandad es proporcionalmente más pequeña, por eso lleva 3 edictos de "
      "la Sombra más. Cuando quedan menos de 3 edictos, se baraja el descarte.", SMALL),
]

# --- 5. Declaraciones --------------------------------------------------------
story += [
    PageBreak(),
    p("Una ronda (3): las declaraciones", H1),
    p("Después de promulgar, el Regente dice qué 3 edictos robó y el Consejero qué 2 recibió, o se "
      "callan. <b>Pueden mentir.</b> Si lo que dicen no cuadra entre sí, el registro avisa: "
      "«Las declaraciones no cuadran: alguien miente»."),
    screenshot(shot("07_declarar"),
               "Ana, como Consejera, elige qué dice que le pasó el Regente (o «No decir nada»).",
               width=CONTENT_W * 0.84),
    note("Un edicto de la Sombra promulgado por un gobierno que dice haber recibido solo cartas de la "
         "Guardia es sospechoso… pero quizá miente el otro. Compara lo que dice cada uno con sus "
         "votos y con lo que ves en «Lo que sabes».", "Para pensar"),
    p("Crisis", H2),
    p("Si se rechazan <b>3 gobiernos seguidos</b>, hay crisis: se promulga directamente el primer "
      "edicto del mazo (sin poderes), sube el descontento y se olvida el límite de mandatos (cualquiera "
      "puede volver a ser nominado). La votación avisa cuando la siguiente derrota provocaría una crisis."),
]

# --- 6. Poderes --------------------------------------------------------------
story += [
    PageBreak(),
    p("Poderes", H1),
    p("Desde el <b>2.º edicto de la Sombra</b>, cada vez que un gobierno promulga uno (después de las "
      "declaraciones), el <b>Consejero</b> roba 2 cartas de poder distintas, elige 1 y la usa. La otra "
      "vuelve al mazo."),
    table([
        ["Poder", "Cartas", "Efecto"],
        ["Espiar", "3", "Mira en secreto la facción de otro jugador (el Usurpador aparece como Sombra)."],
        ["Augurio", "2", "Mira en secreto los 3 primeros edictos del mazo."],
        ["Sucesión", "2", "Elige al próximo Regente (después, el orden sigue normal)."],
        ["Destierro", "2", "Un jugador queda fuera de la partida: no vota ni gobierna. Si es el "
                           "Usurpador, gana la Guardia."],
        ["Pesquisa", "2", "Mira en secreto el edicto que descartó el Regente."],
    ], [26 * mm, 16 * mm, CONTENT_W - 42 * mm]),
    Spacer(1, 6),
    side_by_side(
        (shot("09_elegir_poder"), "Ana (Consejera) puede elegir entre Espiar y Augurio.", RIGHT),
        (shot("11_resultado_poder"), "Elige Augurio y ve en secreto los próximos 3 edictos.", RESULT)),
    p("Lo que descubres con un poder se queda en «Lo que sabes» para el resto de la partida. "
      "Puedes contarlo… o mentir sobre ello.", SMALL),
]

# --- 7. Fin de la partida ----------------------------------------------------
story += [
    PageBreak(),
    p("Fin de la partida", H1),
    table([
        ["Gana", "Cómo"],
        ["Guardia Real", "Promulga <b>5 edictos</b> de la Guardia, o <b>destierra al Usurpador</b>."],
        ["Hermandad de la Sombra", "Promulga <b>6 edictos</b> de la Sombra, o el <b>Usurpador sale "
                                   "elegido Consejero</b> cuando ya hay 3 o más edictos de la Sombra."],
        ["Rebelión", "Si el descontento llega a <b>4</b>, el pueblo se rebela y gana la facción con "
                     "<b>menos</b> edictos promulgados (si empatan, la Guardia)."],
    ], [44 * mm, CONTENT_W - 44 * mm]),
    Spacer(1, 6),
    p("Al terminar se revelan todos los roles y el <b>historial de gobiernos</b>: lo que cada Regente "
      "y Consejero dijo frente a lo que de verdad robó y pasó, marcando quién mintió."),
    screenshot(shot("14_final"),
               "La Sombra gana: el Usurpador (David) sale elegido Consejero con 5 edictos de la Sombra. "
               "El historial muestra que Ana mintió en su declaración."),
    screenshot(shot("13_avanzada"), "La partida poco antes del final: Fran ha sido desterrado y el "
                                    "registro de Ana recoge todo lo que ha visto.",
               width=CONTENT_W * 0.7),
]

# --- 8. Varias personas en un equipo -----------------------------------------
story += [
    PageBreak(),
    p("Jugar varias personas en el mismo equipo", H1),
    p("Si varias personas comparten el ordenador, cada vez que hay algo secreto (tu rol, votar, tus "
      "edictos, el resultado de un poder) aparece una pantalla de <b>«Pasa el dispositivo a…»</b>. "
      "Pulsa «mostrar» solo cuando nadie más mire."),
    side_by_side(
        (shot("15_cortina"), "Turno secreto: hay que pasar el dispositivo a Ana para que vote.", CURTAIN),
        (shot("16_cortina_mostrar"), "Ana pulsa «Soy Ana: mostrar» y vota sin que lo vean los demás.",
         PRIVATE)),
    p("Con el botón <b>«Ver mi información»</b> del panel izquierdo cada persona puede repasar en "
      "privado su rol y lo que ha descubierto. En red local no hace falta: cada uno ve lo suyo en su "
      "ordenador."),
    CondPageBreak(80 * mm),
    p("Resumen rápido", H1),
    table([
        ["Paso", "Qué pasa"],
        ["1. Nominación", "El Regente nomina Consejero (no puede repetir el último Consejero elegido)."],
        ["2. Votación", "Todos a la vez. Más de la mitad aprueba. 3 rechazos seguidos: crisis."],
        ["3. Legislatura", "Regente: roba 3, descarta 1. Consejero: de 2, promulga 1."],
        ["4. Declaraciones", "Regente y Consejero dicen lo que vieron (pueden mentir o callar)."],
        ["5. Poder", "Desde el 2.º edicto de la Sombra: el Consejero elige 1 de 2 poderes."],
        ["Victoria", "Guardia: 5 edictos o desterrar al Usurpador. Sombra: 6 edictos o Usurpador "
                     "Consejero con 3+ edictos de la Sombra. Descontento 4: gana quien tenga menos."],
    ], [34 * mm, CONTENT_W - 34 * mm]),
]

doc = RulesDoc(out, "La Conjura", "Roles ocultos y deducción · 5–10 jugadores",
               shot("09_elegir_poder"),
               ["La Guardia Real contra la Hermandad de la Sombra y su Usurpador.",
                "Vota, legisla, declara… y descubre quién miente."])
doc.build(story)
print("PDF:", out)
