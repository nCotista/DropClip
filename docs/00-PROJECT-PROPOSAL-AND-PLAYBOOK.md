# DropClip — Project Proposal & Engineering Playbook
**Version:** 2.0 | **Status:** Draft / Under Review | **Owner:** Team Lead

---

# PART I — PROJECT PROPOSAL

## 1. ข้อมูลพื้นฐานโครงการ

**ชื่อภาษาอังกฤษ:** DropClip: A Desktop-First Peer-to-Peer Clipboard Continuity and High-Throughput File Transfer System for Heterogeneous Personal Device Clusters

**ชื่อภาษาไทย:** ดรอปคลิป: ระบบเชื่อมต่อคลิปบอร์ดและถ่ายโอนไฟล์ความเร็วสูงแบบ Peer-to-Peer บนเครือข่ายท้องถิ่น สำหรับคลัสเตอร์อุปกรณ์ส่วนบุคคลแบบข้ามแพลตฟอร์ม

**ชื่อซอฟต์แวร์:** DropClip

**คำนิยามสั้น:** สะพานเชื่อมความต่อเนื่องของอุปกรณ์ส่วนบุคคล (Personal Device Continuity Bridge) ทำงานบน LAN แบบ P2P 100% ไม่มี Cloud Server ไม่ต้องต่ออินเทอร์เน็ต ไม่ต้องล็อกอิน ให้ประสบการณ์ Passive Sync เต็มรูปแบบบน Desktop และ Assisted Sync บนอุปกรณ์พกพาตามข้อจำกัดของแต่ละ OS

---

## 2. ที่มา ปัญหา และแรงจูงใจ

### 2.1 ปัญหาหลัก

- **Ecosystem Fragmentation** — Universal Clipboard และ AirDrop ผูกกับ Apple ecosystem เท่านั้น ผู้ใช้ iPhone + Windows PC หรือ Android + Mac ไม่มีทางเลือกระดับเดียวกัน
- **Workaround Friction** — พฤติกรรม "ส่งแชตหาตัวเอง" หรืออัปโหลด Cloud สร้างต้นทุนแฝง 4 ด้าน

| ต้นทุนแฝง | รายละเอียด |
|---|---|
| ขั้นตอนซ้ำซ้อน | Copy → เปิดแอป → วาง → ส่ง → เปิดอีกเครื่อง → Copy/โหลด = 5–6 ขั้นตอน |
| คอขวดแบนด์วิดท์ | ข้อมูลวิ่งออกอินเทอร์เน็ต จำกัดตาม Upload Speed ทั้งที่เครื่องวางติดกัน |
| คุณภาพถูกลดทอน | ภาพ/วิดีโอถูก re-encode เสียความละเอียดต้นฉบับ |
| ความเสี่ยงข้อมูล | OTP, รหัสผ่าน, เอกสารสำคัญ ผ่าน Third-Party Server |

### 2.2 ช่องว่างของเครื่องมือปัจจุบัน

- **กลุ่มส่งไฟล์ (LocalSend)** — ดีสำหรับ Any-to-Any แต่ต้องเปิดแอปสองฝั่งและกดยืนยันทุกครั้ง ไม่มี Clipboard Watcher
- **กลุ่มเชื่อมอุปกรณ์ (KDE Connect)** — ฟีเจอร์กว้างที่สุด แต่เป็น Linux-first คุณภาพ UX บน macOS/Windows ยังไม่เทียบ native และ clipboard sync ต้องกดจาก Notification

**ช่องว่างที่ DropClip ปิด:** Passive Clipboard Sync ระดับ native บนแกน **macOS ↔ Windows** พร้อมส่วนขยายไปมือถือเท่าที่ OS อนุญาต

### 2.3 แรงจูงใจ

สร้าง Personal Continuity System ที่ **ซื่อสัตย์ต่อข้อจำกัดของแพลตฟอร์ม** — ให้ประสบการณ์ดีที่สุดเท่าที่แต่ละ OS อนุญาต แทนการสัญญาสิ่งที่ทำไม่ได้จริงแล้วส่งมอบของครึ่ง ๆ กลาง ๆ ทั้งสี่แพลตฟอร์ม

---

## 3. การวิเคราะห์คู่แข่ง

| ความสามารถ | Apple Universal Clipboard | LocalSend | KDE Connect | ClipCascade | **DropClip** |
|---|---|---|---|---|---|
| ครอบคลุม macOS + Windows | ✗ | ✓ | ~ | ✓ | **✓ Native** |
| Passive Clipboard Sync (Desktop) | ✓ (Apple only) | ✗ | ~ | ✓ | **✓** |
| Clipboard รูปภาพข้าม OS | ✓ (Apple only) | ✗ | ✗ | ✗ | **✓ Normalizer** |
| ถ่ายโอนไฟล์ P2P ไม่จำกัดขนาด | ✗ | ✓ | ✓ | ✗ | **✓** |
| Auto-Accept สำหรับเครื่องตัวเอง | ✓ | ✗ | ~ | — | **✓** |
| ไม่ต้องล็อกอิน / ไม่มี Cloud | ✗ | ✓ | ✓ | ~ | **✓** |
| กรองข้อมูลอ่อนไหวอัตโนมัติ | ✗ | — | ✗ | ✗ | **✓** |
| iOS Support | ✓ | ✓ | ~ | ✗ | ~ (Assisted) |

**จุดยืน:** ไม่แข่งที่ฟีเจอร์เยอะสุด แต่แข่งที่คุณภาพ Clipboard Continuity บนแกน macOS ↔ Windows + นวัตกรรมเฉพาะ 2 อย่าง คือ Cross-OS Image Format Normalizer และ Sensitive-Content Filtering

---

## 4. Product Positioning & Capability Tier

| Tier | แพลตฟอร์ม | Clipboard Sync | เหตุผลเชิงเทคนิค |
|---|---|---|---|
| **Tier 1 — Full Passive** | macOS, Windows | อัตโนมัติสองทาง p95 < 1s | OS อนุญาต background เต็มที่ |
| **Tier 2 — Assisted** | Android 10+ | Desktop→Android อัตโนมัติ / Android→Desktop ผ่าน Quick Settings Tile, Notification, Share Sheet | Android 10+ ห้ามอ่าน clipboard จาก background |
| **Tier 3 — Manual-Assist** | iOS 15+ | Share Sheet, Action Button, Widget, Shortcuts | iOS Sandbox ระงับ background + pasteboard prompt |

> **หมายเหตุ:** ข้อจำกัด Tier 2–3 เป็นข้อจำกัดของ OS ที่บังคับกับทุกแอปเท่ากัน ไม่ใช่ข้อจำกัดของสถาปัตยกรรม DropClip
>
> **การถ่ายโอนไฟล์** ไม่มีข้อจำกัดนี้ — รองรับเต็มรูปแบบทั้ง 4 แพลตฟอร์ม

### หลักการออกแบบ

- **Zero-Click Transfer** — เครื่องที่จับคู่แล้วรับไฟล์อัตโนมัติ
- **Passive Clipboard (Tier 1)** — Copy ปกติ แล้ว Paste อีกเครื่องได้ทันที
- **Personal Cluster, No Account** — QR pairing ครั้งเดียว ไม่มีสมัครสมาชิก

---

## 5. วัตถุประสงค์และเป้าหมาย

1. ระบบถ่ายโอนไฟล์ P2P ทำงานเต็มรูปแบบครบ 4 แพลตฟอร์ม
2. Passive Clipboard Sync สองทาง Tier 1 บน macOS/Windows latency **p95 < 1,000 ms**
3. **Cross-OS Image Clipboard Normalizer** แปลง macOS TIFF/PNG ↔ Windows DIB/CF_DIBV5 รักษา alpha + DPI
4. Zero-Configuration Discovery ผ่าน mDNS + fallback 2 ชั้น (QR / Manual IP)
5. Throughput **≥ 60% ของ iperf3 TCP baseline** โดยใช้ memory คงที่ **< 100 MB**
6. Security model แบบ per-device identity ที่ **เพิกถอนอุปกรณ์ที่สูญหายได้**
7. ลด interaction ในงานประจำวัน **≥ 70%** เทียบ workaround เดิม

---

## 6. สถาปัตยกรรมระบบ

```
+---------------------------------------------------------------------------+
|                        Local Network (Wi-Fi / LAN)                        |
|                                                                           |
|  +----------------------------+          +----------------------------+   |
|  |   TIER 1: macOS / Windows  |          |  TIER 2/3: Android / iOS   |   |
|  |----------------------------|          |----------------------------|   |
|  |  Native Tray/Menubar UI    |          |  Native Mobile UI          |   |
|  |  Clipboard Watcher (BG)    |<--mDNS-->|  Foreground Service (And.) |   |
|  |  Sensitive-Content Filter  |          |  Share Ext / Widget (iOS)  |   |
|  |  Format Normalizer         |          |  Quick Settings Tile       |   |
|  +-------------+--------------+          +-------------+--------------+   |
|                |                                       |                  |
|                |     [ Secure Channel: TLS 1.3 ]       |                  |
|                |      per-device cert pinning          |                  |
|                |                                       |                  |
|     Control Plane  <---- WebSocket over TLS ---->  Control Plane          |
|     Data Plane     <---- HTTP/1.1 Chunked  ---->   Data Plane             |
|                                                                           |
+---------------------------------------------------------------------------+
```

### 6.1 Device Discovery Layer
- mDNS/DNS-SD (UDP 5353) service type `_dropclip._tcp`
- TXT Record: `v`, `id`, `name`, `os`, `fp` (SHA-256 ของ cert)
- กรองด้วย **Trusted Device List ฝั่ง client** ไม่ใช้ shared cluster hash
- Fallback 2 ชั้น: QR Code (IP + fingerprint) / กรอก IP ตรง

### 6.2 Clipboard Sync Engine
- Control Plane: Persistent WebSocket over TLS 1.3
- **Hybrid Logical Clock (HLC) + Last-Writer-Wins** แทนการเทียบ hash อย่างเดียว
- **Sensitive-Content Filter:** `org.nspasteboard.ConcealedType` (macOS), `EXTRA_IS_SENSITIVE` (Android) → ไม่ซิงก์
- **Clipboard TTL:** ลบอัตโนมัติหลัง N วินาที เหมาะกับ OTP

### 6.3 File Transfer Engine
- Lightweight HTTP Server (`shelf`)
- **HTTP/1.1 Chunked** — จงใจไม่ใช้ HTTP/2 (flow-control window ทำให้ช้ากว่าบน LAN)
- Streaming ทีละ chunk เท่านั้น — memory คงที่
- SHA-256 per-chunk + whole-file
- Resumable ด้วย `X-Offset` + `last_chunk_sha256` และ 64 MiB checkpoint ใน sidecar (PROTO §9.7, §12.4)

### 6.4 Security Model

| หัวข้อ | v1.0 (เดิม) | **v2.0** |
|---|---|---|
| Identity | Shared Master Secret | **Per-device ECDSA P-256 keypair** |
| Channel | AES-256-GCM เขียนเอง | **TLS 1.3 + Certificate Pinning** |
| Pairing | แลก secret ดิบ | **QR + public key fingerprint + SAS 6 หลัก** |
| การเพิกถอน | ทำไม่ได้ | **ถอดออกจาก Trusted List ได้ทันที** |
| Forward Secrecy | ไม่มี | **มี (TLS 1.3 ephemeral)** |
| Key Storage | config file | **Keychain / DPAPI / Keystore** |

---

## 7. กลยุทธ์กำจัดแรงเสียดทาน

| จุดที่เกิด Friction | วิธีจัดการ | Tier |
|---|---|---|
| การเปิดโปรแกรม | Auto-start on Boot ซ่อนใน Tray | 1 |
| การคัดลอกข้อความ | Native Clipboard Watcher | 1 |
| การคัดลอกบนมือถือ | Quick Settings Tile / Share Sheet / Action Button | 2, 3 |
| การรับข้อความบนมือถือ | Notification พร้อมปุ่ม Copy หนึ่งแตะ | 2, 3 |
| การรับไฟล์ | Auto-Accept (Opt-in ต่ออุปกรณ์ที่เชื่อถือ, ปิดเป็นค่าเริ่มต้น) | ทุก Tier |
| การส่งไฟล์ | Context Menu + Drag-and-Drop | 1 |
| เครื่องออฟไลน์ | Catch-up Sync Queue (20 รายการล่าสุด) | ทุก Tier |
| เครือข่ายหลุด | Resumable Transfer | ทุก Tier |

---

## 8. ขอบเขตของงาน

### อยู่ในขอบเขต
- macOS 12+, Windows 10/11, iOS 15+, Android 10+
- Clipboard: Plain Text, URL, PNG/JPEG พร้อม Format Normalizer
- File Transfer: ทุกนามสกุล ไม่จำกัดขนาด รองรับโฟลเดอร์ Progress Bar + Resume
- Security: TLS 1.3 + per-device identity + revocation + sensitive filtering

### นอกขอบเขต
- ไม่รองรับข้ามอินเทอร์เน็ตสาธารณะ (No Relay / No NAT Traversal)
- ไม่รองรับเครือข่ายที่เปิด AP/Client Isolation
- **ไม่รองรับ Passive Background Clipboard บน iOS/Android** ตามข้อจำกัด OS
- ไม่รองรับ Rich Text (RTF/HTML), ไฟล์ใน clipboard, วิดีโอใน clipboard
- ไม่รองรับ Linux ในเวอร์ชันนี้

---

## 9. Evaluation Metrics

### 9.1 ประสิทธิภาพ

| ตัวชี้วัด | เป้าหมาย | วิธีวัด |
|---|---|---|
| Clipboard Latency (text) | p50 < 300 ms, p95 < 1,000 ms | Timestamp 100 รอบ |
| Clipboard Latency (image 2 MB) | p95 < 2,500 ms | เช่นเดียวกัน |
| File Throughput | ≥ 60% iperf3 baseline | ไฟล์ 1 GB / 10 GB |
| Peak Memory (10 GB) | < 100 MB คงที่ | Instruments / PerfMon |
| Discovery Time | < 3 s | จับเวลาจนอุปกรณ์ปรากฏ |
| Battery Drain (idle) | < 3% ต่อ 24 ชม. บนมือถือ (Battery Historian) และ CPU idle < 0.5% บน Desktop | ทดสอบต่อเนื่อง 24 ชม. เทียบ baseline |

### 9.2 ประสบการณ์ผู้ใช้

| ตัวชี้วัด | เป้าหมาย | วิธีวัด |
|---|---|---|
| Interaction Count | ลด ≥ 70% | นับ action ใน 5 สถานการณ์มาตรฐาน |
| Time-on-Task | ลด ≥ 60% | จับเวลาผู้ใช้ 10 คน |
| SUS Score | ≥ 75 | แบบสอบถามหลังใช้จริง 1 สัปดาห์ |

**สถานการณ์ทดสอบมาตรฐาน:** (1) ส่ง URL Mac→Win (2) ส่ง screenshot Win→Mac (3) ส่งไฟล์ 2 GB ระหว่าง Desktop (4) ส่งข้อความมือถือ→Desktop (5) ส่งรูป Desktop→มือถือ

### 9.3 ความถูกต้องและความปลอดภัย
- Integrity: ไฟล์ 500 ครั้ง SHA-256 ตรง 100%
- Loop Prevention: 4 เครื่อง 1,000 เหตุการณ์ ไม่มี loop ไม่สูญข้อมูล
- Format Fidelity: 50 ภาพ SSIM ≥ 0.99
- Concealed Filtering: 1Password/Bitwarden/Keychain ไม่ซิงก์ 100%
- Revocation: อุปกรณ์ที่ถูกถอดต้องตัดสิทธิ์ในเครื่องภายใน < 1 วินาที และแพร่กระจายทั่วคลัสเตอร์ภายใน < 2 วินาที (NFR-S05)

---

## 10. Risk Assessment

| ความเสี่ยง | ระดับ | แผนรับมือ |
|---|---|---|
| iOS Sandbox ห้าม background clipboard | สูง | ประกาศเป็น Tier 3 ตั้งแต่ต้น ใช้ Share Extension + Action Button + Shortcuts |
| Android 10+ บล็อก background clipboard | สูง | Quick Settings Tile + Notification — **หลีกเลี่ยง Accessibility Service** |
| Router drop multicast | กลาง | Fallback QR + Manual IP |
| OOM ไฟล์ระดับ GB | กลาง | Streaming บังคับใช้ + ทดสอบ 10 GB เป็น acceptance |
| Image format mismatch | กลาง | Format Normalizer เป็น component แยก + unit test 50 เคส |
| macOS ไม่มี clipboard event API | กลาง | Adaptive polling + วัด battery เป็น metric |
| Notarization / Code Signing | กลาง | ขอ Developer ID ตั้งแต่ Phase 1 |
| Scope Creep 4 แพลตฟอร์ม | สูง | แบ่งเฟส + Phase 3 ลดขอบเขตได้ |

---

# PART II — ENGINEERING PLAYBOOK

## 11. ปรัชญาการทำงานของทีม

**Lead รับผิดชอบ "สัญญา" ทีมรับผิดชอบ "การเติมเต็ม"** — Lead เขียน protocol spec, interface, abstract class, และ test case ให้ก่อน ทีมเขียน implementation ให้ test ผ่าน

### กฎ 6 ข้อที่ห้ามละเมิด
- **PR ห้ามเกิน 400 บรรทัด** เกินแปลว่า task ใหญ่ไป
- **ไม่มี PR ไหน merge ได้โดยไม่มี test**
- **Spike task มี timebox** ติดเกิน 4 ชม. ต้องหยุดแล้วมาคุย
- **ห้าม implement crypto เอง** ทุกอย่างผ่าน TLS ของ OS
- **ห้ามโหลดไฟล์ทั้งก้อนขึ้น RAM** เห็น `readAsBytes()` ในงานไฟล์ = reject
- **Conventional Commits** เพื่อ auto changelog

### การแบ่งงาน
- **Lead ทำเอง:** Protocol design, Security/Pairing Core, Shared Architecture, iOS Network Privacy & Permissions, CI/CD, Code signing (Native clipboard hooks พัฒนาร่วมกับ DESK สำหรับ macOS และ NET สำหรับ Windows)
- **ทีมทำ:** Networking layer, File transfer, UI, Business logic, Format Normalizer, Test suite, และ Mobile native integration

---

## 12. Architecture Decision Records

### ADR-001 — Flutter/Dart + Native Platform Channel

| ตัวเลือก | ตัดสิน | เหตุผล |
|---|---|---|
| Rust core + FFI + Native UI | ❌ | ต้องรู้ 4 ภาษา + FFI debugging หนักเกินทีมจูเนียร์ |
| Native ทั้งหมด | ❌ | เขียน logic ซ้ำ 4 รอบ |
| Electron + React | ❌ | Mobile ไม่ได้, กิน RAM, ไม่มี native clipboard hook |
| **Flutter/Dart + Platform Channel** | ✅ | โค้ดร่วม ~75%, ภาษาเดียว, LocalSend พิสูจน์แล้ว, native code จำกัดที่ ~500 บรรทัด/แพลตฟอร์ม |

### ADR-002 — TLS 1.3 + Self-Signed Cert + Fingerprint Pinning
แต่ละเครื่องสร้าง self-signed cert ตอนติดตั้งครั้งแรก แล้ว pin ด้วย SHA-256 fingerprint ที่แลกตอน pairing ได้ forward secrecy ฟรี ไม่ต้องเขียน crypto เอง เพิกถอนได้ด้วยการลบ fingerprint

### ADR-003 — แยก Control Plane / Data Plane
- **Control Plane** = WebSocket over TLS — signaling, clipboard text, metadata (payload ≤ 32 KB)
- **Data Plane** = HTTP/1.1 Chunked over TLS — ไฟล์และรูปทุกขนาด

เหตุผล: รูป 5 MB บน WebSocket จะ block clipboard text ที่มาทีหลัง และ WS framing ไม่ได้ออกแบบมาเพื่อ bulk transfer

### ADR-004 — HTTP/1.1 ไม่ใช่ HTTP/2
HTTP/2 flow-control window default 64 KB ทำให้ throughput บน LAN แย่กว่า HTTP/1.1 chunked และไม่มี head-of-line blocking ให้แก้เพราะ 1 connection = 1 ไฟล์

### ADR-005 — Monorepo Structure

```
dropclip/
├── packages/
│   ├── dropclip_protocol/      # message schema, HLC, SAS, sanitization
│   ├── dropclip_core/          # discovery, transport, crypto wrapper, sync engine
│   ├── dropclip_clipboard/     # platform channel + Format Normalizer
│   ├── dropclip_transfer/      # file transfer engine
│   └── dropclip_ui/            # shared widgets
├── apps/
│   ├── desktop/                # macOS + Windows
│   └── mobile/                 # iOS + Android
├── native/
│   ├── macos/ClipboardWatcher.swift
│   ├── windows/ClipboardWatcher.h
│   ├── android/ClipboardService.kt
│   └── ios/ShareExtension/
└── tools/
    ├── protocol_fuzzer/
    └── bench/
```

จัดการด้วย **Melos** — `melos test` รันเทสต์ทุก package

### ADR-006 — เปลี่ยน Identity Key จาก Ed25519 เป็น ECDSA P-256 (secp256r1)

| ตัวเลือก | ผลการประเมิน | เหตุผล |
|---|---|---|
| Ed25519 | ❌ ปฏิเสธ | 1. Android Keystore รองรับ Ed25519 ตั้งแต่ Android 13+ เท่านั้น ขัดกับขอบเขต Android 10+<br>2. Apple Security.framework ไม่รองรับ Ed25519 สำหรับ `SecIdentity` / client cert mTLS ใน `URLSession`<br>3. Dart `SecureServerSocket` บน BoringSSL ขาด callback สำหรับ custom self-signed verification หากไม่มี CA/Cert parsing มาตรฐาน |
| **ECDSA P-256 (NIST P-256 / secp256r1)** | ✅ เลือก | รองรับระดับฮาร์ดแวร์ครบทุกระบบ (Apple Secure Enclave, Android Keystore API 23+, Windows CNG/DPAPI), รองรับ X.509 v3 client cert ใน `URLSession` และ Dart TLS เต็มรูปแบบ |

### ADR-007 — Android `connectedDevice` Service Type และ iOS Background `URLSession`

| แพลตฟอร์ม | การตัดสินใจเชิงเทคนิค | เหตุผล |
|---|---|---|
| **Android 14/15** | ใช้ `android:foregroundServiceType="connectedDevice"` แทน `dataSync` | บน Android 15 `dataSync` ถูกจำกัดเวลารวม ~6 ชั่วโมง/วัน ขัดกับข้อกำหนด Foreground Service 24 ชม. ของ DropClip |
| **Android 14+ QS** | ใช้ `PendingIntent` สำหรับ `startActivityAndCollapse` | ปฏิบัติตาม API requirement ของ Android 14 ป้องกัน SecurityException |
| **iOS Share Ext** | ใช้ `URLSessionConfiguration.background(withIdentifier:)` + Cache ใน App Group | ควบคุม Peak RAM < 30 MB และป้องกัน extension ถูก Jetsam kill ระหว่างสตรีมไฟล์ 4 GB |

**S0.2 device & CI verification (2026-11-06 – 2026-11-09, `LEAD` Approved):**
- **iOS:** A signed test host launched on physical iPhone 16 Pro (iOS 27.0) and verified `NWBrowser` for `_dropclip._tcp` reaching `ready` once `NSLocalNetworkUsageDescription` and `NSBonjourServices` were declared ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)). The two-target `ShareUploadHarness` (Host + Share Extension) built and ran on iPhone 16 Pro Simulator with `group.com.dropclip.shared` staging, `getrusage` Peak RSS tracking (< 30 MiB), and end-to-end 4 GiB (4,294,967,296 bytes) TLS 1.3 1 MiB-chunked streaming verified by SHA-256 (`8479e43911dc45e89f934fe48d01297e16f51d17aa561d4d1c216b1ae0fcddca`). Because Apple's free Personal Team (student/open-source tier) restricts `com.apple.security.application-groups` on physical devices, `LEAD` approved the combined physical `NWBrowser` probe + Simulator App Group Share Extension + 4 GiB TLS 1.3 streaming verification (with optional single-target `temporaryDirectory` fallback for on-device RSS sampling).
- **Android:** `connectedDevice` foreground service, `MulticastLock`, sensitive clip suppression, and Quick Settings `PendingIntent` (`startActivityAndCollapse`) passed instrumented tests on GitHub Actions CI across **Android 14 (API 34) and Android 15 (API 35)** (94.6% JaCoCo coverage), paired with physical **Android 14** hardware verification for overnight Doze Mode / OEM power management.

### ADR-008 — ใช้ Hybrid Logical Clock (HLC) แทน Pure Lamport Clock

| ปัญหาของ Pure Lamport | การแก้ปัญหาด้วย HLC |
|---|---|
| เมื่ออุปกรณ์ออฟไลน์ไปนานแล้วคัดลอกข้อมูลใหม่ ค่า Lamport clock จะต่ำ เมื่อเชื่อมต่อกลับมา ข้อมูลใหม่จะถูก LWW ทิ้งเพราะแพ้ clock เก่าของเครื่องอื่น | HLC ผสานเวลาจริง (Physical wall clock `l`) และตัวนับเชิงตรรกะ (`c`) ช่วยให้ข้อมูลที่คัดลอกใหม่บนเครื่องออฟไลน์มีค่าเวลาจริงสูงกว่าข้อมูลเก่าได้ถูกต้องในกรณีส่วนใหญ่ โดยจำกัดกรอบความคลาดเคลื่อนด้วย `MAX_CLOCK_DRIFT` (60 วินาที) หากโหนดใดมีเวลาล้ำหน้าเกินกว่านี้จะถูกปฏิเสธเพื่อป้องกันการยึดสิทธิ์ LWW โดยมิชอบ (แลกกับ trade-off กรณีเครื่องออฟไลน์ที่นาฬิกาเดินช้ากว่าคลัสเตอร์มาก) |

### ADR-009 — ป้องกัน SAS MITM ด้วย Commit-then-Reveal Scheme

| ช่องโหว่เดิม | วิธีแก้ปัญหา (Commit-then-Reveal) |
|---|---|
| ถ้าคำนวณจาก `H(fp_A ‖ fp_B ‖ nonce)` โดย nonce ส่งบนเครือข่าย ผู้โจมตี MITM สามารถ brute-force หา keypair จำลอง ~10⁶ ครั้งใน 60 วินาที เพื่อให้ได้ SAS 6 หลักตรงกัน | Client ส่ง Commitment `C_B = SHA-256(nonce_B ‖ fp_B)` ก่อน เมื่อ Host เปิดเผย `nonce_A` แล้ว Client จึงเปิดเผย `nonce_B` เพื่อคำนวณ SAS ทำให้ผู้โจมตีไม่สามารถ brute-force ย้อนหลังได้ สำหรับโหมด QR บังคับให้ `nonce_A` ส่งผ่านหน้าจอ (Out-Of-Band) เท่านั้น |

---

## 13. Test Strategy

### Test Pyramid

| ระดับ | สัดส่วน | ใครเขียน | รันเมื่อไหร่ |
|---|---|---|---|
| Unit | 60% | ทุกคน | ทุก commit |
| Integration (harness) | 25% | ทุกคน | ทุก PR |
| E2E เครื่องจริง | 10% | Junior หมุนเวียน | ทุกคืน |
| Manual/Exploratory | 5% | ทั้งทีม | ก่อนปิด milestone |

### Device Test Matrix

| แพลตฟอร์ม | ต้องทดสอบ |
|---|---|
| macOS | M-series + Intel, macOS 12 + ล่าสุด |
| Windows | Win 10 + 11, x64 + ARM |
| Android | Pixel, Samsung, Xiaomi (Android 10/13/14) |
| iOS | iPhone (iOS 15 + ล่าสุด), iPad |
| Network | Router 3 ยี่ห้อ, Wi-Fi 5/6, มี/ไม่มี VLAN |

### Definition of Done — ทุก task
- [ ] `dart analyze --fatal-infos` ไม่มี warning
- [ ] Unit test ครอบ happy path + **อย่างน้อย 3 edge case**
- [ ] Integration test ถ้าแตะ network
- [ ] Coverage ของไฟล์ที่แก้ ≥ 75%
- [ ] Code review ≥ 1 คน (งาน security ต้องผ่าน Lead)
- [ ] อัปเดต docs ถ้าเปลี่ยน public API
- [ ] ทดสอบด้วยมือบนเครื่องจริง ≥ 1 แพลตฟอร์ม
- [ ] ไม่มี TODO ที่ไม่มี issue number

---

## 14. Timeline

| สัปดาห์ | Phase | Milestone | Exit Gate |
|---|---|---|---|
| 1–2 | Phase 0 | Foundation, CI, Protocol | CI เขียว, protocol test ผ่าน |
| 3–5 | Phase 1 | M1: Discovery & Pairing | 2 เครื่อง pair สำเร็จบน Wi-Fi จริง |
| 5–7 | Phase 1 | M2: Transport | Reconnect 20 ครั้งไม่ leak |
| 7–10 | Phase 1 | M3: Clipboard ⭐ | latency p95 < 1s, concealed filter ผ่าน |
| 10–12 | Phase 1 | M4: File Transfer + UI | 10 GB, mem < 100 MB |
| **12** | — | **🚦 GATE: ใช้จริง 2 สัปดาห์** | ไม่ผ่าน = ห้ามไป Phase 2 |
| 13–17 | Phase 2 | Android | 5 เครื่องจริง, Play internal ผ่าน |
| 18–21 | Phase 3 | iOS | TestFlight ผ่าน review |
| 22–24 | Phase 4 | Hardening | ครบทุก metric, pentest ผ่าน |

**Buffer 15%** ในทุก phase — ถ้าเลย ให้ตัด **Phase 3 ก่อน** (เหลือแค่รับไฟล์ + Share Extension)

---

## 15. Phase Exit Criteria

### 🚦 Phase 1 Exit — ต้องผ่านครบทุกข้อ
- [ ] ทีมทุกคนใช้ DropClip ทำงานจริงทุกวัน **ติดต่อกัน 2 สัปดาห์** ไม่ต้อง restart
- [ ] Clipboard latency p95 < 1,000 ms บนเครื่องจริง
- [ ] ไฟล์ 10 GB สำเร็จ memory < 100 MB
- [ ] Coverage ≥ 75%, CI เขียว
- [ ] Security checklist ผ่าน: pinning, revocation, concealed filtering, path traversal, rate limiting
- [ ] Bug P0/P1 จากการใช้จริงปิดหมด

### 🚦 Phase 2 Exit
- [ ] ทดสอบครบ 5 เครื่องจริง (ยี่ห้อต่างกัน)
- [ ] Foreground Service อยู่ได้ 24 ชม. บน Pixel/Samsung/Xiaomi
- [ ] Play Store internal testing ผ่าน review
- [ ] Battery drain < 3%/24 ชม.

### 🚦 Phase 3 Exit
- [ ] TestFlight ผ่าน App Review
- [ ] ทดสอบบน iPhone + iPad จริง
- [ ] Share Extension ไม่ถูก kill กับไฟล์ 4 GB

### 🚦 Phase 4 Exit
- [ ] ทุก benchmark metric ผ่านเป้า
- [ ] Pentest จากคนนอกทีมผ่าน
- [ ] Soak test 72 ชม. ไม่มี memory growth
- [ ] SUS ≥ 75

---

## 16. การจัดการทีมจูเนียร์

### Ritual
- **Daily standup 15 นาที** — เมื่อวาน / วันนี้ / **ติดอะไร** (ข้อสามสำคัญสุด)
- **กฎ 4 ชั่วโมง** — ติดเกิน 4 ชม. ต้องขอความช่วยเหลือ การนั่งงมเงียบ 3 วันคือความล้มเหลว
- **Pair programming สัปดาห์ละ 2 ชม./คน** หมุนเวียน
- **Weekly demo วันศุกร์** — โชว์ของจริง ไม่ใช่เปอร์เซ็นต์
- **Retro ทุกปิด milestone**

### กระจายความรู้ (กัน bus factor = 1)
- หมุน task ข้ามโดเมนทุกเฟส
- Junior review งานกันเองก่อนถึง Lead
- เขียน ADR ทุกครั้งที่ตัดสินใจสำคัญ — ให้ junior เขียนแม้ Lead เป็นคนตัดสิน

### สัญญาณอันตราย

| สัญญาณ | ความหมาย | การจัดการ |
|---|---|---|
| PR ใหญ่ขึ้นเรื่อย ๆ | task ซอยไม่ดี / scope creep | ซอย task ใหม่ทันที |
| "เกือบเสร็จแล้ว" 3 วันติด | ติดจริงแต่ไม่กล้าบอก | นั่ง pair ด้วยทันที |
| Coverage ตกลง | เริ่มรีบ เริ่มข้าม test | หยุด feature 1 วัน ตามหนี้ |
| Copy-paste โดยไม่เข้าใจ | จะเป็น bug 2 เดือนหน้า | ให้อธิบายทีละบรรทัดใน review |
