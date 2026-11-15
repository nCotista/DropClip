# DropClip v1.0.6 — Bug Report and Test Cases

Tested version: v1.0.6 (commit `1472426`, branch `release/next`). The three bugs below are fixed on `release/next` after v1.0.6; the fix is not in a release yet.

Part 1 lists bugs found by reading the code and proven with automated tests.
Part 2 is a set of manual test cases for the whole app (PC, Android, iPhone).

---

## Part 1 — Bugs found

Each bug has an automated test that **failed on v1.0.6** and passes with the fix.

| ID | Severity | Where | Summary | Status |
|---|---|---|---|---|
| BUG-01 | High | Phone app, receiving files | Phone answers "complete" to a transfer whose file never arrived | Fixed |
| BUG-02 | High | Phone app, receiving files | A cut-off upload is answered with `state: complete` | Fixed |
| BUG-03 | Medium | PC and phone, receiving files | Two files with the same name arriving at the same time break each other | Fixed |

### BUG-01 — Phone confirms a transfer that never arrived

- **File:** `apps/mobile/lib/src/mobile_node.dart`, `_route`, the `finish` branch.
- **What happens:** when the PC calls `POST /api/v1/file/<id>/finish`, the phone always answers `200 complete` and sends `file.complete`. It does not check that every file was received and verified.
- **Effect for the user:** the PC shows the transfer as "complete" although nothing was saved on the phone.
- **Fix:** `finish` now checks that every file was saved; if not it answers `409` and deletes the partial file.
- **Expected:** `409` and `file.complete` with `state: failed`, as the PC's own receiver does (`apps/desktop/lib/src/transfer/file_transfer.dart`).
- **Test:** `apps/mobile/test/mobile_node_test.dart` → `BUG-01: the phone refuses "finish" when the file never arrived`
- **Result on v1.0.6:** `Expected: <409>  Actual: <200>`

### BUG-02 — A cut-off upload is reported as complete

- **File:** `apps/mobile/lib/src/mobile_node.dart`, `_route`, after the upload loop.
- **What happens:** the phone answers `{"received_bytes": N, "state": "complete"}` after every upload, even when only part of the file arrived (Wi-Fi drop, app paused by iOS).
- **Effect for the user:** together with BUG-01, a half-sent file shows as sent on the PC. The half file stays on the phone as a hidden `.part` file.
- **Fix:** the reply says `in_progress` until the file is whole and verified.
- **Expected:** `state` is `complete` only when the whole file arrived and its SHA-256 matched.
- **Test:** same file → `BUG-02: a cut-off upload is not reported as complete`
- **Result on v1.0.6:** `Expected: not 'complete'  Actual: 'complete'`

### BUG-03 — Same-named files arriving together break each other

- **File:** `packages/dropclip_transfer/lib/src/streaming_file_engine.dart`, `partFileFor`.
- **What happens:** the temporary file is named after the file only (`photo.jpg.part`), not after the transfer. Two transfers of `photo.jpg` at the same time write into the same temporary file.
- **Effect for the user:** the second transfer fails with "offset mismatch", or the first one fails its checksum and is deleted. Likely case: two phones both send `IMG_0001.jpg`, or the user sends the same file twice quickly.
- **Fix:** each transfer gets its own temporary file (`photo.jpg.<hash of transfer id>.part`).
- **Expected:** both files are saved (`photo.jpg` and `photo (1).jpg`).
- **Test:** `packages/dropclip_transfer/test/same_name_transfers_test.dart`
- **Result on v1.0.6:** `ProtocolException(E_OFFSET_MISMATCH): expected offset 1048576 but received 0`

### How to run the bug tests

```bash
cd apps/mobile && flutter test test/mobile_node_test.dart --plain-name "BUG-0"
```

```bash
cd packages/dropclip_transfer && dart test test/same_name_transfers_test.dart
```

---

## Part 2 — Manual test cases

**Setup for all cases:** one Windows PC and one phone (Android or iPhone) on the same Wi-Fi, DropClip v1.0.6 installed on both. Write Pass or Fail in the last column.

### A. Install and start

| ID | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| A-01 | Run `DropClip-Setup-1.0.6.exe` on a PC without admin rights. | Installs without asking for an admin password. DropClip opens. | |
| A-02 | On first start, Windows Firewall asks. Choose Private networks. | App starts; no error. | |
| A-03 | Install the phone app (`.apk`, or `.ipa` with Sideloadly) and open it. | Home screen shows "No computer yet" and a hint to pair. | |
| A-04 | iPhone only: on first use, allow "Local Network" when iOS asks. | Permission accepted; app keeps working. | |

### B. Pairing

| ID | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| B-01 | PC: Devices → Pair new device. Phone: Pair → Scan QR. Compare the number on both screens, confirm on both. | Both show "Paired". The PC appears in the phone's list as Connected. | |
| B-02 | Pair by typing the PC's IP, port and PIN instead of the QR. | Same result as B-01. | |
| B-03 | Start pairing and type a wrong PIN. | Pairing fails with a message. The PC is not added to the list. | |
| B-04 | During pairing, press "Doesn't match" on the phone. | Pairing is cancelled on both sides. No device is added. | |
| B-05 | Wait until the QR/PIN expires, then try to use it. | Pairing fails; a new QR is needed. | |

### C. Clipboard

| ID | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| C-01 | Copy a sentence on the PC. | It appears in the phone's Received list within 2 seconds. | |
| C-02 | On the phone press "Send clipboard" after copying text. | The text can be pasted on the PC. It shows on the PC's Clipboard page. | |
| C-03 | Copy Thai text and emoji (for example `สวัสดี 😀`) on the PC. | Arrives on the phone unchanged. | |
| C-04 | Copy a link on the PC. | Arrives on the phone as a link/text. | |
| C-05 | Copy an image (screenshot) on the PC. | A `.png` appears in the phone's Received list and opens. | |
| C-06 | Phone: Settings → turn "Sync clipboard" off. Copy text on the PC. | Nothing arrives on the phone. Turn it on again: new copies arrive. | |
| C-07 | Tap a received clip on the phone. | "Copied" is shown; the text can be pasted in another app. | |

### D. Files

| ID | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| D-01 | PC: drag a small file (under 1 MB) onto the phone in the Dropzone. | Phone shows the file in Received. "Open" opens it. | |
| D-02 | PC: send a large file (over 100 MB). | Progress goes to 100%. The file on the phone has the same size. | |
| D-03 | Phone: "Send file", pick a photo, choose the PC. | PC asks to receive; after accepting, the file is in the PC's download folder and listed on the Clipboard page. | |
| D-04 | Repeat D-03 but decline on the PC. | Phone shows "Could not send". No file on the PC. | |
| D-05 | PC: add a file to the Dropzone, then remove it before sending. | The file is removed from the list and is not sent. | |
| D-06 | PC Clipboard page: click "Show in folder" on a received file. | Explorer opens with that file selected. | |
| D-07 | Send a file whose name already exists on the receiver. | The old file is kept; the new one is saved as `name (1).ext`. | |
| D-08 | Send a file with a Thai name (for example `รายงาน 1.pdf`). | Saved with the same name. | |
| D-09 | Send an empty file (0 bytes). | Saved as an empty file; transfer shows complete. | |
| D-10 | **(BUG-01/02)** PC → phone, large file. Turn the phone's Wi-Fi off at about 50%. | PC shows the transfer as **failed**, not complete. | |
| D-11 | **(BUG-03)** Send the same file twice from the PC to the phone, the second one right after the first starts. | Both arrive: `name.ext` and `name (1).ext`. | |

### E. Connection

| ID | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| E-01 | Close the phone app completely (swipe away) and open it again. | The PC shows Connected within about 10 seconds, without pairing again. | |
| E-02 | Close DropClip on the PC, wait 30 seconds, open it again. | The phone shows Connected again within about 30 seconds. | |
| E-03 | Turn the phone's Wi-Fi off for 1 minute, then on. | Phone shows Offline, then Connected again by itself. | |
| E-04 | Lock the phone for 2 minutes, unlock, open DropClip. | Connected again within a few seconds. | |
| E-05 | Restart the PC (it may get a new IP address). | The phone finds it and connects again without pairing. | |
| E-06 | Keep DropClip open on the iPhone for 5 minutes without touching it. | The screen stays on and the PC still shows the phone as connected. | |

### F. Devices and settings

| ID | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| F-01 | Phone: Settings → Phone name → type a new name → Save. | The new name is shown on the phone. After reconnecting, the PC shows the new name. | |
| F-02 | PC: Settings → change the device name, press Enter. | Saved once. After reconnecting, the phone shows the new name. | |
| F-03 | Try to save an empty name (only spaces). | The old name is kept. | |
| F-04 | Phone: remove the PC from the list and confirm. | The PC disappears from the phone, and the phone disappears from the PC. | |
| F-05 | After F-04, copy text on the PC. | Nothing arrives on the phone. | |
| F-06 | Switch the language to Thai, then back to English, on both apps. | All texts change at once; no missing texts. | |

### G. Security

| ID | Steps | Expected result | Pass/Fail |
|---|---|---|---|
| G-01 | Use a second phone that is **not** paired, on the same Wi-Fi. | It cannot see clips or send files to the PC. | |
| G-02 | Copy a password from a password manager on the PC. | It is not sent to the phone. | |
| G-03 | Put the phone on mobile data (not the Wi-Fi). | Phone shows Offline; nothing is sent over the internet. | |

---

## Result summary

| Group | Cases | Passed | Failed |
|---|---|---|---|
| A. Install | 4 | | |
| B. Pairing | 5 | | |
| C. Clipboard | 7 | | |
| D. Files | 11 | | |
| E. Connection | 6 | | |
| F. Devices and settings | 6 | | |
| G. Security | 3 | | |
| **Total** | **42** | | |

Expected to fail on v1.0.6: D-10 and D-11. They should pass on the next release.
