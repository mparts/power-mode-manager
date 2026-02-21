#!/usr/bin/env bash
# =============================================================================
# Startup Log Viewer
# =============================================================================
# Shows startup logs and exits on Enter (CURRENTLY DISABLED - causes hangs)
# =============================================================================

STARTUP_LOG="$HOME/.local/share/power_modes/startup.log"

if [ ! -f "$STARTUP_LOG" ]; then
    echo "No startup log found at: $STARTUP_LOG"
    exit 1
fi

echo "=== Power Mode Startup Log ==="
echo "Press Enter to close..."
echo ""

# Show log with tail -f, but kill it when user presses Enter
tail -f "$STARTUP_LOG" &
TAIL_PID=$!

# Wait for Enter key
read -r

# Kill tail process
kill $TAIL_PID 2>/dev/null

exit 0
