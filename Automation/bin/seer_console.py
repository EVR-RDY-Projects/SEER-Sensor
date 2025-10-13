#!/usr/bin/env python3
# SEER Split-Panel Console (Python, curses)
import os, time, json, glob, curses, tempfile, shlex, subprocess
from datetime import datetime

# -------- Config (override via env) --------
REFRESH = float(os.environ.get("REFRESH", "0.5"))
# NOTE: capture service is templated; pass the full unit, e.g. seer-capture@enp1s0.service
CAPTURE_SERVICE = os.environ.get("CAPTURE_SERVICE", "seer-capture@enp1s0.service")
MOVER_SERVICE   = os.environ.get("MOVER_SERVICE",   "seer-move-oldest.service")
MOVER_TIMER     = os.environ.get("MOVER_TIMER",     "seer-move-oldest.timer")

BUFF_DIR = os.environ.get("BUFF_DIR", "/var/seer/pcap_ring")
MGR_LOG_HINT = os.environ.get("MGR_LOG", "/var/log/seer/mover.log")

def run(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

def systemctl_is_active(unit):
    if not unit: return "inactive"
    r = run(["systemctl","is-active",unit])
    s = (r.stdout or r.stderr or "").strip()
    return s if s else "inactive"

def badge_text(state):
    s = (state or "").lower()
    if s == "active":   return ("active", 2)
    if s == "failed":   return ("FAILED", 1)
    if s in ("inactive","dead"): return ("stopped", 3)
    if s.startswith("activat"):  return ("starting", 3)
    return (s or "n/a", 3)

def count_pcaps(path):
    try:
        return sum(1 for _ in glob.glob(os.path.join(path,"*.pcap*")))
    except Exception:
        return 0

def human_bytes(n):
    if not isinstance(n,(int,float)) or n is None: return "n/a"
    u = ["B","KB","MB","GB","TB","PB"]; i=0; v=float(n)
    while v>=1024 and i<len(u)-1: v/=1024; i+=1
    return f"{v:.1f} {u[i]}"

def draw_text(stdscr, y, x, w, text): stdscr.addstr(y, x, (text[:w]).ljust(w))
def divider(stdscr, y, width, ch="-"): stdscr.addstr(y, 0, (ch*width)[:width])

def act_stop():
    units = [CAPTURE_SERVICE, MOVER_SERVICE]
    if MOVER_TIMER: units.append(MOVER_TIMER)
    run(["systemctl","stop",*units])

def act_clear(buff_dir):
    os.makedirs(buff_dir, exist_ok=True)
    for p in glob.glob(os.path.join(buff_dir,"*.pcap*")):
        try: os.unlink(p)
        except: pass

def act_start():
    run(["systemctl","daemon-reload"])
    for u in (CAPTURE_SERVICE, MOVER_SERVICE):
        if not u: continue
        r = run(["systemctl","restart",u])
        if r.returncode!=0: run(["systemctl","start",u])

def render(stdscr):
    global REFRESH
    curses.curs_set(0); stdscr.nodelay(True)
    if curses.has_colors():
        curses.start_color()
        curses.init_pair(1, curses.COLOR_RED,   -1)
        curses.init_pair(2, curses.COLOR_GREEN, -1)
        curses.init_pair(3, curses.COLOR_YELLOW,-1)
        curses.init_pair(4, curses.COLOR_CYAN,  -1)
        curses.init_pair(5, curses.COLOR_WHITE, -1)

    last_key = ""
    while True:
        h, w = stdscr.getmaxyx()
        compact = (w <= 64)
        stdscr.erase()

        host = os.uname().nodename
        now = datetime.now()
        hdr = f"SEER MONITOR  [REF: {REFRESH:.1f}s]  [HOST: {host}]  [TIME: {now.strftime('%H:%M:%S  %b %d %Y')}]"
        draw_text(stdscr, 0, 0, w, hdr)
        divider(stdscr, 1, w)

        cap_state = systemctl_is_active(CAPTURE_SERVICE)
        mov_state = systemctl_is_active(MOVER_SERVICE)
        tim_state = systemctl_is_active(MOVER_TIMER) if MOVER_TIMER else "n/a"

        buff_count = count_pcaps(BUFF_DIR)

        left_w = max(28, (w*2)//3); right_w = max(22, w-left_w-1)
        draw_text(stdscr, 2, 0, left_w,  f"+ SYSTEM {'-'*(max(0,left_w-10))}")
        draw_text(stdscr, 2, left_w+1, right_w, f"+ CONTROLS {'-'*(max(0,right_w-12))}")
        for r in range(3, 12):
            if left_w < w: stdscr.addstr(r, left_w, "|")

        s, c = badge_text(cap_state); stdscr.addstr(3, 2, "  CAPTURE : "); stdscr.addstr(s, curses.color_pair(c))
        s, c = badge_text(mov_state); stdscr.addstr(4, 2, "  MOVER   : "); stdscr.addstr(s, curses.color_pair(c))
        stdscr.addstr(5, 2, f"  TIMER   : {tim_state}")

        stdscr.addstr(7, 0, "PCAP:")
        stdscr.addstr(8, 2, f"  Buffer count: {buff_count:<5} (dir: {BUFF_DIR})")
        stdscr.addstr(10,2, f"  Mover log: {MGR_LOG_HINT}")

        stdscr.addstr(3, left_w+2, "[1] Stop All")
        stdscr.addstr(4, left_w+2, "[2] Clear PCAPs")
        stdscr.addstr(5, left_w+2, "[3] Start/Restart")
        stdscr.addstr(8, left_w+2, "[+] Faster  [-] Slower")
        stdscr.addstr(9, left_w+2, "[c] Capture Logs")
        stdscr.addstr(10,left_w+2, "[m] Mover Logs")
        stdscr.addstr(11,left_w+2, "[s] Service Status  [q] Quit")

        divider(stdscr, 12, w)
        draw_text(stdscr, 13, 0, w, f"Input: {last_key}")
        stdscr.refresh()

        t_end = time.time() + REFRESH
        while time.time() < t_end:
            try: ch = stdscr.getch()
            except curses.error: ch = -1
            if ch == -1: time.sleep(0.02); continue
            if ch in (ord('q'), ord('Q')): return
            last_key = chr(ch) if 32 <= ch < 127 else f"[{ch}]"

            if ch == ord('1'):
                act_stop()
            elif ch == ord('2'):
                act_clear(BUFF_DIR)
            elif ch == ord('3'):
                act_start()
            elif ch == ord('+'):
                REFRESH = round(REFRESH + 0.5, 1)
            elif ch == ord('-'):
                REFRESH = round(max(0.5, REFRESH - 0.5), 1)
            elif ch in (ord('c'), ord('C')):
                curses.def_prog_mode(); curses.endwin()
                os.system(f"journalctl -u {shlex.quote(CAPTURE_SERVICE)} -n 400 --no-pager | less -SRX")
                curses.reset_prog_mode()
            elif ch in (ord('m'), ord('M')):
                curses.def_prog_mode(); curses.endwin()
                os.system(f"journalctl -u {shlex.quote(MOVER_SERVICE)} -n 400 --no-pager | less -SRX")
                curses.reset_prog_mode()
            elif ch in (ord('s'), ord('S')):
                curses.def_prog_mode(); curses.endwin()
                units = " ".join([shlex.quote(CAPTURE_SERVICE), shlex.quote(MOVER_SERVICE)] + ([shlex.quote(MOVER_TIMER)] if MOVER_TIMER else []))
                os.system(f"systemctl status {units} --no-pager -l | less -SRX")
                curses.reset_prog_mode()
            break

def main(): curses.wrapper(render)
if __name__ == "__main__": main()
