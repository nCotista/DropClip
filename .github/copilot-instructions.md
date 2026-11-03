# GitHub Copilot Instructions for DropClip

Please refer to `AGENTS.md` for the complete architectural and operational guidelines.

Key Directives:
1. **Zero-Cloud & Privacy First:** No telemetry, no third-party cloud connections. Everything is local LAN/Wi-Fi.
2. **Streaming Only:** Never read entire files into RAM. Always use chunked streams (1 MiB buffer).
3. **Crypto Safety:** ECDSA P-256 (secp256r1) with TLS 1.3 only. Never implement custom crypto algorithms.
4. **Zero PIN on Wire:** Never send pairing PIN or hash of PIN over the wire. It is strictly an OOB salt for SAS.
5. **Quality Checks:** Always write unit tests for every change. Run `melos run analyze` and `melos run test`.
6. **Logging & Tracking:** Keep work logs in `docs/worklogs/` and update `docs/TASK-PROGRESS-AND-UPDATES.md` in `docs/task-progress-tracker` branch only (never in feature branches).

