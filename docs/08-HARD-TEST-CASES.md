# DropClip — Hard Test Cases (trying to break the app)

Version tested: `main` after v1.0.9 plus PR #120 (branch `fix/same-name-part-files`).

Part 1 is automated: hostile inputs to the file receiver, with results.
Part 2 is manual: situations only real devices and networks can create.

---

## Part 1 — Automated hostile tests

File: `packages/dropclip_transfer/test/adversarial_test.dart`

```bash
cd packages/dropclip_transfer && dart test test/adversarial_test.dart
```

| ID | Attack | Correct behaviour | v1.0.9 → now |
|---|---|---|---|
| ADV-01 | Send a file named `Screenshots` (no extension) while the folder `Downloads/Screenshots` exists | Saved as `Screenshots (1)` | Broke (`PathAccessException`, `.part` left behind) → **fixed** |
| ADV-01b | One offer with a file `report` and a file `report/a.txt` | Offer refused, or both saved | Broke (accepted, then `PathExistsException`) → **fixed**: refused |
| ADV-01c | Same as 01b with different case: `Report` and `report/a.txt` | Offer refused | Broke → **fixed**: refused |
| ADV-02 | A paired device offers a 1 PB file to the phone | Refused: the phone has no space | Broke (accepted, wrote until full) → **fixed**: refused |
| ADV-03 | Path longer than Windows MAX_PATH (about 1 500 chars, 12 folders) | Saved | Passes |
| ADV-04 | `photo.jpg` and `photo.jpg.part` in one offer | Both saved | Passes |
| ADV-05 | The sender retries the same upload while the first is still writing | No duplicate bytes, file intact | Passes |
| ADV-06 | `café.txt` in composed (NFC) and decomposed (NFD) form in one offer | Two separate files | Passes on Windows (macOS not tested) |

### What was wrong and how it is fixed

- **ADV-01**
  - **Cause:** `freeNameFor` checked only for a *file* with the same name, not a *folder*.
  - **Fix:** any existing entry now counts as taken, so the file is saved as `Screenshots (1)`.
- **ADV-01b / 01c**
  - **Cause:** `validateOffer` did not check file-versus-folder clashes.
  - **Fix:** the offer is now refused when a path is both a file and a folder in the same offer (case ignored), or when a file on disk is in the way of a folder the offer needs.
- **ADV-02**
  - **Cause:** the phone accepted offers without checking free space.
  - **Fix:** the phone now asks Android (`StatFs`) or iOS (`volumeAvailableCapacityForImportantUsage`) for free space through the `dropclip/storage` channel, and refuses offers that do not fit. If the platform cannot say, there is no check, as before.
- **Phone write errors**
  - **Cause:** a write error other than a protocol error (disk full, folder gone) left the transfer open forever.
  - **Fix:** the phone now ends the transfer, deletes the partial file and sends `file.complete` with state `failed`, as the PC does.

Phone-level tests: `apps/mobile/test/mobile_node_test.dart`, "ADV-02 the phone refuses…" and "a write error on the phone ends the transfer…".

The Android and iOS native code for the free-space check has not been compiled or tried on a device yet.

### Checked and not a bug

- Windows device names with a space, such as `con .txt` or `NUL .png`: Windows 11 saves them as normal files.
- Negative sizes: refused at the first write.
- More than 10 000 items: both apps refuse the offer before the receiver sees it.

---

## Part 2 — Manual hard cases

**Setup:** one Windows PC and one phone, paired, on the same Wi-Fi, unless the case says otherwise. Write Pass or Fail in the last column. A case passes only if the app recovers by itself, without a restart or pairing again.

### A. Network

| ID | How to break it | Correct behaviour | Pass/Fail |
|---|---|---|---|
| H-01 | PC → phone, file over 200 MB. At about 50%, switch the phone to another Wi-Fi network. | Both sides show **failed**, not complete. No half file shows as received. Sending again works after reconnecting. | |
| H-02 | Turn on a VPN on the PC (Radmin, Hamachi, any corporate VPN), then restart DropClip. | The phone still finds and connects to the PC. Settings → Network adapter lets you pick the real Wi-Fi adapter. | |
| H-03 | Connect both devices to a guest Wi-Fi that blocks devices from seeing each other. | Clear "not connected" status on both. No crash and no endless spinner. | |
| H-04 | While connected, run `ipconfig /release` then `ipconfig /renew` on the PC so it gets a new IP. | The phone reconnects within about 30 s without pairing again. | |
| H-05 | Two phones (or a phone and a second PC) send a file to the PC at the same moment. | Two separate "receive?" prompts. Both files are saved. | |
| H-06 | PC → phone, file over 1 GB on a weak signal (far from the router). | Progress keeps moving, or fails clearly. It never stays stuck at the same percentage for more than about 1 minute. | |

### B. Device and operating system

| ID | How to break it | Correct behaviour | Pass/Fail |
|---|---|---|---|
| H-07 | PC → iPhone transfer. Lock the iPhone halfway. | The PC shows failed within about 1 minute. Sending again after unlocking works. | |
| H-08 | PC receiving a large file: end DropClip in Task Manager halfway, then open it again. | The app starts normally. Sending the same file again works. The leftover `.part` is cleaned up or resumed. | |
| H-09 | Set the PC download folder to a USB stick with less free space than the file, then send the file. | Refused before sending, or a clear "disk full" error. No crash. Partial file removed. | |
| H-10 | Delete the download folder in Explorer while DropClip is running, then receive a file. | The folder is recreated and the file saved, or a clear error. | |
| H-11 | Set the download folder to a place without write access (e.g. `C:\Windows`). | A clear error in Settings or on receive. No crash. | |
| H-12 | While connected, set the PC clock back 2 hours, then copy text on the PC. | The text still reaches the phone. | |
| H-13 | Put the PC to sleep for 5 minutes, then wake it. | The phone reconnects by itself within about 30 s. | |
| H-14 | Close and reopen the phone app 10 times quickly. | Ends up connected. The PC shows the phone once, not duplicates. | |

### C. Files

| ID | How to break it | Correct behaviour | Pass/Fail |
|---|---|---|---|
| H-15 | **(ADV-01)** In the PC's download folder, create a folder `test`. From the phone, send a file named exactly `test` (no extension). | Saved as `test (1)`. Fails on v1.0.9; fixed in PR #120. | |
| H-16 | Send a file over 4 GB from the PC to the iPhone. | Arrives intact, or a clear error if the phone lacks space. The phone app does not crash. | |
| H-17 | Send a folder with 5 000 small files to the PC. | All arrive and the folder structure is kept. The PC stays responsive. | |
| H-18 | Start sending a file that is still growing (e.g. a screen recording in progress). | Fails clearly (checksum), or sends the version from when it started. Never "complete" with a broken file. | |
| H-19 | Choose a file, then delete it before pressing Send. | A clear "file not found" error. No crash. | |
| H-20 | Send files named with emoji, Thai, and a name made on a Mac (`café.txt`). | Saved with readable names that can be opened. | |
| H-21 | Send a file named `photo.jpg` twice in a row, very fast. | `photo.jpg` and `photo (1).jpg`. **Fixed by PR #120.** | |

### D. Clipboard

| ID | How to break it | Correct behaviour | Pass/Fail |
|---|---|---|---|
| H-22 | Copy 30 MB of text on the PC (just under the 32 MiB limit), then 40 MB. | 30 MB arrives (may take a moment). 40 MB is skipped without freezing either app. | |
| H-23 | Copy 50 different texts in 10 seconds on the PC (use a script or macro). | The phone ends with the last one. No ping-pong between the devices. | |
| H-24 | Copy on the PC and press "Send clipboard" on the phone in the same second. | Both devices end with the same text, the newer one. | |
| H-25 | Copy a 20-megapixel photo on the PC. | The image arrives on the phone. The PC stays responsive. | |

### E. Security and trust

| ID | How to break it | Correct behaviour | Pass/Fail |
|---|---|---|---|
| H-26 | From an unpaired phone, enter a wrong PIN 10 times. | Pairing is locked for that device for a while. The PC stays usable. | |
| H-27 | Restore an iPhone backup onto a second iPhone, so both have the same identity. Open DropClip on both. | Only one connects at a time, or the PC warns. The two never fight forever (connect, drop, connect…). | |
| H-28 | Remove the phone on the PC while the phone is sending a file. | The transfer stops. The phone shows the PC as removed. Nothing more is accepted from it. | |
| H-29 | Two people try to pair new phones with the same PC at the same time. | Only one session succeeds. The other gets a clear error and creates no trust. | |

---

## Summary

| Group | Cases | Known to fail on v1.0.9 |
|---|---|---|
| Automated | 8 | ADV-01, 01b, 01c, 02 (all fixed in PR #120) |
| A. Network | 6 | |
| B. Device and OS | 8 | |
| C. Files | 7 | H-15 |
| D. Clipboard | 4 | |
| E. Security and trust | 4 | |
| **Total** | **37** | |
