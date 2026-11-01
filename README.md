# BGC: Board Game Collection

Colección de juegos de mesa hecha en **Godot 4.3+ (GDScript)**, con dos
modos multijugador:

- **En este equipo** (hot-seat): todos juegan en el mismo ordenador por
  turnos.
- **En red local**: cada jugador en su ordenador, conectados a la misma red
  (wifi o cable).

En los dos modos se pueden añadir jugadores controlados por la IA.

Juegos:

- **Archipiélago** (2–4): coloniza islas hexagonales, recoge recursos,
  comercia y construye.
- **La Conjura** (5–10): roles ocultos y deducción social. La Guardia Real
  contra la Hermandad de la Sombra y su Usurpador.

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
games/conjura/
  rules.txt              Reglas del juego
  logic/
    conjura_defs.gd      Roles, edictos, poderes, reparto y umbrales de victoria
    conjura_game.gd      La partida (GameBase): fases, votación, legislatura,
                         crisis, poderes y view_for(seat)
    conjura_deduction.gd Deducción: probabilidad de que cada uno sea traidor
    conjura_ai.gd        IA (solo usa view_for: no hace trampa); miente y deduce
  view/
    conjura_board.gd     Tablero público: pistas, descontento, crisis, mazo
    conjura_screen.gd    Pantalla: jugadores, registro, acciones y ventana
                         privada con cortina de «Pasa el dispositivo»
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
- Cada equipo solo muestra la mano de su jugador, pero tiene la partida
  completa en memoria: está pensado para jugar entre amigos, no para
  evitar trampas.
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
son IA), su rol se ve siempre en el panel derecho. La red local para este
juego llegará en la Fase 4 (por ahora el menú solo ofrece jugar en un equipo).

### Sonido

Los efectos se sintetizan al arrancar (`core/sfx.gd`), así que no hay
archivos de audio. Para sustituir uno por una grabación, pon un `.wav` u
`.ogg` con su nombre en `res://assets/sfx/` (por ejemplo `dice.wav`).
Nombres: `dice`, `build`, `resource`, `card`, `robber`, `turn`, `trade`,
`win`, `error`, `click`.

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
- [ ] **La Conjura, fase 4: red local.** Votos de varios asientos a la vez.
- [ ] **La Conjura, fase 5: pulido.** Arte, sonido e historial final.
