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

# Ensure we have privileges; re-exec with sudo if needed
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

# Wrapper to call systemctl without interactive password prompts
sc() { systemctl --no-ask-password "$@"; }

# Stop/disable helpers with bounded timeouts and signal fallbacks
stop_units() {
  local units=("$@")
  [[ ${#units[@]} -eq 0 ]] && return 0
  for u in "${units[@]}"; do
    # Try gentle INT first (for tcpdump clean close), then stop with timeout
    sc kill -s INT "$u" 2>/dev/null || true
    sc stop --timeout=10s "$u" 2>/dev/null || true
    # If still lingering, force kill and stop again briefly
    sc kill -s KILL "$u" 2>/dev/null || true
    sc stop --timeout=3s "$u" 2>/dev/null || true
  done
}

disable_units() {
  local units=("$@")
  [[ ${#units[@]} -eq 0 ]] && return 0
  for u in "${units[@]}"; do
    sc disable "$u" 2>/dev/null || true
    sc reset-failed "$u" 2>/dev/null || true
  done
}

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  read -r -p "Proceed? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# What we'll do
say "SEER uninstall plan:"
echo "  - Stop & disable: seer-capture@*.service, seer-move-oldest.service, seer-move-oldest.timer, seer-zeek@*.service, seer-hotswap.service"
echo "  - Remove units   : /etc/systemd/system/seer-capture@.service, seer-move-oldest.{service,timer}, seer-zeek@.service, seer-hotswap.service"
echo "  - Remove binaries: /usr/local/bin/seer-capture.sh, /usr/local/bin/seer_console.py, /usr/local/bin/seer-console, /usr/local/bin/seer-zeek.sh, /usr/local/bin/seer_hotswap.py"
if [[ $PURGE -eq 1 ]]; then
  echo "  - PURGE config   : /opt/seer (incl. /opt/seer/etc/seer.yml backups)"
  echo "  - PURGE data     : /var/seer and /var/lib/tcpdump/pcap_ring (PCAPs WILL BE DELETED)"
else
  echo "  - Keep config    : /opt/seer"
  echo "  - Keep data      : /var/seer and /var/lib/tcpdump/pcap_ring"
fi

confirm || { warn "Aborted."; exit 1; }

say "1) Stop & disable services/timer"
# Discover loaded templated units only; avoid parsing bullets or decorations
mapfile -t CAPTURE_UNITS < <(sc list-units --type=service --all --no-legend --plain 'seer-capture@*.service' | awk '{print $1}' || true)
mapfile -t ZEEK_UNITS    < <(sc list-units --type=service --all --no-legend --plain 'seer-zeek@*.service'    | awk '{print $1}' || true)

# Stop capture and zeek instances with timeouts
stop_units "${CAPTURE_UNITS[@]:-}"
stop_units "${ZEEK_UNITS[@]:-}"

# Stop and disable mover units (timer then service)
stop_units seer-move-oldest.timer seer-move-oldest.service seer-hotswap.service
disable_units "${CAPTURE_UNITS[@]:-}"
disable_units "${ZEEK_UNITS[@]:-}"
disable_units seer-move-oldest.timer seer-move-oldest.service seer-hotswap.service
ok "services/timer stopped & disabled (where present)"

say "2) Remove systemd unit files"
rm -f /etc/systemd/system/seer-capture@.service \
      /etc/systemd/system/seer-move-oldest.service \
      /etc/systemd/system/seer-move-oldest.timer \
      /etc/systemd/system/seer-move-oldest.path \
      /etc/systemd/system/seer-zeek@.service \
      /etc/systemd/system/seer-hotswap.service
sc daemon-reload
ok "systemd units removed and daemon reloaded"say "3) Remove installed binaries"
rm -f /usr/local/bin/seer-capture.sh \
  /usr/local/bin/seer_console.py \
  /usr/local/bin/seer-console \
  /usr/local/bin/seer-zeek.sh \
  /usr/local/bin/seer-move-oldest.py \
  /usr/local/bin/seer_hotswap.py \
  /usr/local/bin/seer-verify-install.sh
# Remove legacy stray copy if it exists (some systems may have installed to /usr/bin)
[[ -f /usr/bin/seer-capture.sh ]] && rm -f /usr/bin/seer-capture.sh || true
[[ -f /usr/bin/seer-console ]] && rm -f /usr/bin/seer-console || true
ok "binaries removed"

if [[ $PURGE -eq 1 ]]; then
  say "4) PURGE config and data"
  # Be extra cautious: only rm if the paths look right
  [[ -d /opt/seer ]] && rm -rf /opt/seer || true
  # Known SEER data/log locations (remove if present)
  [[ -d /var/seer ]] && rm -rf /var/seer || true
  [[ -d /var/seer/json_spool ]] && rm -rf /var/seer/json_spool || true
  [[ -d /var/seer/pcap_ring ]] && rm -rf /var/seer/pcap_ring || true
  [[ -d /opt/seer/var/queue ]] && rm -rf /opt/seer/var/queue || true
  [[ -d /opt/seer/var/backlog ]] && rm -rf /opt/seer/var/backlog || true
  [[ -d /var/log/seer ]] && rm -rf /var/log/seer || true
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
