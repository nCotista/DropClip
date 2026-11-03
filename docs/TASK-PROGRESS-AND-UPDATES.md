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
  - [ ] **T1.1** Zero-Configuration mDNS Advertiser & Browser Engine (`DESK`)
  - [x] **T1.2** Per-Device Key Identity & Encrypted Store (`LEAD`) — **DONE**
  - [x] **T1.3** Pairing Engine, Commit-then-Reveal SAS & QR Flow (`LEAD` + `MOB`) — **DONE**
- **Milestone M2: Secure Transport & Control Plane (สัปดาห์ 5–7)**
  - [ ] **T1.4** Mutual TLS 1.3 Transport Server & Pinned Client (`NET`)
  - [ ] **T1.5** WebSocket Control Plane & Reconnect Engine (`NET`)
- **Milestone M3: Cross-OS Clipboard Engine (สัปดาห์ 7–10)**
  - [ ] **T1.6** macOS Native Clipboard Watcher & Concealed Detector (`DESK`)
  - [ ] **T1.7** Windows Native Clipboard Watcher & Win32 Integration (`NET`)
  - [ ] **T1.8** Cross-OS Clipboard Image Format Normalizer (`DESK`)
  - [ ] **T1.9** Distributed Clipboard Sync Engine & Loop Prevention (`DESK`)
- **Milestone M4: Streaming File Engine (สัปดาห์ 10–12)**
  - [ ] **T1.10** Streaming Data Plane File Transfer Engine (`NET`)
  - [ ] **T1.11** Resumable Transfer Engine (64 MiB Checkpoints) (`NET`)
- **Milestone M5: Desktop UI & Polish (สัปดาห์ 11–12)**
  - [ ] **T1.12** Desktop System Tray, Dropzone UI & Settings (`DESK`)
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

