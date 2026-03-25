#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP_DIR="$(mktemp -d)"
FAKE_BIN="$TMP_DIR/bin"
ATTEMPT_LOG="$TMP_DIR/attempts.log"
mkdir -p "$FAKE_BIN"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s
' "$*" >> "$ATTEMPT_LOG"

if [[ "$*" == *"https://api.x.ai/v1/responses"* ]]; then
  cat <<'JSON'
{"error":{"message":"provider responses failed","type":"server_error","code":"provider_error"}}
502
JSON
  exit 0
fi

if [[ "$*" == *"https://api.x.ai/v1/chat/completions"* ]]; then
  cat <<'JSON'
{"choices":[{"message":{"content":"fallback-chat-ok"}}],"model":"fallback-model","usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
200
JSON
  exit 0
fi

cat <<'JSON'
{"error":"unexpected endpoint"}
500
JSON
SH
chmod +x "$FAKE_BIN/curl"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"$'\n'"actual: $haystack"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output to not contain: $needle"$'\n'"actual: $haystack"
}

run_script() {
  env -i \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    ATTEMPT_LOG="$ATTEMPT_LOG" \
    OPENAI_COMPATIBLE_BASE_URL="https://api.x.ai/v1" \
    OPENAI_COMPATIBLE_API_KEY="compat-key" \
    OPENAI_COMPATIBLE_MODEL="compat-model" \
    OPENAI_COMPATIBLE_SEARCH_MODE="${OPENAI_COMPATIBLE_SEARCH_MODE:-}" \
    "$ROOT_DIR/scripts/grok-search.sh" --query "hello" 2>&1
}

rm -f "$ATTEMPT_LOG"
if ! auto_output="$(run_script)"; then
  fail "automatic known-url mode should downgrade to chat mode when responses endpoint fails"$'\n'"output: $auto_output"
fi
assert_contains "$auto_output" '"content": "fallback-chat-ok"'
assert_contains "$auto_output" '"mode": "openai_compatible_chat"'
assert_contains "$auto_output" '"degraded_from": "xai_web_search"'
assert_contains "$auto_output" '"realtime_warning": "provider native web search unavailable; downgraded to plain compatible chat"'
assert_contains "$(cat "$ATTEMPT_LOG")" 'https://api.x.ai/v1/responses'
assert_contains "$(cat "$ATTEMPT_LOG")" 'https://api.x.ai/v1/chat/completions'

rm -f "$ATTEMPT_LOG"
if manual_output="$(OPENAI_COMPATIBLE_SEARCH_MODE="xai_web_search" run_script)"; then
  fail "manual xai_web_search mode should not silently downgrade"
fi
assert_contains "$manual_output" 'provider responses failed'
assert_not_contains "$manual_output" 'fallback-chat-ok'
assert_contains "$(cat "$ATTEMPT_LOG")" 'https://api.x.ai/v1/responses'

echo "PASS: grok search fallback policy"
