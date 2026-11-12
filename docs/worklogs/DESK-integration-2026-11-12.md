# DESK — Main CI fix and end-to-end integration (2026-11-12)

| รายการ | รายละเอียด |
|---|---|
| **Scope** | แก้ CI ของ `main` และเชื่อม engine ทุกตัวเข้าแอปเดสก์ท็อปและมือถือ (T1.2, T1.3, T1.5, T1.9–T1.13, T2.5) |
| **Branches / PRs** | `fix/main-build` (#64) แล้วซ้อนต่อ #65–#79 ตามลำดับ (PR ถัดไปตั้ง base เป็น branch ก่อนหน้า) |
| **Engineer** | `DESK` (ธีร์) |
| **AI Assistant** | Claude Code |
| **Status** | `READY FOR PR` — รอ review/merge ตามลำดับ |

## 1. ปัญหาที่เจอ
- หลัง fix #63 CI บน `main` ยังแดงที่ Analyze จึงไม่เคยรันเทสต์ พอรันจริงเจอ:
  - `ClipboardSyncEngine` สร้าง `msg_id` เป็น hex 32 ตัว ไม่ใช่ UUIDv4 → `Envelope` โยน `E_MALFORMED` ทุกครั้ง แปลว่า clipboard sync ส่งอะไรไม่ได้เลย
  - runner ใช้ Flutter stable ใหม่ที่ประกาศ `package:flutter/material.dart` เป็น deprecated → `--fatal-infos` ล้มทุกไฟล์ UI
- engine ทุกตัวเทสต์ผ่าน แต่ไม่มีตัวไหนต่อเข้าแอป:
  - `DeviceIdentityManager` เรียก `openssl` CLI ตอนรัน (Windows ทั่วไปไม่มี) และแอปใช้ device id สุ่มใหม่ทุกครั้งที่เปิด
  - ไม่มี TLS server ในแอป; หน้า Devices "จับคู่" กับ client จำลองในตัวเองและเขียน Trusted Store ลง temp
  - `apps/mobile` ไม่มี `android/` และ `ios/` จึง build ลงมือถือไม่ได้; หน้า SAS ใช้ค่าตายตัว

## 2. สิ่งที่ทำ (ตามลำดับ PR)
| PR | สิ่งที่ทำ |
|---|---|
| #64 | UUIDv4 `msg_id`, lint, เทสต์ resume จริง, CMake หา `native/windows` เมื่อ REALPATH ไม่ resolve symlink, pin Flutter 3.47.9 |
| #65 | P-256 key/cert/sign/verify ด้วย Dart ล้วน (pointycastle) |
| #66 | `PairingHost` / `PairingClient` (PIN + SAS ผ่าน TLS จริง); `/pair` ส่ง `cert` ของ client เพราะ server ไม่รับ client cert ที่ไม่เคยได้รับ |
| #67 | `PeerMesh` (WS ต่อ peer, initiator rule, hello timeout, backoff) |
| #68–#70 | `DesktopNode` (identity ถาวร, DPAPI/Keychain, TLS server, mesh), หน้าต่างจับคู่, หน้า Devices จริง |
| #71 | sync คลิปบอร์ดข้าม PC (ข้อความ + รูป, blob ผ่าน `GET /api/v1/blob`) |
| #72–#73 | ส่งไฟล์ stream + resume + SHA-256, Dropzone ส่งจริง, หน้า Transfers จริง |
| #74–#75 | โปรเจกต์ Android/iOS, `MobileNode`, หน้าจอมือถือ, CI build APK + iOS |
| #76–#79 | QR pairing (เดสก์ท็อปแสดง, มือถือสแกน), Settings คุม sync policy, Remove = revoke ทั้ง cluster |

## 3. ผลทดสอบ
- `melos run format` / `analyze` / `test` ผ่านบนเครื่อง Windows: 440+ เทสต์ (core TLS tests ต้องมี `openssl` เฉพาะ fixture เก่า)
- integration test ระหว่าง node จริงบน loopback: จับคู่ PIN/QR, mTLS หลังจับคู่, WS สองทาง, sync ข้อความ + รูป 160 KB, ส่งไฟล์ 2.5 MB, revoke สามเครื่อง, มือถือจับคู่และ sync กับ host
- CI: PR #64 เขียวครบทุก job; Mobile Build (APK + iOS no-codesign) ผ่าน
- แอป Windows จริง: สองหน้าต่างบนเครื่องเดียว bind 53317/53318, เห็นกันผ่าน mDNS, device id คงที่หลัง restart, มีแค่ blob DPAPI บนดิสก์

## 4. ยังไม่ได้ตรวจ / ต้องทำต่อ
- คลิกผ่านขั้นตอนจับคู่ในหน้าจอแอปจริง และทดสอบระหว่าง PC สองเครื่องจริง (T1.1 < 3 s)
- มือถือจริง: สแกน QR, sync ข้อความ (MOB)
- Mac จริง: Keychain, คลิปบอร์ด macOS, LaunchAgent
- ยังไม่มี: anti-entropy `revocation.sync`, ส่งไฟล์จากมือถือ, Android foreground service ในแอป
- **ต้องให้ LEAD ตัดสินใจ:** ฟิลด์ `cert` ใน `/pair` (#66) และการต่อ T1.13 เข้าแอป (#78)
