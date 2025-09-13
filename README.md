# SEER Sensor



## 📖 Overview
The **SEER Sensor** is an open-source proof-of-concept (POC) project for OT/IT visibility.  
It is being actively developed and much of the functionality described here is **planned** but not yet implemented.  

SEER is designed to:  
- Capture mirrored traffic from SPAN/TAP ports  
- Generate structured logs (Zeek-style)  
- Ingest endpoint JSON telemetry (Sysmon, osquery, custom agents)  
- Provide hot-swappable PCAP storage for rapid forensic collection  
- Support low-cost hardware builds to simplify deployment in resource-constrained OT environments  


---

## 🚀 Features (current + planned)
- Passive capture of SPAN/TAP traffic *(planned)*  
- Structured metadata generation (Zeek, Suricata optional) *(planned)*  
- Endpoint JSON ingestion (Sysmon, osquery, etc.) *(planned)*  
- **Hot-swappable PCAP drive included in POC hardware** *(planned)*   
- Rolling PCAP capture with remote retrieval via Rampart *(planned)*  
- Hardware reference builds to reduce cost of deployment *(planned)*  
- Secure, one-way forwarding to upstream/cloud SIEMs (e.g., Chronicle) *(planned)*  

---

## 🛠️ Hardware (POC focus)
- Currently testing on commodity x86 mini-PC and ARM SBC platforms  
- **Dedicated storage bay for hot-swappable PCAP drives is working in the POC**  
- Reference Bill of Materials (BOM) for low-cost builds is in progress  
- Long-term goal: integration with **Rampart** (uplink/packager)  

---

## ⚙️ Software (early POC state)
- Current prototype is Linux-based (Debian/Ubuntu)  
- Dependencies under evaluation: Zeek, Python 3  
- Current focus: POC build 
- Planned outputs: JSONs of host logs and Zeek logs  

