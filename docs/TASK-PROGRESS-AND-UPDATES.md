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
| **สถานะเฟสปัจจุบัน** | **Phase 0 Completed $\to$ Entering Phase 1** | สัปดาห์ 1–2 (Foundation & Spikes) |
| **จำนวน Tickets ทั้งหมด** | 34 Tickets + 4 Gates | 24 สัปดาห์ |
| **Tickets ที่เสร็จสิ้นแล้ว** | **5 / 34** (14.7%) | Phase 0 Baseline Done |
| **Tickets ที่กำลังดำเนินการ** | **2 / 34** | S0.1, S0.2 (In Spikes) |
| **สถานะ CI Automation** | **Failing บน `main` (`4ce4e92`)** — format/analyze ไม่ผ่าน และเทสต์ protocol/core compile ไม่ได้; แก้ใน PCR-03 | Melos Monorepo Lint, Analyze & Test |
| **ความพร้อมของเอกสารสเปก** | **Draft — ยังมี Open Issues** (ดู PCR-03) | Protocol Spec v2.0, SRS v1.2, Threat Model |

---

## 1. Ticket Status Board (กระดานสถานะงานแยกตามเฟส)

### 🔹 PHASE 0 — FOUNDATION & TECHNICAL SPIKES (สัปดาห์ 1–2)
- [ ] **S0.1** Cross-Platform mTLS ECDSA P-256 Spike (`LEAD`) — *In Progress* (ส่วน Dart บน Windows ทดลองแล้วใน PCR-03 — เหลือ macOS/Android/iOS)
- [ ] **S0.2** Mobile Background Constraints Spike (`MOB`) — *In Progress*
- [x] **T0.1** Monorepo Architecture Setup & CI/CD Pipeline (`LEAD`) — **DONE** (`4d8270f`)
- [ ] **T0.2** Protocol Package & Data Envelopes (HLC, SAS Engine) (`LEAD`) — *บางส่วน*: SAS/HLC/Path Sanitizer เสร็จ แต่ยังไม่มี envelope data classes + JSON และ fuzz test 10,000 ครั้งตาม Acceptance Criteria
- [x] **T0.3** Logging & Telemetry Scrubber Framework (`DESK`) — **DONE**
- [x] **T0.4** Multi-Device Network Test Harness (`QA`) — **DONE**
- [x] **T0.5** Formal STRIDE Threat Model & Attack Tree Review (`QA` + `LEAD`) — **DONE** (`06cada3`)
- [x] **T0.6** Dev Accounts, Code Signing Setup & Release Plan (`LEAD`) — **DONE** (`06cada3`)

---

### 🔹 PHASE 1 — DESKTOP CORE ENGINE & TIER 1 SYNC (สัปดาห์ 3–12)
- **Milestone M1: Discovery, Identity & Pairing (สัปดาห์ 3–5)**
  - [ ] **T1.1** Zero-Configuration mDNS Advertiser & Browser Engine (`DESK`)
  - [ ] **T1.2** Per-Device Key Identity & Encrypted Store (`LEAD`)
  - [ ] **T1.3** Pairing Engine, Commit-then-Reveal SAS & QR Flow (`LEAD` + `MOB`)
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
  - [ ] **T1.13** Device Management & Signed Cluster Revocation (`LEAD`)
- [ ] **🚦 GATE-1** Milestone Review, Desktop Security Pentest & Dogfooding (`ALL`)

---

### 🔹 PHASE 2 — ANDROID PLATFORM EXTENSION (สัปดาห์ 13–17)
- [ ] **T2.1** Android Foreground Service (connectedDevice) & Lifecycle (`MOB`)
- [ ] **T2.2** Android Quick Settings Tile (PendingIntent) & 1-Click Action (`MOB`)
- [ ] **T2.3** Android Clipboard Receiver & Inbound Sync (`MOB`)
- [ ] **T2.4** Android MediaStore & Share Target Engine (`MOB`)
- [ ] **T2.5** Android Mobile UI & Pairing QR Scanner (`MOB`)
- [ ] **🚦 GATE-2** Phase 2 Android Exit Gate Review (`ALL`)

---

### 🔹 PHASE 3 — iOS CAPABILITY EXTENSION (สัปดาห์ 18–21)
- [ ] **T3.1** iOS Local Network Privacy & Discovery Permissions (`LEAD`)
- [ ] **T3.2** iOS Share Sheet Extension & Memory Sandbox (< 30 MB) (`MOB`)
- [ ] **T3.3** iOS Interactive Widgets, Action Button & Shortcuts (`MOB`)
- [ ] **T3.4** iOS PhotoKit & File Receiver Engine (`MOB`)
- [ ] **🚦 GATE-3** Phase 3 iOS Exit Gate Review (`ALL`)

---

### 🔹 PHASE 4 — SYSTEM HARDENING & MULTI-PLATFORM RELEASE (สัปดาห์ 22–24)
- [ ] **T4.1** Automated Benchmark Suite & CI Regression Verification (`QA`)
- [ ] **T4.2** Comprehensive Security Audit & Mobile Penetration Testing (`QA`)
- [ ] **T4.3** Chaos Engineering, Network Partition & 72h Soak Testing ($\le 5\%$ RSS) (`QA`)
- [ ] **T4.4** Formal Usability Study & SUS Evaluation ($\ge 75$) (`QA` + `ALL`)
- [ ] **T4.5** Binary Packaging, Code Signing & Distribution Setup (`LEAD`)
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
| *(เพิ่มต่อที่นี่)*| ... | ... | ... | ... | ... | ... | ... |

---

## 3. Checklist ก่อนเปิด Pull Request (PR Readiness Gate)

ก่อนที่ทีมงานหรือ AI จะเปิด Pull Request กรุณาตรวจสอบ Checklist ดังต่อไปนี้:
- [ ] โค้ดผ่าน `melos run format` (ไม่มี diff จัดหน้าหลงเหลือ)
- [ ] โค้ดผ่าน `melos run analyze` (0 errors, 0 warnings, 0 infos)
- [ ] ชุดทดสอบผ่านครบ 100% ด้วย `melos run test`
- [ ] ขอบเขตของ PR ไม่เกิน 400 บรรทัด (ตามกฎ Non-Negotiable Rule #1)
- [ ] มีการบันทึก Work Log ลงใน `docs/worklogs/` เรียบร้อยแล้ว
- [ ] ได้เข้ามาติ๊กสถานะและกรอกข้อมูลในตาราง Registry ของไฟล์นี้ (`docs/TASK-PROGRESS-AND-UPDATES.md`) แล้ว

