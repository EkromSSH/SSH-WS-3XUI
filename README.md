# SSH-WS-3XUI

สคริปต์จัดการและติดตั้งระบบ **SSH WebSocket** ร่วมกับ **3-X-UI (VLESS & VMess)** บน **Port 80 เดียวกัน** ผ่าน Nginx Reverse Proxy  
พร้อมระบบ **จำกัด IP (Limit Multi-login)** และ **จำกัดปริมาณเน็ต (Limit Data Quota GB)** สำหรับ SSH  
รองรับแอปพลิเคชัน: **NPV Tunnel (NapsternetV)**, **HTTP Custom**, **HTTP Injector**, **v2rayNG** ฯลฯ

---

## 🚀 คำสั่งติดตั้งและเปิดเมนู (One-Line Installer & Menu)

รันคำสั่งนี้ใน Terminal (สิทธิ์ root):

```bash
bash <(curl -Ls https://raw.githubusercontent.com/EkromSSH/SSH-WS-3XUI/main/install.sh)
```

> **ทิป:** หลังจากรันติดตั้งครั้งแรกแล้ว สามารถพิมพ์คำสั่ง `ssh-xui` ใน Terminal เพื่อเรียกเปิดเมนูจัดการได้ตลอดเวลา!

---

## 📋 หน้าตาเมนูหลัก (Main Menu)

```text
====================================================
      SSH WebSocket + 3-X-UI Manager & Installer    
           Share Port 80 for SSH & Xray             
         Limit IP & Quota (GB) Supported            
                  By EkromSSH                       
====================================================

  [1] ติดตั้ง 3-X-UI (v2.8.9)
  [2] ติดตั้ง SSH WebSocket + Limit IP/GB + Nginx (Port 80)
  [3] ติดตั้งทั้งหมด (3-X-UI + SSH WS + ระบบ Limit)
  ----------------------------------------------------
  [4] จัดการบัญชีผู้ใช้ SSH (สร้าง / ลบ / ต่ออายุ)
  [5] ดูรายชื่อผู้ใช้ทั้งหมด & ข้อมูล GB / วันหมดอายุ
  [6] ตรวจสอบผู้ใช้ออนไลน์ & IP (Real-time)
  ----------------------------------------------------
  [7] ตรวจสอบสถานะระบบ (Services Status)
  [8] รีสตาร์ทเซอร์วิสทั้งหมด (Restart All)
  [9] ถอนการติดตั้ง SSH WS & Limit (Uninstall)
  [0] ออกจากเมนู (Exit)
```

---

## 🛡️ ฟีเจอร์ระบบ Limit IP & Limit GB สำหรับ SSH

1. **ระบบตรวจจับ Real IP ผ่าน WebSocket (Real-IP Mapping):**
   - แก้ปัญหาปกติที่ SSH WS จะเห็น IP เป็น `127.0.0.1` ทั้งหมด
   - สคริปต์จะดึง Real IP จาก HTTP Header ของ Nginx (`X-Real-IP`) ทำให้ระบุ IP จริงของ Client ได้แม่นยำ
2. **จำกัดจำนวน IP (Limit Multi-Login):**
   - กำหนดจำนวนเครื่องสูงสุดที่ล็อกอินพร้อมกันได้ต่อ 1 บัญชี (เช่น ลิมิต 1 IP หรือ 2 IP)
   - หากตรวจพบว่าผู้ใช้เชื่อมต่อเกินจำนวน IP ที่กำหนด ระบบจะตัดเซสชันส่วนเกินออกทันทีแบบอัตโนมัติ
3. **จำกัดปริมาณข้อมูล (Data Quota Limit GB):**
   - ใช้ iptables Quota ระดับเคอร์เนล Linux
   - กำหนดโควต้าเน็ตเป็น GB ได้อย่างแม่นยำ (เช่น 50 GB, 100 GB)
   - เมื่อใช้งานครบโควต้า ระบบจะตัดการเชื่อมต่อและล็อคบัญชีอัตโนมัติ
4. **ตรวจสอบวันหมดอายุ (Auto Expiration):**
   - ตรวจสอบวันหมดอายุแบบ Real-time และล็อคบัญชีที่หมดอายุทันที

---

## ⚙️ คำสั่งจัดการบัญชีผู้ใช้แบบรวดเร็ว (CLI Commands)

นอกจากเปิดผ่านเมนู `ssh-xui` แล้ว คุณยังสามารถใช้คำสั่ง `ssh-user` ได้โดยตรง:

- **สร้างผู้ใช้ใหม่:**
  ```bash
  ssh-user create <user> <pass> <days> <gb> <max_ip>
  # ตัวอย่าง: สร้าง user1 รหัส 1234 อยู่ได้ 30 วัน ลิมิต 50 GB ลิมิต 2 IP
  ssh-user create user1 1234 30 50 2
  ```
- **ลบผู้ใช้:**
  ```bash
  ssh-user delete user1
  ```
- **ต่ออายุผู้ใช้:**
  ```bash
  ssh-user renew user1 30 50 2
  ```
- **ดูรายชื่อและปริมาณ GB ที่ใช้ไป:**
  ```bash
  ssh-user list
  ```
- **ดูผู้ใช้ที่กำลังออนไลน์และ IP จริง:**
  ```bash
  ssh-user online
  ```

---

## ⚙️ การตั้งค่าในแผงควบคุม 3-X-UI (Web Panel)

ไปที่เมนู **Inbounds** $\rightarrow$ กด **+ Add Inbound** จำนวน 2 รายการ:

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

- **NPV Tunnel (VLESS / VMess):** พอร์ต `80` | Path `/vless-ws` หรือ `/vmess-ws`
- **NPV Tunnel / HTTP Custom (SSH):** พอร์ต `80` | Payload:
  ```http
  GET / HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]
  ```
