# SEER Sensor – Software Overview

This folder contains all of the **software components** of the SEER Sensor.  
SEER’s core purpose is simple: **ingest network + host telemetry, normalize it, and output JSON events over UDP**.

---

## Subfolders

- **config/**  
  Master configuration files. Defines:
  - Sensor identity (site ID, sensor ID).
  - Input sources (network + host).
  - Normalization mappings.
  - Output targets (UDP collectors).

- **ingest/**  
  Handles raw data ingestion.  
  - `network/` → SPAN/TAP mirrored traffic (e.g., Zeek, Suricata).  
  - `host/` → endpoint telemetry (e.g., Sysmon, osquery, custom JSON).

- **normalize/**  
  Maps raw fields into a **unified JSON schema** so all outputs look the same.

- **output/**  
  Handles **where** data goes.  
  - Currently focused on UDP forwarding of normalized JSON.

- **buffers/**  
  Temporary storage during processing.  
  - Logs, PCAPs, and retry queues.

- **provision/**  
  Scripts and unit files for setting up a sensor.  
  - USB seed config.  
  - Bootstrap script.  
  - Systemd service files.

- **deploy/**  
  Packaging and deployment.  
  - Container builds (Docker/Podman).  
  - System packages (`.deb`).  

- **seerctl/**  
  Planned lightweight operator CLI (`seerctl`) for status, start/stop, and replay testing.

- **tests/**  
  Validation and performance testing.  
  - Integration tests with PCAPs and host logs.  
  - Performance benchmarks.

- **docs/**  
  Developer and operator documentation.  
  - Architecture, schema reference, networking notes, hardware performance.

---

## Purpose

This folder represents the **software pipeline** of SEER:  
`ingest → normalize → output (UDP)`  

By keeping software separate from `hardware/`, contributors can work independently on:  
- Improving data collection and normalization (software).  
- Testing and validating builds (hardware).  

---

⚠️ **Note:** Much of this structure is placeholder. Components will be filled in as the Proof of Concept (POC) matures.
