#!/bin/bash

PROJECT_DIR="/home/michael/waste-collection"
PYTHON="/usr/bin/python3"
LOG_FILE="waste-collection.log"

timestamp() {
  date "+[%Y-%m-%d %H:%M:%S]"
}

MAX_TRIES=10
COUNT=0

echo "$(timestamp) Waiting for network..." >> "$PROJECT_DIR/$LOG_FILE"

until ip route | grep -q default; do
  COUNT=$((COUNT+1))

  if [ "$COUNT" -ge "$MAX_TRIES" ]; then
    echo "$(timestamp) Network not ready after $MAX_TRIES attempts. Giving up." >> "$PROJECT_DIR/$LOG_FILE"
    exit 1
  fi

  echo "$(timestamp) Network not ready yet ($COUNT/$MAX_TRIES). Sleeping..." >> "$PROJECT_DIR/$LOG_FILE"
  sleep 10
done

echo "$(timestamp) Network ready" >> "$PROJECT_DIR/$LOG_FILE"

cd "$PROJECT_DIR" || exit 1
echo "$(timestamp) Running main.py" >> "$PROJECT_DIR/$LOG_FILE"

"$PYTHON" main.py >> "$PROJECT_DIR/$LOG_FILE" 2>&1

echo "$(timestamp) Script finished with exit code $?" >> "$PROJECT_DIR/$LOG_FILE"
