#!/usr/bin/env bash
# Runs a SceneTree probe on its own kwin --virtual compositor with hardware Vulkan,
# without touching the real display. Trimmed port of simple-forest's tools/probe_launch.sh.
#
# Usage: tools/probe_launch.sh perf_probe [-- probe args]
#   A bare name resolves to res://tools/<name>.gd.
#   GODOT (default godot-4.7), PROBE_SCREEN WxH (default 1920x1080),
#   PROBE_TIMEOUT seconds (default 900), PROBE_DONE marker line that ends the run early.
# Kill switch for anything a crashed run left behind:
#   systemctl --user stop 'outer-godot-probe-*.scope'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBE_SCRIPT="${1:-perf_probe}"
if [[ $# -gt 0 ]]; then
	shift
fi
if [[ "$PROBE_SCRIPT" != res://* ]]; then
	PROBE_SCRIPT="res://tools/${PROBE_SCRIPT%.gd}.gd"
fi
GODOT="${GODOT:-godot-4.7}"
PROBE_SCREEN="${PROBE_SCREEN:-1920x1080}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-900}"
PROBE_DONE="${PROBE_DONE:-[probe] done}"
RUN_ID="$(date -u +%Y%m%dT%H%M%S)-$$"
ROOT="$PROJECT/tmp/probe"
PROBE_LOG="$ROOT/$RUN_ID.log"
ENGINE_LOG="$ROOT/$RUN_ID.engine.log"
KWIN_LOG="$ROOT/$RUN_ID.kwin.log"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SOCKET="$RUNTIME_DIR/kwin-outer-probe-$RUN_ID"
SCOPE_UNIT="outer-godot-probe-$RUN_ID"

ENGINE_PID=""

teardown() {
	systemctl --user kill --signal=KILL --kill-who=all "$SCOPE_UNIT.scope" 2>/dev/null || true
	if [[ -n "$ENGINE_PID" ]]; then
		kill -KILL "$ENGINE_PID" 2>/dev/null || true
	fi
	# Anchored on this run's socket: never another project's compositor or the real session.
	pkill -KILL -f "^(/usr/bin/)?kwin_wayland --no-lockscreen --virtual --socket $SOCKET( |\$)" 2>/dev/null || true
	rm -f -- "$SOCKET" "$SOCKET.lock"
}
trap teardown EXIT
trap 'teardown; exit 130' INT
trap 'teardown; exit 143' TERM

mkdir -p "$ROOT"
exec 9>>"$ROOT/gpu.lock"
flock -w 1800 9 || { printf 'Error: GPU lane busy\n' >&2; exit 1; }

# --no-lockscreen before --virtual: other projects reap '^kwin_wayland --virtual' on cleanup.
env -u WAYLAND_DISPLAY -u DISPLAY -u XAUTHORITY -u XDG_SESSION_TYPE \
	XDG_CONFIG_HOME="$ROOT/kwin-config" \
	setsid kwin_wayland --no-lockscreen --virtual --socket "$SOCKET" \
	--width "${PROBE_SCREEN%x*}" --height "${PROBE_SCREEN#*x}" \
	>"$KWIN_LOG" 2>&1 </dev/null 9>&- &

waited=0
while [[ ! -S "$SOCKET" && $waited -lt 40 ]]; do
	sleep 1
	waited=$((waited + 1))
done
if [[ ! -S "$SOCKET" ]]; then
	printf 'Error: compositor did not start\n' >&2
	tail -20 "$KWIN_LOG" >&2
	exit 1
fi
export WAYLAND_DISPLAY="$SOCKET"

ENGINE_CMD=("$GODOT" --display-driver wayland --rendering-driver vulkan --audio-driver Dummy
	--disable-vsync --path "$PROJECT" --log-file "$ENGINE_LOG" -s "$PROBE_SCRIPT")
if [[ $# -gt 0 ]]; then
	ENGINE_CMD+=(-- "$@")
fi
systemd-run --user --scope -q --unit="$SCOPE_UNIT" -p CPUQuota=$(( $(nproc) * 80 ))% nice -n 10 \
	timeout --signal=TERM --kill-after=20 "${PROBE_TIMEOUT}s" \
	"${ENGINE_CMD[@]}" >"$PROBE_LOG" 2>&1 9>&- &
ENGINE_PID=$!

code=1
deadline=$(( $(date +%s) + PROBE_TIMEOUT + 30 ))
while kill -0 "$ENGINE_PID" 2>/dev/null; do
	if grep -qF -- "$PROBE_DONE" "$PROBE_LOG" 2>/dev/null; then
		code=0
		sleep 3
		break
	fi
	if [[ $(date +%s) -ge $deadline ]]; then
		printf 'Error: probe timeout after %ss\n' "$PROBE_TIMEOUT" >&2
		break
	fi
	sleep 1
done
if [[ $code -ne 0 ]] && grep -qF -- "$PROBE_DONE" "$PROBE_LOG" 2>/dev/null; then
	code=0
fi
teardown
printf 'log: %s\n' "$PROBE_LOG"
if grep -qE 'SCRIPT ERROR|Parse Error' "$PROBE_LOG"; then
	grep -nE 'SCRIPT ERROR|Parse Error' "$PROBE_LOG" | head -20
	code=1
fi
exit "$code"
