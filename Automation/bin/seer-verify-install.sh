#!/usr/bin/env bash
set -euo pipefail

YAML=/opt/seer/etc/seer.yml

err() { echo "$*" >&2; }

if [[ ! -f "$YAML" ]]; then
  err "Config $YAML not found"
  exit 2
fi

read_yaml() {
  python3 - <<PY
import yaml,sys
cfg=yaml.safe_load(open('$YAML'))
print(cfg.get(sys.argv[1], ''))
PY
}

ring_dir=$(python3 - <<'PY'
import yaml
cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml'))
print(cfg.get('ring_dir','/var/seer/pcap_ring'))
PY
)
dest_dir=$(python3 - <<'PY'
import yaml
cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml'))
print(cfg.get('dest_dir','/opt/seer/var/queue'))
PY
)
backlog_dir=$(python3 - <<'PY'
import yaml
cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml'))
print(cfg.get('backlog_dir','/opt/seer/var/backlog'))
PY
)
iface=$(python3 - <<'PY'
import yaml
cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml'))
print(cfg.get('interface','enp1s0'))
PY
)

echo "Verifier: ring_dir=$ring_dir dest_dir=$dest_dir backlog_dir=$backlog_dir iface=$iface"

count_before=$(ls -1 ${ring_dir}/*.pcap* 2>/dev/null | wc -l || true)
echo "PCAPs in ring before: ${count_before}"

# record latest mtime in dest/backlog
latest_dest_before=$(ls -1t ${dest_dir} 2>/dev/null | head -n1 || true)
latest_back_before=$(ls -1t ${backlog_dir} 2>/dev/null | head -n1 || true)

echo "Triggering mover (oneshot)"
sudo systemctl start seer-move-oldest.service || true
sleep 3

count_after=$(ls -1 ${ring_dir}/*.pcap* 2>/dev/null | wc -l || true)
echo "PCAPs in ring after: ${count_after}"

# Determine if a new file appeared in dest/backlog by comparing mtimes
latest_dest_after=$(ls -1t ${dest_dir} 2>/dev/null | head -n1 || true)
latest_back_after=$(ls -1t ${backlog_dir} 2>/dev/null | head -n1 || true)

if [[ ${count_after} -lt ${count_before} ]]; then
  echo "OK: mover removed at least one file from ring"
  moved=1
elif [[ -n "$latest_dest_after" && "$latest_dest_after" != "$latest_dest_before" ]]; then
  echo "OK: new file appeared in dest: $latest_dest_after"
  moved=1
elif [[ -n "$latest_back_after" && "$latest_back_after" != "$latest_back_before" ]]; then
  echo "OK: new file appeared in backlog: $latest_back_after"
  moved=1
else
  echo "FAIL: no files moved from ring and no new files in dest/backlog"
  moved=0
fi

# check capture service active
if systemctl is-active --quiet seer-capture@${iface}.service; then
  echo "OK: seer-capture@${iface} is active"
  capture_ok=1
else
  echo "FAIL: seer-capture@${iface} not active"
  capture_ok=0
fi

if [[ ${moved} -eq 1 && ${capture_ok} -eq 1 ]]; then
  echo "Verification PASSED"
  exit 0
else
  echo "Verification FAILED"
  exit 3
fi
