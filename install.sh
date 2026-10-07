#!/bin/bash
# =========================================================
# Project: SSH-WS-3XUI
# Author: EkromSSH
# Description: SSH WebSocket + 3-X-UI (VLESS & VMess) Port 80
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

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${GREEN}      SSH WebSocket + 3-X-UI Auto Installer         ${NC}"
echo -e "${YELLOW}           Share Port 80 for SSH & Xray             ${NC}"
echo -e "${PURPLE}                  By EkromSSH                       ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo ""

# Check Root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] กรุณารันด้วยสิทธิ์ root (sudo bash)${NC}"
    exit 1
fi

# Check OS (Debian / Ubuntu)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    echo -e "${YELLOW}[WARN] แนะนำให้ใช้งานบน Ubuntu หรือ Debian${NC}"
fi

# 1. Update and install packages
echo -e "${BLUE}[1/4] กำลังติดตั้ง Nginx, Python3 และเครื่องมือจำเป็น...${NC}"
apt-get update -y >/dev/null 2>&1
apt-get install -y nginx python3 curl ufw iptables >/dev/null 2>&1

# 2. Deploy Python SSH WebSocket Service
echo -e "${BLUE}[2/4] กำลังสร้างระบบ SSH WebSocket (Backend Port 2082 -> SSH 22)...${NC}"
cat << 'EOF' > /usr/local/bin/ssh-ws.py
import socket
import select
import threading
import sys

LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 2082
SSH_HOST = '127.0.0.1'
SSH_PORT = 22
BUFFER_SIZE = 4096

def forward_sockets(sock1, sock2):
    sockets = [sock1, sock2]
    try:
        while True:
            r, _, _ = select.select(sockets, [], [], 60)
            if not r:
                continue
            for s in r:
                other = sock2 if s is sock1 else sock1
                data = s.recv(BUFFER_SIZE)
                if not data:
                    return
                other.sendall(data)
    except Exception:
        pass
    finally:
        for s in (sock1, sock2):
            try:
                s.close()
            except Exception:
                pass

def handle_client(client_socket):
    try:
        request = client_socket.recv(BUFFER_SIZE)
        if not request:
            client_socket.close()
            return

        req_lower = request.lower()
        if b"upgrade: websocket" in req_lower or b"http/" in req_lower:
            response = (
                b"HTTP/1.1 101 Switching Protocols\r\n"
                b"Upgrade: websocket\r\n"
                b"Connection: Upgrade\r\n\r\n"
            )
            client_socket.sendall(response)

        ssh_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh_socket.connect((SSH_HOST, SSH_PORT))
        forward_sockets(client_socket, ssh_socket)
    except Exception:
        pass
    finally:
        try:
            client_socket.close()
        except Exception:
            pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(128)
    while True:
        try:
            client, _ = server.accept()
            threading.Thread(target=handle_client, args=(client,), daemon=True).start()
        except KeyboardInterrupt:
            break
        except Exception:
            continue

if __name__ == '__main__':
    main()
EOF

chmod +x /usr/local/bin/ssh-ws.py

# Create systemd service for SSH WS
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

# 3. Configure Nginx Reverse Proxy
echo -e "${BLUE}[3/4] กำลังตั้งค่า Nginx Reverse Proxy สำหรับพอร์ต 80...${NC}"

# Backup old config if exists
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

# Ensure symlink in sites-enabled
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Test Nginx and reload
nginx -t >/dev/null 2>&1
systemctl enable nginx >/dev/null 2>&1
systemctl restart nginx

# 4. Open Port 80 on Firewall if ufw is active
echo -e "${BLUE}[4/4] ตรวจสอบ Firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 22/tcp >/dev/null 2>&1
fi

SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 api.ipify.org || echo "IP_SERVER")

clear
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}          การติดตั้งสำเร็จเรียบร้อยแล้ว!             ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo ""
echo -e "${YELLOW}Server IP:${NC} ${SERVER_IP}"
echo -e "${YELLOW}Main Port:${NC} 80"
echo ""
echo -e "${CYAN}----------------------------------------------------${NC}"
echo -e "${PURPLE}สิ่งที่ต้องตั้งค่าใน 3-X-UI (Web Panel Inbounds):${NC}"
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
echo -e "${CYAN}====================================================${NC}"
