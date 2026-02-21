#!/usr/bin/env bash
# =============================================================================
# Power Mode Startup Wrapper
# =============================================================================
# Runs power_mode.sh once at boot, then monitors AC state every 3 seconds
# =============================================================================

SCRIPT_DIR="$HOME/bin/power_mode_manager"
POWER_MODE_SCRIPT="$SCRIPT_DIR/power_mode.sh"
AC_STATUS_FILE="/sys/class/power_supply/ADP0/online"
CHECK_INTERVAL=3
LOG_FILE="$HOME/.local/share/power_modes/monitor.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

rotate_log() {
    local file="$1"
    local max_lines="$2"
    if [ -f "$file" ] && [ "$(wc -l < "$file")" -gt "$max_lines" ]; then
        local tmp
        tmp=$(mktemp)
        tail -n "$max_lines" "$file" > "$tmp" && mv "$tmp" "$file"
    fi
}

# Rotate monitor log before this session starts (keep last 500 lines)
rotate_log "$LOG_FILE" 500

# Rotate startup log before this session starts (keep last 500 lines)
STARTUP_LOG_PATH="$HOME/.local/share/power_modes/startup.log"
rotate_log "$STARTUP_LOG_PATH" 500

# Capture system startup errors FIRST
if [ -x "$SCRIPT_DIR/capture_startup_errors.sh" ]; then
    "$SCRIPT_DIR/capture_startup_errors.sh"
fi

# Run power mode script once at startup
log "Starting power mode manager"
log "Running initial power mode setup..."
if [ -x "$POWER_MODE_SCRIPT" ]; then
    STARTUP_MODE=1 "$POWER_MODE_SCRIPT" >> "$LOG_FILE" 2>&1
else
    log "ERROR: Power mode script not found: $POWER_MODE_SCRIPT"
    exit 1
fi

# Get initial AC state
LAST_STATE=$(cat "$AC_STATUS_FILE" 2>/dev/null || echo "unknown")
log "Initial AC state: $LAST_STATE (1=plugged, 0=battery)"

# Monitor for AC state changes
log "Monitoring for AC plug/unplug events..."
while true; do
    sleep "$CHECK_INTERVAL"
    
    CURRENT_STATE=$(cat "$AC_STATUS_FILE" 2>/dev/null || echo "unknown")
    
    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        if [ "$CURRENT_STATE" = "1" ]; then
            log "AC PLUGGED IN - switching to performance mode"
        else
            log "AC UNPLUGGED - switching to battery mode"
        fi
        
        # Run power mode script (NOT startup mode)
        "$POWER_MODE_SCRIPT" >> "$LOG_FILE" 2>&1 &
        
        LAST_STATE="$CURRENT_STATE"
    fi
done
