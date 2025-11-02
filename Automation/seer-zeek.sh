#!/usr/bin/env bash
# seer-zeek.sh — start/stop/status/restart helper for Zeek with JSON logs
# Expected env (overridable): IFACE, LOG_DIR, LOG_FLAT, SYSTEMD, PIDFILE, LOCKFILE
# Systemd usage: the service sets SYSTEMD=1 to run in foreground with exec

set -euo pipefail

# Ensure /opt/zeek is in PATH for direct invocation when run outside login shells
export PATH="/opt/zeek/bin:${PATH}"

# ---- CONFIG (override via env: IFACE=eth0 LOG_DIR=/data/zeek etc.) ----
IFACE="${IFACE:-enp1s0}"
LOG_DIR="${LOG_DIR:-/var/log/zeek}"
PIDFILE="${PIDFILE:-/run/zeek.pid}"
LOCKFILE="${LOCKFILE:-/run/zeek-start.lock}"
SYSTEMD="${SYSTEMD:-0}"

"${LOG_FLAT:-}" >/dev/null 2>&1 || true # silence shellcheck for unbound in debug

# Zeek scripts to enable (keep minimal/robust)
ZEEKSCRIPTS=(
  base/protocols/conn/main.zeek
  base/protocols/dns/main.zeek
)

# ---- UTILS ----
die(){ echo "ERROR: $*" >&2; exit 1; }
is_zeek(){ ps -p "$1" -o comm= 2>/dev/null | grep -qx zeek; }
have(){ command -v "$1" >/dev/null 2>&1; }

ensure_env() {
  have zeek || die "zeek not found in PATH (PATH=$PATH)"
}

ensure_iface() {
  ip link show "$IFACE" >/dev/null 2>&1 || die "Interface $IFACE not found"
}

ensure_dirs() {
  mkdir -p "$LOG_DIR"
  # If running as root via systemd, leave ownership as-is; otherwise chown to current user
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    chown "$(id -u)":"$(id -g)" "$LOG_DIR" 2>/dev/null || true
  fi
}

latest_run_dir() {
  ls -1dt "$LOG_DIR"/* 2>/dev/null | head -n1 || true
}

start_zeek_live() {
  ensure_env
  ensure_iface
  ensure_dirs

  # single-run lock
  exec 9>"$LOCKFILE"
  if ! flock -n 9; then
    echo "Another start is in progress; exiting."
    exit 0
  fi

  # already running?
  if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" || true)"
    if [ -n "${PID:-}" ] && is_zeek "$PID"; then
      echo "Zeek already running (PID $PID)"
      exit 0
    fi
    rm -f "$PIDFILE"
  fi

  # Determine output directory
  if [ "${LOG_FLAT:-0}" = "1" ]; then
    RUN_DIR="${LOG_DIR}"
  else
    RUN_DIR="${LOG_DIR}/$(date +'%Y%m%d-%H%M%S')"
  fi
  mkdir -p "$RUN_DIR"

  OUTFILE="${LOG_DIR}/zeek.out"
  ERRFILE="${LOG_DIR}/zeek.err"

  # Read AF_PACKET settings from YAML (zeek_workers, fanout_id)
  ZE_WORKERS=$(python3 - <<'PY'
import yaml
try:
    cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml')) or {}
    print(int(cfg.get('zeek_workers',2)))
except Exception:
    print(2)
PY
)
  FANOUT_ID=$(python3 - <<'PY'
import yaml
try:
    cfg=yaml.safe_load(open('/opt/seer/etc/seer.yml')) or {}
    print(int(cfg.get('fanout_id',42)))
except Exception:
    print(42)
PY
)

  # Build AF_PACKET redefs
  AF_REDEFS="redef AF_Packet::fanout_id=${FANOUT_ID}; redef AF_Packet::interfaces += { [\$name=\"${IFACE}\", \$threads=${ZE_WORKERS}] };"

  echo "Starting Zeek on ${IFACE} (AF_PACKET workers=${ZE_WORKERS} fanout=${FANOUT_ID}); logs -> ${RUN_DIR}"
  echo "[DEBUG] ENV: IFACE=$IFACE LOG_DIR=$LOG_DIR LOG_FLAT=${LOG_FLAT:-unset} SYSTEMD=${SYSTEMD:-unset} PATH=$PATH"

  if [ "$SYSTEMD" = "1" ]; then
    # Foreground mode for systemd: let zeek become the main process
    echo "[DEBUG] Exec: zeek -C -i af_packet::$IFACE ${ZEEKSCRIPTS[*]} -e '$AF_REDEFS' -e 'redef Log::default_logdir=\"$RUN_DIR\"; redef LogAscii::use_json=T;'"
    exec zeek -C -i "af_packet::$IFACE" \
      "${ZEEKSCRIPTS[@]}" \
      -e "$AF_REDEFS" \
      -e "redef Log::default_logdir=\"$RUN_DIR\"; redef LogAscii::use_json=T;"
  else
    # Background mode for manual usage
    echo "[DEBUG] Spawn (bg): zeek -C -i af_packet::$IFACE ${ZEEKSCRIPTS[*]} -e '$AF_REDEFS' -e 'redef Log::default_logdir=\"$RUN_DIR\"; redef LogAscii::use_json=T;'"
    nohup zeek -C -i "af_packet::$IFACE" \
      "${ZEEKSCRIPTS[@]}" \
      -e "$AF_REDEFS" \
      -e "redef Log::default_logdir=\"$RUN_DIR\"; redef LogAscii::use_json=T;" \
      >"$OUTFILE" 2>"$ERRFILE" < /dev/null &
    ZPID=$!
    echo "$ZPID" > "$PIDFILE"

    sleep 1
    if is_zeek "$ZPID"; then
      echo "Zeek started (PID $ZPID)."
      echo "Stdout/Stderr: $OUTFILE  $ERRFILE"
    else
      echo "Zeek failed to start. See $ERRFILE"
      rm -f "$PIDFILE"
      exit 1
    fi
  fi
}

stop_zeek() {
  echo "Stopping Zeek..."
  if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" || true)"
    if [ -n "${PID:-}" ] && is_zeek "$PID"; then
      kill "$PID" || true
      for _ in 1 2 3 4 5; do
        sleep 1; is_zeek "$PID" || break
      done
      is_zeek "$PID" && kill -9 "$PID" || true
    fi
    rm -f "$PIDFILE"
  fi
  # belt & suspenders:
  pkill -x zeek 2>/dev/null || true
  rm -f "$LOCKFILE" 2>/dev/null || true
  echo "Done."
}

status_zeek() {
  if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "${PID:-}" ] && is_zeek "$PID"; then
      echo "Zeek is RUNNING (PID $PID)"
    else
      echo "Zeek is NOT running (stale pidfile removed)"
      rm -f "$PIDFILE"
    fi
  else
    # fallback: look for zeek anyway
    if pgrep -x zeek >/dev/null 2>&1; then
      echo "Zeek is RUNNING (PID $(pgrep -x zeek | tr '\n' ' '))"
    else
      echo "Zeek is NOT running"
    fi
  fi
  LRD="$(latest_run_dir)"
  [ -n "$LRD" ] && echo "Last log dir: $LRD"
}

restart_zeek() {
  stop_zeek || true
  start_zeek_live
}

# ---- CLI ----
case "${1:-}" in
  start)    start_zeek_live ;;
  stop)     stop_zeek ;;
  restart)  restart_zeek ;;
  status)   status_zeek ;;
  *)        echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
