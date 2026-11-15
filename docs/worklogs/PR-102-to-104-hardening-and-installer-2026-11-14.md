# Work Log — [T1.11 / T1.12 / T2.5]: PR #103 → #102 → #104 Sequential Hardening, Merge & Windows Installer

| รายการ | รายละเอียด |
|---|---|
| **Ticket ID** | `T1.11`, `T1.12`, `T2.5`, `T3.4` |
| **Branches Merged** | `fix/T1.11-transfer-integrity-and-runtime-hardening` ([PR #103](https://github.com/nCotista/DropClip/pull/103)), `feat/T1.11-received-file-in-clipboard` ([PR #102](https://github.com/nCotista/DropClip/pull/102)), `feat/T2.5-mobile-parity` ([PR #104](https://github.com/nCotista/DropClip/pull/104)) |
| **Developer / Assignee** | Team PRs (`DESK`, `NET`, `MOB`) + `LEAD` hardening & release verification |
| **Role Code** | `LEAD` / `DESK` / `MOB` |
| **AI Assistant Used** | Antigravity |
| **Start Date** | 2026-11-14 |
| **Completion Date** | 2026-11-14 |
| **Status** | `MERGED` (`main` `cc27440`) |

---

## 1. Objective & Scope (วัตถุประสงค์และขอบเขต)
- [x] Review, harden, verify green CI, and sequentially merge all open PRs (`#103` → `#102` → `#104`) into `main`.
- [x] Enforce protocol, security, and runtime invariants across Desktop file/clipboard UX and Mobile parity (`apps/mobile`).
- [x] Trigger `Windows Installer` (`windows-installer.yml`) on final `main` (`cc27440`) so `DropClip-Setup.exe` includes `#102`–`#104`.
- [x] Record all PR results, CI runs, and worklogs on `docs/task-progress-tracker` while preserving the user's local `.gitignore` edit.

---

## 2. Technical Context & Key Decisions (การตัดสินใจเชิงเทคนิค)
* **PR #103 (`52d54d9`, head `761fd95`, `+471/-53`):**
  - Tracked explicit item completion (`!t.completed.contains(i.itemId)`) before `finish`, guarded `PeerMesh.reach(..., force: true)` after `close()` or revocation, and added `~` home expansion + validation for `destinationDirectory` (`51dfdaf`, `761fd95`).
* **PR #102 (`1c54092`, head `ad3b7c0`, `+410/-13`):**
  - Rebased onto `52d54d9` and resolved `file_transfer.dart` conflict.
  - Hardened `takeSavedFile`: wrapped `decodePng` + `try/catch` so corrupt image data skips clipboard injection without failing or deleting the saved file on disk.
  - Hardened `openCommand` / `runOpenWithSystem`: replaced shell invocation with `runInShell: false` argument lists (`open` on macOS, `xdg-open` on Linux, direct `explorer.exe` invocation on Windows), plus missing-file and `ProcessException` guards (`6339891`, `40980a1`, `ad3b7c0`).
* **PR #104 (`cc27440`, head `9123808`, `+1977/-167`, user-approved 400-line exception):**
  - Fixed Android download path bug in `apps/mobile/lib/main.dart` where `getDownloadsDirectory()` (`Directory?`) was interpolated directly instead of `.path`, and wrapped `OpenFilex.open` in existence + exception guards with `settings.value.save(...).ignore()`.
  - Serialized `MobileSettings.save` with a per-path `Future` queue and atomic `.tmp` (`flush: true`) + rename cleanup.
  - Guarded `BonsoirMdnsBackend.browse` against `StreamController` cancellation while initializing; keyed `mobile_app.dart` online status checks by `deviceId` (`Set<String>`) instead of comparing `TrustedDevice` instances.
  - Hardened `MobileNode`: serialized atomic `hosts.json` updates (`_withHostLock` / `_writeHostsAtomic`), resilient offline `forget()`, serialized incoming messages (`_msgQueue`), `decodePng` validation for `ClipType.image`, `ProtocolConstants.clipboardMaxSize` (32 MiB) cap in `_fetch`, `maxItemsPerTransfer` / `transfer_id` checks in `_offered`, `409 E_INCOMPLETE` + HTTP method/offset checks in `_route`, and `sendFile` status `complete` skip + strict rejection of negative or out-of-range offsets (`9414151`, `9123808`).
* **Zero-Cloud & Protocol Invariants:** Preserved mTLS pinning, 1 MiB chunked file transfer, 32 MiB clipboard/blob cap, and zero plaintext secret/clipboard logging.

---

## 3. Files Created & Modified (รายการไฟล์ที่มีการเปลี่ยนแปลง)
- PR `#103`: `apps/desktop/lib/src/transfer/file_transfer.dart`, `apps/desktop/lib/src/settings/config.dart`, `packages/dropclip_core/lib/src/transport/peer_mesh.dart`, plus regression tests.
- PR `#102`: `apps/desktop/lib/main.dart`, `apps/desktop/lib/src/sync/clipboard_bridge.dart`, `apps/desktop/lib/src/transfer/file_transfer.dart`, `apps/desktop/test/clipboard_bridge_test.dart`, `apps/desktop/test/file_transfer_test.dart`, and Desktop UI/l10n files.
- PR `#104`: `apps/mobile/lib/main.dart`, `apps/mobile/lib/src/bonsoir_backend.dart`, `apps/mobile/lib/src/mobile_app.dart`, `apps/mobile/lib/src/mobile_node.dart`, `apps/mobile/lib/src/mobile_peer.dart`, `apps/mobile/lib/src/mobile_settings.dart`, `apps/mobile/lib/src/mobile_strings.dart`, `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/ios/Runner/Info.plist`, `apps/mobile/pubspec.yaml`, `apps/mobile/test/mobile_app_test.dart`, `apps/mobile/test/mobile_node_test.dart`, `apps/mobile/integration_test/pairing_cancellation_test.dart`.

---

## 4. Verification & Testing Evidence (หลักฐานการทดสอบ)
*(Local environment has no `dart`/`flutter`/`melos` CLI installed; all format, static analysis `--fatal-infos`, unit/widget tests, security audits, and native/mobile builds were verified via GitHub Actions CI.)*
- **PR `#103` (`fix/T1.11-transfer-integrity-and-runtime-hardening`, head `761fd95` → merged `52d54d9`):**
  - `gh pr checks 103`: `12/12 SUCCESS`; `main` push runs `43502449943` (`DropClip Monorepo CI`) and `43502449887` (`Mobile Build (T2.5)`) passed `success`.
- **PR `#102` (`feat/T1.11-received-file-in-clipboard`, head `ad3b7c0` → merged `1c54092`):**
  - `gh pr checks 102`: `6/6 SUCCESS` (CI run `43547317189`); `main` push run `43548463553` (`DropClip Monorepo CI`) passed `success`.
- **PR `#104` (`feat/T2.5-mobile-parity`, head `9123808` → merged `cc27440`):**
  - `gh pr checks 104`: `8/8` checks passed (`Code Quality & Analysis` on `ubuntu-latest`/`macos-latest`/`windows-latest`, `Native Windows Clipboard Core Tests (T1.7)`, `Windows Desktop Build`, `Security & Secret Audit`, `Android APK (debug)`, `iOS app (no codesign)`).
- **Final `main` (`cc27440`) Workflows:**
  - `DropClip Monorepo CI` (run `43558758861`): `completed` / `success`.
  - `Mobile Build (T2.5)` (run `43558758866`): `completed` / `success`.
  - `Windows Installer` (run `43558853900`): `completed` / `success` (`Build DropClip-Setup.exe` in 3m57s + `Publish GitHub Release`).

---

## 5. Reviewer Notes & Next Steps (บันทึกสำหรับผู้ตรวจและขั้นตอนต่อไป)
- All open PRs (`#102`, `#103`, `#104`) are merged cleanly on `main` (`cc27440`), feature branches deleted, and updated `DropClip-Setup.exe` release published via `Windows Installer` run `43558853900`.
- Optional follow-up: dispatch `release-apps.yml` (`Release Apps`) or tag a release if refreshed macOS/Android/iOS release assets for `cc27440` are needed.
