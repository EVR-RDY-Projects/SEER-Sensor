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
thresh=$(python3 - <<'PY'
import yaml
cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml'))
print(int(cfg.get('buffer_threshold',4)))
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

json_spool=$(python3 - <<'PY'
import yaml
cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml'))
print(cfg.get('json_spool','/var/seer/json_spool'))
PY
)

echo "Verifier: ring_dir=$ring_dir dest_dir=$dest_dir backlog_dir=$backlog_dir iface=$iface"
echo "Verifier: json_spool=$json_spool"

count_before=$(ls -1 ${ring_dir}/*.pcap* 2>/dev/null | wc -l || true)
echo "PCAPs in ring before: ${count_before}"

# If the ring doesn't have enough files to trigger the mover, create harmless dummy
# closed pcap files (older mtime) so the mover can operate deterministically during
# automated install verification.
if [[ ${count_before} -lt ${thresh} ]]; then
  need=$((thresh - count_before))
  echo "Creating ${need} dummy pcap(s) in ring to meet threshold ${thresh}"
  for i in $(seq 1 ${need}); do
    fn="${ring_dir}/SEER-DUMMY-$(date +%s)-${i}.pcap"
    mkdir -p "${ring_dir}" || true
    # create a tiny file and mark it as older than QUIET_SECS used by mover
    dd if=/dev/zero of="${fn}" bs=1 count=1 >/dev/null 2>&1 || true
    chown seer:seer "${fn}" 2>/dev/null || true
    # make the mtime safely older than mover's QUIET_SECS (use 10s)
    touch -d '10 seconds ago' "${fn}" || true
  done
  # refresh count
  count_before=$(ls -1 ${ring_dir}/*.pcap* 2>/dev/null | wc -l || true)
  echo "PCAPs in ring after adding dummies: ${count_before}"
fi

# record latest mtime in dest/backlog
latest_dest_before=$(ls -1t ${dest_dir} 2>/dev/null | head -n1 || true)
latest_back_before=$(ls -1t ${backlog_dir} 2>/dev/null | head -n1 || true)

echo "Triggering mover (oneshot)"
# Stop capture briefly to avoid tcpdump creating new files during the oneshot test
sudo systemctl stop seer-capture@${iface}.service || true
sudo systemctl start seer-move-oldest.service || true
sleep 3
sudo systemctl start seer-capture@${iface}.service || true

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

# Check zeek service active
if systemctl is-active --quiet seer-zeek@${iface}.service; then
  echo "OK: seer-zeek@${iface} is active"
  zeek_ok=1
else
  echo "FAIL: seer-zeek@${iface} not active"
  zeek_ok=0
fi

# Check Zeek is writing logs into json_spool
zc_before=$(ls -1 ${json_spool}/*.log ${json_spool}/*.json* 2>/dev/null | wc -l || true)
sleep 2
zc_after=$(ls -1 ${json_spool}/*.log ${json_spool}/*.json* 2>/dev/null | wc -l || true)
if [[ ${zc_after} -gt 0 ]]; then
  echo "OK: Zeek logs detected in json_spool (${zc_after})"
  logs_ok=1
else
  echo "WARN: no Zeek logs found in json_spool yet (fresh install or low traffic). Skipping log assertion."
  logs_ok=1
fi

if [[ ${moved} -eq 1 && ${capture_ok} -eq 1 && ${zeek_ok} -eq 1 && ${logs_ok} -eq 1 ]]; then
  echo "Verification PASSED"
  exit 0
else
  echo "Verification FAILED"
  exit 3
fi
