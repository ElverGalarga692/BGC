"""Maqueta el reglamento de Archipiélago en PDF a partir de las capturas.

Uso: python3 tools/reglas/build_archipelago.py <carpeta_capturas> <salida.pdf>
Las capturas las saca tools/reglas/capture_archipelago.tscn (ver README).
"""

import os
import sys

from reportlab.lib.units import mm
from reportlab.platypus import CondPageBreak, NextPageTemplate, PageBreak, Spacer

from pdf_common import (
    CONTENT_W, H1, H2, SMALL, RulesDoc, bullets, note, p, screenshot, side_by_side, table,
)

shots, out = sys.argv[1], sys.argv[2]


def shot(name):
    return os.path.join(shots, name + ".png")


# Zona del tablero en las capturas de 1600x900 (sin los paneles laterales).
BOARD = (367, 15, 1195, 885)


story = [NextPageTemplate("page"), PageBreak()]

# --- 1. Objetivo -------------------------------------------------------------
story += [
    p("De un vistazo", H1),
    p("Cada jugador funda poblados en las costas de un archipiélago de islas hexagonales. "
      "Las islas producen recursos cuando sale su número en los dados; con ellos se construyen "
      "caminos, poblados y ciudades, se compran cartas de desarrollo y se comercia con la "
      "banca y con los demás jugadores."),
    table([
        ["Jugadores", "De 2 a 4. Cualquiera de ellos puede ser una IA (fácil, normal o difícil)."],
        ["Objetivo", "<b>Gana el primero que llegue a 10 puntos de victoria durante su turno.</b>"],
        ["Modos", "<b>En este equipo</b> (todos en el mismo ordenador, por turnos) o "
                  "<b>en red local</b> (cada uno en su ordenador; solo ves tu mano)."],
        ["Guardado", "La partida se guarda sola tras cada jugada; en este equipo puedes "
                     "continuarla desde el menú."],
    ], [30 * mm, CONTENT_W - 30 * mm], header=False),
    Spacer(1, 6),
    p("Cómo se consiguen los puntos", H2),
    table([
        ["Fuente", "Puntos", "Notas"],
        ["Poblado", "1", "Cada jugador tiene 5."],
        ["Ciudad", "2", "Sustituye a un poblado. Cada jugador tiene 4."],
        ["Monumento", "1", "Carta de desarrollo; los demás no la ven."],
        ["Camino más largo", "2", "Camino continuo de 5 o más tramos."],
        ["Mayor milicia", "2", "3 o más Milicianos jugados."],
    ], [45 * mm, 20 * mm, CONTENT_W - 65 * mm]),
]

# --- 2. La pantalla ----------------------------------------------------------
story += [
    PageBreak(),
    p("La pantalla de juego", H1),
    screenshot(shot("01_tablero"),
               "Inicio de una partida a tres. Los aros amarillos marcan las esquinas donde se puede "
               "colocar el primer poblado."),
    p("La pantalla tiene tres zonas:"),
    *bullets([
        "<b>Izquierda: jugadores y registro.</b> Cada fila muestra el color, los puntos visibles, las "
        "cartas en la mano, las cartas de desarrollo, los Milicianos jugados y la longitud del camino "
        "más largo. La flecha ▶ indica de quién es el turno. Debajo, el registro cuenta todo lo que pasa.",
        "<b>Centro: el tablero</b>, en 3D o en 2D (se cambia con el botón del panel izquierdo).",
        "<b>Derecha: tus acciones.</b> Arriba, de quién es el turno, sus puntos y qué hay que hacer "
        "ahora. Después, los dados, la mano de recursos, los botones de construir (con su coste), "
        "las cartas de desarrollo, el comercio y <b>Terminar turno</b>.",
    ]),
    note("Pasa el ratón por encima de un botón desactivado para ver por qué no se puede usar "
         "(por ejemplo, «No tienes recursos suficientes»).", "Truco"),
]

# --- 3. El tablero -----------------------------------------------------------
story += [
    PageBreak(),
    p("El tablero", H1),
    p("El archipiélago tiene <b>19 casillas</b> que se reparten al azar en cada partida. Cada terreno "
      "produce un recurso:"),
    table([
        ["", "Terreno", "Recurso", "Casillas"],
        ["", "Bosque", "Madera", "4"],
        ["", "Colinas", "Ladrillo", "3"],
        ["", "Pastos", "Lana", "4"],
        ["", "Campos", "Trigo", "4"],
        ["", "Montañas", "Mineral", "3"],
        ["", "Desierto", "Nada (empieza aquí el bandido)", "1"],
    ], [10 * mm, 40 * mm, CONTENT_W - 80 * mm, 30 * mm],
        swatches={1: "#2f7a3b", 2: "#c4623a", 3: "#9ccc5a", 4: "#e8c33f", 5: "#8a8f99", 6: "#e3cf98"}),
    Spacer(1, 6),
    screenshot(shot("01b_tablero_2d"), "El mismo tablero en la vista 2D: se leen mejor los números y "
                                       "los puertos.", width=CONTENT_W * 0.86),
    p("Los números", H2),
    p("Cada casilla (menos el desierto) lleva un número del 2 al 12. Los <b>puntos bajo el número</b> "
      "indican lo probable que es que salga con dos dados: cuantos más puntos, más produce. "
      "El <b>6 y el 8</b>, en rojo, son los más frecuentes (5 puntos) y nunca están juntos. "
      "El 2 y el 12 son los más raros (1 punto)."),
    p("Los puertos", H2),
    p("Alrededor de la costa hay <b>9 puertos</b>, cada uno unido a dos esquinas. Si tienes un "
      "edificio en una de ellas, comercias mejor con la banca: los 4 puertos <b>3:1</b> sirven "
      "para cualquier recurso y los 5 puertos <b>2:1</b> solo para el recurso de su color."),
]

# --- 4. Colocación inicial ---------------------------------------------------
story += [
    PageBreak(),
    p("Colocación inicial", H1),
    p("Antes de empezar, cada jugador coloca <b>dos poblados y dos caminos</b> gratis:"),
    *bullets([
        "<b>Primera ronda</b>, en el orden de juego: cada jugador pone un poblado en una esquina "
        "libre y después un camino pegado a ese poblado.",
        "<b>Segunda ronda</b>, en orden inverso: el último en colocar repite enseguida y el primero "
        "coloca el último.",
        "Con el <b>segundo poblado</b> recibes una carta de cada casilla que toca.",
        "Ningún poblado puede estar en una esquina vecina de otro edificio (hay que dejar al "
        "menos un lado libre entre ellos).",
    ]),
    screenshot(shot("02_colocacion_camino"),
               "Ana ya ha puesto su primer poblado; los lados resaltados son donde puede ir su camino."),
    note("Busca esquinas que toquen números con muchos puntos y recursos variados. La Madera y el "
         "Ladrillo hacen falta al principio; el Trigo y el Mineral, para las ciudades."),
]

# --- 5. El turno -------------------------------------------------------------
story += [
    PageBreak(),
    p("Tu turno", H1),
    p("Cada turno tiene tres pasos:"),
    *bullets([
        "<b>1. Tira los dados</b> con el botón <b>Tirar dados</b>. Todas las casillas con ese número "
        "producen: cada <b>poblado</b> que las toca recibe <b>1 carta</b> de su recurso y cada "
        "<b>ciudad 2</b>. Producen para todos los jugadores, no solo para quien tira. La casilla "
        "donde está el bandido no produce.",
        "<b>2. Construye, compra y comercia</b> en el orden que quieras y tantas veces como puedas pagar.",
        "<b>3. Termina el turno</b> con el botón <b>Terminar turno</b>.",
    ]),
    screenshot(shot("03_primer_turno"),
               "Primer turno tras la colocación: el registro muestra las cartas iniciales y el panel "
               "derecho pide tirar los dados."),
    note("Cada recurso tiene 19 cartas en la banca. Si en una tirada la banca no tiene bastante de un "
         "recurso para todos los que deben recibirlo, ese recurso no lo recibe nadie.", "Detalle"),
]

# --- 6. Construir ------------------------------------------------------------
story += [
    PageBreak(),
    p("Construir", H1),
    table([
        ["Construcción", "Coste", "Reglas"],
        ["Camino", "Madera + Ladrillo",
         "En un lado conectado a tus caminos o edificios. Un edificio rival corta la conexión."],
        ["Poblado (1 PV)", "Madera + Ladrillo + Lana + Trigo",
         "En una esquina que toque uno de tus caminos, sin edificios en las esquinas vecinas."],
        ["Ciudad (2 PV)", "2 Trigo + 3 Mineral",
         "Mejora uno de tus poblados (el poblado vuelve a tu reserva). Produce el doble."],
        ["Carta de desarrollo", "Lana + Trigo + Mineral", "Se roba del mazo. Ver «Cartas de desarrollo»."],
    ], [36 * mm, 46 * mm, CONTENT_W - 82 * mm]),
    Spacer(1, 4),
    p("Cada jugador tiene <b>15 caminos, 5 poblados y 4 ciudades</b>. Cuando se acaban, no se "
      "pueden construir más de ese tipo.", SMALL),
    Spacer(1, 4),
    p("Pulsa el botón de lo que quieras construir: el tablero resalta los sitios válidos. Haz clic en "
      "uno para construir, o clic derecho / Esc para cancelar."),
    screenshot(shot("04_construir_poblado"),
               "Ana ha pulsado «Poblado»: el aro amarillo marca la única esquina donde puede "
               "construirlo ahora mismo."),
]

# --- 7. El 7 y el bandido ----------------------------------------------------
story += [
    PageBreak(),
    p("El 7 y el bandido", H1),
    p("Si los dados suman <b>7</b>, nadie produce. En su lugar:"),
    *bullets([
        "<b>Descartes:</b> todo jugador con <b>más de 7 cartas</b> devuelve a la banca la mitad, "
        "redondeando hacia abajo (con 9 cartas, descarta 4). Cada uno elige cuáles.",
        "<b>Bandido:</b> después, el jugador en turno mueve el bandido a otra casilla y "
        "<b>roba una carta al azar</b> a un jugador que tenga un edificio en ella.",
        "Mientras el bandido esté en una casilla, esa casilla <b>no produce</b>.",
    ]),
    Spacer(1, 4),
    side_by_side(
        (shot("05_descartar"), "Ha salido un 7 y Ana tiene 8 cartas: debe elegir 4 para descartar.", BOARD),
        (shot("06_bandido"), "Ana mueve el bandido: las casillas resaltadas son destinos válidos.", BOARD)),
    p("Si en la casilla elegida hay edificios de varios jugadores, una ventana pregunta a quién "
      "robar. Si no hay nadie con cartas, el bandido se mueve sin robar."),
    screenshot(shot("06_bandido"), "La misma situación con la pantalla completa: el registro "
                                   "muestra el 7 que acaba de salir.", width=CONTENT_W * 0.8),
]

# --- 8. Comercio -------------------------------------------------------------
story += [
    PageBreak(),
    p("Comerciar", H1),
    p("Durante tu turno (después de tirar) puedes comerciar todas las veces que quieras."),
    p("Con la banca", H2),
    p("Das <b>4 cartas iguales</b> y recibes 1 de otro recurso. Con un edificio en un puerto el "
      "cambio mejora a <b>3:1</b> (puerto genérico) o <b>2:1</b> (puerto de ese recurso). "
      "La ventana ya muestra el mejor cambio que tienes para cada recurso."),
    screenshot(shot("07_comercio_banca"),
               "Carta tiene un puerto 2:1 de Trigo, así que cambia 2 Trigo por 1 Mineral.",
               width=CONTENT_W * 0.78),
    p("Con otros jugadores", H2),
    p("Pulsa <b>Con jugadores</b>, elige a quién y qué cartas das y pides. El otro jugador puede "
      "<b>aceptar</b> o <b>rechazar</b>, y tú puedes retirar la oferta mientras espera. "
      "No se puede dar y pedir el mismo recurso en una oferta."),
    side_by_side(
        (shot("08_proponer_intercambio"), "Ventana para proponer un intercambio.", BOARD),
        (shot("09_oferta_recibida"), "Bruno recibe la oferta de Carla y decide si la acepta.", BOARD)),
]

# --- 9. Cartas de desarrollo -------------------------------------------------
story += [
    PageBreak(),
    p("Cartas de desarrollo", H1),
    p("Se compran por Lana + Trigo + Mineral. El mazo tiene 25 cartas:"),
    table([
        ["Carta", "Cartas", "Efecto"],
        ["Miliciano", "14", "Mueve el bandido y roba una carta. Cuenta para la Mayor milicia. "
                            "<b>Se puede jugar antes de tirar los dados.</b>"],
        ["Monumento", "5", "1 punto de victoria, oculto para los demás. No se juega: cuenta solo."],
        ["Ingenieros", "2", "Construye 2 caminos gratis."],
        ["Cosecha abundante", "2", "Toma 2 recursos cualesquiera de la banca (pueden ser iguales)."],
        ["Monopolio", "2", "Elige un recurso: todos los demás te dan todas sus cartas de ese recurso."],
    ], [38 * mm, 18 * mm, CONTENT_W - 56 * mm]),
    Spacer(1, 6),
    *bullets([
        "Solo puedes jugar <b>una carta por turno</b>.",
        "Nunca la puedes jugar el <b>mismo turno en que la compras</b> (el panel la marca como «nueva»).",
        "Antes de tirar los dados solo se puede jugar un Miliciano.",
    ]),
    screenshot(shot("10_cartas_desarrollo"),
               "Carla tiene dos Milicianos, uno comprado en este turno: «Jugar Miliciano ×2 (1 nueva)».",
               width=CONTENT_W * 0.86),
]

# --- 10. Premios -------------------------------------------------------------
story += [
    PageBreak(),
    p("Premios", H1),
    p("Hay dos premios de <b>2 puntos</b> cada uno. El panel de jugadores marca con una estrella "
      "quién los tiene."),
    table([
        ["Premio", "Quién lo consigue"],
        ["Camino más largo",
         "El primero con un camino continuo de <b>5 o más tramos</b> (no cuentan las ramas). "
         "Pasa a quien tenga uno <b>más largo</b>; en caso de empate lo conserva quien lo tenía. "
         "Un poblado o ciudad rival en medio corta el camino."],
        ["Mayor milicia",
         "El primero que juegue <b>3 Milicianos</b>. Pasa a quien juegue más que quien la tiene."],
    ], [38 * mm, CONTENT_W - 38 * mm]),
    Spacer(1, 8),
    screenshot(shot("11_partida_avanzada"),
               "Partida avanzada: Bruno tiene el Camino más largo (★) y ya va por 7 puntos."),
]

# --- 11. Vista 2D/3D y controles ---------------------------------------------
story += [
    PageBreak(),
    p("Vistas y controles", H1),
    p("El botón <b>Cambiar a vista 2D/3D</b> del panel izquierdo alterna las dos vistas del tablero; "
      "el juego recuerda tu elección. Las reglas son las mismas en las dos."),
    screenshot(shot("12_vista_2d"), "La misma partida avanzada en la vista 2D."),
    table([
        ["Control", "Qué hace"],
        ["Clic izquierdo", "Elegir casilla, esquina o lado."],
        ["Clic derecho o Esc", "Cancelar la construcción en curso."],
        ["Rueda del ratón", "Zoom (vista 3D)."],
        ["Botón central (arrastrar) o Q / E", "Girar la cámara (vista 3D)."],
    ], [62 * mm, CONTENT_W - 62 * mm]),
    Spacer(1, 6),
    p("En partidas con IA puedes activar el modo rápido para que las IAs jueguen más deprisa.", SMALL),
]

# --- 12. Fin de la partida ---------------------------------------------------
story += [
    PageBreak(),
    p("Fin de la partida", H1),
    p("En cuanto un jugador llega a <b>10 puntos de victoria durante su propio turno</b> (contando "
      "sus Monumentos ocultos), gana la partida. Si llegas a 10 en el turno de otro, ganas al "
      "empezar a jugar en el tuyo."),
    screenshot(shot("13_victoria"),
               "Bruno gana con 10 puntos. Se puede empezar otra partida con los mismos jugadores o "
               "volver al menú.", width=CONTENT_W * 0.8),
]

# --- 13. Resumen -------------------------------------------------------------
story += [
    CondPageBreak(75 * mm),
    p("Resumen rápido", H1),
    table([
        ["Paso", "Qué hacer"],
        ["Preparación", "2 poblados + 2 caminos por jugador, en serpiente. El 2.º poblado da recursos."],
        ["1. Dados", "Las casillas con ese número producen (poblado 1, ciudad 2). "
                     "Con un 7: descartes si tienes más de 7 cartas, bandido y robo."],
        ["2. Acciones", "Construir, comprar cartas, comerciar (banca 4:1 / 3:1 / 2:1, o con jugadores) "
                        "y jugar 1 carta de desarrollo."],
        ["3. Fin", "Terminar turno."],
        ["Costes", "Camino: Mad + Lad · Poblado: Mad + Lad + Lan + Tri · Ciudad: 2 Tri + 3 Min · "
                   "Carta: Lan + Tri + Min"],
        ["Victoria", "10 puntos en tu turno."],
    ], [32 * mm, CONTENT_W - 32 * mm]),
]

doc = RulesDoc(out, "Archipiélago", "Coloniza, comercia y construye · 2–4 jugadores",
               shot("11_partida_avanzada"),
               ["Coloniza islas hexagonales, recoge recursos, comercia y construye.",
                "El primero que llegue a 10 puntos de victoria gana."])
doc.build(story)
print("PDF:", out)
