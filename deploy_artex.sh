#!/usr/bin/env bash
# ==============================================================================
# Script Name : deploy_artex.sh
# Description : Automated Deployment & Verification Script for ARTEX AI System
# Target Agent: Tencent WorkBuddy / Local Linux Environment
# ==============================================================================

set -euo pipefail

TARGET_DIR="artex_deployment"
PORT=8080

echo "======================================================================"
echo " [ARTEX AI] 自动化环境部署与就绪验证流程启动"
echo "======================================================================"

# 1. 宿主机基础环境与依赖探测
echo "[Step 1/5] 检查 Docker 与环境依赖..."
if ! command -v docker &> /dev/null; then
    echo "[-] 错误: 未检测到 Docker，请先安装 Docker Engine。"
    exit 1
fi

if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "[-] 错误: 未检测到 Docker Compose 插件。"
    exit 1
fi

if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "[!] 警告: 本地端口 ${PORT} 已被占用，请注意冲突排查。"
fi

# 2. 初始化安全工作区目录
echo "[Step 2/5] 创建项目工作区: ./${TARGET_DIR}"
mkdir -p "${TARGET_DIR}/data/postgres"
mkdir -p "${TARGET_DIR}/data/logs"
mkdir -p "${TARGET_DIR}/config"

cd "${TARGET_DIR}"

# 3. 生成环境变量与强随机密码
echo "[Step 3/5] 生成环境配置与安全凭证..."
RANDOM_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 20)

cat <<EOF > .env
COMPOSE_PROJECT_NAME=artex_cluster
POSTGRES_DB=artex_db
POSTGRES_USER=artex_admin
POSTGRES_PASSWORD=${RANDOM_PASS}
DB_HOST=artex-db
DB_PORT=5432
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=claude-3-5-sonnet-20241022
LLM_API_KEY=sk-placeholder-please-update-with-your-key
ARTEX_RUN_MODE=human_in_the_loop
EOF

cat <<'EOF' > config/config.yaml
server:
  host: "0.0.0.0"
  port: 8080
  read_timeout: 60
  write_timeout: 60

database:
  driver: "postgres"
  max_open_conns: 25
  max_idle_conns: 10
  conn_max_lifetime: 300

security:
  custom_header_key: "X-Security-Scan"
  custom_header_value: "ARTEX-Audit-Verified"
  rate_limit_per_second: 15
  max_concurrency: 5
  enable_credential_masking: true

agent:
  mode: "human_in_the_loop"
  max_exploration_steps: 40
  reconnaissance:
    port_scan_range: "top-1000"
    enable_fingerprint: true
    dir_depth: 3
  vulnerability:
    safe_poc_only: true
    disable_dos_payloads: true
    disable_data_dumping: true
EOF

cat <<'EOF' > docker-compose.yml
version: '3.8'

services:
  artex-db:
    image: postgres:15-alpine
    container_name: artex_postgres_instance
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    networks:
      - artex-internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 5

  artex-app:
    image: autumn27/artex:latest
    container_name: artex_core_instance
    restart: unless-stopped
    depends_on:
      artex-db:
        condition: service_healthy
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      - DB_HOST=artex-db
      - DB_PORT=${DB_PORT}
      - DB_USER=${POSTGRES_USER}
      - DB_PASSWORD=${POSTGRES_PASSWORD}
      - DB_NAME=${POSTGRES_DB}
      - LLM_BASE_URL=${LLM_BASE_URL}
      - LLM_API_KEY=${LLM_API_KEY}
      - LLM_MODEL=${LLM_MODEL}
      - ARTEX_MODE=${ARTEX_RUN_MODE}
    volumes:
      - ./config/config.yaml:/app/config.yaml:ro
      - ./data/logs:/app/logs
    networks:
      - artex-internal
      - artex-egress

networks:
  artex-internal:
    internal: true
  artex-egress:
    driver: bridge
EOF

# 4. 容器编排启动与存活探测
echo "[Step 4/5] 启动 Docker 容器群..."
docker compose up -d

echo "[Step 5/5] 等待服务端口响应..."
ATTEMPTS=0
MAX_ATTEMPTS=15
SUCCESS=0

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    ATTEMPTS=$((ATTEMPTS+1))
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/ || true)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "[+] ARTEX 服务探测成功 (HTTP $HTTP_CODE)!"
        SUCCESS=1
        break
    else
        echo "    等待就绪 ($ATTEMPTS/$MAX_ATTEMPTS)..."
        sleep 3
    fi
done

cat <<EOF > DEPLOYMENT_REPORT.md
# ARTEX AI 系统部署交付报告
- Web 控制台: http://127.0.0.1:8080
- 数据库: artex-db:5432 (用户: ${POSTGRES_USER})
- 配置文件: ./config/config.yaml
- 后续步骤: 请在 .env 文件中填入有效 LLM_API_KEY 后重启服务容器。
EOF

echo "======================================================================"
echo "[+] 部署脚本执行完毕！"
echo "    控制台访问地址: http://127.0.0.1:8080"
echo "    交付报告文件: ./${TARGET_DIR}/DEPLOYMENT_REPORT.md"
echo "======================================================================"
