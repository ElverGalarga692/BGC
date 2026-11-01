# BGC: Board Game Collection

Colección de juegos de mesa hecha en **Godot 4.3+ (GDScript)**, con
**multijugador local** (hot-seat: varios jugadores en el mismo equipo).

El primer juego es **Archipiélago**: coloniza islas hexagonales, recoge
recursos, comercia y construye.

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
  app.gd                 Autoload "App": navegación y datos de la sesión
  game_base.gd           Clase base de la lógica de un juego
  game_registry.gd       Lista de juegos de la colección
  action.gd              GameAction: una jugada serializable
  player.gd              PlayerInfo: nombre, color, IA o humano
  turn_manager.gd        Turnos normales y secuencias (orden serpiente)
  rng.gd                 Azar con semilla (partidas reproducibles)
  hex_coords.gd          Matemática de hexágonos (coordenadas axiales)
  hex_grid.gd            Topología: casillas, vértices, aristas
ui_common/
  main_menu.gd           Selector de juego y configuración de jugadores
games/archipelago/
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

### Añadir un juego nuevo

1. Crea `games/<id>/` con `logic/` (una clase que herede de `GameBase`) y
   `view/` (la escena).
2. Registra el juego en `core/game_registry.gd`.
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
- [ ] **Fase 5: pulido.** Más animaciones (dados, recursos), sonido, guardar
      y cargar, tutorial, ajustes.
- [ ] **Siguiente juego** de la colección.
