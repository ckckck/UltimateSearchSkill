#!/usr/bin/env bash
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

cd "$PROJECT_DIR"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  UltimateSearchSkill 部署脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查依赖
for cmd in docker curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        error "$cmd 未安装，请先安装"
    fi
    ok "$cmd 已安装"
done

if docker compose version &>/dev/null; then
    COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
else
    error "docker compose 未安装"
fi
ok "docker compose 可用"

# 配置文件
if [ ! -f .env ]; then
    cp .env.example .env
    warn ".env 已从模板创建，请编辑 .env 填入实际配置"
    warn "特别注意核对 GROK2API_APP_KEY；GROK_API_KEY 仅在 grok2api 配置了 app.api_key 时才需要"
fi

# 加载环境变量
set -a; source .env; set +a

# 创建数据目录
mkdir -p data/grok2api/logs data/tavily-proxy

# 拉取镜像并启动
info "拉取 Docker 镜像..."
$COMPOSE pull

info "启动服务..."
$COMPOSE up -d

# 等待服务就绪
info "等待服务就绪..."
for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:${GROK2API_PORT:-8100}/" >/dev/null 2>&1; then
        ok "grok2api 就绪"
        break
    fi
    [ "$i" -eq 30 ] && warn "grok2api 30秒内未就绪，请检查日志: $COMPOSE logs grok2api"
    sleep 1
done

for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:${TAVILY_PROXY_PORT:-8200}/healthz" >/dev/null 2>&1; then
        ok "TavilyProxyManager 就绪"
        break
    fi
    [ "$i" -eq 30 ] && warn "TavilyProxyManager 30秒内未就绪，请检查日志: $COMPOSE logs tavily-proxy"
    sleep 1
done

# 获取 TavilyProxyManager Master Key
echo ""
info "TavilyProxyManager Master Key："
MASTER_KEY=$($COMPOSE logs tavily-proxy 2>&1 | grep -oP 'key=\K\S+' | head -1 || true)
if [ -n "$MASTER_KEY" ]; then
    echo -e "  ${GREEN}$MASTER_KEY${NC}"
    echo ""
    warn "请将此 Master Key 填入 .env 的 TAVILY_MASTER_KEY"
else
    warn "未能自动获取 Master Key，请手动查看: $COMPOSE logs tavily-proxy | grep 'master key'"
fi

# 后续步骤
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  部署完成！后续步骤：${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "1. 修改 .env 中的密码和 Key"
echo "2. 访问 grok2api 管理面板添加 Grok Token："
echo "   ssh -L 8100:127.0.0.1:${GROK2API_PORT:-8100} 你的服务器"
echo "   然后浏览器打开 http://localhost:8100/admin"
echo ""
echo "3. 访问 TavilyProxyManager 添加 Tavily Key："
echo "   ssh -L 8200:127.0.0.1:${TAVILY_PROXY_PORT:-8200} 你的服务器"
echo "   然后浏览器打开 http://localhost:8200"
echo ""
echo "4. 将脚本加入 PATH："
echo "   echo 'export PATH=\"$PROJECT_DIR/scripts:\$PATH\"' >> ~/.bashrc"
echo "   source ~/.bashrc"
echo ""
echo "5. 加载环境变量（每次使用前）："
echo "   source $PROJECT_DIR/.env"
