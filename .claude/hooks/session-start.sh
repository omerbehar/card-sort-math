#!/bin/bash
# SessionStart hook: ensure Godot 4.6 is available so the gdUnit4 test suite can
# run in Claude Code on the web sessions. Idempotent and non-interactive.
set -euo pipefail

# Only run in remote (Claude Code on the web) environments.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.6-stable"
GODOT_BIN="/usr/local/bin/godot"
ASSET="Godot_v${GODOT_VERSION}_linux.x86_64"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ASSET}.zip"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

install_godot() {
  local tmp
  tmp="$(mktemp -d)"
  echo "Downloading Godot ${GODOT_VERSION}..."
  curl -fsSL -m 180 -o "${tmp}/godot.zip" "${URL}"
  unzip -oq "${tmp}/godot.zip" -d "${tmp}"
  mkdir -p "$(dirname "${GODOT_BIN}")"
  mv "${tmp}/${ASSET}" "${GODOT_BIN}"
  chmod +x "${GODOT_BIN}"
  rm -rf "${tmp}"
}

# (Re)install only if missing or not the expected major.minor version.
if ! "${GODOT_BIN}" --headless --version 2>/dev/null | grep -q "^4\.6\."; then
  install_godot
fi
echo "Godot: $("${GODOT_BIN}" --headless --version 2>/dev/null | tail -1)"

# Expose the binary to gdUnit4's runtest.sh / CI conventions.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export GODOT_BIN=\"${GODOT_BIN}\"" >> "${CLAUDE_ENV_FILE}"
fi

# Import resources so class_name registration + .uid generation are ready for tests.
echo "Importing project..."
"${GODOT_BIN}" --headless --path "${PROJECT_DIR}" --import >/dev/null 2>&1 || true

echo "Godot environment ready. Run tests with:"
echo "  godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests"
