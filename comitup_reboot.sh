#!/bin/bash

# =============================================================================
#  Comitup WiFi Provisioning - Reboot Callback
#
#  Called by: comitup (as its external_callback in /etc/comitup.conf)
#
#  Purpose:  Reboot the Pi after WiFi is provisioned via the captive portal,
#            so that run.sh can start cleanly on the next boot with network.
#
#  Comitup v1.43 calls this script on every state transition:
#    - HOTSPOT    — comitup has created the provisioning access point
#    - CONNECTING — comitup is attempting to connect to a WiFi network
#    - CONNECTED  — WiFi connection is established
#
#  IMPORTANT:
#    - This script must be owned by root (comitup v1.43 bug — it crashes
#      or silently skips the callback if the script is not root-owned).
#      install.sh handles this with: chown root:root comitup_reboot.sh
#    - Comitup blocks waiting for this script to return, so it must exit
#      quickly on non-CONNECTED states to avoid delaying the connection.
#    - Logs to a persistent location (not /tmp, which is cleared on reboot).
# =============================================================================

# --- Logging ---
# Log to the project directory so entries survive the reboot this script triggers.
# /tmp is cleared on reboot, so a /tmp log would lose the very entry we care about.
PROJECT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="$PROJECT_DIR/comitup_callback.log"
exec >> "$LOG_FILE" 2>&1

echo "$(date) Called with args: $@"
echo "$(date) Running as: $(whoami)"

# --- Only act on CONNECTED — ignore HOTSPOT and CONNECTING ---
if [ "$1" = "CONNECTED" ]; then
    echo "$(date) Rebooting..."
    sudo /sbin/reboot
fi
