# ARTEX AI 部署仓库

ARTEX AI 系统的自动化部署脚本与容器编排配置。

## 文件说明

- `deploy_artex.sh` — 一键部署与就绪验证脚本（自动生成配置与随机凭证、启动容器群、端口健康检查）
- `artex_deployment/docker-compose.yml` — Compose 编排（postgres:15 + artex-app，内外双网络隔离）
- `artex_deployment/config/config.yaml` — 应用配置（human_in_the_loop 模式、安全扫描限制项）
- `artex_deployment/.env.example` — 环境变量模板（复制为 `.env` 后填写，真实 `.env` 已被 .gitignore 排除）

## 使用方法

```bash
chmod +x deploy_artex.sh
./deploy_artex.sh
```

脚本完成后访问控制台 `http://127.0.0.1:8080`，并在 `.env` 中填入有效 `LLM_API_KEY` 后重启容器。

## 前置条件 / 已知问题

1. 脚本目标环境为 Linux（脚本头部标注 Tencent WorkBuddy / Local Linux Environment）；Windows 宿主机需 Docker Desktop 且启用 WSL2。
2. **`autumn27/artex:latest` 镜像目前在 Docker Hub 上不存在（查询返回 404）**，部署前需替换为有效镜像名或从源码构建。
3. 需要 `openssl`、`curl`，端口 8080 未被占用。
