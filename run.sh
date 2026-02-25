#!/bin/bash

# =============================================================================
#  Waste Collection Display - Runtime Script
#
#  Called by:
#    - cron @reboot (on every boot)
#    - cron scheduled jobs (midnight+1min, then every 3 hours 6am-6pm)
#
#  What it does:
#    1. On first load after install, displays "Loading ..." on the ePaper
#    2. Waits for network connectivity (up to 60 seconds)
#    3. If no network: starts comitup hotspot for WiFi provisioning
#    4. If network ready: runs main.py to fetch and display waste collection data
#
#  Logs to: <project_dir>/waste-collection.log
#  Log rotation: keeps the last ~1000 lines to prevent unbounded growth.
# =============================================================================


# --- Setup: resolve paths and change to project directory ---
PROJECT_DIR="$(dirname "$(readlink -f "$0")")"
PYTHON="/usr/bin/python3"
LOG_FILE="waste-collection.log"
LOG_PATH="$PROJECT_DIR/$LOG_FILE"
MAX_LOG_LINES=1000

cd "$PROJECT_DIR" || exit 1

# Timestamped log helper
timestamp() {
    date "+[%Y-%m-%d %H:%M:%S]"
}

# Append a timestamped message to the log file
log() {
    echo "$(timestamp) $*" >> "$LOG_PATH"
}

# Verify required Python scripts exist before running
for script in print_text_to_screen.py main.py; do
    if [ ! -f "$script" ]; then
        log "ERROR: Required script '$script' not found in $PROJECT_DIR"
        exit 1
    fi
done


# =============================================================================
#  Log rotation
# =============================================================================

# Trim the log file if it exceeds MAX_LOG_LINES to prevent unbounded growth
# on a Pi with limited SD card storage (script runs ~7 times per day).
if [ -f "$LOG_PATH" ]; then
    LINE_COUNT=$(wc -l < "$LOG_PATH")
    if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
        # Keep the last MAX_LOG_LINES lines
        TEMP_LOG=$(mktemp)
        tail -n "$MAX_LOG_LINES" "$LOG_PATH" > "$TEMP_LOG"
        mv "$TEMP_LOG" "$LOG_PATH"
    fi
fi


# =============================================================================
#  First-load handler
# =============================================================================

# On initial install, install.sh creates first_load.true as a sentinel.
# If it exists, show a loading message and remove it so it only triggers once.
FILE="first_load.true"

if [ -f "$FILE" ]; then
    "$PYTHON" print_text_to_screen.py "Loading ..."
    rm -f "$FILE"
fi


# =============================================================================
#  Network connectivity check
# =============================================================================

# Wait for a default route to appear (indicates network connectivity).
# Check every 10 seconds, up to MAX_TRIES attempts (60 seconds total).
# If network never comes up, start comitup hotspot for WiFi provisioning.

MAX_TRIES=6
COUNT=0

log "Waiting for network..."

until ip route | grep -q default; do
    COUNT=$((COUNT + 1))

    if [ "$COUNT" -ge "$MAX_TRIES" ]; then
        log "Network not ready after $MAX_TRIES attempts. Starting comitup hotspot."

        # Start comitup to broadcast a WiFi provisioning hotspot.
        # Requires passwordless sudo for systemctl (configured in install.sh sudoers).
        if sudo systemctl start comitup; then
            log "comitup started successfully"
        else
            log "ERROR: Failed to start comitup (check sudoers rule in install.sh)"
        fi

        # Show hotspot status on the ePaper display
        "$PYTHON" print_text_to_screen.py "Creating Hotspot ..."

        # Give comitup time to bring up the access point before showing the SSID
        sleep 30

        "$PYTHON" print_text_to_screen.py "SSID: waste-collection-setup"

        # Exit — the next run will be triggered by cron schedule or by reboot
        # after the user provisions WiFi via the comitup captive portal.
        log "Exiting. WiFi provisioning hotspot is active."
        exit 1
    fi

    log "Network not ready yet ($COUNT/$MAX_TRIES). Retrying in 10s..."
    sleep 10
    "$PYTHON" print_text_to_screen.py "Searching For Network ..."
done


# =============================================================================
#  Run main application
# =============================================================================

"$PYTHON" print_text_to_screen.py "Updating ..."

log "Network ready"
log "Running main.py"

"$PYTHON" main.py >> "$LOG_PATH" 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    log "main.py completed successfully"
else
    log "ERROR: main.py exited with code $EXIT_CODE"
    # Show error on the ePaper so it's not stuck on "Updating ..." indefinitely
    "$PYTHON" print_text_to_screen.py "Run Error (code $EXIT_CODE)"
fi