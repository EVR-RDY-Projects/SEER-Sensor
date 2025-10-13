#!/usr/bin/env bash
set -euo pipefail

# deps we expect
if ! dpkg -s python3-yaml >/dev/null 2>&1; then
  echo "Installing python3-yaml..."
  sudo apt-get update
  sudo apt-get install -y python3-yaml
fi
if ! command -v tcpdump >/dev/null 2>&1; then
  echo "Installing tcpdump..."
  sudo apt-get update
  sudo apt-get install -y tcpdump
fi

# install wrapper
echo "Installing /usr/bin/seer-capture.sh"
sudo install -m 0755 Automation/bin/seer-capture.sh /usr/bin/seer-capture.sh

# install unit
echo "Installing systemd unit"
sudo install -m 0644 Automation/systemd/seer-capture@.service /etc/systemd/system/seer-capture@.service

# reload units
sudo systemctl daemon-reload

echo "Done. Run: sudo systemctl enable --now seer-capture@<iface>"
