#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载 .env（如果环境变量未设置）
if [[ -f "$SCRIPT_DIR/../.env" ]]; then
  while IFS='=' read -r key value; do
    key="$(echo "$key" | xargs)"
    [[ -z "$key" || "$key" == \#* ]] && continue
    value="$(echo "$value" | xargs | sed -e "s/^['\"]//;s/['\"]$//")"
    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$SCRIPT_DIR/../.env"
fi

GROK_API_URL="${GROK_API_URL:-}"
GROK_API_KEY="${GROK_API_KEY:-}"
GROK_MODEL="${GROK_MODEL:-grok-4.1-fast}"

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

Grok AI 智能搜索 — 通过 Grok 模型的联网能力进行 AI 驱动搜索

选项:
  --query "查询内容"     必需，搜索查询内容
  --platform "平台"      可选，聚焦平台（如 Twitter, GitHub, Reddit）
  --model "模型"         可选，覆盖默认模型 ($GROK_MODEL)
  --help                 显示此帮助信息

示例:
  $(basename "$0") --query "FastAPI 最新用法"
  $(basename "$0") --query "React 19 新特性" --platform "GitHub"
  $(basename "$0") --query "latest AI news" --model "grok-3"
EOF
  exit 0
}

error_exit() {
  jq -Rn --arg error "$1" '{error: $error}'
  exit 1
}

QUERY=""
PLATFORM=""
MODEL="$GROK_MODEL"

if [[ $# -eq 0 ]]; then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      QUERY="$2"
      shift 2
      ;;
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      error_exit "未知参数: $1"
      ;;
  esac
done

[[ -z "$QUERY" ]] && error_exit "缺少必需参数 --query"
[[ -z "$GROK_API_URL" ]] && error_exit "未设置 GROK_API_URL"

# system prompt（来自 GrokSearch MCP 的 search_prompt）
SYSTEM_PROMPT='# Core Instruction

1. User needs may be vague. Think divergently, infer intent from multiple angles, and leverage full conversation context to progressively clarify their true needs.
2. **Breadth-First Search**—Approach problems from multiple dimensions. Brainstorm 5+ perspectives and execute parallel searches for each. Consult as many high-quality sources as possible before responding.
3. **Depth-First Search**—After broad exploration, select ≥2 most relevant perspectives for deep investigation into specialized knowledge.
4. **Evidence-Based Reasoning & Traceable Sources**—Every claim must be followed by a citation. More credible sources strengthen arguments. If no references exist, remain silent.
5. Before responding, ensure full execution of Steps 1–4.

# Search Instruction

1. Think carefully before responding—anticipate the user'\''s true intent to ensure precision.
2. Verify every claim rigorously to avoid misinformation.
3. Follow problem logic—dig deeper until clues are exhaustively clear. Use multiple parallel tool calls per query and ensure answers are well-sourced.
4. Search in English first (prioritizing English resources for volume/quality), but switch to Chinese if context demands.
5. Prioritize authoritative sources: Wikipedia, academic databases, books, reputable media/journalism.
6. Favor sharing in-depth, specialized knowledge over generic or common-sense content.

# Output Style

1. Lead with the **most probable solution** before detailed analysis.
2. **Define every technical term** in plain language.
3. **Respect facts and search results—use statistical rigor to discern truth**.
4. **Every sentence must cite sources**. More references = stronger credibility.
5. **Strictly format outputs in polished Markdown**.'

# 构建 user message
USER_MESSAGE="$QUERY"

# 时间相关关键词检测 → 注入当前日期时间
TIME_KEYWORDS='今天|最新|当前|latest|recent|today|current|now|这几天|本周|本月|近期|最近'
if echo "$QUERY" | grep -qiE "$TIME_KEYWORDS"; then
  CURRENT_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  USER_MESSAGE="[Current date and time: $CURRENT_TIME]

$USER_MESSAGE"
fi

# 平台聚焦
if [[ -n "$PLATFORM" ]]; then
  USER_MESSAGE="$USER_MESSAGE

You should focus on these platform: $PLATFORM"
fi

# 构建请求 JSON
REQUEST_JSON=$(jq -n \
  --arg model "$MODEL" \
  --arg system "$SYSTEM_PROMPT" \
  --arg user "$USER_MESSAGE" \
  '{
    model: $model,
    stream: false,
    messages: [
      { role: "system", content: $system },
      { role: "user", content: $user }
    ]
  }')

# 调用 API
CURL_ARGS=(
  -s
  -w "\n%{http_code}"
  -X POST "$GROK_API_URL/v1/chat/completions"
  -H "Content-Type: application/json"
  -d "$REQUEST_JSON"
)

# grok2api 默认允许 api_key 为空；仅在显式配置了 app.api_key 时才需要携带 Bearer。
if [[ -n "$GROK_API_KEY" ]]; then
  CURL_ARGS+=(-H "Authorization: Bearer $GROK_API_KEY")
fi

RESPONSE=$(curl "${CURL_ARGS[@]}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ne 200 ]]; then
  EXTRA_HINT=""
  if [[ "$BODY" == *"AppChatReverse"* || "$BODY" == *"upstream_error"* ]]; then
    EXTRA_HINT='；这通常不是 GROK_API_KEY 配错，而是上游 Grok 会话/SSO Token、代理链路或 Cloudflare 校验失败，请优先检查 export_sso.txt 导入结果、grok2api token 池和 cf_clearance'
  fi
  error_exit "API 请求失败 (HTTP $HTTP_CODE): $BODY$EXTRA_HINT"
fi

# 提取结果
echo "$BODY" | jq '{
  content: .choices[0].message.content,
  model: .model,
  usage: .usage
}'
