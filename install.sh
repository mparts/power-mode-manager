#!/usr/bin/env bash
# =============================================================================
# Power Mode Manager - Installer
# =============================================================================
set -euo pipefail

INSTALL_DIR="$HOME/bin/power_mode_manager"
CONFIG_DIR="$HOME/.config"
AUTOSTART_DIR="$HOME/.config/autostart"
LOG_DIR="$HOME/.local/share/power_modes"

SCRIPTS=(
  "power_mode.sh"
  "power_mode_startup.sh"
  "capture_startup_errors.sh"
  "view_startup_log.sh"
)

CONFIGS=(
  "plugged_mode.conf"
  "battery_mode.conf"
)

echo "============================================="
echo " Power Mode Manager - Installer"
echo "============================================="
echo ""
echo "This will:"
echo "  - Copy scripts to:       $INSTALL_DIR"
echo "  - Copy config files to:  $CONFIG_DIR"
echo "  - Create log directory:  $LOG_DIR"
echo "  - Create autostart entry in $AUTOSTART_DIR"
echo ""
read -rp "Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# -------------------------
# Create directories
# -------------------------
echo ""
echo "[1/4] Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$AUTOSTART_DIR"
mkdir -p "$LOG_DIR"

# -------------------------
# Copy scripts
# -------------------------
echo "[2/4] Installing scripts..."
for script in "${SCRIPTS[@]}"; do
  if [ ! -f "$script" ]; then
    echo "  ERROR: $script not found in current directory. Aborting."
    exit 1
  fi
  cp "$script" "$INSTALL_DIR/$script"
  chmod +x "$INSTALL_DIR/$script"
  echo "  Installed: $INSTALL_DIR/$script"
done

# -------------------------
# Copy configs (don't overwrite existing ones)
# -------------------------
echo "[3/4] Installing config files..."
for conf in "${CONFIGS[@]}"; do
  if [ ! -f "$conf" ]; then
    echo "  WARNING: $conf not found in current directory, skipping."
    continue
  fi
  dest="$CONFIG_DIR/$conf"
  if [ -f "$dest" ]; then
    echo "  SKIPPED (already exists): $dest"
    echo "  -> To reinstall: rm $dest && bash install.sh"
  else
    cp "$conf" "$dest"
    echo "  Installed: $dest"
  fi
done

# -------------------------
# Create autostart .desktop entry
# -------------------------
echo "[4/4] Creating autostart entry..."
DESKTOP_FILE="$AUTOSTART_DIR/power_mode_manager.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Power Mode Manager
Comment=Applies power settings based on AC/battery state
Exec=$INSTALL_DIR/power_mode_startup.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

echo "  Created: $DESKTOP_FILE"

# -------------------------
# Done
# -------------------------
echo ""
echo "============================================="
echo " Installation complete!"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Edit your config files if needed:"
echo "       $CONFIG_DIR/plugged_mode.conf"
echo "       $CONFIG_DIR/battery_mode.conf"
echo ""
echo "  2. Log out and back in (or reboot) to activate."
echo ""
echo "  3. Check logs at any time:"
echo "       tail -f $LOG_DIR/monitor.log"
echo ""
