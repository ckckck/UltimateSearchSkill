# UltimateSearchSkill

<p align="center"><a href="./README.md">中文</a> | <a href="./README.en.md">English</a></p>

为 [OpenClaw](https://openclaw.ai/) / [Pi](https://github.com/badlogic/pi-mono/) AI Agent 打造的的双引擎 Web 搜索能力模块。Grok AI + Tavily 双引擎交叉验证，纯 Shell 实现，零 MCP 依赖。

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-0f766e?style=flat-square" />
  <img alt="Shell" src="https://img.shields.io/badge/Shell-Bash-0ea5e9?style=flat-square" />
  <img alt="Docker" src="https://img.shields.io/badge/Infra-Docker-2563eb?style=flat-square" />
  <img alt="OpenAI Compatible" src="https://img.shields.io/badge/Search-OpenAI%20Compatible-f59e0b?style=flat-square" />
  <img alt="Tavily" src="https://img.shields.io/badge/Search-Tavily-f97316?style=flat-square" />
  <img alt="FireCrawl" src="https://img.shields.io/badge/Fallback-FireCrawl-f43f5e?style=flat-square" />
</p>

```
用户提问 → Agent (SKILL.md 指导)
                ├─ grok-search.sh  → Grok（推荐） via OpenAI Compatible API
                │                   ├─ 已知 URL 自动增强（xAI / OpenRouter）
                │                   └─ 兼容其他 OpenAI Compatible 模型 / 代理
                ├─ grok-search.sh  → grok2api (legacy/experimental)
                ├─ tavily-search.sh → TavilyProxyManager (多Key聚合) → Tavily 搜索
                ├─ web-fetch.sh    → Tavily Extract → FireCrawl Scrape (自动降级)
                ├─ web-map.sh      → TavilyProxyManager → Tavily Map (站点映射)
                └─ dual-search.sh  → 并行调用以上，交叉验证
```

## 特性

- **双引擎搜索**：Grok 优先搜索 + Tavily（结构化搜索），双源交叉验证
- **多账户聚合**：Tavily 通过 TavilyProxyManager 聚合使用多个账号；`grok2api` 聚合仅保留为 legacy 方案
- **FireCrawl 托底**：web-fetch 三级降级链（Tavily Extract → FireCrawl Scrape → 报错）
- **零 MCP 依赖**：纯 Shell 脚本 + Skill 指令，agent 通过 Bash 原生调用
- **安全加固**：端口绑定 127.0.0.1，API 认证，SSH 隧道访问管理面板
- **搜索方法论**：内置 GrokSearch MCP 的搜索规划框架和证据标准

<div align="center">
  <table>
    <tr>
      <td width="88" align="center" valign="middle">
        <a href="https://www.popai.pro">
          <img src="https://popaife.s3.ap-southeast-1.amazonaws.com/other/logo_siderbar.svg" alt="PopAi logo" width="56" />
        </a>
      </td>
      <td valign="middle">
        <strong>推荐组合：UltimateSearchSkill × PopAi</strong><br/>
        升级你的工作流：用 PopAi 一键把搜索结果整理成 PPT。<br/>
        <a href="https://www.popai.pro">访问 PopAi</a>
      </td>
    </tr>
  </table>
</div>

## 快速开始

### 前置条件

- Docker + Docker Compose
- curl、jq
- 使用 OpenAI Compatible API 接入 Grok 或其他兼容模型所需的 API 凭证
- Tavily API Key（免费 1000 次/月，注册：https://www.tavily.com/）
- FireCrawl API Key（可选，作为 web-fetch 降级方案，注册：https://www.firecrawl.dev/）

### 安装

```bash
git clone https://github.com/你的用户名/UltimateSearchSkill.git
cd UltimateSearchSkill

# 复制环境变量模板
cp .env.example .env
```

### 推荐的 Grok 搜索配置

`grok-search.sh` 现在优先推荐通过 `OpenAI Compatible` 配置来使用 Grok；同一套配置也可以兼容其他 OpenAI Compatible 模型或代理：

- `OPENAI_COMPATIBLE_BASE_URL`
- `OPENAI_COMPATIBLE_API_KEY`
- `OPENAI_COMPATIBLE_MODEL`
- `OPENAI_COMPATIBLE_SEARCH_MODE`（可选）

默认行为：

- 优先推荐模型仍然是 Grok，推荐接入方式是 OpenAI Compatible API，而不是旧的网页反代链路
- 已知 URL 自动增强：目前内建支持 `https://api.x.ai/v1` 与 `https://openrouter.ai/api/v1`
- 已知 URL 自动增强失败：仅在普通兼容聊天明确可用时，才保守降级到普通模式，并在输出 JSON 中附带 `degraded_from` 与 `realtime_warning`
- 未知 URL 不做自动探测，默认仅走普通兼容聊天
- 如需兼容其他未知 OpenAI Compatible 后端，可在同一配置块中手动设置 `OPENAI_COMPATIBLE_SEARCH_MODE`；手动模式失败时不会隐式降级

示例：

```bash
OPENAI_COMPATIBLE_BASE_URL=https://openrouter.ai/api/v1
OPENAI_COMPATIBLE_API_KEY=你的key
OPENAI_COMPATIBLE_MODEL=x-ai/grok-4.1-fast
OPENAI_COMPATIBLE_SEARCH_MODE=
```

手动覆盖示例：

```bash
OPENAI_COMPATIBLE_BASE_URL=https://your-proxy.example.com/v1
OPENAI_COMPATIBLE_API_KEY=你的key
OPENAI_COMPATIBLE_MODEL=your-model
OPENAI_COMPATIBLE_SEARCH_MODE=openrouter_web
```

> `grok2api` 仍然保留，但仅作为 legacy/experimental 的遗留兼容接入方式；优先推荐的是通过 OpenAI Compatible API 使用 Grok。

脚本输出统一 JSON，核心字段包括 `content`、`model`、`usage`、`mode`；增强模式存在引用时会附带 `citations`。

## Legacy grok2api

如果你仍在使用 `grok2api` / 旧 Grok 网页反代链路，请注意这已经是 **legacy/experimental** 配置方式，不再作为主 README 的推荐主线。

- legacy 凭证边界、`GROK_API_KEY` 的正确含义、SSO Token 获取方式
- `grok2api` 的 Token 导入、管理面板、FlareSolverr 配置与 Cloudflare 排障
- legacy 一键导入流程与部署注意事项

请改看单独文档：[docs/grok2api-legacy.md](docs/grok2api-legacy.md)

---
### 导入 Tavily API Key

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

脚本调用 TavilyProxyManager 时使用的是 `.env` 中的 `TAVILY_MASTER_KEY`。`TAVILY_API_KEYS` 仅用于把多个真实 Tavily key 导入代理做轮询。

### 配置 FireCrawl Key（可选）

FireCrawl 作为 `web-fetch.sh` 的降级方案，当 Tavily Extract 失败时自动切换。

编辑 `.env`：

```bash
# 单个 Key（脚本直接使用）
FIRECRAWL_API_KEY=fc-你的key

# 或批量配置（import-keys.sh 会取第一个）
FIRECRAWL_API_KEYS=fc-key1,fc-key2
```

FireCrawl 直接调用官方 API（`https://api.firecrawl.dev/v2/scrape`），无需代理服务。

### 一键导入流程总结

```bash
# 1. 编辑 .env，填入 Tavily 和 FireCrawl Key
vim .env

# 2. 如需 legacy grok2api，请改看 docs/grok2api-legacy.md

# 3. 测试
bash scripts/tavily-search.sh --query "test" --max-results 1
bash scripts/grok-search.sh --query "hello" --model "grok-4.1-mini"
bash scripts/web-fetch.sh --url "https://example.com"
```

---

## 使用

```bash
# 加载环境变量
source .env

# Grok / OpenAI Compatible 搜索
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

### OpenClaw / Pi 集成

#### 1. 注册 Skill

```bash
# 创建 skill 目录并软链接 SKILL.md
mkdir -p ~/.openclaw/workspace/skills/ultimate-search
ln -sf $(pwd)/SKILL.md ~/.openclaw/workspace/skills/ultimate-search/SKILL.md

# 将脚本加入 PATH
grep -q 'UltimateSearchSkill/scripts' ~/.bashrc || \
  echo 'export PATH="$HOME/UltimateSearchSkill/scripts:$PATH"' >> ~/.bashrc

# 加载环境变量
grep -q 'UltimateSearchSkill/.env' ~/.bashrc || \
  echo '[ -f ~/UltimateSearchSkill/.env ] && source ~/UltimateSearchSkill/.env' >> ~/.bashrc

source ~/.bashrc
```

OpenClaw 启动时会自动发现 `~/.openclaw/workspace/skills/ultimate-search/SKILL.md`，agent 在需要搜索时会自动加载。

#### 2. 设为默认搜索方式

在 `~/.openclaw/workspace/AGENTS.md` 的 `## Tools` 部分添加路由规则：

```markdown
### 搜索工具

**默认搜索方式是 ultimate-search skill。** 任何需要网络搜索的场景，先加载 `ultimate-search` skill 并按其指引操作。支持以下能力：
- `grok-search.sh` — AI 驱动的深度搜索（Grok 联网）
- `tavily-search.sh` — 结构化搜索结果（带评分排序）
- `dual-search.sh` — 双引擎并行搜索（交叉验证）
- `web-fetch.sh` — 网页内容抓取（Tavily → FireCrawl 降级）
- `web-map.sh` — 站点结构映射
```

如有其他搜索 skill（如 ddg-search、jina-search 等），建议移除以避免冲突。

#### 3. 全局提示词配置（推荐）

SKILL.md 已内置搜索方法论和证据标准。如需在 agent 层面强制执行通用行为规范，可在 `AGENTS.md` 中添加：

```markdown
## 工作准则

### 语言
- 工具交互和内部思考使用英文，输出使用中文
- 使用标准 Markdown 格式，代码块标注语言

### 推理与表达
- 简洁、直接、信息密集：离散项用列表，论证用段落
- 遇到用户逻辑错误时，用证据指出具体问题
- 所有结论必须标注：适用条件、范围边界、已知限制
- 不确定时：先陈述未知及原因，再给出已确认的事实
- 不说废话、不寒暄、不用填充词

### 搜索与证据标准
- 严格区分内部知识与外部知识，不确定时必须搜索验证
- 技术实现即使有内部知识，仍应以最新搜索结果或官方文档为准
- 关键事实需 ≥2 个独立来源支持，单一来源须显式声明
- 来源冲突时：展示双方证据，评估可信度和时效性
- 标注置信度：High（多来源一致）/ Medium（有分歧）/ Low（单一来源或推测）
- 引用格式：`[来源标题](URL)`，严禁编造引用
```

> **提示词层次说明：**
> - **SKILL.md**（Skill 层）：搜索决策流程、工具选择策略、搜索规划框架、证据标准 — 仅在 agent 加载 skill 时生效
> - **AGENTS.md**（全局层）：通用行为规范（语言、推理、搜索标准）— 始终在 agent 上下文中
> - **SOUL.md**（人格层）：agent 的身份和响应风格 — 不建议在此添加工具相关指令

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

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=ckckck/UltimateSearchSkill&type=Date)](https://www.star-history.com/#ckckck/UltimateSearchSkill&Date)
