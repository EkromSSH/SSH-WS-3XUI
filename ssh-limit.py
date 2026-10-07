#!/usr/bin/env python3
# =========================================================
# Project: SSH-WS-3XUI
# Author: EkromSSH
# Daemon: ssh-limit.py
# Description: Automated Limit IP & Limit GB Enforcer for SSH
# =========================================================

import os
import re
import sys
import time
import subprocess
import pwd

DB_FILE = "/etc/ssh/.ssh.db"
MAP_DIR = "/run/ssh-ws-ports"
LOG_FILE = "/var/log/ssh-limit.log"
CHECK_INTERVAL = 10  # Seconds between checks

os.makedirs(MAP_DIR, exist_ok=True)

def log_msg(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{ts}] {msg}\n"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(entry)
    except Exception:
        pass

def get_user_limits():
    """
    Reads /etc/ssh/.ssh.db
    Format: ### <username> <exp_ts> <gb_quota> <max_ip>
    """
    limits = {}
    if not os.path.exists(DB_FILE):
        return limits

    try:
        with open(DB_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("### "):
                    parts = line.split()
                    if len(parts) >= 3:
                        u = parts[1]
                        exp = int(parts[2]) if parts[2].isdigit() else 0
                        gb = int(parts[3]) if len(parts) > 3 and parts[3].isdigit() else 0
                        max_ip = int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else 0
                        limits[u] = {"exp": exp, "gb": gb, "max_ip": max_ip}
    except Exception as e:
        log_msg(f"Error reading DB: {e}")
    return limits

def get_iptables_quota_rules():
    """
    Parses iptables OUTPUT chain for user quota stats
    Returns dict: {uid: {"accept_bytes": int, "quota_bytes": int, "rejected_pkts": int}}
    """
    rules = {}
    try:
        out = subprocess.check_output(["iptables", "-L", "OUTPUT", "-v", "-n", "-x"], text=True)
        for line in out.strip().split("\n"):
            # Check ACCEPT with quota
            if "owner UID match" in line:
                m_uid = re.search(r'owner UID match (\d+)', line)
                if not m_uid:
                    continue
                uid = int(m_uid.group(1))
                parts = line.split()
                if len(parts) < 3:
                    continue
                pkts = int(parts[0])
                bytes_cnt = int(parts[1])

                if "quota:" in line and "ACCEPT" in parts:
                    m_quota = re.search(r'quota:\s*(\d+)', line)
                    q_bytes = int(m_quota.group(1)) if m_quota else 0
                    if uid not in rules:
                        rules[uid] = {"accept_bytes": bytes_cnt, "quota_bytes": q_bytes, "rejected_pkts": 0}
                    else:
                        rules[uid]["accept_bytes"] = bytes_cnt
                        rules[uid]["quota_bytes"] = q_bytes

                elif "REJECT" in parts:
                    if uid not in rules:
                        rules[uid] = {"accept_bytes": 0, "quota_bytes": 0, "rejected_pkts": pkts}
                    else:
                        rules[uid]["rejected_pkts"] = pkts
    except Exception:
        pass
    return rules

def set_user_quota(user, gb):
    """
    Configures kernel iptables quota for user UID
    """
    try:
        uid = pwd.getpwnam(user).pw_uid
    except KeyError:
        return

    # Delete existing rules
    del_user_quota(user)
    if gb <= 0:
        return

    total_bytes = gb * 1024 * 1024 * 1024
    subprocess.run(["iptables", "-A", "OUTPUT", "-m", "owner", "--uid-owner", str(uid), "-m", "quota", "--quota", str(total_bytes), "-j", "ACCEPT"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["iptables", "-A", "OUTPUT", "-m", "owner", "--uid-owner", str(uid), "-j", "REJECT"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def del_user_quota(user):
    try:
        uid = pwd.getpwnam(user).pw_uid
    except KeyError:
        return
    try:
        out = subprocess.check_output(["iptables", "-L", "OUTPUT", "-n", "--line-numbers"], text=True)
        nums = []
        for line in out.split("\n"):
            if f"owner UID match {uid}" in line:
                parts = line.split()
                if parts:
                    nums.append(parts[0])
        for n in reversed(nums):
            subprocess.run(["iptables", "-D", "OUTPUT", n], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def sync_iptables_rules(user_limits, current_rules):
    """
    Ensures iptables quota rules exist for users with gb > 0
    """
    for user, info in user_limits.items():
        if info["gb"] > 0:
            try:
                uid = pwd.getpwnam(user).pw_uid
                if uid not in current_rules or current_rules[uid]["quota_bytes"] == 0:
                    set_user_quota(user, info["gb"])
            except KeyError:
                pass

def get_active_ssh_sessions():
    """
    Inspects all established SSH connections and resolves real client IPs.
    Returns: list of dicts: [{"user": str, "pid": int, "ip": str, "port": str}]
    """
    sessions = []
    try:
        out = subprocess.check_output(["ss", "-tnp", "(", "sport", "=", ":22", ")"], text=True)
        for line in out.strip().split("\n"):
            if "ESTAB" not in line:
                continue

            m = re.search(r'users:\(\("sshd",pid=(\d+)', line)
            if not m:
                continue
            pid = int(m.group(1))

            # Determine authenticated user
            user = None
            try:
                # 1. Check process cmdline or children cmdline
                with open(f"/proc/{pid}/cmdline", "r") as f:
                    cmd = f.read().replace('\x00', ' ')
                m_user = re.search(r'sshd:\s*([a-zA-Z0-9_\-\.]+)', cmd)
                if m_user:
                    u = m_user.group(1).split('@')[0]
                    if u not in ["root", "sshd", "nobody", "daemon", "/usr/sbin/sshd"]:
                        user = u
            except Exception:
                pass

            if not user:
                # Check child processes of sshd
                try:
                    children = subprocess.check_output(["pgrep", "-P", str(pid)], text=True).strip().split()
                    for c in children:
                        u = subprocess.check_output(["ps", "-o", "user=", "-p", str(c)], text=True).strip()
                        if u and u not in ["root", "sshd", "nobody", "daemon"]:
                            user = u
                            break
                except Exception:
                    pass

            if not user:
                continue

            # Determine peer IP
            parts = line.split()
            if len(parts) < 5:
                continue
            peer_addr = parts[4]
            if ":" in peer_addr:
                peer_ip, peer_port = peer_addr.rsplit(":", 1)
            else:
                peer_ip, peer_port = peer_addr, "0"

            client_ip = peer_ip
            if peer_ip in ["127.0.0.1", "::1"]:
                # Look up Real IP from WebSocket map directory
                map_file = os.path.join(MAP_DIR, peer_port)
                if os.path.exists(map_file):
                    try:
                        with open(map_file, "r") as mf:
                            client_ip = mf.read().strip()
                    except Exception:
                        pass

            sessions.append({
                "user": user,
                "pid": pid,
                "ip": client_ip,
                "port": peer_port
            })
    except Exception:
        pass
    return sessions

def enforce_limits():
    user_limits = get_user_limits()
    quota_rules = get_iptables_quota_rules()

    # 1. Sync and check Quota
    sync_iptables_rules(user_limits, quota_rules)

    now_ts = int(time.time())

    for user, info in user_limits.items():
        # Check Expiry
        if info["exp"] > 0 and now_ts > info["exp"]:
            log_msg(f"EXPIRED: User '{user}' has expired. Disabling account.")
            subprocess.run(["usermod", "-L", user], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["pkill", "-u", user], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            del_user_quota(user)
            continue

        # Check Quota Exceeded
        if info["gb"] > 0:
            try:
                uid = pwd.getpwnam(user).pw_uid
                if uid in quota_rules:
                    r = quota_rules[uid]
                    # If REJECT rule received packets or bytes reached/exceeded quota
                    if r["rejected_pkts"] > 0 or (r["quota_bytes"] > 0 and r["accept_bytes"] >= r["quota_bytes"]):
                        log_msg(f"QUOTA-EXCEEDED: User '{user}' exceeded {info['gb']} GB quota. Disabling account.")
                        subprocess.run(["usermod", "-L", user], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        subprocess.run(["pkill", "-u", user], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except KeyError:
                pass

    # 2. Check and Enforce Limit IP
    sessions = get_active_ssh_sessions()
    user_sessions = {}
    for s in sessions:
        user_sessions.setdefault(s["user"], []).append(s)

    for user, s_list in user_sessions.items():
        if user not in user_limits:
            continue
        max_ip = user_limits[user]["max_ip"]
        if max_ip <= 0:
            continue

        # Map unique IPs to their sessions
        ip_map = {}
        for s in s_list:
            ip_map.setdefault(s["ip"], []).append(s)

        unique_ips = list(ip_map.keys())
        if len(unique_ips) > max_ip:
            log_msg(f"LIMIT-IP: User '{user}' exceeded limit ({len(unique_ips)}/{max_ip} IPs: {', '.join(unique_ips)})")
            # Kill excess IP sessions
            excess_ips = unique_ips[max_ip:]
            for ex_ip in excess_ips:
                for s in ip_map[ex_ip]:
                    try:
                        os.kill(s["pid"], 9)
                        log_msg(f"Killed excess session PID {s['pid']} for user '{user}' on IP {ex_ip}")
                    except Exception:
                        pass

def main():
    log_msg("ssh-limit service started successfully.")
    while True:
        try:
            enforce_limits()
        except Exception as e:
            log_msg(f"Error in limit loop: {e}")
        time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    main()
