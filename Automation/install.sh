#!/usr/bin/env bash
set -euo pipefail

# Ensure non-interactive apt in all contexts
export DEBIAN_FRONTEND=noninteractive

# CLI args
ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) echo "Usage: $0 [--yes]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

# deps we expect
if ! dpkg -s python3-yaml >/dev/null 2>&1; then
  echo "Installing python3-yaml..."
  sudo -E apt-get update -qq || true
  sudo -E apt-get install -y -qq python3-yaml
fi
if ! command -v tcpdump >/dev/null 2>&1; then
  echo "Installing tcpdump..."
  sudo -E apt-get update -qq || true
  sudo -E apt-get install -y -qq tcpdump
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
if [[ $ASSUME_YES -eq 1 ]]; then
  echo "Running setup wizard (non-interactive defaults with timeout)"
  if ! timeout "${WIZ_TIMEOUT:-60s}" sudo -E "$REPO_ROOT/Automation/SEER/setup_wizard.py" --yes; then
    echo "WARNING: setup wizard --yes timed out or failed; continuing with defaults." >&2
  fi
else
  echo "Running setup wizard (interactive)"
  sudo -E "$REPO_ROOT/Automation/SEER/setup_wizard.py" || true
fi

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

# Install Zeek wrapper
if [[ -f "$REPO_ROOT/Automation/seer-zeek.sh" ]]; then
  echo "Installing seer-zeek.sh to /usr/local/bin/seer-zeek.sh"
  sudo install -m 0755 "$REPO_ROOT/Automation/seer-zeek.sh" /usr/local/bin/seer-zeek.sh
fi

# Install Zeek systemd unit
if [[ -f "$REPO_ROOT/Automation/systemd/seer-zeek@.service" ]]; then
  echo "Installing seer-zeek@.service"
  sudo install -m 0644 "$REPO_ROOT/Automation/systemd/seer-zeek@.service" /etc/systemd/system/seer-zeek@.service
fi

# Install hotswap script and service
if [[ -f "$REPO_ROOT/Automation/SEER/seer_hotswap.py" ]]; then
  echo "Installing seer_hotswap.py to /usr/local/bin/seer_hotswap.py"
  sudo install -m 0755 "$REPO_ROOT/Automation/SEER/seer_hotswap.py" /usr/local/bin/seer_hotswap.py
fi
if [[ -f "$REPO_ROOT/Automation/systemd/seer-hotswap.service" ]]; then
  echo "Installing seer-hotswap.service"
  sudo install -m 0644 "$REPO_ROOT/Automation/systemd/seer-hotswap.service" /etc/systemd/system/seer-hotswap.service
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
INTERFACE="enp2s0"
if [[ -f /opt/seer/etc/seer.yml ]]; then
  INTERFACE=$(python3 - <<'PY'
import yaml
try:
    cfg = yaml.safe_load(open('/opt/seer/etc/seer.yml'))
    print(cfg.get('interface', 'enp2s0'))
except Exception:
    print('enp2s0')
PY
  )
fi

echo "Enabling and starting seer-capture@${INTERFACE}.service"
sudo systemctl enable --now seer-capture@${INTERFACE}.service || true

# Enable and start Zeek (if unit is installed and zeek binary exists)
if [[ -f /etc/systemd/system/seer-zeek@.service ]]; then
  if command -v zeek >/dev/null 2>&1; then
    echo "Enabling and starting seer-zeek@${INTERFACE}.service"
    sudo systemctl enable --now seer-zeek@${INTERFACE}.service || true
  elif [[ -x /opt/zeek/bin/zeek ]]; then
    echo "Zeek found at /opt/zeek/bin; proceeding to enable service"
    sudo systemctl enable --now seer-zeek@${INTERFACE}.service || true
  else
    echo "WARNING: zeek binary not found; skipping seer-zeek@ enable/start." >&2
  fi
else
  echo "WARNING: seer-zeek@.service unit file not found; skipping seer-zeek@ enable/start." >&2
fi

if systemctl list-unit-files | grep -q seer-move-oldest.timer; then
  echo "Enabling and starting seer-move-oldest.timer"
  sudo systemctl enable --now seer-move-oldest.timer || true
fi

if systemctl list-unit-files | grep -q seer-hotswap.service; then
  echo "Enabling and starting seer-hotswap.service"
  sudo systemctl enable --now seer-hotswap.service || true
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
  if ! timeout "${VERIFY_TIMEOUT:-120s}" sudo /usr/local/bin/seer-verify-install.sh; then
    if [[ $ASSUME_YES -eq 1 ]]; then
      echo "WARNING: Post-install verification failed or timed out. Check seer-move-oldest and seer-capture logs." >&2
    else
      echo "Post-install verification failed. Check journalctl -u seer-move-oldest.service and seer-capture logs." >&2
      exit 4
    fi
  fi
fi
