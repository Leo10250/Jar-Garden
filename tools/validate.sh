#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_MANIFEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_suites.txt"
TEST_SUITES=()

resolve_godot() {
  if [[ -n "${GODOT_BIN:-}" ]]; then
    if [[ -x "$GODOT_BIN" ]]; then
      printf '%s\n' "$GODOT_BIN"
      return 0
    fi
    if command -v "$GODOT_BIN" >/dev/null 2>&1; then
      command -v "$GODOT_BIN"
      return 0
    fi
    echo "FAIL: GODOT_BIN is set but cannot be resolved: $GODOT_BIN" >&2
    return 1
  fi

  local candidate
  for candidate in godot godot4; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done

  echo "FAIL: Godot was not found. Add Godot to PATH or set GODOT_BIN to the Godot executable." >&2
  return 1
}

load_test_suites() {
  if [[ ! -f "$TEST_MANIFEST" ]]; then
    echo "FAIL: Test manifest is missing: $TEST_MANIFEST" >&2
    return 1
  fi

  local suite
  while IFS= read -r suite || [[ -n "$suite" ]]; do
    suite="${suite%$'\r'}"
    [[ -z "$suite" || "$suite" == \#* ]] && continue
    TEST_SUITES+=("$suite")
  done < "$TEST_MANIFEST"

  if [[ ${#TEST_SUITES[@]} -eq 0 ]]; then
    echo "FAIL: Test manifest contains no test entrypoints: $TEST_MANIFEST" >&2
    return 1
  fi
}

run_step() {
  local label="$1"
  shift
  echo "==> $label"
  if "$GODOT" "$@"; then
    echo "PASS: $label"
  else
    local status=$?
    echo "FAIL: $label (exit $status)" >&2
    exit "$status"
  fi
}

GODOT="$(resolve_godot)"
load_test_suites

echo "Jar Garden validation"
echo "Godot: $GODOT"
echo "Repo:  $REPO_ROOT"
echo "Tests: ${#TEST_SUITES[@]}"

cd "$REPO_ROOT"

run_step "project import / parse" \
  --headless \
  --path "$REPO_ROOT" \
  --import

for suite in "${TEST_SUITES[@]}"; do
  run_step "test ${suite##*/}" \
    --headless \
    --path "$REPO_ROOT" \
    --script "$suite"
done

run_step "main scene smoke" \
  --headless \
  --path "$REPO_ROOT" \
  --quit-after 2

echo "PASS: Jar Garden validation completed successfully."
