## SEER Sensor — Overview (Summary)

SEER is a modular, air-gap-friendly network forensics sensor. It captures PCAPs via tcpdump into a ring buffer, analyzes live traffic with Zeek over AF_PACKET, and safely evacuates PCAPs to an external drive (PCAP-only). A mover enforces a bounded ring by exporting the oldest safe files; integrity is enforced with streaming SHA-256, atomic manifests, and append-only transfer logs. A lightweight Agent Tracker maintains an on-box heartbeat inventory, while a Shipper (later) sends Zeek JSON and agent/service logs one-way over UDP through the GHOST diode to RAMPART. A TUI + local Status API surfaces health (capture/Zeek), storage pressure, current PCAP destination (which drive), integrity stats, and the number of agents reporting. An installer (last) provisions users/dirs, systemd units, and kernel tunings. Everything runs as `seer:seer`, writes state atomically, and degrades safely under disk or link pressure.

---

## Table of Contents
- [Req 0 — Interactive Setup & Configuration Wizard](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#requirement-0--interactive-setup--configuration-wizard)
- [Req 1 — PCAP Capture & Ring Buffer (tcpdump)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#requirement-1--pcap-capture--ring-buffer-tcpdump)
- [Req 1a — Service Definition for PCAP Capture (tcpdump)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#requirement-1a--service-definition-for-pcap-capture-tcpdump)
- [Req  2 — Zeek Live Analysis via AF_PACKET](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#requirement-2--zeek-live-analysis-via-af_packet)
- [Req 2a — Service Definition for Zeek (AF_PACKET)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#requirement-2a--service-definition-for-zeek-af_packet)
- [Req 3 — PCAP Mover (oldest-out with export-preferred path)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#requirement-3--pcap-mover-oldest-out-with-export-preferred-path)
- [Requirement 3a — Timer & Service Definition for Mover (unchanged + export-aware notes)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#requirement-3a--timer--service-definition-for-mover-unchanged--export-aware-notes)
- [Req 4 — Hot-Swap / Export (External Drive Offload)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#requirement-4--hot-swap--export-external-drive-offload)
- [Req 5 — Integrity: checksums/manifests & logging conventions](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#req-5--integrity-checksumsmanifests--logging-conventions)
- [Req 6 — Agent Tracker (environment heartbeat & inventory)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#req-6--agent-tracker-environment-heartbeat--inventory)
- [Req 7 — JSON & Agent Logs Shipper (UDP over GHOST to RAMPART)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#req-7--json--agent-logs-shipper-udp-over-ghost-to-rampart)
- [Req 8 — Monitoring: TUI Console & Status API](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#req-8--monitoring-tui-console--status-api)
- [Req 9 — Installer & sysctl / Kernel Tuning (deploy everything last)](https://github.com/EVR-RDY-Projects/SEER-Sensor/blob/main/Automation/SEER/Requirements.md#req-9--installer--sysctl--kernel-tuning-deploy-everything-last)


> **Optional:** Add a small “Back to top” link at the end of each section: `[↑ Back to top](#seer-sensor--overview-summary)` (adjust the anchor if you rename the summary heading).


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

# Requirement 1a — Service Definition for PCAP Capture (tcpdump)

## Purpose
Provide a parameterized systemd unit to run tcpdump as a long-lived service using values from `/opt/seer/etc/seer.yml`.

## Unit Model
- Template unit name: `seer-capture@.service`
- Instance example: `seer-capture@enp1s0.service`
- Targets/Ordering: `After=network-online.target`, `Wants=network-online.target`
- User/Group: `seer:seer` (non-root steady state)
- Logging: journald with identifier `seer-capture`
- Restart policy: `Restart=always`, `RestartSec=2`
- Stop behavior: send `SIGINT` to close the current pcap cleanly
- Security hardening:
  - `NoNewPrivileges=yes`
  - `ProtectSystem=full`
  - `ProtectHome=yes`
  - `PrivateTmp=yes`
  - `ReadWritePaths=/var/seer/pcap_ring /var/log/seer`
  - `CapabilityBoundingSet=CAP_NET_RAW` (only if needed at start; prefer dropping via `-Z seer`)

## Command Shape (spec only)
- `tcpdump -i %I -n -U -s <snaplen> -G <rotate_seconds> -Z seer -w <ring_dir>/SEER-%Y%m%d-%H%M%S.pcap`
- `%I` comes from the instance name; other parameters read from YAML at start via a small wrapper (Requirement 6 installer will place the wrapper).

## Configuration Contract
- Reads:
  - `capture.interface` (or `%I`), `capture.snaplen`, `capture.rotate_seconds`
  - `ring_dir`, `capture.disk_soft_pct`, `capture.disk_hard_pct`
- Must fail fast with a clear log if the interface doesn’t exist or `ring_dir` isn’t writable.

## Setup vs. Installation
- **Setup Wizard (Req 0):** collects values and writes `seer.yml`. It may **offer** to enable the service but does not create the unit file.
- **Installer (Req 6):** deploys the unit file to `/etc/systemd/system/`, `daemon-reload`, and optionally enables `seer-capture@<iface>.service`.

## Acceptance Criteria
- Starting `seer-capture@enp1s0` creates a new pcap every `rotate_seconds` in `ring_dir`.
- Stopping the service yields a readable final file (no truncation).
- Service runs as `seer:seer` and restarts on failure.
- Journald shows warnings at `disk_soft_pct` and error/pause behavior at `disk_hard_pct`.

# Requirement 2 — Zeek Live Analysis via AF_PACKET

## Purpose
Perform high-speed, zero-copy live traffic analysis with Zeek using AF_PACKET, outputting JSON logs for downstream processing and export.

## Scope
- Live capture on a single physical interface using AF_PACKET.
- Multi-worker load balancing (fanout) for scalability.
- JSON log output to a fixed spool directory.
- Non-root steady state (runs as seer:seer).

## Behavior
- Interface: af_packet::<interface> (default enp1s0 from config).
- Workers: zeek_workers (default 2) share a common fanout_id (default 42).
- Output: JSON logs written to /var/seer/json_spool with rotation by Zeek defaults.
- Start/Stop: graceful startup; on stop, Zeek closes logs cleanly.
- Isolation: Zeek’s AF_PACKET socket is independent from tcpdump’s libpcap path.

## Performance & Kernel Tuning (consumed from installer step)
- sysctl hints: rmem_max, wmem_max, netdev_max_backlog sized as per Requirement 6.
- Optional NIC queue tuning using ethtool if available.

## Inputs (from /opt/seer/etc/seer.yml)
- interface: string (default enp1s0)
- zeek_workers: int (default 2; must be 1..CPU cores)
- fanout_id: int (default 42; 1..65535; shared across workers)
- json_spool: path (default /var/seer/json_spool)

## Configuration Contract
- Zeek node config must reference af_packet::<interface>.
- Fanout ID must match for all workers on the same interface.
- Output format is JSON (not TSV) and lands in json_spool.

## Interactions & Contracts
- With Requirement 1 (tcpdump): both read the same physical link; no dependency ordering beyond After=network-online.target.
- With Requirement 5 (Monitoring/TUI): expose observable signals such as worker count, recent file writes in json_spool, and process state.
- With Requirement 4 (Hot-swap/export): json_spool is part of export payloads and integrity manifests.

## Validation Rules
- interface exists and is non-loopback.
- zeek_workers within 1..CPU cores; if higher, cap and log.
- json_spool exists, writable by seer:seer.

## Acceptance Criteria
- Zeek starts with af_packet::<interface> and spins up zeek_workers workers using fanout_id.
- JSON logs appear in json_spool during live traffic.
- Stopping Zeek yields cleanly closed log files.
- Under moderate traffic, no packet drop is observed in Zeek stats for sustained periods aligned with hardware capability.

## Non-Functional
- Continuous operation; auto-restart on failure.
- Works offline; no external dependencies.
- Minimal dependencies beyond Zeek itself.

# Requirement 2a — Service Definition for Zeek (AF_PACKET)

## Purpose
Provide a parameterized systemd unit (template) to run Zeek with AF_PACKET using values from /opt/seer/etc/seer.yml.

## Unit Model
- Template unit name: seer-zeek@.service
- Instance example: seer-zeek@enp1s0.service
- Ordering: After=network-online.target; Wants=network-online.target
- User/Group: seer:seer (non-root steady state)
- Logging: journald identifier seer-zeek
- Restart policy: Restart=on-failure; sensible backoff
- Security hardening:
  - NoNewPrivileges=yes
  - ProtectSystem=full
  - ProtectHome=yes
  - PrivateTmp=yes
  - ReadWritePaths=/var/seer/json_spool /var/log/seer
  - CapabilityBoundingSet minimized (Zeek should not retain elevated caps once AF_PACKET socket is open)

## Command Shape (spec only)
- Zeek invoked with interface af_packet::%I
- Worker count and fanout_id sourced from seer.yml (wrapper responsible)
- Example shape: /usr/local/zeek/bin/zeek -i af_packet::%I -b -C local

## Configuration Contract
- Reads: interface (%I), zeek_workers, fanout_id, json_spool from YAML.
- Must fail fast and log clearly if Zeek binary missing, interface invalid, or json_spool unwritable.

## Setup vs. Installation
- Setup Wizard (Req 0): writes YAML; may offer to enable.
- Installer (Req 6): deploys unit to /etc/systemd/system, performs daemon-reload, and optionally enables seer-zeek@<iface>.service.

## Acceptance Criteria
- Starting seer-zeek@enp1s0 launches Zeek bound to af_packet::enp1s0 with the configured number of workers and fanout_id.
- JSON logs are written to json_spool; ownership is seer:seer.
- Stopping the service results in closed, readable log files.

# Requirement 3 — PCAP Mover (oldest-out with export-preferred path)

## Purpose
Prevent the ring buffer from growing unbounded by moving the **oldest closed PCAP** out of `/var/seer/pcap_ring`, **preferentially to a mounted external drive** if present; otherwise, stage it in a local waiting area for later hot-swap export.

## Scope
- Threshold-based eviction by **file count** (not size).
- Safe file selection (never touch the currently written file).
- **Destination selection logic**:
  1) If an approved external mount is available with sufficient free space → move to that **export target**.
  2) Else → move to local **queue** (preferred) or **backlog** (fallback).
- No duplication with the hot-swap/export process.

## Behavior
1. **Trigger**: periodically (Req 3a) and on boot (catch-up).
2. **Candidate**: `pcaps = sorted(ring_dir/*.pcap by mtime asc)`.
3. **Threshold**: if `len(pcaps) >= buffer_threshold`, pick the **oldest** whose `mtime` is **older than rotate_seconds × 1.5**.
4. **Destination resolution** `export_target()`:
   - Detect mounted external targets, in priority order (first match wins):
     - `/mnt/SEER_EXT`
     - `/mnt/seer_ext`
     - Any mount under `/mnt/` or `/media/` with label containing `SEER` or `EXT`
   - Require:
     - Writable by `seer:seer`
     - Free space ≥ `file_size + 2%` buffer
   - If none qualifies, **return `None`**.
5. **Move decision**:
   - If `export_target()` returns a path `T`, move atomically to `${T}/pcap/<YYYYmmdd>/`.
   - Else move to `dest_dir/` (queue). If `dest_dir` not writable or low space → use `backlog_dir/`.
6. **Integrity hook**: compute/record checksum (finalized in Req 7).
7. **Idempotency**: one file per run; no duplicate moves.
8. **Logging**: append one line per action to `mover_log`.

## Inputs (from /opt/seer/etc/seer.yml)
- `ring_dir`: default `/var/seer/pcap_ring`
- `dest_dir`: default `/opt/seer/var/queue`
- `backlog_dir`: default `/opt/seer/var/backlog`
- `buffer_threshold`: default `4` (≥ 2)
- `mover_log`: default `/var/log/seer/mover.log`
- `capture.rotate_seconds`: used to avoid active files
- `export.mount_candidates` (optional list, default shown above)
- `export.min_free_pct`: default `2` (extra headroom on target FS)

## Interactions & Contracts
- **With Req 1 (tcpdump)**: never touch the active file; rely on rotate timing guard.
- **With Req 4 (Hot-swap/export)**:
  - If mover already writes directly to the external mount, hot-swap should **ignore** those files (to avoid double handling).
  - If mover stages to `dest_dir`/`backlog_dir`, hot-swap is responsible for transferring later.
  - A small sidecar marker (e.g., `.origin=mover`) may be written to exported directories for observability.
- **With Req 5 (Monitoring/TUI)**: expose counters:
  - `moved_export`, `moved_queue`, `moved_backlog`, `skipped_active`, `errors`.

## Validation Rules
- `buffer_threshold` integer ≥ 2.
- All directories exist and writable by `seer:seer`.
- Export target must be a local mount point; remote network FS optional but not required.

## Acceptance Criteria
- When ≥ `buffer_threshold` pcaps exist and a valid external mount is present with space, the **oldest safe** pcap is moved to the external drive under `pcap/YYYYmmdd/`.
- When no external mount qualifies, the file is moved to `dest_dir` (or `backlog_dir` if needed).
- The most recent (possibly-active) file is never moved.
- Each action logs: `ts action=move src=… dst=… bytes=… route=export|queue|backlog result=OK|ERROR sha256=<short>`.

## Non-Functional
- Fast decisions (<100 ms typical).
- Offline; minimal dependencies.
- Safe under power loss (copy-verify-delete fallback for cross-device moves).

---

# Requirement 3a — Timer & Service Definition for Mover (unchanged + export-aware notes)

## Purpose
Provide a systemd **oneshot** service and **recurring timer** to trigger the mover logic at a fixed cadence and on boot, with persistence across downtime.

## Unit Model
- Service: `seer-move-oldest.service` (Type=oneshot)
- Timer: `seer-move-oldest.timer`
- Schedule: `OnUnitActiveSec=20s`, `Persistent=true`
- User/Group: `seer:seer`; Ordering: `After=local-fs.target`
- Logging: journald identifier `seer-mover`

## Export-Aware Notes
- The service must **not** assume an external drive; it **checks** availability each run via `export_target()`.
- On error writing to export target, it must **fall back** to `dest_dir` or `backlog_dir` in the same invocation (no data loss, no tight retry loop).

## Acceptance Criteria
- Periodic runs visible via `systemctl list-timers`.
- With an external drive mounted, ticks route files to export; without it, ticks route to queue/backlog.
- After reboot, first tick processes accumulated ring files due to `Persistent=true`.
# Requirement 4 — Hot-Swap / Export (External Drive Offload)

## Purpose
Automatically detect an approved external drive and **export** staged artifacts (PCAPs and Zeek JSON) to it without dropping capture, then mark the export and signal it’s safe to remove.

## Scope
- Polls for presence of an approved mount (local block device; no network share required).
- Transfers files from local staging to the external drive with integrity checks.
- Writes clear logs and a human-readable receipt on the drive.
- Runs continuously as a background service under `seer:seer`.

## Sources (local staging)
- `dest_dir` (primary queue for ready-to-export PCAPs)
- `backlog_dir` (fallback queue when primary unavailable)
- `json_spool` (Zeek JSON logs; include everything except files still open by Zeek)

## Targets (external)
- Prioritized mount candidates (default list; overridable in config):
  - `/mnt/SEER_EXT`
  - `/mnt/seer_ext`
  - Any mount under `/mnt/` or `/media/` whose volume label contains `SEER` or `EXT`
- The chosen target root will contain:
  - `pcap/YYYYmmdd/` for PCAP files
  - `zeek/YYYYmmdd/` for JSON logs
  - `MANIFEST.txt` files (per batch directory)
  - `TRANSFER.LOG` (append-only, root of the volume)
  - Optional `.origin` markers (e.g., `.origin=mover`)

## Behavior
1. **Detection loop**: every `2s` (tunable), scan candidates for a writable mount with free space ≥ `min_free_pct` (default `2%` headroom above required bytes).
2. **Locking**: ensure a single exporter instance via a lightweight PID/lock file under `/var/log/seer/export.lock`. If locked, sleep until available.
3. **Selection**:
   - Prefer files in `dest_dir`, then `backlog_dir`, then `json_spool`.
   - Skip “active” files (modified within the last `rotate_seconds × 1.5` for PCAPs; for JSON, skip files still growing in size over two consecutive polls).
4. **Transfer**:
   - Same-filesystem: `rename` is atomic.
   - Cross-filesystem: `copy → fsync → sha256 verify → remove source`. Never delete on verify failure; log and retry later.
   - Place PCAPs under `pcap/YYYYmmdd/`; JSON under `zeek/YYYYmmdd/`.
5. **Integrity**:
   - For each destination subfolder created during a run, write a `MANIFEST.txt` containing lines of `sha256  relative/path`.
   - Append one line per file to `TRANSFER.LOG` with timestamp, hostname, src, dst, size bytes, sha256 (short), and `result=OK|VERIFY_FAIL|IO_ERROR|SKIP_ACTIVE`.
6. **Completion & Safe-remove hint**:
   - When queues are empty (no eligible files), write/update a small `EXPORT_STATUS.json` at the volume root summarizing counts and last transfer time.
   - If supported later, optionally touch a `SAFE_TO_REMOVE` marker when idle for >10s (purely informational; no hardware eject).

## Inputs (from `/opt/seer/etc/seer.yml`)
- `dest_dir`, `backlog_dir`, `json_spool`
- `capture.rotate_seconds` (used for “active file” guard)
- `export.mount_candidates` (list of mount paths/labels)
- `export.min_free_pct` (default `2`)
- `mover_log` or a dedicated `export_log` (implementation can reuse a shared log)

## Interactions & Contracts
- **With Requirement 3 (Mover)**:
  - If mover directly wrote to the external drive (when present), exporter must **skip** those paths (no duplication).
  - Otherwise, exporter drains `dest_dir` first, then `backlog_dir`.
- **With Requirement 5 (Monitoring/TUI)**: expose counters: `export_ok`, `verify_fail`, `io_error`, `skipped_active`, `bytes_exported`, `last_export_ts`.
- **With Requirement 7 (Integrity)**: use shared checksum/manifest helpers so hashing is consistent across mover/exporter.

## Validation Rules
- External target must be a local, writable mount and owned/accessible by `seer:seer`.
- Free space check must include a small safety margin (`min_free_pct`).
- Only closed files are exported (no growing files).
- JSON file detection must avoid partial files (double-poll size check).

## Acceptance Criteria
- When an approved external drive is mounted, queued PCAPs and stable Zeek JSON are exported to the correct dated folders, with manifests and a running `TRANSFER.LOG`.
- If no external is present, no files are lost; they remain in `dest_dir`/`backlog_dir` until a drive arrives.
- On cross-device moves, a failed checksum prevents source deletion and is logged as `VERIFY_FAIL`.
- Export resumes automatically after transient IO errors or after drive replacement.
- Only one exporter runs at a time (lock respected).

## Non-Functional
- Low CPU overhead; incremental hashing (streaming) preferred for large files.
- Resilient to power loss (never delete before successful verify on cross-FS).
- Offline operation; no network dependency.

---

# Requirement 4a — Service Definition for Hot-Swap / Export

## Purpose
Provide a long-running systemd unit that continuously watches for external mounts and performs exports per Requirement 4.

## Unit Model
- Service name: `seer-hotswap.service`
- Type: `simple` (long-running loop)
- Ordering: `After=local-fs.target`; no network dependency
- User/Group: `seer:seer`
- Logging: journald identifier `seer-hotswap`
- Restart policy: `Restart=always`, with backoff (e.g., 2s, 5s, 10s)
- Security hardening:
  - `NoNewPrivileges=yes`
  - `ProtectSystem=full`
  - `ProtectHome=yes`
  - `PrivateTmp=yes`
  - `ReadWritePaths=/opt/seer/var /var/seer /var/log/seer /mnt /media`
  - Limit privileges to what’s required for file IO (no network caps)

# Req 5 — Integrity: checksums/manifests & logging conventions

## Purpose
Guarantee file-level integrity for PCAP exports and standardize logs so operators and parsers can trust provenance, detect corruption, and audit actions.

## Scope
- Applies to **PCAPs** handled by the Mover (Req 3) and Hot-swap Export (Req 4).
- Provides shared helpers for future use by the Shipper (Req 7).
- Defines **manifest** format, **verification** workflow, and **logging** conventions.
- All operations run as `seer:seer` and use atomic file semantics.

## Artifacts & Formats

### 1) MANIFEST.txt (per destination subfolder)
**Location**
- On external drive, alongside exported files: `pcap/YYYYmmdd/MANIFEST.txt`.
- (Optional) Local staging manifest under `dest_dir/YYYYmmdd/`.

**Format** — one line per file:  
`sha256  size_bytes  relative/path`

**Example**
    9c1f…a7  10485760  SEER-20251012-143000.pcap
    1b54…2e   5242880  SEER-20251012-143020.pcap

**Write semantics**
- Build `MANIFEST.txt.tmp`, `fsync`, then `rename()` to `MANIFEST.txt`.

### 2) TRANSFER.LOG (append-only, external drive root)
**Purpose**
- Human-readable receipt of every export attempt.

**Line format** (space-delimited key=value)
- `ts=2025-10-12T14:30:25Z host=seer-sensor-01 action=export src=/opt/seer/var/queue/SEER-20251012-143000.pcap dst=/mnt/SEER_EXT/pcap/20251012/SEER-20251012-143000.pcap bytes=10485760 sha256=9c1f…a7 result=OK batch=pcap-20251012 sensor_id=SEER01`

**Result codes**
- `OK | VERIFY_FAIL | IO_ERROR | SKIP_ACTIVE | SKIP_EXISTS`

**Rotation**
- Start a new file per day or when >50 MB.

### 3) Local integrity state (for monitor)
**File**
- `/var/log/seer/integrity.state` (atomic JSON)

**Shape**
- `{"manifests_written":<int>,"verify_ok":<int>,"verify_fail":<int>,"last_verify_ts":<epoch>,"last_manifest_ts":<epoch>}`

## Integrity Workflow

### A) Mover (Req 3)
1. Select oldest safe PCAP.
2. **Cross-filesystem transfer**:
   - Copy to `filename.part` while streaming `sha256`; `fsync`.
   - Independently compute source `sha256`; compare.
   - On match: `rename(filename.part → filename)`; delete source.
   - On mismatch: delete `.part`, keep source; log `result=VERIFY_FAIL`.
3. **Same filesystem**: use atomic `rename()`; optional deferred hash at export stage.
4. Update `mover_log` and, if used, local `MANIFEST.txt`.

### B) Hot-swap Export (Req 4)
1. For each eligible PCAP, perform verify-on-copy if cross-FS.
2. Append/merge entry in `pcap/YYYYmmdd/MANIFEST.txt`.
3. Append one line to `TRANSFER.LOG`.
4. Update `integrity.state` counters.

**Never delete a source on cross-FS transfer until checksum verify passes.**

## Logging Conventions

**Journald identifiers**
- `seer-capture`, `seer-zeek`, `seer-mover`, `seer-hotswap`, `seer-integrity`, `seer-monitor`, `seer-status`, `seer-shipper` (later).

**Style**
- Structured single-line `key=value` pairs.
- Required keys (when applicable): `ts`, `host`, `action`, `src`, `dst`, `bytes`, `sha256` (short allowed in logs), `result`, `sensor_id`, `batch`.

**Levels**
- INFO: routine moves/exports, manifest writes.
- WARNING: soft disk threshold, skipped active file.
- ERROR: verify failed, I/O error, unwritable path.
- CRITICAL: invalid configuration, cannot proceed.

**Time**
- All integrity/export timestamps are **UTC** ISO-8601 with `Z`.

## Configuration (seer.yml)
- `integrity.enable: true`
- `integrity.hash_algo: sha256`
- `integrity.manifest_max_size_mb: 50`
- `integrity.sensor_id: SEER01`  (operator-set; included in logs)
- `integrity.batch_prefix: pcap`  (e.g., `pcap-YYYYmmdd`)

## Interactions & Contracts
- Req 3/4 must call integrity helpers for hashing and manifest writes.
- Req 8 (Monitoring) reads `integrity.state` and displays counters.
- Req 7 (Shipper, later) reuses the hash helper for optional JSON checksums.
- Req 9 (Installer) deploys helper libs and validates journald identifiers.

## Validation Rules
- `MANIFEST.txt` is written atomically (tmp → fsync → rename).
- `TRANSFER.LOG` appends are atomic per line.
- On verify failure: destination temp removed, source retained, ERROR logged with `result=VERIFY_FAIL`.
- Hash algorithm is **sha256** only.
- Timestamps are UTC.

## Acceptance Criteria
- Every exported file has a correct `MANIFEST.txt` entry (sha256 + size).
- Cross-device copies never delete the source on checksum mismatch.
- `TRANSFER.LOG` contains one line per attempted export with accurate result.
- `integrity.state` counters reflect activity and are consumable by the monitor.
- Monitoring surfaces `verify_ok` and `verify_fail` without blocking other components.

## Non-Functional
- Streamed hashing (low memory footprint).
- CPU overhead bounded by disk throughput.
- Power-safe due to atomic rename pattern and verify-before-delete.

## Configuration Contract
- Reads all paths and export settings from the YAML (Requirement 0).
- Fails fast (and logs a clear error) if required staging directories are missing or unwritable, but keeps retrying on a healthy cadence after operator remediation.

## Observability
- Journald lines include: `action=export src=… dst=… bytes=… sha256=<short> result=…`
- Optionally maintain a small state file at `/var/log/seer/export.state` for the TUI/API to read.

# Req 6 — Agent Tracker (environment heartbeat & inventory)

## Purpose
Maintain a lightweight, local inventory of deployed agents and a live **count of agents reporting**, so the monitor can display fleet health even in air-gapped deployments.

## Scope
- Receive agent heartbeats over **UDP** on the OT side (no inbound TCP).
- Track last-seen timestamps and minimal metadata per agent.
- Expire agents that stop reporting (configurable timeout).
- Publish an atomic state file for the Monitor (Req 8).
- Runs as `seer:seer`, offline, no external dependencies.

## Heartbeat Protocol (wire format)
- Transport: UDP (default port `5515`, configurable).
- Payload: newline-delimited JSON (one heartbeat per datagram).
- Required fields:
  - `agent_id` (string; stable ID/UUID/hostname)
  - `site` (string; e.g., OT-1) — optional
  - `version` (string)
  - `ip` (string; agent’s self-reported IP; receiver also records source IP)
  - `ts` (sender’s epoch seconds)

**Example heartbeat**
```
{"agent_id":"OT-PLC-01","site":"OT-1","version":"1.4.2","ip":"192.168.10.55","ts":1734036122}
```

## Behavior
1) Listen on `<bind_addr>:<port>` (default `0.0.0.0:5515`).  
2) Validate & normalize JSON; discard malformed entries (rate-limited warnings).  
3) Record/update in an in-memory index and an on-disk registry:
   - Keep: `first_seen`, `last_seen`, `agent_id`, `site`, `version`, `ip_src`, `ip_claimed`, `hb_count`.
4) Expire agents whose `last_seen` is older than `agent_timeout_sec` (default **300s**).
5) Persist registry periodically (e.g., every 5s or N updates) using temp + fsync + atomic rename.
6) Publish monitor state after each write.
7) Maintain rolling counters: total heartbeats, invalid/dropped, active agents.

## Configuration (seer.yml)
```
agent_tracker:
  enable: true
  udp_bind_addr: "0.0.0.0"
  udp_port: 5515
  agent_timeout_sec: 300      # consider "offline" if no heartbeat within 5 min
  persist_interval_sec: 5
  max_registry_size: 10000    # safety cap on unique agents
```

## Outputs (atomic files for Monitor)
- **/var/log/seer/agents.state**
  - Shape:
    ```
    {
      "agent_count": <int>,                  // active (not expired)
      "last_heartbeat_ts": <epoch>,          // most recent receive time
      "by_site": {"OT-1": N1, "OT-2": N2},   // optional site breakdown
      "counters": {
        "total_heartbeats": <int>,
        "invalid_messages": <int>,
        "expired": <int>
      }
    }
    ```

- **/var/log/seer/agents.registry.json**
  - Per-agent entries:
    ```
    {
      "agent_id": "OT-PLC-01",
      "site": "OT-1",
      "version": "1.4.2",
      "ip_src": "192.168.10.55",
      "ip_claimed": "192.168.10.55",
      "first_seen": <epoch>,
      "last_seen": <epoch>,
      "hb_count": <int>,
      "status": "active|expired"
    }
    ```

> All writes use temp file → fsync → atomic rename to avoid partial reads.

## Logging (journald identifier: seer-agents)
- INFO: `hb_received agent_id=… site=… ip_src=…`
- WARNING: `hb_invalid reason=…`
- INFO: `agent_expired agent_id=… last_seen=…`
- ERROR: I/O or JSON parsing errors (rate-limited)

## Security & Hardening
- Runs as `seer:seer`; no elevated caps.
- UDP listener is local network only; no internet connectivity.
- Optional allowlist (future): restrict by source subnet(s).

## Interactions & Contracts
- **Monitor (Req 8)** reads `agents.state` to show:
  - `AGENTS: <agent_count> reporting, last_heartbeat=<ago>` (+ optional by-site lines).
- **Shipper (Req 7, later)**: independent; no coupling.
- **Installer (Req 9)**: deploys unit and ensures `/var/log/seer` exists.

## Validation Rules
- `agent_id` non-empty string ≤ 128 chars.
- Reject payloads > 4 KB.
- `agent_timeout_sec` in [60, 86400]; default 300.
- Registry never exceeds `max_registry_size` (drop oldest expired first).

## Acceptance Criteria
- With two agents sending 30-second heartbeats, `agents.state.agent_count == 2` and updates within one refresh cycle.
- After `agent_timeout_sec` without heartbeats, expired agents drop from `agent_count`.
- `agents.registry.json` reflects accurate `first_seen/last_seen/hb_count` per agent.
- Monitor displays correct count and last heartbeat age.

## Service Definition (Req 6a)
- Name: `seer-agents.service` (Type=simple, long-running).
- Ordering: `After=local-fs.target`.
- User/Group: `seer:seer`.
- Restart: `Restart=always` with backoff (2s → 5s → 10s).
- Hardening: `NoNewPrivileges=yes`, `ProtectSystem=full`, `ProtectHome=yes`, `PrivateTmp=yes`, `ReadWritePaths=/var/log/seer`.

## Service-level acceptance

- systemctl status seer-agents shows active (running) and listening on the configured UDP port.
- On receiving valid heartbeats, agents.state and agents.registry.json update atomically.
- Malformed heartbeats log warnings without crashing or blocking the service

# Req 7 — JSON & Agent Logs Shipper (UDP over GHOST to RAMPART)

## Purpose
Reliably transmit Zeek JSON and agent/service logs **one-way via UDP** across the GHOST diode to RAMPART, without acknowledgments, while preventing local buildup and avoiding interference with PCAP workflows.

## Scope
- **Inputs:** Zeek JSON (`json_spool`) and optional agent/service logs directory.
- **Output:** UDP datagrams to RAMPART ingest on the IT/RX side.
- **Excludes:** PCAP files (handled only by external-drive export).
- Runs as user `seer`; no inbound connectivity required.

## Behavior

### 1) File eligibility
- A JSON/log file is “stable/ready” when its size is unchanged across two polls (e.g., 2 seconds apart).
- Never send files still being written.

### 2) Framing & transmission
- Default: line-delimited JSON; send **each line** as one UDP datagram.
- Optional: **per-file gzip**, then ship framed chunks with a minimal header containing `sensor_id`, `file_id`, `seq`, and `total`.
- Respect MTU; use a safe max UDP payload (e.g., 1200 bytes) when chunking.

### 3) Ordering & metadata
- Best-effort ordering only (UDP).
- Include lightweight headers per datagram: `sensor_id`, `file_id`, `seq` (and `total` when compressed).

### 4) Rate limiting & backoff
- Enforce `max_bytes_per_sec` via a token-bucket.
- On send errors (e.g., buffer full), apply exponential backoff and requeue unsent chunks.

### 5) File lifecycle
- After a successful **full** send of a file:
  - **Default:** move file to `json_spool/sent/` and create a small sidecar marker recording last-send timestamp and byte count.
  - **Option:** delete after send (`retention: delete_after_send`).
- On failure/partial: keep file; retry next cycle.

### 6) Resilience
- Power-safe: derive state from filesystem (presence in `sent/` and `.sent` markers).
- If RAMPART is unreachable, queue depth grows locally; shipper retries at a capped rate without blocking other components.

## Configuration (seer.yml keys)
- `shipper.enable`: true/false
- `shipper.udp_target_host`: IP or hostname of RAMPART ingest
- `shipper.udp_target_port`: integer
- `shipper.poll_interval_sec`: float (default 1.0)
- `shipper.max_bytes_per_sec`: integer (e.g., 250000 default)
- `shipper.compress`: boolean (default false)
- `shipper.json_spool`: path (default `/var/seer/json_spool`)
- `shipper.extra_logs_dir`: optional path for agent/service logs
- `shipper.retention`: `move_to_sent` (default) | `delete_after_send`
- `sensor_id`: string identifier included in headers/markers

## Outputs (for Monitor)
- `/var/log/seer/shipper.state` (atomic JSON):
  - `udp_target` (host:port), `queue_depth`, `bytes_sent_1m`, `send_errors_1m`, `backoff_level`, `last_sent_ts`
- Optional per-file sidecar in `sent/`: `<filename>.sent` with `sent_ts`, `bytes`, `lines`, `compress=true|false`, optional `hash`.

## Logging (journald identifier: `seer-shipper`)
- INFO: `file_start path=… size=… mode=json|gzip`
- INFO: `file_done path=… lines=… bytes=… duration_ms=…`
- WARNING: `send_error errno=… backoff=…`
- ERROR: `open_failed|read_failed|stats_failed path=… reason=…`

## Security & hardening
- Runs as `seer`; no elevated capabilities.
- **Outbound UDP only**; no listener sockets.
- Prefer static IP for `udp_target_host` to avoid DNS dependency; optional allowlist.

## Interactions & contracts
- **Monitoring (Req 8):** reads `shipper.state` to show `q=<depth>`, `rate=<bytes/min>`, `errors`, `backoff`, `last` sent age.
- **Agent Tracker (Req 6):** independent; may also ship tracker logs if `extra_logs_dir` is configured.
- **Integrity (Req 5):** may compute per-file sha256 and store in the `.sent` marker (optional).
- **Installer (Req 9):** deploys unit and ensures `json_spool` and `sent/` exist.

## Validation rules
- Only **stable** files are transmitted.
- `max_bytes_per_sec` enforced within ±10%.
- Compressed-mode chunking respects max datagram size and includes sequence metadata.
- When RAMPART is unreachable, the shipper does not crash; queue depth grows while rate is bounded by backoff.

## Acceptance criteria
- Under normal conditions, the shipper drains `json_spool` continuously; queue depth stays near zero.
- During outages, files accumulate; upon recovery, backlog drains without exceeding rate limits.
- Monitor shows target, queue depth, bytes/min, error count, and backoff level.
- **PCAP files are never touched** by the shipper.

## Non-functional
- Low CPU/memory footprint; I/O-bound on file reads.
- No external libraries beyond stdlib (if feasible).
- Deterministic across restarts using filesystem state only.

# Req 8 — Monitoring: TUI Console & Status API

## Purpose
Provide a live terminal dashboard (TUI) and a local JSON Status API summarizing SEER state:
- Capture & Zeek health
- Ring/Queue/Backlog counts and disk usage
- **Current PCAP destination (which drive/mount)**
- **Number of agents reporting**
- Export activity and integrity counters
- Shipper queue/throughput (when enabled)

## Scope
- Read-only aggregation; no control-plane actions.
- Works offline; minimal dependencies.
- Two consumers:
  - TUI: full-screen, flicker-free, refresh every `refresh_interval` (default 0.5s).
  - Status API: HTTP `GET 127.0.0.1:8088/status` returns unified JSON.

## Inputs (seer.yml)
- `refresh_interval` (float, default 0.5)
- Paths: `ring_dir`, `dest_dir`, `backlog_dir`
- Optional UI: `ui.colors` (bool), `ui.show_site_breakdown` (bool)

## Data Contracts (producers → monitor; all files written atomically)
- `/var/log/seer/capture.state`
  - service, status, iface, snaplen, rotate_seconds, last_file, last_roll_ts
- `/var/log/seer/zeek.state`
  - service, status, workers, fanout_id, last_log_ts, drops_pct
- `/var/log/seer/mover.state`
  - buffer_threshold, ring_count, moved_export, moved_queue, moved_backlog, skipped_active, errors, last_action_ts
- `/var/log/seer/export.state`
  - active_target { mount, label, fs, free_pct }, bytes_exported_1h, files_exported_1h, last_export_ts, status
- `/var/log/seer/agents.state`
  - agent_count, last_heartbeat_ts, by_site { ... }, counters { total_heartbeats, invalid_messages, expired }
- `/var/log/seer/integrity.state` (optional)
  - manifests_written, verify_ok, verify_fail, last_verify_ts
- `/var/log/seer/shipper.state` (when enabled)
  - udp_target, queue_depth, bytes_sent_1m, send_errors_1m, backoff_level, last_sent_ts

## TUI Layout
Top bar (health):
- `CAPTURE: <status> iface=<iface> roll=<sec> last_roll=<ago>   ZEEK: <status> workers=<n> drops=<pct>%`

Middle left (storage):
- `RING: <count> files  FS Used: <used%>`
- `QUEUE: <count>   BACKLOG: <count>`

Middle right (export & agents):
- `PCAP DEST: <mode>` where:
  - `export:<label>@<mount>` if an active export target exists
  - else `queue` if queue has items
  - else `backlog` if backlog has items
  - else `ring`
- `EXPORT: <status> target=<label>@<mount> free=<free_pct>% bytes_1h=<num> files_1h=<num> last=<ago>`
- `AGENTS: <agent_count> reporting  last_heartbeat=<ago>` (+ by-site lines if enabled)

Bottom bar (shipper, when enabled):
- `SHIPPER: udp=<host:port> q=<depth> rate=<bytes/min> errors=<n> backoff=<lvl> last=<ago>`

Footer:
- `Input: (q=quit, r=refresh, ?=help)`

## Status API (GET /status)
Response body (omit sections that are missing/unknown):
- `sensor` { hostname, version, ts }
- `capture` { ... }
- `zeek` { ... }
- `ring` { dir, count, bytes, fs_used_pct }
- `queues` { dest_dir { path, count, bytes }, backlog_dir { path, count, bytes } }
- `export` { ... }
- `agents` { agent_count, last_heartbeat_ts, by_site { ... } }
- `integrity` { ... }
- `shipper` { ... }

## Drive/Mount Detection Logic (for “PCAP DEST”)
- If `export.state.active_target` present → show `export:<label>@<mount>`.
- Else if `queues.dest_dir.count > 0` → `queue`.
- Else if `queues.backlog_dir.count > 0` → `backlog`.
- Else → `ring`.

## Reliability & Performance
- Atomic reads of state files; tolerate missing files (display `unknown`).
- No blocking on producers; use non-blocking file IO and short timeouts.
- CPU target < 3% on small-form hardware.

## Security
- Runs as `seer:seer`; no elevated privileges.
- API binds only to `127.0.0.1:8088`.

## Validation Rules
- Missing or malformed state files must not crash the TUI/API.
- All timestamps rendered as humanized “ago” and raw epoch available in API.
- Filesystem usage for `ring_dir` sampled each refresh; must not block UI.

## Acceptance Criteria
- TUI refreshes smoothly at configured interval with no flicker.
- When an external drive is active, `PCAP DEST` shows `export:<label>@<mount>` within one refresh cycle.
- Agent count and last heartbeat reflect `agents.state` accurately.
- Status API returns 200 with well-formed JSON and includes available sections.

# Req 9 — Installer & sysctl / Kernel Tuning (deploy everything last)

## Purpose
Provide a reliable, idempotent installer that provisions the SEER runtime, deploys all systemd units, applies kernel tuning, sets ownership/permissions, and (optionally) enables services — using values from `/opt/seer/etc/seer.yml`.

## Scope
- User/group creation
- Directory creation and permissions
- File deployment (bins/configs/units)
- `systemd` daemon-reload, enable/start (optional)
- Kernel `sysctl` tuning
- Environment validation
- Dry-run mode and backups

## Inputs
- Config: `/opt/seer/etc/seer.yml` (from Req 0)
- Flags: `--dry-run`, `--no-enable`, `--yes` (non-interactive), `--interface <dev>` (override)
- Required tools: `systemctl`, `sysctl`, `tcpdump`, `sha256sum`, `zeek` (optional to enable)
- Paths (from YAML): `ring_dir`, `dest_dir`, `backlog_dir`, `json_spool`, logs, etc.

## Operations
1) **User/Group**
   - Ensure `seer:seer` exists (locked shell, minimal home `/var/lib/seer` or none).

2) **Directories (create if missing)**
   - `/opt/seer/bin` (0755), `/opt/seer/etc` (0755)
   - `/opt/seer/var/queue` (0750), `/opt/seer/var/backlog` (0750)
   - `/var/seer/pcap_ring` (0750), `/var/seer/json_spool` (0750)
   - `/var/log/seer` (0755)
   - Ownership for all above: `seer:seer`

3) **Deploy artifacts**
   - Copy Python tools → `/opt/seer/bin` (`seer:seer`, 0755)
   - Copy `seer.yml` → `/opt/seer/etc` (0644, `seer:seer`); back up existing as `seer.yml.bak-YYYYmmdd-HHMMSS`
   - Install systemd units → `/etc/systemd/system/`:
     - `seer-capture@.service` (Req 1a)
     - `seer-zeek@.service` (Req 2a)
     - `seer-move-oldest.service` & `seer-move-oldest.timer` (Req 3a)
     - `seer-hotswap.service` (Req 4a)
     - `seer-agents.service` (Req 6a)
     - (Optional) `seer-console.service`, `seer-status.service` (Req 8)
     - (Optional) `seer-shipper.service` (Req 7)
   - Never overwrite a locally modified unit without making a `.bak-YYYYmmdd-HHMMSS`

4) **Kernel tuning (`/etc/sysctl.d/99-seer.conf`)**
   - Set:
     - `net.core.rmem_max = 33554432`
     - `net.core.wmem_max = 33554432`
     - `net.core.netdev_max_backlog = 10000`
   - Apply with `sysctl --system` and record effective values.

5) **Validation**
   - Interface (from YAML or `--interface`) exists & non-loopback.
   - Binaries present: `tcpdump` (required), `zeek` (warn/skip enable if missing).
   - All runtime dirs writable by `seer:seer` and on local FS.
   - Free space on `ring_dir` FS ≥ 10% (warn if less).
   - Read/parse YAML successfully.

6) **Systemd integration**
   - `systemctl daemon-reload`
   - Unless `--no-enable`:
     - Enable: `seer-capture@<iface>`, `seer-zeek@<iface>` (if Zeek present), `seer-move-oldest.timer`, `seer-hotswap.service`, `seer-agents.service`
     - (Optional) Enable: `seer-status.service`, `seer-console.service`, `seer-shipper.service` (if configured)
   - Start now unless `--no-enable` set; print exact start commands otherwise.

7) **Post-install report**
   - Summarize created/updated paths, owners, modes.
   - List enabled/disabled units and their current status.
   - Show quick commands:
     - `systemctl status 'seer-*'`
     - `journalctl -u seer-mover -u seer-hotswap -u seer-agents --since -1h`
     - `ls -lh /var/seer/pcap_ring /opt/seer/var/queue /opt/seer/var/backlog`

## Security & Hardening
- All services run as `seer:seer`.
- Units include `NoNewPrivileges`, `ProtectSystem=full`, `ProtectHome=yes`, `PrivateTmp=yes`, and minimal `ReadWritePaths`.
- No persistent root-owned files in runtime paths.

## Idempotency & Safety
- Re-running yields the same end state; no duplicates.
- Back up modified files before overwrite.
- `--dry-run` prints actions and diffs without writing.
- Never delete data in `ring_dir`, `dest_dir`, `backlog_dir`, or `json_spool`.

## Observability
- Append a line to `/var/log/seer/setup.log` with timestamp, user, version/revision, and actions taken.
- Echo concise remediation hints for each failed check.

## Validation Rules
- YAML must parse; missing critical keys abort with a clear message.
- `systemctl daemon-reload` must succeed.
- If enabling units, each `systemctl enable` returns success (or is skipped with rationale).
- `sysctl` values are active after install.

## Acceptance Criteria
- `seer` user exists; all runtime dirs present with correct perms/owners.
- `/etc/sysctl.d/99-seer.conf` exists and is applied.
- Units installed; enabled/started per flags.
- `systemctl status` shows active or a clear, actionable error for each enabled unit.
- No permission errors in first-run logs.

## Edge Cases
- Zeek missing: skip enabling `seer-zeek@.service`, warn, continue.
- Read-only `/etc` or `/usr`: abort with remediation instructions.
- Conflicting unit names pre-exist: back up and replace, report change.
- Multi-NIC hosts: `--interface` overrides YAML for enable/start only; YAML remains the source of truth.

## Non-Functional
- Offline-capable; no network required.
- Minimal dependencies (coreutils, systemd, sysctl).
- Clear, copy-pasteable remediation guidance for common failures.


