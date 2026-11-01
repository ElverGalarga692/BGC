# BGC: Board Game Collection

Colección de juegos de mesa hecha en **Godot 4.3+ (GDScript)**, con
**multijugador local** (hot-seat: varios jugadores en el mismo equipo).

El primer juego es **Archipiélago**: coloniza islas hexagonales, recoge
recursos, comercia y construye.

## Cómo ejecutarlo

1. Abre la carpeta del proyecto con Godot 4.3 o superior.
2. Pulsa F5. Para abrir directamente el tablero, abre
   `games/archipelago/archipelago.tscn` y pulsa F6.

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
  view/                  Escenas y dibujo
    board_view.gd        Vista 2D: tablero, piezas, objetivos y detección
    archipelago_screen.gd  Pantalla de juego: HUD, registro, acciones
tests/                   Tests sin dependencias externas (test_*.gd)
```

### Vistas intercambiables (2D hoy, 3D en el futuro)

La pantalla solo habla con la vista del tablero a través de un contrato
pequeño, documentado en `board_view.gd`: la propiedad `game`,
`set_targets()`, `refresh()`, `fit()` y las señales `hovered` y `clicked`.
La detección trabaja en "unidades de hexágono" con `HexGrid`, así que una
vista 3D solo tiene que proyectar el rayo del ratón sobre el plano del
tablero y reutilizar esa misma detección.

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
- [ ] **Fase 4: IA.** Jugador aleatorio y luego por heurísticas.
- [ ] **Fase 5: pulido.** Animaciones, sonido, guardar y cargar, tutorial.
- [ ] **Siguiente juego** de la colección.
