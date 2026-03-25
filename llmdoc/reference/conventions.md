# 约定

## 凭证命名

- `OPENAI_COMPATIBLE_BASE_URL` / `OPENAI_COMPATIBLE_API_KEY` / `OPENAI_COMPATIBLE_MODEL`：统一兼容后端配置，优先级高于 legacy `GROK_*`。
- `OPENAI_COMPATIBLE_SEARCH_MODE`：增强模式开关；留空表示按已知 URL 自动选择，`none` 表示强制普通兼容聊天，其余枚举值表示手动指定增强模式且失败不降级。
- `GROK_API_KEY`：本地 grok2api 的 Bearer Token，仅在 grok2api 显式配置 `app.api_key` 时需要；不是 Grok 官方 API key，也不是 `sso` cookie。
- `GROK2API_APP_KEY`：grok2api 管理后台密码，供 `import-keys.sh` 和 `/v1/admin/*` 使用；脚本会先尝试 `.env` 配置值，再回退默认 `grok2api`。
- `export_sso.txt` / `sso` Cookie：Grok 网页会话凭证，供 grok2api 上游访问使用。
- `TAVILY_MASTER_KEY`：TavilyProxyManager 的单个访问令牌，供 `tavily-search.sh`、`web-map.sh`、`web-fetch.sh` 使用。
- `TAVILY_API_KEYS`：多个上游 Tavily key，供 `import-keys.sh` 导入代理。

## 敏感信息排除

- `.env`、`.env.bak`、`data/`、`export_sso.txt` 必须保持在 `.gitignore` 中。
- `import-keys.sh` 在写入 `.env` 时会生成临时备份 `.env.bak`，脚本结束后会删除，但仓库仍需忽略该文件以防中断残留。
