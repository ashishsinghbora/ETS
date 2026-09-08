#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:${PATH}"

CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

TIERED_MOUNT="${TIERED_MOUNT:-$HOME/mnt/cloud-tiered}"
IMMEDIATE_DIR="${TIERED_MOUNT}/.immediate_sync"
REMOTE_DEST="${CRYPT_REMOTE:-gcrypt}:"
RC_ADDR="${RCLONE_RC_ADDR:-127.0.0.1:5572}"
BWLIMIT="${SYNC_BWLIMIT:-5M}"
LOG_TO_FILE="${LOG_TO_FILE:-false}"
LOG_FILE="${LOG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.log}"

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] [IMMEDIATE] $*"
    echo "$msg"
    if [ "$LOG_TO_FILE" = "true" ] && [ -n "$LOG_FILE" ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "$msg" >>"$LOG_FILE"
    fi
}

mkdir -p "$IMMEDIATE_DIR"

process_file() {
    local filepath="$1"
    [ -f "$filepath" ] || return 0
    local relpath
    relpath="${filepath#"$IMMEDIATE_DIR"/}"
    log "Offloading: $relpath -> ${REMOTE_DEST}${relpath}..."
    if rclone moveto "$filepath" "${REMOTE_DEST}${relpath}" \
        --bwlimit "$BWLIMIT" \
        --stats-one-line; then
        log "Successfully offloaded: $relpath"
        rclone rc --rc-addr "$RC_ADDR" vfs/refresh recursive=true >/dev/null 2>&1 || true
        find "$IMMEDIATE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    else
        log "ERROR: Failed to offload: $relpath" >&2
    fi
}

sweep_existing_files() {
    find "$IMMEDIATE_DIR" -mindepth 1 -type f 2>/dev/null | while IFS= read -r f; do
        process_file "$f"
    done
    find "$IMMEDIATE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
}

log "Watching $IMMEDIATE_DIR for new files to immediately offload to $REMOTE_DEST..."
sweep_existing_files

if ! command -v inotifywait &>/dev/null; then
    log "[WARN] inotifywait is not installed. Gracefully falling back to 30s polling loop."
    while true; do
        sleep 30
        sweep_existing_files
    done
fi

# Continuous inotify watcher with unbuffered line output
stdbuf -oL inotifywait -m -r -e close_write,moved_to --format "%w%f" "$IMMEDIATE_DIR" | while IFS= read -r filepath; do
    process_file "$filepath"
done
