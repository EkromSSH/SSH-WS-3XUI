# SSH-WS-3XUI

สคริปต์จัดการและติดตั้งระบบ **SSH WebSocket** ร่วมกับ **3-X-UI (VLESS & VMess)** บน **Port 80 เดียวกัน** ผ่าน Nginx Reverse Proxy  
รองรับแอปพลิเคชันยอดนิยม: **NPV Tunnel (NapsternetV)**, **HTTP Custom**, **HTTP Injector**, **v2rayNG** ฯลฯ

---

## 🚀 คำสั่งติดตั้งและเปิดเมนู (One-Line Installer & Menu)

รันคำสั่งนี้ใน Terminal (สิทธิ์ root):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/EkromSSH/SSH-WS-3XUI/main/install.sh)
```

> **ทิป:** หลังจากรันครั้งแรกแล้ว คุณสามารถพิมพ์คำสั่ง `ssh-xui` ใน Terminal เพื่อเปิดเมนูจัดการได้ตลอดเวลา!

---

## 📋 ฟังก์ชันในเมนู (Menu Features)

```text
====================================================
      SSH WebSocket + 3-X-UI Manager & Installer    
           Share Port 80 for SSH & Xray             
                  By EkromSSH                       
====================================================

  [1] ติดตั้ง 3-X-UI (v2.8.9)
  [2] ติดตั้ง SSH WebSocket + Nginx Proxy (Port 80)
  [3] ติดตั้งทั้งหมด (3-X-UI + SSH WS + Nginx)
  [4] ตรวจสอบสถานะระบบ (Services Status)
  [5] รีสตาร์ทเซอร์วิสทั้งหมด (Restart All)
  [6] ถอนการติดตั้ง SSH WS (Uninstall)
  [0] ออกจากเมนู (Exit)
```

---

## 📌 แผนผังการทำงาน (Architecture)

```text
[ Client (NPV Tunnel / HTTP Custom / v2rayNG) ]
                       │
                       │ เชื่อมต่อเข้ามาที่ Port 80
                       ▼
               [ Nginx Proxy:80 ]
       ┌───────────────┼───────────────┐
 (Path: /vless-ws) (Path: /vmess-ws) (Path: / หรือ /ssh)
       │               │               │
       ▼               ▼               ▼
[3-X-UI: VLESS] [3-X-UI: VMess] [Python SSH-WS]
(127.0.0.1:10082) (127.0.0.1:10081) (127.0.0.1:2082)
                                       │
                                       ▼
                                 [SSH Port 22]
```

---

## ⚙️ การตั้งค่าในแผงควบคุม 3-X-UI (Web Panel)

หลังจากติดตั้งแล้ว ให้เข้าไปที่หน้าเว็บจัดการของ 3-X-UI (พอร์ต `2053` หรือพอร์ตที่คุณตั้งไว้) $\rightarrow$ ไปที่เมนู **Inbounds** $\rightarrow$ กด **+ Add Inbound** จำนวน 2 รายการ:

### 1. Inbound สำหรับ VLESS
- **Remark**: `VLESS-WS-80`
- **Protocol**: `vless`
- **Listening IP**: `127.0.0.1`
- **Port**: `10082`
- **Transmission (Network)**: `ws`
- **Path**: `/vless-ws`

### 2. Inbound สำหรับ VMess
- **Remark**: `VMESS-WS-80`
- **Protocol**: `vmess`
- **Listening IP**: `127.0.0.1`
- **Port**: `10081`
- **Transmission (Network)**: `ws`
- **Path**: `/vmess-ws`

---

## 📱 การตั้งค่าใน Client แอปต่างๆ

### 1. NPV Tunnel (NapsternetV)
- **VLESS / VMess**:
  - สแกน QR Code หรือนำเข้าลิงก์จาก 3-X-UI
  - ตรวจสอบ Port เป็น `80`
  - ตรวจสอบ Network เป็น `WebSocket` และ Path เป็น `/vless-ws` หรือ `/vmess-ws`
- **SSH WebSocket**:
  - เลือกประเภทโปรไฟล์เป็น **SSH**
  - **Host**: IP หรือ โดเมนของเซิร์ฟเวอร์
  - **Port**: `80`
  - **WS Path**: `/`
  - **Payload**:
    ```http
    GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
    ```

### 2. HTTP Custom / HTTP Injector (สำหรับ SSH)
- **SSH Host**: IP ของเซิร์ฟเวอร์
- **SSH Port**: `80`
- **Username & Password**: บัญชี SSH ของคุณ
- **Payload**:
  ```http
  GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
  ```

---

## 🛠️ คำสั่งลัด (Shortcut Command)

เมื่อติดตั้งแล้ว สามารถพิมพ์คำสั่งนี้ใน Terminal เพื่อเรียกเมนูจัดการได้ทันที:
```bash
ssh-xui
```
