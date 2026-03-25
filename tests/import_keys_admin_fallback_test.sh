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

python3 -u - "$PORT_FILE" "$SERVER_LOG" >"$TMP_DIR/python.log" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file = sys.argv[1]
log_file = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def _read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def _log(self, payload):
        with open(log_file, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(payload) + "\n")

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        auth = self.headers.get("Authorization")
        self._log({"method": "GET", "path": self.path, "auth": auth})
        if self.path == "/v1/admin/tokens":
          if auth == "Bearer grok2api":
              self._send(200, {"ssoBasic": ["tok-a", "tok-b"]})
          else:
              self._send(401, {"error": "bad auth"})
          return

        if self.path == "/api/keys":
            self._send(200, {"items": []})
            return

        self._send(404, {"error": "not found"})

    def do_POST(self):
        auth = self.headers.get("Authorization")
        payload = self._read_json()
        self._log({"method": "POST", "path": self.path, "auth": auth, "payload": payload})

        if self.path == "/v1/admin/tokens":
            if auth == "Bearer grok2api":
                self._send(200, {"status": "ok"})
            else:
                self._send(401, {"error": "bad auth"})
            return

        if self.path == "/api/keys":
            self._send(200, {"status": "ok"})
            return

        self._send(404, {"error": "not found"})

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
PROJECT_DIR="$TMP_DIR/project"
mkdir -p "$PROJECT_DIR/scripts"
cp "$ROOT_DIR/scripts/import-keys.sh" "$PROJECT_DIR/scripts/"
chmod +x "$PROJECT_DIR/scripts/import-keys.sh"

cat >"$PROJECT_DIR/.env" <<EOF
GROK2API_PORT=$PORT
GROK2API_APP_KEY=wrong-key
TAVILY_PROXY_PORT=$PORT
TAVILY_MASTER_KEY=master-test
TAVILY_API_KEYS=
FIRECRAWL_API_KEYS=
EOF

cat >"$PROJECT_DIR/export_sso.txt" <<'EOF'
token-one
token-two
EOF

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"$'\n'"actual: $haystack"
}

assert_log_contains() {
  local needle="$1"
  if ! grep -Fq "$needle" "$SERVER_LOG"; then
    fail "expected server log to contain: $needle"
  fi
}

output="$(
  cd "$PROJECT_DIR" &&
    PATH="$PATH" bash scripts/import-keys.sh 2>&1
)"

assert_contains "$output" 'Grok Tokens 导入成功（2 个）'
assert_contains "$output" 'grok2api Token 数量: 2'
assert_log_contains '"auth": "Bearer grok2api"'

echo "PASS: import keys admin fallback"
