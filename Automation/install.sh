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

# Resolve repository root (so script can be run from any cwd)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# install wrapper (standardize to /usr/local/bin)
echo "Installing /usr/local/bin/seer-capture.sh"
sudo install -m 0755 "$REPO_ROOT/Automation/bin/seer-capture.sh" /usr/local/bin/seer-capture.sh

# install unit
echo "Installing systemd unit"
sudo install -m 0644 "$REPO_ROOT/Automation/systemd/seer-capture@.service" /etc/systemd/system/seer-capture@.service

# reload units
sudo systemctl daemon-reload
echo "Running setup wizard (non-interactive defaults)"
sudo -E "$REPO_ROOT/Automation/SEER/setup_wizard.py" --yes || true

# Install mover script and units if present
if [[ -f "$REPO_ROOT/Automation/SEER/move_oldest.py" ]]; then
  echo "Installing mover script to /usr/local/bin/seer-move-oldest.py"
  sudo install -m 0755 "$REPO_ROOT/Automation/SEER/move_oldest.py" /usr/local/bin/seer-move-oldest.py
fi

# Install console (TUI) to /usr/local/bin
if [[ -f "$REPO_ROOT/Automation/bin/seer_console.py" ]]; then
  echo "Installing seer-console to /usr/local/bin/seer-console"
  sudo install -m 0755 "$REPO_ROOT/Automation/bin/seer_console.py" /usr/local/bin/seer-console
fi

if [[ -f "$REPO_ROOT/Automation/systemd/seer-move-oldest.service" ]]; then
  echo "Installing seer-move-oldest.service"
  sudo install -m 0644 "$REPO_ROOT/Automation/systemd/seer-move-oldest.service" /etc/systemd/system/seer-move-oldest.service
fi
if [[ -f "$REPO_ROOT/Automation/systemd/seer-move-oldest.timer" ]]; then
  echo "Installing seer-move-oldest.timer"
  sudo install -m 0644 "$REPO_ROOT/Automation/systemd/seer-move-oldest.timer" /etc/systemd/system/seer-move-oldest.timer
fi

echo "Reloading systemd daemon and enabling services"
sudo systemctl daemon-reload

# Enable and start capture for detected interface (use what was written to /opt/seer/etc/seer.yml if present)
INTERFACE="enp1s0"
if [[ -f /opt/seer/etc/seer.yml ]]; then
  INTERFACE=$(python3 - <<'PY'
import yaml
try:
    cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml'))
    print(cfg.get('interface','enp1s0'))
except Exception:
    print('enp1s0')
PY
)
fi

echo "Enabling and starting seer-capture@${INTERFACE}.service"
sudo systemctl enable --now seer-capture@${INTERFACE}.service || true

if systemctl list-unit-files | grep -q seer-move-oldest.timer; then
  echo "Enabling and starting seer-move-oldest.timer"
  sudo systemctl enable --now seer-move-oldest.timer || true
fi

echo "Verification: listing units and recent journal entries"
systemctl status seer-capture@${INTERFACE}.service --no-pager || true
systemctl list-timers --all | grep seer || true
sudo journalctl -u seer-capture@${INTERFACE}.service -n 30 --no-pager || true

echo "Install finished. If setup wrote /opt/seer/etc/seer.yml, review it and adjust as needed."

# Install verifier and run it
if [[ -f "$REPO_ROOT/Automation/bin/seer-verify-install.sh" ]]; then
  echo "Installing verifier to /usr/local/bin/seer-verify-install.sh"
  sudo install -m 0755 "$REPO_ROOT/Automation/bin/seer-verify-install.sh" /usr/local/bin/seer-verify-install.sh
  echo "Running post-install verification (this may trigger mover once)"
  sudo /usr/local/bin/seer-verify-install.sh || {
    echo "Post-install verification failed. Check journalctl -u seer-move-oldest.service and seer-capture logs." >&2
    exit 4
  }
fi
