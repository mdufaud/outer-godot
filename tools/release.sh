#!/usr/bin/env bash
# Builds the release native libraries, exports the four presets into OUT_DIR (default bin/)
# and verifies the APK signature and its native library.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GODOT="${GODOT:-${HOME}/.local/bin/godot-4.7}"
OUT_DIR="${OUT_DIR:-${PROJECT_DIR}/bin}"
NDK_VERSION="${NDK_VERSION:-28.0.13004108}"
APK="${OUT_DIR}/OuterGodot.apk"
APK_LIBRARY="lib/arm64-v8a/libouter_native.android.template_release.arm64.so"

[[ -x "$GODOT" ]] || { printf 'Error: godot not found at %s (set GODOT)\n' "$GODOT" >&2; exit 1; }
command -v apksigner >/dev/null || { printf 'Error: apksigner not found\n' >&2; exit 1; }

build() {
	scons -C "${PROJECT_DIR}/native" -Q -j"$(nproc)" target=template_release optimize=speed "$@" \
		|| { printf 'Error: native build failed (%s)\n' "$*" >&2; exit 1; }
}

export_preset() {
	local preset="$1"
	local file="${OUT_DIR}/$2"
	"$GODOT" --headless --path "$PROJECT_DIR" --export-release "$preset" "$file" \
		|| { printf 'Error: export failed for preset %s\n' "$preset" >&2; exit 1; }
	[[ -f "$file" ]] || { printf 'Error: preset %s produced no %s\n' "$preset" "$file" >&2; exit 1; }
}

build platform=linux arch=x86_64
build platform=windows arch=x86_64
build platform=android arch=arm64 ndk_version="$NDK_VERSION"

"$GODOT" --headless --path "$PROJECT_DIR" --import
mkdir -p "$OUT_DIR"
export_preset "Linux" "OuterGodot.x86_64"
export_preset "Windows Desktop" "OuterGodot.exe"
export_preset "Steam Deck" "OuterGodot_SteamDeck.x86_64"
export_preset "Android" "OuterGodot.apk"

apksigner verify --verbose "$APK" || { printf 'Error: APK signature invalid\n' >&2; exit 1; }
zipinfo -1 "$APK" "$APK_LIBRARY" >/dev/null 2>&1 \
	|| { printf 'Error: %s missing from APK\n' "$APK_LIBRARY" >&2; exit 1; }
certificates="$(apksigner verify --print-certs "$APK" 2>/dev/null)"
if [[ "$certificates" == *"CN=Android Debug"* ]]; then
	printf 'Warning: APK signed with the Android debug keystore\n' >&2
fi
printf 'Release exported to %s\n' "$OUT_DIR"
