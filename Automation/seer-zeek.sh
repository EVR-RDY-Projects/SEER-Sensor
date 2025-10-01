#!/usr/bin/env bash
# seer-zeek.sh — start/stop/status/pcap helper for Zeek with JSON logs
# Usage:
#   sudo ./seer-zeek.sh start         # live capture
#   sudo ./seer-zeek.sh stop
#   ./seer-zeek.sh status
#   sudo ./seer-zeek.sh pcap /path/to/file.pcap   # run on a pcap once

set -euo pipefail

# ---- CONFIG (override via env: IFACE=eth0 LOG_DIR=/data/zeek etc.) ----
IFACE="${IFACE:-enp1s0}"
LOG_DIR="${LOG_DIR:-/var/log/zeek}"
PIDFILE="${PIDFILE:-/var/run/zeek.pid}"
LOCKFILE="${LOCKFILE:-/var/run/zeek-start.lock}"

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
  have zeek || die "zeek not found in PATH"
}

ensure_iface() {
  ip link show "$IFACE" >/dev/null 2>&1 || die "Interface $IFACE not found"
}

ensure_dirs() {
  sudo mkdir -p "$LOG_DIR"
  sudo chown "$(id -u)":"$(id -g)" "$LOG_DIR" 2>/dev/null || true
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

  RUN_DIR="${LOG_DIR}/$(date +'%Y%m%d-%H%M%S')"
  mkdir -p "$RUN_DIR"

  OUTFILE="${LOG_DIR}/zeek.out"
  ERRFILE="${LOG_DIR}/zeek.err"

  echo "Starting Zeek on ${IFACE}; logs -> ${RUN_DIR}"

  # -C ignores bad checksums; JSON via LogAscii::use_json=T
  nohup zeek -C -i "$IFACE" \
    "${ZEEKSCRIPTS[@]}" \
    -e "redef Log::default_logdir=\"$RUN_DIR\"; redef LogAscii::use_json=T;" \
    >"$OUTFILE" 2>"$ERRFILE" < /dev/null &

  ZPID=$!
  echo "$ZPID" | sudo tee "$PIDFILE" >/dev/null

  sleep 1
  if is_zeek "$ZPID"; then
    echo "Zeek started (PID $ZPID)."
    echo "Stdout/Stderr: $OUTFILE  $ERRFILE"
  else
    echo "Zeek failed to start. See $ERRFILE"
    rm -f "$PIDFILE"
    exit 1
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

pcap_once() {
  ensure_env
  ensure_dirs
  PCAP="${1:-}"
  [ -n "$PCAP" ] || die "Usage: $0 pcap /path/to/file.pcap"
  [ -r "$PCAP" ] || die "PCAP not readable: $PCAP"

  RUN_DIR="${LOG_DIR}/pcap-$(date +'%Y%m%d-%H%M%S')"
  mkdir -p "$RUN_DIR"
  echo "Processing PCAP -> $RUN_DIR"

  zeek -r "$PCAP" \
    "${ZEEKSCRIPTS[@]}" \
    -e "redef Log::default_logdir=\"$RUN_DIR\"; redef LogAscii::use_json=T;"

  echo "Done. Example:"
  for f in conn.log dns.log; do
    [ -f "$RUN_DIR/$f" ] && { echo "$RUN_DIR/$f"; head -n 2 "$RUN_DIR/$f" || true; }
  done
}

# ---- DISPATCH ----
case "${1:-}" in
  start)  start_zeek_live ;;
  stop)   stop_zeek ;;
  status) status_zeek ;;
  pcap)   shift; pcap_once "${1:-}";;
  *) echo "Usage: $0 {start|stop|status|pcap <file.pcap>}"; exit 1 ;;
esac
