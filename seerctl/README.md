# SEER Sensor – seerctl Directory

This folder is reserved for a lightweight **operator command-line tool (CLI)** called `seerctl`.  
The goal of this tool is to provide a simple way to check status, run local tests, or manage the SEER Sensor without needing to remember long commands.

---

## Planned Contents

- **__main__.py**  
  Entry point for the CLI. Allows `python -m seerctl` or a packaged binary.

- **cli.py**  
  Placeholder for command definitions (e.g., `status`, `start`, `stop`, `replay`).

- **utils.py**  
  Placeholder for helper functions (e.g., reading config, checking services, formatting output).

---

## Example Future Commands

- `seerctl status` → Show current site ID, sensor ID, and running processes.  
- `seerctl start` → Start capture + forwarding pipeline.  
- `seerctl stop` → Stop all SEER services.  
- `seerctl replay <pcap>` → Test ingest and output using a sample PCAP.  

---

## Purpose

- Give operators a **single tool** to interact with SEER.  
- Reduce friction for testing and validation.  
- Provide consistent status output for troubleshooting.  

---

⚠️ **Note:** `seerctl` is optional at the Proof of Concept stage.  
This directory is a **placeholder** until CLI functionality is developed.
