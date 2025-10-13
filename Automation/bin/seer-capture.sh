#!/usr/bin/env bash
set -euo pipefail

iface="${1:?usage: seer-capture.sh <iface>}"

# Read settings from YAML (fall back to hard defaults if yaml or pyyaml missing)
rotate="$(python3 - <<'PY'
import sys, yaml
try:
    cfg = yaml.safe_load(open('/opt/seer/etc/seer.yml'))
    print(cfg.get('capture', {}).get('rotate_seconds', 20))
except Exception:
    print(20)
PY
)"
snap="$(python3 - <<'PY'
import sys, yaml
try:
    cfg = yaml.safe_load(open('/opt/seer/etc/seer.yml'))
    print(cfg.get('capture', {}).get('snaplen', 128))
except Exception:
    print(128)
PY
)"

# Ensure ring dir exists and owned by seer
mkdir -p /var/seer/pcap_ring
chown seer:seer /var/seer/pcap_ring || true

# Find tcpdump dynamically
TCPDUMP="$(command -v tcpdump || true)"
if [ -z "${TCPDUMP}" ] || [ ! -x "${TCPDUMP}" ]; then
  echo "tcpdump not found in PATH" >&2
  exit 127
fi

# Run tcpdump as root, let it drop privileges to 'seer' via -Z after opening
exec "${TCPDUMP}" -i "$iface" -n -U -s "$snap" -G "$rotate" -Z seer \
  -w /var/seer/pcap_ring/SEER-%Y%m%d-%H%M%S.pcap
