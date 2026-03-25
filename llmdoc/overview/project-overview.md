# 项目概览

UltimateSearchSkill 是一个面向 OpenClaw/Pi 的搜索 Skill，使用 Shell 脚本调用 Grok 与 TavilyProxyManager，提供搜索、抓取和站点映射能力。

## 当前关键约定

- Grok 相关凭证分为三类：`export_sso.txt` 中的 `sso` 会话 token 供 grok2api 访问 grok.com，`GROK_API_KEY` 仅作为本地 grok2api 的 Bearer Token，`GROK2API_APP_KEY` 仅用于 grok2api 管理后台接口。
- `scripts/grok-search.sh` 允许在 grok2api 未配置 `app.api_key` 时省略 `GROK_API_KEY`，并在上游 `AppChatReverse`/`upstream_error` 失败时提示优先排查 SSO token、token 池和 `cf_clearance`。
- Tavily 运行时脚本统一使用 `TAVILY_MASTER_KEY` 访问 TavilyProxyManager。
- `TAVILY_API_KEYS` 表示多个真实 Tavily 官方 key，仅用于导入到代理后做轮询。
- FireCrawl 仍使用 `FIRECRAWL_API_KEY` 或 `FIRECRAWL_API_KEYS` 作为降级抓取凭证。
