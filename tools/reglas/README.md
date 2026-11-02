# Reglamentos en PDF

Los PDF están en `docs/reglas/`. Cada uno se genera en dos pasos:

1. **Capturas**: una escena de Godot juega una partida entre IAs y fotografía
   la pantalla real del juego en distintos momentos. Necesita pantalla; en un
   servidor sin ella, usa Xvfb:

   ```bash
   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 res://tools/reglas/capture_archipelago.tscn -- /tmp/capturas
   ```

   Hay una escena por juego (`capture_<juego>.tscn`); todas heredan de
   `rules_capture.gd`, que juega la partida y abre la pantalla en cada
   momento que se quiere fotografiar.

2. **PDF**: un script de Python (ReportLab y Pillow, fuente DejaVu Sans)
   maqueta el texto y las capturas:

   ```bash
   python3 tools/reglas/build_archipelago.py /tmp/capturas docs/reglas/archipielago.pdf
   ```

   Para Pests!: `capture_pests.tscn` y `build_pests.py` (salida
   `docs/reglas/pests.pdf`). Para La Conjura: `capture_conjura.tscn` y
   `build_conjura.py` (salida `docs/reglas/conjura.pdf`).

`pdf_common.py` tiene los estilos y piezas que comparten todos los
reglamentos (portada, figuras, tablas, recuadros).
