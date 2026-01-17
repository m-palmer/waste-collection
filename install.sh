#!/usr/bin/env bash
#
# Waste Collection Display - Installer
#
# Run with:
#   sudo ./install.sh
#
# What this script does (high level):
#  - Logs everything to waste-collection-install.log (next to this script)
#  - Enables SPI and I2C (via raspi-config, if available)
#  - Sets console-only boot with autologin (via raspi-config, if available)
#  - Sets hostname to "waste-collection" and updates /etc/hosts safely
#  - Installs Python deps + Playwright + Chromium
#  - Disables optional background services (only if present)
#  - Removes default home folders (Desktop, Documents, etc.) only if EMPTY
#
# Safety:
#  - You must type exactly: Yes
#    or the script exits without making changes.
#
# Note:
#  - A reboot is recommended at the end.

set -euo pipefail

# -----------------------------
# Logging
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${SCRIPT_DIR}/waste-collection-install.log"

# Log everything (stdout + stderr) to console and file
exec > >(tee -a "$LOGFILE") 2>&1

log() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  log "[X] $*"
  exit 1
}

# -----------------------------
# Root check
# -----------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "Please run with sudo: sudo ./install.sh"
fi

log "[*] Starting install"
log "[*] Log file: $LOGFILE"

# -----------------------------
# Confirmation gate (must type Yes)
# -----------------------------
cat <<'EOF'

============================================================
Waste Collection Display Installer

This script WILL make changes to your Raspberry Pi, including:
  1) Enabling SPI and I2C (if raspi-config is available)
  2) Switching boot to console autologin (no desktop GUI)
  3) Changing hostname to: waste-collection
     - and updating /etc/hosts
  4) Installing packages:
     - python3-pip, python3-pil, python3-numpy, python3-gpiozero
     - pip installs: spidev, playwright (with --break-system-packages)
     - Playwright installs: chromium
  5) Disabling services (only if present), including:
     - bluetooth, cups, avahi, rpcbind, etc.
  6) Removing default home folders ONLY if empty:
     - Desktop, Documents, Downloads, Music, Pictures, Public, Templates, Videos

A reboot is recommended after completion.

Warning this script is known to crash (sometimes even the OS when installing 
chromium/Playwright. If it does, run it again!

To continue, type exactly: Yes
Anything else will cancel.
============================================================

EOF

read -r -p "Type Yes to continue: " CONFIRM
log "Confirmation entered: $CONFIRM"

if [[ "$CONFIRM" != "Yes" ]]; then
  die "Cancelled by user (did not type exactly: Yes)"
fi

log "[✓] Confirmation received. Proceeding..."

# -----------------------------
# systemd helpers
# -----------------------------
unit_exists() {
  systemctl list-unit-files --no-pager 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

disable_and_stop() {
  local unit="$1"
  if unit_exists "$unit"; then
    systemctl stop "$unit" 2>/dev/null || true
    systemctl disable "$unit" 2>/dev/null || true
    log "  - Disabled $unit"
  else
    log "  - $unit not present (skipped)"
  fi
}

# -----------------------------
# 1) Hardware interfaces
# -----------------------------
log "[1/6] Enabling hardware interfaces..."

if command -v raspi-config >/dev/null 2>&1; then
  log " -> Enabling SPI"
  raspi-config nonint do_spi 0

  log " -> Enabling I2C"
  raspi-config nonint do_i2c 0

  log " -> SPI and I2C enabled"
else
  log " -> raspi-config not found; skipped"
fi

# -----------------------------
# 2) Boot behaviour
# -----------------------------
log "[2/6] Setting console-only boot..."

if command -v raspi-config >/dev/null 2>&1; then
  # B1 = Console Autologin
  raspi-config nonint do_boot_behaviour B1
  log " -> Console autologin enabled"
else
  log " -> raspi-config not found; skipped"
fi

# -----------------------------
# 3) Hostname
# -----------------------------
log "[3/6] Setting hostname..."

NEW_HOSTNAME="waste-collection"
hostnamectl set-hostname "$NEW_HOSTNAME"

# Update /etc/hosts safely (idempotent)
if grep -q "^127.0.1.1" /etc/hosts; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
else
  echo -e "127.0.1.1\t$NEW_HOSTNAME" >> /etc/hosts
fi

log " -> Hostname set to $NEW_HOSTNAME"

# -----------------------------
# 4) Python + Playwright
# -----------------------------
log "[4/6] Installing dependencies..."

log " -> apt-get update"
apt-get update -y

log " -> Installing system packages"
apt-get install -y \
  python3-pip \
  python3-pil \
  python3-numpy \
  python3-gpiozero

log " -> Installing spidev via pip (PEP 668 override)"
python3 -m pip install --break-system-packages spidev

log " -> Installing Playwright via pip (PEP 668 override)"
python3 -m pip install --break-system-packages playwright

log " -> Installing Chromium for Playwright"
python3 -m playwright install chromium

log " -> Python and Playwright ready"

# -----------------------------
# 5) Disable services
# -----------------------------
log "[5/6] Disabling unused services..."

SERVICES=(
  wayvnc-control
  bluetooth
  cups
  cups-browsed
  cups.path
  ModemManager
  glamor-test
  rp1-test
  avahi-daemon
  avahi-daemon.socket
  udisks2
  nfs-blkmap
  rpcbind.socket
  rpcbind.service
  serial-getty@ttyAMA0
)

for svc in "${SERVICES[@]}"; do
  disable_and_stop "$svc"
done

# -----------------------------
# 6) Remove unused home folders (empty only)
# -----------------------------
log "[6/6] Removing unused home folders (only if empty)..."

# Adjust if your target user is not "michael"
HOME_DIR="/home/michael"

FOLDERS=(
  Desktop
  Documents
  Downloads
  Music
  Pictures
  Public
  Templates
  Videos
)

for folder in "${FOLDERS[@]}"; do
  if rmdir "$HOME_DIR/$folder" 2>/dev/null; then
    log "  - Removed $folder"
  else
    log "  - $folder not empty or not present (skipped)"
  fi
done

# -----------------------------
# Finish
# -----------------------------
log "[✓] Install complete"
log "A reboot is recommended:"
log "    sudo reboot"
