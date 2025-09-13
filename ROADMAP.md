# SEER Sensor Roadmap

This roadmap outlines the planned milestones and features for **SEER Sensor**.  
It is a living document and will evolve as development progresses.

---

## 🚧 Current Status
- **Stage**: Proof of Concept (POC)  
- **Focus**: Establishing basic functionality for network packet capture, log generation, and safe test workflows.

---

## 📌 Milestones

### v0.1 — Proof of Concept
- [x] Repository structure with core docs (README, LICENSE, CONTRIBUTING, SECURITY).  
- [ ] Basic Zeek integration: capture from SPAN/TAP and write logs locally.  
- [ ] PCAP rotation & safe storage (to `test-data/` for demos).  
- [ ] Scripts for install/start/stop Zeek.  
- [ ] Placeholder configs (`examples/`, `configs/`).  

### v0.2 — Endpoint + Ingest
- [ ] Add support for JSON ingestion from endpoints (e.g., Sysmon, OT logs).  
- [ ] Python ingest script (`scripts/ingest-endpoints.py`).  
- [ ] Configurable inputs (`examples/inputs.json`).  
- [ ] Initial docs for endpoint log mapping.  

### v0.3 — Rampart Uplink
- [ ] Define secure one-way forwarding design (“Rampart” box).  
- [ ] Prototype forwarding PCAP/Zeek logs to remote collector.  
- [ ] Document network architecture (`docs/architecture.md`).  
- [ ] Add configs for SIEM integration (Chronicle, Splunk, Elastic).  

### v0.4 — Hardware POC Benchmarks
- [ ] Test SEER Sensor performance on common low-cost platforms:
  - Raspberry Pi 4 / 5  
  - Intel NUC / mini PC  
  - Low-power x86 box (fanless)  
- [ ] Document throughput limits (e.g., stable capture @ 100 Mbps / 1 Gbps).  
- [ ] Measure CPU, RAM, and disk usage during sustained PCAP capture.  
- [ ] Publish results in `docs/hardware.md` with recommendations.  
- [ ] Define **minimum viable hardware spec** for field deployments.  

### v0.5 — Testing & Validation
- [ ] Add test PCAPs/logs under `test-data/`.  
- [ ] Build `docs/testing.md` (how to validate the sensor).  
- [ ] Continuous Integration (basic lint/test checks).  

### v0.6 — Alpha Release
- [ ] Hardened scripts for deployment.  
- [ ] Expanded docs: install, hardware, OT environment guidance.  
- [ ] Release tagged container/image for easier deployment.  
- [ ] Community feedback loop (Issues, Discussions).  

---

## 🔭 Future Considerations
- Suricata support alongside Zeek.  
- Visual dashboards for ICS/OT visibility.  
- Integration with AI-assisted detection (Phase 2+).  
- Partnership with non-profit efforts in OT workforce development.  

---

## 📅 Timeline
No fixed deadlines at this stage — development is milestone-based and community-driven.  
Contributors are encouraged to help move milestones forward through Issues and Pull Requests.

---
