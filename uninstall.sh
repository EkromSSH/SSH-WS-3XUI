#!/bin/bash
# =========================================================
# Project: SSH-WS-3XUI (Uninstaller)
# Author: EkromSSH
# =========================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] กรุณารันด้วยสิทธิ์ root${NC}"
    exit 1
fi

echo -e "${YELLOW}กำลังถอนการติดตั้ง SSH WebSocket และระบบ Limit...${NC}"

# Stop and disable services
systemctl stop ssh-ws 2>/dev/null || true
systemctl disable ssh-ws 2>/dev/null || true
systemctl stop ssh-limit 2>/dev/null || true
systemctl disable ssh-limit 2>/dev/null || true

# Remove binaries and services
rm -f /etc/systemd/system/ssh-ws.service
rm -f /etc/systemd/system/ssh-limit.service
rm -f /usr/local/bin/ssh-ws.py
rm -f /usr/local/bin/ssh-limit.py
rm -f /usr/local/bin/ssh-user
rm -f /usr/bin/ssh-user
rm -f /usr/local/bin/ssh-xui
rm -f /usr/bin/ssh-xui
rm -rf /run/ssh-ws-ports

systemctl daemon-reload

# Restore Nginx backup if exists
if [ -f /etc/nginx/sites-available/default.bak ]; then
    cp /etc/nginx/sites-available/default.bak /etc/nginx/sites-available/default
    systemctl restart nginx 2>/dev/null || true
fi

echo -e "${GREEN}ถอนการติดตั้งเรียบร้อยแล้ว!${NC}"
