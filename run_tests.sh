#!/usr/bin/env bash
# Ejecuta los tests en modo headless.
# Uso: ./run_tests.sh   (o GODOT=/ruta/a/godot ./run_tests.sh)
set -uo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
# Importa el proyecto (genera la caché de class_name) y lanza los tests.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
# Sin GPU, el renderizador vacío de Godot avisa en cada malla generada por
# código de la vista 3D ("Parameter m is null"): es inofensivo y se filtra.
"$GODOT" --headless --path . -s res://tests/run_tests.gd 2>&1 \
	| grep -v -e 'Parameter "m" is null' -e 'mesh_storage.h:'
exit "${PIPESTATUS[0]}"
