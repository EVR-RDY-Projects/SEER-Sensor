# SEER POC — Continuous PCAP Buffer, Oldest Mover, and TUI

Small proof-of-concept for continuous packet capture using `tcpdump`, a tiny “buffer” directory, a mover that archives the **oldest** PCAP when the buffer gets full, and a **no-flicker** terminal dashboard.

---

## What you get

- **Capture service** – `seer-capture.service`  
  `tcpdump` on your NIC (`enp1s0` by default), **time-rotated** every 20s with timestamped filenames.

- **Mover** – `seer-move-oldest.service` + `seer-move-oldest.timer`  
  Every 20s, if the buffer has **≥ 4** PCAPs, it moves the **oldest** file to a destination folder.

- **Dashboard (TUI)** – `seer.sh`  
  Compact, stable layout (no flashing). Auto-compact on mini displays (e.g., 24×64 columns).  
  Hotkeys for start/stop/clear, logs, and refresh speed.

---

## Default locations

| Purpose         | Path                                       | Env var     |
|-----------------|--------------------------------------------|-------------|
| Buffer (Buff)   | `/var/lib/tcpdump/pcap_ring`               | `BUFF_DIR`  |
| Destination     | `/usr/bin/seer-sensor-automation/pcap`     | `DEST_DIR`  |
| Mover log       | `/var/log/seer-mover.log`                  | `MOVER_LOG` |

> You can override these for the mover via `Environment=` lines in the systemd service.

---

## Quick start

1) **Install deps**
```bash
sudo apt-get update
sudo apt-get install -y tcpdump less
```
Create directories

```
sudo mkdir -p /usr/bin/seer-sensor-automation/pcap /var/lib/tcpdump/pcap_ring
sudo chown -R seer:seer /var/lib/tcpdump/pcap_ring
Install the mover script
```
```
sudo tee /usr/bin/seer-sensor-automation/move-oldest-when-4.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BUFF_DIR="${BUFF_DIR:-/var/lib/tcpdump/pcap_ring}"
DEST_DIR="${DEST_DIR:-/usr/bin/seer-sensor-automation/pcap}"
LOG="${LOG:-/var/log/seer-mover.log}"
THRESHOLD="${THRESHOLD:-4}"
mkdir -p "$DEST_DIR"
shopt -s nullglob
pcaps=( "$BUFF_DIR"/*.pcap* )
count="${#pcaps[@]}"
ts="$(date -Is)"
if (( count < THRESHOLD )); then
  echo "$ts: count=$count < threshold=$THRESHOLD (no move)" >>"$LOG"; exit 0; fi
oldest="$(ls -1t "$BUFF_DIR"/*.pcap* 2>/dev/null | tail -n 1 || true)"
if [[ -n "${oldest:-}" && -f "$oldest" ]]; then
  if mv -f -- "$oldest" "$DEST_DIR/"; then
    echo "$ts: moved $(basename "$oldest") -> $DEST_DIR (count was $count)" >>"$LOG"
  else
    echo "$ts: ERROR moving $oldest -> $DEST_DIR" >>"$LOG"; exit 1
  fi
else
  echo "$ts: nothing to move (glob empty?)" >>"$LOG"
fi
EOF
sudo chmod +x /usr/bin/seer-sensor-automation/move-oldest-when-4.sh
```
Install the capture service (time-rotation every 20s)

```
sudo tee /etc/systemd/system/seer-capture.service >/dev/null <<'EOF'
[Unit]
Description=SEER continuous packet capture (time-rotated tcpdump)
After=network.target

[Service]
Type=simple
ExecStartPre=/usr/bin/mkdir -p /var/lib/tcpdump/pcap_ring
ExecStartPre=/usr/bin/chown seer:seer /var/lib/tcpdump/pcap_ring
ExecStart=/usr/bin/tcpdump -i enp1s0 -n -U -s 128 \
  -G 20 -Z seer \
  -w /var/lib/tcpdump/pcap_ring/SEER-%%Y%%m%%d-%%H%%M%%S.pcap
ExecStop=/bin/kill -INT $MAINPID
User=root
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
```
Want size-based rotation instead? Replace -G 20 with -C <MB> -W <count> (e.g., -C 5 -W 6) and set -w /var/lib/.../pcap.pcap to get pcap.pcap0/1/... files.

Install mover service + timer (poll every 20s)

```
sudo tee /etc/systemd/system/seer-move-oldest.service >/dev/null <<'EOF'
[Unit]
Description=SEER mover: when ≥4 pcaps in buffer, move oldest to dest
After=network.target

[Service]
Type=oneshot
# Optional:
# Environment=BUFF_DIR=/var/lib/tcpdump/pcap_ring
# Environment=DEST_DIR=/usr/bin/seer-sensor-automation/pcap
# Environment=THRESHOLD=4
ExecStart=/usr/bin/seer-sensor-automation/move-oldest-when-4.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

sudo tee /etc/systemd/system/seer-move-oldest.timer >/dev/null <<'EOF'
[Unit]
Description=Poll buffer and move oldest when threshold reached

[Timer]
OnUnitActiveSec=20s
AccuracySec=200ms
Unit=seer-move-oldest.service
Persistent=true

[Install]
WantedBy=timers.target
EOF
```
Dashboard (TUI)

```
sudo tee /usr/bin/seer-sensor-automation/seer.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# Compact, no-flicker dashboard (auto-compact at <=64 cols)
set -euo pipefail
REFRESH="${REFRESH:-0.5}"
CAPTURE_SERVICE="${CAPTURE_SERVICE:-seer-capture.service}"
MOVER_SERVICE="${MOVER_SERVICE:-seer-move-oldest.service}"
MOVER_TIMER="${MOVER_TIMER:-seer-move-oldest.timer}"
BUFF_DIR="${BUFF_DIR:-/var/lib/tcpdump/pcap_ring}"
DEST_DIR="${DEST_DIR:-/usr/bin/seer-sensor-automation/pcap}"
MOVER_LOG="${MOVER_LOG:-/var/log/seer-mover.log}"
if [ -t 1 ]; then RESET="$(tput sgr0)"; BOLD="$(tput bold)"; FG_G="$(tput setaf 2)"; FG_Y="$(tput setaf 3)"; FG_R="$(tput setaf 1)"; else RESET=""; BOLD=""; FG_G=""; FG_Y=""; FG_R=""; fi
state(){ systemctl is-active "$1" 2>/dev/null || true; }
badge(){ case "$1" in active) printf "%sactive%s" "$FG_G" "$RESET";; activating) printf "%sstarting%s" "$FG_Y" "$RESET";; failed) printf "%sFAILED%s" "$FG_R" "$RESET";; inactive) printf "%sstopped%s" "$FG_Y" "$RESET";; *) printf "%s" "$1";; esac; }
cnt_pcaps(){ shopt -s nullglob; local c=0; for _ in "$1"/*.pcap*; do ((c++)); done; echo "$c"; }
put(){ tput cup "$1" "$2"; printf "%-*s" "$3" "$4"; }
rule(){ printf "%*s" "$1" "" | tr ' ' '-'; }
open_p(){ tput sc; printf '\033[?25h'; tput smcup; clear; "$@" | ${PAGER:-less} -SRX; tput rmcup; printf '\033[?25l'; tput rc; }
clear; printf '\033[?25l'; OLDSTTY="$(stty -g 2>/dev/null || true)"; stty -echo || true; trap '[ -n "$OLDSTTY" ]&&stty "$OLDSTTY" 2>/dev/null; printf "\033[?25h\n"' EXIT INT TERM
LAST=""
while true; do
  cols=$(tput cols 2>/dev/null || echo 80); host="$(hostname 2>/dev/null || echo seer)"; now="$(date +%T)"
  compact=0; [ "$cols" -le 64 ] && compact=1
  if [ "$compact" -eq 1 ]; then L=46; R=$((cols-L-1)); [ "$R" -lt 16 ] && R=16; put 0 0 "$cols" "$(printf 'SEER [%.1fs] %s %s' "$REFRESH" "$host" "$now")"
  else L=$(( (cols*2)/3 )); R=$((cols-L-1)); [ "$L" -lt 28 ] && L=28; [ "$R" -lt 22 ] && R=22; put 0 0 "$cols" "$(printf 'SEER MONITOR  [REF: %.1fs]  [HOST: %s]  [TIME: %s]' "$REFRESH" "$host" "$now")"; fi
  put 1 0 "$cols" "$(rule "$cols")"
  put 2 0 "$L"  "+ SYSTEM $(rule $((L-9)))"; put 2 $((L+1)) "$R" "+ CTRL $(rule $((R-7)))"
  for r in $(seq 3 11); do tput cup "$r" "$L"; printf "|"; done
  put 3 0 "$L"  "  CAP : $(badge "$(state "$CAPTURE_SERVICE")")"
  put 4 0 "$L"  "  MOV : $(badge "$(state "$MOVER_SERVICE")")"
  put 5 0 "$L"  "  TMR : $(badge "$(state "$MOVER_TIMER")")"
  put 7 0 "$L"  "PCAP:"
  put 8 0 "$L"  "  Buff: $(cnt_pcaps "$BUFF_DIR") ($(basename "$BUFF_DIR"))"
  put 9 0 "$L"  "  Dest: $(cnt_pcaps "$DEST_DIR") ($(basename "$DEST_DIR"))"
  put 3 $((L+2)) "$((R-2))" "[1]Stop";  put 4 $((L+2)) "$((R-2))" "[2]Clear"; put 5 $((L+2)) "$((R-2))" "[3]Start"; put 6 $((L+2)) "$((R-2))" "[4]All"
  put 8 $((L+2)) "$((R-2))" "[+/-]Speed"; put 9 $((L+2)) "$((R-2))" "[c]Cap [m]Mov"; put 10 $((L+2)) "$((R-2))" "[t]Tim [s]Stat"; put 11 $((L+2)) "$((R-2))" "[h]Help [q]Quit"
  put 12 0 "$cols" "$(rule "$cols")"; put 13 0 "$cols" "Input: $LAST"
  if read -r -t "$REFRESH" -n 1 k; then LAST="$k"; case "$k" in
    1) systemctl stop "$CAPTURE_SERVICE" "$MOVER_SERVICE" "$MOVER_TIMER" ;;
    2) mkdir -p "$BUFF_DIR" "$DEST_DIR"; rm -f "$BUFF_DIR"/*.pcap* "$DEST_DIR"/*.pcap* 2>/dev/null || true; :>/var/log/seer-mover.log ;;
    3) systemctl daemon-reload; systemctl restart "$CAPTURE_SERVICE"; systemctl restart "$MOVER_SERVICE" 2>/dev/null || true; systemctl start "$MOVER_TIMER" 2>/dev/null || true ;;
    4) systemctl stop "$CAPTURE_SERVICE" "$MOVER_SERVICE" "$MOVER_TIMER"; mkdir -p "$BUFF_DIR" "$DEST_DIR"; rm -f "$BUFF_DIR"/*.pcap* "$DEST_DIR"/*.pcap* 2>/dev/null || true; :>/var/log/seer-mover.log; systemctl daemon-reload; systemctl start "$CAPTURE_SERVICE"; systemctl start "$MOVER_TIMER" ;;
    '+') REFRESH=$(awk -v r="$REFRESH" 'BEGIN{printf "%.1f", r+0.5}') ;;
    '-') REFRESH=$(awk -v r="$REFRESH" 'BEGIN{v=r-0.5; if(v<0.2)v=0.2; printf "%.1f", v}') ;;
    c|C) open_p journalctl -u "$CAPTURE_SERVICE" -n 400 --no-pager ;;
    m|M) open_p journalctl -u "$MOVER_SERVICE"   -n 400 --no-pager ;;
    t|T) open_p journalctl -u "$MOVER_TIMER"     -n 300 --no-pager ;;
    s|S) open_p systemctl status "$CAPTURE_SERVICE" "$MOVER_SERVICE" "$MOVER_TIMER" --no-pager -l ;;
    h|H) open_p bash -lc "cat <<'HLP'
Controls:
 [1] Stop  [2] Clear  [3] Start  [4] All
 [+/-] Speed  [c] Cap logs  [m] Mover logs
 [t] Timer logs  [s] Status  [q] Quit
HLP" ;;
    q|Q) exit 0 ;;
  esac; fi
done
EOF
sudo chmod +x /usr/bin/seer-sensor-automation/seer.sh
```
Enable + start

```
sudo systemctl daemon-reload
sudo systemctl enable --now seer-capture.service
sudo systemctl enable --now seer-move-oldest.timer
```
Run the dashboard

```
sudo /usr/bin/seer-sensor-automation/seer.sh
```

Usage notes
Change NIC: edit -i enp1s0 in seer-capture.service to your interface (ip -br link to list).

Change cadence: modify -G 20 (seconds) for faster/slower time rotation.

Threshold: set Environment=THRESHOLD=… in seer-move-oldest.service if you want a value other than 4.

Mini monitor: the TUI auto-compacts at ≤64 columns; works nicely on 24×64 terminals.

