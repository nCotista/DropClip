# DropClip — AI Agent & Developer Workspace Instructions
# (AI Instructions & Coding Standards for Collaborative Development)

Welcome AI assistants (Cursor, Copilot, Windsurf, Claude Code, Antigravity, ChatGPT) and engineers!
This document is the **authoritative operating specification** for working within the DropClip codebase.
Every AI assistant working in this repository **MUST** adhere strictly to the rules, architectural invariants, logging protocols, and task update procedures defined herein.

---

## 1. Project Overview & Core Philosophy

**DropClip** is a high-throughput, cross-platform clipboard continuity and file transfer system for personal device clusters (macOS, Windows, Android, iOS).
- **Core Philosophy:** **Zero-Cloud & 100% Local-First**. All communications happen directly over local Wi-Fi/LAN (Subnet).
- **Zero-Cloud Guarantee:** NO central servers, NO cloud relays (No TURN/STUN), NO third-party telemetry, NO analytics SDKs.
- **Monorepo Architecture:** Melos monorepo powered by Dart & Flutter, with native platform hooks:
  - macOS & iOS: Swift / Network.framework
  - Windows: C++ / Win32 API
  - Android: Kotlin / Android Keystore / Foreground Service

### Official Documentation Reference
Before designing or implementing code, always consult the primary specifications:
1. [`docs/00-PROJECT-PROPOSAL-AND-PLAYBOOK.md`](docs/00-PROJECT-PROPOSAL-AND-PLAYBOOK.md) — Playbook, team rules & ADRs
2. [`docs/01-PROTOCOL-SPEC.md`](docs/01-PROTOCOL-SPEC.md) — Wire protocol v2.0, state machines, packet frames
3. [`docs/02-TICKETS.md`](docs/02-TICKETS.md) — Task breakdown, estimates, and team allocations
4. [`docs/03-SRS.md`](docs/03-SRS.md) — Software Requirements Specification (FR, NFR, Tiers)
5. [`docs/04-THREAT-MODEL.md`](docs/04-THREAT-MODEL.md) — STRIDE analysis, Attack Trees, CVSS v3.1
6. [`docs/05-RELEASE-AND-UPDATE-PLAN.md`](docs/05-RELEASE-AND-UPDATE-PLAN.md) — Roll-Forward release & distribution

---

## 2. The 6 Non-Negotiable Engineering Rules (กฎ 6 ข้อที่ห้ามละเมิด)

Every PR and AI code change must pass these constraints:

1. **Pull Request Max Size:** PRs **MUST NOT exceed 400 lines of diff** (excluding generated files `*.g.dart`, `*.freezed.dart`). If a task exceeds 400 lines, decompose it into sub-tasks.
2. **No Code Without Tests:** Every feature or fix **MUST** have unit or integration tests covering Happy Path and at least 3 edge cases. Minimum package coverage threshold is **75%**.
3. **Timeboxed Spikes:** Research/Spike tasks are timeboxed to **4 hours max**. If blocked, escalate immediately to Team Lead (`LEAD`).
4. **NO Homegrown Cryptography:** Use standard **TLS 1.3** (`SecureServerSocket`, `HttpClient`, Network.framework, OkHttp) with **ECDSA P-256 (secp256r1)** self-signed certificates; private keys are envelope-encrypted with OS secure storage (Keychain, DPAPI, Android Keystore wrapping key) — not hardware-bound, because Dart TLS needs key bytes (Protocol Spec §4.2).
5. **NO Whole-File RAM Buffering:** **NEVER** use `file.readAsBytes()` for file transfers. File transfer **MUST** stream in **1 MiB chunks** (Delta RSS ≤ 50 MB over baseline on desktop, < 30 MB peak in iOS Share Extension — SRS NFR-R01).
6. **Strict Conventional Commits:** All commits must follow:
   `<type>(<scope>): <short description> (<TICKET_ID>)`

---

## 3. Strict Architectural & Protocol Invariants

When writing code, you **MUST NOT** violate these protocol invariants:

### 3.1 Pairing & Zero-PIN-on-Wire Security (ADR-009 & Protocol Spec §5)
- **Commit-then-Reveal SAS:** In pairing, the client sends commitment $C_B = \text{SHA-256}(\text{"dropclip-commit-v1:"} \parallel N_B \parallel \text{fp}_B)$ to host **before** host reveals $N_A$. This prevents active MITM collision attacks.
- **Zero PIN on Wire:** In Manual PIN pairing mode, **NEVER transmit the PIN or any PIN hash over the network**. The 6-digit PIN is strictly an Out-of-Band (OOB) salt for the client's local SAS calculation:
  $$\text{SAS} = \text{SHA-256}(\text{fp}_{lo} \parallel \text{fp}_{hi} \parallel N_A \parallel N_B \parallel \text{"dropclip-pin-salt-v1:"} \parallel \text{UTF8}(\text{PIN})) \bmod 10^6$$
  *(Test vector conformance: QR mode `"337017"`, PIN mode `"639589"`).*

### 3.2 Protocol Version Negotiation (Protocol Spec §2.4 & SRS FR-10)
- Nodes negotiate version via compatible overlap:
  $$\min(\text{local.v}, \text{remote.v}) \ge \max(\text{local.min\_supported\_v}, \text{remote.min\_supported\_v})$$
- If incompatible, close WebSocket with code **`4003`** and error **`E_UNSUPPORTED_VERSION`**.

### 3.3 Explicit Size Quotas (Protocol Spec §7.1 & §10.2)
- **WebSocket Control Plane Frame:** Max **64 KiB** (`E_PAYLOAD_TOO_LARGE`).
- **Inline Text Payload:** Max **32 KiB**.
- **Blob Threshold:** $> 32$ KiB routes to HTTP Data Plane.
- **Maximum Content Total (Image / Clipboard):** **32 MiB**.
- **Data Plane Streaming File Transfer:** Unlimited.

### 3.4 Revocation Safety (Protocol Spec §13.2 & SRS FR-11)
- **No Self-Revocation by Proxy:** If a node receives a cluster revocation broadcast where `revoked_id == my_id`, it **MUST ignore it** (prevents stolen devices from wiping legitimate peers).
- **Quarantine-then-Confirm:** A valid revocation of *another* peer only quarantines it (disconnect + reject) until the local user confirms; if the user rejects, the revoker is quarantined instead (stops a stolen device from permanently revoking real peers).
- **Persistent Tombstones & Handshake Anti-Entropy:** Offline peers exchange `tombstones_hash` in `hello`/`hello.ack` and sync via `revocation.sync`.

### 3.5 Sensitive Content Suppression (SRS NFR-S04)
100% suppress and drop clipboard content marked with any of the 5 recognized OS markers:
1. macOS: `org.nspasteboard.ConcealedType`
2. macOS: `org.nspasteboard.TransientType` / `com.agilebits.onepassword`
3. Windows: `ExcludeClipboardContentFromMonitorProcessing`
4. Windows: `CanIncludeInClipboardHistory` or `CanUploadToCloudClipboard` (value 0)
5. Android: `ClipDescription.EXTRA_IS_SENSITIVE` / `Clipboard.EXTRA_IS_SENSITIVE`

---

## 4. Monorepo Organization & Commands

```
DropClip/
├── apps/
│   ├── desktop/              # Flutter Desktop (macOS & Windows UI, tray, dropzone)
│   └── mobile/               # Flutter Mobile (Android & iOS UI)
├── packages/
│   ├── dropclip_protocol/    # Pure Dart wire protocol, envelopes, SAS, HLC
│   ├── dropclip_core/        # Node engine, TLS 1.3 transport, pairing, storage
│   ├── dropclip_clipboard/   # Clipboard watcher, suppression, HLC merger
│   ├── dropclip_transfer/    # Streaming file transfer sender/receiver, checkpoints
│   └── dropclip_ui/          # Shared Flutter widgets, themes, components
├── native/                   # Native platform implementations (Swift, C++, Kotlin)
├── tools/
│   ├── bench/                # Benchmarking harness & iperf3 runner
│   └── protocol_fuzzer/      # Robustness fuzzing suite
└── docs/                     # Specifications, tickets, threat models, worklogs
```

### Essential Melos Commands
Run these from the repository root:
```bash
# Bootstrap all packages and link dependencies
melos bootstrap

# Check formatting across all packages (must pass cleanly)
melos run format

# Auto-fix formatting across all packages
melos run format:fix

# Run static analysis with fatal warnings (must report 0 issues)
melos run analyze

# Run unit tests across all packages
melos run test

# Run tests with code coverage output
melos run test:coverage

# Run code generation (build_runner)
melos run build:runner
```

---

## 5. Mandatory Workflow for Developers & AI Assistants

Whenever an AI assistant or human developer starts or finishes a task, **YOU MUST FOLLOW THIS TWO-STREAM WORKFLOW**:

> [!IMPORTANT]
> **Centralized Progress Branch:** All updates to `docs/worklogs/` and `docs/TASK-PROGRESS-AND-UPDATES.md` (or `UPDATES.md`) **MUST be committed to the `docs/task-progress-tracker` branch ONLY**!
> **DO NOT** commit worklogs or task progress updates into feature/spike/fix branches (prevents merge conflicts and keeps PR diffs $\le 400$ lines).

### Stream 1: Feature / Spike / Fix Branch (Code & Tests Only)
1. Pick your assigned ticket from [`docs/02-TICKETS.md`](docs/02-TICKETS.md).
2. Branch out from `main`:
   ```bash
   git checkout -b <type>/<TICKET_ID>-<slug>
   # Example: git checkout -b feat/T1.1-mdns-discovery
   ```
3. Implement code and tests in this branch. Keep PR diff $\le 400$ lines.
4. Verify code quality:
   ```bash
   melos run format
   melos run analyze
   melos run test
   ```
5. Commit only code and tests. Open PR, review, and merge into `main`.

### Stream 2: Worklog & Task Progress Tracking (in `docs/task-progress-tracker` branch ONLY)
**Record worklogs and update central progress on the tracker branch:**
1. Switch to `docs/task-progress-tracker` branch:
   ```bash
   git checkout docs/task-progress-tracker
   git pull origin docs/task-progress-tracker
   ```
2. **Open or create your branch work log** in [`docs/worklogs/`](docs/worklogs/):
   - Copy [`docs/worklogs/TEMPLATE.md`](docs/worklogs/TEMPLATE.md) into `docs/worklogs/<TICKET_ID>-<slug>.md` (or append to [`docs/worklogs/WORK_LOG.md`](docs/worklogs/WORK_LOG.md)).
   - Document what you did, technical decisions made, and test results.
3. Open [`docs/TASK-PROGRESS-AND-UPDATES.md`](docs/TASK-PROGRESS-AND-UPDATES.md) (or root shortcut [`UPDATES.md`](UPDATES.md)):
   - Mark your ticket as `[x] DONE` in the Ticket Status Board.
   - Add a new row in the **Branch & Completed Tasks Registry table** with Ticket ID, Branch Name, Assignee, Status, Commit Hash, Date, Summary, and Reviewer notes.
4. Commit and push directly to `docs/task-progress-tracker`:
   ```bash
   git add docs/TASK-PROGRESS-AND-UPDATES.md docs/worklogs/
   git commit -m "docs(updates): update task progress and worklog for <TICKET_ID>"
   git push origin docs/task-progress-tracker
   ```

---

## 6. Definition of Done (DoD) Checklist

No branch or PR may be approved or merged until ALL boxes are checked:
- [ ] Code strictly follows Monorepo & Architectural Invariants (§3).
- [ ] PR diff is $\le 400$ lines (excluding generated files).
- [ ] Feature branch does NOT contain `docs/worklogs/` or `docs/TASK-PROGRESS-AND-UPDATES.md`.
- [ ] `melos run format` passes with 0 changes.
- [ ] `melos run analyze` passes with 0 infos, warnings, or errors.
- [ ] Unit & integration tests pass with $\ge 75\%$ code coverage.
- [ ] NO plaintext secrets, private keys, or clipboard contents logged.
- [ ] Work log documented and central progress registry updated in `docs/task-progress-tracker` branch.

