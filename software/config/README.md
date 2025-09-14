# SEER Sensor – Config Directory

This folder defines **all configuration for the SEER Sensor**.  
Think of it as the **“brain”**: what to listen to, how to normalize, and where to send data.

---

## Files & Subfolders

- **seer.yaml**  
  Master configuration file.  
  Contains sensor identity (site ID, sensor ID), global paths, and defaults.

- **inputs/**  
  Settings for incoming data sources.  
  - `network.yaml` → defines network capture settings (interface, snaplen, filters, output format).  
  - `host.yaml` → defines host telemetry ingestion (Sysmon, osquery, custom JSON agents).

- **normalize/**  
  Rules for mapping raw fields into a **unified JSON schema**.  
  - `mappings.yaml` → field name translations and normalization logic for network + host data.

- **outputs/**  
  Settings for outbound delivery of normalized JSON events.  
  - `udp.yaml` → list of UDP forwarding targets (host:port, batching, retries).

---

## Purpose

- **inputs/** = *what goes in*  
- **normalize/** = *how it’s shaped*  
- **outputs/** = *where it goes*  
- **seer.yaml** = *identity + defaults*  

All configuration is kept separate from code so sensors can be updated or tuned **without touching the core logic**.
