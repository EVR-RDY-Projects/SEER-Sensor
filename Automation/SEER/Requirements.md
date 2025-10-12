# Requirement 0 — Interactive Setup & Configuration Wizard

## Purpose
Provide a guided, idempotent way to collect deployment parameters and produce a valid `/opt/seer/etc/seer.yml`, create required directories with correct ownership, and (optionally) enable services — without embedding business logic into other components.

## Scope
- First-run configuration and safe reconfiguration.
- Validation + file/dir setup only (no capture/analysis here).
- Offline-capable.

## Inputs (Operator-Provided)
- **Network interface**: default `enp1s0` (must exist; non-loopback).
- **tcpdump snaplen**: default `128` (bytes; integer ≥ 64).
- **Rotation interval**: default `20` (seconds; integer 5–300).
- **Zeek workers**: default `2` (integer ≥ 1, ≤ CPU cores).
- **AF_PACKET fanout ID**: default `42` (1–65535; warn on collision).
- **UI refresh interval**: default `0.5` (seconds; 0.1–5.0).
- **Buffer threshold**: default `4` (files; ≥ 2).
- **Paths** (defaults, overridable):
  - `ring_dir` → `/var/seer/pcap_ring`
  - `dest_dir` → `/opt/seer/var/queue`
  - `backlog_dir` → `/opt/seer/var/backlog`
  - `json_spool` → `/var/seer/json_spool`
  - `mover_log` → `/var/log/seer/mover.log`
- **Disk guardrails**:
  - `disk_soft_pct` → `80`
  - `disk_hard_pct` → `90`
- **Run user/group**: fixed `seer:seer` (must exist/will be created).

## Validation Rules
- Interface exists in `/sys/class/net/<iface>` and is not `lo`.
- Paths are absolute, on local filesystems, writable by `seer:seer`.
- Percent thresholds: integers 1–99 with `soft < hard`.
- Numerical inputs within stated ranges; reject → re-prompt.
- If `zeek_workers > CPU cores`, warn and cap; record the cap.

## Outputs
- **YAML** `/opt/seer/etc/seer.yml` with exact keys:
  ```yaml
  refresh_interval: <float>
  buffer_threshold: <int>
  ring_dir: <path>
  dest_dir: <path>
  backlog_dir: <path>
  json_spool: <path>
  mover_log: <path>
  interface: <string>
  fanout_id: <int>
  zeek_workers: <int>
  capture:
    snaplen: <int>
    rotate_seconds: <int>
    disk_soft_pct: <int>
    disk_hard_pct: <int>

- Directories ensured with perms/ownership:
  - /opt/seer/bin  → 0755, seer:seer
  - /opt/seer/etc  → 0755, seer:seer
  - /opt/seer/var/queue  → 0750, seer:seer
  - /opt/seer/var/backlog → 0750, seer:seer
  - /var/seer/pcap_ring   → 0750, seer:seer
  - /var/seer/json_spool  → 0750, seer:seer
  - /var/log/seer         → 0755, seer:seer
- No auto-start by default; provide an explicit “enable services now?” toggle (handled by installer later).

## Idempotency & Safety
- Re-run uses existing values as defaults; operator can accept/modify.
- Prior config is backed up as seer.yml.bak-YYYYmmdd-HHMMSS before overwrite.
- Validate free space on filesystems hosting ring_dir and json_spool; warn if <10% free.
- Never deletes data; only creates/updates config and directories.

## Non-Functional Requirements
- Offline: no network access required.
- Clear UX: show a pre-write YAML preview and final confirmation.
- Auditability: append changes to /var/log/seer/setup.log (who/when/what).
- Minimal deps: POSIX tools; YAML writing via Python or pure POSIX (no heavy deps).

## Acceptance Criteria
- Given valid inputs, seer.yml is created with the exact key structure above.
- Required directories exist with specified permissions/ownership.
- Re-run preserves prior values as defaults and creates a timestamped backup.
- Interface validation rejects non-existent/loopback interfaces with clear guidance.
- Disk guardrails satisfy soft < hard; otherwise, prompt to fix.
- Dry-run mode available: prints intended actions and YAML; performs no writes.

## Edge Cases
- Interface is down: warn, allow continue, mark status: degraded in setup log.
- Target path on read-only filesystem: fail with remediation hint.
- Operator refuses creation of seer:seer: block (non-root steady state is mandatory).
- Existing malformed YAML: back up original; regenerate from validated inputs, preserving recoverable keys where possible.

## Dependencies
- Must run with elevated privileges for directory creation and ownership changes.
- Downstream components (capture, Zeek, mover) must consume values from this YAML without assuming defaults.

# Requirement 1 — PCAP Capture & Ring Buffer (tcpdump)

## Purpose
Maintain a continuous, timestamped forensic PCAP archive independent of Zeek, with predictable rotation and graceful shutdown to avoid truncated files.

## Scope
- Live packet capture from a tap/SPAN on a single interface.
- Ring-style rotation to bounded file count/age (mover handles overflow).
- Non-root steady state (runs as seer:seer).

## Behavior
- Interface: templated via `%i` (default `enp1s0` from config).
- Command shape (spec only, not code): tcpdump with `-n -U -s <snaplen> -G <rotate_seconds> -Z seer -w <ring_dir>/SEER-%Y%m%d-%H%M%S.pcap`
- Rotation: new file every `<rotate_seconds>` (default 20s).
- Snap length: `<snaplen>` bytes (default 128; tunable).
- Timebase: local time (option to switch to UTC in config).
- Ownership: files owned by `seer:seer`, mode `0640`; `ring_dir` mode `0750`.
- Stop behavior: send SIGINT so the last file closes cleanly.
- Journaling: capture process logs to journal with tag `seer-capture`.

## Disk Guardrails (soft enforcement; mover provides relief)
- `disk_soft_pct` (default 80): emit warning to journal when the filesystem hosting `ring_dir` exceeds this.
- `disk_hard_pct` (default 90): pause starting new captures; log error; rely on mover/export to reduce usage.

## Inputs (from /opt/seer/etc/seer.yml)
- `capture.interface` (string) — default `enp1s0`
- `capture.snaplen` (int) — default `128`
- `capture.rotate_seconds` (int) — default `20`
- `capture.disk_soft_pct` (int) — default `80`
- `capture.disk_hard_pct` (int) — default `90`
- `ring_dir` (path) — default `/var/seer/pcap_ring`

## Interactions & Contracts
- **With Requirement 7 (Mover):** when count of PCAPs in `ring_dir` ≥ `buffer_threshold` (default 4), mover will relocate the **oldest** file out of the ring. Capture must not lock files longer than needed to close/rotate.
- **With Requirement 0 (Setup):** respects YAML values; no hidden defaults beyond those explicitly listed here.
- **With Requirement 5 (Monitoring/TUI):** exposes status via `systemctl is-active` and by observable file creation cadence in `ring_dir`.

## Validation Rules
- Interface is non-loopback and exists.
- `snaplen` ≥ 64 and ≤ MTU+overhead (practically ≤ 262144).
- `rotate_seconds` ∈ [5, 300].
- `disk_soft_pct` and `disk_hard_pct` are 1–99 with `soft < hard`.

## Acceptance Criteria
- A new PCAP appears in `ring_dir` every ~`rotate_seconds`.
- Stopping capture yields a readable last file (pcap header/trailer intact).
- Files/dirs have required ownership and permissions.
- Soft/hard disk thresholds trigger the specified journald messages/actions.
- Under mover pressure (≥ threshold), oldest files leave `ring_dir` without breaking active capture.

## Non-Functional
- Runs continuously; auto-restarts on failure.
- Minimal CPU impact; `-s 128` chosen to reduce I/O (tunable).
- Works offline; no network dependencies.




