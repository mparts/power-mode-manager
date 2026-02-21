#!/usr/bin/env bash
# =============================================================================
# Capture Cinnamon/System Startup Errors
# =============================================================================

STARTUP_LOG="$HOME/.local/share/power_modes/startup.log"
mkdir -p "$(dirname "$STARTUP_LOG")"

echo "=== System Startup Errors ($(date +'%Y-%m-%d %H:%M:%S')) ===" > "$STARTUP_LOG"

# Capture recent systemd errors
if command -v journalctl >/dev/null 2>&1; then
    echo "" >> "$STARTUP_LOG"
    echo "--- Systemd Errors (last 5 minutes) ---" >> "$STARTUP_LOG"
    journalctl --user --since "5 minutes ago" --priority err -q >> "$STARTUP_LOG" 2>&1 || echo "No systemd errors" >> "$STARTUP_LOG"
fi

# Capture Cinnamon errors from .xsession-errors
if [ -f "$HOME/.xsession-errors" ]; then
    echo "" >> "$STARTUP_LOG"
    echo "--- Recent Xsession Errors ---" >> "$STARTUP_LOG"
    tail -n 50 "$HOME/.xsession-errors" | grep -i "error\|warning\|fail" >> "$STARTUP_LOG" 2>&1 || echo "No xsession errors" >> "$STARTUP_LOG"
fi

echo "" >> "$STARTUP_LOG"
echo "=== Power Mode Startup Logs ===" >> "$STARTUP_LOG"
