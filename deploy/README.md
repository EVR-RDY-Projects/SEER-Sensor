# SEER Sensor – Deploy Directory

This folder is reserved for **deployment and packaging** of the SEER Sensor.  
It defines how SEER is built, packaged, and run in different environments.

---

## Planned Subfolders

- **docker/**  
  Placeholder for containerization files.  
  - `Dockerfile` → build instructions for a container image.  
  - `docker-compose.yml` → run SEER locally for testing or lab use.

- **packaging/**  
  Placeholder for system-level packaging and release metadata.  
  - `debian/` → build files for `.deb` packages (Debian/Ubuntu).  
  - `sbom/` → Software Bill of Materials for supply-chain transparency.

---

## Purpose

- Provide **reproducible builds** of SEER for developers and operators.  
- Support **containerized deployment** (Docker, Podman, Kubernetes).  
- Support **native packages** for bare-metal OT installs.  
- Standardize how releases are published and versioned.

---

⚠️ **Note:** Deployment artifacts are still in the planning stage.  
This directory is a **placeholder** until Docker images and/or `.deb` packages are built.
