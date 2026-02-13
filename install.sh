#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Waste Collection Display - Installer (Merged)
#
# Run with:
#   sudo ./install.sh
#
# High-level actions:
#  - Logs to waste-collection-install.log (next to this script)
#  - Requires explicit confirmation (type exactly: Yes)
#  - Enables SPI and I2C (if raspi-config is available)
#  - Sets console boot (B1) and attempts do_boot_cli where available
#  - Sets hostname to waste-collection and updates /etc/hosts
#  - Installs system + Python deps, Playwright, and Chromium
#  - Installs Playwright browser cache for the *sudo invoking user*
#  - Enables cron and installs cron schedule for run.sh (idempotent)
#  - Normalises run.sh (LF line endings) and makes it executable
#  - Disables optional services if present
#  - Removes default home folders only if EMPTY
#
# Notes:
#  - Repo is expected to live at: /home/<user>/waste-collection
#  - This script is safe to re-run (it replaces its own cron block).
# ============================================================

# -----------------------------
# Logging
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${SCRIPT_DIR}/waste-collection-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { log "[X] $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# -----------------------------
# Root check + determine target user
# -----------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "Please run with sudo:\n  sudo ./install.sh"
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
  die "Run via sudo as a normal user (not directly as root), so user installs/cron work correctly."
fi

TARGET_HOME="$(eval echo "~${TARGET_USER}")"

log "[*] Starting install"
log "[*] Log file: $LOGFILE"
log "[*] Installing for user: ${TARGET_USER}"
log "[*] Target home: ${TARGET_HOME}"
log ""

# -----------------------------
# Confirmation gate
# -----------------------------
cat <<'EOF'

============================================================
Waste Collection Display Installer

This script WILL make changes to your Raspberry Pi, including:
  1) Enabling SPI and I2C (if raspi-config is available)
  2) Switching boot to console (no desktop GUI)
  3) Changing hostname to: waste-collection
     - and updating /etc/hosts
  4) Installing packages + Python deps + Playwright + Chromium
     - pip uses --break-system-packages
     - Playwright browser install is done for the target (non-root) user
  5) Enabling cron and installing scheduled jobs for run.sh
  6) Disabling optional services (only if present)
  7) Removing default home folders ONLY if empty

Warning:
On some Raspberry Pi OS builds, the Chromium / Playwright steps can
occasionally hang or crash over SSH. If that happens, reconnect and run
the installer again. It is safe to re-run.

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
log ""

# -----------------------------
# Config
# -----------------------------
TARGET_DIR_NAME="waste-collection"   # folder name under the user's home
PROJECT_DIR="${TARGET_HOME}/${TARGET_DIR_NAME}"
RUN_SH="${PROJECT_DIR}/run.sh"

CRON_TAG="waste-collection"
CRON_LINES=(
  "@reboot \$HOME/${TARGET_DIR_NAME}/run.sh"
  "1 0 * * * \$HOME/${TARGET_DIR_NAME}/run.sh"
  "0 6 * * * \$HOME/${TARGET_DIR_NAME}/run.sh"
  "0 9 * * * \$HOME/${TARGET_DIR_NAME}/run.sh"
  "0 12 * * * \$HOME/${TARGET_DIR_NAME}/run.sh"
  "0 15 * * * \$HOME/${TARGET_DIR_NAME}/run.sh"
  "0 18 * * * \$HOME/${TARGET_DIR_NAME}/run.sh"
)

# -----------------------------
# Required commands
# -----------------------------
require_cmd apt-get
require_cmd sed
require_cmd crontab
require_cmd python3

# raspi-config is optional (some images may not include it)
if command -v raspi-config >/dev/null 2>&1; then
  RASPI_CONFIG_AVAILABLE="yes"
else
  RASPI_CONFIG_AVAILABLE="no"
fi

# -----------------------------
# [1/8] Enable interfaces
# -----------------------------
log "[1/8] Enabling hardware interfaces..."
if [[ "$RASPI_CONFIG_AVAILABLE" == "yes" ]]; then
  log " -> Enabling SPI (required for e-ink display)"
  raspi-config nonint do_spi 0
  log " -> Enabling I2C (safe to enable, commonly used)"
  raspi-config nonint do_i2c 0
else
  log " -> raspi-config not found; skipping SPI/I2C enable"
fi
log ""

# -----------------------------
# [2/8] Boot to console (no GUI)
# -----------------------------
log "[2/8] Configuring boot behaviour..."
if [[ "$RASPI_CONFIG_AVAILABLE" == "yes" ]]; then
  # B1 = Console Autologin
  raspi-config nonint do_boot_behaviour B1
  # Some images also support do_boot_cli; ignore failure if unavailable.
  raspi-config nonint do_boot_cli 0 >/dev/null 2>&1 || true
  log " -> Console boot configured"
else
  log " -> raspi-config not found; skipping boot behaviour change"
fi
log ""

# -----------------------------
# [3/8] Hostname
# -----------------------------
log "[3/8] Setting hostname..."
NEW_HOSTNAME="waste-collection"
hostnamectl set-hostname "$NEW_HOSTNAME"

# Update /etc/hosts safely (idempotent)
if grep -q "^127.0.1.1" /etc/hosts; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
else
  echo -e "127.0.1.1\t$NEW_HOSTNAME" >> /etc/hosts
fi

log " -> Hostname set to $NEW_HOSTNAME"
log ""

# -----------------------------
# [4/8] System & Python dependencies
# -----------------------------
log "[4/8] Installing system & Python dependencies..."
apt-get update -y

apt-get install -y \
  cron \
  ca-certificates \
  curl \
  python3-pip \
  python3-pil \
  python3-numpy \
  python3-gpiozero

# Chromium (package name varies across Debian/RPi OS builds)
if apt-cache show chromium >/dev/null 2>&1; then
  apt-get install -y chromium || true
elif apt-cache show chromium-browser >/dev/null 2>&1; then
  apt-get install -y chromium-browser || true
else
  log " -> Chromium not found via apt-cache; Playwright can still download its own."
fi

log " -> Installing spidev (pip, PEP 668 override)"
python3 -m pip install --break-system-packages spidev

log " -> Installing Playwright (pip, PEP 668 override)"
python3 -m pip install --break-system-packages playwright

log " -> Installing Playwright OS dependencies (Chromium) [may be slow]"
python3 -m playwright install-deps chromium || true

log " -> Installing Playwright Chromium for ${TARGET_USER} (user cache)"
sudo -u "${TARGET_USER}" -H python3 -m playwright install chromium

log " -> Ensuring cron service is enabled"
systemctl enable --now cron 2>/dev/null || true

log " -> Installing comitup (Wifi Network Bootstrap for the Raspberry Pi)"
sudo apt install -y comitup

log " -> Configuring comitup"
sudo tee /etc/comitup.conf << EOF
ap_name: waste-collection-setup
external_callback: ${HOME}/${TARGET_DIR_NAME}/comitup-callback
EOF

log ""

# -----------------------------
# [5/8] Cron for the target user (NOT root)
# -----------------------------
log "[5/8] Setting up cron for ${TARGET_USER}..."

CRON_BLOCK="# === ${CRON_TAG} BEGIN ===
$(printf "%s\n" "${CRON_LINES[@]}")
# === ${CRON_TAG} END ==="

(
  crontab -u "${TARGET_USER}" -l 2>/dev/null | sed "/# === ${CRON_TAG} BEGIN ===/,/# === ${CRON_TAG} END ===/d" || true
  echo "${CRON_BLOCK}"
) | crontab -u "${TARGET_USER}" -

log " -> Cron installed for ${TARGET_USER}"
log ""

# -----------------------------
# [6/8] Fix run.sh (line endings + permissions)
# -----------------------------
log "[6/8] Fixing run.sh..."

if [[ ! -d "${PROJECT_DIR}" ]]; then
  die "Project directory not found: ${PROJECT_DIR}\nClone/copy your repo there, or update TARGET_DIR_NAME in install.sh."
fi

if [[ ! -f "${RUN_SH}" ]]; then
  die "run.sh not found: ${RUN_SH}"
fi

# Convert CRLF -> LF if needed
sed -i 's/\r$//' "${RUN_SH}"

# Ensure a shebang exists
if ! head -n 1 "${RUN_SH}" | grep -qE '^#!/'; then
  die "run.sh has no shebang line. First line should be something like: #!/bin/bash"
fi

chmod 755 "${RUN_SH}"
log " -> ${RUN_SH} is now executable."
log ""

# -----------------------------
# [7/8] Disable optional services
# -----------------------------
log "[7/8] Disabling optional services (only if present)..."

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

log ""

# -----------------------------
# [8/8] Remove unused home folders (empty only)
# -----------------------------
log "[8/8] Removing unused home folders (only if empty)..."

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
  if rmdir "${TARGET_HOME}/${folder}" 2>/dev/null; then
    log "  - Removed ${folder}"
  else
    log "  - ${folder} not empty or not present (skipped)"
  fi
done

log ""
log "[✓] Install complete"
log ""
log "IMPORTANT:"
log "This system is now configured to boot into CONSOLE mode (no desktop GUI)."
log ""
log "If you ever want to re-enable the desktop GUI:"
log "  sudo raspi-config"
log "  → System Options"
log "  → Boot / Auto Login"
log "  → Choose Desktop mode"
log ""
log "Or via command line:"
log "  sudo raspi-config nonint do_boot_behaviour B4"
log ""
log "BEFORE RUNNING THE SCRIPT:"
log "Edit main.py and set your postcode and address value (e.g. POSTCODE / ADDRESS_VALUE)."
log ""
log "Next checks:"
log "  • Edit config:  nano ${PROJECT_DIR}/main.py"
log "  • Test run.sh:  ${RUN_SH}"
log "  • Test python:  cd ${PROJECT_DIR} && python3 main.py"
log ""
log "A reboot is recommended:"
log "  sudo reboot"
