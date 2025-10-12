#!/usr/bin/env python3
"""
Req3 — Move oldest closed PCAP from ring -> dest when count >= threshold.
- "Closed" = file mtime older than QUIET_SECS (not being written).
- Writes a simple log line to mover_log.
"""

import time, yaml, shutil
from pathlib import Path

CFG = yaml.safe_load(open("/opt/seer/etc/seer.yml"))
RING = Path(CFG["ring_dir"])
DEST = Path(CFG["dest_dir"])
THRESH = int(CFG["buffer_threshold"])
LOGPATH = Path(CFG["mover_log"])
QUIET_SECS = 3  # consider file closed if not touched for >= 3s

def log(msg: str):
    LOGPATH.parent.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    with open(LOGPATH, "a") as f:
        f.write(f"{ts} {msg}\n")

def closed(p: Path) -> bool:
    try:
        age = time.time() - p.stat().st_mtime
        return age >= QUIET_SECS
    except FileNotFoundError:
        return False

def pick_oldest_closed():
    files = [p for p in RING.glob("*.pcap") if p.is_file()]
    files.sort(key=lambda p: p.stat().st_mtime)
    for p in files:
        if closed(p):
            return p
    return None

def main():
    RING.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True, exist_ok=True)

    files = [p for p in RING.glob("*.pcap") if p.is_file()]
    count = len(files)
    if count < THRESH:
        log(f"[noop] ring has {count} files (< threshold {THRESH})")
        return

    target = pick_oldest_closed()
    if not target:
        log("[noop] no closed file to move")
        return

    dest_path = DEST / target.name
    try:
        shutil.move(str(target), str(dest_path))  # atomic within same filesystem; otherwise copy+unlink
        log(f"[moved] {target} -> {dest_path}")
    except Exception as e:
        log(f"[error] move {target} -> {dest_path}: {e}")

if __name__ == "__main__":
    main()
