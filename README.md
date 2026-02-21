# Power Mode Manager

Automatically applies power-saving or performance settings based on whether your laptop is plugged into AC power or running on battery. Runs silently in the background from login and reacts instantly when you plug or unplug the charger.

---

## What it does

- **Plugged in (AC):** switches to a performance power profile, high refresh rate (e.g. 165Hz), full brightness, Bluetooth on, and keyboard backlight on.
- **On battery:** switches to a power-saver profile, lower refresh rate (e.g. 60Hz), reduced brightness, Bluetooth off, and keyboard backlight off.
- **Monitors continuously** for plug/unplug events and re-applies settings automatically (no reboot or manual action needed).
- **Sends a desktop notification** when a mode switch completes.
- **Logs every action** to `~/.local/share/power_modes/`, with automatic rotation so logs don't grow forever.

---

## Requirements

- Linux with a Cinnamon desktop (or any X11 desktop — Cinnamon-specific features like screensaver will just skip gracefully on others)
- `bash` 4+
- `xrandr` — for refresh rate and brightness control
- `powerprofilesctl` — for CPU power profile switching (part of `power-profiles-daemon`)
- `rfkill` — for Bluetooth control (usually pre-installed)
- `pactl` — for audio control (part of `pulseaudio-utils` or `pipewire-pulse`)
- `notify-send` — for desktop notifications (part of `libnotify-bin`)
- `gsettings` — for Cinnamon screensaver settings (pre-installed with Cinnamon)

Install missing dependencies on Ubuntu/Mint:

```bash
sudo apt install power-profiles-daemon libnotify-bin pulseaudio-utils
```

---

## File structure

```
~/bin/power_mode_manager/
├── power_mode.sh              # Main script — applies settings based on AC state
├── power_mode_startup.sh      # Startup wrapper — runs once at boot, then monitors
├── capture_startup_errors.sh  # Captures system/Cinnamon errors at startup
└── view_startup_log.sh        # Helper to view the startup log interactively

~/.config/
├── plugged_mode.conf          # Settings for AC/plugged-in mode
└── battery_mode.conf          # Settings for battery mode

~/.local/share/power_modes/
├── monitor.log                # Continuous log of all events and mode switches (last 500 lines)
├── startup.log                # Log of startup-phase output (last 500 lines)
├── plugged_mode.log           # Log from the most recent plugged-mode run
└── battery_mode.log           # Log from the most recent battery-mode run
```

---

## Installation

Run the install script:

```bash
bash install.sh
```

Then **log out and back in** (or reboot) for the autostart entry to take effect.

See [install.sh](install.sh) for exactly what it does before running it.

---

## Configuration

Edit `~/.config/plugged_mode.conf` and `~/.config/battery_mode.conf` after installation. The most common settings to adjust:

| Setting | Description | Example |
|---|---|---|
| `REFRESH_RATE` | Target display refresh rate in Hz | `165` / `60` |
| `SCREEN_BRIGHTNESS` | Display brightness, 0–100% | `100` / `50` |
| `POWER_PROFILE` | CPU profile (`performance`, `balanced`, `power-saver`) | `performance` |
| `BLUETOOTH_ON` / `BLUETOOTH_OFF` | Set one to `1`, the other to `0` | |
| `SINK_VOLUME` | System volume (pactl format) | `80%` / `0%` |
| `MIC_MUTE` | `1` = muted, `0` = unmuted | `1` |
| `KBD_BACKLIGHT_LEVEL` | Keyboard backlight brightness (0 = off) | `1` / `0` |
| `SCREENSAVER_MODE` | `cinnamon` or `xscreensaver` | `cinnamon` |

To enable GPU switching via `prime-select` (disabled by default), set `ENABLE_GPU_SWITCH=1` in `power_mode.sh` and configure `GPU_MODE` in each `.conf` file.

---

## How autostart works

The install script creates an entry in `~/.config/autostart/` that launches `power_mode_startup.sh` at login. This script:

1. Rotates logs (keeping the last 500 lines of `monitor.log` and `startup.log`).
2. Captures any Cinnamon/systemd startup errors to `startup.log`.
3. Runs `power_mode.sh` once immediately to apply the correct settings for the current AC state.
4. Enters a monitoring loop, checking the AC adapter state every 3 seconds and re-running `power_mode.sh` whenever it changes.

The monitoring loop runs for the duration of your session and exits when you log out.

---

## Viewing logs

```bash
# Live monitor log
tail -f ~/.local/share/power_modes/monitor.log

# Last plugged-mode run
cat ~/.local/share/power_modes/plugged_mode.log

# Last battery-mode run
cat ~/.local/share/power_modes/battery_mode.log

# Startup log (interactive viewer)
bash ~/bin/power_mode_manager/view_startup_log.sh
```

---

## Uninstall

```bash
rm -rf ~/bin/power_mode_manager
rm -f ~/.config/plugged_mode.conf ~/.config/battery_mode.conf
rm -f ~/.config/autostart/power_mode_manager.desktop
rm -rf ~/.local/share/power_modes
```
