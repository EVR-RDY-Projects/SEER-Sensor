# Terminal console launcher

Use the terminal wrapper to run the curses-based SEER console directly from a terminal session.

Run one-shot status (no extra deps):

```bash
python3 Automation/bin/seer_terminal.sh --once
```

Run interactive console (in a TTY):

```bash
python3 Automation/bin/seer_terminal.sh
```

Theme auto-detection and override
- The wrapper auto-detects terminal color capability (via `tput colors`) and sets `SEER_THEME` accordingly.
- You can explicitly choose a theme:

```bash
# explicit theme
python3 Automation/bin/seer_terminal.sh --theme=evr
python3 Automation/bin/seer_terminal.sh --theme=classic

# or set environment variable
SEER_THEME=evr python3 Automation/bin/seer_terminal.sh
```

Notes:
- If the interactive console needs elevated privileges to manage captures, run it under sudo:

```bash
sudo -E python3 Automation/bin/seer_terminal.sh
```

- To make this easier for operators, you can symlink the wrapper to `/usr/local/bin/seer-terminal`:

```bash
sudo ln -sf $(realpath Automation/bin/seer_terminal.sh) /usr/local/bin/seer-terminal
sudo chmod +x /usr/local/bin/seer-terminal
```
