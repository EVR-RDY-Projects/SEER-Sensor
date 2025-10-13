mkdir -p Automation/bin
tee Automation/bin/seer-capture.sh >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
iface="${1:?usage: seer-capture.sh <iface>}"

# Read settings from YAML
rotate="$(python3 -c 'import yaml;print(yaml.safe_load(open("/opt/seer/etc/seer.yml"))["capture"]["rotate_seconds"])')"
snap="$(python3 -c 'import yaml;print(yaml.safe_load(open("/opt/seer/etc/seer.yml"))["capture"]["snaplen"])')"

# Ensure ring dir exists and owned by seer
mkdir -p /var/seer/pcap_ring
chown seer:seer /var/seer/pcap_ring

# Find tcpdump dynamically
TCPDUMP="$(command -v tcpdump || true)"
if [ -z "${TCPDUMP}" ] || [ ! -x "${TCPDUMP}" ]; then
  echo "tcpdump not found in PATH" >&2
  exit 127
fi

# Run tcpdump as root, drop privileges to 'seer' after opening the iface
exec "${TCPDUMP}" -i "$iface" -n -U -s "$snap" -G "$rotate" -Z seer \
  -w /var/seer/pcap_ring/SEER-%Y%m%d-%H%M%S.pcap
SH
chmod +x Automation/bin/seer-capture.sh
