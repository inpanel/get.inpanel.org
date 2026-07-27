#!/bin/bash
#
#   InPanel 一键安装脚本
#
#   Copyright (c) 2021-2026, Jackson Dou
#   All rights reserved.
#
#   GitHub: https://github.com/inpanel/inpanel
#   Issues: https://github.com/inpanel/inpanel/issues
#
#   用法:
#       curl -fsSL https://get.inpanel.org/install.sh | bash
#       或
#       wget -qO- https://get.inpanel.org/install.sh | bash
#
#   安装策略（按优先级）:
#       Debian/Ubuntu 系:
#           1. DEB 包安装 — 最推荐，卸载干净
#           2. pip + venv 安装 — 避免 PEP 668 externally-managed 限制
#           3. pip install --break-system-packages — 最后手段
#
#       RHEL/CentOS/Fedora 系:
#           1. RPM 包安装 — 最推荐，卸载干净
#           2. pip + venv 安装 — 避免系统环境污染
#           3. pip install --break-system-packages — 最后手段
#
#       其他系统:
#           1. pip + venv 安装
#           2. pip install --break-system-packages
#
#   此脚本基于 MIT License 分发。

set -e

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

# ========== 颜色 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
DARK='\033[1;30m'
NC='\033[0m'
BOLD='\033[1m'

INP="[\033[1;30mINPANEL\033[0m]"
OK="${GREEN}OK${NC}"
FAIL="${RED}FAIL${NC}"

# ========== 默认配置 ==========
INPANEL_PORT=14433
USERNAME='admin'
PASSWORD='admin'
INSTALL_MODE=''           # deb | rpm | venv | pip-system | auto (空=auto)
REPOSITORY='https://github.com/inpanel/inpanel'
BRANCH='master'
GITHUB_RELEASES_API='https://api.github.com/repos/inpanel/inpanel/releases/latest'
GITHUB_DEB_DOWNLOAD='https://github.com/inpanel/inpanel/releases/download'

# 安装路径（仅 venv 模式使用）
VENV_DIR='/opt/inpanel'
INPANEL_BIN='/usr/local/bin/inpanel'

# ========== 工具函数 ==========
info()    { echo -e "${INP}: $1"; }
success() { echo -e "${INP}: $1 [${OK}]"; }
warn()    { echo -e "${INP}: ${RED}$1${NC}"; }
step()    { echo -e "${INP}: ${BOLD}$1${NC}"; }

error_exit() {
    warn "$1"
    exit 1
}

need_root() {
    if [ "$(id -u)" != "0" ]; then
        error_exit "Aborted, must be run as root. Try: sudo bash install.sh"
    fi
}

need_network() {
    if ! curl -s --connect-timeout 3 https://github.com >/dev/null 2>&1; then
        if ! wget -q --timeout=3 -O /dev/null https://github.com 2>/dev/null; then
            warn "Network unavailable, but will try to continue..."
        fi
    fi
}

detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DL='curl -fsSL'
    elif command -v wget >/dev/null 2>&1; then
        DL='wget -qO-'
    else
        error_exit "Could not find curl or wget. Please install one of them first."
    fi
}

# ========== 系统检测 ==========
detect_os() {
    OS_ID=''
    OS_VERSION=''
    OS_CODENAME=''
    OS_ARCH=$(uname -m)

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_CODENAME="${VERSION_CODENAME:-}"
    elif [ -f /etc/redhat-release ]; then
        OS_ID='centos'
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    elif [ "$(uname)" = 'Darwin' ]; then
        OS_ID='macos'
        OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo 'unknown')
    else
        OS_ID='unknown'
    fi

    info "System: ${OS_ID} ${OS_VERSION} (${OS_ARCH})"
}

# 判断是否 Debian 系
is_debian_family() {
    case "$OS_ID" in
        ubuntu|debian|deepin|uos|linuxmint|kali|raspbian) return 0 ;;
        *) return 1 ;;
    esac
}

# 判断是否 RHEL 系
is_rhel_family() {
    case "$OS_ID" in
        centos|rhel|fedora|rocky|almalinux|openEuler) return 0 ;;
        *) return 1 ;;
    esac
}

# ========== 依赖安装 ==========
install_dependencies() {
    step "Installing dependencies..."

    local pkgs=''

    if is_debian_family; then
        apt-get update -qq
        # 最小依赖：curl/wget + python3 + python3-venv
        pkgs='curl wget python3 python3-venv python3-pip'
        apt-get install -y -qq $pkgs 2>/dev/null || apt-get install -y $pkgs
    elif is_rhel_family; then
        if command -v dnf >/dev/null 2>&1; then
            pkgs='curl wget python3 python3-pip'
            dnf install -y -q $pkgs 2>/dev/null || dnf install -y $pkgs
        else
            pkgs='curl wget python3 python3-pip'
            yum install -y -q $pkgs 2>/dev/null || yum install -y $pkgs
        fi
    fi

    success "Dependencies installed"
}

# ========== Python3 检查 ==========
check_python3() {
    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found, trying to install..."
        install_dependencies
        if ! command -v python3 >/dev/null 2>&1; then
            error_exit "Cannot install python3. Please install it manually."
        fi
    fi
    info "Python: $(python3 --version)"
}

# ========== 模式1: DEB 包安装 ==========
install_via_deb() {
    step "Install via DEB package..."

    # 获取最新 release tag
    local latest_tag=''
    if command -v curl >/dev/null 2>&1; then
        latest_tag=$(curl -fsSL "$GITHUB_RELEASES_API" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"tag_name": *"\(.*\)"/\1/')
    fi

    if [ -z "$latest_tag" ]; then
        warn "Cannot fetch latest version from GitHub, trying local DEB..."
        # 尝试从已知路径安装
        local local_deb=$(ls /tmp/inpanel_*.deb 2>/dev/null | head -1)
        if [ -n "$local_deb" ]; then
            dpkg -i "$local_deb" || apt-get install -y -f
            success "DEB package installed from local file"
            return 0
        fi
        return 1
    fi

    # 清理版本号前缀 v
    local ver="${latest_tag#v}"

    # 构建下载 URL
    local deb_url="${GITHUB_DEB_DOWNLOAD}/${latest_tag}/inpanel_${ver}-1_all.deb"
    local deb_file="/tmp/inpanel_${ver}-1_all.deb"

    info "Downloading: ${deb_url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$deb_file" "$deb_url" || {
            warn "Download failed, DEB file may not exist for this release"
            return 1
        }
    else
        wget -q -O "$deb_file" "$deb_url" || {
            warn "Download failed, DEB file may not exist for this release"
            return 1
        }
    fi

    # 安装
    info "Installing DEB package..."
    dpkg -i "$deb_file" 2>/dev/null || apt-get install -y -f
    rm -f "$deb_file"
    success "DEB package installed"
    return 0
}

# ========== 模式2: RPM 包安装 ==========
install_via_rpm() {
    step "Install via RPM package..."

    # 获取最新 release tag
    local latest_tag=''
    if command -v curl >/dev/null 2>&1; then
        latest_tag=$(curl -fsSL "$GITHUB_RELEASES_API" 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"tag_name": *"\(.*\)"/\1/')
    fi

    if [ -z "$latest_tag" ]; then
        warn "Cannot fetch latest version from GitHub, trying local RPM..."
        local local_rpm=$(ls /tmp/inpanel_*.noarch.rpm 2>/dev/null | head -1)
        if [ -n "$local_rpm" ]; then
            rpm -ivh "$local_rpm" 2>/dev/null || yum install -y "$local_rpm"
            success "RPM package installed from local file"
            return 0
        fi
        return 1
    fi

    local ver="${latest_tag#v}"
    local rpm_url="${GITHUB_DEB_DOWNLOAD}/${latest_tag}/inpanel-${ver}-1.noarch.rpm"
    local rpm_file="/tmp/inpanel-${ver}-1.noarch.rpm"

    info "Downloading: ${rpm_url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$rpm_file" "$rpm_url" || {
            warn "Download failed, RPM file may not exist for this release"
            return 1
        }
    else
        wget -q -O "$rpm_file" "$rpm_url" || {
            warn "Download failed, RPM file may not exist for this release"
            return 1
        }
    fi

    # 安装
    info "Installing RPM package..."
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$rpm_file" 2>/dev/null || rpm -ivh "$rpm_file"
    else
        yum install -y "$rpm_file" 2>/dev/null || rpm -ivh "$rpm_file"
    fi
    rm -f "$rpm_file"
    success "RPM package installed"
    return 0
}

# ========== 模式3: pip + venv 安装 ==========
install_via_venv() {
    step "Install via pip + venv..."

    # 检查 python3-venv
    if ! python3 -c 'import venv' 2>/dev/null; then
        warn "python3-venv not available, trying to install..."
        if is_debian_family; then
            apt-get install -y -qq python3-venv 2>/dev/null || apt-get install -y python3-venv
        fi
    fi

    if ! python3 -c 'import venv' 2>/dev/null; then
        warn "Cannot create venv, falling back to pip --break-system-packages..."
        return 1
    fi

    # 创建 venv
    info "Creating virtual environment at ${VENV_DIR}..."
    python3 -m venv "$VENV_DIR"
    success "Virtual environment created"

    # 安装 InPanel
    info "Installing InPanel via pip..."
    "$VENV_DIR/bin/pip" install --upgrade pip -q
    "$VENV_DIR/bin/pip" install inpanel -q || {
        warn "Failed to install from PyPI, trying from GitHub..."
        "$VENV_DIR/bin/pip" install "git+${REPOSITORY}@${BRANCH}" || {
            warn "pip install failed"
            rm -rf "$VENV_DIR"
            return 1
        }
    }

    # 创建全局软链接
    cat > "$INPANEL_BIN" << 'SCRIPT'
#!/bin/bash
INPANEL_VENV="/opt/inpanel"
if [ -x "${INPANEL_VENV}/bin/inpanel" ]; then
    exec "${INPANEL_VENV}/bin/inpanel" "$@"
else
    echo "InPanel not found at ${INPANEL_VENV}/bin/inpanel" >&2
    exit 1
fi
SCRIPT
    chmod +x "$INPANEL_BIN"
    success "pip install completed (venv mode)"
    return 0
}

# ========== 模式3: pip install --break-system-packages ==========
install_via_pip_force() {
    step "Install via pip --break-system-packages..."

    # 先尝试正常 pip install
    if pip3 install inpanel -q 2>/dev/null; then
        success "pip install completed"
        return 0
    fi

    # 如果被 PEP 668 阻止，使用 --break-system-packages
    warn "Normal pip install blocked (PEP 668), using --break-system-packages..."
    pip3 install --break-system-packages inpanel -q || {
        # 降级：从 GitHub 安装
        pip3 install --break-system-packages "git+${REPOSITORY}@${BRANCH}" || {
            warn "pip install failed"
            return 1
        }
    }
    success "pip install completed (--break-system-packages)"
    return 0
}

# ========== 主安装流程 ==========
install_inpanel() {
    local mode="${INSTALL_MODE:-auto}"

    # --- auto: 自动选择最佳模式 ---
    if [ "$mode" = 'auto' ]; then
        if is_debian_family; then
            # Debian/Ubuntu: 优先 DEB 包
            if install_via_deb; then
                INSTALL_MODE='deb'
                return 0
            fi
            warn "DEB install failed, trying venv..."
            if install_via_venv; then
                INSTALL_MODE='venv'
                return 0
            fi
            warn "Venv install failed, trying --break-system-packages..."
            if install_via_pip_force; then
                INSTALL_MODE='pip-system'
                return 0
            fi
        elif is_rhel_family; then
            # RHEL/CentOS/Fedora: 优先 RPM 包
            if install_via_rpm; then
                INSTALL_MODE='rpm'
                return 0
            fi
            warn "RPM install failed, trying venv..."
            if install_via_venv; then
                INSTALL_MODE='venv'
                return 0
            fi
            warn "Venv install failed, trying --break-system-packages..."
            if install_via_pip_force; then
                INSTALL_MODE='pip-system'
                return 0
            fi
        else
            # 其他系统：venv 优先
            if install_via_venv; then
                INSTALL_MODE='venv'
                return 0
            fi
            if install_via_pip_force; then
                INSTALL_MODE='pip-system'
                return 0
            fi
        fi
        error_exit "All install methods failed."
    fi

    # --- 指定模式 ---
    case "$mode" in
        deb)
            install_via_deb || error_exit "DEB install failed"
            ;;
        rpm)
            install_via_rpm || error_exit "RPM install failed"
            ;;
        venv)
            install_via_venv || error_exit "Venv install failed"
            ;;
        pip-system)
            install_via_pip_force || error_exit "pip install failed"
            ;;
        *)
            error_exit "Unknown install mode: $mode (valid: auto, deb, rpm, venv, pip-system)"
            ;;
    esac
}

# ========== 配置服务 ==========
install_service() {
    step "Configuring service..."

    if [ -d /etc/systemd/system ]; then
        # systemd 服务
        cat > /etc/systemd/system/inpanel.service << 'SERVICE'
[Unit]
Description=InPanel Control Panel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/inpanel run
ExecStop=/usr/local/bin/inpanel stop
ExecReload=/usr/local/bin/inpanel reload
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
        systemctl daemon-reload
        systemctl enable inpanel 2>/dev/null || true
        success "systemd service installed"
    else
        # init.d 服务
        cat > /etc/init.d/inpanel << 'INITD'
#!/bin/bash
# chkconfig: 2345 99 01
# description: InPanel Control Panel

PROG="/usr/local/bin/inpanel"

case "$1" in
    start|stop|status|restart|reload)
        $PROG $1
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart|reload}"
        exit 1
        ;;
esac
exit 0
INITD
        chmod +x /etc/init.d/inpanel

        if command -v chkconfig >/dev/null 2>&1; then
            chkconfig --add inpanel 2>/dev/null || true
            chkconfig inpanel on 2>/dev/null || true
        elif command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d inpanel defaults 2>/dev/null || true
        fi
        success "init.d service installed"
    fi
}

# ========== 配置账号和端口 ==========
config_account() {
    if [ "$USERNAME" != 'admin' ]; then
        inpanel config set auth username "$USERNAME" 2>/dev/null || true
    fi
    if [ "$PASSWORD" != 'admin' ]; then
        inpanel config set auth password "$PASSWORD" 2>/dev/null || true
    fi
}

config_port() {
    if [ -n "$INPANEL_PORT" ] && [ "$INPANEL_PORT" != '14433' ]; then
        inpanel config set server port "$INPANEL_PORT" 2>/dev/null || true
    fi
}

# ========== 配置防火墙 ==========
config_firewall() {
    step "Configuring firewall..."

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
        ufw allow "${INPANEL_PORT}/tcp" 2>/dev/null || true
        success "ufw configured"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${INPANEL_PORT}/tcp" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        success "firewalld configured"
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "${INPANEL_PORT}" -j ACCEPT 2>/dev/null || true
        success "iptables configured"
    else
        info "No firewall detected, skipping."
    fi
}

# ========== 启动服务 ==========
start_service() {
    step "Starting InPanel..."

    if [ -d /etc/systemd/system ]; then
        systemctl start inpanel 2>/dev/null || {
            warn "Failed to start via systemd, trying directly..."
            /usr/local/bin/inpanel run &
        }
    else
        /etc/init.d/inpanel start 2>/dev/null || {
            warn "Failed to start via init.d, trying directly..."
            /usr/local/bin/inpanel run &
        }
    fi

    # 等待服务启动
    sleep 2
    success "InPanel started"
}

# ========== 获取公网 IP ==========
get_public_ip() {
    local ip=''
    # 依次尝试多个 IP 检测服务
    for svc in 'http://ip.42.pl/raw' 'https://api.ipify.org' 'https://ifconfig.me' 'https://icanhazip.com'; do
        ip=$(curl -s --connect-timeout 3 "$svc" 2>/dev/null || true)
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    done
    # 如果外网不可达，取本地 IP
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')
    echo "$ip"
}

# ========== 显示安装信息 ==========
show_success() {
    local ip=$(get_public_ip)

    echo ''
    echo -e "  ${GREEN}=========================================${NC}"
    echo -e "  ${GREEN}      InPanel Install Completed!${NC}"
    echo -e "  ${GREEN}=========================================${NC}"
    echo ''
    echo -e "  URL:      ${BLUE}http://${ip}:${INPANEL_PORT}${NC}"
    echo -e "  Username: ${BLUE}${USERNAME}${NC}"
    echo -e "  Password: ${BLUE}${PASSWORD}${NC}"
    echo -e "  Mode:     ${BLUE}${INSTALL_MODE}${NC}"
    echo ''
    echo -e "  Commands:"
    echo -e "    inpanel status    - check status"
    echo -e "    inpanel stop      - stop service"
    echo -e "    inpanel start     - start service"
    echo -e "    inpanel config    - manage config"
    echo ''
    echo -e "  ${DARK}For security, please change your password immediately:${NC}"
    echo -e "  ${DARK}  inpanel config set auth password <new_password>${NC}"
    echo ''
    echo -e "  ${GREEN}Wish you a happy life!${NC}"
    echo ''
}

# ========== 参数解析 ==========
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode|--mode=*)
                if [ "$1" = '--mode' ]; then
                    INSTALL_MODE="$2"; shift
                else
                    INSTALL_MODE="${1#--mode=}"
                fi
                ;;
            --port|--port=*)
                if [ "$1" = '--port' ]; then
                    INPANEL_PORT="$2"; shift
                else
                    INPANEL_PORT="${1#--port=}"
                fi
                ;;
            --branch|--branch=*)
                if [ "$1" = '--branch' ]; then
                    BRANCH="$2"; shift
                else
                    BRANCH="${1#--branch=}"
                fi
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ''
                echo 'Options:'
                echo '  --mode=<auto|deb|rpm|venv|pip-system>  安装模式 (default: auto)'
                echo '  --port=<port>                      监听端口 (default: 14433)'
                echo '  --branch=<branch>                  Git 分支 (default: master)'
                echo '  --help, -h                         显示帮助'
                echo ''
                echo 'Install modes:'
                echo '  auto       自动选择最佳方式 (DEB/RPM > venv > pip-system)'
                echo '  deb        安装 .deb 包 (Debian/Ubuntu)'
                echo '  rpm        安装 .rpm 包 (CentOS/RHEL/Fedora)'
                echo '  venv       创建虚拟环境安装 (避免 PEP 668 限制)'
                echo '  pip-system pip install --break-system-packages'
                echo ''
                echo 'Examples:'
                echo '  curl -fsSL https://get.inpanel.org/install.sh | bash'
                echo '  bash install.sh --mode=rpm --port=8888'
                echo '  bash install.sh --mode=deb'
                exit 0
                ;;
            *)
                warn "Unknown option: $1 (try --help)"
                exit 1
                ;;
        esac
        shift
    done
}

# ========== 主入口 ==========
main() {
    parse_args "$@"

    echo ''
    echo -e "  ${BLUE}===========================================${NC}"
    echo -e "  ${BLUE}     InPanel Installer v2.0${NC}"
    echo -e "  ${BLUE}===========================================${NC}"
    echo ''

    need_root
    detect_downloader
    detect_os
    need_network

    check_python3
    install_dependencies

    install_inpanel

    # 确保 inpanel 命令可用
    if ! command -v inpanel >/dev/null 2>&1; then
        if [ -f /usr/bin/inpanel ]; then
            ln -sf /usr/bin/inpanel /usr/local/bin/inpanel 2>/dev/null || true
        fi
    fi

    install_service
    config_account
    config_port
    config_firewall
    start_service
    show_success
}

main "$@"
