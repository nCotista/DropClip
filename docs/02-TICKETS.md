# DropClip — Task Tickets, Team Allocation & Engineering Workflow

| รายการ | รายละเอียด |
|---|---|
| **รหัสเอกสาร** | TICKET-DC-V2.0 |
| **Document Version** | 2.0 — Realigned to SRS-DC-V1.2 & PROTO-DC-V2.0 |
| **สถานะ** | Draft / Under Review (ทีมจัดทำ — ยังไม่ผ่านการอนุมัติจากผู้ประเมิน) |
| **Project Lead** | นายธนกฤต บุญญาวรกุล (เจ) — Team Lead & System Architect |
| **เอกสารอ้างอิง** | `00-PROJECT-PROPOSAL-AND-PLAYBOOK.md` (v2.0), `01-PROTOCOL-SPEC.md` (v2.0), `03-SRS.md` (SRS-DC-V1.2) |
| **Import Compatibility** | GitHub Projects / Linear / Jira CSV Import |

---

## 1. Team Allocation & Role Dedication

ตามภาคผนวกของเอกสาร SRS-DC-V1.2 โครงการ DropClip มีสมาชิกทีมพัฒนาทั้งหมด 5 คน โดยกำหนดรหัสย่อ (Role Code) และความรับผิดชอบหลักตลอดทั้ง 5 เฟส ดังนี้:

| ลำดับ | ชื่อ-นามสกุล (ชื่อเล่น) | Role Code | บทบาทหลัก (Primary Role) | ขอบเขตหน้าที่และความรับผิดชอบหลัก (SRS Mapping) |
|:---:|---|:---:|---|---|
| **1** | **นายธนกฤต บุญญาวรกุล (เจ)** | `LEAD` | Project Lead & System Architect | Architecture, Protocol Spec, Security Core (FR-02, NFR-S), Signed Cluster Revocation (T1.13), iOS Network Privacy & NWBrowser (T3.1), Co-engineer T1.3, T2.1, T3.2 with MOB, CI/CD, Code Signing & Release |
| **2** | **นายณัฐธีร์ อโณทัยไพบูลย์ (ธีร์)** | `DESK` | Desktop Client Developer | Desktop Discovery (FR-01), macOS Native Clipboard Watcher (T1.6), Tier 1 Clipboard Sync Engine (FR-03A, FR-04), Cross-OS Image Normalizer (T1.8, FR-06), Desktop UI & System Tray (FR-12, UI-01, UI-02) |
| **3** | **นายเกื้ออนันต์ พวงนิลน้อย (เกื้อ)** | `MOB` | Mobile Client Developer | Mobile Spikes (S0.2), Android Tier 2 Sync & Foreground Service (FR-03B, T2.1 with LEAD, T2.3 with NET, T2.4 with NET), iOS Tier 3 Extensions & PhotoKit (T3.2 with LEAD, T3.4 with NET), Mobile UI (UI-05), Co-engineer T1.3 with LEAD |
| **4** | **นายปัณณ์ ศรีเจริญชัยกุล (ปัน)** | `NET` | Network & File Engine Engineer | Transport Layer (FR-10, CI-02), Windows Native Clipboard Watcher (T1.7), Streaming Data Plane (FR-07, FR-08, SF-06), Resumable Transfer Engine (FR-09), Co-engineer Android/iOS data engines (T2.3, T2.4, T3.4 with MOB) |
| **5** | **นายปรมินทร์ มุขอาษา (ตามด)** | `QA` | QA, UX/UI & Performance Engineer | Test Harness & Chaos Simulation (NFR-RE), Automated Benchmarks (NFR-P, NFR-R), Security Pentest Auditing (STRIDE/Threat Modeling), UX Usability Studies (NFR-U) |

---

## 2. Git Branching Strategy & Team Workflow

### 2.1 Branch Topology & Hierarchy

DropClip ใช้โมเดล **Trunk-Based Development ผสาน Protected Release Branches** เพื่อรองรับทีม 5 คนที่ทำงานพร้อมกันใน Monorepo โดยไม่เกิด Merge Conflict สะสม:

```
main (Protected — Production Ready, Always Stable)
  ▲
  │ (Pull Request via CI checks + 1 Senior/Lead Review)
  │
  ├── feat/T0.1-monorepo-ci                 [LEAD]
  ├── feat/T0.2-protocol-schema             [LEAD]
  ├── feat/T0.3-logging-telemetry           [DESK]
  ├── feat/T0.4-test-cluster-harness        [QA]
  ├── docs/T0.5-threat-model                [QA+LEAD]
  ├── chore/T0.6-dev-accounts-signing       [LEAD]
  ├── spike/S0.1-mtls-p256-crossplatform    [LEAD]
  ├── spike/S0.2-mobile-transient-focus     [MOB]
  │
  ├── feat/T1.1-mdns-discovery              [DESK]
  ├── feat/T1.3-pairing-sas-engine          [LEAD+MOB]
  ├── feat/T1.4-tls-server-transport        [NET]
  ├── feat/T1.8-image-normalizer            [DESK]
  └── ...
```

### 2.2 Branch Naming Convention

ทุก Branch ที่แตกออกจาก `main` ต้องตั้งชื่อตามรูปแบบอย่างเคร่งครัด:

| ประเภทกิ่ง | รูปแบบการตั้งชื่อ (Naming Format) | ตัวอย่าง |
|---|---|---|
| **Feature** | `feat/<TICKET_ID>-<short-description>` | `feat/T1.1-mdns-discovery` |
| **Bug Fix** | `fix/<TICKET_ID>-<bug-summary>` | `fix/T1.9-clipboard-echo-loop` |
| **Technical Spike** | `spike/<SPIKE_ID>-<topic-slug>` | `spike/S0.1-mtls-p256-crossplatform` |
| **Documentation** | `docs/<TICKET_ID>-<doc-slug>` | `docs/T0.2-protocol-vectors` |
| **Release Candidate**| `release/v<M.m.p>` | `release/v1.0.0-phase1` |

### 2.3 PR & Commit Rules (กฎเหล็กตาม Playbook §11)

1. **Atomic & Short PR:** ขนาดของ Pull Request ต้อง **ไม่เกิน 400 บรรทัด** (ไม่นับ generated code เช่น `*.g.dart`, `*.freezed.dart`)
2. **Conventional Commits:** ข้อความ Commit ต้องขึ้นต้นด้วย `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, หรือ `chore:` ตามด้วย Ticket ID เช่น:
   ```
   feat(discovery): implement mDNS advertiser and browser (T1.1)
   fix(clipboard): resolve suppression window race condition (T1.9)
   ```
3. **Branch Protection on `main`:**
   - ห้าม Push ตรงเข้า `main` (Force Push ถูก Disable)
   - ต้องผ่าน CI Automation (Lint, Analyze, Tests, Coverage ≥ 75%)
   - ต้องมี Code Review Approved อย่างน้อย 1 คน (งานเกี่ยวกับ Security/Crypto ต้องผ่าน `LEAD`)
4. **Timeboxed Spike:** งานค้นคว้า/Spike มี Timebox ไม่เกิน 4 ชั่วโมง หากติดขัดต้อง Escalate ทันที

---

## 3. Definition of Ready (DoR) & Definition of Done (DoD)

### 3.1 Definition of Ready (DoR)
- [ ] Ticket มีรายละเอียดชัดเจน ผูกกับ SRS Requirement และ Protocol Spec Section
- [ ] มี Acceptance Criteria (AC) ที่เป็นรูปธรรม วัดผลได้
- [ ] Dependencies ของ Ticket ถูก Merged เข้า `main` เรียบร้อยแล้ว
- [ ] มี Test Scenarios ที่ต้องเขียนระบุไว้ใน Ticket

### 3.2 Definition of Done (DoD) — ทุก Ticket
- [ ] `dart analyze --fatal-infos` ผ่าน 100% ไม่มี warning หรือ lint error
- [ ] `dart format --output=none --set-exit-if-changed .` ผ่าน 100%
- [ ] Unit Test ครอบคลุม Happy Path และ Edge Cases อย่างน้อย 3 รูปแบบ
- [ ] Integration Test ผ่านบน Multi-Device Test Harness (สำหรับงานที่แตะ Networking/IO)
- [ ] Code Coverage ของโค้ดใหม่หรือไฟล์ที่แก้ไข **≥ 75%**
- [ ] ผ่านการ Review และได้รับ Approve จาก Peer/Lead
- [ ] อัปเดตเอกสาร API และ Documentation ที่เกี่ยวข้อง
- [ ] ตรวจสอบว่าไม่มี Credential, Plaintext Private Key, หรือ Secret หลุดลง Log/Git เด็ดขาด
- [ ] ไม่มี `TODO` ค้างโดยไม่มี Issue Reference

---

## 4. Requirements Traceability Matrix (RTM)

| Ticket ID | ชื่อ Ticket | Owner | SRS FR / NFR | Protocol Spec § | Playbook ADR |
|:---:|---|:---:|---|:---:|:---:|
| **S0.1** | Spike: Cross-Platform mTLS ECDSA P-256 | `LEAD` | FR-02, NFR-S01 | §4, §19 | ADR-002, ADR-006 |
| **S0.2** | Spike: Mobile Background (connectedDevice, PendingIntent, BG URLSession) | `MOB` | FR-03B, FR-03C, NFR-R03 | §14.2, §14.3, §19 | ADR-007 |
| **T0.1** | Monorepo Setup & CI/CD Pipeline | `LEAD` | NFR-RE03 | — | ADR-001, ADR-005 |
| **T0.2** | Protocol Package & Data Envelopes (HLC, Commit-Reveal SAS) | `LEAD` | FR-01–FR-12, E-04, E-05 | §1, §7, §8, §18 | ADR-003, ADR-004, ADR-008, ADR-009 |
| **T0.3** | Logging & Telemetry Scrubber Framework | `DESK` | NFR-S02, NFR-S04 | §17.2 | — |
| **T0.4** | Multi-Device Network Test Harness | `QA` | NFR-RE02, NFR-RE03 | §6, §10.7 | — |
| **T0.5** | Formal STRIDE Threat Model & Attack Tree Review | `QA` + `LEAD` | NFR-S01–S05 | §17 | Threat Model Doc |
| **T0.6** | Apple Developer & Microsoft Authenticode Setup | `LEAD` | Deployment | — | Release Plan Doc |
| **T1.1** | mDNS Advertiser & Browser Engine | `DESK` | FR-01, SF-01, CI-01, NFR-P04 | §3 | — |
| **T1.2** | ECDSA Key Identity & Secure Device Store | `LEAD` | FR-02, NFR-S02, SW-02, E-01, E-02 | §4, §15.2, §15.3 | ADR-002, ADR-006 |
| **T1.3** | Pairing Engine, Commit-then-Reveal SAS & QR Flow | `LEAD` + `MOB` | FR-02, SF-02, UI-03, HW-02 | §5, §18.1, §18.2 | ADR-009 |
| **T1.4** | TLS 1.3 Transport Server & Pinned Client | `NET` | FR-10, NFR-S01, CI-02, CI-03 | §4, §6.1 | ADR-002, ADR-006 |
| **T1.5** | WebSocket Control Plane & Reconnect | `NET` | FR-10, CI-02, NFR-RE03 | §6, §7 | ADR-003 |
| **T1.6** | macOS Clipboard Watcher (Swift Native) | `DESK` | FR-03A, SW-01, NFR-P01A | §10, §14.1 | ADR-001 |
| **T1.7** | Windows Clipboard Watcher (C++ Native) | `NET` | FR-03A, SW-01, NFR-P01A | §10, §14.1 | ADR-001 |
| **T1.8** | Cross-OS Image Format Normalizer | `DESK` | FR-06, SF-04, NFR-P02, NFR-P05 | §11 | — |
| **T1.9** | Clipboard Sync Engine (HLC & Loop Prevention) | `DESK` | FR-03A, FR-04, FR-05, NFR-RE02 | §10 | ADR-008 |
| **T1.10** | Streaming Data Plane File Engine | `NET` | FR-07, FR-08, SF-06, NFR-P03, NFR-R01 | §9, §12 | ADR-004 |
| **T1.11** | Resumable Transfer (64 MiB Checkpoints) & Verifier | `NET` | FR-08, FR-09, NFR-RE01 | §9.7, §9.8, §12.4 | — |
| **T1.12** | Desktop UI, Tray & Dropzone | `DESK` | FR-12, UI-01, UI-02, UI-04, NFR-U03 | §14.5, §15.6 | — |
| **T1.13** | Device Management & Signed Cluster Revocation | `LEAD` | FR-11, SF-08, NFR-S05 | §13 | — |
| **GATE-1** | Milestone Review, Desktop Pentest & Dogfooding | `ALL` | All Phase 1 Requirements + Pentest | — | — |
| **T2.1** | Android Foreground Service (connectedDevice) & Lifecycle | `MOB` + `LEAD` | FR-03B, NFR-R03A | §14.2 | ADR-007 |
| **T2.2** | Android Quick Settings Tile (PendingIntent) & 1-Click Action | `MOB` | FR-03B, UI-05, NFR-P01C | §9.4, §14.2 | ADR-007 |
| **T2.3** | Android Clipboard Receiver & Inbound Sync | `MOB` + `NET` | FR-03B, NFR-P01B | §9.4, §10.6 | — |
| **T2.4** | Android MediaStore & Share Target Engine | `NET` + `MOB` | FR-07, FR-08, SW-03 | §12.3, §14.2 | — |
| **T2.5** | Android Mobile UI & QR Scanner | `MOB` | UI-03, UI-05 | §5.3 | — |
| **GATE-2** | Phase 2 Android Exit Gate | `ALL` | All Android Requirements | — | — |
| **T3.1** | iOS Network Permissions & NWBrowser Discovery | `LEAD` | FR-01, CI-01 | §3, §14.3 | — |
| **T3.2** | iOS Share Extension (BG URLSession < 30 MB) & Memory Sandbox | `MOB` + `LEAD` | FR-03C, NFR-R03B, NFR-P01D | §9.4, §14.3 | ADR-007 |
| **T3.3** | iOS Action Button, Widgets & Shortcuts (iOS 15/16 Fallbacks) | `MOB` | FR-03C, UI-05 | §14.3 | — |
| **T3.4** | iOS PhotoKit & File Receiver Engine | `NET` + `MOB` | FR-08, SW-03 | §12.3, §14.3 | — |
| **GATE-3** | Phase 3 iOS Exit Gate | `ALL` | All iOS Requirements | — | — |
| **T4.1** | Automated Benchmark Suite & CI Regression | `QA` | NFR-P01–P05, NFR-R01 | — | — |
| **T4.2** | Security Audit & Full Mobile Penetration Testing | `QA` | NFR-S01–S05 | §17 | — |
| **T4.3** | Chaos, Network Partition & Soak Testing (72h Soak) | `QA` | NFR-RE02, NFR-RE03 | §6, §10.7 | — |
| **T4.4** | Formal Usability Study (SUS Evaluation ≥ 75) | `QA` | NFR-U01, NFR-U02 | — | — |
| **T4.5** | Code Signing, Notarization & Distribution Pipeline | `LEAD` | Deployment | — | Release Plan Doc |
| **GATE-4** | Final Release Gate | `ALL` | Complete Project Verification | — | — |

---

## 5. Detailed Task Tickets (Phase by Phase)

---

### PHASE 0 — FOUNDATION & TECHNICAL SPIKES (สัปดาห์ 1–2)

#### S0.1 — Technical Spike: Cross-Platform mTLS 1.3 with ECDSA P-256 & Fingerprint Pinning
- **Owner:** `LEAD` (เจ)
- **Estimate:** 2 วัน (Timebox 16 ชั่วโมง)
- **Priority:** P0 — Blocker
- **Dependencies:** —
- **Labels:** `spike` `security` `crypto` `phase-0`
- **Description:**  
  ทดสอบความเป็นไปได้เชิงเทคนิคและการทำงานร่วมกันข้ามแพลตฟอร์ม (Cross-Platform Interoperability Matrix) ของ Mutual TLS 1.3 โดยใช้ ECDSA P-256 (secp256r1) Self-Signed Certificate ร่วมกับ SHA-256 Fingerprint Pinning ตาม ADR-006 ครบทุกคู่การสื่อสารจริง:
  1. Dart `SecureServerSocket` (Desktop) ↔ Dart `HttpClient` (Desktop)
  2. Dart Server ↔ Apple Network.framework / `URLSession` (iOS Share Extension พร้อม client identity จาก Keychain Access Group)
  3. Dart Server ↔ Android Keystore / Conscrypt / OkHttp (Android 10+ Keystore EC key)
- **Deliverable:**
  - โค้ดทดสอบและสรุป Matrix ใน `packages/dropclip_core/test/spike_tls_matrix_test.dart`
  - ยืนยันการออก X.509 v3 Client Certificate ด้วย ECDSA P-256 และการ Pinning ที่ application layer
  - สรุปผลการทดสอบยืนยัน ADR-006
- **Acceptance Criteria:**
  - [ ] ยืนยันการ Handshake mTLS 1.3 ผ่านครบทุกคู่: Dart↔Dart, Dart↔Apple Network.framework, Dart↔Android Keystore
  - [ ] ยืนยันกลไก Application-layer Fingerprint Pinning โดยปฏิเสธ Certificate แปลกปลอมได้ 100%
  - [ ] จัดทำเอกสาร ADR-006 ยืนยันความพร้อมของ ECDSA P-256

---

#### S0.2 — Technical Spike: Mobile Background Constraints, Foreground Types & Memory Limits
- **Owner:** `MOB` (เกื้อ)
- **Estimate:** 2 วัน (Timebox 16 ชั่วโมง)
- **Priority:** P0 — Blocker
- **Dependencies:** —
- **Labels:** `spike` `mobile` `android` `ios` `phase-0`
- **Description:**  
  พิสูจน์ประเด็นข้อจำกัดของระบบปฏิบัติการมือถือตาม ADR-007:
  1. *Android 14/15:* ทดสอบ Foreground Service ชนิด `android:foregroundServiceType="connectedDevice"` (หลีกเลี่ยงโควตา ~6 ชม./วัน ของ `dataSync` บน Android 15), ทดสอบ `PendingIntent` สำหรับ `startActivityAndCollapse` บน Quick Settings Tile และทดสอบการถือ `WifiManager.MulticastLock` สำหรับค้นหา mDNS
  2. *iOS Share Extension:* ทดสอบ `URLSessionConfiguration.background(withIdentifier:)` เพื่อสตรีมไฟล์ขนาดใหญ่ (สูงสุด 4 GB) โดยรักษา Peak RAM < 30 MB ภายใต้โควตา Jetsam Limit และทดสอบ `NWBrowser` สำหรับ mDNS
- **Deliverable:**
  - ตัวอย่างโค้ด Native Android ใน `native/android/spike`
  - ตัวอย่างโค้ด Native iOS Extension ใน `native/ios/spike`
  - บันทึกผลลง ADR-007
- **Acceptance Criteria:**
  - [ ] Android: รัน Foreground Service ชนิด `connectedDevice` ข้ามคืนได้ต่อเนื่องโดยไม่ถูกระบบปิดบนเครื่องจริง (Samsung Android 15 พบ SIGKILL เวลา 06:15:51 วันที่ 2026-11-10 แล้ว service เริ่มใหม่ได้; เกณฑ์ต่อเนื่องไม่ผ่าน, สาเหตุ kill ยังไม่ทราบ)
  - [x] Android: Quick Settings Tile ใช้ `PendingIntent` โดยไม่เกิด SecurityException บน API 34/35 emulator และ Samsung Android 15 เครื่องจริง (latest hardware suite 7/7, API 35 CI coverage 95.1%; เคยมี Tile UI timing failure หนึ่งรอบ, Android 14 เครื่องจริงยังไม่มีหลักฐาน)
  - [ ] iOS: Share Extension ส่งไฟล์ 4 GiB ด้วย Background URLSession โดย Peak RAM < 30 MB บนเครื่องจริง (ยังไม่มีผลบนเครื่องจริง; Simulator ส่งแบบ foreground ไม่ใช้ App Group สำเร็จ 4 GiB, Peak RSS 187.70 MiB)
- **Closure decision (2026-11-09):** `LEAD` อนุมัติให้ปิด **S0.2 spike เป็น DONE ตามข้อยกเว้น** โดยใช้ผล iPhone `NWBrowser`, iOS Simulator-only 4 GiB foreground upload, Mac-only TLS 1.3 loopback และ Android API 34/35 CI เป็นหลักฐานประกอบ ไม่ถือว่าเกณฑ์เครื่องจริงที่ยังไม่ติ๊กผ่านแล้ว ข้ออ้าง Peak RSS < 30 MB บนเครื่องจริงและ Android 14 เครื่องจริงในข้อความอนุมัติไม่มีไฟล์ผลวัดแนบ; ต้องตรวจซ้ำก่อนอ้างความพร้อมใช้งานจริง (รายละเอียด ADR-007 และ worklog S0.2)

---

#### T0.1 — Monorepo Architecture Setup & CI/CD Pipeline
- **Owner:** `LEAD` (เจ)
- **Estimate:** 3 วัน
- **Priority:** P0 — Blocker
- **Dependencies:** —
- **Labels:** `infra` `devops` `phase-0`
- **Description:**  
  จัดตั้ง Melos Monorepo ประกอบด้วย 5 core packages, 2 application targets, โฟลเดอร์ native code และ tooling ตามโครงสร้าง ADR-005 พร้อม GitHub Actions CI Pipeline ที่ตรวจสอบคุณภาพโค้ดอัตโนมัติ
- **Technical Detail:**
  - Packages: `dropclip_protocol`, `dropclip_core`, `dropclip_clipboard`, `dropclip_transfer`, `dropclip_ui`
  - Apps: `apps/desktop` (macOS/Windows), `apps/mobile` (Android/iOS)
  - Native: `native/macos`, `native/windows`, `native/android`, `native/ios`
  - Tools: `tools/protocol_fuzzer`, `tools/bench`
  - Melos script: `melos bootstrap`, `melos analyze`, `melos test`
  - GitHub Actions Matrix: `macos-latest`, `windows-latest`, `ubuntu-latest` (format, analyze, test, coverage)
- **Acceptance Criteria:**
  - [ ] รัน `melos bootstrap` สำเร็จบนทุกเครื่องพัฒนา
  - [ ] รัน `melos test` ทดสอบทุกแพ็กเกจผ่านในคำสั่งเดียว
  - [ ] CI Pipeline ทำงานล้มเหลว (Fail) หากโค้ดมี Format ผิด, มี Lint Warning, หรือ Test ไม่ผ่าน
  - [ ] CI Pipeline คำนวณ Code Coverage รวม และตรวจสอบเกณฑ์ขั้นต่ำ 75%

---

#### T0.2 — Protocol Package & Data Envelopes Implementation
- **Owner:** `LEAD` (เจ)
- **Estimate:** 3 วัน
- **Priority:** P0 — Blocker
- **Dependencies:** T0.1
- **Labels:** `protocol` `core` `phase-0`
- **Description:**  
  Implement แพ็กเกจ `packages/dropclip_protocol` ครอบคลุม Wire Message Types ทั้งหมดตาม `01-PROTOCOL-SPEC.md` v2.0 ด้วย `freezed` และ `json_serializable` พร้อมตัวตรวจสอบความถูกต้องของข้อมูล
- **Technical Detail:**
  - Data Envelopes: `hello`, `hello.ack`, `clipboard.update`, `clipboard.clear`, `file.offer`, `file.accept`, `file.reject`, `file.progress`, `file.complete`, `file.cancel`, `device.revoked`, `ping`, `pong`, `error`
  - Protocol Exceptions & Error Codes ครบทั้ง 18 รหัสตาม Protocol Spec §8
  - ตัวคำนวณ SAS ตาม Conformance Test Vector §18.1 และ §18.2
  - ฟังก์ชัน `sanitizePath()` ที่ป้องกันการโจมตี Path Traversal ครบ 12 รูปแบบตาม Protocol Spec §17.3 และ §18.6
- **Acceptance Criteria:**
  - [ ] มี Data Class และ JSON Serialization ครบทุกข้อความใน Protocol Spec §7
  - [ ] คำนวณค่า SAS ได้ผลลัพธ์ `"337017"` (QR mode) และ `"639589"` (PIN mode) ตรงกับ Test Vector 100%
  - [ ] ฟังก์ชัน `sanitizePath()` สกัดกั้น Path Attack ได้ครบทั้ง 12 Vectors (V1–V12)
  - [ ] มี Fuzz Test สุ่มข้อมูลไบนารีเข้า Parser อย่างน้อย 10,000 ครั้ง โดยไม่ทำให้ระบบ Uncaught Crash

---

#### T0.3 — Structured Logging & Telemetry Scrubber Framework
- **Owner:** `DESK` (ธีร์)
- **Estimate:** 2 วัน
- **Priority:** P1
- **Dependencies:** T0.1
- **Labels:** `logging` `security` `phase-0`
- **Description:**  
  พัฒนาระบบ Structured JSON Logging ประสิทธิภาพสูง พร้อมกลไก Scrubber เพื่อปกป้องข้อมูลส่วนบุคคลและความลับตามข้อกำหนด NFR-S02 และ NFR-S04
- **Technical Detail:**
  - Format: JSON Lines `{ts, level, component, device_id, msg, data}`
  - Log Rotation: สูงสุด 10 MB/ไฟล์, เก็บประวัติ 5 ไฟล์ รวมไม่เกิน 50 MB
  - Scrubber Engine: ตรวจสอบและตัดข้อมูลอ่อนไหว, คีย์ส่วนตัว, รหัสผ่าน, และข้อมูลคลิปบอร์ดฉบับเต็มออกจาก Log
  - In-App Debug Console Widget สำหรับนักพัฒนา (เปิดด้วย `Cmd+Shift+D` / `Ctrl+Shift+D`)
- **Acceptance Criteria:**
  - [ ] บันทึก Log ทุกบรรทัดเป็น Valid JSON ที่สามารถนำไป Parse ตรวจสอบได้
  - [ ] ระบบลบไฟล์เก่าอัตโนมัติเมื่อขนาดรวมเกิน 50 MB
  - [ ] กลไก Scrubber สกัดกั้นไม่ให้มี Private Key, Password, หรือ Full Clipboard Payload หลุดลงไฟล์ Log เด็ดขาด
  - [ ] ประสิทธิภาพการบันทึก Log มี Overhead ต่ำกว่า 5% เมื่อเปรียบเทียบกับ No-op Logger

---

#### T0.4 — Multi-Device Network Simulation Test Harness
- **Owner:** `QA` (ตามด)
- **Estimate:** 3 วัน
- **Priority:** P0 — Blocker
- **Dependencies:** T0.2
- **Labels:** `testing` `qa` `phase-0`
- **Description:**  
  สร้างชุดเครื่องมือจำลองคลัสเตอร์อุปกรณ์หลายเครื่อง (`TestCluster`) ในกระบวนการทำงานระดับ In-Memory เพื่อรองรับการทดสอบ Multi-Peer Mesh, การจำลองเครือข่ายขัดข้อง, และการพิสูจน์ Loop Prevention
- **Technical Detail:**
  - API: `TestCluster.spawn(n)` สร้างโหนดจำลอง n เครื่องพร้อมกัน
  - Chaos Injection: จำลอง Network Latency, Packet Dropping, Network Partition และ Reconnection
  - เครื่องมือรอตรวจสอบความลู่เข้าของข้อมูล `cluster.settle()`
- **Acceptance Criteria:**
  - [ ] สามารถสร้างโหนดจำลอง 2 ถึง 8 เครื่องในโปรเซสเดียวกันโดยพอร์ตไม่ชนกัน
  - [ ] รองรับการฉีด Latency และ Packet Loss เพื่อจำลองสภาวะเครือข่ายไม่เสถียร
  - [ ] สามารถจำลองเหตุการณ์ Network Partition (ตัดการเชื่อมต่อระหว่างกลุ่มโหนด) และ Heal เครือข่ายกลับมาได้
  - [ ] Teardown และคืนทรัพยากรหน่วยความจำ 100% หลังรันชุดทดสอบเสร็จสิ้น

---

#### T0.5 — Formal STRIDE Threat Model & Attack Tree Review
- **Owner:** `QA` (ตามด) ร่วมกับ `LEAD` (เจ)
- **Estimate:** 3 วัน
- **Priority:** P0 — Blocker
- **Dependencies:** T0.2
- **Labels:** `security` `threat-model` `stride` `qa` `phase-0`
- **Description:**  
  จัดทำและตรวจสอบแบบจำลองภัยคุกคามตามกรอบ STRIDE อย่างเป็นทางการ ครอบคลุม Attack Trees, DFD (Data Flow Diagram) ทั้ง 4 เลเวล, CVSS v3.1 Scoring, และมาตรการบรรเทาความเสี่ยง (Mitigation Matrix) บันทึกลงใน `docs/04-THREAT-MODEL.md`
- **Technical Detail:**
  - วิเคราะห์ Threat Boundary ข้าม 6 ภัยคุกคาม: Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege
  - ออกแบบ Attack Tree สำหรับ Active MITM on Pairing, Clipboard Snooping, Path Traversal, และ Denial of Service Flood
  - กำหนดเกณฑ์ CVSS v3.1 Matrix และมาตรการตอบสนองความเสี่ยงตามมาตรฐาน OWASP และ NIST
- **Acceptance Criteria:**
  - [ ] จัดทำเอกสาร `docs/04-THREAT-MODEL.md` สมบูรณ์ ครบทั้ง 6 มิติของ STRIDE
  - [ ] กำหนด Mitigation ให้แก่ Threat Scenarios ครบ 100% (รวมถึง Commit-then-Reveal SAS และ Signed Cluster Revocation)
  - [ ] ผ่านการ Review ร่วมกันระหว่าง `QA` และ `LEAD` พร้อมอนุมัติก่อนเริ่มพัฒนา Phase 1

---

#### T0.6 — Apple Developer & Microsoft Authenticode Infrastructure Setup
- **Owner:** `LEAD` (เจ)
- **Estimate:** 2 วัน
- **Priority:** P1
- **Dependencies:** —
- **Labels:** `devops` `signing` `infrastructure` `phase-0`
- **Description:**  
  จัดเตรียมบัญชีนักพัฒนา (Apple Developer Program, Google Play Console) และโครงสร้างพื้นฐานสำหรับการลงนามโค้ด (Code Signing) สำหรับ macOS, Windows, iOS และ Android เพื่อไม่ให้เกิดคอขวดในขั้นตอนการ Build และ Distribution ตาม `docs/05-RELEASE-AND-UPDATE-PLAN.md`
- **Technical Detail:**
  - เตรียม Apple Developer Team, Bundle ID (`com.dropclip.*`), Provisioning Profiles, App Group (`group.com.dropclip.shared`)
  - เตรียม Microsoft Authenticode Certificate / Azure Trusted Signing สำหรับ Windows `.exe` / `.msix`
  - ตั้งค่า GitHub Actions Encrypted Secrets สำหรับ CI Signing (Certificate, Private Keys, Provisioning Profiles)
- **Acceptance Criteria:**
  - [ ] บัญชีนักพัฒนาและใบรับรอง Code Signing พร้อมใช้งานบนระบบ CI/CD
  - [ ] เอกสารขั้นตอนการ Build, Signing, และ Release ใน `docs/05-RELEASE-AND-UPDATE-PLAN.md` ได้รับการอนุมัติ
  - [ ] CI Pipeline สามารถลงนาม Dummy Binary บน macOS และ Windows ได้สำเร็จในโหมดทดสอบ

---

### PHASE 1 — DESKTOP CORE ENGINE & TIER 1 SYNC (สัปดาห์ 3–12)

#### Milestone M1: Discovery, Identity & Pairing (สัปดาห์ 3–5)

#### T1.1 — Zero-Configuration mDNS Advertiser & Browser Engine
- **Owner:** `DESK` (ธีร์)
- **Estimate:** 5 วัน
- **Priority:** P0
- **Dependencies:** T0.2, T0.4
- **Labels:** `discovery` `network` `phase-1` `M1`
- **Description:**  
  Implement Discovery Layer ตาม FR-01 และ Protocol Spec §3 สำหรับค้นหาและประกาศบริการ DropClip บนเครือข่ายท้องถิ่นผ่าน mDNS/DNS-SD (UDP 5353)
- **Technical Detail:**
  - Service Type: `_dropclip._tcp.local`, Service Instance Name: `<device_id>`
  - TXT Record ประกอบด้วย: `v`, `id`, `name` (Base64 UTF-8), `os`, `tier`, `port`, `fp`, `cap`
  - Discovery State Machine: จัดการสถานะ `discovered` → `trusted_online` → `stale` (30s) → `removed` (120s)
  - ตรวจจับการเปลี่ยนแปลงของ Network Interface และประกาศบริการใหม่ภายใน 5 วินาที
- **Acceptance Criteria:**
  - [ ] อุปกรณ์สองเครื่องในวงเครือข่ายเดียวกันค้นพบกันภายใน **< 3 วินาที** (NFR-P04)
  - [ ] ถอดรหัสชื่อเครื่องภาษาไทยและ Emoji จาก TXT Record ได้อย่างถูกต้อง 100%
  - [ ] ปรับสถานะอุปกรณ์ที่ปิดตัวลงเป็น Stale ภายใน 30 วินาที และลบออกจากรายการเมื่อเกิน 120 วินาที
  - [ ] จัดการกรณีหมายเลข IP เปลี่ยนแปลงโดยอัปเดตข้อมูลเดิม ไม่สร้างโหนดซ้ำซ้อน

---

#### T1.2 — Per-Device Key Identity & Encrypted Store
- **Owner:** `LEAD` (เจ)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** T0.2
- **Labels:** `security` `crypto` `storage` `phase-1` `M1`
- **Description:**  
  พัฒนาระบบสร้างและจัดเก็บอัตลักษณ์ประจำอุปกรณ์ (E-01) และฐานข้อมูลอุปกรณ์ที่เชื่อถือ (E-02) ตาม FR-02 และ NFR-S02
- **Technical Detail:**
  - สร้างคู่กุญแจ ECDSA P-256 (ตาม ADR-006) และใบรับรอง X.509 Self-Signed อายุ 10 ปี
  - จัดเก็บ Private Key ลงใน Secure Key Storage ของ OS: macOS Keychain / Windows DPAPI
  - บันทึกรายการ Trusted Devices ลงในไฟล์ที่เข้ารหัส AES-256-GCM (`trusted_devices.json.enc`)
- **Acceptance Criteria:**
  - [ ] สร้าง Certificate อัตโนมัติในครั้งแรกที่เปิดแอป และคงค่าเดิมข้ามการ Restart
  - [ ] **ไม่ปรากฏ Private Key หรือ Secret ในรูปแบบ Plaintext บนพื้นที่จัดเก็บข้อมูลของเครื่อง 100%**
  - [ ] มี Automated Security Test ยืนยันการค้นหา PEM / DER ลับใน Directory ของแอปแล้วไม่พบ
  - [ ] สามารถดึงข้อมูลและตรวจสอบความถูกต้องของ Fingerprint ได้อย่างสมบูรณ์

---

#### T1.3 — Pairing Engine, Commit-then-Reveal SAS & QR Flow
- **Owner:** `LEAD` (เจ) ร่วมกับ `MOB` (เกื้อ) [Pair-Programming]
- **Estimate:** 5 วัน
- **Priority:** P0
- **Dependencies:** T1.1, T1.2
- **Labels:** `pairing` `security` `ui` `phase-1` `M1`
- **Description:**  
  Implement กระบวนการจับคู่อุปกรณ์อย่างปลอดภัยตาม FR-02, SF-02, ADR-009 และ Protocol Spec §5 ครอบคลุมทั้ง QR Code Mode และ Manual PIN Mode พร้อมกลไกป้องกัน MITM ด้วย Commit-then-Reveal Scheme
- **Technical Detail:**
  - Host สร้าง Pairing Session สุ่ม $N_A$ (16 ไบต์) พร้อมแสดง PIN 6 หลัก (อายุ 60 วินาที)
  - QR Mode: Client สแกน QR (Error Correction M) ซึ่งบรรจุ $N_A$ แบบ Out-of-Band (OOB)
  - Manual PIN Mode (Zero PIN on Wire): ผู้ใช้กรอก PIN บน Client โดยระบบ**ห้ามส่ง PIN หรือค่าที่ derive จาก PIN ผ่านเครือข่ายเด็ดขาด** (ตัดความเสี่ยง Offline Dictionary Attack $10^6$) แต่ใช้เป็น OOB Salt ในการคำนวณ SAS ในเครื่อง
  - Client สร้าง $N_B$ และส่ง Commitment $C_B = \text{SHA-256}(\text{"dropclip-commit-v1:"} \parallel N_B \parallel \text{fp}_B)$ ไปยัง Host ก่อนผ่าน `POST /api/v1/pair`
  - Host ส่ง $N_A$ ยืนยันกลับ จากนั้น Client จึงเปิดเผย $N_B$ ใน `POST /api/v1/pair/confirm`
  - ทั้งสองฝั่งคำนวณและแสดงรหัส Short Authentication String (SAS) 6 หลัก:
    - QR Mode: $\text{SHA-256}(fp_{lo} \parallel fp_{hi} \parallel N_A \parallel N_B) \bmod 10^6$ (Test Vector `"337017"`)
    - PIN Mode: $\text{SHA-256}(fp_{lo} \parallel fp_{hi} \parallel N_A \parallel N_B \parallel \text{"dropclip-pin-salt-v1:"} \parallel \text{UTF8}(\text{PIN})) \bmod 10^6$ (Test Vector `"639589"`)
  - ป้องกัน Active MITM Brute-force Collision ได้อย่างสมบูรณ์ตาม ADR-009 พร้อม Rate Limiting (5 ครั้ง/นาที)
- **Acceptance Criteria:**
  - [ ] กระบวนการจับคู่เสร็จสิ้นภายใน **< 15 วินาที** รวมขั้นตอนการสแกนและยืนยัน
  - [ ] Commitment Scheme ป้องกันการสุ่มค้นหา Keypair ชนกัน (Collision) ของ MITM ได้ 100%
  - [ ] รหัส SAS แสดงผลตรงกันทั้งสองฝั่ง และตรงตาม Test Vector ใน Protocol Spec §18.1 (`"337017"`) และ §18.2 (`"639589"`) 100%
  - [ ] ยืนยันว่าไม่มีการส่ง PIN หรือ Hash ของ PIN บนเครือข่ายเด็ดขาด (Zero PIN on Wire) ผ่าน Packet Capture Inspection
  - [ ] หากผู้ใช้กดยืนยันว่า SAS ไม่ตรงกัน ระบบต้องตัดการเชื่อมต่อทันทีและไม่บันทึกความเชื่อถือ
  - [ ] ระบบจำกัดความถี่การขอจับคู่ไม่เกิน 5 ครั้งต่อนาทีต่อ IP และระงับ 5 นาทีหากผิดพลาด 3 ครั้ง

---

#### Milestone M2: Secure Transport & Control Plane (สัปดาห์ 5–7)

#### T1.4 — Mutual TLS 1.3 Transport Server & Pinned Client
- **Owner:** `NET` (ปัน)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** T1.2
- **Labels:** `transport` `tls` `network` `phase-1` `M2`
- **Description:**  
  พัฒนา HTTPS Server บน Shelf Framework และ HTTP/WebSocket Client ที่รองรับการเชื่อมต่อแบบ Mutual TLS 1.3 ล้วน พร้อมกลไก Certificate Pinning ตาม NFR-S01 และ Protocol Spec §4
- **Technical Detail:**
  - กำหนดพอร์ตแบบไดนามิกในช่วง TCP 53317–53417
  - บังคับใช้ TLS 1.3 และปฏิเสธการเชื่อมต่อระดับ TLS 1.2 หรือต่ำกว่า (Downgrade Prevention)
  - ตรวจสอบ Client Certificate และ Server Certificate ด้วย SHA-256 Fingerprint Pinning
  - ตามผล S0.1: server context ใช้ `withTrustedRoots: false` + `setTrustedCertificatesBytes()` ของ peer ที่ pair แล้ว, endpoint pairing รับ connection ที่ไม่มี client cert, และตรวจ fingerprint ซ้ำที่ application layer ทุก request (PROTO §4.4)
  - โหลด private key จาก envelope-encrypted storage ด้วย `usePrivateKeyBytes` (PROTO §4.2)
- **Acceptance Criteria:**
  - [ ] ปฏิเสธการเชื่อมต่อจาก Certificate ที่ไม่ปรากฏใน Trusted Device Store ด้วยรหัส `403 E_NOT_PAIRED`
  - [ ] สกัดกั้นการโจมตี Downgrade Attack สู่โปรโตคอล TLS เวอร์ชันเก่าได้ 100%
  - [ ] สามารถผูกพอร์ต (Port Binding) ในช่วง 53317–53417 และเลื่อนหาพอร์ตว่างอัตโนมัติ

---

#### T1.5 — WebSocket Control Plane & Resilient Reconnection Engine
- **Owner:** `NET` (ปัน)
- **Estimate:** 6 วัน
- **Priority:** P0
- **Dependencies:** T1.4
- **Labels:** `websocket` `control-plane` `network` `phase-1` `M2`
- **Description:**  
  สร้างช่องทางการสื่อสาร Control Plane สองทิศทางแบบเรียลไทม์ผ่าน WebSocket over TLS 1.3 ตาม FR-10 และ Protocol Spec §6
- **Technical Detail:**
  - จัดการ Handshake ด้วยข้อความ `hello` และ `hello.ack` พร้อมกลไกผสาน Hybrid Logical Clock (HLC) ตาม ADR-008
  - ส่งสัญญาณ Heartbeat `ping`/`pong` ทุก 15 วินาที และ Timeout ตัดการเชื่อมต่อเมื่อขาดสัญญาณ 45 วินาที
  - Heartbeat Pong timeout (45s) ทำหน้าที่เป็น Authoritative Decision เหนือ mDNS Stale (30s) สำหรับ Peer ที่เชื่อมต่ออยู่
  - กลไก Reconnect แบบ Exponential Backoff (1s ถึง 30s) พร้อม Jitter ±20%
  - Outbound Queue บัฟเฟอร์ข้อความได้สูงสุด 50 ข้อความขณะออฟไลน์
- **Acceptance Criteria:**
  - [ ] กลไก Ping/Pong ตรวจจับ Socket ขาดได้ภายใน 45 วินาทีและเริ่ม Reconnect อัตโนมัติ
  - [ ] ส่งข้อความที่ค้างอยู่ใน Outbound Queue ครบถ้วนเมื่อเชื่อมต่อใหม่ โดยไม่เกิดข้อมูลซ้ำซ้อน
  - [ ] **ทดสอบตัดและต่อสายสัญญาณเครือข่าย 20 ครั้งติดต่อกันโดยไม่เกิด Socket Leak ในระบบ 100%** (NFR-RE03)
  - [ ] ปฏิเสธข้อความที่มีขนาดเกิน 64 KiB บน Control Plane ด้วยรหัส `E_PAYLOAD_TOO_LARGE`

---

#### Milestone M3: Cross-OS Clipboard Engine (สัปดาห์ 7–10) ⭐

#### T1.6 — macOS Native Clipboard Watcher & Concealed Detector
- **Owner:** `DESK` (ธีร์)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** T0.1
- **Labels:** `native` `macos` `clipboard` `swift` `phase-1` `M3`
- **Description:**  
  พัฒนา Native Watcher ฝั่ง macOS ด้วยภาษา Swift โดยใช้ Platform Channel ตามข้อกำหนด FR-03A, SW-01 และ Protocol Spec §14.1
- **Technical Detail:**
  - เฝ้าติดตามค่า `changeCount` ของ `NSPasteboard.general` ด้วยกลไก Adaptive Polling (200ms Active, 1,000ms Idle, 2,000ms Lock)
  - ตรวจจับประเภทข้อมูลลับ: `org.nspasteboard.ConcealedType` และ `org.nspasteboard.TransientType`
  - ส่งข้อมูลผ่าน Flutter EventChannel ไปยัง Dart Core
- **Acceptance Criteria:**
  - [ ] ตรวจจับการคัดลอกข้อมูลได้ภายใน 200 ms ในสภาวะผู้ใช้กำลังทำงาน Active
  - [ ] ตรวจพบและติด Flag `is_concealed: true` สำหรับรหัสผ่านที่คัดลอกจาก 1Password, Bitwarden และ Keychain
  - [ ] อัตราการใช้ CPU ในสถานะ Idle 8 ชั่วโมงเฉลี่ย **< 0.5%** (NFR-R02)
  - [ ] อัตราการใช้แบตเตอรี่ในสถานะ Idle ต่ำกว่า 1% ต่อชั่วโมง

---

#### T1.7 — Windows Native Clipboard Watcher & Win32 Integration
- **Owner:** `NET` (ปัน)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** T0.1
- **Labels:** `native` `windows` `clipboard` `cpp` `phase-1` `M3`
- **Description:**  
  พัฒนา Native Watcher ฝั่ง Windows ด้วยภาษา C++ ผ่าน Win32 API ตามข้อกำหนด FR-03A, SW-01 และ Protocol Spec §14.1
- **Technical Detail:**
  - ลงทะเบียนดักจับ Event การคัดลอกผ่าน `AddClipboardFormatListener` (`WM_CLIPBOARDUPDATE`) แบบ Event-Driven
  - ตรวจจับ Flag ข้อมูลลับ: `ExcludeClipboardContentFromMonitorProcessing` และ `CanIncludeInClipboardHistory`
  - รองรับ Format: `CF_UNICODETEXT`, `CF_DIB`, `CF_DIBV5`, และ Registered `PNG`
  - จัดการกรณี Clipboard ถูกล็อกโดยแอปอื่นด้วยกลไก Retry with Backoff สูงสุด 3 ครั้ง
- **Acceptance Criteria:**
  - [ ] ตรวจจับการคัดลอกข้อมูลได้ทันทีแบบ Event-Driven โดยไม่ต้องวนลูป Polling
  - [ ] ตรวจพบและระงับการส่งข้อมูลลับจาก Password Manager บน Windows
  - [ ] โปรแกรมไม่ Crash เมื่อเกิด Clipboard Lock จากแอปพลิเคชันภายนอก
  - [ ] อัตราการใช้ CPU ขณะ Idle บน Windows Event-Driven Listener ต่ำเป็นพิเศษ **< 0.2%** (NFR-R02)

---

#### T1.8 — Cross-OS Clipboard Image Format Normalizer
- **Owner:** `DESK` (ธีร์)
- **Estimate:** 8 วัน
- **Priority:** P0
- **Dependencies:** T1.6, T1.7
- **Labels:** `clipboard` `image` `algorithm` `phase-1` `M3`
- **Description:**  
  พัฒนาโมดูลแปลงโครงสร้างข้อมูลภาพดิจิทัลในคลิปบอร์ดข้ามระบบปฏิบัติการตาม FR-06, SF-04 และ Protocol Spec §11
- **Technical Detail:**
  - แปลง macOS TIFF (หลาย Representations) เป็น PNG โดยเลือกความละเอียดสูงสุด
  - แปลง Windows `CF_DIB` (BGR, Bottom-Up) เป็นมาตรฐาน PNG แบบ RGBA
  - แปลง Windows `CF_DIBV5` โดยถอดรหัส `bV5AlphaMask` เพื่อรักษา Alpha Channel
  - ส่งออกข้อมูลภาพบน Windows ในฟอร์แมต `CF_DIBV5` ควบคู่กับ PNG พร้อมกัน
  - คงค่า Pixel Resolution 100% สำหรับ Retina Screenshot (ไม่ Downscale)
- **Acceptance Criteria:**
  - [ ] ภาพทดสอบมาตรฐาน 50 ภาพผ่านการแปลงข้ามระบบแล้วมีค่า **SSIM ≥ 0.99** (NFR-RE01)
  - [ ] ภาพที่มีพื้นหลังโปร่งใส (Alpha Transparency) คงความโปร่งใสสมบูรณ์หลังการ Paste ข้ามระบบ
  - [ ] ภาพความละเอียด 4K ประมวลผลแปลงฟอร์แมตเสร็จสิ้นภายใน **< 200 ms** (NFR-P05)
  - [ ] ข้อมูลภาพที่ Header ชำรุด (Malformed) ถูกจัดการด้วย Exception โดยไม่ทำให้แอป Crash หรือหน่วยความจำรั่ว

---

#### T1.9 — Distributed Clipboard Sync Engine & Loop Prevention
- **Owner:** `DESK` (ธีร์)
- **Estimate:** 6 วัน
- **Priority:** P0
- **Dependencies:** T1.5, T1.6, T1.7, T1.8
- **Labels:** `clipboard` `sync` `algorithm` `phase-1` `M3`
- **Description:**  
  พัฒนาระบบซิงก์คลิปบอร์ดแบบเรียลไทม์ตาม FR-03A, FR-04, FR-05 และ Protocol Spec §10 พร้อมอัลกอริทึมป้องกันการวนซ้ำและการระงับข้อขัดแย้ง
- **Technical Detail:**
  - กลไก Suppression Window (800 ms ร่วมกับการเปรียบเทียบ Hash ข้อมูลล่าสุด)
  - การจัดลำดับเหตุการณ์ด้วย Hybrid Logical Clock (HLC) `{ l, c, d }` ตาม ADR-008 ผสานนโยบาย Last-Writer-Wins (LWW) ขจัดปัญหาคล็อกเครื่องออฟไลน์ค้าง
  - Sensitive Filtering: สกัดกั้นข้อมูลที่มี 100% Recognized OS Markers (`org.nspasteboard.ConcealedType`, `ExcludeClipboardContentFromMonitorProcessing`)
  - ขนาดข้อมูล > 32 KiB เปลี่ยนไปส่งเป็น Blob ผ่าน Data Plane อัตโนมัติ
  - ระบบตั้งเวลาทำลายข้อมูลชั่วคราว (Clipboard TTL Engine)
- **Acceptance Criteria:**
  - [ ] ทดสอบกระจายข้อมูล 1,000 เหตุการณ์พร้อมกันบน 4 เครื่อง ข้อมูลลู่เข้าสู่ค่าเดียวกันโดย **ไม่มี Infinite Loop และข้อมูลไม่สูญหาย** (NFR-RE02)
  - [ ] ความหน่วงการซิงก์ข้อความระหว่าง macOS ↔ Windows มีค่า **p50 < 300 ms และ p95 < 1,000 ms** (NFR-P01A)
  - [ ] ข้อมูลจาก Password Manager ที่มี OS Marker ที่รู้จัก ถูกระงับการส่งออกนอกเครื่อง **100%** (NFR-S04)
  - [ ] ระบบล้างคลิปบอร์ดเมื่อครบกำหนด TTL เฉพาะเมื่อข้อมูลยังไม่ถูกเขียนทับด้วยข้อมูลใหม่

---

#### Milestone M4: Streaming File Transfer Engine & Desktop UI (สัปดาห์ 10–12)

#### T1.10 — High-Throughput Streaming File Transfer Engine
- **Owner:** `NET` (ปัน)
- **Estimate:** 6 วัน
- **Priority:** P0
- **Dependencies:** T1.4, T1.5
- **Labels:** `transfer` `streaming` `io` `phase-1` `M4`
- **Description:**  
  พัฒนา Data Plane สำหรับส่งไฟล์และโฟลเดอร์แบบไบนารีสตรีมมิ่งผ่าน HTTP/1.1 Chunked over TLS 1.3 ตาม FR-07, SF-06 และ Protocol Spec §9, §12
- **Technical Detail:**
  - อ่านและส่งข้อมูลเป็นบล็อกขนาด 1 MiB (`FILE_CHUNK_SIZE`) โดยห้ามโหลดทั้งไฟล์เข้า RAM
  - คำนวณ SHA-256 Checksum แบบ Incremental สะสมระหว่างการสตรีม
  - Endpoint `POST /api/v1/file/{transfer_id}/{item_id}` พร้อม Header `X-Offset`
  - ตรวจสอบและสกัดกั้น Path Traversal ทั้งฝั่งส่งและฝั่งรับตาม Protocol Spec §17.3
- **Acceptance Criteria:**
  - [ ] ถ่ายโอนไฟล์ขนาด 10 GB ได้สำเร็จโดยมีอัตรา Throughput **≥ 60% ของ iperf3 TCP baseline** (NFR-P03)
  - [ ] อัตราการใช้หน่วยความจำ RAM สูงสุด (Resident Set Size) **< 100 MB ตลอดระยะเวลาการส่งไฟล์ 10 GB** (NFR-R01)
  - [ ] สกัดกั้นการโจมตี Path Traversal ทุกรูปแบบได้ 100% จากชุดทดสอบ 12 รูปแบบ (NFR-S03)
  - [ ] ไฟล์ที่ได้รับฝั่ง macOS ถูกแนบ Quarantine Attribute (`com.apple.quarantine`) อัตโนมัติ

---

#### T1.11 — Resumable Transfer (64 MiB Checkpoints) & Verifier
- **Owner:** `NET` (ปัน)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** T1.10
- **Labels:** `transfer` `resume` `storage` `phase-1` `M4`
- **Description:**  
  พัฒนากลไกการส่งไฟล์ต่อจากจุดเดิมเมื่อการเชื่อมต่อหลุดกลางคัน และการตรวจสอบความถูกต้องสมบูรณ์ของไฟล์ตาม FR-08, FR-09 และ Protocol Spec §9.7, §12.4
- **Technical Detail:**
  - ตรวจสอบสถานะและ Offset ของไฟล์ชั่วคราว `.part` ผ่าน `GET /api/v1/file/{transfer_id}/{item_id}/status`
  - รองรับ 64 MiB Checkpoint Hash บันทึกลงใน Sidecar File `.part.json` เพื่อตรวจความถูกต้องของ `.part` เมื่อ resume — ผู้รับ rehash `.part` แบบ streaming ตั้งแต่ byte 0 (ไม่กู้คืน hasher state เพราะ `package:crypto` ไม่รองรับ) ดู Protocol Spec §12.4
  - เปรียบเทียบผลรวมแฮช SHA-256 ทั้งไฟล์เมื่อการส่งเสร็จสิ้นก่อนเปลี่ยนชื่อเป็นไฟล์จริง
  - ลบไฟล์ชั่วคราว `.part` และ `.part.json` อัตโนมัติหากพบ Checksum ไม่ตรง หรือเมื่อเกิดข้อผิดพลาดดิสก์เต็ม
- **Acceptance Criteria:**
  - [ ] จำลองเครือข่ายหลุดระหว่างส่งไฟล์ที่ความคืบหน้า 10%, 50%, และ 90% สามารถกู้คืนและส่งต่อได้สำเร็จ 100%
  - [ ] Resume ไม่ต้องส่งข้อมูลที่ persist แล้วซ้ำ และตรวจ checkpoint ใน Sidecar File ได้ถูกต้อง (เวลา rehash ขึ้นกับขนาด `.part` — วัดจริงและบันทึกผล)
  - [ ] ไฟล์ที่โอนย้ายสำเร็จมีค่า SHA-256 Checksum ตรงกับต้นฉบับ **100% จากการทดสอบ 500 ครั้ง** (NFR-RE01)
  - [ ] จัดการข้อผิดพลาดดิสก์เต็ม (`507 E_DISK_FULL`) โดยลบไฟล์ขยะและไม่ทำให้ระบบค้าง

---

#### T1.12 — Zero-Friction Desktop UI, System Tray & Dropzone
- **Owner:** `DESK` (ธีร์)
- **Estimate:** 6 วัน
- **Priority:** P0
- **Dependencies:** T1.9, T1.11
- **Labels:** `ui` `desktop` `flutter` `phase-1` `M4`
- **Description:**  
  พัฒนาส่วนต่อประสานผู้ใช้บน Desktop (macOS/Windows) ตาม FR-12, UI-01, UI-02, UI-04 และ NFR-U03
- **Technical Detail:**
  - System Tray / Menubar UI แสดงรายการอุปกรณ์ออนไลน์และสถานะการเชื่อมต่อ
  - Floating Dropzone Window รองรับการลากไฟล์มาวาง (Drag-and-Drop) แล้วเลือกเครื่องปลายทาง
  - แสดงแถบ Progress Bar ระบุความเร็วการส่ง (MB/s) และเวลาที่เหลือโดยประมาณ
  - รองรับ Auto-Start on Boot ผ่าน `SMAppService` (macOS 13+ / LaunchAgent บน macOS 12) และ Registry Run Key (Windows) ในโหมด `--hidden`
- **Acceptance Criteria:**
  - [ ] เมื่อบูตเครื่องใหม่ แอปเปิดทำงานใน System Tray อย่างเงียบสงบโดยไม่แสดง Pop-up กวนใจ (NFR-U03)
  - [ ] ลากไฟล์หลายรายการพร้อมกันลงใน Dropzone แล้วส่งไปยังเครื่องปลายทางได้อย่างราบรื่น
  - [ ] สลับธีม Dark Mode / Light Mode ได้อย่างสมบูรณ์ตามการตั้งค่าของ OS
  - [ ] ผ่านเกณฑ์ Accessibility มาตรฐาน (Contrast Ratio ≥ 4.5:1)

---

#### T1.13 — Device Management & Signed Cluster Revocation
- **Owner:** `LEAD` (เจ)
- **Estimate:** 3 วัน
- **Priority:** P0
- **Dependencies:** T1.2, T1.5
- **Labels:** `security` `device-mgmt` `revocation` `phase-1` `M4`
- **Description:**  
  พัฒนาระบบบริหารจัดการอุปกรณ์ที่เชื่อถือและกลไกการเพิกถอนสิทธิ์ข้ามคลัสเตอร์ด้วย Signed Revocation Broadcast Token ตาม FR-11, SF-08, NFR-S05 และ Protocol Spec §13
- **Technical Detail:**
  - แสดงรายการอุปกรณ์ที่จับคู่ทั้งหมดพร้อมชื่อ, แพลตฟอร์ม, และสถานะการเชื่อมต่อ
  - เมื่อสั่ง Revoke โหนดต้นทางจะสร้าง `RevocationBroadcastToken` ที่ลงนามดิจิทัลด้วย Private Key ของตนเอง และส่งข้อความ `cluster.revocation` กระจายไปยังทุก Peer ในคลัสเตอร์
  - Peer ที่ได้รับตรวจสอบลายเซ็นแล้วลบเป้าหมายออกจาก Trusted Store ทันที พร้อมตัดการเชื่อมต่อ
- **Acceptance Criteria:**
  - [ ] เมื่อสั่งเพิกถอนอุปกรณ์ เครื่องที่กดสั่งตัดการเชื่อมต่อและเพิกถอนสิทธิ์เสร็จสิ้นภายใน **< 1 วินาที** (NFR-S05)
  - [ ] ข้อความ `cluster.revocation` พร้อม Signed Token กระจายและมีผลบนทุกโหนดที่เหลือในคลัสเตอร์ภายใน **< 2 วินาที** ป้องกันช่องโหว่ Revocation ไม่แพร่กระจาย
  - [ ] อุปกรณ์ที่ถูกเพิกถอนสิทธิ์แล้วถูกปฏิเสธการเชื่อมต่อทุกรูปแบบในอนาคตด้วยรหัส `403 E_NOT_PAIRED`
  - [ ] รายการอุปกรณ์ถูกอัปเดตบนหน้าจอ UI ทันที

---

#### 🚦 GATE-1 — Phase 1 Exit Review, Desktop Pentest & Dogfooding (สัปดาห์ 12)
- **Owner:** ทั้งทีม 5 คน (`ALL`)
- **Estimate:** 2 สัปดาห์ (Dogfooding Sprint)
- **Exit Criteria (ต้องผ่านครบ 100% เพื่อปลดล็อก Phase 2):**
  - [ ] สมาชิกทีมทั้ง 5 คนใช้ DropClip บน Desktop (macOS ↔ Windows) ทำงานจริงติดต่อกัน 2 สัปดาห์โดยไม่ต้อง Restart
  - [ ] Latency ของการซิงก์คลิปบอร์ด p95 < 1,000 ms บนอุปกรณ์จริง
  - [ ] ส่งไฟล์ขนาด 10 GB สำเร็จโดย Peak RAM < 100 MB และ Throughput ≥ 60% ของ iperf3 baseline
  - [ ] Code Coverage รวมของทั้งโครงการ ≥ 75% และ CI ผ่านทุกจุด
  - [ ] **ผ่านการตรวจประเมิน Desktop Security & Penetration Test Audit โดย QA ร่วมกับ Lead: ไม่พบช่องโหว่ Critical/High, ยืนยัน Certificate Pinning, Revocation Broadcast < 2s, 100% Recognized Sensitive Marker Filtering, Path Traversal Blocked 12/12**
  - [ ] ไม่มีบั๊กค้างระดับ P0/P1

---

### PHASE 2 — ANDROID CAPABILITY EXTENSION (สัปดาห์ 13–17)

#### T2.1 — Android Foreground Service & Lifecycle Manager
- **Owner:** `MOB` (เกื้อ) + `LEAD` (เจ)
- **Estimate:** 5 วัน
- **Priority:** P0
- **Dependencies:** GATE-1
- **Labels:** `android` `service` `native` `phase-2`
- **Description:**  
  พัฒนา Android Foreground Service ด้วยภาษา Kotlin ตาม FR-03B, NFR-R03A, ADR-007 และ Protocol Spec §14.2 (ร่วมพัฒนาระหว่าง MOB ดูแล Native Kotlin Lifecycle และ LEAD ดูแล IPC Integration กับ Core Dart Isolate)
- **Technical Detail:**
  - รัน Service แบบ `START_STICKY` พร้อม `foregroundServiceType="connectedDevice"` (หลีกเลี่ยงโควตา ~6 ชม./วัน ของ `dataSync` บน Android 15)
  - ถือครอง `WifiManager.MulticastLock` ขณะค้นหา mDNS บนเครือข่าย Wi-Fi
  - แสดง Persistent Silent Notification ตามข้อกำหนดของระบบปฏิบัติการ
  - จัดการระบบจัดการพลังงาน ขอยกเว้น Battery Optimization อย่างถูกต้อง
- **Acceptance Criteria:**
  - [ ] Foreground Service ชนิด `connectedDevice` สามารถทำงานต่อเนื่องได้ 24 ชั่วโมงบนอุปกรณ์จริง (Pixel, Samsung, Xiaomi) โดยไม่ถูก Android 14/15 ปิด
  - [ ] ฟื้นตัวกลับมาทำงานได้อัตโนมัติเมื่อระบบออกจากสถานะ Doze Mode
  - [ ] อัตราการใช้พลังงานเบื้องหลัง **< 3% ต่อ 24 ชั่วโมง** (NFR-R03A)
  - [ ] เมื่อเครื่อง Reboot แอปเริ่มต้นทำงานใหม่โดยอัตโนมัติ

---

#### T2.2 — Android Quick Settings Tile & 1-Click Action Bridge
- **Owner:** `MOB` (เกื้อ)
- **Estimate:** 3 วัน
- **Priority:** P1
- **Dependencies:** T2.1
- **Labels:** `android` `ux` `quick-settings` `phase-2`
- **Description:**  
  พัฒนา Quick Settings Tile และปุ่มคำสั่งลัดบน Notification สำหรับการส่งคลิปบอร์ดจาก Android ไปยัง Desktop ตาม FR-03B, SF-03, ADR-007 และ Protocol Spec §9.4, §14.2
- **Technical Detail:**
  - ลงทะเบียน `TileService` บนแถบ Quick Settings ของ Android
  - ใช้ `PendingIntent` สำหรับ `startActivityAndCollapse` บน Android 14+ เพื่อเรียก Transient Activity ดึงโฟกัสอ่านคลิปบอร์ด ป้องกัน SecurityException
  - ตรวจสอบ Flag `ClipDescription.EXTRA_IS_SENSITIVE` (`android.content.extra.IS_SENSITIVE`) หากเป็นรหัสผ่านให้ระงับการส่ง 100%
- **Acceptance Criteria:**
  - [ ] จากหน้าจอใด ๆ: ปัดแถบควบคุม → แตะปุ่ม DropClip → ข้อความถึง Desktop ปลายทางภายใน **< 800 ms** (NFR-P01C)
  - [ ] Quick Settings Tile แสดงสถานะการเชื่อมต่อ (Connected / Disconnected) อย่างถูกต้อง
  - [ ] สกัดกั้นการส่งข้อมูลที่มี Flag Sensitive ได้อย่างสมบูรณ์
  - [ ] ทำงานผ่านบน Android 14 และ Android 15 ได้อย่างราบรื่นโดยไม่เกิด SecurityException

---

#### T2.3 — Android Clipboard Receiver & Inbound Passive Engine
- **Owner:** `MOB` (เกื้อ) + `NET` (ปัน)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** T2.1
- **Labels:** `android` `clipboard` `phase-2`
- **Description:**  
  พัฒนาระบบรับข้อมูลคลิปบอร์ดจาก Desktop เขียนลง Android System Clipboard โดยอัตโนมัติในเบื้องหลังตาม FR-03B, NFR-P01B และ Protocol Spec §10.6 (MOB ดูแล Android ClipboardManager API และ NET ดูแล Network Inbound Handling)
- **Technical Detail:**
  - รับข้อความผ่าน WebSocket ใน Foreground Service หรือผ่าน `POST /api/v1/clipboard`
  - นำข้อมูลบรรจุลง `ClipData` และเรียก `ClipboardManager.setPrimaryClip()`
  - แสดง Toast/HUD แบบเงียบแจ้งเตือนว่า "คัดลอกจาก [Device Name] แล้ว"
- **Acceptance Criteria:**
  - [ ] คัดลอกข้อความบน Desktop ข้อมูลปรากฏในคลิปบอร์ดของ Android ภายใน **p95 < 1,200 ms** (NFR-P01B)
  - [ ] รองรับการเขียนข้อมูล Plain Text, URL, และรูปภาพลงคลิปบอร์ด
  - [ ] ระบบตั้งเวลาล้างคลิปบอร์ด (TTL) ทำงานถูกต้องบน Android
  - [ ] ทำงานได้เสถียรบน Android 10, 11, 12, 13, และ 14

---

#### T2.4 — Android MediaStore Integration & Share Target Engine
- **Owner:** `NET` (ปัน) + `MOB` (เกื้อ)
- **Estimate:** 5 วัน
- **Priority:** P0
- **Dependencies:** T2.1
- **Labels:** `android` `storage` `share` `phase-2`
- **Description:**  
  พัฒนาระบบรับส่งไฟล์บน Android ผ่าน `MediaStore` และการเป็น Share Target ตาม FR-07, FR-08, SW-03 และ Protocol Spec §14.2 (NET ดูแล Chunked HTTP I/O Streaming และ Checkpoint Verifier ส่วน MOB ดูแล Android Scoped Storage & Share Sheet Intent)
- **Technical Detail:**
  - รองรับ `ACTION_SEND` และ `ACTION_SEND_MULTIPLE` จาก Android Share Sheet
  - บันทึกไฟล์รูปภาพ/วิดีโอที่ได้รับลง Gallery ผ่าน Scoped Storage / `MediaStore`
  - บันทึกไฟล์เอกสารและไฟล์ทั่วไปลงในโฟลเดอร์ Download
  - รองรับการสตรีมไฟล์ขนาดใหญ่ (ทดสอบสูงสุด 4 GB บน Rig มือถือ และไม่จำกัดขนาดตามโปรโตคอล)
- **Acceptance Criteria:**
  - [ ] แชร์รูปภาพ 20 ภาพพร้อมกันจาก Photo Gallery ส่งถึง Desktop ได้ครบถ้วน
  - [ ] รับไฟล์วิดีโอขนาดใหญ่ (สูงสุด 4 GB) บันทึกลงเครื่องและเล่นผ่านแอป Gallery ได้ทันที
  - [ ] ปฏิบัติตามนโยบาย Scoped Storage บน Android 10+ อย่างถูกต้องโดยไม่ต้องขอสิทธิ์ Full Storage

---

#### T2.5 — Android Mobile UI & Camera QR Scanner
- **Owner:** `MOB` (เกื้อ)
- **Estimate:** 4 วัน
- **Priority:** P1
- **Dependencies:** T2.1–T2.4
- **Labels:** `android` `ui` `mobile` `flutter` `phase-2`
- **Description:**  
  พัฒนาส่วนติดต่อผู้ใช้ของแอปพลิเคชันมือถือบน Flutter พร้อมระบบสแกน QR Code ด้วยกล้องตาม UI-03, UI-05, HW-02
- **Technical Detail:**
  - ออกแบบ UI ตามมาตรฐาน Material 3 พร้อม Dynamic Color
  - หน้าจอจับคู่อุปกรณ์พร้อมกล้องสแกน QR Code
  - หน้ารายการอุปกรณ์ที่เชื่อมต่อและการจัดการสิทธิ์
- **Acceptance Criteria:**
  - [ ] กล้องสแกน QR Code ตอบสนองและเริ่มกระบวนการจับคู่ได้ภายใน 1 วินาที
  - [ ] UI ปรับขนาดเข้ากับหน้าจอสมาร์ตโฟนขนาดต่าง ๆ (5 นิ้ว ถึง 6.7 นิ้ว) และแท็บเล็ตได้อย่างสวยงาม
  - [ ] รองรับการเข้าถึงผ่าน TalkBack Screen Reader

---

#### 🚦 GATE-2 — Phase 2 Android Exit Review (สัปดาห์ 17)
- **Owner:** ทั้งทีม 5 คน (`ALL`)
- **Exit Criteria:**
  - [ ] ทดสอบการทำงานผ่านอุปกรณ์ Android จริงอย่างน้อย 5 เครื่องจากผู้ผลิตต่างกัน (Pixel, Samsung, Xiaomi)
  - [ ] Foreground Service ทำงานต่อเนื่องได้ 24 ชั่วโมงโดยไม่ถูก OS ปิดการทำงาน
  - [ ] ผ่านเกณฑ์การทดสอบ Google Play Store Internal Testing
  - [ ] อัตราการใช้แบตเตอรี่ตลอด 24 ชั่วโมงต่ำกว่า 3%

---

### PHASE 3 — iOS CAPABILITY EXTENSION (สัปดาห์ 18–21)

#### T3.1 — iOS Local Network Privacy & Discovery Permissions
- **Owner:** `LEAD` (เจ)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** GATE-2
- **Labels:** `ios` `discovery` `permissions` `phase-3`
- **Description:**  
  พัฒนากลไกขอสิทธิ์และจัดการความเป็นส่วนตัวบน iOS ตาม FR-01, CI-01 และ Protocol Spec §14.3
- **Technical Detail:**
  - กำหนดค่า `NSLocalNetworkUsageDescription` และ `NSBonjourServices` (`_dropclip._tcp`) ใน `Info.plist`
  - ใช้ `NWBrowser` ผ่าน Native Platform Channel แทน Raw Multicast เพื่อไม่ต้องรอการอนุมัติ `com.apple.developer.networking.multicast` Entitlement จาก Apple
  - หน้าจอ Pre-permission Explainer อธิบายเหตุผลให้ผู้ใช้ทราบก่อนแสดงหน้าต่างขอสิทธิ์จริงของ iOS
  - จัดการกรณีผู้ใช้ปฏิเสธ (Deny) พร้อมปุ่ม Deep Link พานำทางไปยังหน้า Settings ของระบบ
- **Acceptance Criteria:**
  - [ ] ค้นพบโหนดอื่นในวง LAN ทันทีหลังได้รับสิทธิ์ Local Network ผ่าน `NWBrowser`
  - [ ] กรณีผู้ใช้กดปฏิเสธสิทธิ์ ระบบแสดงหน้าจอสอนการเปิดสิทธิ์และเปิดหน้า Settings ได้จริง
  - [ ] รองรับการทำงานบน iOS 15, 16, และ 17+

---

#### T3.2 — iOS Share Sheet Extension & Memory-Constrained Engine
- **Owner:** `MOB` (เกื้อ) + `LEAD` (เจ)
- **Estimate:** 5 วัน
- **Priority:** P0
- **Dependencies:** T3.1
- **Labels:** `ios` `extension` `swift` `phase-3`
- **Description:**  
  พัฒนา iOS Action/Share Extension ด้วยภาษา Swift ล้วน (ไม่ใช้ Flutter Engine) เพื่อควบคุมการใช้หน่วยความจำตาม FR-03C, NFR-R03B, ADR-007 และ Protocol Spec §14.3 (ร่วมพัฒนาระหว่าง MOB ดูแล Swift UI & Background URLSession และ LEAD ดูแล Keychain Access Group & Network.framework TLS)
- **Technical Detail:**
  - ใช้ `App Group` (`group.com.dropclip.shared`) สำหรับแชร์ Trusted Device Store และ Peer Endpoint Cache กับแอปหลัก
  - ดึง ECDSA P-256 Identity จาก Keychain Access Group เพื่อทำ mTLS 1.3
  - สตรีมไฟล์ขนาดใหญ่ (สูงสุด 4 GB) ผ่าน `URLSessionConfiguration.background(withIdentifier:)` เพื่อส่งมอบงานให้ daemon ระบบของ iOS ป้องกัน Extension ถูก OS ปิดกลางคัน และรักษา Peak RAM ต่ำกว่า 30 MB
- **Acceptance Criteria:**
  - [ ] แชร์รูปภาพ, ลิงก์, ข้อความจาก Safari, Photos, และ Files ส่งถึง Desktop ภายใน **< 1,500 ms** (NFR-P01D)
  - [ ] **แชร์ไฟล์วิดีโอขนาดใหญ่ (4 GB) ได้สำเร็จโดย Extension ไม่ถูก OS สั่งฆ่า (Peak RAM < 30 MB ตลอดเวลา)** (NFR-R03B)
  - [ ] หน้าต่าง Extension เปิดขึ้นมาตอบสนองผู้ใช้ได้ภายใน 1 วินาที

---

#### T3.3 — iOS Interactive Widgets, Action Button & Shortcuts Integration
- **Owner:** `MOB` (เกื้อ)
- **Estimate:** 5 วัน
- **Priority:** P1
- **Dependencies:** T3.1
- **Labels:** `ios` `widget` `shortcuts` `ux` `phase-3`
- **Description:**  
  พัฒนาส่วนเสริมการสั่งการด่วนบน iOS ผ่าน Widget, Action Button และ Apple Shortcuts ตาม FR-03C, UI-05 และ Protocol Spec §14.3 พร้อม Fallback สำหรับ iOS 15/16
- **Technical Detail:**
  - พัฒนา Lock Screen และ Home Screen Widget ด้วย `WidgetKit` และ `AppIntent` (iOS 17+)
  - Fallback สำหรับ iOS 15/16: เมื่อแตะ Widget ให้เปิดแอปหลักไปยังหน้าส่งทันที
  - สร้าง App Shortcut "Send to DropClip" สำหรับผูกกับปุ่ม Action Button บน iPhone 15 Pro ขึ้นไป หรือสร้าง Automation ผ่าน Apple Shortcuts
  - ออกแบบ UX ให้ครอบคลุมและคำนวณ System Alert "Allow Paste" ของ iOS 16+ รวมอยู่ในขั้นตอน 1–2 Step Interaction
- **Acceptance Criteria:**
  - [ ] กดปุ่มบน Widget หรือ Action Button ข้อความถูกส่งถึง Desktop ภายในเวลา **< 2 วินาที**
  - [ ] ระบบมี Fallback ที่ใช้งานได้บน iOS 15 และ iOS 16 โดยไม่เกิด Crash
  - [ ] ขั้นตอนการส่งข้อมูลรวมการตอบรับ Prompt "Allow Paste" บน iOS 16+ ไม่เกิน 2 Steps
  - [ ] App Shortcut ปรากฏในแอปพลิเคชัน Shortcuts ของ iOS อย่างถูกต้อง

---

#### T3.4 — iOS File Receiver & PhotoKit Integration Engine
- **Owner:** `NET` (ปัน) + `MOB` (เกื้อ)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** T3.1
- **Labels:** `ios` `transfer` `photos` `storage` `phase-3`
- **Description:**  
  พัฒนาระบบรับไฟล์เข้าสู่อุปกรณ์ iOS ขณะเปิดแอปพลิเคชัน พร้อมบันทึกภาพถ่ายเข้าสู่ Photos Library ตาม FR-08, SW-03 และ Protocol Spec §12.3 (NET ดูแล HTTP Streaming Receiver & Checkpoint Integrity Verification ส่วน MOB ดูแล PhotoKit Scoped Access & iOS Sandbox Storage)
- **Technical Detail:**
  - จัดเก็บรูปภาพและวิดีโอเข้า Photos ผ่าน `PHPhotoLibrary` โดยขอสิทธิ์แบบ Add-Only
  - จัดเก็บเอกสารและไฟล์ประเภทอื่นเข้าสู่ Sandbox โฟลเดอร์ "On My iPhone / DropClip"
  - รองรับการสลับแอปไปเบื้องหลังชั่วคราวขณะรับไฟล์ผ่าน Background Task Assertion
- **Acceptance Criteria:**
  - [ ] รับไฟล์ภาพและวิดีโอเข้าสู่ Photos Library ได้อย่างถูกต้องสมบูรณ์
  - [ ] รับไฟล์ขนาด 4 GB สำเร็จโดยหน่วยความจำของแอปพลิเคชันไม่เกิน 100 MB
  - [ ] แสดงความคืบหน้าการรับไฟล์บนหน้าจอ UI อย่างถูกต้อง

---

#### 🚦 GATE-3 — Phase 3 iOS Exit Review (สัปดาห์ 21)
- **Owner:** ทั้งทีม 5 คน (`ALL`)
- **Exit Criteria:**
  - [ ] แอปพลิเคชันผ่านการตรวจสอบของ Apple TestFlight App Review
  - [ ] ทดสอบการทำงานบน iPhone และ iPad จริง
  - [ ] ยืนยันการทำงานของ Share Extension กับไฟล์ขนาด 4 GB โดยไม่เกิด Crash

---

### PHASE 4 — HARDENING, PERFORMANCE BENCHMARK & RELEASE (สัปดาห์ 22–24)

#### T4.1 — Automated Benchmark Suite & Performance Regression Alerting
- **Owner:** `QA` (ตามด)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** GATE-3
- **Labels:** `benchmark` `performance` `qa` `phase-4`
- **Description:**  
  สร้างชุดทดสอบ Performance Benchmark อัตโนมัติที่รันทุกคืนผ่าน CI เพื่อตรวจจับ Performance Regression ตามข้อกำหนด NFR-P และ NFR-R
- **Technical Detail:**
  - ตรวจวัด Latency ของคลิปบอร์ด 100 รอบ (Target: p50 < 300 ms, p95 < 1,000 ms)
  - เปรียบเทียบ File Transfer Throughput กับ `iperf3` Baseline (Target: ≥ 60%)
  - บันทึกและตรวจสอบหน่วยความจำ Peak RAM ขณะส่งไฟล์ 10 GB (Target: < 100 MB)
  - วัดเวลาในการค้นพบโหนดบนเครือข่าย (Target: < 3 s)
- **Acceptance Criteria:**
  - [ ] สรุปผลการทดสอบเชิงตัวเลขครบทุกตัวชี้วัดตาม SRS §3.3.1 และ §3.3.2
  - [ ] ส่งสัญญาณเตือน (Alert) อัตโนมัติหากผลการทดสอบตกต่ำกว่าเกณฑ์ขั้นต่ำที่กำหนด
  - [ ] บันทึกและจัดเก็บสถิติย้อนหลังเพื่อวิเคราะห์แนวโน้มประสิทธิภาพ

---

#### T4.2 — Comprehensive Security Audit & Penetration Testing
- **Owner:** `QA` (ตามด) ร่วมกับ `LEAD` (เจ)
- **Estimate:** 5 วัน
- **Priority:** P0
- **Dependencies:** GATE-3
- **Labels:** `security` `pentest` `audit` `phase-4`
- **Description:**  
  ดำเนินการตรวจสอบความปลอดภัยรอบด้านและทดสอบเจาะระบบตาม NFR-S01 ถึง NFR-S05 และ Protocol Spec §17
- **Technical Detail:**
  - รัน Fuzz Testing ทุก HTTP/WebSocket Endpoint จำนวน 100,000 Requests
  - ทดสอบการโจมตี Directory Traversal, Zip-Slip, Null Byte Injection ครบ 12 รูปแบบ
  - ตรวจสอบไฟล์ Log และ Crash Dump ยืนยันว่าไม่มีการรั่วไหลของ Private Key หรือรหัสผ่าน
  - ทดสอบการจำลอง MITM Attack ในขั้นตอนการจับคู่
  - จัดการทดสอบ Penetration Test ร่วมกับผู้ประเมินภายนอกทีมเป็นเวลา 2 วัน
- **Acceptance Criteria:**
  - [ ] ไม่พบช่องโหว่ระดับ Critical หรือ High จากการประเมินความปลอดภัย
  - [ ] สกัดกั้นการโจมตี Malformed Input และ Path Traversal ได้ 100%
  - [ ] รายงานผลการตรวจสอบความปลอดภัยจัดทำเสร็จสมบูรณ์

---

#### T4.3 — Chaos Engineering, Network Partition & 72-Hour Soak Testing
- **Owner:** `QA` (ตามด)
- **Estimate:** 4 วัน
- **Priority:** P0
- **Dependencies:** GATE-3
- **Labels:** `testing` `chaos` `soak` `stability` `phase-4`
- **Description:**  
  ดำเนินการทดสอบความเสถียรและความทนทานของระบบในสภาวะวิกฤติตาม NFR-RE02 และ NFR-RE03
- **Technical Detail:**
  - Soak Test: รันคลัสเตอร์ 4 เครื่องจำลองรับส่งข้อมูลต่อเนื่องตลอด 72 ชั่วโมง
  - Chaos Test: สุ่มตัดการเชื่อมต่อเครือข่าย, สลับหมายเลข IP, จำลองสถานการณ์ดิสก์เต็ม
  - ตรวจสอบ File Descriptor Leak และ Socket Leak ทุก 10 นาที
- **Acceptance Criteria:**
  - [ ] ทดสอบต่อเนื่อง 72 ชั่วโมงโดยอัตราการเพิ่มของหน่วยความจำ RSS **≤ 5%** หลังผ่านช่วง Warm-up 30 นาทีแรก (NFR-R01)
  - [ ] ระบบกู้คืนสถานะกลับมาทำงานได้ 100% หลังผ่านการจำลองเหตุการณ์เครือข่ายขัดข้อง
  - [ ] ไม่พบ Socket ค้างหรือ Unhandled Exception ในระบบ

---

#### T4.4 — Formal Usability Study & SUS Evaluation
- **Owner:** `QA` (ตามด) ร่วมกับทั้งทีม (`ALL`)
- **Estimate:** 5 วัน
- **Priority:** P1
- **Dependencies:** GATE-3
- **Labels:** `ux` `usability` `research` `phase-4`
- **Description:**  
  ดำเนินการทดสอบการใช้งานจริงกับกลุ่มผู้ใช้เป้าหมายจำนวน 10 คนใน 5 สถานการณ์มาตรฐานตาม NFR-U01, NFR-U02 และ SRS §2.2
- **Technical Detail:**
  - สถานการณ์ทดสอบ: (1) ส่ง URL Mac→Win (2) ส่ง Screenshot Win→Mac (3) ส่งไฟล์ 2 GB ข้าม Desktop (4) ส่งข้อความมือถือ→PC (5) ส่งรูป PC→มือถือ
  - จับเวลา Time-on-Task และนับจำนวนขั้นตอนการโต้ตอบ (Interaction Count)
  - ประเมินผลความพึงพอใจด้วยแบบสอบถามมาตรฐาน System Usability Scale (SUS)
- **Acceptance Criteria:**
  - [ ] ผู้ใช้ทั้ง 10 คนปฏิบัติภารกิจทั้ง 5 สถานการณ์สำเร็จ 100%
  - [ ] จำนวนขั้นตอนการโต้ตอบ (Interaction Count) ลดลง **≥ 70%** เมื่อเทียบกับวิธีการเดิม (NFR-U01)
  - [ ] ระยะเวลาเฉลี่ยในการส่งข้อมูล (Time-on-Task) ลดลง **≥ 60%**
  - [ ] ได้รับคะแนนประเมินความง่ายในการใช้งาน **SUS Score ≥ 75 คะแนน** (NFR-U02)

---

#### T4.5 — Binary Packaging, Code Signing & Distribution Setup
- **Owner:** `LEAD` (เจ)
- **Estimate:** 3 วัน
- **Priority:** P0
- **Dependencies:** T4.1, T4.2, T4.3
- **Labels:** `release` `packaging` `signing` `phase-4`
- **Description:**  
  จัดทำชุดติดตั้ง ทำการลงนามความปลอดภัย (Code Signing) และเตรียมการเผยแพร่โปรแกรมข้ามทั้ง 4 แพลตฟอร์ม
- **Technical Detail:**
  - macOS: ลงนามด้วย Apple Developer ID Application พร้อมทำ Notarization และ Staple Ticket
  - Windows: ลงนามด้วย Code Signing Certificate สำหรับไฟล์ `.exe` / `.msix`
  - Android: จัดทำ App Bundle (`.aab`) สำหรับ Google Play Store
  - iOS: จัดทำ Release Build สำหรับ Apple App Store / TestFlight
  - ติดตั้งระบบ Auto-Updater สำหรับ Desktop (Sparkle / Squirrel)
- **Acceptance Criteria:**
  - [ ] ติดตั้งบน macOS เครื่องเปล่าได้สำเร็จโดยไม่มีการแจ้งเตือน Gatekeeper Error
  - [ ] ติดตั้งบน Windows เครื่องเปล่าได้สำเร็จโดยไม่มีหน้าต่างเตือน SmartScreen Block
  - [ ] ระบบ Auto-Updater สามารถอัปเดตเวอร์ชันใหม่ได้สำเร็จ

---

#### 🚦 GATE-4 — Final Release Gate (สัปดาห์ 24)
- **Owner:** ทั้งทีม 5 คน (`ALL`)
- **Exit Criteria:**
  - [ ] ผลการทดสอบทุกเกณฑ์ใน Performance Matrix ผ่านเป้าหมาย 100%
  - [ ] รายงาน Penetration Test ไม่พบช่องโหว่ระดับ High หรือ Critical
  - [ ] ผ่านการทดสอบ Soak Test 72 ชั่วโมงโดยอัตราการเพิ่มของหน่วยความจำ RSS ≤ 5% หลังช่วง Warm-up 30 นาทีแรก (NFR-R01)
  - [ ] ได้รับคะแนนประเมินความพึงพอใจการใช้งาน SUS Score ≥ 75 คะแนน
  - [ ] Build Artifacts ผ่านการ Signed และ Notarized ครบทั้ง 4 แพลตฟอร์ม พร้อมเปิดตัวอย่างเป็นทางการ

---

## 6. Workload Distribution Summary

*(คำนวณใหม่ใน PCR-03 จาก Estimate ของทุก ticket: ticket ที่มีเจ้าของร่วมแบ่งวันเท่ากัน ไม่รวม Gate — รวม 145 วัน)* ตารางสรุปสัดส่วนภาระงาน (Workload Distribution) แยกตามสมาชิกทั้ง 5 คน ตลอดระยะเวลาการดำเนินโครงการ 24 สัปดาห์ (Rebalanced):

| Role Code | สมาชิกในทีม | จำนวน Tickets หลัก | รวมประมาณการวันทำงาน (Est. Working Days) | สัดส่วนภาระงาน (%) | ขอบเขตโมดูลหลักที่รับผิดชอบ |
|:---:|---|:---:|:---:|:---:|---|
| `LEAD` | **นายธนกฤต บุญญาวรกุล (เจ)** | 13 Tickets (5 ร่วม) | 35.5 วัน | 24.5% | System Architecture, Protocol Core, Security/Crypto Engine, Signed Cluster Revocation (T1.13), iOS Network Privacy & NWBrowser (T3.1), Pair-Program T1.3 with MOB, CI/CD, Code Signing & Release |
| `DESK` | **นายณัฐธีร์ อโณทัยไพบูลย์ (ธีร์)** | 6 Tickets | 31.0 วัน | 21.4% | Logging Scrubber, mDNS Discovery, macOS Native Clipboard Watcher (T1.6), Cross-OS Image Normalizer (T1.8), Clipboard Sync Engine & Loop Prevention, Desktop UI & System Tray |
| `MOB` | **นายเกื้ออนันต์ พวงนิลน้อย (เกื้อ)** | 10 Tickets (5 ร่วม) | 28.0 วัน | 19.3% | Mobile Spikes, Pair-Program T1.3 with LEAD, Android Service & UI, iOS Extensions, Widgets & PhotoKit File Engine (T3.2–T3.4) |
| `NET` | **นายปัณณ์ ศรีเจริญชัยกุล (ปัน)** | 8 Tickets (3 ร่วม) | 30.5 วัน | 21.0% | TLS Transport, WebSocket Control Plane, Windows Native Clipboard Watcher (T1.7), Streaming File Engine, Resumable Transfer Engine |
| `QA` | **นายปรมินทร์ มุขอาษา (ตามด)** | 6 Tickets (1 ร่วม) | 20.0 วัน | 13.8% | STRIDE Threat Model (T0.5), Test Cluster Harness, Desktop Pentest Audit (GATE-1), Benchmark Suite, Mobile Pentest, Chaos/Soak Testing, UX Study |
| `ALL` | **ทั้งทีม 5 คนร่วมกัน** | 4 Gates | 2 สัปดาห์ (Dogfooding) | — | Phase Gate Reviews, Dogfooding Testing, Final Deployment Approval |
| **รวม** | **5 คน** | **34 Tickets + 4 Gates** | **~146 working days** | **100.0%** | **กระจายภาระงานสมดุล พร้อมรับการพัฒนาระยะยาว 24 สัปดาห์** |
