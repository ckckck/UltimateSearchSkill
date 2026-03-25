# UltimateSearchSkill 架构说明

## 设计理念

### 为什么不用 MCP？

OpenClaw 的底层 agent Pi 的设计哲学是：**agent 通过 Bash 执行代码来扩展自己**，而非通过 MCP 加载外部工具。MCP 工具需要注入到模型的系统上下文中，增加 token 消耗，且不支持热重载。

因此我们选择了 **Skill + Shell 脚本** 的方案：
- SKILL.md 引导 agent 的搜索决策和方法论
- Shell 脚本通过 Bash 工具直接调用
- 无额外进程、无上下文开销

### 三层架构

```
┌─────────────────────────────────────────────────┐
│  Layer 1: Skill 层 (SKILL.md)                   │
│  搜索方法论 | 决策流程 | 证据标准 | 输出规范       │
├─────────────────────────────────────────────────┤
│  Layer 2: 脚本层 (scripts/)                      │
│  grok-search | tavily-search | web-fetch        │
│  web-map | dual-search                          │
├─────────────────────────────────────────────────┤
│  Layer 3: 后端层 / 基础设施层                      │
│  OpenAI Compatible | grok2api(legacy) | Tavily  │
└─────────────────────────────────────────────────┘
```

## 数据流

### Grok 搜索流

```
Agent → Bash → grok-search.sh
                 → 解析统一 OpenAI Compatible 配置
                      ├─ 已知 URL → 自动增强搜索
                      │    ├─ xAI Responses API + web_search
                      │    └─ OpenRouter Responses API + web plugin
                      │    └─ 若增强失败且普通聊天可用 → 保守降级到 chat/completions
                      ├─ 未知 URL → 普通兼容聊天模式
                      └─ grok2api (legacy/experimental)
                           → Grok Web (x.ai) 执行联网搜索
```

关键特点：搜索策略 prompt 与后端能力解耦。`grok-search.sh` 保留统一的搜索方法论、时间注入和平台聚焦逻辑；已知兼容后端自动增强，增强失败时只允许向普通兼容聊天做保守降级；手动增强模式失败不隐式切换；统一输出结构可附带 `citations`、`degraded_from` 与 `realtime_warning`；`grok2api` 仅作为 legacy/experimental 兼容路径保留。

### Tavily 搜索流

```
Agent → Bash → tavily-search.sh / web-fetch.sh / web-map.sh
                 → curl POST TavilyProxyManager:8200/search|extract|map
                      → TavilyProxyManager 选择最优 Key
                           → Tavily API (tavily.com)
                                → 返回结构化搜索/抓取结果
```

关键特点：Tavily 提供专业的搜索 API，支持结构化结果、评分排序、时间过滤。TavilyProxyManager 负责多 Key 聚合、余额优先调度、自动故障切换。

### 双引擎搜索流

```
Agent → Bash → dual-search.sh
                 ├─ (后台) grok-search.sh → OpenAI Compatible / grok2api
                 └─ (后台) tavily-search.sh → TavilyProxy → Tavily
                 → wait (等待两者完成)
                 → jq 合并结果
                 → 输出 {"grok": {...}, "tavily": {...}}
```

## 与 GrokSearch MCP 的对比

| 维度 | GrokSearch MCP | UltimateSearchSkill |
|------|---------------|---------------------|
| 运行时 | 独立 Python MCP 进程 | 无额外进程，Shell 脚本 |
| 安装 | Python + uvx + FastMCP | Docker + bash |
| Agent 集成 | 需要 MCP 客户端支持 | Bash 原生调用 |
| Token 管理 | 单个 Key | 多 Key 聚合（grok2api） |
| 搜索规划 | MCP tool（search_planning） | Skill 指令引导 agent 自行规划 |
| 上下文开销 | 工具定义占用 context | 仅 Skill 指令，按需加载 |
| 维护 | 依赖上游更新 | 自己掌控 |

## 安全加固

### 网络隔离

所有 Docker 端口绑定到 `127.0.0.1`，不暴露到外部网络：

```yaml
ports:
  - "127.0.0.1:8100:8000"   # grok2api
  - "127.0.0.1:8200:8080"   # TavilyProxyManager
```

### 认证

- **grok2api**：必须配置 `api_key`（默认为空=无认证，极度危险）
- **TavilyProxyManager**：自动生成随机 Master Key

### 远程管理

通过 SSH 端口转发安全访问管理面板：

```bash
# 转发管理面板端口
ssh -L 8100:127.0.0.1:8100 -L 8200:127.0.0.1:8200 用户@服务器

# 浏览器访问
# grok2api: http://localhost:8100/admin
# TavilyProxy: http://localhost:8200
```

### 密钥管理

- 所有密钥存储在 `.env` 文件中（已加入 .gitignore）
- grok2api Token 存储在 `data/grok2api/` 目录（已加入 .gitignore）
- Tavily Key 存储在 `data/tavily-proxy/proxy.db`（已加入 .gitignore）
