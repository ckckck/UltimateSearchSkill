# 约定

## 凭证命名

- `GROK_API_KEY`：本地 grok2api 的 Bearer Token，仅在 grok2api 显式配置 `app.api_key` 时需要；不是 Grok 官方 API key，也不是 `sso` cookie。
- `GROK2API_APP_KEY`：grok2api 管理后台密码，供 `import-keys.sh` 和 `/v1/admin/*` 使用；脚本会先尝试 `.env` 配置值，再回退默认 `grok2api`。
- `export_sso.txt` / `sso` Cookie：Grok 网页会话凭证，供 grok2api 上游访问使用。
- `TAVILY_MASTER_KEY`：TavilyProxyManager 的单个访问令牌，供 `tavily-search.sh`、`web-map.sh`、`web-fetch.sh` 使用。
- `TAVILY_API_KEYS`：多个上游 Tavily key，供 `import-keys.sh` 导入代理。

## 敏感信息排除

- `.env`、`.env.bak`、`data/`、`export_sso.txt` 必须保持在 `.gitignore` 中。
- `import-keys.sh` 在写入 `.env` 时会生成临时备份 `.env.bak`，脚本结束后会删除，但仓库仍需忽略该文件以防中断残留。
