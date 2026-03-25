#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
PORT_FILE="$TMP_DIR/port"
SERVER_LOG="$TMP_DIR/server.log"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

python3 -u - "$PORT_FILE" >"$SERVER_LOG" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file = sys.argv[1]


class Handler(BaseHTTPRequestHandler):
    def _read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        payload = self._read_json()
        user_message = payload["messages"][-1]["content"]
        auth = self.headers.get("Authorization")

        if "trigger upstream error" in user_message:
            self._send(502, {
                "error": {
                    "message": "AppChatReverse: Chat failed, 403",
                    "type": "server_error",
                    "code": "upstream_error"
                }
            })
            return

        content = "no-auth" if not auth else f"auth:{auth}"
        self._send(200, {
            "choices": [{"message": {"content": content}}],
            "model": payload.get("model", ""),
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
        })

    def log_message(self, *_args):
        return


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as fh:
    fh.write(str(server.server_port))
server.serve_forever()
PY
SERVER_PID=$!

for _ in $(seq 1 50); do
  if [[ -f "$PORT_FILE" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -f "$PORT_FILE" ]]; then
  echo "test server did not start" >&2
  exit 1
fi

PORT="$(cat "$PORT_FILE")"
API_URL="http://127.0.0.1:$PORT"
ISOLATED_SCRIPTS="$TMP_DIR/scripts"
mkdir -p "$ISOLATED_SCRIPTS"
cp "$ROOT_DIR/scripts/grok-search.sh" "$ISOLATED_SCRIPTS/"
chmod +x "$ISOLATED_SCRIPTS/grok-search.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"$'\n'"actual: $haystack"
}

no_auth_output="$(
  env -i PATH="$PATH" GROK_API_URL="$API_URL" GROK_MODEL="grok-4.1-mini" \
    "$ISOLATED_SCRIPTS/grok-search.sh" --query "hello" 2>&1
)"
assert_contains "$no_auth_output" '"content": "no-auth"'

with_auth_output="$(
  env -i PATH="$PATH" GROK_API_URL="$API_URL" GROK_API_KEY="local-key" GROK_MODEL="grok-4.1-mini" \
    "$ISOLATED_SCRIPTS/grok-search.sh" --query "hello" 2>&1
)"
assert_contains "$with_auth_output" '"content": "auth:Bearer local-key"'

if error_output=$(
  env -i PATH="$PATH" GROK_API_URL="$API_URL" GROK_MODEL="grok-4.1-mini" \
    "$ISOLATED_SCRIPTS/grok-search.sh" --query "trigger upstream error" 2>&1
); then
  fail "grok-search.sh should fail on upstream 502"
fi
assert_contains "$error_output" 'AppChatReverse: Chat failed, 403'
assert_contains "$error_output" '这通常不是 GROK_API_KEY 配错'

echo "PASS: grok search auth behavior"
