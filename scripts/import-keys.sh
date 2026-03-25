#!/usr/bin/env bash
set -eo pipefail

# =========================================================
# import-keys.sh — 从 .env 批量导入 Key 到各服务
# =========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# 加载 .env
if [[ ! -f "$PROJECT_DIR/.env" ]]; then
  error ".env 文件不存在，请先创建"
  exit 1
fi

set -a; source "$PROJECT_DIR/.env"; set +a

GROK2API_PORT="${GROK2API_PORT:-8100}"
TAVILY_PROXY_PORT="${TAVILY_PROXY_PORT:-8200}"
GROK2API_APP_KEY="${GROK2API_APP_KEY:-}"
DEFAULT_GROK2API_APP_KEY="grok2api"
ACTIVE_GROK2API_APP_KEY=""

grok_admin_request() {
  local method="$1"
  local endpoint="$2"
  local key="$3"
  local data="${4:-}"
  local args=(
    -s
    -w "\n%{http_code}"
    -X "$method" "http://127.0.0.1:$GROK2API_PORT$endpoint"
    -H "Authorization: Bearer $key"
  )

  if [[ -n "$data" ]]; then
    args+=(-H "Content-Type: application/json" -d "$data")
  fi

  curl "${args[@]}"
}

resolve_grok2api_app_key() {
  local candidates=()
  local result http_code

  if [[ -n "$GROK2API_APP_KEY" ]]; then
    candidates+=("$GROK2API_APP_KEY")
  fi
  if [[ "$GROK2API_APP_KEY" != "$DEFAULT_GROK2API_APP_KEY" ]]; then
    candidates+=("$DEFAULT_GROK2API_APP_KEY")
  fi

  for candidate in "${candidates[@]}"; do
    result=$(grok_admin_request GET "/v1/admin/tokens" "$candidate")
    http_code=$(echo "$result" | tail -1)
    if [[ "$http_code" -eq 200 ]]; then
      ACTIVE_GROK2API_APP_KEY="$candidate"
      if [[ -n "$GROK2API_APP_KEY" && "$candidate" != "$GROK2API_APP_KEY" ]]; then
        warn "GROK2API_APP_KEY 校验失败，已回退到 grok2api 默认后台密码；建议同步更新 .env 或后台配置"
      fi
      return 0
    fi
  done

  ACTIVE_GROK2API_APP_KEY="${GROK2API_APP_KEY:-$DEFAULT_GROK2API_APP_KEY}"
  return 1
}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  批量导入 Key 到服务${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if ! resolve_grok2api_app_key; then
  warn "无法提前验证 grok2api 后台密码，后续管理接口调用可能失败"
fi

# ==========================================
# 1. 导入 Grok SSO Tokens（从文件）
# ==========================================
GROK_SSO_FILE="${1:-${PROJECT_DIR}/export_sso.txt}"

if [[ -f "$GROK_SSO_FILE" ]]; then
  info "导入 Grok SSO Tokens（从 $GROK_SSO_FILE）..."

  # 读取文件中的 token，每行一个
  TOKENS_JSON="["
  FIRST=true
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(echo "$line" | xargs)"  # trim whitespace
    [[ -z "$line" || "$line" == \#* ]] && continue
    # 去掉可能的 sso= 前缀
    line="${line#sso=}"
    if [[ "$FIRST" == "true" ]]; then
      TOKENS_JSON+="\"$line\""
      FIRST=false
    else
      TOKENS_JSON+=",\"$line\""
    fi
  done < "$GROK_SSO_FILE"
  TOKENS_JSON+="]"

  TOKEN_COUNT=$(echo "$TOKENS_JSON" | jq 'length')
  info "发现 $TOKEN_COUNT 个 Grok Token，正在导入..."

  RESULT=$(grok_admin_request POST "/v1/admin/tokens" "$ACTIVE_GROK2API_APP_KEY" "{\"ssoBasic\": $TOKENS_JSON}")

  HTTP_CODE=$(echo "$RESULT" | tail -1)
  BODY=$(echo "$RESULT" | sed '$d')

  if [[ "$HTTP_CODE" -eq 200 ]]; then
    ok "Grok Tokens 导入成功（$TOKEN_COUNT 个）"
  else
    error "Grok Tokens 导入失败 (HTTP $HTTP_CODE): $BODY"
  fi
else
  warn "未找到 Grok SSO 文件: $GROK_SSO_FILE，跳过"
fi

echo ""

# ==========================================
# 2. 获取 TavilyProxyManager Master Key
# ==========================================
TAVILY_MASTER_KEY="${TAVILY_MASTER_KEY:-}"

if [[ -z "$TAVILY_MASTER_KEY" ]]; then
  info "TAVILY_MASTER_KEY 未设置，尝试从日志获取..."
  cd "$PROJECT_DIR"
  if command -v docker &>/dev/null; then
    TAVILY_MASTER_KEY=$(docker compose logs tavily-proxy 2>&1 | grep -oE 'master_key=[^ ]+' | head -1 | cut -d= -f2 || true)
    if [[ -n "$TAVILY_MASTER_KEY" ]]; then
      ok "从日志获取到 Master Key: ${TAVILY_MASTER_KEY:0:10}..."
      warn "请将此 Key 填入 .env 的 TAVILY_MASTER_KEY"
    else
      error "无法从日志获取 Master Key"
    fi
  fi
fi

# ==========================================
# 3. 导入 Tavily API Keys
# ==========================================
TAVILY_API_KEYS="${TAVILY_API_KEYS:-}"

if [[ -n "$TAVILY_API_KEYS" && -n "$TAVILY_MASTER_KEY" ]]; then
  info "导入 Tavily API Keys..."

  IFS=',' read -ra KEYS <<< "$TAVILY_API_KEYS"
  SUCCESS=0
  FAIL=0

  for key in "${KEYS[@]}"; do
    key="$(echo "$key" | xargs)"  # trim whitespace
    [[ -z "$key" ]] && continue

    RESULT=$(curl -s -w "\n%{http_code}" \
      -X POST "http://127.0.0.1:$TAVILY_PROXY_PORT/api/keys" \
      -H "Authorization: Bearer $TAVILY_MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"key\": \"$key\", \"alias\": \"批量导入\", \"total_quota\": 1000}")

    HTTP_CODE=$(echo "$RESULT" | tail -1)
    if [[ "$HTTP_CODE" -eq 200 ]]; then
      ((SUCCESS++))
    else
      ((FAIL++))
      BODY=$(echo "$RESULT" | sed '$d')
      warn "Tavily Key ${key:0:10}... 导入失败: $BODY"
    fi
  done

  ok "Tavily Keys 导入完成：成功 $SUCCESS 个，失败 $FAIL 个"
elif [[ -z "$TAVILY_API_KEYS" ]]; then
  warn "TAVILY_API_KEYS 未设置，跳过 Tavily Key 导入"
elif [[ -z "$TAVILY_MASTER_KEY" ]]; then
  error "TAVILY_MASTER_KEY 未设置，无法导入 Tavily Keys"
fi

echo ""

# ==========================================
# 4. 导入 FireCrawl API Keys（预留）
# ==========================================
FIRECRAWL_API_KEYS="${FIRECRAWL_API_KEYS:-}"

if [[ -n "$FIRECRAWL_API_KEYS" ]]; then
  info "FireCrawl Keys 已配置，当前版本暂不支持自动导入（需要 FireCrawl 代理服务）"
  IFS=',' read -ra KEYS <<< "$FIRECRAWL_API_KEYS"
  info "  发现 ${#KEYS[@]} 个 FireCrawl Key"
fi

echo ""

# ==========================================
# 5. 更新 .env 中的 TAVILY_MASTER_KEY
# ==========================================
if [[ -n "$TAVILY_MASTER_KEY" ]]; then
  # 检查 .env 中是否已设置
  CURRENT_MASTER=$(grep '^TAVILY_MASTER_KEY=' "$PROJECT_DIR/.env" | cut -d= -f2- || true)

  if [[ -z "$CURRENT_MASTER" ]]; then
    info "自动更新 .env 中的 TAVILY_MASTER_KEY..."
    sed -i.bak "s|^TAVILY_MASTER_KEY=.*|TAVILY_MASTER_KEY=$TAVILY_MASTER_KEY|" "$PROJECT_DIR/.env"
    rm -f "$PROJECT_DIR/.env.bak"
    ok ".env 已更新"
  fi
fi

# ==========================================
# 验证结果
# ==========================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  验证服务状态${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查 grok2api Token 数量
GROK_TOKENS=$(curl -s \
  -H "Authorization: Bearer $ACTIVE_GROK2API_APP_KEY" \
  "http://127.0.0.1:$GROK2API_PORT/v1/admin/tokens" 2>/dev/null || echo "{}")

GROK_COUNT=$(echo "$GROK_TOKENS" | jq 'if type == "object" and (.error | not) then [to_entries[] | select(.value | type == "array") | .value | length] | add // 0 else 0 end' 2>/dev/null || echo "?")
info "grok2api Token 数量: $GROK_COUNT"

# 检查 TavilyProxyManager Key 数量
if [[ -n "$TAVILY_MASTER_KEY" ]]; then
  TAVILY_KEYS_RESULT=$(curl -s \
    -H "Authorization: Bearer $TAVILY_MASTER_KEY" \
    "http://127.0.0.1:$TAVILY_PROXY_PORT/api/keys" 2>/dev/null || echo "{}")

  TAVILY_COUNT=$(echo "$TAVILY_KEYS_RESULT" | jq '.items | length' 2>/dev/null || echo "?")
  info "TavilyProxyManager Key 数量: $TAVILY_COUNT"
fi

echo ""
ok "导入完成！"
