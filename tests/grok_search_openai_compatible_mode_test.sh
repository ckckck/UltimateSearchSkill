#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP_DIR="$(mktemp -d)"
FAKE_BIN="$TMP_DIR/bin"
CURL_LOG="$TMP_DIR/curl.log"
mkdir -p "$FAKE_BIN"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s
' "$*" >> "$CURL_LOG"

if [[ "$*" == *"/v1/responses"* ]]; then
  cat <<'JSON'
{"output":[{"type":"message","content":[{"type":"output_text","text":"responses-ok"}]}],"model":"compat-model","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}
200
JSON
else
  cat <<'JSON'
{"choices":[{"message":{"content":"chat-ok"}}],"model":"compat-model","usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
200
JSON
fi
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

run_script() {
  env -i \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    CURL_LOG="$CURL_LOG" \
    OPENAI_COMPATIBLE_BASE_URL="${OPENAI_COMPATIBLE_BASE_URL:-}" \
    OPENAI_COMPATIBLE_API_KEY="${OPENAI_COMPATIBLE_API_KEY:-}" \
    OPENAI_COMPATIBLE_MODEL="${OPENAI_COMPATIBLE_MODEL:-}" \
    OPENAI_COMPATIBLE_SEARCH_MODE="${OPENAI_COMPATIBLE_SEARCH_MODE:-}" \
    "$ROOT_DIR/scripts/grok-search.sh" --query "hello" 2>&1
}

rm -f "$CURL_LOG"
if ! output=$(OPENAI_COMPATIBLE_BASE_URL="https://example.com/v1" \
  OPENAI_COMPATIBLE_API_KEY="compat-key" \
  OPENAI_COMPATIBLE_MODEL="compat-model" \
  run_script); then
  fail "grok-search.sh should support OPENAI_COMPATIBLE_* configuration"$'\n'"output: $output"
fi
assert_contains "$output" '"content": "chat-ok"'
assert_contains "$output" '"mode": "openai_compatible_chat"'
assert_contains "$(cat "$CURL_LOG")" '/v1/chat/completions'

rm -f "$CURL_LOG"
if ! xai_output=$(OPENAI_COMPATIBLE_BASE_URL="https://api.x.ai/v1" \
  OPENAI_COMPATIBLE_API_KEY="compat-key" \
  OPENAI_COMPATIBLE_MODEL="compat-model" \
  run_script); then
  fail "xAI known URL should be accepted for automatic mode selection"$'\n'"output: $xai_output"
fi
assert_contains "$xai_output" '"content": "responses-ok"'
assert_contains "$xai_output" '"mode": "xai_web_search"'
assert_contains "$(cat "$CURL_LOG")" '/v1/responses'

rm -f "$CURL_LOG"
if ! openrouter_output=$(OPENAI_COMPATIBLE_BASE_URL="https://openrouter.ai/api/v1" \
  OPENAI_COMPATIBLE_API_KEY="compat-key" \
  OPENAI_COMPATIBLE_MODEL="compat-model" \
  run_script); then
  fail "OpenRouter known URL should be accepted for automatic mode selection"$'\n'"output: $openrouter_output"
fi
assert_contains "$openrouter_output" '"content": "responses-ok"'
assert_contains "$openrouter_output" '"mode": "openrouter_web"'
assert_contains "$(cat "$CURL_LOG")" '/v1/responses'

rm -f "$CURL_LOG"
if ! manual_none_output=$(OPENAI_COMPATIBLE_BASE_URL="https://api.x.ai/v1" \
  OPENAI_COMPATIBLE_API_KEY="compat-key" \
  OPENAI_COMPATIBLE_MODEL="compat-model" \
  OPENAI_COMPATIBLE_SEARCH_MODE="none" \
  run_script); then
  fail "manual search mode none should override automatic enhancement"$'\n'"output: $manual_none_output"
fi
assert_contains "$manual_none_output" '"content": "chat-ok"'
assert_contains "$manual_none_output" '"mode": "openai_compatible_chat"'
assert_contains "$(cat "$CURL_LOG")" '/v1/chat/completions'

echo "PASS: grok search openai compatible mode"
