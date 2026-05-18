#!/bin/bash
#
# Claude Code 一键安装/配置脚本 (修复版)
# SkillEvolve-RL v24.1
#
# 功能：
#   1. 安装 Claude Code CLI（如未安装）
#   2. 配置 API 密钥和端点
#   3. 配置 MCP 服务器
#   4. 启用必要的插件
#   5. 配置权限和语言设置
#   6. 设置项目特定的 CLAUDE.md
#
# 使用方法：
#   chmod +x install_claude_code.sh
#   ./install_claude_code.sh [OPTIONS]
#
# 选项：
#   --api-key KEY        设置 API 密钥（必填）
#   --base-url URL       设置 API 基础 URL（可选）
#   --model MODEL        设置默认模型（可选）
#   --project-only       仅配置当前项目，不修改全局设置
#   --config-only        仅配置 API 设置，不安装 Claude Code CLI（服务器环境）
#   --skip-plugins       跳过插件安装
#   --skip-mcp           跳过 MCP 服务器配置
#   --uninstall          卸载 Claude Code
#   --help               显示帮助信息
#

set -e

# ============================================================================
# 配置变量（可根据需要修改默认值）
# ============================================================================

# API 配置
DEFAULT_BASE_URL="https://api.minimaxi.com/anthropic"
DEFAULT_MODEL="MiniMax-M2.7"

# Claude Code 配置目录
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# 插件列表（仅包含官方市场确认存在的插件）
ENABLED_PLUGINS=(
    "commit-commands@claude-plugins-official"
    "frontend-design@claude-plugins-official"
    "agent-sdk-dev@claude-plugins-official"
)

# ============================================================================
# 颜色输出
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# 帮助信息
# ============================================================================

show_help() {
    cat << EOF
Claude Code 一键安装/配置脚本

使用方法：
    $0 [OPTIONS]

选项：
    --api-key KEY        设置 API 密钥（必填）
    --base-url URL       设置 API 基础 URL（默认: ${DEFAULT_BASE_URL}）
    --model MODEL        设置默认模型（默认: ${DEFAULT_MODEL}）
    --project-only       仅配置当前项目，不修改全局设置
    --config-only        仅配置 API 设置，不安装 Claude Code CLI（服务器环境）
    --skip-plugins       跳过插件安装
    --skip-mcp           跳过 MCP 服务器配置
    --uninstall          卸载 Claude Code
    --help               显示此帮助信息

示例：
    # 使用 MiniMax API
    $0 --api-key your-api-key --base-url https://api.minimaxi.com/anthropic

    # 仅配置当前项目
    $0 --api-key your-api-key --project-only

    # 服务器环境仅配置 API（不安装 CLI）
    $0 --api-key your-api-key --config-only

    # 使用 Anthropic 官方 API
    $0 --api-key your-api-key

环境变量：
    ANTHROPIC_API_KEY   API 密钥（可替代 --api-key）
    ANTHROPIC_BASE_URL  API 基础 URL（可替代 --base-url）

EOF
}

# ============================================================================
# 解析命令行参数
# ============================================================================

parse_args() {
    API_KEY=""
    BASE_URL=""
    MODEL=""
    PROJECT_ONLY=false
    CONFIG_ONLY=false
    SKIP_PLUGINS=false
    SKIP_MCP=false
    UNINSTALL=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --api-key)
                API_KEY="$2"
                shift 2
                ;;
            --base-url)
                BASE_URL="$2"
                shift 2
                ;;
            --model)
                MODEL="$2"
                shift 2
                ;;
            --project-only)
                PROJECT_ONLY=true
                shift
                ;;
            --config-only)
                CONFIG_ONLY=true
                shift
                ;;
            --skip-plugins)
                SKIP_PLUGINS=true
                shift
                ;;
            --skip-mcp)
                SKIP_MCP=true
                shift
                ;;
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 环境变量覆盖
    : "${API_KEY:=${ANTHROPIC_API_KEY}}"
    : "${BASE_URL:=${ANTHROPIC_BASE_URL}}"
    : "${MODEL:=${DEFAULT_MODEL}}"

    # 检查必填参数
    if [[ -z "$API_KEY" ]]; then
        error "API 密钥未提供，请使用 --api-key 或设置 ANTHROPIC_API_KEY"
        exit 1
    fi
}

# ============================================================================
# 1. 检查和安装 Claude Code
# ============================================================================

check_claude_installed() {
    if command -v claude &> /dev/null; then
        info "Claude Code 已安装: $(claude --version 2>/dev/null || echo 'version unknown')"
        return 0
    else
        return 1
    fi
}

install_nodejs() {
    # 检测 Node.js 版本
    local node_version=""
    if command -v node &> /dev/null; then
        node_version=$(node --version 2>/dev/null | sed 's/v//')
        local major_version=$(echo "$node_version" | cut -d. -f1)
        if [[ "$major_version" -ge 14 ]]; then
            info "Node.js 已安装: v${node_version}"
            return 0
        else
            warn "Node.js 版本过低: v${node_version}，需要 v14+"
        fi
    fi

    info "正在安装 Node.js..."

    local os_type="$(uname -s)"
    local dist_type=""
    local dist_version=""

    # 检测 Linux 发行版
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        dist_type="$ID"
        dist_version="$VERSION_ID"
    fi

    # 判断是否有 root 权限
    local use_sudo=""
    if [[ "$EUID" -eq 0 ]]; then
        use_sudo=""
    elif sudo -n true 2>/dev/null; then
        use_sudo="sudo"
    else
        use_sudo="sudo"
    fi

    # Ubuntu / Debian
    if command -v apt-get &> /dev/null; then
        info "检测到 Debian/Ubuntu 系统 (${dist_type} ${dist_version})..."
        info "安装基础依赖..."

        # 安装基础依赖
        $use_sudo apt-get update
        $use_sudo apt-get install -y curl ca-certificates gnupg apt-transport-https wget

        # Ubuntu 20.04+: 可以直接安装 nodejs
        if [[ "$dist_type" == "ubuntu" ]] && [[ "${dist_version%%.*}" -ge 20 ]]; then
            info "使用 apt 安装 Node.js 20.x..."
            # 添加 NodeSource 仓库
            curl -fsSL https://deb.nodesource.com/setup_20.x | $use_sudo bash -
            $use_sudo apt-get install -y nodejs
        elif [[ "$dist_type" == "debian" ]] || [[ "$dist_type" == "ubuntu" ]]; then
            # 对于 Debian 或旧版 Ubuntu，使用 NodeSource
            info "使用 NodeSource 安装 Node.js 20.x..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | $use_sudo bash - || {
                # 如果 NodeSource 失败，尝试直接安装
                warn "NodeSource 安装失败，尝试直接安装..."
                $use_sudo apt-get install -y nodejs npm
            }
            $use_sudo apt-get install -y nodejs
        else
            # 其他 Debian 系发行版
            info "使用 NodeSource 安装 Node.js 20.x..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | $use_sudo bash -
            $use_sudo apt-get install -y nodejs
        fi

    # RHEL / CentOS / AlmaLinux / Rocky
    elif command -v yum &> /dev/null; then
        info "检测到 RHEL/CentOS 系统..."
        info "使用 NodeSource 安装 Node.js 20.x..."
        $use_sudo yum install -y curl
        curl -fsSL https://deb.nodesource.com/setup_20.x | $use_sudo bash -
        $use_sudo yum install -y nodejs

    # Fedora
    elif command -v dnf &> /dev/null; then
        info "检测到 Fedora 系统..."
        info "使用 NodeSource 安装 Node.js 20.x..."
        $use_sudo dnf install -y curl
        curl -fsSL https://deb.nodesource.com/setup_20.x | $use_sudo bash -
        $use_sudo dnf install -y nodejs

    # Alpine
    elif command -v apk &> /dev/null; then
        info "检测到 Alpine Linux 系统..."
        info "使用 apk 安装 Node.js..."
        $use_sudo apk add --no-cache nodejs npm

    # 其他 Linux 发行版，尝试通用方法
    elif [[ "$os_type" == "Linux" ]]; then
        info "检测到未知 Linux 发行版，尝试通用安装方法..."
        if command -v pacman &> /dev/null; then
            $use_sudo pacman -Sy nodejs npm
        elif command -v zypper &> /dev/null; then
            $use_sudo zypper install -y nodejs npm
        else
            # 最后尝试从官方二进制安装
            info "尝试从官方二进制安装 Node.js 20.x..."
            local node_tar="/tmp/node-v20.tar.xz"
            curl -fsSL https://nodejs.org/dist/v20.x/node-v20-linux-x64.tar.xz -o "$node_tar"
            $use_sudo tar -xJf "$node_tar" -C /usr/local --strip-components=1
            rm -f "$node_tar"
        fi
    fi

    # 验证安装结果
    if command -v node &> /dev/null; then
        local new_version=$(node --version)
        local npm_version=$(npm --version 2>/dev/null || echo "unknown")
        success "Node.js 安装成功: ${new_version}, npm: ${npm_version}"
        return 0
    else
        error "Node.js 安装失败"
        return 1
    fi
}

install_claude() {
    info "正在安装 Claude Code..."

    local os_type="$(uname -s)"
    local install_method=""

    # 检测 Claude Code 是否已安装
    if command -v claude &> /dev/null; then
        info "Claude Code 已安装，跳过安装步骤"
        return 0
    fi

    # 方法1: Homebrew (macOS/Linux)
    if command -v brew &> /dev/null; then
        info "使用 Homebrew 安装..."
        brew install claude-code
        install_method="Homebrew"
    # 方法2: npm 全局安装
    elif command -v npm &> /dev/null; then
        # 配置国内镜像源（解决 SSL 证书问题）
        info "配置 npm 国内镜像源..."
        npm config set registry https://registry.npmmirror.com
        info "使用 npm 安装..."
        npm install -g @anthropic-ai/claude-code
        install_method="npm"
    # 方法3: Linux 系统，先安装 Node.js，再安装 Claude Code
    elif [[ "$os_type" == "Linux" ]]; then
        info "检测到 Linux 系统，准备安装 Node.js..."

        # 先安装 Node.js（确保版本符合要求）
        if install_nodejs; then
            if command -v npm &> /dev/null; then
                # 配置国内镜像源（解决 SSL 证书问题）
                info "配置 npm 国内镜像源..."
                npm config set registry https://registry.npmmirror.com
                info "Node.js 安装成功，使用 npm 安装 Claude Code..."
                npm install -g @anthropic-ai/claude-code
                install_method="npm"
            fi
        else
            error "无法安装 Node.js"
        fi
    fi

    # 验证安装结果
    if command -v claude &> /dev/null; then
        success "Claude Code 安装完成 (使用 ${install_method:-未知方法})"
    else
        error "无法自动安装 Claude Code"
        echo ""
        echo "请手动安装 Claude Code："
        echo "  方式1 - npm: npm install -g @anthropic-ai/claude-code"
        echo "  方式2 - Homebrew: brew install claude-code"
        echo "  方式3 - 手动安装: https://docs.anthropic.com/en/docs/claude-code/setup"
        echo ""
        info "或者使用 --config-only 选项仅配置 API 设置（推荐服务器环境）"
        exit 1
    fi
}

uninstall_claude() {
    info "正在卸载 Claude Code..."

    local os_type="$(uname -s)"

    if [[ "$os_type" == "Darwin" ]] && command -v brew &> /dev/null; then
        brew uninstall claude-code
    elif command -v npm &> /dev/null; then
        npm uninstall -g @anthropic-ai/claude-code
    fi

    # 清理配置文件
    rm -f "${SETTINGS_FILE}" "${CLAUDE_DIR}/.claude.json"

    success "Claude Code 卸载完成"
}

# ============================================================================
# 2. 配置 API 密钥和设置
# ============================================================================

configure_api() {
    info "配置 API 设置..."

    mkdir -p "${CLAUDE_DIR}"

    # 备份现有配置
    [[ -f "${SETTINGS_FILE}" ]] && cp "${SETTINGS_FILE}" "${SETTINGS_FILE}.backup"

    cat > "${SETTINGS_FILE}" << EOF
{
  "env": {
    "ANTHROPIC_API_KEY": "${API_KEY}",
    "ANTHROPIC_BASE_URL": "${BASE_URL:-${DEFAULT_BASE_URL}}",
    "ANTHROPIC_MODEL": "${MODEL:-${DEFAULT_MODEL}}",
    "ANTHROPIC_SMALL_FAST_MODEL": "${MODEL:-${DEFAULT_MODEL}}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${MODEL:-${DEFAULT_MODEL}}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${MODEL:-${DEFAULT_MODEL}}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${MODEL:-${DEFAULT_MODEL}}",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "permissions": {
    "allow": [
      "Bash(ls:*)",
      "Bash(touch:*)",
      "Bash(mkdir:*)",
      "Bash(less:*)"
    ]
  },
  "language": "simplified chinese",
  "skipDangerousModePermissionPrompt": true,
  "hasCompletedOnboarding": true
}
EOF

    success "API 配置完成"

    # =========================================================================
    # 2.1 配置 .claude.json（解决服务器连接问题）
    # =========================================================================
    CLAUDE_JSON="${CLAUDE_DIR}/.claude.json"

    info "配置 .claude.json..."

    [[ -f "${CLAUDE_JSON}" ]] && cp "${CLAUDE_JSON}" "${CLAUDE_JSON}.backup"

    # 创建或更新 .claude.json
    # 注意：这个文件必须包含 hasCompletedOnboarding: true 才能跳过首次启动的连接检查
    cat > "${CLAUDE_JSON}" << EOF
{
  "installMethod": "script",
  "autoUpdates": true,
  "firstStartTime": "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)",
  "hasCompletedOnboarding": true,
  "userID": "$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo 'auto-generated')",
  "projects": {
    "${PROJECT_ROOT:-.}": {
      "allowedTools": [],
      "history": [],
      "mcpContextUris": [],
      "mcpServers": {},
      "enabledMcpjsonServers": [],
      "disabledMcpjsonServers": [],
      "hasTrustDialogAccepted": false,
      "projectOnboardingSeenCount": 0,
      "hasClaudeMdExternalIncludesApproved": false,
      "hasClaudeMdExternalIncludesWarningShown": false
    }
  }
}
EOF

    success ".claude.json 配置完成"
}

# ============================================================================
# 3. 配置 MCP 服务器
# ============================================================================

configure_mcp() {
    if [[ "$SKIP_MCP" == true ]]; then
        warn "跳过 MCP 服务器配置"
        return
    fi

    info "配置 MCP 服务器..."

    # MCP 配置文件路径
    MCP_SETTINGS="${CLAUDE_DIR}/settings.json"

    # 确保 npx 可用（用于运行 MCP 服务器）
    if ! command -v npx &> /dev/null; then
        warn "npx 未安装，跳过 MCP 服务器配置"
        warn "请安装 Node.js 以使用 MCP 服务器: https://nodejs.org"
        return
    fi

    # 检查是否为 MiniMax 模型
    if [[ "${MODEL}" == MiniMax-* ]]; then
        info "检测到 MiniMax 模型，配置 MiniMax MCP 服务器..."

        if claude mcp list -s user 2>/dev/null | grep -Fq "MiniMax"; then
            warn "MiniMax MCP 服务器已存在，跳过创建"
        else
            local mcp_output
            if ! mcp_output=$(claude mcp add -s user MiniMax --env MINIMAX_API_KEY="${API_KEY}" --env MINIMAX_API_HOST=https://api.minimaxi.com -- uvx minimax-coding-plan-mcp -y 2>&1); then
                if echo "$mcp_output" | grep -qi "already exists"; then
                    warn "MiniMax MCP 服务器已存在，跳过创建"
                else
                    error "MiniMax MCP 服务器配置失败: $mcp_output"
                    exit 1
                fi
            else
                success "MiniMax MCP 服务器配置完成"
            fi
        fi
    fi

    # MCP 服务器将通过 npx 动态运行
    # Claude Code 会根据 settings.json 中的 MCP 配置启动服务器
    # 这里不需要额外配置，因为插件已经包含了 MCP 服务器定义

    success "MCP 服务器配置完成"
    info "MCP 服务器将在 Claude Code 首次运行时自动安装和启动"
}

# ============================================================================
# 4. 安装插件
# ============================================================================

install_plugins() {
    if [[ "$SKIP_PLUGINS" == true ]]; then
        warn "跳过插件安装"
        return
    fi

    if [[ "$CONFIG_ONLY" == true ]]; then
        warn "config-only 模式，跳过插件安装（需运行时 CLI 环境）"
        return
    fi

    info "安装插件..."

    for plugin in "${ENABLED_PLUGINS[@]}"; do
        info "安装插件: ${plugin}"

        if claude plugin install "${plugin}" 2>/dev/null; then
            success "插件 ${plugin} 安装成功"
        else
            warn "插件 ${plugin} 安装失败或已存在，跳过"
        fi
    done

    success "插件安装完成"
}

# ============================================================================
# 5. 配置项目特定的 CLAUDE.md
# ============================================================================

configure_project() {
    # 获取脚本所在目录
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
    CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"

    info "配置项目: ${PROJECT_ROOT}"

    # 检查是否已存在 CLAUDE.md
    if [[ -f "${CLAUDE_MD}" ]]; then
        warn "CLAUDE.md 已存在，跳过创建"
        return
    fi

    # 创建项目特定的 CLAUDE.md
    cat > "${CLAUDE_MD}" << EOF
# SkillEvolve-RL 项目配置

> 本文件定义 Claude Code 在本项目中的行为

## 项目概述

**SkillEvolve-RL** 是一个基于强化学习的 Skill 协同进化框架，包含：
- Meta-Controller: 元控制器
- Surrogate Reward Model: 替代奖励模型
- Skill Retrieval: 基于对比学习的 Skill 检索
- SMDP-PBRS: 基于势函数的奖励塑造
- MC Dropout: 不确定性估计
- 64维状态表示: 降维信息保持

## 语言设置

- 响应语言: **简体中文**
- 代码注释: 简体中文/English 混用均可

## 架构规范

### 目录结构

\`\`\`
skill-evo/
├── scripts/
│   ├── experiments_harness/  # 实验运行框架
│   ├── download/             # 数据下载模块
│   └── data/                 # 数据目录
├── skill_evolve_rl/
│   ├── experiments/          # 假设验证模块 (H2-H7)
│   ├── core/                 # 核心模块
│   ├── envs/                 # 环境接口
│   ├── worker/               # Worker LLM
│   └── utils/                # 工具函数
└── docs/
    └── plans/                # 设计文档
\`\`\`

### 实验假设

| 假设 | 描述 | 判定标准 |
|------|------|----------|
| H2 | n-step TD 收敛速度 | 提升 ≥ 20% vs TD(0) |
| H3 | Surrogate RM 预测精度 | Pearson ≥ 0.65 |
| H4 | Contrastive Retrieval | Top-20 召回率 ≥ 85% |
| H5 | SMDP-PBRS 策略保持 | 保持率 ≥ 95% |
| H6 | MC Dropout 不确定性 | 相关性 ≥ 0.5 |
| H7 | 64维状态表示 | 误差 < 15% |

## 开发规范

### Git 提交

- 使用 \`/commit\` 或 \`/commit-push-pr\` 技能
- 提交前确保测试通过
- PR 需要代码审查

### 实验开发

1. 先阅读 \`docs/SkillEvolve-RL_v24.1_preliminary_exp_framework.md\`
2. 遵循 \`scripts/experiments_harness/\` 的模块化结构
3. 每个假设独立验证
4. 使用日志系统记录所有输出
5. 结果保存到 \`scripts/experiments_harness/results/\`

### 代码风格

- Python: PEP 8
- 配置文件: YAML
- 文档: Markdown
- 类型提示: 使用 dataclass 或 type hints

## 工具使用

### 可用技能

- \`/commit\`: Git 提交
- \`/commit-push-pr\`: 提交并创建 PR
- \`/test-driven-development\`: TDD 开发
- \`/brainstorming\`: 头脑风暴
- \`/verification-before-completion\`: 完成前验证

### MCP 服务器

- Playwright: 浏览器自动化
- Context7: 文档检索
- GitHub: GitHub API

## 注意事项

1. **不要**猜测 API 密钥，使用提供的配置
2. **不要**修改全局 \`settings.json\`，除非明确要求
3. **始终**遵循 \`docs/plans/\` 中的设计文档
4. **保留**所有实验日志和结果，便于复现

---

*本文件由 install_claude_code.sh 自动生成*
EOF

    success "项目配置完成: ${CLAUDE_MD}"
}

# ============================================================================
# 6. 验证安装
# ============================================================================

verify_installation() {
    info "验证安装..."

    # 检查配置文件
    if [[ ! -f "${SETTINGS_FILE}" ]]; then
        error "配置文件未创建"
        return 1
    fi

    # 检查 API 配置
    if ! grep -q "ANTHROPIC_API_KEY" "${SETTINGS_FILE}"; then
        error "API 配置缺失"
        return 1
    fi

    # 检查 CLI 安装（除非是 config-only 模式）
    if [[ "$CONFIG_ONLY" != true ]] && ! command -v claude &> /dev/null; then
        error "Claude Code CLI 未正确安装"
        return 1
    fi

    success "安装验证通过"
    return 0
}

# ============================================================================
# 7. 显示使用说明
# ============================================================================

show_usage() {
    echo ""
    echo "========================================================================"
    success "Claude Code 安装/配置完成!"
    echo "========================================================================"
    echo ""

    if [[ "$CONFIG_ONLY" == true ]]; then
        echo "配置模式: 仅配置了 API 设置"
        echo ""
        echo "注意: Claude Code CLI 未安装，如需使用 CLI 请："
        echo "  - 在本地机器运行: npm install -g @anthropic-ai/claude-code"
        echo "  - 或使用 Homebrew: brew install claude-code"
    else
        echo "下一步："
        echo "  1. 重启终端或在当前会话中运行: source ~/.zshrc  # 或 ~/.bashrc"
        echo "  2. 验证安装: claude --version"
        echo "  3. 进入项目目录: cd ${PROJECT_ROOT:-.}"
        echo "  4. 开始使用: claude"
        echo ""
        echo "可用命令："
        echo "  claude                  # 启动 Claude Code"
        echo "  claude --version        # 查看版本"
        echo "  claude plugin list      # 列出已安装插件"
        echo "  claude mcp list         # 列出 MCP 服务器"
    fi

    echo ""
    echo "配置已保存到: ${SETTINGS_FILE}"
    echo ""
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    parse_args "$@"

    # 解析参数后获取 PROJECT_ROOT
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

    echo "========================================================================"
    info "Claude Code 安装/配置脚本"
    info "SkillEvolve-RL v24.1"
    echo "========================================================================"
    echo ""

    # 卸载模式
    if [[ "$UNINSTALL" == true ]]; then
        uninstall_claude
        exit 0
    fi

    # 检查安装状态（除非使用 config-only）
    if [[ "$CONFIG_ONLY" == true ]]; then
        info "配置模式: 仅配置 API 设置，跳过 CLI 安装"
    elif ! check_claude_installed; then
        install_claude
    fi

    # 配置
    if [[ "$PROJECT_ONLY" == false && "$CONFIG_ONLY" == false ]]; then
        configure_api
        configure_mcp
        install_plugins
    elif [[ "$CONFIG_ONLY" == true ]]; then
        configure_api
    else
        info "项目模式: 仅配置 ${PROJECT_ROOT}"
    fi

    # 项目特定配置
    configure_project

    # 验证
    if [[ "$CONFIG_ONLY" != true ]]; then
        verify_installation
    fi

    # 显示使用说明
    show_usage
}

# 运行主函数
main "$@"