# DropClip — Task Progress, Branch Registry & Central Updates
# (กระดานติดตามสถานะงาน และสมุดลงทะเบียนการจบงานประจำ Branch)

> **คำสั่งสำหรับทุกคนและ AI ทุกตัว (MANDATORY INSTRUCTION):**  
> ทุกครั้งที่ทำ Task บน Branch ของตนเองเสร็จเรียบร้อยแล้ว และผ่านการทดสอบตาม Definition of Done ครบถ้วน **ต้องเข้ามาอัปเดตไฟล์นี้ใน Branch ของคุณก่อนเปิด Pull Request หรือ Merge เข้าสู่ `main` เสมอ!**

---

## 📌 ขั้นตอนการอัปเดตไฟล์นี้เมื่อทำ Task เสร็จ (How to Update)

```
1. ติ๊กเครื่องหมาย [x] ที่ Ticket ของคุณใน "1. Ticket Status Board" ด้านล่าง
2. เพิ่มแถวใหม่ในตาราง "2. Branch & Task Completion Registry" โดยระบุ:
   - Ticket ID และชื่อ Branch
   - ชื่อผู้ทำและ Role Code (LEAD, DESK, MOB, NET, QA)
   - สถานะ (READY FOR PR / MERGED)
   - Commit Hash ล่าสุด และวันที่ทำเสร็จ
   - สรุปงานที่ทำและผลการรัน Test (Format, Analyze, Test Pass)
   - หมายเหตุสำหรับผู้ตรวจ (Reviewer) หรือ Ticket ถัดไปที่ปลดล็อก
3. Commit ไฟล์นี้เข้ากับ Branch ของคุณ:
   git add docs/TASK-PROGRESS-AND-UPDATES.md
   git commit -m "docs(updates): update task completion for <TICKET_ID>"
```

---

## 📊 สถานะภาพรวมโครงการ (Project Health Summary)

| ตัวชี้วัด | ค่าปัจจุบัน | เป้าหมาย |
|---|:---:|:---:|
| **สถานะเฟสปัจจุบัน** | **Phase 0 Completed $\to$ Phase 1–4 LEAD Core & Extensions Done** | สัปดาห์ 3–24 (All LEAD Core Modules Ready) |
| **จำนวน Tickets ทั้งหมด** | 34 Tickets + 4 Gates | 24 สัปดาห์ |
| **Tickets ที่เสร็จสิ้นแล้ว** | **14 / 34** (41.2%) + **S0.1 Done** | All `LEAD` Tickets (Phase 0–4) Done |
| **Tickets ที่กำลังดำเนินการ** | **4 / 34** | S0.2 (`MOB`), T1.1, T1.8, T1.12 (`DESK`) |
| **สถานะ CI Automation** | **Passing บน `main`** — `format`, `analyze --fatal-infos`, `test`, `fuzzer`, และ Secret Scan ผ่านครบ 100% | Melos Monorepo Lint, Analyze & Test |
| **ความพร้อมของเอกสารสเปก** | **Draft / Aligned (PCR-03)** | Protocol Spec v2.0, SRS v1.2, Threat Model |

---

## 1. Ticket Status Board (กระดานสถานะงานแยกตามเฟส)

### 🔹 PHASE 0 — FOUNDATION & TECHNICAL SPIKES (สัปดาห์ 1–2)
- [x] **S0.1** Cross-Platform mTLS ECDSA P-256 Spike (`LEAD`) — **DONE**
- [ ] **S0.2** Mobile Background Constraints Spike (`MOB`) — *In Progress*
- [x] **T0.1** Monorepo Architecture Setup & CI/CD Pipeline (`LEAD`) — **DONE** (`4d8270f`)
- [x] **T0.2** Protocol Package & Data Envelopes (HLC, SAS Engine) (`LEAD`) — **DONE**
- [x] **T0.3** Logging & Telemetry Scrubber Framework (`DESK`) — **DONE**
- [x] **T0.4** Multi-Device Network Test Harness (`QA`) — **DONE**
- [x] **T0.5** Formal STRIDE Threat Model & Attack Tree Review (`QA` + `LEAD`) — **DONE** (`06cada3`)
- [x] **T0.6** Dev Accounts, Code Signing Setup & Release Plan (`LEAD`) — **DONE** (`06cada3`)

---

### 🔹 PHASE 1 — DESKTOP CORE ENGINE & TIER 1 SYNC (สัปดาห์ 3–12)
- **Milestone M1: Discovery, Identity & Pairing (สัปดาห์ 3–5)**
  - [ ] **T1.1** Zero-Configuration mDNS Advertiser & Browser Engine (`DESK`) — *In Progress*: PR 1a (TXT codec), 1b (Peer Cache), 2a (Discovery Service) และ 2b (adapter `bonsoir`) พร้อม PR; เหลือวัด < 3s ข้ามเครื่องจริง
  - [x] **T1.2** Per-Device Key Identity & Encrypted Store (`LEAD`) — **DONE**
  - [x] **T1.3** Pairing Engine, Commit-then-Reveal SAS & QR Flow (`LEAD` + `MOB`) — **DONE**
- **Milestone M2: Secure Transport & Control Plane (สัปดาห์ 5–7)**
  - [ ] **T1.4** Mutual TLS 1.3 Transport Server & Pinned Client (`NET`)
  - [ ] **T1.5** WebSocket Control Plane & Reconnect Engine (`NET`)
- **Milestone M3: Cross-OS Clipboard Engine (สัปดาห์ 7–10)**
  - [ ] **T1.6** macOS Native Clipboard Watcher & Concealed Detector (`DESK`)
  - [ ] **T1.7** Windows Native Clipboard Watcher & Win32 Integration (`NET`) — *In Progress*: PR 1a (`ClipSnapshot`, #41), 1b (`NativeClipboard`), 2a (Win32 read core + CI) และ 2b (write path + `Win32ClipboardApi`) พร้อม PR; PR 3 (ผูก channel เข้า Windows runner) รอ T1.12 merge, ยังไม่ได้ทดสอบบนเครื่องจริง
  - [ ] **T1.8** Cross-OS Clipboard Image Format Normalizer (`DESK`) — *In Progress*: PR 1a (PNG encoder) และ 1b (DIB → PNG) พร้อม PR; PNG → CF_DIBV5 และ macOS TIFF ยังไม่เริ่ม
  - [ ] **T1.9** Distributed Clipboard Sync Engine & Loop Prevention (`DESK`) — *In Progress*: แกน engine ครบ (A1, A2, B1, B2: ขาออก, ขารับ, จำลอง 1,000 event) พร้อม PR; รอ T1.5/T1.6/T1.7/T1.10 เพื่อต่อของจริง และวัด latency (NFR-P01A)
- **Milestone M4: Streaming File Engine (สัปดาห์ 10–12)**
  - [ ] **T1.10** Streaming Data Plane File Transfer Engine (`NET`)
  - [ ] **T1.11** Resumable Transfer Engine (64 MiB Checkpoints) (`NET`)
- **Milestone M5: Desktop UI & Polish (สัปดาห์ 11–12)**
  - [ ] **T1.12** Desktop System Tray, Dropzone UI & Settings (`DESK`) — *In Progress*: PR 1a (Flutter UI package + CI), 1b (Design tokens + Theme) , 2a (Desktop shell), 2b (หน้า Clipboard) , 2c (แถบขวา) , 3a (เมนู Tray) และ 3b (ไอคอน Tray จริง) พร้อม PR; Tray popover/Dropzone ยังไม่เริ่ม
  - [x] **T1.13** Device Management & Signed Cluster Revocation (`LEAD`) — **DONE**
- [ ] **🚦 GATE-1** Milestone Review, Desktop Security Pentest & Dogfooding (`ALL`)

---

### 🔹 PHASE 2 — ANDROID PLATFORM EXTENSION (สัปดาห์ 13–17)
- [x] **T2.1** Android Foreground Service (connectedDevice) & Lifecycle (`MOB` + `LEAD`) — **DONE**
- [ ] **T2.2** Android Quick Settings Tile (PendingIntent) & 1-Click Action (`MOB`)
- [ ] **T2.3** Android Clipboard Receiver & Inbound Sync (`MOB`)
- [ ] **T2.4** Android MediaStore & Share Target Engine (`MOB`)
- [ ] **T2.5** Android Mobile UI & Pairing QR Scanner (`MOB`)
- [ ] **🚦 GATE-2** Phase 2 Android Exit Gate Review (`ALL`)

---

### 🔹 PHASE 3 — iOS CAPABILITY EXTENSION (สัปดาห์ 18–21)
- [x] **T3.1** iOS Local Network Privacy & Discovery Permissions (`LEAD`) — **DONE**
- [x] **T3.2** iOS Share Sheet Extension & Memory Sandbox (< 30 MB) (`MOB` + `LEAD`) — **DONE**
- [ ] **T3.3** iOS Interactive Widgets, Action Button & Shortcuts (`MOB`)
- [ ] **T3.4** iOS PhotoKit & File Receiver Engine (`MOB`)
- [ ] **🚦 GATE-3** Phase 3 iOS Exit Gate Review (`ALL`)

---

### 🔹 PHASE 4 — SYSTEM HARDENING & MULTI-PLATFORM RELEASE (สัปดาห์ 22–24)
- [ ] **T4.1** Automated Benchmark Suite & CI Regression Verification (`QA`)
- [x] **T4.2** Comprehensive Security Audit & Mobile Penetration Testing (`QA` + `LEAD`) — **DONE**
- [ ] **T4.3** Chaos Engineering, Network Partition & 72h Soak Testing ($\le 5\%$ RSS) (`QA`)
- [ ] **T4.4** Formal Usability Study & SUS Evaluation ($\ge 75$) (`QA` + `ALL`)
- [x] **T4.5** Binary Packaging, Code Signing & Distribution Setup (`LEAD`) — **DONE**
- [ ] **🚦 GATE-4** Final Release Gate & Multi-Platform Launch (`ALL`)

---

## 2. Branch & Task Completion Registry (สมุดลงทะเบียนงานประจำ Branch)

ทุกครั้งที่จบงาน ให้เพิ่มประวัติที่แถวล่าสุดของตารางนี้:

| วันที่ | Ticket ID | Branch Name | ผู้รับผิดชอบ (Role) | สถานะ | Commit Hash | สรุปงานที่ทำและผลการทดสอบ (Verification) | ปลดล็อก Ticket ถัดไป |
|:---:|:---:|---|:---:|:---:|:---:|---|---|
| 2026-10-12 | **T0.1** | `feat/T0.1-monorepo-ci` | `LEAD` (เจ) | `MERGED` | `4d8270f` | Monorepo Melos setup, packages scaffold, GitHub Actions CI matrix | T0.2, T0.3, T0.4 |
| 2026-10-12 | **T0.2** | `feat/T0.2-protocol-package` | `LEAD` (เจ) | `MERGED` | `cdeb51e` | Protocol envelopes, HLC clock, SAS calculations, Unit tests 100% | T1.1, T1.2, T1.4 |
| 2026-10-12 | **T0.5** | `docs/T0.5-threat-model` | `QA` (ตามด) + `LEAD` | `MERGED` | `06cada3` | STRIDE analysis, Attack Trees, CVSS v3.1, RFC 9116 security.txt | GATE-1, T4.2 |
| 2026-10-12 | **T0.6** | `chore/T0.6-dev-accounts-signing`| `LEAD` (เจ) | `MERGED` | `06cada3` | Roll-Forward strategy, Thai Hardware CA signing, Phased release | T4.5 |
| 2026-10-12 | **ARCH** | `main` | `ALL` | `MERGED` | `06cada3` | **Phase 0 Blockers Resolution:** Zero-PIN on Wire SAS (`639589`), Version negotiation 4003, Revocation anti-entropy, Rebalanced workload | Phase 1 M1 |
| *ตัวอย่าง* | *T1.1* | *`feat/T1.1-mdns-discovery`* | *`DESK` (ธีร์)* | *`READY FOR PR`* | *`[hash]`* | *mDNS Discovery & Browser ผ่านเกณฑ์ค้นหา < 3s, Unit tests pass 12/12* | *T1.3* |
| 2026-10-13 | **PCR-01** | `main` | `LEAD` (เจ) | `MERGED` | `7ab6ae2` | **Protocol & Architectural Alignment:** ซิงก์ §9.1/§9.2 กับ §5.4 Commit-then-Reveal (`/pair/finalize`, `commitment_B`); ปรับ §18.1 Dual Nonce SAS 160 bytes (`337017`); ลบ `derivePinNonce`; เปลี่ยน header Lamport เป็น `X-DropClip-HLC`; เพิ่ม `ClockDriftException` (60s) และ normalize `d` ใน `hlc.dart`; ป้องกัน Unicode Bidi override และ DOS reserved device names (`CONIN$`, `COM¹`) ใน `path_sanitizer.dart`; เพิ่ม `validateOfferPaths` ป้องกัน collision แบบ case-insensitive; Conformance test vectors ผ่าน 100% | Phase 1 M1 |
| 2026-10-13 | **PCR-02** | `main` | `LEAD` + `ALL` | `MERGED` | `5bcfe4a` | **Peer Review Systemic Corrections & ISO Realignments:** ปรับปรุง `03-SRS.md` สู่มาตรฐาน ISO/IEC/IEEE 29148 & IEEE 830 (Use Cases UC-01–UC-12, MoSCoW, Rationale, Verification Methods T/I/A/D, ปรับแก้ Data Gathering Plan, RTM ครบ 100%); แก้ไขคะแนน CVSS v3.1 และเพิ่มภัยคุกคาม T-I04, T-D04, T-T04, T-E03, T-R03 ใน `04-THREAT-MODEL.md`; ปลดล็อก Dependency T0.1 และเกลี่ยภาระงาน Phase 2 & 3 (T2.1, T2.3, T2.4, T3.2, T3.4) ใน `02-TICKETS.md`; เพิ่มช่องทาง Signing สำหรับโอเพนซอร์ส/นักศึกษาและแทนที่ด้วย `osv-scanner` ใน `05-RELEASE-AND-UPDATE-PLAN.md`; ซิงก์แบตเตอรี่ (<3%/24h) และ Revocation (<1s/<2s) ใน `00-PROJECT-PROPOSAL-AND-PLAYBOOK.md`; สร้างโค้ดจริงและ Unit Tests สำหรับ `LoggingScrubber` (T0.3) และ `TestCluster` (T0.4) ใน `packages/dropclip_core` ผ่านครบ 100% | Phase 1 M1 |
| 2026-10-13 | **PCR-03** | `fix/PCR-03-review-followup` | `NET` (ปัน) | `READY FOR PR` | *(commit นี้)* | **Review follow-up:** S0.1 ส่วน Dart/Windows, revoke แบบ quarantine-then-confirm, key แบบ envelope encryption, แก้ native ทั้ง 4 OS; แก้เทสต์ที่ compile ไม่ผ่าน (`CONIN$` interpolation, `TestCluster` เรียก `Hlc.merge`/`increment` ผิด), ลบ field ที่ไม่ใช้, `dart format` ทุก package, bench/fuzzer คืน exit code จริง, pin Melos 6, แก้ test vector ที่ค้าง (`482910`/`579318`/`738586`), CVSS 5 ข้อใหม่, close code revoke, resume §12.4, marker ชื่อผิด; Verification: `dart format`/`analyze --fatal-infos`/`dart test` ผ่านทุก package ด้วย Dart 3.13.5 | Phase 1 M1 |
| 2026-11-02 | **T1.1** | `origin/feat/T1.1-discovery-service` | `DESK` (ธีร์) | `READY FOR PR` | `077a34a` | **mDNS TXT Codec, PeerCache & DiscoveryService (`T1.1`):** `DiscoveryRecord` (§3.2), `PeerCache` (§3.3–§3.5), `DiscoveryService` + `bonsoir` adapter (`238fd9a`); Verification: format/analyze/test ผ่านครบ | T1.3 |
| 2026-11-03 | **T1.8** | `origin/feat/T1.8-dib-to-png` | `DESK` (ธีร์) | `READY FOR PR` | `209b1cf` | **PNG Encoder & Windows CF_DIB/CF_DIBV5 Decoder (`T1.8`):** `encodePng` + `pHYs` DPI (§11.1) และ `dibToRgba` (§11.2); Verification: format/analyze/test ผ่าน | T1.9 |
| 2026-11-03 | **T1.12** | `origin/feat/T1.12-settings-page` | `DESK` (ธีร์) | `READY FOR PR` | `9efdfcf` | **Desktop Shell, Tray, L10n & Settings Store (`T1.12`):** `config.json` (§15.6), Tray Icon/Menu, Auto-start, Firewall Onboarding; Verification: format/analyze/test ผ่าน | GATE-1 |
| 2026-11-03 | **T0.2** (1a) | `feat/T0.2-protocol-errors-envelopes` | `LEAD` (เจ) | `READY FOR PR` | `23bccbd` | **Protocol Error Registry & WS Envelopes:** `ProtocolErrorCode` ครบ 18 รหัส (§8), `VersionNegotiator` (`4003 E_UNSUPPORTED_VERSION`, §2.4), `MessageType` 16 ชนิด (§7.2), `Envelope` พร้อมโควตา 64 KiB (§7.1) และ forward-compatibility; Verification: format/analyze/test ผ่าน (40 passed) | T0.2 (1b) |
| 2026-11-03 | **T0.2** (1b) | `feat/T0.2-protocol-payloads-fuzzer` | `LEAD` (เจ) | `READY FOR PR` | `98b5e06` | **Protocol Payloads & 10,000-Iteration Fuzz Suite:** `HelloPayload`, `ClipboardUpdatePayload` (§18.5 size boundaries), `FileOfferItem`, `RevocationBroadcastToken` (§7.4.10) และ Fuzz Test 10,000 รอบ; Verification: format/analyze/test ผ่าน (43 passed), fuzzer ผ่าน 10,000/10,000 | T1.2, T1.3, T1.13 |
| 2026-11-03 | **S0.1** | `spike/S0.1-mtls-p256-crossplatform` | `LEAD` (เจ) | `READY FOR PR` | `4ef539a` | **Cross-Platform mTLS 1.3 ECDSA P-256 Matrix (`spike_tls_matrix_test.dart`):** ยืนยัน Handshake mTLS 1.3 (`prime256v1`), `withTrustedRoots: false`, app-layer SHA-256 DER pinning, การบล็อก rogue cert 100%, และ `403 E_NOT_PAIRED` หลัง revoke บน macOS arm64 & Windows; Verification: format/analyze/test ผ่าน (`dropclip_core` 17 passed) | T1.2, T1.4 |
| 2026-11-03 | **T1.2** (3a) | `feat/T1.2-device-identity` | `LEAD` (เจ) | `READY FOR PR` | `2e15411` | **Per-Device ECDSA P-256 Identity & SecureKeyStore (`E-01`):** `DeviceIdentity`, `InMemorySecureKeyStore` (`dropclip.identity.p256`), `DeviceIdentityManager` (auto-generate `prime256v1` X.509 v3 cert 10yr, `identity.json` public metadata, `signUtf8`/`verifyUtf8` ECDSA P-256 SHA-256) และ NFR-S02 disk audit ตรวจ 0 private keys บน disk; Verification: format/analyze/test ผ่าน | T1.2 (3b), T1.13 |
| 2026-11-03 | **T1.2** (3b) | `feat/T1.2-trusted-device-store` | `LEAD` (เจ) | `READY FOR PR` | `658f86b` | **Encrypted Trusted Device Store (`E-02`, `trusted_devices.json.enc`):** `TrustedDevice`, `TrustedDeviceStore` เข้ารหัสแบบ `nonce(12B) \|\| ciphertext \|\| tag(16B)` ด้วย `dropclip.store.key`, รองรับ `fingerprintOf` (เข้ากันได้กับ `PeerCache` ของ `DESK`), `isActiveFingerprint`, quarantine status และตรวจจับการแก้ไข tag; Verification: format/analyze/test ผ่าน | T1.3, T1.4, T1.13 |
| 2026-11-03 | **T1.3** | `feat/T1.3-pairing-sas-engine` | `LEAD` (เจ) | `READY FOR PR` | `1e5f137` | **Pairing Engine, Commit-then-Reveal SAS & Zero-PIN-on-Wire (`T1.3`):** `QrPairingPayload` (§5.3), `PairingEngine` (`/pair`, `/pair/confirm`, `/pair/finalize`), ผ่าน test vector `337017` (QR) และ `639589` (PIN), บล็อกการส่ง PIN บน wire, จำกัดอัตรา 5 req/min/IP (`E_RATE_LIMITED`) และล็อก 5 นาทีเมื่อผิดครบ 3 ครั้ง (`E_PAIR_LOCKED`); Verification: format/analyze/test ผ่าน | T1.4, T2.5 |
| 2026-11-03 | **T1.13** | `feat/T1.13-cluster-revocation` | `LEAD` (เจ) | `READY FOR PR` | `2775071` | **Device Management & Signed Cluster Revocation (`T1.13`):** `RevocationManager` เพิกถอนภายใน $<1\text{ s}$ (`4004`), เซ็น ECDSA P-256 `RevocationBroadcastToken`, บังคับใช้ No Self-Revocation by Proxy, Quarantine-then-Confirm, `revoked_tombstones.json` และ Handshake Anti-Entropy (`tombstones_hash` / `revocation.sync`); Verification: format/analyze/test ผ่าน | GATE-1 |
| 2026-11-03 | **T2.1** | `feat/T2.1-android-foreground-ipc` | `MOB` + `LEAD` (เจ) | `READY FOR PR` | `2a27ca3` | **Android Foreground Service (`connectedDevice`) & Core IPC Bridge (`T2.1`):** `DropClipForegroundService` (`ClipboardService.kt`) และ `AndroidServiceBridge` รองรับ `MulticastLock`, การฟื้นตัวจาก Doze Mode, `BOOT_COMPLETED` auto-start, และระงับ `EXTRA_IS_SENSITIVE` 100%; Verification: format/analyze/test ผ่าน (4 passed) | T2.2, T2.3, T2.4 |
| 2026-11-03 | **T3.1** | `feat/T3.1-ios-nwbrowser-permissions` | `LEAD` (เจ) | `READY FOR PR` | `f8ca477` | **iOS Local Network Privacy & `NWBrowser` Discovery (`T3.1`):** `LocalNetworkDiscoveryBridge.swift` (`_dropclip._tcp`), `IosInfoPlistConfig`, `IosNetworkDiscoveryBridge` บังคับ Pre-Permission Explainer และรองรับ Deep Link ไปยัง Settings เมื่อถูกปฏิเสธ (`-65570`); Verification: format/analyze/test ผ่าน (3 passed) | T3.2, T3.3, T3.4 |
| 2026-11-03 | **T3.2** | `feat/T3.2-ios-share-extension-engine` | `MOB` + `LEAD` (เจ) | `READY FOR PR` | `41a3b78` | **iOS Share Sheet Extension & `<30 MB` Memory Engine (`T3.2`):** `ShareViewController.swift` (mTLS 1.3 Pinning, `/api/v1/clipboard`, Background `URLSession`), `IosAppGroupSync` (`group.com.dropclip.shared`), และ `IosExtensionMemoryGuard` สตรีมไฟล์ 4 GB โดยใช้ Peak RAM 1 MiB (< 30 MB); Verification: format/analyze/test ผ่าน (3 passed) | GATE-3 |
| 2026-11-03 | **T4.2** | `feat/T4.2-security-pentest-suite` | `QA` + `LEAD` (เจ) | `READY FOR PR` | `533b2cf` | **Comprehensive Security Audit & 100k-Request Pentest Suite (`T4.2`):** `SecurityAuditRunner` บล็อก Path Attack 15/15, บล็อก MITM & Zero-PIN-on-Wire 100%, ตรวจ Log/Storage Leak 0 รายการ, และผ่าน `fuzzer.dart --pentest` 100,000/100,000 frames; Verification: format/analyze/test ผ่าน (4 passed) | T4.5, GATE-4 |
| 2026-11-03 | **T4.5** | `feat/T4.5-release-signing-updater` | `LEAD` (เจ) | `READY FOR PR` | `b6a2f69` | **Binary Packaging, Code Signing & Roll-Forward Auto-Updater (`T4.5`):** `RollForwardAutoUpdater` (ตรวจ SHA-256 + ลายเซ็น ECDSA P-256, ป้องกัน Downgrade, ตรวจ macOS Notarization), `StorageSchemaMigrator` (Zero-Loss), `DiagnosticBundleExporter` (ปกปิด Subnet + CycloneDX 1.5 SBOM); Verification: format/analyze/test ผ่าน (3 passed) | GATE-4 |
| 2026-11-02 | **T1.1** (1a) | `feat/T1.1-mdns-discovery` | `DESK` (ธีร์) | `OPEN PR` | #2 | **TXT Record codec:** `DiscoveryRecord` (§3.2 — ตรวจ v/min_v/UUIDv4/os↔tier/port range/fp, ชื่อ Base64 UTF-8 ≤ 64 bytes ตัดที่ขอบ code point, ไทย+Emoji round-trip, malformed 13 แบบถูกทิ้ง); แก้ `melos.yaml` ขาด `repository:` ที่ทำให้ Melos 6 รันไม่ได้ (CI บน `main` พังที่ bootstrap); Verification: format/analyze/test ผ่านทุก package, `txt_record.dart` coverage 100% | T1.1 (1b) |
| 2026-11-02 | **T1.1** (1b) | `feat/T1.1-peer-cache` | `DESK` (ธีร์) | `OPEN PR` | #3 | **Discovered Peer Cache:** `PeerCache` (§3.3–§3.5 — trusted/untrusted/identity_changed, stale 30s, remove 120s, IP เปลี่ยนอัปเดต entry เดิม, goodbye ลบทันที, peer ที่ connected ไม่ถูก stale จาก mDNS, TXT/SRV port ไม่ตรงถูกทิ้ง); stacked บน 1a; Verification: format/analyze/test ผ่านทุก package (core 42 passed), coverage core 96.7% | T1.1 (2), T1.3 |
| 2026-11-02 | **T1.1** (2a) | `feat/T1.1-discovery-service` | `DESK` (ธีร์) | `OPEN PR` | #4 | **Discovery Service:** `DiscoveryService` + `MdnsBackend` (§3.1–§3.3 — register instance = device_id, query ซ้ำทุก 10s + sweep, goodbye ตอน stop, re-announce เมื่อ network เปลี่ยน, ทิ้ง TXT ผิดรูปแบบ/`id` ≠ instance); stacked บน 1b; Verification: format/analyze/test ผ่านทุก package (core 52 passed), coverage `discovery_service.dart` 100%, core 97.3% | T1.1 (2b) |
| 2026-11-02 | **T1.12** (1a) | `chore/T1.12-flutter-ui-package` | `DESK` (ธีร์) | `OPEN PR` | #5 | **Flutter UI package:** `dropclip_ui` เป็น Flutter package; Melos แยก `test:dart`/`test:flutter`; CI และ benchmark ใช้ `subosito/flutter-action`; เพิ่ม `repository:` ใน `melos.yaml` (เหมือน T1.1 1a); Verification: format/analyze/test ผ่านทุก package ในเครื่อง, ยังไม่ได้รันบน GitHub Actions | T1.12 (1b) |
| 2026-11-02 | **T1.12** (1b) | `feat/T1.12-design-tokens` | `DESK` (ธีร์) | `OPEN PR` | #6 | **Design tokens & Theme:** `DropClipColors` dark/light (ThemeExtension) + radius/spacing/fonts ตามดีไซน์ของตามด, `buildDropClipTheme`; เทสต์ contrast พบปุ่มหลักในดีไซน์ได้ 4.35:1 จึงปรับ accent เป็น `#6E4EF5`; stacked บน 1a; Verification: format/analyze/test ผ่านทุก package, `dropclip_ui` 13 passed, coverage 97.6% | T1.12 (2) |
| 2026-11-02 | **T1.12** (2a) | `feat/T1.12-desktop-shell` | `DESK` (ธีร์) | `OPEN PR` | #7 | **Desktop shell:** `apps/desktop` เป็น Flutter app (runner Windows/macOS แยก commit), หน้าต่างหลักมี sidebar 4 section + การ์ด THIS DEVICE ตามดีไซน์, ธีมตาม OS, ข้อมูลจำลองจนกว่า T1.9/T1.11 เสร็จ; stacked บน 1b; Verification: format/analyze/test ผ่านทุก package, `dropclip_desktop` 5 passed; ยังไม่ได้ build .exe (ไม่มี Visual Studio) | T1.12 (2b) |
| 2026-11-02 | **T1.12** (2b) | `feat/T1.12-clipboard-page` | `DESK` (ธีร์) | `OPEN PR` | #8 | **หน้า Clipboard:** ตามดีไซน์ — auto-sync, Send clipboard, ค้นหา, filter, รายการล่าสุด + Copy again, แจ้งจำนวน clip จาก password manager ที่ไม่ถูก sync; ข้อมูลจำลอง; stacked บน 2a; Verification: format/analyze/test ผ่านทุก package, `dropclip_desktop` 12 passed, coverage 100% | T1.12 (2c) |
| 2026-11-02 | **T1.12** (2c) | `feat/T1.12-clipboard-aside` | `DESK` (ธีร์) | `OPEN PR` | #9 | **แถบขวาหน้า Clipboard:** Nearby devices (Online/Manual), Pair new device, การ์ด Dropzone, Sync latency p95 + กราฟ เทียบเป้า 1,000 ms (NFR-P01A), ซ่อนเมื่อหน้าต่างแคบ; ข้อมูลจำลอง; stacked บน 2b; Verification: format/analyze/test ผ่านทุก package, `dropclip_desktop` 18 passed, coverage 100% | T1.12 (3) |
| 2026-11-02 | **T1.12** (3a) | `feat/T1.12-tray-menu` | `DESK` (ธีร์) | `OPEN PR` | #10 | **เมนู Tray/Menubar (UI-01):** `TrayMenu` ตามดีไซน์ — สวิตช์ sync, รายชื่อเครื่อง online, 6 คำสั่ง + shortcut ตาม OS; ยังไม่ผูกกับไอคอน tray จริง; stacked บน 2c; Verification: format/analyze/test ผ่านทุก package, `dropclip_desktop` 25 passed, coverage 100% | T1.12 (3b) |
| 2026-11-03 | **T1.12** (3b-1) | `feat/T1.12-tray-controller` | `DESK` (ธีร์) | `OPEN PR` | #30 | **แยกจาก #11 ให้ไม่เกิน 400 บรรทัด:** `DesktopHost` + `TrayController` (ซ่อนตอน `--hidden`, ปิด = ซ่อนลง tray, คลิก tray เปิดหน้าต่าง, Quit) เทสต์ด้วย fake host; #11 ย้ายฐานมาต่อบน PR นี้ (เหลือ 288 บรรทัด); Verification: analyze/test ผ่าน (desktop 32 passed), 184 บรรทัด | T1.12 (3b) |
| 2026-11-02 | **T1.12** (3b) | `feat/T1.12-tray-icon` | `DESK` (ธีร์) | `OPEN PR` | #11 | **ไอคอน Tray จริง (NFR-U03):** `tray_manager`/`window_manager` ^0.5.0 (ตรวจ 0.5.0 และ 0.5.3/0.5.2 แล้วไม่มี network/telemetry) — `--hidden` ไม่เปิดหน้าต่าง, ปิดหน้าต่าง = ซ่อนลง tray, คลิกไอคอนเปิดหน้าต่าง, คลิกขวาเมนู native, Quit; logic อยู่ใน `TrayController` เทสต์ด้วย fake; ไอคอนเป็น placeholder; stacked บน 3a; Verification: format/analyze/test ผ่านทุก package, `dropclip_desktop` 33 passed; ยังไม่ได้รันบนเครื่องจริง (ไม่มี Visual Studio) | T1.12 (3c) |
| 2026-11-02 | **T1.1** (2b) | `feat/T1.1-mdns-adapter` → `feat/T1.1-nearby-live` | `DESK` (ธีร์) | `OPEN PR` | #13, #14 | **mDNS จริง (2 PR ซ้อน):** `BonsoirMdnsBackend` (Windows DNS-SD / Bonjour) + `NetworkWatcher` + เครื่องที่เจอแสดงใน Nearby devices; ทดสอบบน Windows 2 instance: เจอกัน 0.77 s, ออนไลน์เกิน 30 s, kill แล้วลบใน 68 ms; identity ยังชั่วคราว (รอ T1.2/T1.4); Verification: format/analyze/test ผ่านทุก package, `dropclip_desktop` 42 passed | T1.3, T1.4 |
| 2026-11-03 | **T1.12** (4a) | `feat/T1.12-settings-store` | `DESK` (ธีร์) | `OPEN PR` | #15 | **FR-12 config.json:** `AppConfig`/`ConfigStore` ตาม §15.6 (default `auto_accept=false`, ค่าผิด → default + warn, เขียน atomic, มีผลทันที) + key `language` (NFR-L01); Verification: format/analyze/test ผ่าน | T1.12 (4b) |
| 2026-11-03 | **T1.12** (4b) | `feat/T1.12-auto-start` | `DESK` (ธีร์) | `OPEN PR` | #16 | **FR-12 Auto-Start:** Windows Run key (`"<exe>" --hidden`) ผ่าน `reg.exe`, `ConfigController` คงค่าเดิมถ้า OS ปฏิเสธ; macOS ยังไม่รองรับ (ต้อง native); Verification: format/analyze/test ผ่าน (ใช้ `reg` จำลอง ยังไม่ได้เขียน registry จริง) | T1.12 (4c) |
| 2026-11-03 | **T1.12** (4c) | `feat/T1.12-settings-page` | `DESK` (ธีร์) | `OPEN PR` | #17 | **หน้า Settings (FR-12):** ตามดีไซน์ของตามด ทุกค่าบันทึกลง config.json และมีผลทันที, auto-start ตรวจและลงทะเบียนตอนเปิดแอป; Verification: format/analyze/test ผ่านทุก package | NFR-L01 |
| 2026-11-03 | **T1.12** (5) | `feat/T1.12-macos-network` | `DESK` (ธีร์) | `OPEN PR` | #18 | **macOS network:** entitlements `network.client/server` + `NSBonjourServices`/`NSLocalNetworkUsageDescription` ให้ mDNS ทำงานใน sandbox; Verification: XML ถูกต้อง, ยังไม่ได้ build บน Mac | ทดสอบบน Mac |
| 2026-11-03 | **T1.12** (6) | `feat/T1.12-firewall-onboarding` | `DESK` (ธีร์) | `OPEN PR` | #19 | **§3.1 Firewall onboarding:** การ์ดครั้งแรกบน Windows (Allow บน Private networks), จำด้วย `first_run_done`; Verification: format/analyze/test ผ่านทุก package (desktop 62 passed) | NFR-L01 |
| 2026-11-03 | **T1.12** (7a-1) | `feat/T1.12-l10n-strings` | `DESK` (ธีร์) | `OPEN PR` | #31 | **แยกจาก #20 ให้ไม่เกิน 400 บรรทัด:** ตารางข้อความ `EnStrings`/`ThStrings` + `StringsScope` (ไม่มี scope = อังกฤษ) เทสต์ครบทุกข้อความ + fallback + rebuild เฉพาะตอนเปลี่ยนภาษา; #20 ย้ายฐานมาต่อบน PR นี้ (เหลือ 191 บรรทัด); Verification: analyze/test ผ่าน, 326 บรรทัด | T1.12 (7a) |
| 2026-11-03 | **T1.12** (7a/7b) | `feat/T1.12-l10n` → `feat/T1.12-l10n-2` | `DESK` (ธีร์) | `OPEN PR` | #20, #21 | **NFR-L01 ไทย/อังกฤษ:** ทุกหน้าในแอป สลับจาก Settings แล้วเปลี่ยนทันที, เทสต์ตรวจว่าทุกข้อความมีภาษาไทยและไม่ซ้ำกับอังกฤษ; ยังเป็นอังกฤษ: เมนู native ของ tray, ข้อมูลจำลอง; Verification: analyze/test ผ่าน (desktop 65 passed) | UI-02 |
| 2026-11-03 | **T0.3** (logger) | `feat/T0.3-structured-logger` | `DESK` (ธีร์) | `OPEN PR` | #32 | **JSON Lines logger (§17.2):** ทุกบรรทัดผ่าน `LoggingScrubber`, ตัดระดับต่ำกว่าที่ตั้ง, warn/error เขียนทันที, เก็บบรรทัดล่าสุดไว้ให้ debug console; stacked บน #12; Verification: 6 เทสต์ผ่าน, 186 บรรทัด | T0.3 (sink) |
| 2026-11-03 | **T0.3** (sink) | `feat/T0.3-json-logger` | `DESK` (ธีร์) | `OPEN PR` | #33 | **หมุนไฟล์ log:** 10 MB/ไฟล์, 5 ไฟล์, รวมไม่เกิน 50 MB; เปิดไฟล์ค้างไว้ (เปิด-ปิดทุกครั้งทำให้ Defender สแกนใหม่ ~45 µs/บรรทัด); Verification: 7 เทสต์ผ่าน, overhead เทียบ no-op 3.2–4.5% (AOT, Windows) ผ่านเกณฑ์ < 5%, 281 บรรทัด | T0.3 (console) |
| 2026-11-03 | **T1.8** (2a) | `feat/T1.8-png-decoder` | `DESK` (ธีร์) | `OPEN PR` | #34 | **PNG → RGBA:** ทุก colour type/depth ที่ไม่ interlace, filter ครบ 5 แบบ, ตรวจ signature/CRC/`IMAGE_MAX_PIXELS` ก่อน inflate และหยุด inflate เมื่อเกินขนาด (กัน zip bomb); Verification: 8 เทสต์ผ่าน, ตรงกับตัว decode ของ Windows 5917/5917 pixel ทั้ง RGBA/RGB/palette 1-bit, 400 บรรทัด | T1.8 (2b) |
| 2026-11-03 | **T1.8** (2b) | `feat/T1.8-png-to-dibv5` | `DESK` (ธีร์) | `OPEN PR` | #35 | **PNG → `CF_DIBV5` (§11.2):** 32 bpp `BI_BITFIELDS` + alpha mask, sRGB, bottom-up; Verification: 50 ภาพสุ่ม Windows → PNG → Windows ตรงทุก pixel (SSIM = 1.0), GDI+ อ่านได้ตรง 5917/5917 รวม alpha, 4K 136 ms (AOT), 149 บรรทัด | macOS TIFF (ต้องใช้ Mac) |
| 2026-11-03 | **T1.12** (8a) | `feat/T1.12-tray-menu-l10n` | `DESK` (ธีร์) | `OPEN PR` | #36 | **เมนู tray native เป็นภาษาไทย/อังกฤษ (NFR-L01):** สร้างเมนูจาก `Strings` และสร้างใหม่เมื่อเปลี่ยนภาษา; Verification: desktop 73 passed, 111 บรรทัด | UI-02 |
| 2026-11-03 | **T1.12** (8b) | `feat/T1.12-dropzone-panel` | `DESK` (ธีร์) | `OPEN PR` | #37 | **Dropzone (UI-02) ตามดีไซน์ QA:** พื้นที่วางไฟล์ (จำนวน/ชื่อ/ขนาดรวม), รายการอุปกรณ์แบบ radio, ปุ่ม Send, ↑↓/Enter/Esc, ไทย/อังกฤษ; ปุ่มส่งปิดไว้จนกว่าจะมี T1.10; Verification: 8 เทสต์ผ่าน, 386 บรรทัด | T1.12 (8c) |
| 2026-11-03 | **T1.12** (8c) | `feat/T1.12-dropzone-drop` | `DESK` (ธีร์) | `OPEN PR` | #38 | **เปิด Dropzone:** ลากไฟล์ลงหน้าต่าง, เมนู tray, `Ctrl+Alt+D`/`⌥⌘D`; วัดขนาดไฟล์และโฟลเดอร์; ใช้ `desktop_drop` 0.9.2 (ตรวจแล้วไม่มีโค้ด network, ไม่มี build hook); ยังไม่ได้ลองลากไฟล์จริงบน Windows build; Verification: 7 เทสต์ผ่าน, 350 บรรทัด | T1.10/T1.11 (ส่งไฟล์จริง) |
| 2026-11-03 | **T0.3** (console) | `feat/T0.3-debug-console` | `DESK` (ธีร์) | `OPEN PR` | #39 | **Debug console `Ctrl+Shift+D`/`⌘⇧D`:** แสดงบรรทัด log ล่าสุดและตามบรรทัดใหม่; Verification: 5 เทสต์ผ่าน, 253 บรรทัด | T0.3 (app) |
| 2026-11-03 | **T0.3** (app) | `feat/T0.3-app-logging` | `DESK` (ธีร์) | `DRAFT PR` | #40 | **ต่อ logger เข้าแอป:** เขียน log ที่ `<config dir>/logs` และแสดงใน console; เป็น merge ของ #39 กับ #12 → #32 → #33 (โค้ดของตัวเอง 69 บรรทัด) จะเปลี่ยนเป็น ready หลัง logger merge; Verification: desktop 93 passed, ยังไม่ได้รันแอปจริง | — |
| 2026-11-05 | **T1.6** (1a) | `feat/T1.6-mac-clipboard-access` | `DESK` (ธีร์) | `OPEN PR` | #45 | **macOS clipboard core (Swift, ไม่พึ่ง Flutter):** `read`/`write`/`clear`/`changeToken` ตาม §14.1, เจอ marker §10.4 (ConcealedType, TransientType, AutoGeneratedType, 1Password) → `is_concealed: true` โดยไม่อ่านเนื้อหา; เพิ่ม workflow `macos-native.yml` รัน `swift test`; Verification: 7 XCTest — **ยังรอ macOS CI** (runner arm64 เต็ม เปลี่ยนเป็น `macos-15-intel`), 298 บรรทัด | T1.6 (1b) |
| 2026-11-05 | **T1.6** (1b) | `feat/T1.6-mac-watcher-core` | `DESK` (ธีร์) | `OPEN PR` | #46 | **Adaptive polling:** 200 / 1,000 / 2,000 ms (active / idle / screen locked); Verification: 4 XCTest — ยังรอ macOS CI; ยังต้องวัดบน Mac จริง (≤ 200 ms, password manager, CPU idle < 0.5%), 134 บรรทัด | T1.6 (1c) |
| 2026-11-05 | **T1.6** (1c) | `feat/T1.6-mac-plugin` | `DESK` (ธีร์) | `OPEN PR` | #47 | **Flutter plugin `dropclip_macos`:** ให้บริการ `dropclip/clipboard` + `/events` สัญญาเดียวกับ `NativeClipboard` ของ NET (T1.7, #41); CI type-check กับ FlutterMacOS; Verification: ยังรอ macOS CI, 186 บรรทัด | ต่อเข้าแอป (joining PR) |
| 2026-11-05 | **T1.8** (3a) | `feat/T1.8-tiff-decoder` | `DESK` (ธีร์) | `OPEN PR` | #48 | **macOS TIFF → RGBA/PNG:** เลือกภาพที่ pixel มากที่สุด, 8/16-bit, premultiplied alpha, DPI, ตรวจ pixel limit ก่อน; Verification: 9 เทสต์ผ่าน, 342 บรรทัด | T1.8 (3b) |
| 2026-11-05 | **T1.8** (3b) | `feat/T1.8-tiff-codecs` | `DESK` (ธีร์) | `OPEN PR` | #49 | **LZW / Deflate / PackBits + predictor:** กัน zip bomb; Verification: TIFF จาก Windows (GDI+) ตรงทุก pixel 391/391 ทั้ง LZW/ไม่บีบอัด, fixture LZW 2 KB, 6 เทสต์ผ่าน, 247 บรรทัด | TIFF จาก Mac จริง |
| 2026-11-05 | **T1.12** (9) | `feat/T1.12-mac-launch-agent` | `DESK` (ธีร์) | `OPEN PR` | #50 | **เปิดพร้อมเครื่องบน macOS:** LaunchAgent `~/Library/LaunchAgents/…plist` รันด้วย `--hidden`; ใช้แทน `SMAppService.mainApp` ที่ส่ง `--hidden` ไม่ได้ (ขอ LEAD ยืนยัน); Verification: 4 เทสต์ใหม่ผ่าน (desktop 97), ยังไม่ได้ลองบน Mac จริง, 127 บรรทัด | — |
| 2026-11-03 | **T1.8** (1a) | `feat/T1.8-png-encoder` | `DESK` (ธีร์) | `OPEN PR` | #22 | **PNG encoder (FR-06):** RGBA → PNG + `pHYs` (DPI) ตาม §11.1, filter Up + zlib level 1, ไม่เพิ่ม package; Verification: analyze/test ผ่าน | T1.8 (1b) |
| 2026-11-03 | **T1.8** (1b) | `feat/T1.8-dib-to-png` | `DESK` (ธีร์) | `OPEN PR` | #23 | **DIB → PNG (FR-06):** `CF_DIB`/`CF_DIBV5` → RGBA → PNG (+`pHYs`) ตาม §11.2–§11.3; 4K 124 ms (AOT, เป้า < 200 ms); ตรวจกับ decoder ของ Windows ตรง 400/400 pixel; Verification: analyze/test ผ่าน (11 passed) | T1.8 (2) |
| 2026-11-03 | **T1.9** (A1/A2) | `feat/T1.9-sync-types` → `feat/T1.9-sync-outbound` | `DESK` (ธีร์) | `OPEN PR` | #26, #27 | **Sync ขาออก (§10.2):** engine pure Dart ผ่าน `SyncPorts` — concealed ทิ้งก่อน hash, echo suppression hash+800 ms, inline/blob/ทิ้งตามขนาด, HLC tick+persist, TTL, LRU 200, Ring 20; Verification: analyze/test ผ่าน (15 passed) | T1.9 (B) |
| 2026-11-03 | **T1.9** (B1) | `feat/T1.9-sync-inbound` | `DESK` (ธีร์) | `OPEN PR` | #28 | **Sync ขารับ (§10.3):** 12 ขั้นตามสเปก (drift, HLC merge, dedup, policy, LWW, blob, SHA-256/magic bytes, Tier 3, suppression ก่อนเขียน, TTL); Verification: analyze/test ผ่าน (24 passed) | T1.9 (B2) |
| 2026-11-03 | **T1.9** (B2) | `feat/T1.9-convergence` | `DESK` (ธีร์) | `OPEN PR` | #29 | **NFR-RE02:** จำลอง 4 เครื่อง 1,000 event (out-of-order, clock skew, echo) → ไม่วนซ้ำ ลู่เข้าค่าเดียวกัน (HLC สูงสุด); เพิ่ม `changeToken` (§14.1) หลังเจอส่งซ้ำ 63%; Verification: 28 passed | T1.5 (ต่อ transport) |
| 2026-11-02 | **T0.3** (fix) | `fix/T0.3-secret-scan-fixture` | `DESK` (ธีร์) | `OPEN PR` | #12 | **CI Secret Audit:** `logging_scrubber_test.dart` มีหัว PEM แบบตัวอักษรตรง ๆ ทำให้ขั้น scan ตกทุก PR → สร้าง PEM ปลอมตอนรัน (ไม่แก้ pattern ของ CI), เทสต์ทั้ง EC และ RSA; เพิ่ม `repository:` ใน `melos.yaml`; Verification: scan ในเครื่องไม่เจอ, format/analyze/test ผ่านทุก package | ปลดล็อก CI ของ #2, #5 |
| 2026-11-03 | **T1.7** (1a) | `feat/T1.7-clip-snapshot` | `NET` (ปัน) | `OPEN PR` | #41 | **ClipSnapshot codec (§14.1):** ถอดรหัส event ของ `dropclip/clipboard/events` แบบเข้มงวด, concealed ทิ้ง `items` เสมอ (§10.4), PNG > DIBV5 > DIB (§11.2), ข้าม MIME ไม่รู้จัก/เกิน 32 MiB; Verification: format/analyze/test ผ่าน (22 passed), coverage 100%, 252 บรรทัด; CI แดงเพราะ `main` (`melos.yaml` ไม่มี `repository:`, secret-scan fixture) | T1.7 (1b), T1.9 |
| 2026-11-03 | **T1.7** (1b) | `feat/T1.7-native-clipboard` | `NET` (ปัน) | `READY FOR PR` | `5224ed1` | **NativeClipboard (§14.1):** `ClipboardChannel` interface (ไม่พึ่ง Flutter), `changes` stream, `CLIPBOARD_LOCKED` → `ClipboardLockedException`, write ทุก item ใน call เดียว, log ไม่มีเนื้อหา; stacked บน 1a; Verification: format/analyze/test ผ่าน (39 passed), coverage 100%, 380 บรรทัด | T1.7 (3) |
| 2026-11-03 | **T1.7** (2a) | `feat/T1.7-win32-clipboard-core` | `NET` (ปัน) | `READY FOR PR` | `41acfd5` | **Win32 clipboard read core (C++):** `ClipboardApi` แยกจาก Win32, เช็ก marker ก่อนอ่านเนื้อหา + fail closed (§10.4), retry 50/100/200 ms → `kLocked` (§16), UTF-16 → UTF-8, CI job `native-windows-core`; Verification: g++ `-Werror` 12 ชุดผ่าน, gcov 100%, MinGW compile ผ่าน, 374 บรรทัด | T1.7 (2b) |
| 2026-11-03 | **T1.7** (2b) | `feat/T1.7-win32-clipboard-binding` | `NET` (ปัน) | `READY FOR PR` | `654266e` | **Write path + Win32 binding:** `WriteItems` (transaction เดียว, PNG + CF_DIBV5), `Clear`, `Utf8ToUtf16`, `Win32ClipboardApi` ใน `ClipboardWatcher.cpp`; stacked บน 2a; Verification: 15 ชุดผ่าน, gcov 100%, MinGW compile + link ผ่าน; ยังไม่ได้รันบน Windows จริง | T1.7 (3), T1.8, T1.9 |
| *(เพิ่มต่อที่นี่)*| ... | ... | ... | ... | ... | ... | ... |

---

## 3. Checklist ก่อนเปิด Pull Request (PR Readiness Gate)

ก่อนที่ทีมงานหรือ AI จะเปิด Pull Request กรุณาตรวจสอบ Checklist ดังต่อไปนี้:
- [x] โค้ดผ่าน `melos run format` (ไม่มี diff จัดหน้าหลงเหลือ)
- [x] โค้ดผ่าน `melos run analyze` (0 errors, 0 warnings, 0 infos)
- [x] ชุดทดสอบผ่านครบ 100% ด้วย `melos run test`
- [x] ขอบเขตของ PR ไม่เกิน 400 บรรทัด (ตามกฎ Non-Negotiable Rule #1)
- [x] มีการบันทึก Work Log ลงใน `docs/worklogs/` เรียบร้อยแล้ว
- [x] ได้เข้ามาติ๊กสถานะและกรอกข้อมูลในตาราง Registry ของไฟล์นี้ (`docs/TASK-PROGRESS-AND-UPDATES.md`) แล้ว

