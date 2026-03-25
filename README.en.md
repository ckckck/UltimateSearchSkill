# UltimateSearchSkill

<p align="center"><a href="./README.md">中文</a> | <a href="./README.en.md">English</a></p>

A dual-engine web search capability module for [OpenClaw](https://openclaw.ai/) / [Pi](https://github.com/badlogic/pi-mono/) AI agents. It combines Grok AI and Tavily for cross-verification, is implemented in pure Shell, and has zero MCP dependency.

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-0f766e?style=flat-square" />
  <img alt="Shell" src="https://img.shields.io/badge/Shell-Bash-0ea5e9?style=flat-square" />
  <img alt="Docker" src="https://img.shields.io/badge/Infra-Docker-2563eb?style=flat-square" />
  <img alt="OpenAI Compatible" src="https://img.shields.io/badge/Search-OpenAI%20Compatible-f59e0b?style=flat-square" />
  <img alt="Tavily" src="https://img.shields.io/badge/Search-Tavily-f97316?style=flat-square" />
  <img alt="FireCrawl" src="https://img.shields.io/badge/Fallback-FireCrawl-f43f5e?style=flat-square" />
</p>

```text
User request → Agent (guided by SKILL.md)
                ├─ grok-search.sh  → Grok (recommended) via OpenAI Compatible API
                │                   ├─ Known URL auto-enhancement (xAI / OpenRouter)
                │                   └─ Compatible with other OpenAI Compatible models / proxies
                ├─ grok-search.sh  → grok2api (legacy/experimental)
                ├─ tavily-search.sh → TavilyProxyManager (multi-key pool) → Tavily search
                ├─ web-fetch.sh    → Tavily Extract → FireCrawl Scrape (auto fallback)
                ├─ web-map.sh      → TavilyProxyManager → Tavily Map (site mapping)
                └─ dual-search.sh  → Parallel execution for cross-verification
```

## Features

- **Dual-engine search**: Grok-first search plus Tavily structured search with cross-source verification.
- **Multi-account aggregation**: Tavily uses TavilyProxyManager to pool multiple accounts; `grok2api` aggregation remains available only as a legacy option.
- **FireCrawl fallback**: `web-fetch` uses a three-step fallback chain: Tavily Extract → FireCrawl Scrape → error.
- **Zero MCP dependency**: Pure Shell scripts plus skill instructions, invoked natively through Bash.
- **Security hardening**: Ports bind to `127.0.0.1`, APIs are authenticated, and admin panels are accessed through SSH tunnels.
- **Search methodology**: Built-in GrokSearch MCP-inspired planning framework and evidence standards.

<div align="center">
  <table>
    <tr>
      <td width="88" align="center" valign="middle">
        <a href="https://www.popai.pro">
          <img src="https://popaife.s3.ap-southeast-1.amazonaws.com/other/logo_siderbar.svg" alt="PopAi logo" width="56" />
        </a>
      </td>
      <td valign="middle">
        <strong>Recommended Combo: UltimateSearchSkill × PopAi</strong><br/>
        Step up your workflow: Turn results into PPTs with PopAi.<br/>
        <a href="https://www.popai.pro">Visit PopAi</a>
      </td>
    </tr>
  </table>
</div>

## Quick Start

### Prerequisites

- Docker + Docker Compose
- `curl`, `jq`
- API credentials required to access Grok or another compatible model through an OpenAI Compatible API
- Tavily API Key (free tier includes 1000 searches/month): https://www.tavily.com/
- FireCrawl API Key (optional, used as the `web-fetch` fallback): https://www.firecrawl.dev/

### Installation

```bash
git clone https://github.com/your-username/UltimateSearchSkill.git
cd UltimateSearchSkill

# Copy the environment template
cp .env.example .env
```

### Recommended Grok Search Configuration

`grok-search.sh` now primarily recommends using Grok through an `OpenAI Compatible` configuration. The same config block can also work with other OpenAI Compatible models or proxies:

- `OPENAI_COMPATIBLE_BASE_URL`
- `OPENAI_COMPATIBLE_API_KEY`
- `OPENAI_COMPATIBLE_MODEL`
- `OPENAI_COMPATIBLE_SEARCH_MODE` (optional)

Default behavior:

- Grok is still the recommended model, and the recommended connection path is OpenAI Compatible API instead of the older webpage reverse-proxy chain.
- Known URL auto-enhancement currently supports `https://api.x.ai/v1` and `https://openrouter.ai/api/v1`.
- If known URL auto-enhancement fails, the script only falls back conservatively when standard compatible chat is confirmed to work, and returns `degraded_from` plus `realtime_warning` in the output JSON.
- Unknown URLs are not auto-detected and default to standard compatible chat only.
- For other unknown OpenAI Compatible backends, you can manually set `OPENAI_COMPATIBLE_SEARCH_MODE`; manual mode failures do not silently downgrade.

Example:

```bash
OPENAI_COMPATIBLE_BASE_URL=https://openrouter.ai/api/v1
OPENAI_COMPATIBLE_API_KEY=your-key
OPENAI_COMPATIBLE_MODEL=x-ai/grok-4.1-fast
OPENAI_COMPATIBLE_SEARCH_MODE=
```

Manual override example:

```bash
OPENAI_COMPATIBLE_BASE_URL=https://your-proxy.example.com/v1
OPENAI_COMPATIBLE_API_KEY=your-key
OPENAI_COMPATIBLE_MODEL=your-model
OPENAI_COMPATIBLE_SEARCH_MODE=openrouter_web
```

> `grok2api` is still available, but only as a legacy/experimental compatibility path. The recommended approach is using Grok through an OpenAI Compatible API.

Script output is normalized as JSON. Core fields include `content`, `model`, `usage`, and `mode`; enhanced modes also include `citations` when available.

## Legacy grok2api

If you are still using `grok2api` or the older Grok webpage reverse-proxy chain, note that this is now a **legacy/experimental** setup and is no longer part of the main recommended README path.

- Legacy credential boundaries, the correct meaning of `GROK_API_KEY`, and how to obtain SSO tokens
- `grok2api` token import, admin panel usage, FlareSolverr configuration, and Cloudflare troubleshooting
- Legacy one-shot import flow and deployment notes

See the dedicated document instead: [docs/grok2api-legacy.md](docs/grok2api-legacy.md)

---

### Import Tavily API Keys

**Option 1: Put them in `.env` and use `import-keys.sh`**

Edit `.env` and set `TAVILY_API_KEYS` (comma-separated for multiple keys):

```bash
TAVILY_API_KEYS=tvly-xxx111,tvly-xxx222,tvly-xxx333
```

Then run:

```bash
bash scripts/import-keys.sh
```

**Option 2: Import manually via API**

```bash
# Get the master key first
docker compose logs tavily-proxy | grep "master key"

# Add a key
curl -X POST http://127.0.0.1:8200/api/keys \
  -H "Authorization: Bearer yourMasterKey" \
  -H "Content-Type: application/json" \
  -d '{"key": "tvly-your-key", "alias": "Account A", "total_quota": 1000}'
```

**Option 3: Use the web admin panel**

```bash
ssh -L 8200:127.0.0.1:8200 your-server
# Open http://localhost:8200 in your browser
```

> TavilyProxyManager generates a master key automatically on first startup, and `import-keys.sh` can fetch and update it in `.env` automatically.

When scripts call TavilyProxyManager, they use `TAVILY_MASTER_KEY` from `.env`. `TAVILY_API_KEYS` is only used to import the real Tavily keys into the proxy rotation pool.

### Configure FireCrawl Key (Optional)

FireCrawl is used as the fallback path in `web-fetch.sh` whenever Tavily Extract fails.

Edit `.env`:

```bash
# Single key (used directly by the script)
FIRECRAWL_API_KEY=fc-your-key

# Or multiple keys (`import-keys.sh` uses the first one)
FIRECRAWL_API_KEYS=fc-key1,fc-key2
```

FireCrawl calls the official API directly (`https://api.firecrawl.dev/v2/scrape`) and does not require a proxy service.

### One-Shot Import Summary

```bash
# 1. Edit .env and fill in Tavily and FireCrawl keys
vim .env

# 2. If you need legacy grok2api, see docs/grok2api-legacy.md

# 3. Test
bash scripts/tavily-search.sh --query "test" --max-results 1
bash scripts/grok-search.sh --query "hello" --model "grok-4.1-mini"
bash scripts/web-fetch.sh --url "https://example.com"
```

---

## Usage

```bash
# Load environment variables
source .env

# Grok / OpenAI Compatible search
grok-search.sh --query "Latest FastAPI features"

# Tavily search
tavily-search.sh --query "Python web frameworks comparison" --depth advanced

# Dual-engine search
dual-search.sh --query "Rust vs Go 2026"

# Fetch webpage content (Tavily → FireCrawl auto fallback)
web-fetch.sh --url "https://docs.python.org/3/whatsnew/3.13.html"

# Site mapping
web-map.sh --url "https://docs.tavily.com" --depth 2
```

## Register As A Skill

### OpenClaw / Pi Integration

#### 1. Register the skill

```bash
# Create the skill directory and symlink SKILL.md
mkdir -p ~/.openclaw/workspace/skills/ultimate-search
ln -sf $(pwd)/SKILL.md ~/.openclaw/workspace/skills/ultimate-search/SKILL.md

# Add scripts to PATH
grep -q 'UltimateSearchSkill/scripts' ~/.bashrc || \
  echo 'export PATH="$HOME/UltimateSearchSkill/scripts:$PATH"' >> ~/.bashrc

# Load environment variables
grep -q 'UltimateSearchSkill/.env' ~/.bashrc || \
  echo '[ -f ~/UltimateSearchSkill/.env ] && source ~/UltimateSearchSkill/.env' >> ~/.bashrc

source ~/.bashrc
```

OpenClaw automatically discovers `~/.openclaw/workspace/skills/ultimate-search/SKILL.md` on startup, and the agent can load it when search is needed.

#### 2. Set it as the default search path

Add the following routing rule under `## Tools` in `~/.openclaw/workspace/AGENTS.md`:

```markdown
### Search Tools

**The default search method is the ultimate-search skill.** For any scenario requiring web search, load `ultimate-search` first and follow its instructions. It supports:
- `grok-search.sh` — AI-driven deep search with Grok web access
- `tavily-search.sh` — structured search results with ranking scores
- `dual-search.sh` — parallel dual-engine search for cross-verification
- `web-fetch.sh` — webpage content extraction with Tavily → FireCrawl fallback
- `web-map.sh` — site structure mapping
```

If you have other search skills such as ddg-search or jina-search, removing them is recommended to avoid routing conflicts.

#### 3. Global prompt configuration (recommended)

`SKILL.md` already includes the search methodology and evidence standards. If you also want to enforce generic behavior at the agent layer, you can add this to `AGENTS.md`:

```markdown
## Working Principles

### Language
- Use English for tool interaction and internal reasoning; output in Chinese
- Use standard Markdown and language-tagged code blocks

### Reasoning and expression
- Be concise, direct, and information-dense
- Use evidence to point out logical errors in user assumptions
- State scope, boundary conditions, and limitations for every conclusion
- If uncertain, state the uncertainty and its reason before confirmed facts
- Avoid filler and small talk

### Search and evidence standards
- Strictly distinguish internal knowledge from external knowledge; search when uncertain
- Even for technical implementation details you already know, prefer fresh search results or official docs
- Key facts should be backed by at least two independent sources; if only one source is available, say so explicitly
- When sources conflict, present both sides and evaluate credibility and freshness
- Mark confidence as High / Medium / Low
- Use the citation format `[Title](URL)` and never fabricate references
```

> **Prompt hierarchy note:**
> - **SKILL.md** (skill layer): search decision flow, tool selection strategy, planning framework, evidence standards — only active when the skill is loaded
> - **AGENTS.md** (global layer): generic behavior rules such as language, reasoning, and evidence standards — always active in the agent context
> - **SOUL.md** (persona layer): identity and tone — not recommended for tool-related instructions

## Architecture

See [docs/architecture.md](docs/architecture.md).

## Security Notes

- All ports bind to `127.0.0.1`, so they are not directly exposed externally
- `export_sso.txt`, `.env`, and `data/` are in `.gitignore` and will not be committed
- grok2api uses the default admin password `grok2api`; changing `app_key` in `data/grok2api/config.toml` is recommended
- TavilyProxyManager uses a randomly generated master key
- Remote administration is done via SSH tunnel
- See the [security hardening guide](docs/architecture.md#安全加固) for more details

## Acknowledgements

- [GrokSearch MCP](https://github.com/GuDaStudio/GrokSearch) — inspiration for search methodology and prompting
- [grok2api](https://github.com/chenyme/grok2api) — Grok token aggregation service
- [TavilyProxyManager](https://github.com/xuncv/TavilyProxyManager) — Tavily key aggregation service
- [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) — automated Cloudflare bypass
- [FireCrawl](https://www.firecrawl.dev/) — fallback web scraping solution

## License

MIT

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=ckckck/UltimateSearchSkill&type=Date)](https://www.star-history.com/#ckckck/UltimateSearchSkill&Date)
