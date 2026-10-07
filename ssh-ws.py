#!/usr/bin/env python3
# =========================================================
# Project: SSH-WS-3XUI
# Author: EkromSSH
# Script: ssh-ws.py
# Description: Multi-threaded SSH WebSocket Bridge with Real-IP tracking
# =========================================================

import os
import re
import socket
import select
import threading
import sys

LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 2082
SSH_HOST = '127.0.0.1'
SSH_PORT = 22
BUFFER_SIZE = 4096
MAP_DIR = '/run/ssh-ws-ports'

os.makedirs(MAP_DIR, exist_ok=True)

def parse_client_ip(request_bytes):
    try:
        text = request_bytes.decode('utf-8', errors='ignore')
        m = re.search(r'X-Real-IP:\s*([^\r\n]+)', text, re.IGNORECASE)
        if m:
            return m.group(1).strip()
        m = re.search(r'X-Forwarded-For:\s*([^\r\n,]+)', text, re.IGNORECASE)
        if m:
            return m.group(1).strip()
    except Exception:
        pass
    return None

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
    local_port = None
    try:
        request = client_socket.recv(BUFFER_SIZE)
        if not request:
            client_socket.close()
            return

        client_ip = parse_client_ip(request)

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
        local_port = ssh_socket.getsockname()[1]

        if client_ip and local_port:
            port_file = os.path.join(MAP_DIR, str(local_port))
            try:
                with open(port_file, 'w') as f:
                    f.write(client_ip)
            except Exception:
                pass

        forward_sockets(client_socket, ssh_socket)

    except Exception:
        pass
    finally:
        if local_port:
            port_file = os.path.join(MAP_DIR, str(local_port))
            try:
                if os.path.exists(port_file):
                    os.remove(port_file)
            except Exception:
                pass
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
