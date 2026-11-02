"""Maqueta el reglamento de Pests! en PDF a partir de las capturas.

Uso: python3 tools/reglas/build_pests.py <carpeta_capturas> <salida.pdf>
Las capturas las saca tools/reglas/capture_pests.tscn (ver README).
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

# Colores de la pantalla de Pests! (fondo marrón de la casa).
set_theme("#3a2c26", "#2b2320", "#e8d9c8", "#b59d88", heading="#5a3a2c")


def shot(name):
    return os.path.join(shots, name + ".png")


def have(name):
    return os.path.exists(shot(name))


# Zona del tablero en las capturas de 1600x900 y un recorte de la casa.
BOARD = (393, 15, 1170, 885)
HOUSE = (490, 215, 1175, 690)
TILES = (393, 190, 1170, 720)

SPECIES = [
    ["", "Exterminador", "Habilidad"],
    ["", "<b>Amarillo</b>: Bichos voladores",
     "Su trampa atrae también las plagas de las habitaciones vecinas. Su reina avanza 2 "
     "habitaciones por tirada."],
    ["", "<b>Verde</b>: Rastreros escalofriantes", "Tiene 2 trampas."],
    ["", "<b>Rojo</b>: Bestias aladas",
     "+1 a la tirada al exterminar. Al poblar, sus plagas aparecen a 2 habitaciones."],
    ["", "<b>Azul</b>: Alimañas feroces", "Su trampa admite 9 plagas (en vez de 7)."],
    ["", "<b>Naranja</b>: Huéspedes indeseados",
     "Sellar su nido le cuesta 1 punto (en vez de 2). Su nido genera 1 plaga más cada turno."],
    ["", "<b>Morado</b>: Espectros espeluznantes",
     "Destruir su trampa cuesta 2 puntos a los rivales. Su reina y sus plagas atraviesan paredes."],
]
SPECIES_SWATCH = {1: "#e9d64a", 2: "#4caf50", 3: "#e2504c", 4: "#4f6fc4", 5: "#f0a030", 6: "#9b5fc0"}

story = [NextPageTemplate("page"), PageBreak()]

# --- 1. De un vistazo --------------------------------------------------------
story += [
    p("De un vistazo", H1),
    p("Eres un exterminador especializado en una plaga. El dueño de una casa infestada ha "
      "contratado a varios a la vez, pero <b>solo cobra el primero que termine su trabajo</b>. "
      "Cada jugador tiene su color: su exterminador, su reina, su nido y sus plagas."),
    table([
        ["Jugadores", "De 2 a 6. Cualquiera de ellos puede ser una IA (fácil, normal o difícil)."],
        ["Objetivo", "<b>Sellar tu nido, eliminar todas tus plagas de la casa y atrapar a tu reina; "
                     "después, vaciar la trampa con tu reina.</b>"],
        ["Derrota", "Si al acabar tu turno <b>todas tus plagas disponibles están en la casa</b>, "
                    "quedas eliminado."],
        ["Modos", "<b>En este equipo</b> (por turnos en el mismo ordenador) o <b>en red local</b>. "
                  "Opcional: reglas rápidas, casa al azar y partida por equipos."],
        ["Guardado", "La partida se guarda sola tras cada jugada."],
    ], [28 * mm, CONTENT_W - 28 * mm], header=False),
    Spacer(1, 6),
    p("Opciones del menú", H2),
    table([
        ["Opción", "Qué cambia"],
        ["Reglas rápidas", "Los exterminadores y las cartas de herramientas se reparten al azar "
                           "(se salta la elección)."],
        ["Construir la casa al azar", "La casa se monta sola (activada por defecto). Desactívala "
                                      "para colocar las losetas a mano."],
        ["Por equipos", "Con 4 o 6 jugadores, dos equipos que ganan o pierden juntos "
                        "(ver la última sección)."],
    ], [48 * mm, CONTENT_W - 48 * mm]),
]

# --- 2. Los exterminadores ---------------------------------------------------
story += [
    PageBreak(),
    p("Los exterminadores", H1),
    p("Hay seis exterminadores, uno por color. Cada uno tiene una habilidad que cambia una regla:"),
    table(SPECIES, [8 * mm, 62 * mm, CONTENT_W - 70 * mm], swatches=SPECIES_SWATCH),
    Spacer(1, 6),
    p("Cada jugador elige exterminador por turnos, en sentido <b>antihorario</b> desde el jugador "
      "inicial. El panel derecho muestra los que quedan, con su habilidad."),
    screenshot(shot("01_elegir_exterminador"),
               "Carla elige exterminador. En el centro, la entrada de la casa con la rosa de los "
               "vientos (U, D, L, R) y el jardín.", width=CONTENT_W * 0.86),
]

# --- 3. Preparación: cartas y casa -------------------------------------------
story += [
    PageBreak(),
    p("Preparación", H1),
    p("1. Cartas de herramientas", H2),
    p("Hay 24 cartas distintas (12 defensivas y 12 ofensivas). Se ponen boca arriba y se eligen "
      "una a una, en sentido <b>horario</b> empezando por el último que eligió exterminador, hasta "
      "que cada jugador tiene <b>4</b>. Las que sobran forman el mazo."),
    screenshot(shot("02_elegir_cartas"), "Elección de cartas: defensivas arriba, ofensivas abajo. "
                                         "Pasa el ratón por una carta para leer su efecto.",
               width=CONTENT_W * 0.6),
    p("2. La casa", H2),
    p("Se parte de la <b>entrada</b> (con la rosa de los vientos, que marca arriba, abajo, izquierda "
      "y derecha) y su jardín. Cada jugador recibe losetas y por turnos coloca una:"),
    *bullets([
        "Debe tocar la casa y al menos una de sus puertas debe conectarla con ella.",
        "Sus puertas deben coincidir con las de al lado: <b>ninguna puerta puede dar a una pared</b>. "
        "Las puertas al exterior sí están permitidas.",
        "Tu <b>nido</b> (con puertas en los 4 lados) no se puede colocar antes de la 3.ª ronda.",
        "Con menos de 6 jugadores se retiran algunas losetas (4 con 2 jugadores, 3 con 3, 2 con 4, "
        "1 con 5).",
    ]),
]
tile_shots = [(shot("03_colocar_loseta"), "Ana ha elegido una loseta: las casillas resaltadas son "
               "donde cabe con ese giro. «Girar loseta» (o R) la gira.", TILES)]
if have("03b_colocar_nido"):
    tile_shots.append((shot("03b_colocar_nido"), "En la 3.ª ronda Carla ya puede colocar su nido.",
                       TILES))
story += [side_by_side(*tile_shots) if len(tile_shots) == 2 else screenshot(*tile_shots[0][:2])]

# --- 4. La infestación y las piezas ------------------------------------------
story += [
    PageBreak(),
    p("La infestación", H1),
    p("Con la casa completa empieza la partida:"),
    *bullets([
        "Tu <b>exterminador</b> empieza en la entrada y tu <b>reina</b> en tu nido.",
        "Pones <b>3 plagas</b> en tu nido y <b>4</b> en las habitaciones conectadas a él, en orden DLUR.",
        "Cada color tiene 24 plagas, menos las que se devuelven a la caja según los jugadores "
        "(4 con 2 jugadores, 3 con 3, 2 con 4, 1 con 5). Las que no están en la casa forman tu "
        "<b>reserva</b>.",
    ]),
    note("<b>Orden DLUR</b>: abajo (D), izquierda (L), arriba (U), derecha (R), según la rosa de los "
         "vientos de la entrada. Cuando hay que repartir plagas o desempatar, se sigue este orden, "
         "dando la vuelta si hace falta.", "Importante"),
    screenshot(shot("04_casa_infestada"),
               "La casa infestada al empezar. Cada nido tiene su reina (con corona) y sus plagas; los "
               "cuatro exterminadores esperan en la entrada."),
    p("En el panel izquierdo, cada jugador muestra su <b>reserva</b>, sus plagas <b>en la casa</b> y "
      "<b>en trampas</b>, si su nido está sellado, si su reina está atrapada y cuántas cartas tiene.",
      SMALL),
]

story += [
    PageBreak(),
    p("Las piezas en el tablero", H1),
    screenshot(shot("08_reina_atrapada"), "Detalle de la casa a media partida.", crop=HOUSE),
    table([
        ["Pieza", "Cómo se ve"],
        ["Nido", "Habitación del color del jugador con un agujero negro. Cuando se sella, lleva el "
                 "sello rojo «SELLADO»."],
        ["Reina", "Bicho con corona, del color de su jugador."],
        ["Plagas", "Bichos del color de su jugador con un número: cuántas hay de ese color en la "
                   "habitación."],
        ["Exterminador", "Figura de persona del color del jugador."],
        ["Trampa", "Jaula. Si tiene plagas o una reina, se ve dentro."],
    ], [32 * mm, CONTENT_W - 32 * mm]),
]

# --- 5. El turno: la reina ---------------------------------------------------
story += [
    PageBreak(),
    p("Tu turno (1): la reina", H1),
    p("Primero activas a tu reina con <b>Tirar el dado de la reina</b> (en tu primer turno, dos veces). "
      "El dado tiene seis caras, cada una con una letra y el color del exterminador que lleva esa "
      "letra en su carta:"),
    table([
        ["Cara", "Color", "Qué hace la reina"],
        ["U / D / L / R", "Rojo / Naranja / Amarillo / Verde",
         "Se mueve una habitación arriba, abajo, a la izquierda o a la derecha (por una puerta)."],
        ["S (invocar)", "Azul",
         "Todas tus plagas avanzan una habitación hacia la reina. Si hay varios caminos igual de "
         "cortos, se reparten; las que sobran siguen el orden DLUR."],
        ["P (poblar)", "Morado",
         "En vez de soltar 1 plaga donde está, la reina reparte 4 en las habitaciones vecinas (DLUR)."],
    ], [30 * mm, 46 * mm, CONTENT_W - 76 * mm]),
    Spacer(1, 6),
    *bullets([
        "Después la reina <b>suelta 1 plaga</b> en su habitación (salvo con P) y <b>sale 1 plaga nueva "
        "de tu nido</b> si no está sellado.",
        "Si la reina <b>no puede hacer su acción</b> (hay una pared, no hay nada que invocar…), se "
        "enfada y suelta <b>2 plagas</b> en vez de 1.",
        "Si sale de la casa por una puerta exterior, vuelve a entrar por la puerta más cercana de "
        "otra habitación, rodeando la casa por fuera (en empate, en el sentido de las agujas del reloj). "
        "Si sale a un patio interior sin otra puerta, vuelve a su habitación y suelta 2 plagas.",
        "Una <b>reina atrapada</b> solo escapa si sale su color en el dado. Aunque esté atrapada, su "
        "nido sigue generando plagas si no está sellado.",
    ]),
    note("Antes de tirar puedes jugar gratis <b>Las plagas hibernan</b> o <b>Control mental</b>.",
         "Recuerda"),
]

# --- 6. El turno: el exterminador --------------------------------------------
story += [
    PageBreak(),
    p("Tu turno (2): el exterminador", H1),
    p("Después tienes <b>1 movimiento gratis</b> y <b>2 puntos de acción (PA)</b>. Si empiezas con otra "
      "acción que no sea moverte, pierdes el movimiento gratis. Los puntos que no uses se pierden. "
      "Termina con <b>Terminar turno</b>."),
    table([
        ["Acción", "PA", "Detalle"],
        ["Moverse", "1", "A una habitación vecina, solo por puertas. Haz clic en una habitación resaltada."],
        ["Exterminar", "1", "Tira el d6 y quita ese número de plagas de tu color de tu habitación. "
                            "Vuelven a tu reserva."],
        ["Soltar trampa", "1", "En tu habitación (no en tu nido)."],
        ["Vaciar trampa", "1", "Una trampa tuya en tu habitación: sus plagas vuelven a tu reserva. Si tiene a tu reina, necesitas el nido "
                               "sellado y ninguna plaga tuya en la casa: <b>así se gana</b>."],
        ["Arrastrar trampa", "2", "Te mueves con una trampa a la habitación de al lado."],
        ["Sellar tu nido", "2", "Estando en él (1 PA para el naranja). Deja de generar plagas."],
        ["Destruir trampa rival", "1", "En tu habitación (2 PA si es del morado)."],
        ["Desellar nido rival", "2", "Estando en él."],
        ["Jugar una carta", "1", "Salvo las de «antes de tirar», que son gratis."],
        ["Comprar una carta", "2", "Del mazo (si se acaba, al azar del descarte)."],
    ], [38 * mm, 12 * mm, CONTENT_W - 50 * mm]),
    Spacer(1, 6),
    screenshot(shot("05_turno_exterminador"),
               "Turno del exterminador de Carla: arriba, la tirada de la reina y los puntos que le quedan; "
               "las habitaciones resaltadas son a donde puede moverse.", width=CONTENT_W * 0.86),
]

# --- 7. Trampas --------------------------------------------------------------
story += [
    PageBreak(),
    p("Trampas", H1),
    *bullets([
        "Una trampa guarda <b>7 plagas de su color o su reina</b>, nunca las dos cosas (el azul, 9 "
        "plagas; el verde tiene 2 trampas).",
        "Al soltarla atrapa lo que haya de su color en la habitación y sigue atrapando lo que entre "
        "hasta llenarse. Si en una trampa vacía coinciden reina y plagas, se atrapa lo que eligió su "
        "dueño al soltarla (por defecto, la reina).",
        "Si una reina entra en una trampa a mitad de su movimiento, se detiene ahí.",
        "Las plagas que están en una trampa <b>no cuentan como «en la casa»</b>.",
    ]),
    screenshot(shot("08_reina_atrapada"),
               "Ana suelta su trampa en el Nido azul y atrapa a su reina naranja. Su nido ya está "
               "sellado: solo le falta eliminar sus plagas de la casa y vaciar la trampa.",
               width=CONTENT_W * 0.66),
    p("Sellar el nido", H2),
    p("Un nido sellado no genera plagas nuevas, pero un rival puede desellarlo (2 PA o con una carta)."),
    screenshot(shot("09_nido_sellado"),
               "Ana acaba de sellar su nido naranja: en el panel izquierdo pone «nido sellado».",
               width=CONTENT_W * 0.66),
]

# --- 8. Cartas ---------------------------------------------------------------
story += [
    PageBreak(),
    p("Cartas de herramientas", H1),
    p("Jugar una carta cuesta 1 PA y se descarta al final de tu turno. Las que se quedan "
      "<b>delante de un jugador</b> se descartan cuando se cumple su efecto (el panel izquierdo las "
      "muestra en «Delante:»). En la mano, las defensivas se ven en verde y las ofensivas en rojo."),
    p("Defensivas (te ayudan a ti)", H2),
    table([
        ["Carta", "Efecto"],
        ["Más tiempo", "2 acciones extra este turno."],
        ["Las plagas hibernan", "<i>Antes de tirar, gratis.</i> Tu reina no actúa y tu nido no genera "
                                "plagas este turno."],
        ["Control mental", "<i>Antes de tirar, gratis.</i> Eliges la acción de tu reina en vez de tirar."],
        ["Llamada de apareamiento", "Tus plagas avanzan 2 habitaciones hacia ti."],
        ["Colapso de la colonia", "Extermina la mitad (hacia arriba) de tus plagas en la habitación "
                                  "donde más tienes."],
        ["Bomba insecticida", "Elimina todas tus plagas de tu habitación."],
        ["Bebida energética", "Como única acción, muévete hasta 4 habitaciones."],
        ["Trampa exprés", "Suelta y vacía una trampa en tu habitación."],
        ["Sellado exprés", "Sella el nido de tu habitación (aunque sea de otro)."],
        ["Trampa a distancia", "Vacía tu trampa aunque esté en otra habitación."],
        ["De vuelta al nido", "Tu reina vuelve a su nido."],
        ["¡Zas!", "Extermina hasta 3 de tus plagas en cualquier habitación."],
    ], [46 * mm, CONTENT_W - 46 * mm]),
    PageBreak(),
    p("Ofensivas (contra un rival)", H2),
    table([
        ["Carta", "Efecto"],
        ["Desellar nido", "Quita el sello del nido de otro jugador."],
        ["Trampa rota", "Devuelve una trampa a su dueño; su contenido queda libre."],
        ["Oleada de plagas", "Salen 5 plagas del nido elegido, aunque esté sellado."],
        ["Herramientas saboteadas", "Descarta al azar una carta de otro jugador."],
        ["Menos que infestar", "5 plagas de su reserva vuelven a la caja."],
        ["¡Se extienden!", "4 plagas suyas alrededor de una habitación donde ya tenga (DLUR)."],
        ["Reina furiosa", "<i>Delante.</i> Su próxima tirada se hace dos veces."],
        ["¡Atascado!", "<i>Delante.</i> Su próximo turno, sin movimiento gratis y con 1 acción."],
        ["Persuasión real", "<i>Delante.</i> Tú eliges la acción de su reina en su próximo turno."],
        ["De dos en dos", "<i>Delante.</i> Su nido genera 1 plaga más hasta que lo selle."],
        ["Fértil", "<i>Delante.</i> Su reina suelta 1 plaga más hasta que sea atrapada."],
        ["Buscador de basura", "Toma una carta ofensiva del descarte y úsala."],
    ], [46 * mm, CONTENT_W - 46 * mm]),
]
if have("06_jugar_carta"):
    story += [
        Spacer(1, 6),
        screenshot(shot("06_jugar_carta"),
                   "Al jugar una carta ofensiva, una ventana pregunta contra quién.",
                   width=CONTENT_W * 0.8),
    ]

# --- 9. Fin de la partida ----------------------------------------------------
story += [
    PageBreak(),
    p("Cómo se gana y cómo se pierde", H1),
    p("Para ganar hay que cumplir, <b>en cualquier orden</b>:"),
    *bullets([
        "<b>Sellar tu nido.</b>",
        "<b>Eliminar todas tus plagas de la casa</b> (las que estén en otra trampa tuya no cuentan).",
        "<b>Atrapar a tu reina</b> con una trampa.",
    ]),
    p("Por último, con todo eso cumplido, <b>vacías la trampa con tu reina</b> (1 PA) y ganas. "
      "Las plagas exterminadas vuelven a tu reserva y pueden volver a salir: por eso sellar el nido "
      "y atrapar a la reina es imprescindible."),
    p("<b>Eliminación:</b> si al final de tu turno todas tus plagas disponibles están en la casa, la "
      "infestación es completa y quedas fuera. Tus plagas, tu reina y tus trampas salen de la casa. "
      "Si solo queda un jugador, gana."),
    side_by_side(
        (shot("11_antes_del_final"), "Ana ya tiene el nido sellado, ninguna plaga en la casa y su "
                                     "reina atrapada en el Nido azul.", BOARD),
        (shot("12_victoria"), "Vacía la trampa con su reina y gana la partida.", BOARD)),
]

# --- 10. Por equipos ---------------------------------------------------------
story += [
    PageBreak(),
    p("Partida por equipos (opcional)", H1),
    p("Con 4 o 6 jugadores se puede jugar en dos equipos alternos: los jugadores 1, 3 y 5 (equipo A) "
      "contra 2, 4 y 6 (equipo B)."),
    *bullets([
        "<b>Ganáis</b> cuando todos los nidos del equipo están sellados, no queda ninguna plaga del "
        "equipo en la casa, todas sus reinas están atrapadas y uno de vosotros vacía la trampa con "
        "su reina.",
        "<b>Perdéis</b> si cualquier jugador del equipo tiene todas sus plagas en la casa al final de "
        "su turno: cae todo el equipo.",
        "Puedes <b>exterminar plagas de cualquier color</b> (eliges cuáles), pero solo sellas tu nido "
        "(salvo con una carta) y tu trampa solo atrapa tu color.",
        "En la misma habitación que un compañero podéis <b>daros y coger cartas</b> gratis (0 PA).",
        "Las cartas ofensivas, desellar nidos y destruir trampas solo se usan contra el equipo rival.",
    ]),
    screenshot(shot("13_equipos"),
               "Partida por equipos con la casa construida al azar: junto a cada exterminador se indica su "
               "equipo y aparecen las acciones para dar y coger cartas.", width=CONTENT_W * 0.72),
]

# --- 11. Resumen y controles -------------------------------------------------
story += [
    CondPageBreak(100 * mm),
    p("Resumen rápido", H1),
    table([
        ["Paso", "Qué hacer"],
        ["Preparación", "Elegir exterminador (antihorario) y 4 cartas (horario). Construir la casa. "
                        "3 plagas en tu nido y 4 alrededor (DLUR)."],
        ["1. Reina", "Tirar su dado (dos veces el primer turno): moverse, invocar o poblar; suelta 1 "
                     "plaga (2 si no puede actuar). Sale 1 plaga del nido si está abierto."],
        ["2. Exterminador", "1 movimiento gratis (si es lo primero que haces) + 2 PA: moverse, "
                            "exterminar, trampas, sellar, cartas…"],
        ["3. Fin", "Terminar turno. Si todas tus plagas están en la casa, quedas eliminado."],
        ["Victoria", "Nido sellado + ninguna plaga en la casa + reina atrapada → vaciar esa trampa."],
    ], [32 * mm, CONTENT_W - 32 * mm]),
    Spacer(1, 10),
    p("Controles", H2),
    table([
        ["Control", "Qué hace"],
        ["Clic en una habitación resaltada", "Mover a tu exterminador o colocar la loseta elegida."],
        ["R o «Girar loseta»", "Girar la loseta durante la construcción de la casa."],
        ["Pasar el ratón", "Ver qué hay en una habitación, el efecto de una carta o por qué una "
                           "acción no se puede hacer."],
        ["IA rápida", "Las IAs juegan más deprisa."],
    ], [62 * mm, CONTENT_W - 62 * mm]),
    Spacer(1, 6),
    p("El juego incluye en el botón <b>Reglas</b> las aclaraciones sobre los casos dudosos del "
      "reglamento original (edición de prueba v1.2).", SMALL),
]

doc = RulesDoc(out, "Pests!", "Exterminadores rivales · 2–6 jugadores",
               shot("05_turno_exterminador"),
               ["Sella tu nido, elimina tus plagas y atrapa a tu reina.",
                "Solo cobra el primero que termine el trabajo."])
doc.build(story)
print("PDF:", out)
