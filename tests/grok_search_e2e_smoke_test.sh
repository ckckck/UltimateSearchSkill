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
{"choices":[{"message":{"content":"chat-smoke"}}],"model":"chat-model","usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
200
JSON
elif [[ "$*" == *"https://api.x.ai/v1/responses"* ]]; then
  cat <<'JSON'
{"output":[{"type":"message","content":[{"type":"output_text","text":"xai-smoke"}]}],"model":"xai-model","usage":{"input_tokens":2,"output_tokens":2,"total_tokens":4}}
200
JSON
elif [[ "$*" == *"https://openrouter.ai/api/v1/responses"* ]]; then
  cat <<'JSON'
{"output":[{"type":"message","content":[{"type":"output_text","text":"openrouter-smoke","annotations":[{"type":"url_citation","url":"https://example.com/citation"}]}]}],"model":"openrouter-model","usage":{"input_tokens":3,"output_tokens":3,"total_tokens":6}}
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
    OPENAI_COMPATIBLE_BASE_URL="$1" \
    OPENAI_COMPATIBLE_API_KEY="compat-key" \
    OPENAI_COMPATIBLE_MODEL="compat-model" \
    "$ROOT_DIR/scripts/grok-search.sh" --query "hello" 2>&1
}

chat_output="$(run_script "https://example.com/v1")"
assert_contains "$chat_output" '"content": "chat-smoke"'
assert_contains "$chat_output" '"mode": "openai_compatible_chat"'

xai_output="$(run_script "https://api.x.ai/v1")"
assert_contains "$xai_output" '"content": "xai-smoke"'
assert_contains "$xai_output" '"mode": "xai_web_search"'

openrouter_output="$(run_script "https://openrouter.ai/api/v1")"
assert_contains "$openrouter_output" '"content": "openrouter-smoke"'
assert_contains "$openrouter_output" '"mode": "openrouter_web"'
assert_contains "$openrouter_output" '"url": "https://example.com/citation"'

echo "PASS: grok search e2e smoke"
