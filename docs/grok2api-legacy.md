# grok2api Legacy 配置指南

本文档仅适用于 **legacy/experimental** 的 `grok2api` 接入方式。

如果你使用的是当前推荐方案，请优先查看主 [README](../README.md) 中的 `OpenAI Compatible` 配置说明，通过 OpenAI Compatible API 使用 Grok。

## 适用场景

- 你已经部署并依赖本地 `grok2api`
- 你需要继续复用 `export_sso.txt`、`FlareSolverr` 和本地 `grok2api` 管理面板
- 你明确知道自己不是在走 OpenAI Compatible 直连/代理链路

## 凭证边界

- `export_sso.txt` / `sso` Cookie：这是 **Grok 网页会话凭证**，供 grok2api 访问 grok.com 使用。
- `.env` 里的 `GROK_API_KEY`：这是 **本地 grok2api 的 Bearer Token**，只在你给 grok2api 配置了 `app.api_key` 时才需要。
- `.env` 里的 `GROK2API_APP_KEY`：这是 **grok2api 管理后台密码**，供 `import-keys.sh` 和 `/v1/admin/*` 使用。

如果看到 `AppChatReverse: Chat failed, 403` 这类上游报错，优先排查的是 `sso` token、token 池状态、代理链路和 `cf_clearance`，通常不是 `GROK_API_KEY` 填错。

## 部署服务

```bash
# 创建数据目录
mkdir -p data/grok2api/logs data/tavily-proxy

# 拉取镜像并启动（包含 FlareSolverr + grok2api + TavilyProxyManager）
docker compose pull
docker compose up -d
```

## 获取 Grok SSO Session Token

grok2api 需要 Grok 网页版的 **SSO Session Token**（JWT 格式），不是 API Key。

### 方式一：浏览器手动获取

1. 用浏览器登录 `https://grok.com`
2. 打开开发者工具（F12）→ Application → Cookies → `https://grok.com`
3. 找到名为 `sso` 的 Cookie，复制其值（以 `eyJ` 开头的长字符串）
4. 每个 Grok 账号对应一个 Token

### 方式二：批量导出

如果你有多个 Grok 账号的 SSO Cookie，可以将它们保存到 `export_sso.txt` 文件中，**每行一个 Token**：

```text
eyJhbGciOiJIUzI1NiJ9.xxx...（第1个账号）
eyJhbGciOiJIUzI1NiJ9.yyy...（第2个账号）
eyJhbGciOiJIUzI1NiJ9.zzz...（第3个账号）
```

> `export_sso.txt` 已加入 `.gitignore`，不会被提交到 Git。

### Token 额度说明

| 账号类型 | 额度 | 刷新周期 |
|---------|------|---------|
| Basic（免费） | 80 次 | 每 20 小时 |
| Super（付费） | 140 次 | 每 2 小时 |

## 导入 Grok Token 到 grok2api

### 方式一：使用 `import-keys.sh`

```bash
# 确保 export_sso.txt 在项目根目录
bash scripts/import-keys.sh
```

脚本会自动：

- 读取 `export_sso.txt` 中的 Token
- 通过 grok2api 管理 API 批量导入到 `ssoBasic` Token Pool
- 获取 TavilyProxyManager 的 Master Key 并更新 `.env`
- 导入 `.env` 中配置的 Tavily/FireCrawl Key

如果 `.env` 里的 `GROK2API_APP_KEY` 与当前 grok2api 后台密码不一致，脚本会先尝试该值，再自动回退默认密码 `grok2api`。

### 方式二：通过 API 手动导入

```bash
# 单个 Token
curl -X POST http://127.0.0.1:8100/v1/admin/tokens \
  -H "Authorization: Bearer grok2api" \
  -H "Content-Type: application/json" \
  -d '{"ssoBasic": ["eyJhbGci...你的Token"]}'

# 批量导入（从文件）
TOKENS=$(cat export_sso.txt | jq -R 'select(length > 0)' | jq -s '.')
curl -X POST http://127.0.0.1:8100/v1/admin/tokens \
  -H "Authorization: Bearer grok2api" \
  -H "Content-Type: application/json" \
  -d "{\"ssoBasic\": $TOKENS}"
```

### 方式三：通过 Web 管理面板

```bash
ssh -L 8100:127.0.0.1:8100 你的服务器
# 浏览器打开 http://localhost:8100/admin
# 默认密码: grok2api
```

> Token Pool 名称必须是 `ssoBasic`（Basic 账号）或 `ssoSuper`（Super 账号），否则 grok2api 无法调度。

## 配置 `GROK_API_KEY` 的正确方式

`scripts/grok-search.sh` 调用的是本地 `grok2api` 的 `/v1/chat/completions`，不是直接调 Grok 官方接口。

- 如果 grok2api 的 `app.api_key` 为空：`.env` 里的 `GROK_API_KEY` 可以留空。
- 如果你在 grok2api 后台或 `config.toml` 中设置了 `app.api_key`：把同一个值填到 `.env` 的 `GROK_API_KEY`。
- 不要把 `export_sso.txt` 里的 `sso` token 填到 `GROK_API_KEY`。

## Cloudflare 绕过（FlareSolverr）

grok2api 访问 Grok 官网时会被 Cloudflare 拦截（403）。项目已集成 **FlareSolverr** 来自动处理，但该链路仍可能因网页上游变化而失效：

- FlareSolverr 使用无头 Chrome 自动通过 Cloudflare JS Challenge
- **不需要 Grok 账号密码**，只需访问 grok.com 首页即可
- 获取的 `cf_clearance` 每 3600 秒自动刷新
- `cf_clearance` 与 IP 绑定，换服务器需要重新获取（FlareSolverr 会自动处理）

首次启动时，需确保 grok2api 的 `config.toml` 已启用 FlareSolverr：

```bash
# 查看是否已自动配置（启动后自动生成 config.toml）
cat data/grok2api/config.toml | grep -A2 'flaresolverr'
```

如果 `enabled = false` 或 `flaresolverr_url` 为空，需修改：

```bash
# Linux 服务器上（Docker 生成的文件需要 sudo）
sudo sed -i 's|^enabled = false|enabled = true|' data/grok2api/config.toml
sudo sed -i 's|^flaresolverr_url = ""|flaresolverr_url = "http://ultimate-search-flaresolverr:8191"|' data/grok2api/config.toml

# 重启 grok2api 使配置生效
docker compose restart grok2api
```

验证 `cf_clearance` 是否获取成功：

```bash
docker compose logs grok2api | grep "配置已更新"
# 应看到: 配置已更新: cf_cookies (长度 xxxx), 指纹: chromeXXX
```

## Legacy 一键导入流程总结

```bash
# 1. 编辑 .env，填入 Tavily 和 FireCrawl Key
vim .env

# 2. 准备 Grok SSO Token 文件
# 将 Token 保存到 export_sso.txt，每行一个

# 3. 一键导入所有 Key
bash scripts/import-keys.sh

# 4. 确认 FlareSolverr 配置（首次需要）
docker compose logs grok2api | grep "配置已更新"

# 5. 测试
bash scripts/tavily-search.sh --query "test" --max-results 1
bash scripts/grok-search.sh --query "hello" --model "grok-4.1-mini"
bash scripts/web-fetch.sh --url "https://example.com"
```
