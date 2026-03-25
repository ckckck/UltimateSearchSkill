#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"$'\n'"actual: $haystack"
}

output="$(env -i PATH="$PATH" "$ROOT_DIR/scripts/grok-search.sh" --help 2>&1)"

assert_contains "$output" 'OPENAI_COMPATIBLE_BASE_URL'
assert_contains "$output" 'OPENAI_COMPATIBLE_SEARCH_MODE'
assert_contains "$output" 'grok2api'
assert_contains "$output" 'legacy'

echo "PASS: grok search help output"
