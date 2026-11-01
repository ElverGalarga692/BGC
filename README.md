# BGC: Board Game Collection

Colección de juegos de mesa hecha en **Godot 4.3+ (GDScript)**, con dos
modos multijugador:

- **En este equipo** (hot-seat): todos juegan en el mismo ordenador por
  turnos.
- **En red local**: cada jugador en su ordenador, conectados a la misma red
  (wifi o cable).

En los dos modos se pueden añadir jugadores controlados por la IA.

Juegos:

- **Archipiélago**: coloniza islas hexagonales, recoge recursos, comercia y
  construye (2–4 jugadores).
- **Pests!**: exterminadores rivales en una casa infestada; sella tu nido,
  elimina tus plagas y atrapa a tu reina antes que nadie (2–6 jugadores).
  Opciones en el menú: reglas rápidas (exterminadores y cartas al azar),
  casa construida al azar y partida por equipos (4 o 6 jugadores).
- **La Conjura**: roles ocultos y deducción social; la Guardia Real
  contra la Hermandad de la Sombra y su Usurpador (5–10 jugadores).

## Cómo ejecutarlo

1. Abre la carpeta del proyecto con Godot 4.3 o superior.
2. Pulsa F5. Para abrir directamente el tablero, abre
   `games/archipelago/archipelago.tscn` y pulsa F6.

### Controles del tablero 3D

- Clic izquierdo: elegir casilla, esquina o lado.
- Clic derecho o Esc: cancelar la construcción en curso.
- Rueda del ratón: zoom.
- Botón central (arrastrar) o teclas Q / E: girar la cámara.
- "Cambiar a vista 2D/3D" en el panel izquierdo (se recuerda la elección).

### Tests

```bash
./run_tests.sh
```

Si `godot` no está en el `PATH`, indica dónde está con
`GODOT=/ruta/a/godot ./run_tests.sh`.

## Arquitectura

La **lógica** de cada juego está separada de su **presentación**. La lógica
es GDScript puro, sin nodos: guarda el estado y valida y aplica jugadas
(`GameAction`). La vista solo dibuja el estado y envía acciones. Así la IA,
los tests y el guardado de partidas reutilizan la misma lógica.

```
core/                    Compartido por todos los juegos
  app.gd                 Autoload "App": navegación, sesión, ajustes y partidas guardadas
  sfx.gd                 Autoload "Sfx": efectos de sonido sintetizados
  net.gd                 Autoload "Net": multijugador en red local
  game_base.gd           Clase base de la lógica de un juego
  game_registry.gd       Lista de juegos de la colección
  action.gd              GameAction: una jugada serializable
  player.gd              PlayerInfo: nombre, color, IA o humano
  turn_manager.gd        Turnos normales y secuencias (orden serpiente)
  rng.gd                 Azar con semilla (partidas reproducibles)
  hex_coords.gd          Matemática de hexágonos (coordenadas axiales)
  hex_grid.gd            Topología: casillas, vértices, aristas
ui_common/
  main_menu.gd           Selector de juego, jugadores, ajustes y "Continuar"
  bgc_theme.gd           Tema visual de los menús (botones, paneles, campos)
  menu_background.gd     Fondo animado del menú (hexágonos flotantes)
  hex_emblem.gd          Emblema de hexágonos (título y tarjetas de juego)
  dice_view.gd           Dados con animación de tirada
  rules_panel.gd         Ventana de reglas (texto BBCode de cada juego)
games/archipelago/
  rules.txt              Reglas del juego (se muestran en el juego)
  logic/                 Reglas y estado (sin nodos)
    arch_defs.gd         Terrenos, recursos, fichas, puertos
    arch_board.gd        Tablero: terrenos, números, puertos, bandido
    board_generator.gd   Generación aleatoria equilibrada
    archipelago_game.gd  La partida (GameBase): fases, reglas y acciones
    arch_ai.gd           IA (fácil, normal, difícil)
    arch_card_tracker.gd Contador de cartas de la IA difícil
  view/                  Escenas y dibujo
    board_view.gd        Vista 2D: tablero, piezas, objetivos y detección
    board_view_3d.gd     Vista 3D (mismo contrato), con los modelos de Blender
  assets/models/         Modelos 3D (.glb) exportados desde Blender
    archipelago_screen.gd  Pantalla de juego: HUD, registro, acciones
games/pests/             Pests!
  rules.txt              Reglas y aclaraciones de la edición de prueba v1.2
  pests.tscn             Escena del juego
  logic/
    pests_defs.gd        Especies, habilidades, dado de la reina, costes,
                         losetas (puertas) y cartas de herramientas
    pests_house.gd       La casa: colocación de losetas, vecinos, distancias,
                         invocación, reparto DLUR y salida/reentrada de la reina
    pests_house_generator.gd  Casas aleatorias (partida rápida, IA, tests)
    pests_game.gd        La partida (GameBase): elección de exterminador,
                         cartas, construcción de la casa, reina, acciones,
                         trampas, victoria y eliminación
    pests_ai.gd          IA: fácil (reglas con errores), normal (reglas con
                         prioridades) y difícil (planifica el turno en copias
                         de la partida y evalúa el resultado)
  view/
    pests_board_view.gd  Vista 2D de la casa, dibujada por código (suelos,
                         muebles, nidos, bichos, trampas) y animaciones
    queen_die_view.gd    Dado de la reina con animación de tirada
    pests_screen.gd      Pantalla de juego: jugadores, registro, acciones, cartas
games/conjura/
  rules.txt              Reglas del juego
  logic/
    conjura_defs.gd      Roles, edictos, poderes, reparto y umbrales de victoria
    conjura_game.gd      La partida (GameBase): fases, votación, legislatura,
                         crisis, poderes y view_for(seat)
    conjura_deduction.gd Deducción: probabilidad de que cada uno sea traidor
    conjura_ai.gd        IA (solo usa view_for: no hace trampa); miente y deduce
  view/
    conjura_art.gd       Ilustraciones por código: cartas de edicto y de rol
    conjura_board.gd     Tablero público: pistas, descontento, crisis, mazo
    vote_reveal.gd       Revelación animada de cada votación
    conjura_screen.gd    Pantalla: jugadores, registro, acciones y ventana
                         privada con cortina de «Pasa el dispositivo»
games/bajamar/           Bajamar
  rules.txt              Reglas del juego
  logic/
    bajamar_defs.gd      Cartas (enteros), mazo y puntuación de una red
    bajamar_game.gd      La partida (GameBase): rondas, mercado, tormentas,
                         especiales, volver a puerto, puntos y fin de partida
    bajamar_ai.gd        IA (fácil, normal y difícil); cuenta cartas solo con
                         lo que está a la vista
  view/
    bajamar_art.gd       Cartas dibujadas por código (peces, tormenta,
                         especiales, reverso) y BajamarCard con volteo
    bajamar_screen.gd    Pantalla: marcador, mesa (mazo, mercado, descartes),
                         barcas con sus redes, acciones con los puntos de
                         cada opción, resumen de ronda y pantalla final
games/puerto_franco/     Puerto Franco (en desarrollo, aún no está en el menú)
  rules.txt              Reglas del juego
  logic/
    puerto_defs.gd       Gremios, edificios y maravillas (cartas = enteros),
                         cargos, objetivos, barrio hexagonal y puntuación
    puerto_game.gd       La partida (GameBase): elección secreta de cargos con
                         puja, vacantes, turnos, habilidades, construir y final
tests/                   Tests sin dependencias externas (test_*.gd)
```

### Vistas intercambiables (2D y 3D)

La pantalla solo habla con la vista del tablero a través de un contrato
pequeño, documentado en `board_view.gd`: la propiedad `game`,
`set_targets()`, `refresh()`, `fit()` y las señales `hovered` y `clicked`.
La detección trabaja en "unidades de hexágono" (`ArchBoardView.pick_unit`):
la vista 3D proyecta el rayo del ratón sobre el plano del tablero y reutiliza
esa misma función. Si falta algún modelo `.glb`, la vista 3D usa una forma
sencilla generada por código.

### Modelos 3D (Blender)

Los modelos de Archipiélago se crean con un script de Blender, así que se
pueden regenerar y modificar:

- `art/blender/build_models.py`: construye los modelos y los exporta.
- `art/blender/archipelago_models.blend`: el resultado, para retocarlo a mano.
- `games/archipelago/assets/models/*.glb`: lo que carga Godot.

Para regenerarlos, abre el script en la pestaña *Scripting* de Blender y
pulsa *Run Script*, o desde la terminal:

```bash
pip install bpy
python art/blender/build_models.py
```

Si retocas el `.blend` a mano, exporta cada objeto como `.glb` con el mismo
nombre. Convenciones que usa la vista 3D:
- Unidades de hexágono: radio de ficha 0,965 y altura 0,22, con el origen en
  el centro de la base. El círculo central queda libre para la ficha numérica.
- Los materiales `player`, `player_dark` y `port_flag` se recolorean en el
  juego (color del jugador y color del recurso del puerto).
- La carpeta `art/` lleva un `.gdignore` para que Godot no intente importar
  el `.blend`.

### Multijugador en red local

1. Un jugador elige el juego, pulsa **En red local → Crear partida** y queda
   en la sala de espera (ahí ve su IP).
2. Los demás, en **En red local**, ven la partida en la lista y pulsan
   **Unirse** (o escriben la IP del anfitrión).
3. El anfitrión puede añadir IAs y pulsa **Empezar partida**.

Funcionamiento (`core/net.gd`, autoload `Net`, con ENet de Godot):
- El **anfitrión tiene la autoridad**: los clientes le envían sus acciones,
  él las valida con las reglas y las reenvía a todos, que las aplican en su
  copia. Como las partidas son deterministas, todos los equipos calculan los
  mismos dados y robos.
- Las IAs funcionan en el equipo del anfitrión.
- Si un jugador se desconecta, una IA ocupa su plaza; si se desconecta el
  anfitrión, los demás vuelven al menú.
- El anfitrión se anuncia por difusión UDP (puerto 47811) y la partida usa
  el puerto 47810. Si un cortafuegos los bloquea, hay que permitirlos.
- Cada juego fija su número de jugadores (Archipiélago 2–4, Pests! 2–6, La Conjura
  5–10); si faltan personas, el anfitrión completa la mesa con IAs.
- Varios jugadores pueden actuar a la vez (las votaciones de La Conjura):
  el anfitrión acepta la jugada de cualquier asiento al que le toque.
- Cada equipo solo muestra la información de su jugador (la mano, o el rol
  y los secretos en La Conjura), pero tiene la partida completa en memoria:
  está pensado para jugar entre amigos, no para evitar trampas.
- Para probar en un solo ordenador: abre dos ventanas del juego, crea la
  partida en una y únete desde la otra con la IP `127.0.0.1`. Con la
  variable de entorno `BGC_AUTOPLAY=1`, los jugadores humanos de esa
  ventana juegan solos (útil para pruebas automáticas).

### Información oculta (La Conjura)

La partida guarda el estado completo, pero la interfaz y la IA solo leen
`ConjuraGame.view_for(seat)`: la proyección de lo que ese asiento puede saber
(su rol, sus aliados, sus edictos en mano, lo que ha descubierto con poderes;
los votos ajenos solo cuando se resuelve la votación). `view_for(-1)` es la
vista pública. Los tests comprueban que no se filtra nada.

En un solo equipo con varias personas, todo lo secreto aparece tras una
cortina de «Pasa el dispositivo a X». Si solo hay una persona (y el resto
son IA), su rol se ve siempre en el panel derecho. En red, cada equipo
enseña solo lo de su asiento y no hace falta cortina.

### Sonido

Los efectos se sintetizan al arrancar (`core/sfx.gd`), así que no hay
archivos de audio. Para sustituir uno por una grabación, pon un `.wav` u
`.ogg` con su nombre en `res://assets/sfx/` (por ejemplo `dice.wav`).
Nombres: `dice`, `build`, `resource`, `card`, `robber`, `turn`, `trade`,
`win`, `error`, `click`, y los de La Conjura: `approve`, `reject`, `seal`,
`gong`, `whisper`, `crisis`, `win_sombra`, y los de Bajamar: `thunder`,
`gull` y `wave`.

### Partidas guardadas

Como las partidas son deterministas, guardar es solo guardar la semilla, los
jugadores y la lista de acciones (`GameBase.save_data()`); al cargar se
repiten (`GameBase.replay()`). Se guarda automáticamente tras cada jugada en
`user://saves/<juego>.save` y se borra al terminar la partida.

### Añadir un juego nuevo

1. Crea `games/<id>/` con `logic/` (una clase que herede de `GameBase`) y
   `view/` (la escena).
2. Registra el juego en `core/game_registry.gd` (con su archivo de reglas).
3. Añade tests en `tests/test_<id>_*.gd`.

## Hoja de ruta

- [x] **Fase 0: base.** Estructura del proyecto, núcleo genérico, menú,
      jugadores locales y tests.
- [x] **Fase 1: tablero.** Grafo de hexágonos, vértices y aristas;
      generación equilibrada (6 y 8 nunca vecinos, puertos repartidos);
      dibujo; detección de casilla, vértice y arista.
- [x] **Fase 2: reglas básicas.** Colocación inicial en serpiente, dados y
      producción, construir caminos, poblados y ciudades, comercio con la
      banca y los puertos, puntos de victoria (10). Interfaz para jugar en
      local por turnos.
- [x] **Fase 3: reglas completas.** El 7 (descartes y bandido), cartas de
      desarrollo (Miliciano, Monumento, Ingenieros, Cosecha abundante,
      Monopolio), Mayor milicia, Camino más largo y comercio entre jugadores.
- [x] **Fase 4: IA.** Tres niveles por jugador (fácil, normal y difícil). La
      difícil cuenta cartas con información pública y está ajustada con
      torneos: gana ~43 % de las partidas contra tres IAs normales.
- [x] **Vista 3D.** Tablero en 3D con decoración por terreno, piezas que
      caen al colocarse, bandido animado y cámara orbital; se puede volver
      a la vista 2D en cualquier momento.
- [x] **Modelos de Blender.** Fichas de terreno, piezas, bandido, fichas
      numéricas y muelles, generados con un script de Blender reproducible.
- [x] **Fase 5: pulido.** Dados animados, casillas que se iluminan al
      producir, recursos que vuelan a la mano, efectos de sonido
      sintetizados, guardado automático con "Continuar partida", pantalla
      de reglas y menú de ajustes (volumen, pantalla completa, 2D/3D,
      velocidad de la IA).
- [x] **La Conjura, fases 1 y 2.** Lógica con información oculta por
      asiento (`view_for`), votación simultánea, crisis, poderes elegibles,
      descontento y cuatro formas de ganar; tests de reglas y de filtrado;
      pantalla jugable en un equipo con cortina para lo secreto e IA básica.
- [x] **La Conjura, fase 3: IA.** Fase de declaraciones (verdad o
      mentira), deducción exacta por enumeración de repartos y IA por rol
      (la Sombra miente coordinada y mide cuánto sospechan de ella).
      Equilibrado con simulaciones: entre IAs normales la Guardia gana
      ~55 % (cada número de jugadores entre 45 y 64 %); la IA difícil gana
      ~5 puntos más que la normal.
- [x] **La Conjura, fase 4: red local.** Hasta 10 jugadores por red (el
      límite lo pone cada juego), votos simultáneos, ventana privada por
      asiento y una IA ocupa el sitio de quien se desconecta. Probado con un
      anfitrión y dos clientes: todos terminan con el mismo historial.
- [x] **La Conjura, fase 5: pulido.** Cartas de edicto y de rol dibujadas
      por código, votos que se revelan carta a carta, rótulos al promulgar,
      sonidos propios (sello, gong, redoble, susurro, victorias) y pantalla
      final con las cartas de rol y el historial de gobiernos, que compara
      lo que dijo cada uno con lo que pasó de verdad y marca las mentiras.
- [x] **Bajamar, fases 0 y 1.** Juego original de cartas de arriesgar o
      plantarse (2 a 6 jugadores): robar a ciegas o del mercado, volver a
      puerto, tormentas (la primera avisa, la segunda rompe la red),
      puntuación con especie doble y escaleras, rondas hasta 150 puntos;
      mazo que se rebaraja y riesgo calculable con información pública
      (`storm_chance()`). Tests de reglas, determinismo y guardado.
- [x] **Bajamar, fase 2: especiales.** Gaviota (quita el último pez a otro
      jugador, también en puerto; se elige víctima con `choose_target` y el
      turno espera), Red reforzada (salva de la tormenta que rompería la red)
      y Marea alta (todos los que siguen en el mar roban; sin cadenas). Mazo
      de 76 cartas.
- [x] **Bajamar, fase 3: IA y equilibrio.** Fácil (pesca hasta un umbral),
      normal (cuenta cartas y compara plantarse con el valor esperado de
      robar) y difícil (mira dos robos por delante, valora el daño de la
      Gaviota y juega para ganar en la última ronda). Las simulaciones
      cambiaron las reglas: una tormenta ya rompe la red (con aviso previo
      se pescaba sin riesgo y salían rondas de 200 puntos), coger del
      mercado lleva a puerto (si no, era una fuente de peces sin riesgo), la
      Red reforzada salva la mitad de los puntos en vez de una tormenta, la
      especie mayoritaria da +2 por carta en vez de valer doble, 10
      tormentas y los descartes se barajan al empezar cada ronda. Con IAs
      normales una partida a 4 dura ~7 rondas (~16 puntos por ronda, máximo
      ~80); la normal gana ~57 % contra tres fáciles. Pendiente: la difícil
      todavía empata con la normal (49 % en 500 duelos), porque maximizar
      los puntos esperados de cada ronda ya es casi lo mejor que se puede
      hacer; solo gana algo en la última ronda.
- [x] **Bajamar, fase 4: pantalla.** Mesa 2D con el mazo (y el riesgo de
      tormenta), el mercado (se puede pulsar una carta para cogerla) y los
      descartes; una barca por jugador con su red; botones con los puntos que
      daría cada opción y desglose de la red; elección de víctima de la
      Gaviota; cartas que se voltean al aparecer, barcas que se tiñen de rojo
      al romperse la red, rótulos y sonidos; resumen al final de cada ronda
      (se cierra solo si solo juegan IAs) y pantalla final. Atajos: R, P y
      1-3. El juego ya aparece en el menú, con guardado automático.
- [x] **Bajamar, fase 5: red local y pulido.** Probado en red con un
      anfitrión y dos clientes (hasta 5 plazas con IAs): todos terminan con
      el mismo historial, y si un cliente se desconecta una IA ocupa su plaza
      y la partida sigue. En red, el resumen de ronda se cierra solo para que
      nadie bloquee. El resumen y la pantalla final enseñan las cartas de
      cada red (las rotas, oscurecidas), el riesgo de tormenta cambia de
      color y hay sonidos propios (trueno, gaviota y ola).
- [x] **Puerto Franco, fases 0 y 1.** Juego original de cargos secretos y
      barrios hexagonales (2 a 6 jugadores). Cada ronda todos eligen a la vez
      un cargo y una puja; la puja más alta se lo queda, los empates van por
      la vara y quien pierde elige entre los vacantes, que acumulan monedas.
      Turnos en orden de cargo: cobrar (monedas, muelle o a ciegas), usar el
      cargo (Capitana de puerto, Contrabandista, Recaudadora, Urbanista,
      Maestra de obras, Mecenas y Alcaldesa) y construir en el barrio,
      vecino de lo que ya hay. Puntos por coste, grupos de vecinos del mismo
      gremio, 9 maravillas, 2 objetivos públicos y terminar primero.
      Información oculta con `view_for`. Tests de reglas, determinismo y
      guardado. Primera simulación con una estrategia sencilla: ~9–10
      rondas por partida; con 6 jugadores puntúan menos (faltan cartas), a
      revisar al equilibrar con la IA.
- [ ] **Puerto Franco, fase 2:** IA (fácil, normal y difícil) y equilibrio
      con simulaciones (pujas, cargos, número de cartas por jugadores).
- [ ] **Puerto Franco, fase 3:** pantalla 2D (mesa de cargos, mano, barrio
      y barrios rivales), cortina de «Pasa el dispositivo» para la elección
      secreta y entrada en el menú.
- [ ] **Puerto Franco, fase 4:** red local (elección simultánea sin revelar).
- [ ] **Puerto Franco, fase 5:** pulido (cartas y edificios dibujados por
      código, animaciones y sonidos).

### Opciones de cada juego

Un juego puede declarar opciones en `GameRegistry` (`"options": [{"key",
"label", "default"}]`). El menú las muestra como casillas y las recuerda
(`App.game_options()`); la partida las recibe en `App.session["options"]`, se
guardan con la partida y, en red, se usan las del anfitrión. Cada juego
declara también cuántas plazas admite en red (`max_players`).
