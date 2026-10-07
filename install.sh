#!/bin/bash
# =========================================================
# Project: SSH-WS-3XUI
# Author: EkromSSH
# Description: SSH WebSocket + 3-X-UI (VLESS & VMess) Port 80
# Features: Multi-Protocol, Real-IP tracking, Limit IP & Limit GB
# Supports: NPV Tunnel, HTTP Custom, HTTP Injector, v2rayNG
# =========================================================

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_URL="https://raw.githubusercontent.com/EkromSSH/SSH-WS-3XUI/main"

# Check Root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] กรุณารันด้วยสิทธิ์ root (sudo bash)${NC}"
        exit 1
    fi
}

# Create shortcut command so user can type 'ssh-xui' anytime
install_shortcut() {
    cp "$0" /usr/local/bin/ssh-xui 2>/dev/null || true
    chmod +x /usr/local/bin/ssh-xui 2>/dev/null || true
    ln -sf /usr/local/bin/ssh-xui /usr/bin/ssh-xui 2>/dev/null || true
}

# Banner
show_banner() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}      SSH WebSocket + 3-X-UI Manager & Installer    ${NC}"
    echo -e "${YELLOW}           Share Port 80 for SSH & Xray             ${NC}"
    echo -e "${PURPLE}         Limit IP & Quota (GB) Supported            ${NC}"
    echo -e "${BLUE}                  By EkromSSH                       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo ""
}

# 1. Install 3-X-UI (v2.8.9)
install_3xui() {
    check_root
    echo -e "${GREEN}[*] กำลังดาวน์โหลดและติดตั้ง 3-X-UI เวอร์ชัน v2.8.9...${NC}"
    echo -e "${YELLOW}คำแนะนำ: แนะนำให้ตั้ง Port สำหรับ Web Panel เป็นพอร์ตอื่น เช่น 2053 (อย่าใช้พอร์ต 80)${NC}"
    echo ""
    sleep 2
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) v2.8.9
    echo ""
    echo -e "${GREEN}[✓] ติดตั้ง 3-X-UI v2.8.9 เรียบร้อยแล้ว!${NC}"
    read -p "กด Enter เพื่อกลับสู่เมนูหลัก..." temp
}

# 2. Install SSH WebSocket + Nginx Reverse Proxy + Limit System
install_ssh_ws() {
    check_root
    echo -e "${BLUE}[1/5] กำลังติดตั้ง Nginx, Python3, iptables และเครื่องมือจำเป็น...${NC}"
    apt-get update -y >/dev/null 2>&1
    apt-get install -y nginx python3 curl ufw iptables >/dev/null 2>&1
    mkdir -p /etc/ssh /run/ssh-ws-ports

    echo -e "${BLUE}[2/5] กำลังสร้างระบบ SSH WebSocket (Backend Port 2082 -> SSH 22)...${NC}"
    # Download or write ssh-ws.py
    if [ -f "$(dirname "$0")/ssh-ws.py" ]; then
        cp "$(dirname "$0")/ssh-ws.py" /usr/local/bin/ssh-ws.py
    else
        curl -s -L "${REPO_URL}/ssh-ws.py" -o /usr/local/bin/ssh-ws.py 2>/dev/null || true
    fi
    chmod +x /usr/local/bin/ssh-ws.py

    cat << 'EOF' > /etc/systemd/system/ssh-ws.service
[Unit]
Description=SSH WebSocket Service by EkromSSH
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ssh-ws.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now ssh-ws >/dev/null 2>&1
    systemctl restart ssh-ws

    echo -e "${BLUE}[3/5] กำลังติดตั้งระบบ Limit IP และ Limit GB (ssh-limit)...${NC}"
    # Download or write ssh-limit.py
    if [ -f "$(dirname "$0")/ssh-limit.py" ]; then
        cp "$(dirname "$0")/ssh-limit.py" /usr/local/bin/ssh-limit.py
    else
        curl -s -L "${REPO_URL}/ssh-limit.py" -o /usr/local/bin/ssh-limit.py 2>/dev/null || true
    fi
    chmod +x /usr/local/bin/ssh-limit.py

    # Install ssh-user CLI tool
    if [ -f "$(dirname "$0")/ssh-user" ]; then
        cp "$(dirname "$0")/ssh-user" /usr/local/bin/ssh-user
    else
        curl -s -L "${REPO_URL}/ssh-user" -o /usr/local/bin/ssh-user 2>/dev/null || true
    fi
    chmod +x /usr/local/bin/ssh-user
    ln -sf /usr/local/bin/ssh-user /usr/bin/ssh-user 2>/dev/null || true

    # Create systemd service for ssh-limit
    cat << 'EOF' > /etc/systemd/system/ssh-limit.service
[Unit]
Description=SSH Limit IP and GB Enforcer by EkromSSH
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ssh-limit.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now ssh-limit >/dev/null 2>&1
    systemctl restart ssh-limit

    echo -e "${BLUE}[4/5] กำลังตั้งค่า Nginx Reverse Proxy สำหรับพอร์ต 80...${NC}"
    if [ -f /etc/nginx/sites-available/default ]; then
        cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
    fi

    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # 1. 3-X-UI: VLESS WebSocket
    location /vless-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # 2. 3-X-UI: VMess WebSocket
    location /vmess-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    # 3. SSH WebSocket (Default / Path)
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    nginx -t >/dev/null 2>&1
    systemctl enable nginx >/dev/null 2>&1
    systemctl restart nginx

    echo -e "${BLUE}[5/5] ตรวจสอบ Firewall...${NC}"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow 22/tcp >/dev/null 2>&1
    fi

    install_shortcut

    SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 api.ipify.org || echo "IP_SERVER")

    clear
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}  ติดตั้ง SSH WS + Limit IP/GB + Nginx สำเร็จ!       ${NC}"
    echo -e "${GREEN}====================================================${NC}"
    echo ""
    echo -e "${YELLOW}Server IP:${NC} ${SERVER_IP}"
    echo -e "${YELLOW}Main Port:${NC} 80"
    echo ""
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "${PURPLE}สิ่งที่ต้องตั้งค่าใน 3-X-UI (Inbounds):${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "1) ${GREEN}VLESS Inbound:${NC}"
    echo -e "   - Protocol       : vless"
    echo -e "   - Listening IP   : 127.0.0.1"
    echo -e "   - Port           : 10082"
    echo -e "   - Network        : ws"
    echo -e "   - Path           : /vless-ws"
    echo ""
    echo -e "2) ${GREEN}VMess Inbound:${NC}"
    echo -e "   - Protocol       : vmess"
    echo -e "   - Listening IP   : 127.0.0.1"
    echo -e "   - Port           : 10081"
    echo -e "   - Network        : ws"
    echo -e "   - Path           : /vmess-ws"
    echo ""
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "${PURPLE}การใช้งานใน Client (NPV Tunnel / HTTP Custom):${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "• ${YELLOW}NPV Tunnel (VLESS/VMess):${NC} พอร์ต 80 | Path /vless-ws หรือ /vmess-ws"
    echo -e "• ${YELLOW}NPV Tunnel / HTTP Custom (SSH):${NC} พอร์ต 80 | Payload:"
    echo -e "  ${GREEN}GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${NC}"
    echo ""
    echo -e "${CYAN}* คุณสามารถพิมพ์คำสั่ง '${YELLOW}ssh-xui${CYAN}' เพื่อเปิดเมนูจัดการได้ตลอดเวลา${NC}"
    echo ""
    read -p "กด Enter เพื่อกลับสู่เมนูหลัก..." temp
}

# 3. Install All (3-X-UI + SSH WS + Limit System)
install_all() {
    check_root
    echo -e "${GREEN}=== เริ่มต้นติดตั้งทั้ง 3-X-UI และ SSH WS + Limit System ===${NC}"
    echo ""
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) v2.8.9
    install_ssh_ws
}

# 4. Check Status
check_status() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}             ตรวจสอบสถานะการทำงานของระบบ            ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo ""

    # Status of Nginx
    if systemctl is-active --quiet nginx; then
        echo -e "Nginx (Port 80 Proxy)  : ${GREEN}[ กำลังทำงาน - ACTIVE ]${NC}"
    else
        echo -e "Nginx (Port 80 Proxy)  : ${RED}[ ไม่ทำงาน - INACTIVE ]${NC}"
    fi

    # Status of SSH WS
    if systemctl is-active --quiet ssh-ws; then
        echo -e "SSH WebSocket (WS)     : ${GREEN}[ กำลังทำงาน - ACTIVE ]${NC}"
    else
        echo -e "SSH WebSocket (WS)     : ${RED}[ ไม่ทำงาน - INACTIVE ]${NC}"
    fi

    # Status of SSH Limit
    if systemctl is-active --quiet ssh-limit; then
        echo -e "SSH Limit Daemon (IP/GB): ${GREEN}[ กำลังทำงาน - ACTIVE ]${NC}"
    else
        echo -e "SSH Limit Daemon (IP/GB): ${RED}[ ไม่ทำงาน - INACTIVE ]${NC}"
    fi

    # Status of 3-X-UI (x-ui)
    if systemctl is-active --quiet x-ui; then
        echo -e "3-X-UI (Xray Core)     : ${GREEN}[ กำลังทำงาน - ACTIVE ]${NC}"
    else
        echo -e "3-X-UI (Xray Core)     : ${YELLOW}[ ไม่ได้ติดตั้ง หรือ หยุดทำงาน ]${NC}"
    fi

    echo ""
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "${PURPLE}พอร์ตที่กำลังเปิดใช้งาน (Listening Ports):${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn | grep -E ':(80|22|2082|10081|10082|2053|54321)' || echo "ยังไม่พบพอร์ตที่กำหนด"
    fi
    echo ""
    read -p "กด Enter เพื่อกลับสู่เมนูหลัก..." temp
}

# 5. Restart All Services
restart_services() {
    echo -e "${YELLOW}กำลังรีสตาร์ทเซอร์วิสทั้งหมด...${NC}"
    systemctl restart nginx 2>/dev/null || true
    systemctl restart ssh-ws 2>/dev/null || true
    systemctl restart ssh-limit 2>/dev/null || true
    systemctl restart x-ui 2>/dev/null || true
    echo -e "${GREEN}[✓] รีสตาร์ทเรียบร้อยแล้ว!${NC}"
    sleep 2
}

# 6. Uninstall SSH WS & Limit
uninstall_ssh_ws() {
    check_root
    echo -e "${YELLOW}กำลังถอนการติดตั้ง SSH WebSocket และระบบ Limit...${NC}"
    systemctl stop ssh-ws 2>/dev/null || true
    systemctl disable ssh-ws 2>/dev/null || true
    systemctl stop ssh-limit 2>/dev/null || true
    systemctl disable ssh-limit 2>/dev/null || true
    rm -f /etc/systemd/system/ssh-ws.service
    rm -f /etc/systemd/system/ssh-limit.service
    rm -f /usr/local/bin/ssh-ws.py
    rm -f /usr/local/bin/ssh-limit.py
    rm -f /usr/local/bin/ssh-user
    systemctl daemon-reload

    if [ -f /etc/nginx/sites-available/default.bak ]; then
        cp /etc/nginx/sites-available/default.bak /etc/nginx/sites-available/default
        systemctl restart nginx 2>/dev/null || true
    fi

    echo -e "${GREEN}[✓] ถอนการติดตั้งเรียบร้อยแล้ว!${NC}"
    sleep 2
}

# User Management Wrapper
user_manager() {
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${GREEN}             จัดการบัญชีผู้ใช้ SSH (User Admin)       ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e "  ${GREEN}[1]${NC} สร้างบัญชี SSH (กำหนด วัน / GB / Limit IP)"
        echo -e "  ${RED}[2]${NC} ลบบัญชี SSH"
        echo -e "  ${YELLOW}[3]${NC} ต่ออายุบัญชี SSH (วัน / GB / Limit IP)"
        echo -e "  ${CYAN}[4]${NC} ปลดล็อคบัญชี SSH"
        echo -e "  ${PURPLE}[5]${NC} ดูรายชื่อผู้ใช้ทั้งหมด (List Users)"
        echo -e "  ${BLUE}[6]${NC} ตรวจสอบผู้ใช้ออนไลน์ (Online Real-time)"
        echo -e "  ${NC}[0]${NC} กลับสู่เมนูหลัก"
        echo ""
        read -p "เลือกเมนู [0-6]: " uchoice
        case $uchoice in
            1) /usr/local/bin/ssh-user create; read -p "กด Enter เพื่อดำเนินการต่อ..." temp ;;
            2) /usr/local/bin/ssh-user delete; read -p "กด Enter เพื่อดำเนินการต่อ..." temp ;;
            3) /usr/local/bin/ssh-user renew;  read -p "กด Enter เพื่อดำเนินการต่อ..." temp ;;
            4) /usr/local/bin/ssh-user unlock; read -p "กด Enter เพื่อดำเนินการต่อ..." temp ;;
            5) /usr/local/bin/ssh-user list;   read -p "กด Enter เพื่อดำเนินการต่อ..." temp ;;
            6) /usr/local/bin/ssh-user online; read -p "กด Enter เพื่อดำเนินการต่อ..." temp ;;
            0) break ;;
            *) echo -e "${RED}ตัวเลือกไม่ถูกต้อง!${NC}"; sleep 1 ;;
        esac
    done
}

# Main Menu Loop
main_menu() {
    install_shortcut
    while true; do
        show_banner
        echo -e "  ${GREEN}[1]${NC} ติดตั้ง 3-X-UI (v2.8.9)"
        echo -e "  ${GREEN}[2]${NC} ติดตั้ง SSH WebSocket + Limit IP/GB + Nginx (Port 80)"
        echo -e "  ${GREEN}[3]${NC} ติดตั้งทั้งหมด (3-X-UI + SSH WS + ระบบ Limit)"
        echo -e "  ${CYAN}----------------------------------------------------${NC}"
        echo -e "  ${YELLOW}[4]${NC} จัดการบัญชีผู้ใช้ SSH (สร้าง / ลบ / ต่ออายุ)"
        echo -e "  ${YELLOW}[5]${NC} ดูรายชื่อผู้ใช้ทั้งหมด & ข้อมูล GB / วันหมดอายุ"
        echo -e "  ${YELLOW}[6]${NC} ตรวจสอบผู้ใช้ออนไลน์ & IP (Real-time)"
        echo -e "  ${CYAN}----------------------------------------------------${NC}"
        echo -e "  ${CYAN}[7]${NC} ตรวจสอบสถานะระบบ (Services Status)"
        echo -e "  ${PURPLE}[8]${NC} รีสตาร์ทเซอร์วิสทั้งหมด (Restart All)"
        echo -e "  ${RED}[9]${NC} ถอนการติดตั้ง SSH WS & Limit (Uninstall)"
        echo -e "  ${NC}[0]${NC} ออกจากเมนู (Exit)"
        echo ""
        read -p "เลือกเมนู [0-9]: " choice
        case $choice in
            1) install_3xui ;;
            2) install_ssh_ws ;;
            3) install_all ;;
            4) user_manager ;;
            5) /usr/local/bin/ssh-user list 2>/dev/null || echo "กรุณาติดตั้งก่อน"; read -p "กด Enter เพื่อดำเนินการต่อ..." temp ;;
            6) /usr/local/bin/ssh-user online 2>/dev/null || echo "กรุณาติดตั้งก่อน"; read -p "กด Enter เพื่อดำเนินการต่อ..." temp ;;
            7) check_status ;;
            8) restart_services ;;
            9) uninstall_ssh_ws ;;
            0) echo -e "${GREEN}ขอบคุณที่ใช้งานครับ!${NC}"; exit 0 ;;
            *) echo -e "${RED}ตัวเลือกไม่ถูกต้อง! กรุณาลองใหม่${NC}"; sleep 1 ;;
        esac
    done
}

# Run Menu
main_menu
