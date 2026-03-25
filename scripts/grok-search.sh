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

OPENAI_COMPATIBLE_BASE_URL="${OPENAI_COMPATIBLE_BASE_URL:-}"
OPENAI_COMPATIBLE_API_KEY="${OPENAI_COMPATIBLE_API_KEY:-}"
OPENAI_COMPATIBLE_MODEL="${OPENAI_COMPATIBLE_MODEL:-}"
OPENAI_COMPATIBLE_SEARCH_MODE="${OPENAI_COMPATIBLE_SEARCH_MODE:-}"

GROK_API_URL="${OPENAI_COMPATIBLE_BASE_URL:-${GROK_API_URL:-}}"
GROK_API_KEY="${OPENAI_COMPATIBLE_API_KEY:-${GROK_API_KEY:-}}"
GROK_MODEL="${OPENAI_COMPATIBLE_MODEL:-${GROK_MODEL:-grok-4.1-fast}}"

normalize_base_url() {
  local url="$1"
  url="${url%/}"
  if [[ "$url" == */v1 ]]; then
    printf '%s' "$url"
  else
    printf '%s/v1' "$url"
  fi
}

detect_search_mode() {
  local normalized_url="$1"

  case "$OPENAI_COMPATIBLE_SEARCH_MODE" in
    "") ;;
    none) printf '%s' 'openai_compatible_chat'; return ;;
    xai_web_search|openrouter_web) printf '%s' "$OPENAI_COMPATIBLE_SEARCH_MODE"; return ;;
    *) error_exit "不支持的 OPENAI_COMPATIBLE_SEARCH_MODE: $OPENAI_COMPATIBLE_SEARCH_MODE" ;;
  esac

  case "$normalized_url" in
    https://api.x.ai/v1) printf '%s' 'xai_web_search' ;;
    https://openrouter.ai/api/v1) printf '%s' 'openrouter_web' ;;
    *) printf '%s' 'openai_compatible_chat' ;;
  esac
}

is_auto_enhanced_mode() {
  case "$1" in
    xai_web_search|openrouter_web)
      [[ -z "$OPENAI_COMPATIBLE_SEARCH_MODE" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

build_request_json() {
  local mode="$1"

  case "$mode" in
    openai_compatible_chat)
      jq -n \
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
        }'
      ;;
    xai_web_search)
      jq -n \
        --arg model "$MODEL" \
        --arg system "$SYSTEM_PROMPT" \
        --arg user "$USER_MESSAGE" \
        '{
          model: $model,
          input: [
            { role: "system", content: $system },
            { role: "user", content: $user }
          ],
          tools: [
            { type: "web_search" }
          ]
        }'
      ;;
    openrouter_web)
      jq -n \
        --arg model "$MODEL" \
        --arg system "$SYSTEM_PROMPT" \
        --arg user "$USER_MESSAGE" \
        '{
          model: $model,
          input: [
            { type: "message", role: "system", content: [{ type: "input_text", text: $system }] },
            { type: "message", role: "user", content: [{ type: "input_text", text: $user }] }
          ],
          plugins: [
            { id: "web" }
          ]
        }'
      ;;
    *)
      error_exit "未知搜索模式: $mode"
      ;;
  esac
}

extract_response_json() {
  local mode="$1"
  local body="$2"

  case "$mode" in
    openai_compatible_chat)
      echo "$body" | jq --arg mode "$mode" '{
        content: .choices[0].message.content,
        model: .model,
        usage: .usage,
        mode: $mode
      }'
      ;;
    xai_web_search|openrouter_web)
      echo "$body" | jq --arg mode "$mode" '{
        content: (([.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | (.text // .content)] | first) // .output_text),
        model: .model,
        usage: .usage,
        citations: ([.output[]? | select(.type == "message") | .content[]? | .annotations[]? | select(.type == "url_citation")] // []),
        mode: $mode
      }'
      ;;
    *)
      error_exit "未知搜索模式: $mode"
      ;;
  esac
}

perform_request() {
  local endpoint="$1"
  local request_json="$2"
  local response http_code body

  local curl_args=(
    -s
    -w "\n%{http_code}"
    -X POST "$endpoint"
    -H "Content-Type: application/json"
    -d "$request_json"
  )

  # 兼容 legacy grok2api：仅在显式提供 key 时才发送 Bearer。
  if [[ -n "$GROK_API_KEY" ]]; then
    curl_args+=(-H "Authorization: Bearer $GROK_API_KEY")
  fi

  response=$(curl "${curl_args[@]}")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  printf '%s\n%s' "$http_code" "$body"
}

build_error_message() {
  local http_code="$1"
  local body="$2"
  local extra_hint=""

  if [[ "$body" == *"AppChatReverse"* || "$body" == *"upstream_error"* ]]; then
    extra_hint='；这通常不是 GROK_API_KEY 配错，而是上游 Grok 会话/SSO Token、代理链路或 Cloudflare 校验失败，请优先检查 export_sso.txt 导入结果、grok2api token 池和 cf_clearance'
  fi

  printf '%s' "API 请求失败 (HTTP $http_code): $body$extra_hint"
}

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

Grok AI 智能搜索 — 通过 Grok 模型的联网能力进行 AI 驱动搜索

选项:
  --query "查询内容"     必需，搜索查询内容
  --platform "平台"      可选，聚焦平台（如 Twitter, GitHub, Reddit）
  --model "模型"         可选，覆盖默认模型 ($GROK_MODEL)
  --help                 显示此帮助信息

环境变量:
  OPENAI_COMPATIBLE_BASE_URL     推荐的统一兼容后端入口
  OPENAI_COMPATIBLE_API_KEY      统一兼容后端 API Key
  OPENAI_COMPATIBLE_MODEL        统一兼容后端模型名
  OPENAI_COMPATIBLE_SEARCH_MODE  可选：none / xai_web_search / openrouter_web
  GROK_API_URL                   legacy grok2api 入口
  GROK_API_KEY                   legacy grok2api Bearer，仅在配置 app.api_key 时需要

说明:
  已知 URL（xAI / OpenRouter）会自动增强搜索；未知 URL 默认走普通兼容聊天。
  grok2api 仍保留为 legacy/experimental 路径。

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

API_BASE_URL="$(normalize_base_url "$GROK_API_URL")"
SEARCH_MODE="$(detect_search_mode "$API_BASE_URL")"

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
REQUEST_JSON="$(build_request_json "$SEARCH_MODE")"

API_ENDPOINT="$API_BASE_URL/chat/completions"
if [[ "$SEARCH_MODE" == "xai_web_search" || "$SEARCH_MODE" == "openrouter_web" ]]; then
  API_ENDPOINT="$API_BASE_URL/responses"
fi

HTTP_AND_BODY="$(perform_request "$API_ENDPOINT" "$REQUEST_JSON")"
HTTP_CODE="$(echo "$HTTP_AND_BODY" | head -1)"
BODY="$(echo "$HTTP_AND_BODY" | tail -n +2)"

if [[ "$HTTP_CODE" -ne 200 ]]; then
  if is_auto_enhanced_mode "$SEARCH_MODE"; then
    FALLBACK_MODE='openai_compatible_chat'
    FALLBACK_REQUEST_JSON="$(build_request_json "$FALLBACK_MODE")"
    FALLBACK_ENDPOINT="$API_BASE_URL/chat/completions"
    FALLBACK_HTTP_AND_BODY="$(perform_request "$FALLBACK_ENDPOINT" "$FALLBACK_REQUEST_JSON")"
    FALLBACK_HTTP_CODE="$(echo "$FALLBACK_HTTP_AND_BODY" | head -1)"
    FALLBACK_BODY="$(echo "$FALLBACK_HTTP_AND_BODY" | tail -n +2)"

    if [[ "$FALLBACK_HTTP_CODE" -eq 200 ]]; then
      extract_response_json "$FALLBACK_MODE" "$FALLBACK_BODY" | jq --arg degraded_from "$SEARCH_MODE" --arg warning 'provider native web search unavailable; downgraded to plain compatible chat' '. + {degraded_from: $degraded_from, realtime_warning: $warning}'
      exit 0
    fi
  fi

  error_exit "$(build_error_message "$HTTP_CODE" "$BODY")"
fi

# 提取结果
extract_response_json "$SEARCH_MODE" "$BODY"
