#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Power Mode Manager - Main Script
# =============================================================================
# Applies power-saving or performance settings based on AC adapter state
# =============================================================================

# -------------------------
# GPU switching toggle
# -------------------------
ENABLE_GPU_SWITCH=0   # 1 = enable prime-select, 0 = skip GPU changes

# -------------------------
# Detect AC state
# -------------------------
AC_CANDIDATES=(
  "/sys/class/power_supply/ADP0/online"
  "/sys/class/power_supply/AC/online"
  "/sys/class/power_supply/AC0/online"
  "/sys/class/power_supply/ACAD/online"
  "/sys/class/power_supply/ACPI/online"
)

AC_STATUS_FILE=""
for f in "${AC_CANDIDATES[@]}"; do
  [ -f "$f" ] && AC_STATUS_FILE="$f" && break
done

if [ -z "$AC_STATUS_FILE" ]; then
  AC_STATE="0"
else
  AC_STATE=$(cat "$AC_STATUS_FILE")
fi

# -------------------------
# Load config
# -------------------------
if [ "$AC_STATE" = "1" ]; then
  CONFIG_FILE="$HOME/.config/plugged_mode.conf"
else
  CONFIG_FILE="$HOME/.config/battery_mode.conf"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

source "$CONFIG_FILE"

mkdir -p "$(dirname "$LOG_FILE")"

rotate_log() {
  local file="$1"
  local max_lines="$2"
  if [ -f "$file" ] && [ "$(wc -l < "$file")" -gt "$max_lines" ]; then
    local tmp
    tmp=$(mktemp)
    tail -n "$max_lines" "$file" > "$tmp" && mv "$tmp" "$file"
  fi
}

# Rotate mode-specific log before appending this session (keep last 200 lines)
rotate_log "$LOG_FILE" 200
: > "$LOG_FILE"

# Startup mode flag and startup log
STARTUP_LOG="$HOME/.local/share/power_modes/startup.log"
IS_STARTUP_MODE="${STARTUP_MODE:-0}"

# -------------------------
# Logging
# -------------------------
log() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
  
  # Also write to startup log if this is startup mode
  if [ "$IS_STARTUP_MODE" = "1" ]; then
    echo "$msg" >> "$STARTUP_LOG"
  fi
}

notify() {
  notify-send -r "${NOTIFY_ID:-0}" -u low -t 4000 -i "${NOTIFY_ICON:-dialog-information}" \
    "${NOTIFY_TITLE:-Power Mode}" "$1" 2>/dev/null || true
}

# -------------------------
# Wait for desktop readiness
# -------------------------
wait_for_desktop() {
  local max_wait=15
  local waited=0
  log "Waiting for desktop readiness (up to ${max_wait}s)..."
  
  while [ $waited -lt $max_wait ]; do
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      if command -v gsettings >/dev/null 2>&1; then
        if gsettings get org.cinnamon.desktop.interface scaling-factor >/dev/null 2>&1; then
          log "Desktop ready after ${waited}s (Cinnamon detected)"
          return 0
        fi
      fi
      # Fallback: if dbus is up for 5s, assume desktop is ready
      if [ $waited -ge 5 ]; then
        log "Desktop assumed ready after ${waited}s (DBUS active)"
        return 0
      fi
    fi
    sleep 1
    waited=$((waited + 1))
  done
  
  log "Desktop readiness timeout; continuing anyway"
}

# -------------------------
# GPU switching (optional, startup only)
# -------------------------
maybe_set_gpu_mode() {
  if [ "${ENABLE_GPU_SWITCH:-0}" -ne 1 ]; then
    log "GPU switching disabled"
    return
  fi
  
  if ! command -v prime-select >/dev/null 2>&1; then
    log "prime-select not found; skipping GPU mode change"
    return
  fi
  
  # GPU switching should only run at startup, not during mode switches
  if [ "${IS_STARTUP_MODE:-0}" -ne 1 ]; then
    log "GPU switching only runs at startup; skipping"
    return
  fi
  
  log "Setting GPU mode to $GPU_MODE (via pkexec)"
  if pkexec /usr/bin/prime-select "$GPU_MODE" >> "$LOG_FILE" 2>&1; then
    log "GPU mode set to $GPU_MODE. Reboot required for changes to take effect."
  else
    log "prime-select failed"
  fi
}

# -------------------------
# Power profile
# -------------------------
apply_power_profile() {
  if command -v powerprofilesctl >/dev/null 2>&1; then
    log "Setting power profile to $POWER_PROFILE"
    powerprofilesctl set "$POWER_PROFILE" >> "$LOG_FILE" 2>&1 || log "powerprofilesctl failed"
  else
    log "powerprofilesctl not found; skipping power profile"
  fi
}

# -------------------------
# Screen Brightness (External Display - xrandr)
# -------------------------
apply_brightness() {
  # Skip if SCREEN_BRIGHTNESS not set in config
  if [ -z "${SCREEN_BRIGHTNESS:-}" ]; then
    log "No screen brightness setting in config, skipping"
    return 0
  fi

  log "Setting screen brightness to ${SCREEN_BRIGHTNESS}%"

  # For external displays, use xrandr brightness
  if ! command -v xrandr >/dev/null 2>&1; then
    log "WARNING: xrandr not found, cannot set brightness"
    return 0
  fi

  # Get the connected display
  local output
  output=$(xrandr --query 2>/dev/null | grep " connected" | grep -v "disconnected" | head -n1 | awk '{print $1}')
  
  if [ -z "$output" ]; then
    log "WARNING: No connected display found for brightness control"
    return 0
  fi

  # Convert percentage to decimal (0-100 -> 0.0-1.0)
  # Force C locale to ensure period as decimal separator (not comma)
  local brightness_decimal
  brightness_decimal=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", ${SCREEN_BRIGHTNESS} / 100}")
  
  log "Setting brightness via xrandr: output=$output, brightness=$brightness_decimal (${SCREEN_BRIGHTNESS}%)"
  
  if xrandr --output "$output" --brightness "$brightness_decimal" >> "$LOG_FILE" 2>&1; then
    log "SUCCESS: Brightness set to ${SCREEN_BRIGHTNESS}% via xrandr"
    return 0
  else
    log "WARNING: xrandr brightness command failed"
    log "Note: External displays may not support software brightness control"
    return 0
  fi
}

# -------------------------
# Refresh rate
# -------------------------
apply_refresh_rate() {
  if ! command -v xrandr >/dev/null 2>&1; then
    log "xrandr not found, skipping refresh rate change"
    return 1
  fi

  # Wait for X to be ready and stable
  log "Waiting for X server stability (3 seconds)..."
  sleep 3

  # Detect output and mode automatically
  local output mode
  output=$(xrandr --query 2>/dev/null | grep " connected" | grep -v "disconnected" | head -n1 | awk '{print $1}')
  mode=$(xrandr --query 2>/dev/null | grep '\*' | head -n1 | awk '{print $1}')
  
  if [ -z "$output" ] || [ -z "$mode" ]; then
    log "ERROR: Could not detect display output or mode"
    return 1
  fi
  
  local desired_rate="${REFRESH_RATE}"
  
  # Get current state before change
  local before_state
  before_state=$(xrandr --query 2>/dev/null | grep "^   ${mode}" | head -n1 || echo "unknown")
  log "Before: $before_state"
  
  log "Setting refresh rate to ${desired_rate}Hz on ${output}"
  log "Command: xrandr --output ${output} --mode ${mode} --rate ${desired_rate}"
  
  # Apply the change
  if xrandr --output "${output}" --mode "${mode}" --rate "${desired_rate}" >> "$LOG_FILE" 2>&1; then
    log "xrandr command executed successfully"
    
    # Wait for the change to take effect
    sleep 2
    
    # Verify the change
    local after_state
    after_state=$(xrandr --query 2>/dev/null | grep "^   ${mode}" | head -n1 || echo "unknown")
    log "After: $after_state"
    
    # Check which rate has the asterisk (current)
    if echo "$after_state" | grep -q "${desired_rate}\.00.*\*"; then
      log "SUCCESS: Refresh rate verified at ${desired_rate}Hz"
      return 0
    elif echo "$after_state" | grep -q "${desired_rate}.*\*"; then
      log "SUCCESS: Refresh rate verified at ${desired_rate}Hz"
      return 0
    else
      log "WARNING: Refresh rate may not have changed"
      return 1
    fi
  else
    log "ERROR: xrandr command failed"
    return 1
  fi
}

# -------------------------
# Screensaver/Lock Screen Management
# -------------------------
apply_screensaver() {
 local mode="${SCREENSAVER_MODE:-cinnamon}"
 
 log "Setting screensaver mode to: $mode"
 
 if [ "$mode" = "xscreensaver" ]; then
   # Fancy animations for AC power
   if command -v xscreensaver >/dev/null 2>&1; then
     log "Enabling xscreensaver (fancy animations)"
     
     # Disable Cinnamon screensaver FIRST
     if command -v gsettings >/dev/null 2>&1; then
       gsettings set org.cinnamon.desktop.screensaver lock-enabled false >> "$LOG_FILE" 2>&1
       gsettings set org.cinnamon.desktop.screensaver idle-activation-enabled false >> "$LOG_FILE" 2>&1
     fi
     
     # Kill existing xscreensaver if running
     pkill xscreensaver 2>/dev/null || true
     sleep 1
     
     # Start xscreensaver daemon
     xscreensaver -nosplash >> "$LOG_FILE" 2>&1 &
     
     log "xscreensaver enabled, Cinnamon screensaver disabled"
   else
     log "WARNING: xscreensaver not installed"
   fi
   
 elif [ "$mode" = "cinnamon" ]; then
   # Battery-friendly Cinnamon lock
   log "Enabling Cinnamon screensaver (battery mode)"
   
   # Kill xscreensaver if running
   if command -v xscreensaver-command >/dev/null 2>&1; then
     xscreensaver-command -exit >> "$LOG_FILE" 2>&1 || true
   fi
   pkill xscreensaver 2>/dev/null || true
   
   # Enable Cinnamon screensaver
   if command -v gsettings >/dev/null 2>&1; then
     gsettings set org.cinnamon.desktop.screensaver lock-enabled true >> "$LOG_FILE" 2>&1
     gsettings set org.cinnamon.desktop.screensaver idle-activation-enabled true >> "$LOG_FILE" 2>&1
     gsettings set org.cinnamon.desktop.session idle-delay 300 >> "$LOG_FILE" 2>&1
   fi
   
   log "Cinnamon screensaver enabled, xscreensaver disabled"
 else
   log "WARNING: Unknown screensaver mode: $mode"
 fi
}

# -------------------------
# Bluetooth
# -------------------------
apply_bluetooth() {
  if command -v rfkill >/dev/null 2>&1; then
    if [ "${BLUETOOTH_ON:-0}" -eq 1 ]; then
      log "Unblocking Bluetooth"
      rfkill unblock bluetooth >> "$LOG_FILE" 2>&1
    elif [ "${BLUETOOTH_OFF:-0}" -eq 1 ]; then
      log "Blocking Bluetooth"
      rfkill block bluetooth >> "$LOG_FILE" 2>&1
    fi
  else
    log "rfkill not found; skipping bluetooth control"
  fi
}

# -------------------------
# Audio
# -------------------------
set_system_volume() {
  if command -v pactl >/dev/null 2>&1; then
    log "Setting system volume to ${SINK_VOLUME}"
    pactl set-sink-volume @DEFAULT_SINK@ "${SINK_VOLUME}" >> "$LOG_FILE" 2>&1
  else
    log "pactl not found; skipping volume control"
  fi
}

set_mic_mute() {
  if command -v pactl >/dev/null 2>&1; then
    if [ "${MIC_MUTE:-0}" -eq 1 ]; then
      log "Muting microphone"
      pactl set-source-mute @DEFAULT_SOURCE@ 1 >> "$LOG_FILE" 2>&1
    else
      log "Unmuting microphone"
      pactl set-source-mute @DEFAULT_SOURCE@ 0 >> "$LOG_FILE" 2>&1
    fi
  else
    log "pactl not found; skipping microphone control"
  fi
}

# -------------------------
# Keyboard backlight
# -------------------------
set_kbd_backlight_level() {
  local level="$1"
  local led
  led=$(ls /sys/class/leds 2>/dev/null | grep -i 'kbd_backlight' | head -n1 || true)
  
  if [ -n "$led" ]; then
    log "Setting keyboard backlight to ${level}"
    echo "${level}" > "/sys/class/leds/${led}/brightness" 2>>"$LOG_FILE" || \
      log "Failed to set keyboard backlight (may need sudo/udev rules)"
  else
    log "No keyboard backlight device found"
  fi
}

# -------------------------
# Services
# -------------------------
manage_services() {
  for svc in "${SERVICES_TO_STOP[@]}"; do
    log "Stopping service: $svc"
    systemctl --user stop "$svc" >> "$LOG_FILE" 2>&1 || true
  done
  for svc in "${SERVICES_TO_START[@]}"; do
    log "Starting service: $svc"
    systemctl --user start "$svc" >> "$LOG_FILE" 2>&1 || true
  done
}

# -------------------------
# Main sequence
# -------------------------
log "================================="
log "Power Mode Manager"
log "AC_STATE=${AC_STATE}"
log "Config: $CONFIG_FILE"
log "Target refresh rate: ${REFRESH_RATE}Hz"
log "Target brightness: ${SCREEN_BRIGHTNESS:-not set}%"
log "================================="

# GPU switching (startup only, doesn't need desktop)
maybe_set_gpu_mode

# Wait for desktop to be ready
wait_for_desktop

# Apply settings in safe order
apply_power_profile
apply_refresh_rate              # Set refresh rate first
#apply_screensaver               # Screensaver daemon
# sleep 0.5                       # Let screensaver settle
apply_brightness                # Brightness AFTER refresh rate (prevents reset)
apply_bluetooth
set_system_volume
set_mic_mute
set_kbd_backlight_level "${KBD_BACKLIGHT_LEVEL:-0}"
manage_services

log "================================="
log "Power mode settings applied."
log "================================="

# Final notification (only one)
notify "Power mode applied"

# Optional completion sound
if [ -n "${SOUND:-}" ] && command -v paplay >/dev/null 2>&1; then
  paplay "$SOUND" >/dev/null 2>&1 || true
fi

exit 0
