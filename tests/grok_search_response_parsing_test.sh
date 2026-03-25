#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP_DIR="$(mktemp -d)"
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"https://example.com/v1/chat/completions"* ]]; then
  cat <<'JSON'
{"choices":[{"message":{"content":"chat-response"}}],"model":"chat-model","usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}
200
JSON
elif [[ "$*" == *"https://api.x.ai/v1/responses"* ]]; then
  cat <<'JSON'
{"output":[{"type":"message","content":[{"type":"output_text","text":"xai-response"}]}],"model":"xai-model","usage":{"input_tokens":4,"output_tokens":5,"total_tokens":9}}
200
JSON
elif [[ "$*" == *"https://openrouter.ai/api/v1/responses"* ]]; then
  cat <<'JSON'
{"output":[{"type":"message","content":[{"type":"output_text","text":"openrouter-response","annotations":[{"type":"url_citation","url":"https://example.com/source"}]}]}],"model":"openrouter-model","usage":{"input_tokens":6,"output_tokens":7,"total_tokens":13}}
200
JSON
else
  cat <<'JSON'
{"error":"unexpected endpoint"}
500
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
    OPENAI_COMPATIBLE_BASE_URL="${OPENAI_COMPATIBLE_BASE_URL:-}" \
    OPENAI_COMPATIBLE_API_KEY="compat-key" \
    OPENAI_COMPATIBLE_MODEL="compat-model" \
    OPENAI_COMPATIBLE_SEARCH_MODE="${OPENAI_COMPATIBLE_SEARCH_MODE:-}" \
    "$ROOT_DIR/scripts/grok-search.sh" --query "hello" 2>&1
}

chat_output=$(OPENAI_COMPATIBLE_BASE_URL="https://example.com/v1" run_script)
assert_contains "$chat_output" '"content": "chat-response"'
assert_contains "$chat_output" '"model": "chat-model"'
assert_contains "$chat_output" '"mode": "openai_compatible_chat"'
assert_contains "$chat_output" '"prompt_tokens": 2'

xai_output=$(OPENAI_COMPATIBLE_BASE_URL="https://api.x.ai/v1" run_script)
assert_contains "$xai_output" '"content": "xai-response"'
assert_contains "$xai_output" '"model": "xai-model"'
assert_contains "$xai_output" '"mode": "xai_web_search"'
assert_contains "$xai_output" '"input_tokens": 4'

openrouter_output=$(OPENAI_COMPATIBLE_BASE_URL="https://openrouter.ai/api/v1" run_script)
assert_contains "$openrouter_output" '"content": "openrouter-response"'
assert_contains "$openrouter_output" '"model": "openrouter-model"'
assert_contains "$openrouter_output" '"mode": "openrouter_web"'
assert_contains "$openrouter_output" '"input_tokens": 6'
assert_contains "$openrouter_output" '"citations": ['
assert_contains "$openrouter_output" '"url": "https://example.com/source"'

echo "PASS: grok search response parsing"
