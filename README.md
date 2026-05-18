# 开发环境（Docker）

> **Ubuntu 24.04 + CUDA 12.8 + PyTorch + Conda + Jupyter + VS Code**

本项目提供一套 **100% 可复现的 Docker 开发环境**，基于 `supervisord` 多服务管理方案，确保持久稳定运行。

---

## 一、环境依赖（宿主机）

**必须**
- Windows 10/11
- WSL2（Ubuntu 24.04）
- Docker Desktop（启用 WSL2 backend）
- NVIDIA 驱动 ≥ 550（支持 CUDA 12.8）

**可选**
- VS Code（Remote - Containers）
- JetBrains Gateway

---

## 二、目录结构

```
.
├── Dockerfile              # 容器镜像定义
├── docker-compose.yml     # 容器编排配置
├── supervisord.conf       # 多服务管理配置
├── .env                   # 环境变量
├── .condarc               # Conda 镜像源配置
├── ubuntu.sources         # APT 镜像源配置
├── install_claude_code.sh # Claude Code 安装脚本
└── run_docker_container.sh # 快速启动脚本
```

---

## 三、核心技术栈

### 系统与运行时
- Ubuntu 24.04（Noble）
- CUDA 12.8
- glibc 2.39

### Python / 包管理
- Python 3.12
- Miniconda
- pip / uv（极速 Python 包管理）
- PyTorch（CUDA 12.8）

### 开发工具
- JupyterLab（端口 5866）
- code-server / VS Code Server（端口 8080）
- SSH 服务（端口 2222）
- 工作目录：宿主机 `/mnt/d` 直接挂载

---

## 四、快速开始

### 1. 克隆 / 进入项目目录

```bash
cd /mnt/d/docker
cp .env.example .env
```

### 2. 配置环境变量

编辑 `.env` 文件：

```env
JUPYTER_PASSWORD=Pass1234
JUPYTER_PORT=5866
VSCODE_PORT=8080
```

> **不要提交 `.env` 到 Git**

### 3. 构建 & 启动容器

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

### 4. 进入容器配置开发环境

```bash
docker compose exec pytorch_dev bash
```

### 5. （可选）配置 Claude Code

如果需要 Claude Code，执行安装脚本：

```bash
/opt/install_claude_code.sh \
  --api-key "your-api-key" \
  --base-url "https://api.minimaxi.com/anthropic" \
  --model "MiniMax-M2.7" \
  --config-only \
  --skip-plugins \
  --skip-mcp

source ~/.bashrc
```

之后使用：

```bash
docker compose exec pytorch_dev claude
```

---

## 五、访问服务

| 服务 | 地址 | 认证方式 |
|------|------|----------|
| JupyterLab | http://localhost:5866 | 密码 `Pass1234` |
| VS Code Server | http://localhost:8080 | 密码 `Pass1234` |
| SSH | localhost:2222 | 密钥 |

---

## 六、多服务管理架构

本项目使用 `supervisord` 作为进程管理器，实现：

- **自动拉起**：任何服务崩溃后自动重启
- **前台运行**：容器永远不会 `Exited`
- **独立日志**：各服务日志分离，便于排查

```
┌─────────────────────────────────────────┐
│           容器 (supervisord)            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  │
│  │  sshd   │  │ jupyter │  │code-srv │  │
│  └─────────┘  └─────────┘  └─────────┘  │
└─────────────────────────────────────────┘
```

### supervisord.conf 核心配置

```ini
[supervisord]
nodaemon=true

[program:sshd]
command=/usr/sbin/sshd -D
autorestart=true

[program:jupyter]
command=jupyter lab --ip=0.0.0.0 --port=5866 ...
autorestart=true

[program:code-server]
command=code-server --bind-addr 0.0.0.0:8080 ...
autorestart=true
```

---

## 七、国内镜像加速

### APT（清华大学）

```text
https://mirrors.tuna.tsinghua.edu.cn/ubuntu
```

### PyPI（清华大学）

```text
https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
```

### Conda（清华大学 + 教育网）

```text
https://mirrors.tuna.tsinghua.edu.cn/anaconda/
https://mirrors.cernet.edu.cn/anaconda-extra/cloud/nvidia
```

---

## 八、常见问题（FAQ）

### Q1：如何进入容器？

```bash
docker compose exec pytorch_dev bash
```

### Q2：如何验证 CUDA 是否正常？

```bash
nvidia-smi
python -c "import torch; print(torch.cuda.is_available())"
```

### Q3：如何查看服务状态？

```bash
docker compose exec pytorch_dev supervisorctl status
```

### Q4：某个服务挂了怎么办？

`supervisord` 会自动拉起。如需手动重启：

```bash
docker compose exec pytorch_dev supervisorctl restart jupyter
```

### Q5：为什么用 supervisord？

- 避免 bash 脚本前台进程退出导致容器终止
- 避免多服务"打架"
- 确保 sshd / Jupyter / code-server 全部持久运行

---

## 九、维护与更新

### 重建镜像

```bash
docker compose build --no-cache
```

### 清理无用资源

```bash
docker system prune -a
```

### 查看日志

```bash
docker compose exec pytorch_dev tail -f /var/log/supervisor/jupyter.log
```

---

## 十、许可证

本项目配置采用 **MIT License**。
第三方软件（CUDA / Conda / PyTorch）请遵守各自许可证。

---

*本 README 基于 supervisord 多服务架构文档自动生成*