#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

mkdir -p "${PROJECT_DIR}/build/web"
echo "Exporting Godot Web release to build/web/index.html..."
godot --headless --path "${PROJECT_DIR}" --export-release "Web" "${PROJECT_DIR}/build/web/index.html"
echo "Web build completed successfully at $(date)."
