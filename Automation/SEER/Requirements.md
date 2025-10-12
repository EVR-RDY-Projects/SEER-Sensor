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
