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
' "$*" > "$CURL_LOG"

json='{"choices":[{"message":{"content":"ok"}}],"model":"compat-model","usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}'
if [[ "$*" == *"/v1/responses"* ]]; then
  json='{"output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}],"model":"compat-model","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}'
fi

printf '%s
200
' "$json"
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

extract_body() {
  python3 - <<'PY' "$CURL_LOG"
import sys

log = open(sys.argv[1], encoding='utf-8').read()
marker = " -d "
start = log.index(marker) + len(marker)
body = log[start:]
print(body)
PY
}

run_script() {
  env -i \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    CURL_LOG="$CURL_LOG" \
    OPENAI_COMPATIBLE_BASE_URL="${OPENAI_COMPATIBLE_BASE_URL:-}" \
    OPENAI_COMPATIBLE_API_KEY="${OPENAI_COMPATIBLE_API_KEY:-}" \
    OPENAI_COMPATIBLE_MODEL="${OPENAI_COMPATIBLE_MODEL:-}" \
    OPENAI_COMPATIBLE_SEARCH_MODE="${OPENAI_COMPATIBLE_SEARCH_MODE:-}" \
    "$ROOT_DIR/scripts/grok-search.sh" --query "latest hello" --platform "GitHub" >/dev/null
}

rm -f "$CURL_LOG"
OPENAI_COMPATIBLE_BASE_URL="https://example.com/v1" \
OPENAI_COMPATIBLE_API_KEY="compat-key" \
OPENAI_COMPATIBLE_MODEL="compat-model" \
run_script
body="$(extract_body)"
assert_contains "$(cat "$CURL_LOG")" '/v1/chat/completions'
assert_contains "$body" '"messages"'
assert_contains "$body" '"role": "system"'
assert_contains "$body" '"role": "user"'
assert_contains "$body" 'Current date and time:'
assert_contains "$body" 'You should focus on these platform: GitHub'

rm -f "$CURL_LOG"
OPENAI_COMPATIBLE_BASE_URL="https://api.x.ai/v1" \
OPENAI_COMPATIBLE_API_KEY="compat-key" \
OPENAI_COMPATIBLE_MODEL="compat-model" \
run_script
body="$(extract_body)"
assert_contains "$(cat "$CURL_LOG")" '/v1/responses'
assert_contains "$body" '"input"'
assert_contains "$body" '"tools"'
assert_contains "$body" '"type": "web_search"'
assert_contains "$body" 'You should focus on these platform: GitHub'

rm -f "$CURL_LOG"
OPENAI_COMPATIBLE_BASE_URL="https://openrouter.ai/api/v1" \
OPENAI_COMPATIBLE_API_KEY="compat-key" \
OPENAI_COMPATIBLE_MODEL="compat-model" \
run_script
body="$(extract_body)"
assert_contains "$(cat "$CURL_LOG")" '/v1/responses'
assert_contains "$body" '"plugins"'
assert_contains "$body" '"id": "web"'
assert_contains "$body" '"type": "message"'
assert_contains "$body" '"type": "input_text"'

echo "PASS: grok search request shapes"
