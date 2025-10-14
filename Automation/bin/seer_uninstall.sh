#!/usr/bin/env bash
set -euo pipefail

# Defaults
PURGE=0
ASSUME_YES=0

usage() {
  cat <<EOF
SEER uninstall

Usage: $0 [--purge] [--yes]

  --purge   Also delete config (/opt/seer) and data (/var/seer, /var/lib/tcpdump/pcap_ring)
  --yes     Do not prompt for confirmation
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

say() { echo -e "\033[1m$*\033[0m"; }
ok()  { echo "  ✔ $*"; }
warn(){ echo "  ! $*" >&2; }

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  read -r -p "Proceed? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# What we'll do
say "SEER uninstall plan:"
echo "  - Stop & disable: seer-capture@*.service, seer-move-oldest.service, seer-move-oldest.timer, seer-zeek@*.service"
echo "  - Remove units   : /etc/systemd/system/seer-capture@.service, seer-move-oldest.{service,timer}, seer-zeek@.service"
echo "  - Remove binaries: /usr/local/bin/seer-capture.sh, /usr/local/bin/seer_console.py, /usr/local/bin/seer-console, /usr/local/bin/seer-zeek.sh"
if [[ $PURGE -eq 1 ]]; then
  echo "  - PURGE config   : /opt/seer (incl. /opt/seer/etc/seer.yml backups)"
  echo "  - PURGE data     : /var/seer and /var/lib/tcpdump/pcap_ring (PCAPs WILL BE DELETED)"
else
  echo "  - Keep config    : /opt/seer"
  echo "  - Keep data      : /var/seer and /var/lib/tcpdump/pcap_ring"
fi

confirm || { warn "Aborted."; exit 1; }

say "1) Stop & disable services/timer"
# Stop any capture instances
mapfile -t CAPTURE_UNITS < <(systemctl list-units --type=service --all --no-legend 'seer-capture@*.service' | awk '{print $1}' || true)
if [[ ${#CAPTURE_UNITS[@]} -gt 0 ]]; then
  systemctl stop "${CAPTURE_UNITS[@]}" || true
  systemctl disable "${CAPTURE_UNITS[@]}" || true
  systemctl reset-failed "${CAPTURE_UNITS[@]}" || true
fi
# Stop mover
systemctl stop  seer-move-oldest.timer 2>/dev/null || true
systemctl stop  seer-move-oldest.service 2>/dev/null || true
systemctl disable seer-move-oldest.timer 2>/dev/null || true
systemctl disable seer-move-oldest.service 2>/dev/null || true
systemctl reset-failed seer-move-oldest.timer 2>/dev/null || true
systemctl reset-failed seer-move-oldest.service 2>/dev/null || true
# Stop any zeek instances
mapfile -t ZEEK_UNITS < <(systemctl list-units --type=service --all --no-legend 'seer-zeek@*.service' | awk '{print $1}' || true)
if [[ ${#ZEEK_UNITS[@]} -gt 0 ]]; then
  systemctl stop "${ZEEK_UNITS[@]}" || true
  systemctl disable "${ZEEK_UNITS[@]}" || true
  systemctl reset-failed "${ZEEK_UNITS[@]}" || true
fi
ok "services/timer stopped & disabled (where present)"

say "2) Remove systemd unit files"
rm -f /etc/systemd/system/seer-capture@.service \
      /etc/systemd/system/seer-move-oldest.service \
  /etc/systemd/system/seer-move-oldest.timer \
  /etc/systemd/system/seer-zeek@.service
systemctl daemon-reload
ok "systemd units removed and daemon reloaded"

say "3) Remove installed binaries"
rm -f /usr/local/bin/seer-capture.sh \
  /usr/local/bin/seer_console.py \
  /usr/local/bin/seer-console \
  /usr/local/bin/seer-zeek.sh
# Remove legacy stray copy if it exists (some systems may have installed to /usr/bin)
[[ -f /usr/bin/seer-capture.sh ]] && rm -f /usr/bin/seer-capture.sh || true
[[ -f /usr/bin/seer-console ]] && rm -f /usr/bin/seer-console || true
ok "binaries removed"

if [[ $PURGE -eq 1 ]]; then
  say "4) PURGE config and data"
  # Be extra cautious: only rm if the paths look right
  [[ -d /opt/seer ]] && rm -rf /opt/seer || true
  [[ -d /var/seer ]] && rm -rf /var/seer || true
  [[ -d /var/log/zeek ]] && rm -rf /var/log/zeek || true
  [[ -d /var/lib/tcpdump/pcap_ring ]] && rm -rf /var/lib/tcpdump/pcap_ring || true
  ok "config/data purged"
else
  say "4) Skipping purge (config/data kept)"
fi

say "5) Done"
echo "You can reinstall with:"
echo "  sudo -E Automation/SEER/setup_wizard.py"
echo "  Automation/install.sh"
