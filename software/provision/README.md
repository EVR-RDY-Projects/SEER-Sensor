# SEER Sensor – Provision Directory

This folder is reserved for **setup and bootstrap** of the SEER Sensor.  
Provisioning makes it possible to install, configure, and start the sensor with minimal steps.

---

## Planned Contents

- **usb-seed/**  
  Placeholder for USB “seed” files used to configure a sensor offline.  
  - Example: `seer.env` for site/sensor IDs and interface settings.  
  - Example: `seer.yaml` for local overrides.  
  - Example: `authorized_ops.pub` for operator SSH keys.

- **bootstrap.sh**  
  Placeholder for a script that reads the USB seed (or defaults) and prepares the system.  
  - Creates directories, applies configs, and enables services.  

- **systemd/**  
  Placeholder for Linux service unit files to ensure SEER starts automatically.  
  - Example: `seer-zeek.service` for packet capture.  
  - Example: `seer-vector.service` for JSON forwarding.  
  - Example: `seer-dumpcap.service` for PCAP rotation.  

---

## Purpose

- Enable **zero-touch setup** for new sensors (especially in OT environments).  
- Support **offline provisioning** using a USB stick (no internet required).  
- Ensure services start automatically and consistently on boot.  

---

⚠️ **Note:** Provisioning details are still being designed — this directory is a **placeholder** until bootstrap and service management are finalized.
