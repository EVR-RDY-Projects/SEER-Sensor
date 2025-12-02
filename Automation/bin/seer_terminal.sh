
#!/usr/bin/env bash
# seer_terminal.sh
# Lightweight terminal wrapper to run the curses-based SEER console in a TTY.
# Enhancements:
# - auto-detect terminal color capability and set SEER_THEME (evr|classic)
# - accept --theme=evr|classic to override detection
# - still passes all args through to the Python console

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSOLE_PY="$SCRIPT_DIR/seer_console.py"

if [ ! -f "$CONSOLE_PY" ]; then
  echo "ERROR: cannot find $CONSOLE_PY" >&2
  exit 2
fi

# Parse an optional --theme argument (simple parsing)
THEME_ARG=""
REST_ARGS=()
for a in "$@"; do
  case "$a" in
    --theme=*) THEME_ARG="${a#--theme=}" ;;
    --theme) shift; THEME_ARG="$1" ;;
    *) REST_ARGS+=("$a") ;;
  esac
done

# If env SEER_THEME is already set, respect it unless user passed --theme
if [ -n "${THEME_ARG}" ]; then
  SEER_THEME="$THEME_ARG"
elif [ -n "${SEER_THEME:-}" ]; then
  SEER_THEME="$SEER_THEME"
else
  # auto-detect using tput if available
  if command -v tput >/dev/null 2>&1; then
    COLORS=$(tput colors 2>/dev/null || echo 0)
  else
    COLORS=0
  fi
  # heuristic: prefer 'evr' when terminal supports at least 16 colors
  if [ "$COLORS" -ge 16 ]; then
    SEER_THEME=evr
  else
    SEER_THEME=classic
  fi
fi

export SEER_THEME

# If the caller asked to disable colors, propagate NO_COLORS
if [ "${NO_COLORS:-}" = "1" ] || [ "${NO_COLORS:-}" = "true" ]; then
  export NO_COLORS=1
fi

exec python3 "$CONSOLE_PY" "${REST_ARGS[@]:-}"
