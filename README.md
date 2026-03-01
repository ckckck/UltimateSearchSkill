# UltimateSearchSkill

为 [OpenClaw](https://openclaw.ai/) / [Pi](https://github.com/badlogic/pi-mono/) agent 打造的双引擎网络搜索 Skill。

```
用户提问 → Agent (SKILL.md 指导)
                ├─ grok-search.sh  → grok2api (多Token聚合) → Grok 联网搜索
                ├─ tavily-search.sh → TavilyProxyManager (多Key聚合) → Tavily 搜索
                ├─ web-fetch.sh    → Tavily Extract → FireCrawl Scrape (自动降级)
                ├─ web-map.sh      → TavilyProxyManager → Tavily Map (站点映射)
                └─ dual-search.sh  → 并行调用以上，交叉验证
```

## 特性

- **双引擎搜索**：Grok（AI 联网搜索）+ Tavily（结构化搜索），互补协作
- **多账户聚合**：通过 grok2api 和 TavilyProxyManager 聚合多个账号，自动负载均衡
- **FireCrawl 托底**：web-fetch 三级降级链（Tavily Extract → FireCrawl Scrape → 报错）
- **Cloudflare 自动绕过**：FlareSolverr 自动获取并定期刷新 `cf_clearance`
- **零 MCP 依赖**：纯 Shell 脚本 + Skill 指令，agent 通过 Bash 原生调用
- **安全加固**：端口绑定 127.0.0.1，API 认证，SSH 隧道访问管理面板
- **搜索方法论**：内置 GrokSearch MCP 的搜索规划框架和证据标准

## 快速开始

### 前置条件

- Docker + Docker Compose
- curl、jq
- Grok 账号的 SSO Session Token（至少 1 个，详见[获取方法](#1-获取-grok-sso-session-token)）
- Tavily API Key（免费 1000 次/月，注册：https://www.tavily.com/）
- FireCrawl API Key（可选，作为 web-fetch 降级方案，注册：https://www.firecrawl.dev/）

### 安装

```bash
git clone https://github.com/你的用户名/UltimateSearchSkill.git
cd UltimateSearchSkill

# 复制环境变量模板
cp .env.example .env
```

### 部署服务

```bash
# 创建数据目录
mkdir -p data/grok2api/logs data/tavily-proxy

# 拉取镜像并启动（包含 FlareSolverr + grok2api + TavilyProxyManager）
docker compose pull
docker compose up -d
```

---

## Key 导入指南

部署完成后，需要将各类 Key/Token 导入到对应服务中。

### 1. 获取 Grok SSO Session Token

grok2api 需要 Grok 网页版的 **SSO Session Token**（JWT 格式），不是 API Key。

#### 方式一：浏览器手动获取

1. 用浏览器登录 https://grok.com
2. 打开开发者工具（F12）→ Application → Cookies → `https://grok.com`
3. 找到名为 `sso` 的 Cookie，复制其值（以 `eyJ` 开头的长字符串）
4. 每个 Grok 账号对应一个 Token

#### 方式二：批量导出（推荐）

如果你有多个 Grok 账号的 SSO Cookie，可以将它们保存到 `export_sso.txt` 文件中，**每行一个 Token**：

```
eyJhbGciOiJIUzI1NiJ9.xxx...（第1个账号）
eyJhbGciOiJIUzI1NiJ9.yyy...（第2个账号）
eyJhbGciOiJIUzI1NiJ9.zzz...（第3个账号）
```

> ⚠️ `export_sso.txt` 已加入 `.gitignore`，不会被提交到 Git。

#### Token 额度说明

| 账号类型 | 额度 | 刷新周期 |
|---------|------|---------|
| Basic（免费） | 80 次 | 每 20 小时 |
| Super（付费） | 140 次 | 每 2 小时 |

### 2. 导入 Grok Token 到 grok2api

**方式一：使用 import-keys.sh 脚本（推荐）**

```bash
# 确保 export_sso.txt 在项目根目录
bash scripts/import-keys.sh
```

脚本会自动：
- 读取 `export_sso.txt` 中的 Token
- 通过 grok2api 管理 API 批量导入到 `ssoBasic` Token Pool
- 获取 TavilyProxyManager 的 Master Key 并更新 `.env`
- 导入 `.env` 中配置的 Tavily/FireCrawl Key

**方式二：通过 API 手动导入**

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

**方式三：通过 Web 管理面板**

```bash
# SSH 隧道（远程服务器）
ssh -L 8100:127.0.0.1:8100 你的服务器
# 浏览器打开 http://localhost:8100/admin
# 默认密码: grok2api
```

> **注意**：Token Pool 名称必须是 `ssoBasic`（Basic 账号）或 `ssoSuper`（Super 账号），否则 grok2api 无法调度。

### 3. Cloudflare 绕过（FlareSolverr）

grok2api 访问 Grok 官网时会被 Cloudflare 拦截（403）。项目已集成 **FlareSolverr** 来自动处理：

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

验证 cf_clearance 是否获取成功：

```bash
docker compose logs grok2api | grep "配置已更新"
# 应看到: 配置已更新: cf_cookies (长度 xxxx), 指纹: chromeXXX
```

### 4. 导入 Tavily API Key

**方式一：配置到 .env 后使用 import-keys.sh**

编辑 `.env`，将 Tavily Key 填入 `TAVILY_API_KEYS`（多个用逗号分隔）：

```bash
TAVILY_API_KEYS=tvly-xxx111,tvly-xxx222,tvly-xxx333
```

然后运行：

```bash
bash scripts/import-keys.sh
```

**方式二：通过 API 手动导入**

```bash
# 先获取 Master Key
docker compose logs tavily-proxy | grep "master key"

# 添加 Key
curl -X POST http://127.0.0.1:8200/api/keys \
  -H "Authorization: Bearer 你的MasterKey" \
  -H "Content-Type: application/json" \
  -d '{"key": "tvly-你的key", "alias": "账号A", "total_quota": 1000}'
```

**方式三：通过 Web 管理面板**

```bash
ssh -L 8200:127.0.0.1:8200 你的服务器
# 浏览器打开 http://localhost:8200
```

> TavilyProxyManager 首次启动时自动生成 Master Key，`import-keys.sh` 会自动获取并更新到 `.env`。

### 5. 配置 FireCrawl Key（可选）

FireCrawl 作为 `web-fetch.sh` 的降级方案，当 Tavily Extract 失败时自动切换。

编辑 `.env`：

```bash
# 单个 Key（脚本直接使用）
FIRECRAWL_API_KEY=fc-你的key

# 或批量配置（import-keys.sh 会取第一个）
FIRECRAWL_API_KEYS=fc-key1,fc-key2
```

FireCrawl 直接调用官方 API（`https://api.firecrawl.dev/v2/scrape`），无需代理服务。

### 6. 一键导入流程总结

```bash
# 1. 编辑 .env，填入 Tavily 和 FireCrawl Key
vim .env

# 2. 准备 Grok SSO Token 文件
# 将 Token 保存到 export_sso.txt，每行一个

# 3. 一键导入所有 Key
bash scripts/import-keys.sh

# 4. 确认 FlareSolverr 配置（首次需要）
docker compose logs grok2api | grep "配置已更新"
# 如果没有，按上面 "Cloudflare 绕过" 章节操作

# 5. 测试
bash scripts/tavily-search.sh --query "test" --max-results 1
bash scripts/grok-search.sh --query "hello" --model "grok-4.1-mini"
bash scripts/web-fetch.sh --url "https://example.com"
```

---

## 使用

```bash
# 加载环境变量
source .env

# Grok AI 搜索
grok-search.sh --query "FastAPI 最新特性"

# Tavily 搜索
tavily-search.sh --query "Python web frameworks comparison" --depth advanced

# 双引擎搜索
dual-search.sh --query "Rust vs Go 2026"

# 抓取网页内容（Tavily → FireCrawl 自动降级）
web-fetch.sh --url "https://docs.python.org/3/whatsnew/3.13.html"

# 站点映射
web-map.sh --url "https://docs.tavily.com" --depth 2
```

## 注册为 Skill

```bash
# 在 OpenClaw/Pi 中注册
ln -s $(pwd)/SKILL.md ~/.openclaw/skills/ultimate-search/SKILL.md

# 将脚本加入 PATH
echo "export PATH=\"$(pwd)/scripts:\$PATH\"" >> ~/.bashrc
source ~/.bashrc
```

## 架构说明

详见 [docs/architecture.md](docs/architecture.md)。

## 安全说明

- 所有端口绑定到 `127.0.0.1`，外部无法直接访问
- `export_sso.txt`、`.env`、`data/` 已加入 `.gitignore`，不会提交到 Git
- grok2api 默认管理密码 `grok2api`，建议修改 `data/grok2api/config.toml` 中的 `app_key`
- TavilyProxyManager 使用随机生成的 Master Key
- 远程管理通过 SSH 隧道访问
- 详见 [安全加固指南](docs/architecture.md#安全加固)

## 致谢

- [GrokSearch MCP](https://github.com/GuDaStudio/GrokSearch) — 搜索方法论和提示词的灵感来源
- [grok2api](https://github.com/chenyme/grok2api) — Grok Token 聚合服务
- [TavilyProxyManager](https://github.com/xuncv/TavilyProxyManager) — Tavily Key 聚合服务
- [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) — Cloudflare 自动绕过
- [FireCrawl](https://www.firecrawl.dev/) — 网页抓取降级方案

## License

MIT
