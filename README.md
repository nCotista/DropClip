# DropClip (v1.0 — Full Release)

> **DropClip: A Desktop-First Peer-to-Peer Clipboard Continuity and High-Throughput File Transfer System for Heterogeneous Personal Device Clusters**  
> *ดรอปคลิป: ระบบเชื่อมต่อคลิปบอร์ดและถ่ายโอนไฟล์ความเร็วสูงแบบ Peer-to-Peer บนเครือข่ายท้องถิ่น สำหรับคลัสเตอร์อุปกรณ์ส่วนบุคคลแบบข้ามแพลตฟอร์ม (macOS, Windows, Android, iOS)*

[![Project Status](https://img.shields.io/badge/Tickets-34%2F34%20DONE%20(100%25)-brightgreen)](#)
[![Release Gates](https://img.shields.io/badge/Release%20Gates-GATE--1..4%20PASSED-blue)](#)
[![Architecture](https://img.shields.io/badge/Zero--Cloud-100%25%20Local%20LAN%20P2P-6366F1)](#)
[![Security](https://img.shields.io/badge/TLS%201.3-ECDSA%20P--256%20%2B%20Zero--PIN--on--Wire%20SAS-06B6D4)](#)

👉 **สำหรับผู้ทดสอบที่ไม่ใช่โปรแกรมเมอร์ (Non-Coder Tester):** สามารถอ่านคู่มือกดทดสอบทีละขั้นตอนได้ที่ [**ส่วนที่ 5 ของหน้านี้**](#5-คู่มือการทดสอบใช้งานจริงสำหรับผู้ใช้งานทั่วไปแบบไม่ต้องเขียนโค้ด-non-coder-testing-manual) หรือเปิดคู่มือฉบับเต็มได้ที่ [**`docs/06-USER-AND-TESTING-MANUAL.md`**](docs/06-USER-AND-TESTING-MANUAL.md)  
👉 **กระดานติดตามความคืบหน้าโครงการ (100% Complete):** [**`docs/TASK-PROGRESS-AND-UPDATES.md`**](docs/TASK-PROGRESS-AND-UPDATES.md)

---

## 1. ภาพรวมโครงการและระดับขีดความสามารถ (Overview & Capability Tiers)

**DropClip** คือสะพานเชื่อมความต่อเนื่องของอุปกรณ์ส่วนบุคคล (Personal Device Continuity Bridge) ที่ทำงานบนเครือข่ายท้องถิ่น (LAN / Wi-Fi) แบบ **Peer-to-Peer (P2P) 100% ไร้เซิร์ฟเวอร์กลาง (Zero-Cloud & Serverless)** ไม่ต้องใช้อินเทอร์เน็ต ไม่ต้องพึ่งพา Cloud Relay (ไม่มี TURN/STUN) และไม่ต้องสมัครบัญชีผู้ใช้ โดยออกแบบภายใต้หลักการความซื่อสัตย์ต่อข้อจำกัดของระบบปฏิบัติการ (**Platform-Constrained Honesty**):

| ระดับ (Tier) | แพลตฟอร์ม | โหมดการซิงก์คลิปบอร์ด (Clipboard Sync Mode) | ขีดความสามารถด้านการถ่ายโอนไฟล์ (File Transfer) |
|---|---|---|---|
| **Tier 1 — Full Passive** | **macOS 12+**<br>**Windows 10/11** | **อัตโนมัติเต็มรูปแบบ (Zero-Interaction)** สองทิศทางในเบื้องหลัง (`p95 < 1,000 ms`) พร้อมตรวจจับและบล็อกข้อมูลจาก Password Manager 100% | เต็มรูปแบบ (Streaming `1 MiB` chunks บน TLS 1.3, ควบคุม Delta RSS $\le 50\text{ MB}$, ส่งต่อจากจุดที่ค้าง `.part` ได้ทุก `64 MiB`) |
| **Tier 2 — Assisted** | **Android 10+** (API 29–35) | **Desktop → Android:** เขียนคลิปบอร์ดอัตโนมัติผ่าน Foreground Service พร้อม Notification & Toast<br>**Android → Desktop:** สั่งส่งใน 1 คลิกผ่าน **Quick Settings Tile** หรือปุ่มลัดใน Notification (`< 500 ms`) | เต็มรูปแบบ (บันทึกและอ่านผ่าน `MediaStore` & Scoped Storage โดยไม่ต้องขอสิทธิ์ `MANAGE_EXTERNAL_STORAGE`) |
| **Tier 3 — Manual-Assist** | **iOS 15+** | สั่งส่งและรับผ่าน **Share Sheet Extension**, **Home/Lock Screen Widgets**, **App Shortcuts** และ **Action Button** | เต็มรูปแบบผ่าน Background `URLSession` (`Peak RSS < 30 MB` ใน Share Extension) และ `PhotoKit` (Add-Only) |

---

## 2. จุดเด่นด้านสถาปัตยกรรมและความปลอดภัย (Key Security & Protocol Invariants)

1. **TLS 1.3 + ECDSA P-256 & OS Envelope Encryption (`T1.2`, `T1.4`):**
   - ทุกการเชื่อมต่อเข้ารหัสด้วย **TLS 1.3** พร้อมใบรับรอง Self-Signed **ECDSA P-256 (`secp256r1`)** และการปักหมุดลายนิ้วมือใบรับรอง (**SPKI SHA-256 Pinning**)
   - กุญแจส่วนตัวถูกเข้ารหัสซ้อน (Envelope Encryption) ด้วยคลังนิรภัยของระบบปฏิบัติการ (macOS Keychain, Windows DPAPI, Android Keystore, iOS Keychain)
2. **Commit-then-Reveal & Zero-PIN-on-Wire SAS Pairing (`T1.3`, `ADR-009`):**
   - ป้องกันการโจมตีแบบ Active MITM ด้วยการส่งค่าผูกมัด $C_B = \text{SHA-256}(\text{"dropclip-commit-v1:"} \parallel N_B \parallel \text{fp}_B)$ ก่อนเปิดเผย Nonce
   - **Zero-PIN-on-Wire:** ในโหมดจับคู่ด้วยรหัส PIN 6 หลัก **จะไม่มีการส่งรหัส PIN หรือค่าแฮชของ PIN ผ่านเครือข่ายเด็ดขาด** แต่ใช้เป็นค่าเกลือ (Out-of-Band Salt) เพื่อคำนวณรหัสยืนยันตัวตน **SAS 6 หลัก** บนเครื่องของแต่ละฝ่าย (Test Vector มาตรฐาน: PIN `123456` $\rightarrow$ SAS `639589`, โหมด QR $\rightarrow$ SAS `337017`)
3. **Sensitive Content Suppression 100% (`NFR-S04`, `T1.6`–`T1.8`):**
   - ดักจับและระงับการส่งข้อมูลจากโปรแกรมจัดการรหัสผ่าน (เช่น 1Password, Bitwarden, Keychain) ทันทีเมื่อพบป้ายกำกับของระบบปฏิบัติการทั้ง 5 ชนิด (`ConcealedType`, `TransientType`, `ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory=0`, `EXTRA_IS_SENSITIVE`)
4. **HLC Conflict Resolution & Anti-Echo Suppression (`T1.9`):**
   - ใช้ **Hybrid Logical Clock (HLC)** ร่วมกับ `origin_device_id` เพื่อตัดสินลำดับเหตุการณ์อย่างเที่ยงตรงแม้นาฬิกาเครื่องคลาดเคลื่อน และป้องกันการเกิดลูปสะท้อนกลับ (Echo Loop) ด้วยตาราง `lastWrittenHash`
5. **Streaming 1 MiB File Engine & 64 MiB Resumable Checkpoints (`T1.10`, `T1.11`):**
   - ห้ามโหลดไฟล์ทั้งก้อนเข้าสู่ RAM (`NO Whole-File RAM Buffering`) — ส่งและรับข้อมูลทีละ `1 MiB` พร้อมตรวจสอบ SHA-256 รายชิ้นและทั้งไฟล์
   - บันทึกจุดเช็คพอยต์ลง `transfers.json` ทุกๆ `64 MiB` หากสายหลุดหรือ Wi-Fi ตัด สามารถตรวจสอบ `.part` และส่งต่อจากจุดเดิมได้ทันที (Resume)
6. **Quarantine-then-Confirm Revocation (`T1.12`, `SRS FR-11`):**
   - ป้องกันไม่ให้อุปกรณ์ที่ถูกขโมยสั่งเพิกถอนเครื่องอื่นโดยพลการ ด้วยการกักกัน (`QUARANTINED`) รอให้เจ้าของเครื่องกดยืนยัน (`Confirm Revoke`) หรือปฏิเสธเพื่อกู้คืน (`Restore Peer`)

---

## 3. โครงสร้าง Monorepo Workspace (ADR-005)

```text
DropClip/
├── docs/                                    # เอกสารข้อกำหนด สถาปัตยกรรม คู่มือทดสอบ และบันทึกความคืบหน้า
│   ├── 00-PROJECT-PROPOSAL-AND-PLAYBOOK.md  # Proposal, Engineering Playbook & ADRs (v2.0)
│   ├── 01-PROTOCOL-SPEC.md                  # ข้อกำหนด Wire Protocol Spec ฉบับสมบูรณ์ (v2.0)
│   ├── 02-TICKETS.md                        # รายการ Task Tickets 34 รายการ, DoR/DoD และตาราง RTM
│   ├── 03-SRS.md                            # ข้อกำหนดความต้องการซอฟต์แวร์ (SRS-DC-V1.2)
│   ├── 04-THREAT-MODEL.md                   # การวิเคราะห์ภัยคุกคาม STRIDE, Attack Trees & CVSS v3.1
│   ├── 05-RELEASE-AND-UPDATE-PLAN.md        # แผนการปล่อยรุ่นและการอัปเดตแบบ Roll-Forward
│   ├── 06-USER-AND-TESTING-MANUAL.md        # คู่มือการใช้งานและทดสอบทีละขั้นตอนสำหรับผู้ที่ไม่ใช่โปรแกรมเมอร์
│   ├── TASK-PROGRESS-AND-UPDATES.md         # กระดานสถานะงานส่วนกลาง (34/34 Tickets — 100% DONE)
│   └── worklogs/                            # บันทึกรายละเอียดการทำงานและหลักฐานการทดสอบของแต่ละ Ticket
│
├── packages/                                # โมดูล Core Libraries ที่แชร์ร่วมกัน
│   ├── dropclip_protocol/                   # Message Envelopes, SAS Generator, HLC, Path Sanitizer
│   ├── dropclip_core/                       # TLS 1.3 Server/Pinned Client, Control Plane WS, Pairing, QA Gates
│   ├── dropclip_clipboard/                  # Clipboard Sync Engine, Transport Adapter, PNG Normalizer
│   ├── dropclip_transfer/                   # 1 MiB Streaming File Engine, 64 MiB Resumable Checkpoint Store
│   ├── dropclip_ui/                         # Design System Widgets, Dark/Light Theme Tokens
│   ├── dropclip_macos/                      # macOS Native Clipboard Plugin Bridge
│   └── dropclip_windows/                    # Windows Native C++ Win32 Clipboard Plugin Bridge
│
├── apps/                                    # แอปพลิเคชันปลายทางพร้อมใช้งาน
│   ├── desktop/                             # Flutter Desktop (macOS & Windows): Clipboard, Dropzone, Transfers, Devices, Settings
│   └── mobile/                              # Flutter Mobile (Android & iOS): Pairing, QS Tile, Clipboard, Resumable Transfers
│
├── native/                                  # Native Bridge & Platform Extensions
│   ├── macos/                               # Swift NSPasteboard Adaptive Watcher &ConcealedType Suppression
│   ├── windows/                             # C++ Win32 AddClipboardFormatListener & Cloud/History Suppression
│   ├── android/                             # Kotlin Foreground Service, Quick Settings Tile, MediaStore
│   └── ios/                                 # Swift Share Sheet Extension (< 30 MB Peak RSS) & PhotoKit
│
└── tools/                                   # เครื่องมือทดสอบและวัดประสิทธิภาพ
    ├── protocol_fuzzer/                     # Fuzzer ทดสอบความทนทานของ Protocol Parser (10,000+ inputs)
    ├── bench/                               # ชุดวัดความหน่วงและหน่วยความจำอัตโนมัติ
    └── s02_receiver/                        # ตัวรับไฟล์สตรีมมิ่งสำหรับทดสอบไฟล์ขนาดใหญ่ 4 GiB
```

---

## 4. ทีมพัฒนาและความรับผิดชอบ (Team Roles)

| ลำดับ | สมาชิกในทีม | Role Code | หน้าที่รับผิดชอบหลัก (Primary Responsibilities) |
|:---:|---|:---:|---|
| **1** | **นายธนกฤต บุญญาวรกุล (เจ)** | `LEAD` | Team Lead, Protocol Architecture, Security & Pairing Engine (`T0.2`, `T1.2`, `T1.3`), macOS Native (`T1.6`), Code Signing |
| **2** | **นายณัฐธีร์ อโณทัยไพบูลย์ (ธีร์)** | `DESK` | Desktop mDNS Discovery (`T1.1`), Tier 1 Clipboard Sync Engine (`T1.9`), Desktop UI, Dropzone & System Tray (`T1.12`) |
| **3** | **นายเกื้ออนันต์ พวงนิลน้อย (เกื้อ)** | `MOB` | Mobile Background Spike (`S0.2`), Android Tier 2 Service & QS Tile (`T2.1`–`T2.5`), iOS Tier 3 Share Extension & Widgets (`T3.1`–`T3.4`) |
| **4** | **นายปัณณ์ ศรีเจริญชัยกุล (ปัน)** | `NET` | TLS 1.3 Transport (`T1.4`), WebSocket Control Plane (`T1.5`), Windows Native (`T1.7`), Image Normalizer (`T1.8`), Streaming File Engine (`T1.10`, `T1.11`) |
| **5** | **นายปรมินทร์ มุขอาษา (ตามด)** | `QA` | Structured Logger (`T0.3`), Protocol Fuzzer (`T4.2`), Benchmark & Chaos Soak Verification (`T4.1`, `T4.3`), Usability & SUS Study (`T4.4`) |

---

## 5. คู่มือการทดสอบใช้งานจริงสำหรับผู้ใช้งานทั่วไปแบบไม่ต้องเขียนโค้ด (Non-Coder Testing Manual)

ส่วนนี้เขียนขึ้นเพื่อให้ **ผู้ตรวจรับงาน อาจารย์ที่ปรึกษา หรือผู้ทดสอบทั่วไปที่ไม่ใช่โปรแกรมเมอร์** สามารถเปิดโปรแกรมและกดทดสอบทุกฟีเจอร์ได้ด้วยตนเองอย่างมั่นใจ (ดูรายละเอียดฉบับเต็มเพิ่มเติมได้ที่ [**`docs/06-USER-AND-TESTING-MANUAL.md`**](docs/06-USER-AND-TESTING-MANUAL.md)):

### ขั้นตอนที่ 1: เตรียมความพร้อมก่อนเปิดโปรแกรม (ทำครั้งเดียว)
เปิดโปรแกรม **Terminal** (บน Mac กด `⌘ + Space` พิมพ์ `Terminal`) หรือ **PowerShell** (บน Windows) แล้วคัดลอกคำสั่งนี้ไปวางแล้วกด `Enter`:

```bash
# เข้าไปยังโฟลเดอร์โปรเจกต์ DropClip แล้วติดตั้งไลบรารีทั้งหมดอัตโนมัติ
melos bootstrap
```

### ขั้นตอนที่ 2: เปิดหน้าต่างโปรแกรมขึ้นมาทดสอบ
คุณสามารถเปิดทดสอบทั้งแอป **Desktop** และแอป **Mobile** บนเครื่องคอมพิวเตอร์เครื่องเดียวกัน (เปิด 2 หน้าต่างคู่กัน) หรือรันบนมือถือจริงได้ทันที:

- **เปิดแอปฝั่งคอมพิวเตอร์ (Desktop):**
  ```bash
  cd apps/desktop
  flutter run -d macos      # บนเครื่อง Mac (หรือใช้ flutter run -d windows บนเครื่อง Windows)
  ```
- **เปิดแอปฝั่งมือถือ (Mobile — เปิดใน Terminal อีกหน้าต่างหนึ่ง):**
  ```bash
  cd apps/mobile
  flutter run               # รันบนมือถือ/จำลองที่เชื่อมต่ออยู่ (หรือใช้ flutter run -d macos เพื่อเปิดเป็นหน้าต่างที่ 2 บน Mac)
  ```

---

### ขั้นตอนที่ 3: รายการกดทดสอบ 7 ฟีเจอร์หลัก (Checklist กดตามได้ทีละข้อ)

| ลำดับ | ฟีเจอร์ที่ต้องการทดสอบ | วิธีดำเนินการกดบนหน้าจอ (Step-by-Step Action) | ผลลัพธ์ที่ถูกต้องซึ่งต้องปรากฏบนหน้าจอ (Expected Result) |
|:---:|---|---|---|
| **1** | **จับคู่อุปกรณ์และตรวจรหัส SAS 6 หลัก**<br>*(Zero-PIN-on-Wire Pairing — `T1.3`)* | 1. บน **Desktop**: คลิกเมนู **`Devices`** ทางซ้าย ดูช่อง PIN (`123456`)<br>2. บน **Mobile**: แตะแท็บ **`Devices`** ด้านล่าง ดูช่อง PIN (`123456`) แล้วกดปุ่ม **`Pair & Compute SAS`**<br>3. กดปุ่ม **`Confirm SAS Match`** บน Desktop | ทั้งหน้าจอ Desktop และ Mobile แสดงรหัส **`SAS: 639589`** ตรงกันทุกหลัก และเมื่อกดยืนยันจะขึ้นข้อความสีเขียว *"Peer pinned in Trusted Peer Store"* |
| **2** | **ส่งข้อความและลิงก์ข้ามเครื่อง**<br>*(Clipboard Sync — `T1.9`, `T2.2`, `T2.3`)* | 1. บน **Desktop** (เมนู `Clipboard`): คัดลอกข้อความใดๆ แล้วกดปุ่ม **`Send clipboard`** ด้านบน<br>2. ลองกดปุ่มกรอง **`Links` / `Text`** หรือพิมพ์ในช่องค้นหา<br>3. บน **Mobile** (แท็บ `Clipboard`): พิมพ์ข้อความแล้วกด **`Send to Cluster`** หรือกด **`Simulate Inbound Clip`** | ข้อความปรากฏเป็นรายการแรกสุดในประวัติทันที, ค้นหาและกรองตามชนิดได้, กดคัดลอกซ้ำขึ้นแจ้งเตือน *"Copied to clipboard"* |
| **3** | **บล็อกรหัสผ่านไม่ให้หลุดออกจากเครื่อง**<br>*(Sensitive Suppression — `NFR-S04`)* | 1. บน **Desktop** (เมนู `Clipboard`): ดูกล่องแจ้งเตือนรูปแม่กุญแจด้านล่างสุด<br>2. บน **Mobile** (แท็บ `Clipboard`): เปิดสวิตช์ **`Mark as Sensitive (Password Manager / Concealed)`** แล้วกด **`Send to Cluster`** | บน Mobile ขึ้นแถบเตือนสีแดง **`Suppressed sensitive clipboard item (NFR-S04)`** และไม่ส่งข้อมูลรหัสผ่านออกไปเด็ดขาด |
| **4** | **ลากไฟล์ส่งผ่านหน้าต่างลอย Dropzone**<br>*(1 MiB Streaming Transfer — `T1.10`, `UI-02`)* | 1. บน **Desktop**: กดคีย์ลัด **`⌥⌘D`** (Mac) หรือ **`Ctrl+Alt+D`** (Windows) หรือคลิกการ์ด **`Drop files to send`**<br>2. ลากไฟล์มาวาง เลือกอุปกรณ์แล้วกดส่ง หรือไปที่เมนู **`Transfers`** แล้วกดปุ่ม **`Stream Sample File (1 MiB Chunks)`** | รายการไฟล์ปรากฏขึ้นในหน้า **`Transfers`** พร้อมแถบความคืบหน้า **`100% · SHA-256 Verified`** |
| **5** | **ส่งไฟล์ขนาดใหญ่ต่อจากจุดที่ค้าง (`.part`)**<br>*(Resumable Transfer — `T1.11`)* | 1. บน **Desktop**: ไปที่เมนู **`Transfers`** ดูรายการ `4K-Demo-Recording.mp4.part` (ค้างอยู่ที่ 50%) แล้วคลิกปุ่ม **`Resume .part (T1.11)`**<br>2. บน **Mobile**: ไปที่แท็บ **`Transfers`** แล้วกดปุ่ม **`Resume Interrupted .part`** | แถบสถานะวิ่งต่อจาก **50% ไปจนถึง 100%** ทันทีโดยไม่ต้องเริ่มส่งใหม่ตั้งแต่ต้น และเปลี่ยนสถานะเป็น **`SHA-256 Verified`** |
| **6** | **กักกันและเพิกถอนอุปกรณ์ที่สูญหาย**<br>*(Quarantine-then-Confirm — `T1.12`)* | 1. บน **Desktop** (เมนู `Devices`) หรือ **Mobile** (แท็บ `Devices`): ดูรายชื่ออุปกรณ์ที่เชื่อถือ<br>2. กดปุ่ม **`Quarantine`** เพื่อกักกัน แล้วทดลองกด **`Confirm Revoke`** (เพิกถอนถาวร) หรือ **`Restore Peer`** (คืนสิทธิ์) | สถานะอุปกรณ์เปลี่ยนจาก `TRUSTED` $\rightarrow$ `QUARANTINED` และเลือกยืนยันเป็น `REVOKED` หรือกู้คืนเป็น `TRUSTED` ได้อย่างปลอดภัย |
| **7** | **สลับภาษา ไทย/อังกฤษ ทันที & ตรวจ Log**<br>*(Live Localization & Privacy Log — `FR-12`, `T0.3`)* | 1. บน **Desktop**: คลิกเมนู **`Settings`** ทางซ้าย แล้วสลับภาษาระหว่าง **`English`** กับ **`ไทย`**<br>2. กดคีย์ลัด **`⌘⇧D`** (Mac) หรือ **`Ctrl+Shift+D`** (Windows) เพื่อเปิด **Debug Console** | หน้าจอทั้งหมดเปลี่ยนเป็นภาษาไทย/อังกฤษทันทีโดยไม่ต้องปิดเปิดแอปใหม่ และใน Debug Console ไม่มีเนื้อหาคลิปบอร์ดหรือรหัสผ่านรั่วไหล |

---

## 6. คำสั่งสำหรับนักพัฒนาและการตรวจสอบคุณภาพโค้ด (Developer & CI Commands)

```bash
# 1. ติดตั้ง dependencies ข้ามทุกแพ็กเกจใน Monorepo
melos bootstrap

# 2. ตรวจสอบการจัดรูปแบบโค้ด (Formatting)
melos run format

# 3. ตรวจสอบคุณภาพโค้ดและ Lint rules (ต้องรายงาน 0 issues)
melos run analyze

# 4. รันชุดทดสอบ Unit และ Widget Tests ทั้งหมด
melos run test

# 5. รันชุดทดสอบพร้อมคำนวณ Code Coverage (เกณฑ์ขั้นต่ำ >= 75%)
melos run test:coverage
```

---

## 7. กฎระเบียบและแนวทางการส่งงาน (Contribution & Branching)
โปรดอ่านรายละเอียดใน [`CONTRIBUTING.md`](CONTRIBUTING.md) และ [`AGENTS.md`](AGENTS.md) สำหรับกฎเหล็ก 6 ข้อของโครงการและขั้นตอนการอัปเดตสถานะงานบนกิ่ง `docs/task-progress-tracker`
