# Work Log — MOB PR review, 2026-11-10

| Item | Value |
|---|---|
| Tickets | S0.2, T1.3; T0.1 bootstrap follow-up |
| Developer | MOB (เกื้อ), assisted by Codex |
| Tracking branch | `docs/task-progress-tracker` only |
| Status | Technical review complete; LEAD acceptance/security review and production integration pending |

## Scope and rules

Reviewed against AGENTS.md, CONTRIBUTING.md, README, Playbook ADR-007/009, Protocol §4.4–5.6, S0.2/T1.3/T1.4/T2.5 tickets, SRS FR-02/NFR-R03B and threat mitigations T-S02/T-D04/T-E02. Code/test diffs stay in their task branches. User authorized merge of #56 and review of the other five PRs. No LEAD approval is claimed.

## Reviewed heads and latest GitHub checks

| PR | Head | Diff lines | Latest checks | Result |
|---|---|---:|---|---|
| [#53](https://github.com/nCotista/DropClip/pull/53) | `cfae1cb` | 60 | 7/7 success | Android harness review complete; LEAD acceptance pending |
| [#54](https://github.com/nCotista/DropClip/pull/54) | `916ad1e` | 18 | 5/5 success | Corrected 30 MiB to SRS 30 MB; exception remains explicit |
| [#55](https://github.com/nCotista/DropClip/pull/55) | `03e7f3f` | 123 | 5/5 success | Corrected device RSS bytes/KiB mismatch; tests added |
| [#56](https://github.com/nCotista/DropClip/pull/56) | `5162b31` | 3 | 5/5 success | Squash merged as `2ffd255` on user authorization |
| [#57](https://github.com/nCotista/DropClip/pull/57) | `0320b34` | 124 | 5/5 success | No additional blocking finding; LEAD security review required |
| [#58](https://github.com/nCotista/DropClip/pull/58) | `a37548b` | 397 | 5/5 success | No additional blocking finding; LEAD security review required |

All five open branches include the #56 bootstrap fix from `main`. Ubuntu/macOS/Windows quality gates, native Windows tests and secret audit passed. #53 also passed API 34/35 emulator jobs. PR descriptions and technical review comments now reflect the latest state. Only #56 was merged.

## Findings and validation

- **iOS RSS units (#55):** Darwin `ru_maxrss` is bytes. The device path's old KiB label/display caused a factor-of-1024 error. Store raw bytes, use explicit MiB display, and ignore ambiguous legacy filenames. Tests cover actual measured value, whitespace, zero, negative, missing and nonnumeric input. Swift helper coverage 56/59 lines (94.92%); Swift tests and five receiver tests pass. Generic Simulator/device build and analyze pass with signing disabled.
- **Requirement units (#54):** Original NFR-R03B is <30 MB, not <30 MiB. ADR/harness documentation now uses 30,000,000 bytes. No new physical-device measurement is claimed; a device enqueue-time snapshot alone does not measure full-transfer peak.
- **Pairing integration (#57 + #58):** A separate local checkout combining both heads passed 110 core tests, analyze with no issues, and format with zero changes. This combined branch is not published as a >400-line PR. #58's earlier standalone coverage remains 1122/1213 core lines (92.50%), engine 148/156 (94.87%).
- **Pairing TLS (#58):** Optional client-certificate fingerprint matches Protocol §4.4 for unpaired clients. Supplied fingerprints remain checked; commitment validation and both SAS confirmations gate trust. Reviewed downgrade, pinning, mismatch, expiry, malformed input, rate-window and lockout cases. Latest Windows CI executes the TLS tests, superseding the earlier bootstrap-blocked result.
- **Android recovery (#53):** Seven corrected hardware tests passed. Original PID 3044 exited at 06:15:51.964 on 2026-11-10 with SIGNALED/status 9 (SIGKILL), cause unknown. Later PID 9205 had restartCount=1, foreground state and an actual multicast lock. Recovery is demonstrated; uninterrupted overnight survival and Doze survival are not. Only four initial monitor samples exist. [Raw evidence](evidence/S0.2-android15-2026-11-10.txt), [corrected suite](evidence/S0.2-android15-regression-2026-11-10.txt).

[Apple Darwin source documentation for getrusage](https://github.com/apple/darwin-xnu/blob/main/bsd/man/man2/getrusage.2) supports the byte units used here.

## Remaining acceptance and ownership

- S0.2 remains DONE by the existing LEAD exception, with failed/missing original measurements visible. LEAD still needs to assess the newly observed SIGKILL/recovery finding. No new physical iOS run is assigned; no phone is needed for the completed PR reviews.
- T1.3's full flow cannot yet be exercised in the app inspected at `main` `2ffd255`: mobile `main.dart` prints startup messages; desktop Pair calls `_notReady` at `apps/desktop/lib/src/shell.dart:103`; production pairing HTTP routing was not found. T1.4 belongs to NET, and T2.5 mobile QR/UI belongs to MOB. No branch containing those implementations was found in the remote inspection.
- Test-adapter HTTPS and in-memory JSON assertions do not satisfy production UI integration or formal PCAP inspection. Complete scan/confirmation timing <15 seconds, bilateral trust persistence and post-pair mTLS/WebSocket remain unverified.
- CONTRIBUTING §2.1 requires LEAD review for security work. These technical comments do not substitute for that approval. PRs #53/#54/#55/#57/#58 remain open.
