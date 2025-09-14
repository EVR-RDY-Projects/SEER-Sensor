# SEER Sensor – Ingest Directory

This folder is reserved for **data ingestion sources**.  
SEER will ultimately support two main types of input:

---

## Planned Subfolders

- **network/**  
  Placeholder for SPAN/TAP mirrored traffic ingestion.  
  - Final toolset not yet decided (Zeek, Suricata, or similar).  
  - Will handle raw packet capture and conversion into structured events.

- **host/**  
  Placeholder for endpoint / host telemetry ingestion.  
  - Format and tools are still being evaluated.  
  - Could include Sysmon, osquery, OT-specific agents, or a custom JSON emitter.  

---

## Purpose

This directory is where raw inputs will land before being normalized and forwarded.  
Right now, it exists as a **staging area** until ingestion methods are finalized.
