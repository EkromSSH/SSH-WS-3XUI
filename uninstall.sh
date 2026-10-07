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

echo -e "${YELLOW}กำลังถอนการติดตั้ง SSH WebSocket และคืนค่า Nginx...${NC}"

# Stop and disable SSH WS service
systemctl stop ssh-ws 2>/dev/null || true
systemctl disable ssh-ws 2>/dev/null || true
rm -f /etc/systemd/system/ssh-ws.service
rm -f /usr/local/bin/ssh-ws.py
systemctl daemon-reload

# Restore Nginx backup if exists
if [ -f /etc/nginx/sites-available/default.bak ]; then
    cp /etc/nginx/sites-available/default.bak /etc/nginx/sites-available/default
    systemctl restart nginx 2>/dev/null || true
fi

echo -e "${GREEN}ถอนการติดตั้งเรียบร้อยแล้ว!${NC}"
