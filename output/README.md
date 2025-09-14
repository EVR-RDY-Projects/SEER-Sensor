# SEER Sensor – Output Directory

This folder is reserved for **data output definitions**.  
SEER’s core purpose is to take in network + host telemetry, normalize it, and then **emit JSON events over UDP**.

---

## Planned Contents

- **udp/**  
  Placeholder for configuration and notes on UDP forwarding.  
  - `targets.d/` → directory for target definitions (e.g., lab collector, Chronicle, Splunk, custom).  
  - `README.md` → guidance on expected JSON framing and transport details.  

---

## Purpose

- Define **where** SEER sends events (host + port).  
- Define **how** SEER sends events (batching, retries, framing).  
- Keep all outbound transport details in one place, separate from ingestion and normalization.  

---

⚠️ **Note:** Current focus is strictly **UDP JSON output**, but this structure leaves room to add other transports later if needed.
