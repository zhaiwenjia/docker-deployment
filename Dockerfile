FROM nvidia/cuda:12.8.0-base-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ========== APT 源 ==========
RUN rm -f /etc/apt/sources.list && \
    rm -f /etc/apt/sources.list.d/*.sources
COPY ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources

# ========== 基础 + 编译工具 ==========
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip \
    curl git \
    ca-certificates gnupg wget \
    build-essential gcc g++ clang make cmake ninja-build \
    vim openssh-client openssh-server supervisor \
    && ssh-keygen -A \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========== pip 清华源 ==========
RUN pip config set global.index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple

# ========== uv ==========
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# ========== Node.js ==========
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ========== Miniconda ==========
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/miniconda && \
    rm /tmp/miniconda.sh

ENV PATH="/opt/miniconda/bin:$PATH"
COPY .condarc /root/.condarc
RUN conda init bash || true

# ========== JupyterLab + code-server ==========
RUN pip install jupyterlab && \
    curl -fsSL https://code-server.dev/install.sh | sh

# ========== Claude Code 安装脚本 ==========
COPY install_claude_code.sh /opt/install_claude_code.sh
RUN chmod +x /opt/install_claude_code.sh

# ========== supervisord ==========
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

WORKDIR /mnt/d
CMD ["/usr/bin/supervisord", "-n"]
