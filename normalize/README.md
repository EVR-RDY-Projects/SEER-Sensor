# SEER Sensor – Normalize Directory

This folder is reserved for **normalization rules**.  
Normalization means taking raw fields from different sources and mapping them into a **unified JSON schema** that SEER can output consistently.

---

## Planned Contents

- **schema/**  
  Placeholder for JSON schema definitions that describe the “canonical” SEER event format.  
  - Example: `network.json` for packet events, `host.json` for endpoint events.  

- **mappings.yaml**  
  Placeholder for field mapping rules.  
  - Maps raw fields from Zeek, Suricata, Sysmon, osquery, or custom agents → into the SEER schema fields.  
  - Example: `id.orig_h` (Zeek) → `src_ip` (SEER).

---

## Purpose

- Ensure all ingested data (network or host) is **output in a consistent JSON format**.  
- Provide a single “source of truth” schema so downstream systems (SIEMs, analytics tools) know what to expect.  

---

⚠️ **Note:** The exact schema and field mappings are **still being decided**.  
This directory is a placeholder until the event format is finalized.
