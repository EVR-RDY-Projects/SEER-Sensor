# SEER Sensor



## 📖 Overview
The **SEER Sensor** is an open-source proof-of-concept (POC) project for OT/IT visibility.  
It is being actively developed and much of the functionality described here is **planned** but not yet implemented.  

SEER is designed to:  
- Capture mirrored traffic from SPAN/TAP ports  
- Generate structured logs (Zeek-style)  
- Ingest endpoint JSON telemetry (Sysmon, osquery, custom agents)  
- Provide hot-swappable PCAP storage for rapid forensic collection  
- Support low-cost hardware builds to simplify deployment in resource-constrained OT environments  


---

## 🚀 Features (current + planned)
- Passive capture of SPAN/TAP traffic *(planned)*  
- Structured metadata generation (Zeek, Suricata optional) *(planned)*  
- Endpoint JSON ingestion (Sysmon, osquery, etc.) *(planned)*  
- **Hot-swappable PCAP drive included in POC hardware** *(planned)*   
- Rolling PCAP capture with remote retrieval via Rampart *(planned)*  
- Hardware reference builds to reduce cost of deployment *(planned)*  
- Secure, one-way forwarding to upstream/cloud SIEMs (e.g., Chronicle) *(planned)*  

---

## 🛠️ Hardware (POC focus)
- Currently testing on commodity x86 mini-PC and ARM SBC platforms  
- **Dedicated storage bay for hot-swappable PCAP drives is working in the POC**  
- Reference Bill of Materials (BOM) for low-cost builds is in progress  
- Long-term goal: integration with **Rampart** (uplink/packager)  

---

## ⚙️ Software early dev

### Functional Summary
- **Continuous Capture:** Persistent ring buffer of PCAPs via `dumpcap` (or equivalent).
- **Inline Zeek Processing:** Nearline Zeek consumes rolling chunks, producing NDJSON spools.
- **Shipper:** UDP-based JSON shipper transmits to RAMPART through the data diode with redundancy and sequencing.
- **Backfill Archive:** Hot-swappable SATA drives serve as authoritative long-term PCAP storage for forensic recall and re-ingest.

---

## Storage Architecture

| Layer | Path | Description | Notes |
|-------|------|-------------|-------|
| **Local (internal SSD/NVMe)** | `/var/seer/pcap_ring/` | Rolling PCAP capture ring (24–72h) | Non-stop writer |
|  | `/var/seer/json_spool/` | Zeek NDJSON output | Read by UDP shipper |
|  | `/var/seer/meta/` | Mode & manifest state | Persistent metadata |
| **External (hot-swap SATA)** | `/mnt/seer_hot/` | Auto-mount root | ext4/xfs, noatime |
|  | `/mnt/seer_hot/pcap_archive/` | Archived PCAPs | Long-term |
|  | `/mnt/seer_hot/meta/` | Drive-specific manifests | SHA256 + UUID |

---

## Button Interface Specification

| Press Type | Duration | Function | Behavior |
|-------------|-----------|-----------|-----------|
| **Short** | ≤ 1 s | “Transfer Now” | Rotate current chunk(s) and enqueue mover job(s). Continues live capture. |
| **Long** | ≥ 3 s | “Prepare for Removal” | Rotate, flush, drain mover, write manifest, unmount drive, LED steady green (safe). |
| **Double** | 2 × short within 1 s | “Switch Archive Target” | Toggle preferred archive (external ↔ local). Persist in `/var/seer/meta/mode.json`. |

> Debounce in hardware or userspace; ignore input during `PREP_REMOVE`.

---

## State Machine

### States
`NO_DRIVE → DRIVE_MOUNTED → ARCHIVING → PREP_REMOVE → SAFE_TO_REMOVE → NO_DRIVE`

### Transitions
| Event | From → To | Action |
|--------|------------|--------|
| Drive insert | `NO_DRIVE → DRIVE_MOUNTED` | Auto-mount, FS check, verify `.seer_drive` marker. |
| Healthy check | `DRIVE_MOUNTED → ARCHIVING` | Begin mover operations to archive. |
| Short press | any (except `PREP_REMOVE`) | Rotate current chunk(s), enqueue copy jobs. |
| Long press | `ARCHIVING → PREP_REMOVE` | Flush buffers, write manifest, unmount, set LED = green. |
| Drive removal | `SAFE_TO_REMOVE → NO_DRIVE` | Archive to local until new drive present. |
| New drive insertion | `NO_DRIVE → DRIVE_MOUNTED` | Auto-copy unarchived local backlog first. |

---

## “Never Drop Coverage” Guarantee

- Capture writer **never halts**; only rotates current PCAP chunk.
- Mover operates only on **closed chunks**.
- Throttled I/O via `nice/ionice` to avoid contention.
- Automatic fallback to local archive if external unavailable or full.
- Backpressure and alerting ensure continuity.

---

## File & Manifest Format

**Chunk naming:**  
`pcap_<sensor>_<YYYYMMDD>_<HHMMSS>_<seq>.pcap`

**Metadata sidecar:**  
`pcap_<...>.json` → `{ ts_first, ts_last, packets, bytes, sha256 }`

**Daily manifest (NDJSON):**  
`manifest-YYYYMMDD.jsonl` — list of all chunks + checksums.

**Daily summary hash:**  
`manifest-YYYYMMDD.sha256`

---

## LED / Feedback Logic

| LED State | Meaning |
|------------|----------|
| **Blue (blinking)** | Archiving/mover active |
| **Green (steady)** | Safe to remove |
| **Amber (steady)** | External missing/full or FS error |
| **Red (blinking)** | Integrity or disk I/O failure |

---

## Failure & Edge Handling

| Scenario | Response |
|-----------|-----------|
| Power loss mid-transfer | Resume pending copies on boot; verify checksums. |
| Drive full | Fallback to local; alert; backfill upon new drive. |
| Bad FS | Mount read-only or ignore; continue local archive. |
| Button spam | Debounced; ignored during `PREP_REMOVE`. |
| Emergency pull | FS check on next insert; resume after journal replay. |

---

## Zeek & Shipper Interaction

- Zeek continuously consumes PCAPs from `/var/seer/pcap_ring/`.
- JSON spool unaffected by archive events.
- Optionally trigger NDJSON rotation on long press for alignment with PCAP cutoff.

---

## Security & Provenance

- `.seer_drive` marker with UUID & owner metadata.
- Mount permissions: `uid=seer,gid=seer,umask=007`.
- Optional **signing** of manifests with device key.
- Optional **LUKS encryption** unlocked via TPM or token.

---

## Retention & Capacity Targets

| Layer | Retention | Notes |
|--------|------------|-------|
| PCAP ring | 24–72 h | Based on traffic throughput |
| External archive | N days/weeks | Low-watermark alert @ 80 % |
| Local backstop | 48–72 h | Buffer until next swap |

---

## Monitoring & Telemetry

- Metrics: queue depth, throughput, free space, last transfer time, errors.
- Syslog + JSON events for all state transitions.
- Watchdog restarts mover if stalled > N minutes.

---

## Acceptance Tests

1. **Hot-swap continuity:** Verify zero packet loss across insert/remove cycles.  
2. **Power loss recovery:** Resume transfers and validate integrity.  
3. **Drive-full fallback:** Automatic local archive & later backfill.  
4. **Button debounce:** No duplicate or skipped events.  
5. **Checksum validation:** Source = Target; manifests match totals.

---

## Operator Playbooks

### Normal Swap
1. (Optional) Short press → rotate chunks.  
2. Long press → wait for **green LED**.  
3. Remove drive.  
4. Insert new drive → auto-mount, copy backlog → resume blue blinking.

### Emergency Pull
If drive removed without long press:
- Log warning, perform FS check on next insert.
- Resume safely post-journal replay.

---

## Future Extensions

- State-machine YAML spec for automated testing.  
- GPIO pin map for button & LEDs.  
- Adaptive rotation sizes (based on Mbps & disk size).  
- Optional drive encryption