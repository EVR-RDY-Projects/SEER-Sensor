#!/usr/bin/env bash
set -euo pipefail

# Wait for a network interface to report carrier/LOWER_UP and enable promisc
# Usage: seer-wait-link.sh <iface> [timeout-seconds]

iface=${1:-}
timeout=${2:-${WAIT_LINK_TIMEOUT:-60}}
interval=1

if [ -z "$iface" ]; then
  echo "seer-wait-link: missing iface" >&2
  exit 2
fi

echo "seer-wait-link: bringing $iface up and waiting for link (timeout ${timeout}s)" >&2
ip link set dev "$iface" up || true

elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
  # Prefer carrier sysfs if available
  if [ -f "/sys/class/net/$iface/carrier" ]; then
    if [ "$(cat /sys/class/net/$iface/carrier)" = "1" ]; then
      echo "seer-wait-link: $iface carrier detected" >&2
      ip link set dev "$iface" promisc on || true
      exit 0
    fi
  fi

  # Fallback: look for LOWER_UP in ip output
  if ip -d link show "$iface" 2>/dev/null | grep -q 'LOWER_UP'; then
    echo "seer-wait-link: $iface LOWER_UP" >&2
    ip link set dev "$iface" promisc on || true
    exit 0
  fi

  sleep $interval
  elapsed=$((elapsed + interval))
done

echo "seer-wait-link: timed out waiting for link on $iface (timeout ${timeout}s); continuing" >&2
# Do not fail the start; let capture attempt startup (it may fail if device truly missing)
exit 0
