# SEER Sensor – Tests Directory

This folder is reserved for **validation and testing** of the SEER Sensor.  
Tests ensure that ingestion, normalization, and UDP output behave as expected.

---

## Planned Subfolders

- **integration/**  
  Placeholder for end-to-end tests.  
  - Example: replay a sample PCAP → verify normalized JSON is produced → check it is sent to UDP target.  
  - Example: ingest host JSON → verify it maps correctly into the schema.

- **perf/**  
  Placeholder for performance and throughput benchmarks.  
  - Example: measure sustained packet capture at 100 Mbps / 1 Gbps.  
  - Example: measure JSON output rate and UDP reliability under load.

---

## Purpose

- Validate that SEER produces the **correct output** for known inputs.  
- Document performance limits on different hardware.  
- Provide sample datasets (PCAPs, host logs, golden outputs) for regression testing.  

---

⚠️ **Note:** This directory will likely contain **sample data** (e.g., small PCAPs, JSON logs) for testing.  
Runtime artifacts and large captures should be **gitignored** and stored separately.
