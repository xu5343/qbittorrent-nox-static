#!/bin/bash
#======================================
# qBittorrent-Enhanced-Edition 一键安装脚本
# 支持系统：Debian 10+, Ubuntu 20.04+
# 作者：自动化安装脚本
#======================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查是否为 root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_error "此脚本必须以 root 权限运行！请使用 sudo 或切换到 root 用户。"
    fi
}

# 检查系统版本
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        print_info "检测到系统: $PRETTY_NAME"
        
        if [[ "$OS" == "debian" && "${VER%%.*}" -ge 10 ]] || [[ "$OS" == "ubuntu" && "${VER%%.*}" -ge 20 ]]; then
            print_success "系统版本符合要求"
        else
            print_error "不支持的系统版本。需要 Debian 10+ 或 Ubuntu 20.04+"
        fi
    else
        print_error "无法检测系统版本"
    fi
}

# 获取最新版本号
get_latest_version() {
    print_info "正在获取最新版本信息..."
    LATEST_VERSION=$(curl -sL https://api.github.com/repos/c0re100/qBittorrent-Enhanced-Edition/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$LATEST_VERSION" ]; then
        print_error "无法获取最新版本信息，请检查网络连接"
    fi
    
    print_success "最新版本: $LATEST_VERSION"
}

# 安装依赖
install_dependencies() {
    print_info "安装必要依赖..."
    apt update -qq
    apt install -y wget curl unzip python3 >/dev/null 2>&1
    print_success "依赖安装完成"
}

# 下载并安装 qBittorrent-Enhanced
install_qbittorrent() {
    print_info "下载 qBittorrent-Enhanced-Edition $LATEST_VERSION ..."
    
    # 构建下载链接
    DOWNLOAD_URL="https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/download/${LATEST_VERSION}/qbittorrent-enhanced-nox_linux_x86_64_static.zip"
    
    cd /tmp
    rm -f qbittorrent-enhanced-nox_linux_x86_64_static.zip qbittorrent-enhanced-nox
    
    if ! wget -q --show-progress "$DOWNLOAD_URL"; then
        print_error "下载失败，请检查网络或 GitHub 访问"
    fi
    
    print_info "解压文件..."
    unzip -q qbittorrent-enhanced-nox_linux_x86_64_static.zip
    
    print_info "安装到系统路径..."
    chmod +x qbittorrent-enhanced-nox
    mv qbittorrent-enhanced-nox /usr/local/bin/
    
    print_success "qBittorrent-Enhanced 安装完成"
}

# 生成密码哈希
generate_password_hash() {
    local password="$1"
    
    python3 << EOF
import hashlib, base64, os

password = "$password"
salt = os.urandom(16)
iterations = 100000

key = hashlib.pbkdf2_hmac('sha512', password.encode('utf-8'), salt, iterations, dklen=64)

salt_b64 = base64.b64encode(salt).decode('ascii')
key_b64 = base64.b64encode(key).decode('ascii')

print(f'@ByteArray({salt_b64}:{key_b64})')
EOF
}

# 创建配置文件
create_config() {
    print_info "创建配置文件..."
    
    mkdir -p /root/.config/qBittorrent
    
    local password_hash=$(generate_password_hash "$QB_PASSWORD")
    
    cat > /root/.config/qBittorrent/qBittorrent.conf << EOF
[BitTorrent]
Session\DefaultSavePath=/root/Downloads
Session\TempPath=/root/Downloads/temp
Session\TempPathEnabled=true
Session\Port=$QB_PORT
Session\QueueingSystemEnabled=true
Session\GlobalMaxRatio=2
Session\GlobalMaxSeedingMinutes=-1

[Preferences]
WebUI\Username=$QB_USERNAME
WebUI\Password_PBKDF2="$password_hash"
WebUI\Port=$QB_WEBUI_PORT
WebUI\HostHeaderValidation=false
WebUI\CSRFProtection=true
WebUI\ClickjackingProtection=true
WebUI\LocalHostAuth=false
WebUI\Address=0.0.0.0

[LegalNotice]
Accepted=true
EOF
    
    # 创建下载目录
    mkdir -p /root/Downloads/temp
    
    print_success "配置文件创建完成"
}

# 创建 systemd 服务
create_systemd_service() {
    print_info "创建 systemd 服务..."
    
    cat > /etc/systemd/system/qbittorrent-nox.service << 'EOF'
[Unit]
Description=qBittorrent-Enhanced-Edition Daemon
After=network.target

[Service]
Type=forking
User=root
ExecStart=/usr/local/bin/qbittorrent-enhanced-nox -d --webui-port=8080 --confirm-legal-notice
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    # 替换实际端口
    sed -i "s/8080/$QB_WEBUI_PORT/g" /etc/systemd/system/qbittorrent-nox.service
    
    systemctl daemon-reload
    print_success "systemd 服务创建完成"
}

# 启动服务
start_service() {
    print_info "启动 qBittorrent 服务..."
    systemctl enable qbittorrent-nox >/dev/null 2>&1
    systemctl start qbittorrent-nox
    
    sleep 2
    
    if systemctl is-active --quiet qbittorrent-nox; then
        print_success "qBittorrent 服务启动成功"
    else
        print_error "服务启动失败，请查看日志: journalctl -u qbittorrent-nox -n 50"
    fi
}

# 显示安装信息
show_info() {
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        qBittorrent-Enhanced 安装成功！                  ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  版本: ${YELLOW}$LATEST_VERSION${NC}"
    echo -e "${GREEN}║${NC}  Web UI 地址: ${BLUE}http://$SERVER_IP:$QB_WEBUI_PORT${NC}"
    echo -e "${GREEN}║${NC}  用户名: ${YELLOW}$QB_USERNAME${NC}"
    echo -e "${GREEN}║${NC}  密码: ${YELLOW}$QB_PASSWORD${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  下载目录: ${BLUE}/root/Downloads${NC}"
    echo -e "${GREEN}║${NC}  临时目录: ${BLUE}/root/Downloads/temp${NC}"
    echo -e "${GREEN}║${NC}  BT 端口: ${YELLOW}$QB_PORT${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${RED}⚠️  重要：请手动放行以下端口！${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}  - Web UI 端口: $QB_WEBUI_PORT (TCP)${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}  - BT 数据端口: $QB_PORT (TCP + UDP)${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  防火墙配置示例 (根据实际情况选择):"
    echo -e "${GREEN}║${NC}  ${BLUE}  # UFW${NC}"
    echo -e "${GREEN}║${NC}  ${BLUE}  ufw allow $QB_WEBUI_PORT/tcp${NC}"
    echo -e "${GREEN}║${NC}  ${BLUE}  ufw allow $QB_PORT/tcp${NC}"
    echo -e "${GREEN}║${NC}  ${BLUE}  ufw allow $QB_PORT/udp${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BLUE}  # iptables${NC}"
    echo -e "${GREEN}║${NC}  ${BLUE}  iptables -I INPUT -p tcp --dport $QB_WEBUI_PORT -j ACCEPT${NC}"
    echo -e "${GREEN}║${NC}  ${BLUE}  iptables -I INPUT -p tcp --dport $QB_PORT -j ACCEPT${NC}"
    echo -e "${GREEN}║${NC}  ${BLUE}  iptables -I INPUT -p udp --dport $QB_PORT -j ACCEPT${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${RED}  ⚠️  云服务器还需在控制台安全组放行端口！${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  常用命令:"
    echo -e "${GREEN}║${NC}    启动: ${BLUE}systemctl start qbittorrent-nox${NC}"
    echo -e "${GREEN}║${NC}    停止: ${BLUE}systemctl stop qbittorrent-nox${NC}"
    echo -e "${GREEN}║${NC}    重启: ${BLUE}systemctl restart qbittorrent-nox${NC}"
    echo -e "${GREEN}║${NC}    状态: ${BLUE}systemctl status qbittorrent-nox${NC}"
    echo -e "${GREEN}║${NC}    日志: ${BLUE}journalctl -u qbittorrent-nox -f${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 用户输入配置
user_input() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   qBittorrent-Enhanced-Edition 一键安装脚本             ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Web UI 端口
    read -p "$(echo -e ${YELLOW}请设置 Web UI 端口 [默认: 8080]: ${NC})" QB_WEBUI_PORT
    QB_WEBUI_PORT=${QB_WEBUI_PORT:-8080}
    
    # BT 端口
    read -p "$(echo -e ${YELLOW}请设置 BT 监听端口 [默认: 6881]: ${NC})" QB_PORT
    QB_PORT=${QB_PORT:-6881}
    
    # 用户名
    read -p "$(echo -e ${YELLOW}请设置登录用户名 [默认: admin]: ${NC})" QB_USERNAME
    QB_USERNAME=${QB_USERNAME:-admin}
    
    # 密码
    while true; do
        read -s -p "$(echo -e ${YELLOW}请设置登录密码: ${NC})" QB_PASSWORD
        echo ""
        if [ -z "$QB_PASSWORD" ]; then
            print_warning "密码不能为空，请重新输入"
            continue
        fi
        
        read -s -p "$(echo -e ${YELLOW}请再次输入密码: ${NC})" QB_PASSWORD_CONFIRM
        echo ""
        
        if [ "$QB_PASSWORD" == "$QB_PASSWORD_CONFIRM" ]; then
            break
        else
            print_warning "两次密码不一致，请重新输入"
        fi
    done
    
    echo ""
    print_info "配置确认:"
    echo "  Web UI 端口: $QB_WEBUI_PORT"
    echo "  BT 端口: $QB_PORT"
    echo "  用户名: $QB_USERNAME"
    echo "  密码: ********"
    echo ""
    
    read -p "$(echo -e ${YELLOW}确认以上配置？[y/N]: ${NC})" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_error "安装已取消"
    fi
}

# 主函数
main() {
    clear
    check_root
    check_system
    user_input
    get_latest_version
    install_dependencies
    install_qbittorrent
    create_config
    create_systemd_service
    start_service
    show_info
}

# 执行主函数
main
