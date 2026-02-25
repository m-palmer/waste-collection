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
#  - Creates temporary swap file for memory-heavy installs
#  - Enables SPI and I2C (if raspi-config is available)
#  - Sets console boot (B1) and attempts do_boot_cli where available
#  - Sets hostname to waste-collection and updates /etc/hosts
#  - Installs system + Python deps, Playwright, and Chromium
#  - Installs Playwright browser cache with retry (up to 3 attempts)
#  - Installs and configures comitup (WiFi provisioning hotspot)
#  - Enables cron and installs cron schedule for run.sh (idempotent)
#  - Normalises run.sh (LF line endings) and makes it executable
#  - Disables optional services if present
#  - Removes default home folders only if EMPTY
#
# Notes:
#  - Repo is expected to live at: /home/<user>/waste-collection
#  - This script is safe to re-run (it replaces its own cron block).
# ============================================================


# =============================================================================
#  SECTION: Logging & Utility Functions
# =============================================================================

# Resolve the directory this script lives in (follows relative paths, not symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${SCRIPT_DIR}/waste-collection-install.log"

# Redirect all stdout and stderr to both the terminal and the log file
exec > >(tee -a "$LOGFILE") 2>&1

# Timestamped log message
log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Log an error and exit immediately (%b interprets escape sequences like \n)
die() { printf "[%s] [X] %b\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; exit 1; }

# Ensure a required command exists on $PATH before continuing
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}


# =============================================================================
#  SECTION: Privilege & User Detection
# =============================================================================

# This script MUST be run as root (via sudo), not directly as root.
# We need SUDO_USER to know which non-root user to configure cron,
# Playwright cache, etc. for.

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "Please run with sudo:\n  sudo ./install.sh"
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
  die "Run via sudo as a normal user (not directly as root), so user installs/cron work correctly."
fi

# FIX #2: Use getent instead of eval to avoid shell injection risk via SUDO_USER
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
  die "Could not determine home directory for user: ${TARGET_USER}"
fi

log "[*] Starting install"
log "[*] Log file: $LOGFILE"
log "[*] Installing for user: ${TARGET_USER}"
log "[*] Target home: ${TARGET_HOME}"
log ""


# =============================================================================
#  SECTION: Temporary Swap File
# =============================================================================

# Playwright + Chromium installs can be memory-hungry on Pi Zero / low-RAM boards.
# We create a temporary swap file to prevent OOM kills during the install.
# It is removed at the end of the script.

SWAPFILE="/swapfile"
SWAP_SIZE_MB=512
SWAP_CREATED="no"

# Ensure swap is cleaned up even if the script exits early (e.g. set -e abort).
# The trap runs on any exit — normal or error — so swap won't be left behind.
cleanup_swap() {
  if [[ "$SWAP_CREATED" == "yes" && -f "$SWAPFILE" ]]; then
    log "[*] Cleaning up temporary swap file..."
    swapoff "$SWAPFILE" 2>/dev/null || true
    rm -f "$SWAPFILE"
    log " -> Swap file removed"
  fi
}
trap cleanup_swap EXIT

if ! swapon --show | grep -qw "$SWAPFILE"; then
  # Guard against overwriting an existing file that isn't currently active as swap
  if [[ -f "$SWAPFILE" ]]; then
    log " [!] ${SWAPFILE} exists but is not active as swap — removing stale file"
    rm -f "$SWAPFILE"
  fi
  log "[*] Creating ${SWAP_SIZE_MB}MB swap file (temporary, removed after install)..."
  dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE_MB" status=progress
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"
  SWAP_CREATED="yes"
  log " -> Swap enabled (${SWAP_SIZE_MB}MB)"
else
  log " -> ${SWAPFILE} already active (skipping creation)"
fi


# =============================================================================
#  SECTION: User Confirmation Gate
# =============================================================================

# Display a summary of everything the script will do and require
# the user to type "Yes" exactly. This prevents accidental runs.

cat <<'EOF'

============================================================
Waste Collection Display Installer

This script WILL make changes to your Raspberry Pi, including:
  1) Enabling SPI and I2C (if raspi-config is available)
  2) Switching boot to console (no desktop GUI)
  3) Changing hostname to: waste-collection
     - and updating /etc/hosts
  4) Installing packages + Python deps + Playwright + Chromium + comitup
     - pip uses --break-system-packages
     - Playwright browser install retries up to 3 times
     - Temporary swap file created for memory-heavy installs
     - comitup installed for WiFi provisioning (disabled by default)
  5) Enabling cron and installing scheduled jobs for run.sh
  6) Normalising run.sh (line endings + permissions)
  7) Disabling optional services (only if present)
  8) Removing default home folders ONLY if empty

This install is safe to re-run if needed.

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


# =============================================================================
#  SECTION: Project Configuration
# =============================================================================

# Where the waste-collection repo is expected to live on disk
TARGET_DIR_NAME="waste-collection"   # folder name under the user's home
PROJECT_DIR="${TARGET_HOME}/${TARGET_DIR_NAME}"
RUN_SH="${PROJECT_DIR}/run.sh"
REBOOT_SH="${PROJECT_DIR}/comitup_reboot.sh"

# --- Cron schedule definition ---
# The cron block is tagged so it can be replaced idempotently on re-runs.
# Schedule: run at reboot, midnight+1min, then every 3 hours from 6am-6pm.
#
# Note: run.sh handles the first-load "Loading ..." display internally via
# the first_load.true sentinel file, so there is no separate @reboot entry
# for print_text_to_screen.py (that would race with run.sh over the ePaper).
#
# FIX #7: Use absolute paths instead of $HOME to avoid cron environment issues
# where $HOME may not be set in all cron implementations.

CRON_TAG="waste-collection"
CRON_LINES=(
  "@reboot ${TARGET_HOME}/${TARGET_DIR_NAME}/run.sh"
  "1 0 * * * ${TARGET_HOME}/${TARGET_DIR_NAME}/run.sh"
  "0 6 * * * ${TARGET_HOME}/${TARGET_DIR_NAME}/run.sh"
  "0 9 * * * ${TARGET_HOME}/${TARGET_DIR_NAME}/run.sh"
  "0 12 * * * ${TARGET_HOME}/${TARGET_DIR_NAME}/run.sh"
  "0 15 * * * ${TARGET_HOME}/${TARGET_DIR_NAME}/run.sh"
  "0 18 * * * ${TARGET_HOME}/${TARGET_DIR_NAME}/run.sh"
)


# =============================================================================
#  SECTION: Pre-flight Checks
# =============================================================================

# Verify essential commands are available before we start making changes
require_cmd apt-get
require_cmd sed
require_cmd crontab
require_cmd python3

# raspi-config is optional — headless/Docker images may not include it
if command -v raspi-config >/dev/null 2>&1; then
  RASPI_CONFIG_AVAILABLE="yes"
else
  RASPI_CONFIG_AVAILABLE="no"
fi


# =============================================================================
#  SECTION: Playwright Browser Install Function
# =============================================================================

# Downloads Playwright's Chromium binaries directly via wget rather than
# using `playwright install`, which spawns a heavy Node.js process that
# can cause OOM or network timeouts on constrained devices.
#
# Installs two components:
#   1. chromium           — full browser (for headed mode / debugging)
#   2. chromium-headless-shell — lightweight headless binary (production use)
#
# Each download is retried up to 3 times with cleanup between attempts.

install_playwright_browsers() {
  local max_retries=3
  local pw_cache="${TARGET_HOME}/.cache/ms-playwright"

  # --- Detect Playwright's expected Chromium revision ---
  # We read this from the installed Playwright package's browsers.json
  # so our manual download matches what Playwright expects at runtime.

  local pw_revision
  pw_revision=$(sudo -u "${TARGET_USER}" -H python3 -c "
import json
try:
    from playwright._impl._driver import compute_driver_executable
    node = str(compute_driver_executable())
    pkg = node.replace('/package/cli.js','')
    with open(pkg + '/package/browsers.json') as f:
        data = json.load(f)
    for b in data['browsers']:
        if b['name'] == 'chromium':
            print(b['revision'])
            break
except Exception:
    print('')
" 2>/dev/null || true)

  # --- FIX #3: Dynamic fallback — fetch revision from GitHub ---
  # If local detection fails (e.g. broken/partial install), we look up
  # the installed Playwright pip version and fetch the matching
  # browsers.json from the official GitHub repo tag. This avoids
  # hardcoding a revision that could silently become incompatible.

  if [[ -z "$pw_revision" ]]; then
    log "    Local revision detection failed. Attempting GitHub lookup..."

    local pw_pip_version
    pw_pip_version=$(sudo -u "${TARGET_USER}" -H python3 -c "
import importlib.metadata
print(importlib.metadata.version('playwright'))
" 2>/dev/null || true)

    if [[ -n "$pw_pip_version" ]]; then
      log "    Installed Playwright pip version: ${pw_pip_version}"

      # Fetch browsers.json from the matching GitHub release tag
      local browsers_json_url="https://raw.githubusercontent.com/microsoft/playwright/v${pw_pip_version}/packages/playwright-core/browsers.json"
      local tmp_browsers_json="/tmp/playwright-browsers-${pw_pip_version}.json"

      if wget -q --tries=3 --timeout=30 -O "$tmp_browsers_json" "$browsers_json_url" 2>/dev/null; then
        pw_revision=$(python3 -c "
import json
try:
    with open('${tmp_browsers_json}') as f:
        data = json.load(f)
    for b in data['browsers']:
        if b['name'] == 'chromium':
            print(b['revision'])
            break
except Exception:
    print('')
" 2>/dev/null || true)
        rm -f "$tmp_browsers_json"
      else
        rm -f "$tmp_browsers_json"
      fi
    fi

    # If both methods failed, abort loudly instead of using a stale hardcoded value
    if [[ -n "$pw_revision" ]]; then
      log "    Resolved revision from GitHub: ${pw_revision}"
    else
      die "Could not determine Playwright Chromium revision from local install or GitHub.\n     Please run manually: sudo -u ${TARGET_USER} python3 -m playwright install"
    fi
  else
    log "    Detected Playwright revision: ${pw_revision}"
  fi

  # --- Browser definitions ---
  # Format: name|zip_filename|install_dirname|verify_binary|revision
  local -a BROWSERS=(
    "chromium|chromium-linux-arm64.zip|chromium-${pw_revision}|chrome-linux/chrome|${pw_revision}"
    "chromium-headless-shell|chromium-headless-shell-linux-arm64.zip|chromium_headless_shell-${pw_revision}|chrome-linux/headless_shell|${pw_revision}"
  )

  local all_ok="yes"

  for browser_entry in "${BROWSERS[@]}"; do
    IFS='|' read -r name zip_name dir_name verify_bin revision <<< "$browser_entry"

    local install_dir="${pw_cache}/${dir_name}"
    local verify_path="${install_dir}/${verify_bin}"
    local cdn_base="https://cdn.playwright.dev/dbazure/download/playwright/builds"
    local zip_url="${cdn_base}/chromium/${revision}/${zip_name}"
    local zip_path="/tmp/playwright-${name}-${revision}.zip"

    # Skip if this browser is already installed and executable
    if [[ -x "$verify_path" ]]; then
      log " -> ${name} already installed at ${verify_path}"
      continue
    fi

    local attempt=1
    local installed="no"

    # --- Retry loop: download, extract, verify ---
    while (( attempt <= max_retries )); do
      log " -> Attempt ${attempt}/${max_retries}: Installing ${name}"

      # Clear any partial/corrupt install from a previous attempt
      if [[ -d "$install_dir" ]]; then
        log "    Clearing partial install at ${install_dir}"
        rm -rf "$install_dir"
      fi

      # Step 1: Download the zip (reuse if already present from a prior attempt)
      if [[ -f "$zip_path" ]]; then
        log "    Zip already downloaded, reusing: ${zip_path}"
      else
        log "    Downloading ${name}..."
        rm -f "$zip_path"
        if wget -q --show-progress --tries=3 --timeout=60 -O "$zip_path" "$zip_url"; then
          log "    Download complete"
        else
          log "    Download failed"
          rm -f "$zip_path"
          ((attempt++))
          sleep 5
          continue
        fi
      fi

      # Step 2: Extract the zip into the Playwright cache
      log "    Extracting to ${install_dir}..."
      mkdir -p "$install_dir"

      if unzip -q -o "$zip_path" -d "$install_dir"; then
        log "    Extraction complete"
      else
        log "    Extraction failed"
        rm -rf "$install_dir"
        rm -f "$zip_path"
        ((attempt++))
        sleep 5
        continue
      fi

      # Step 3: Fix ownership and permissions for the target user
      chown -R "${TARGET_USER}:${TARGET_USER}" "$install_dir"
      chmod -R u+rwX "$install_dir"

      # Ensure the main binary is executable
      if [[ -f "$verify_path" ]]; then
        chmod +x "$verify_path"
      fi

      # Playwright checks for this sentinel file to consider the browser "installed"
      touch "${install_dir}/INSTALLATION_COMPLETE"
      chown "${TARGET_USER}:${TARGET_USER}" "${install_dir}/INSTALLATION_COMPLETE"

      # Step 4: Final verification — is the binary present and executable?
      if [[ -x "$verify_path" ]]; then
        log " -> ${name} verified at ${verify_path}"
        rm -f "$zip_path"
        installed="yes"
        break
      fi

      log " [!] Attempt ${attempt} failed — ${verify_path} not found or not executable"
      rm -rf "$install_dir"
      rm -f "$zip_path"
      ((attempt++))
      sleep 5
    done

    if [[ "$installed" != "yes" ]]; then
      log " [X] ${name} failed after ${max_retries} attempts"
      all_ok="no"
    fi
  done

  # Ensure the entire Playwright cache is owned by the target user (if it exists)
  if [[ -d "$pw_cache" ]]; then
    chown -R "${TARGET_USER}:${TARGET_USER}" "$pw_cache"
  fi

  if [[ "$all_ok" == "yes" ]]; then
    return 0
  else
    log "     You can retry manually: sudo -u ${TARGET_USER} python3 -m playwright install"
    return 1
  fi
}


# =============================================================================
#  STEP [1/8]: Enable Hardware Interfaces (SPI / I2C)
# =============================================================================

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


# =============================================================================
#  STEP [2/8]: Configure Boot Behaviour (Console, No GUI)
# =============================================================================

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


# =============================================================================
#  STEP [3/8]: Set Hostname
# =============================================================================

log "[3/8] Setting hostname..."

NEW_HOSTNAME="waste-collection"
hostnamectl set-hostname "$NEW_HOSTNAME"

# Update /etc/hosts idempotently:
#   - If a 127.0.1.1 line already exists, replace it
#   - Otherwise, append a new one
if grep -q "^127.0.1.1" /etc/hosts; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
else
  echo -e "127.0.1.1\t$NEW_HOSTNAME" >> /etc/hosts
fi

log " -> Hostname set to $NEW_HOSTNAME"
log ""


# =============================================================================
#  STEP [4/8]: Install System & Python Dependencies
# =============================================================================

log "[4/8] Installing system & Python dependencies..."

apt-get update -y

# --- Core system packages ---
apt-get install -y \
  cron \
  ca-certificates \
  curl \
  python3-pip \
  python3-pil \
  python3-numpy \
  python3-gpiozero

# --- Chromium browser (package name varies across Debian/RPi OS builds) ---
if apt-cache show chromium >/dev/null 2>&1; then
  apt-get install -y chromium || true
elif apt-cache show chromium-browser >/dev/null 2>&1; then
  apt-get install -y chromium-browser || true
else
  log " -> Chromium not found via apt-cache; Playwright can still download its own."
fi

# --- Python packages (using --break-system-packages to override PEP 668 restrictions) ---

log " -> Installing spidev (pip, PEP 668 override)"
python3 -m pip install --break-system-packages spidev

log " -> Installing Playwright (pip, PEP 668 override)"
python3 -m pip install --break-system-packages playwright

# --- Playwright OS-level dependencies (shared libraries for Chromium) ---

log " -> Installing Playwright OS dependencies (Chromium) [may be slow]"
python3 -m playwright install-deps chromium || true

# --- Playwright browser binaries (custom wget-based installer with retry) ---

log " -> Installing Playwright browsers (with retry)..."
install_playwright_browsers || true

# --- Cron service ---

log " -> Ensuring cron service is enabled"
systemctl enable --now cron 2>/dev/null || true

# --- Comitup: WiFi provisioning hotspot ---
# Comitup creates a temporary access point so users can configure WiFi
# credentials on a headless Pi via a captive portal.

log " -> Installing comitup (Wifi Network Bootstrap for the Raspberry Pi)"
DEBIAN_FRONTEND=noninteractive apt-get install -y comitup

log " -> Configuring comitup"

# FIX #6: Use cat redirect instead of tee to avoid dumping config to stdout/log
cat > /etc/comitup.conf << EOF
ap_name: waste-collection-setup
external_callback: ${PROJECT_DIR}/comitup_reboot.sh
verbose: 1
EOF
log ""

# Comitup is installed but disabled by default — it is expected to be
# enabled separately (e.g. by run.sh or a first-boot script) when needed.
# FIX #1: Removed redundant 'sudo' — this script already runs as root
systemctl stop comitup 2>/dev/null || true
systemctl disable comitup 2>/dev/null || true

# Grant the target user passwordless sudo for:
#   - /sbin/reboot           (used by comitup_reboot.sh after WiFi provisioning)
#   - systemctl start comitup (used by run.sh when no network is available)
echo "${TARGET_USER} ALL=(ALL) NOPASSWD: /sbin/reboot, /usr/bin/systemctl start comitup" > /etc/sudoers.d/comitup-reboot
chmod 440 /etc/sudoers.d/comitup-reboot


# =============================================================================
#  STEP [5/8]: Install Cron Schedule for Target User
# =============================================================================

# The cron block is wrapped in tagged markers so that re-running this
# script removes the old block and replaces it with the current one.

log "[5/8] Setting up cron for ${TARGET_USER}..."

CRON_BLOCK="# === ${CRON_TAG} BEGIN ===
$(printf "%s\n" "${CRON_LINES[@]}")
# === ${CRON_TAG} END ==="

# Remove any existing tagged block, then append the new one
(
  crontab -u "${TARGET_USER}" -l 2>/dev/null | sed "/# === ${CRON_TAG} BEGIN ===/,/# === ${CRON_TAG} END ===/d" || true
  echo "${CRON_BLOCK}"
) | crontab -u "${TARGET_USER}" -

log " -> Cron installed for ${TARGET_USER}"
log ""


# =============================================================================
#  STEP [6/8]: Normalise run.sh (Line Endings + Permissions)
# =============================================================================

log "[6/8] Normalising run.sh..."

# Verify the project directory and run.sh exist
if [[ ! -d "${PROJECT_DIR}" ]]; then
  die "Project directory not found: ${PROJECT_DIR}\nClone/copy your repo there, or update TARGET_DIR_NAME in install.sh."
fi

if [[ ! -f "${RUN_SH}" ]]; then
  die "run.sh not found: ${RUN_SH}"
fi

# Convert Windows-style CRLF line endings to Unix LF
sed -i 's/\r$//' "${RUN_SH}"

# Sanity check: ensure the script has a valid shebang
if ! head -n 1 "${RUN_SH}" | grep -qE '^#!/'; then
  die "run.sh has no shebang line. First line should be something like: #!/bin/bash"
fi

chmod 755 "${RUN_SH}"

# FIX #5: Validate comitup_reboot.sh exists before chmod (matching run.sh pattern)
# NOTE: comitup v1.43 requires the callback script to be owned by root —
# it silently skips or crashes on the callback if the file is user-owned.
if [[ -f "${REBOOT_SH}" ]]; then
  chown root:root "${REBOOT_SH}"
  chmod 755 "${REBOOT_SH}"
else
  log " [!] Warning: ${REBOOT_SH} not found — skipping chmod/chown"
fi

# Make print_text_to_screen.py executable (called by run.sh and install.sh)
PRINT_SCREEN_PY="${PROJECT_DIR}/print_text_to_screen.py"
if [[ -f "${PRINT_SCREEN_PY}" ]]; then
  chmod 755 "${PRINT_SCREEN_PY}"
else
  log " [!] Warning: ${PRINT_SCREEN_PY} not found — skipping chmod"
fi

# Create a sentinel file so the application knows it should run its first-load sequence
# (re-created on every install run so a re-install triggers first-load again)
sudo -u "${TARGET_USER}" touch "${PROJECT_DIR}/first_load.true"

log " -> ${RUN_SH} is now executable."
log ""


# =============================================================================
#  STEP [7/8]: Disable Optional / Unused Services
# =============================================================================

# Disable services that aren't needed for a headless e-ink display device.
# Each service is only touched if it actually exists on the system.

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
  wayvnc-control              # VNC remote desktop control
  bluetooth                   # Bluetooth (not needed)
  cups                        # Print server
  cups-browsed                # Print server browser
  cups.path                   # Print server path unit
  ModemManager                # Cellular modem manager
  glamor-test                 # GPU test service
  rp1-test                    # RP1 chip test service
  avahi-daemon                # mDNS / Bonjour discovery
  avahi-daemon.socket         # mDNS socket activation
  udisks2                     # USB disk automounting
  nfs-blkmap                  # NFS block mapping
  rpcbind.socket              # RPC port mapper (NFS)
  rpcbind.service             # RPC port mapper service
  serial-getty@ttyAMA0        # Serial console on GPIO UART
)

for svc in "${SERVICES[@]}"; do
  disable_and_stop "$svc"
done

log ""


# =============================================================================
#  STEP [8/8]: Remove Unused Default Home Folders
# =============================================================================

# The default Raspberry Pi OS home directory contains several XDG folders
# (Desktop, Documents, etc.) that are unnecessary on a headless device.
# We only remove them if they're completely empty to avoid data loss.

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

# Display a message on the e-ink screen prompting the user to reboot
# (failure is non-fatal — display may not be connected during install)
sudo -u "${TARGET_USER}" python3 "${PROJECT_DIR}/print_text_to_screen.py" "Power Me Up To Get Started" || log " [!] Could not write to e-ink display (non-fatal)"


# =============================================================================
#  SECTION: Final Summary
# =============================================================================

# Swap cleanup is handled automatically by the EXIT trap (see Temporary Swap section).

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
log "If you want to remove the saved WIFI credentials run:"
if command -v nmcli >/dev/null 2>&1; then
  WIFI_CONS=$(nmcli -t -f NAME,TYPE connection show | grep -E ':(wifi|802-11-wireless)$' | grep -v 'comitup\|waste-collection-setup' | sed 's/:[^:]*$//' || true)
  while IFS= read -r con; do
      [ -n "$con" ] && log "  sudo nmcli connection delete \"$con\""
  done <<< "$WIFI_CONS"
else
  log "  (nmcli not found — skip WiFi credential listing)"
fi


log ""
log "A reboot is recommended:"
log "  sudo reboot"