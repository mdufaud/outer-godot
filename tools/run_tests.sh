#!/usr/bin/env bash
# Runs every headless suite: the per-planet invariant tests, the Cyclops geometry/storm/rock tests
# and the shared integration tests. Exits non-zero if any suite fails.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GODOT="${GODOT:-${HOME}/.local/bin/godot}"

[[ -x "$GODOT" ]] || { printf 'Error: godot not found at %s (set GODOT)\n' "$GODOT" >&2; exit 1; }

# Godot leaks a handful of RIDs and dummy resources on every headless exit; documented noise.
NOISE='RID allocations of type|resources still in use at exit|ObjectDB instances leaked|Pages in use exist at exit|Leaked instance dependency'

suites=()
while IFS= read -r -d '' suite; do
	suites+=("$suite")
done < <(find "${PROJECT_DIR}/tests/integration" "${PROJECT_DIR}/game/planets" -name '*_test.gd' -print0 | sort -z)

failed=()
for suite in "${suites[@]}"; do
	name="${suite#"${PROJECT_DIR}/"}"
	output="$("$GODOT" --headless --path "$PROJECT_DIR" -s "$name" 2>&1 | grep -Ev "$NOISE" || true)"
	if printf '%s' "$output" | grep -q 'passed$'; then
		printf 'PASS  %s\n' "$name"
	else
		printf 'FAIL  %s\n' "$name"
		printf '%s\n' "$output" | grep -E 'ERROR|SCRIPT ERROR|FAIL' | head -20
		failed+=("$name")
	fi
done

printf -- '---\n%d suites, %d failed\n' "${#suites[@]}" "${#failed[@]}"
[[ ${#failed[@]} -eq 0 ]] || exit 1
