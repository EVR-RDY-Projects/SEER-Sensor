# SEER Sensor Roadmap

This roadmap outlines the planned milestones and features for **SEER Sensor (POC)**.  
It follows the order of how the sensor will actually be built and tested:  
**hardware first, then software, then validation**.  

---

## 🚧 Current Status
- **Stage**: Proof of Concept (POC)  
- **Focus**: Building and validating a low-cost hardware platform that can run SEER software reliably.

---

## 📌 Milestones

### v0.1 — Hardware POC Setup
- [x] Create `hardware/POC/` folder structure.  
- [ ] Draft BOMs for candidate platforms (`hardware/POC/bom/`).  
- [ ] Assembly notes for each test build (`hardware/POC/assembly/`).  
- [ ] Initial throughput and stability testing:
  - Raspberry Pi 4 / 5  
  - Intel NUC / mini PC  
  - Low-power x86 fanless box  
- [ ] Document hot-swap drive setup (`hardware/POC/storage/`).  
- [ ] Record performance results (CPU, RAM, disk, packet loss) in `hardware/POC/benchmarks/`.  
- [ ] Define **minimum viable hardware spec** for software testing.  

---

### v0.2 — Core Software Pipeline
*(Runs on validated POC hardware)*  
- [ ] Create `software/` folder structure.  
- [ ] Basic Zeek integration: capture from SPAN/TAP and write logs locally (`software/ingest/network/`).  
- [ ] PCAP rotation & safe storage (`software/buffers/`).  
- [ ] Placeholder configs (`software/config/`).  
- [ ] Scripts to install/start/stop the pipeline (`software/provision/`).  
- [ ] Normalize logs into simple JSON schema (`software/normalize/`).  
- [ ] Emit JSON events over UDP (`software/output/`).  

---

### v0.3 — Endpoint Ingest (Host Telemetry)
- [ ] Add support for ingesting host JSON logs (e.g., Sysmon, osquery) (`software/ingest/host/`).  
- [ ] Configurable inputs (`software/config/inputs/`).  
- [ ] Basic documentation of endpoint field mappings (`software/docs/ENDPOINTS.md`).  

---

### v0.4 — Validation & Testing
- [ ] Add test PCAPs and host logs under `software/tests/`.  
- [ ] Define golden JSON outputs for validation.  
- [ ] Document validation steps in `software/docs/TESTING.md`.  
- [ ] Continuous Integration: basic lint + schema checks (`.github/`).  

---

### v0.5 — POC Release
- [ ] Publish POC hardware results in `software/docs/HARDWARE.md`.  
- [ ] Harden install/provision scripts.  
- [ ] Tag `v0.5` release with packaged configs + instructions.  
- [ ] Begin community feedback loop (Issues, Discussions).  

---

## 🔭 Future Considerations
- Suricata support alongside Zeek.  
- Visual dashboards for ICS/OT visibility.  
- Integration with AI-assisted detection (Phase 2+).  
- Rampart uplink (secure one-way forwarding) as a **separate project**.  
- Partnership with non-profit efforts in OT workforce development.  

---

## 📅 Timeline
No fixed deadlines — milestone-based and driven by testing results.  
Focus is **hardware stability first**, then layering in the software pipeline.
