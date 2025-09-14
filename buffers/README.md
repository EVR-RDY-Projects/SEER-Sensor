# SEER Sensor – Buffers Directory

This folder is reserved for **temporary storage** used by the SEER Sensor.  
Buffers are like a **holding area**: data rests here before being normalized or forwarded.

---

## Planned Subfolders

- **logs/**  
  Placeholder for structured logs generated from network and host ingestion.  
  - Example: Zeek-style JSON logs.  
  - Not meant for long-term storage — just staging before forwarding.

- **pcap/**  
  Placeholder for rolling packet captures.  
  - Useful for forensics and troubleshooting.  
  - May be implemented with a ring buffer (fixed size, oldest files rotate out).

- **queue/**  
  Placeholder for retry queues if UDP forwarding fails.  
  - Events will be temporarily held here until they can be resent.  

---

## Purpose

- Provide resilience against network outages or collector downtime.  
- Allow hot-swappable PCAPs for investigations.  
- Keep ingestion and forwarding decoupled (don’t drop data if the pipeline stalls).  

---

⚠️ **Note:** These directories will normally be **gitignored** since they contain runtime data, not source code.
