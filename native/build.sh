#!/usr/bin/env bash
# Builds the Linux debug library when its sources changed and registers the extension.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GODOT="${GODOT:-${HOME}/.local/bin/godot-4.7}"
TARGET="${TARGET:-template_debug}"
LIBRARY="${PROJECT_DIR}/game/native/bin/libouter_native.linux.${TARGET}.x86_64.so"

if [[ ! -f "${LIBRARY}" ]] || [[ -n "$(find "${SCRIPT_DIR}/src" "${SCRIPT_DIR}/SConstruct" \
		"${SCRIPT_DIR}/godot-cpp" -newer "${LIBRARY}" -type f -print -quit)" ]]; then
	scons -C "${SCRIPT_DIR}" -Q -j"$(nproc)" target="${TARGET}" optimize=speed
	touch "${LIBRARY}"
fi
if ! grep -qxF -- "res://game/native/outer_native.gdextension" "${PROJECT_DIR}/.godot/extension_list.cfg" 2>/dev/null; then
	"${GODOT}" --headless --path "${PROJECT_DIR}" --import
fi
