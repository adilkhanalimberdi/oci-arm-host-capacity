#!/usr/bin/env bash
# Runs index.php every INTERVAL seconds until an instance exists.
# Alternative to cron, e.g. for WSL or a terminal left open (use tmux/screen).
# Usage: ./loop.sh [env-file] [interval-seconds]

cd "$(dirname "$0")" || exit 1

ENV_FILE="${1:-.env}"
INTERVAL="${2:-60}"

while true; do
    output="$(php ./index.php "$ENV_FILE" 2>&1)"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $output" | tee -a oci.log

    if echo "$output" | grep -q -e '"lifecycleState"' -e 'Already have an instance'; then
        echo "Instance created (or already exists). Stopping."
        exit 0
    fi

    sleep "$INTERVAL"
done
