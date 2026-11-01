#!/usr/bin/env bash
# Ejecuta los tests en modo headless.
# Uso: ./run_tests.sh   (o GODOT=/ruta/a/godot ./run_tests.sh)
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
# Importa el proyecto (genera la caché de class_name) y lanza los tests.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd
