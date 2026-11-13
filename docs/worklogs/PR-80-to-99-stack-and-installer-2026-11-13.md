# Work Log — [T3.x / T1.5 / T1.12 / Release]: Stack Merge (#80–#99) & Windows Installer

| รายการ | รายละเอียด |
|---|---|
| **Ticket ID** | `T1.2` (fix), `T1.3`, `T1.5`, `T1.12`, `T2.5`, `T3.x` (Web Companion), `T4.5` (Installer/Release CI) |
| **Branch Name** | `main` merges from `#80`–`#86`, `#88`, `#89`, `#93`, `#94`, `#96`–`#99` (tracked on `docs/task-progress-tracker`) |
| **Developer / Assignee** | `DESK` (ธีร์), `MOB` (เกื้อ), `LEAD` (เจ) — Audit, Hardening, Stack Merge & Release Dispatch |
| **Role Code** | `LEAD` / `DESK` / `MOB` |
| **AI Assistant Used** | Antigravity |
| **Start Date** | 2026-11-12 |
| **Completion Date** | 2026-11-13 |
| **Status** | `MERGED` (`main` @ `da0cf24`) |

---

## 1. Objective & Scope (วัตถุประสงค์และขอบเขต)
- [x] ปิด PR `#65` และเก็บกวาด branch ที่รวมเข้า `main` แล้ว (`feat/T1.2-pure-dart-identity`, `fix/main-build`)
- [x] ปรับปรุงความปลอดภัย (`hardening`) และ merge PR `#98` (`fix/T1.5-peer-clock-skew`) เข้าสู่ `main`
- [x] Retarget และ merge สแตก PR `#81 → #82 → #83 → #84 → #85 → #86 → #88 → #96` เข้าสู่ `main` ทีละ PR หลัง CI เขียวครบทุกตัว (คง PR `#82` ที่ 415 บรรทัดตามการอนุมัติของผู้ใช้)
- [x] อัปเดตสถานะ PR ที่ merge เข้า `main` แล้วในทะเบียน (`#80`, `#89`, `#93`, `#94`, `#97`, `#99`)
- [x] สั่งรัน workflow `Windows Installer` บน commit ล่าสุดของ `main` (`da0cf24`) เพื่อเผยแพร่ `DropClip-Setup.exe` / `DropClip-Setup-1.0.0.exe` ที่รวมโค้ด `#80`–`#99`

---

## 2. Technical Context & Key Decisions (การตัดสินใจเชิงเทคนิค)
* **T1.5 Clock-Skew Guard (`#98`, `12d2f4e`):** จำกัดการคำนวณ/อัปเดตค่าชดเชยเวลาของ peer เฉพาะเฟรม `hello` แรกของ handshake ด้วยเงื่อนไข `_remoteHello == null && _isHello(env.type)`, อ่านเวลา `_nowMs()` เพียงครั้งเดียวต่อเฟรม, และเพิ่ม negative tests สำหรับ clock skew เกิน 24 ชั่วโมง (`±25h`) และการส่ง `hello` ซ้ำหลัง handshake เพื่อไม่ให้ peer แก้ skew ระหว่าง session ได้
* **Clipboard Echo / Dedupe Alignment (`#83` vs `#91`):** ยึด `ClipboardSyncEngine` (`engine.head` + suppression window 800 ms จาก `#91`) เป็นแหล่งความจริงหลัก และตรวจ `web_companion` / `clipboard_bridge` ให้ส่งข้อความและรูปจาก iPhone ขึ้นประวัติคลิปบอร์ดและ sync ต่อได้
* **Web Companion & Desktop UX Stack Hardening (`#80`–`#88`, `#96`):**
  - `#80` (`ddb1645`): Drain request body ที่เกินขนาดก่อนตอบ `413` และจัดรูปแบบ Dart format
  - `#82` (`d23c69e`): แก้ `_WebLinkDialogState._next` ให้ข้ามการสร้างรหัสเชื่อมต่อหากผู้ใช้งานปิด Web Companion และคง PR ที่ขนาด 415 บรรทัดตามการอนุมัติของผู้ใช้
  - `#85` (`6b829df`): ถอดรหัสและตรวจสอบ PNG ด้วย `decodePng` ก่อนส่งต่อเข้าคลิปบอร์ด PC
  - `#88` (`1420ef1`): เพิ่ม guard ป้องกันการเปิด OS file dialog ซ้อนระหว่างเลือกไฟล์ (`Dropzone`)
* **Stacked Merge Discipline:** เนื่องจาก `.github/workflows/ci.yml` ตั้งค่า `pull_request` trigger เฉพาะ `[opened, synchronize, reopened]` (ไม่รวม `edited`) จึงปิดและเปิด PR ใหม่หลัง retarget base เป็น `main` ทีละตัว และใช้ `--merge` (`delete_branch_on_merge: false`) เพื่อคง ancestry ของ commit และรักษาขนาด diff ของ PR ถัดไปให้สะอาด

---

## 3. Files Created & Modified (รายการไฟล์ที่มีการเปลี่ยนแปลงใน `main`)
- **PR `#80` (`bcdb268`, head `ddb1645`):** `apps/desktop/lib/src/web/web_companion.dart`, `apps/desktop/pubspec.yaml`, `apps/desktop/test/web_companion_test.dart`, `packages/dropclip_core/lib/src/transport/tls_transport_server.dart`
- **PR `#81` (`2c45f73`, head `0460b43`):** `apps/desktop/lib/src/web/web_page.dart`, `apps/desktop/test/web_page_test.dart`
- **PR `#82` (`af18bcf`, head `d23c69e`):** `apps/desktop/lib/main.dart`, `apps/desktop/lib/src/devices_page.dart`, `apps/desktop/lib/src/l10n/strings.dart`, `apps/desktop/lib/src/node/desktop_node.dart`, `apps/desktop/lib/src/settings/config.dart`, `apps/desktop/lib/src/settings/settings_page.dart`, `apps/desktop/lib/src/web/web_link_dialog.dart`, และชุด tests ที่เกี่ยวข้อง
- **PR `#83` (`0102690`, head `0d633e0`):** `apps/desktop/lib/main.dart`, `apps/desktop/lib/src/app.dart`, `apps/desktop/lib/src/shell.dart`, `apps/desktop/lib/src/sync/clipboard_bridge.dart`, `apps/desktop/test/clipboard_bridge_test.dart`, `apps/desktop/windows/runner/main.cpp`
- **PR `#84` (`fc29692`, head `ee64934`):** `apps/desktop/lib/main.dart`, `apps/desktop/lib/src/sync/clipboard_bridge.dart`, `apps/desktop/lib/src/web/web_companion.dart`, `apps/desktop/test/{clipboard_bridge_test.dart,web_companion_test.dart,web_link_dialog_test.dart}`
- **PR `#85` (`05298f6`, head `6b829df`):** `apps/desktop/lib/main.dart`, `apps/desktop/lib/src/sync/clipboard_bridge.dart`, `apps/desktop/lib/src/web/{web_companion.dart,web_page.dart}`, `apps/desktop/test/{clipboard_bridge_test.dart,web_companion_test.dart}`
- **PR `#86` (`8afe3a5`, head `b34ccaa`):** `apps/desktop/lib/src/web/web_page.dart`
- **PR `#88` (`fe0f84a`, head `1420ef1`):** `apps/desktop/lib/src/dropzone/{dropzone_controller.dart,dropzone_host.dart,dropzone_panel.dart,file_dialog.dart}`, `apps/desktop/lib/src/l10n/strings.dart`, `apps/desktop/test/dropzone_browse_test.dart`
- **PR `#96` (`da0cf24`, head `6fbe936`):** `apps/desktop/lib/main.dart`, `apps/desktop/lib/src/{app.dart,clipboard_aside.dart,clipboard_page.dart,shell.dart}`, `apps/desktop/test/clipboard_aside_test.dart`
- **PR `#97` (`801d90e`, head `4a6f330`):** `.github/workflows/windows-installer.yml`, `README.md`, `apps/desktop/installer/{build_installer.ps1,install.ps1,uninstall.ps1}`
- **PR `#98` (`7ac04ae`, head `12d2f4e`):** `packages/dropclip_core/lib/src/transport/control_plane.dart`, `packages/dropclip_core/test/transport/control_plane_test.dart`
- **PR `#99` (`c9a537e`, head `7da8455`):** `.github/workflows/release-apps.yml`

---

## 4. Verification & Testing Evidence (หลักฐานการทดสอบ)
- **PR CI Gates (GitHub Actions):**
  - PR `#98` (`12d2f4e`): **8/8 checks passed** (`gh pr checks 98` before merge as `7ac04ae`)
  - PR `#99` (`7da8455`): **9/9 checks passed** (merged as `c9a537e`)
  - Stacked PRs `#81`, `#82`, `#83`, `#84`, `#85`, `#86`, `#88`, `#96`: ผ่าน **`DropClip Monorepo CI` 6/6 checks** ครบทุก PR ก่อน merge เข้าสู่ `main` ตามลำดับ
- **Final `main` (`da0cf240a5f1650e45447eb26bb5227b73847ed7`):**
  - `DropClip Monorepo CI` (run `43405091684`): **`success`**
  - `Windows Installer` (run `43405364634`): **`success`** (4m16s; Build Release + Pack + Extract/Install Smoke-test + GitHub Release publish)
  - GitHub Release `v1.0.0` (`targetCommitish: da0cf240a5f1650e45447eb26bb5227b73847ed7`) อัปเดต assets: `DropClip-Setup.exe` และ `DropClip-Setup-1.0.0.exe` (13,799,424 bytes, `sha256:8eaba91e88b1b27d5256c920d9f561d0ba1a9e441198ae21ad7c9173b0f5b6b4`)

---

## 5. Reviewer Notes & Next Steps (บันทึกสำหรับผู้ตรวจและขั้นตอนต่อไป)
- **Open PR Queue:** ไม่มี Open PR ค้างอยู่ (`gh pr list --state open` ว่างเปล่า); PR `#65` ถูกปิดเรียบร้อยแล้ว
- **Release Assets Note (`Release Apps`):** ไฟล์ `DropClip-Android.apk`, `DropClip-iOS-unsigned.ipa` และ `DropClip-macOS.zip` ใน Release `v1.0.0` ถูกสร้างจาก run `43391275531` บน commit `c9a537e` (ก่อน PR `#98` และ `#81`–`#96`) หากต้องการให้ไบนารี Android/iOS/macOS บน Release ตรงกับ `da0cf24` สามารถสั่งรัน `gh workflow run release-apps.yml --ref main` เพิ่มเติมได้
