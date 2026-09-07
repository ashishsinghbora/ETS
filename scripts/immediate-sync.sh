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

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [IMMEDIATE] $*"; }

if ! command -v inotifywait &>/dev/null; then
    log "ERROR: inotifywait is not installed. immediate-sync service cannot start." >&2
    exit 1
fi

mkdir -p "$IMMEDIATE_DIR"
log "Watching $IMMEDIATE_DIR for new files to immediately offload to $REMOTE_DEST..."

# Process any files already present in the directory on startup
find "$IMMEDIATE_DIR" -mindepth 1 -type f 2>/dev/null | while IFS= read -r f; do
    [ -f "$f" ] || continue
    rel="${f#$IMMEDIATE_DIR/}"
    log "Processing existing file: $rel"
    if rclone moveto "$f" "${REMOTE_DEST}${rel}" --bwlimit "$BWLIMIT" --stats-one-line; then
        log "Offloaded: $rel"
        rclone rc --rc-addr "$RC_ADDR" vfs/refresh recursive=true >/dev/null 2>&1 || true
    fi
done

# Clean empty subdirectories
find "$IMMEDIATE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true

# Continuous inotify watcher
stdbuf -oL inotifywait -m -r -e close_write,moved_to --format "%w%f" "$IMMEDIATE_DIR" | while read -r filepath; do
    # Ignore if not a regular file or if it disappeared
    [ -f "$filepath" ] || continue
    
    relpath="${filepath#$IMMEDIATE_DIR/}"
    log "Detected event on: $relpath. Immediately offloading to ${REMOTE_DEST}${relpath}..."
    
    if rclone moveto "$filepath" "${REMOTE_DEST}${relpath}" \
        --bwlimit "$BWLIMIT" \
        --stats-one-line; then
        log "Successfully offloaded: $relpath"
        # Refresh VFS cache so file is immediately visible in cloud-tiered
        rclone rc --rc-addr "$RC_ADDR" vfs/refresh recursive=true >/dev/null 2>&1 || true
        # Clean any empty parent directories within IMMEDIATE_DIR
        find "$IMMEDIATE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    else
        log "ERROR: Failed to offload: $relpath" >&2
    fi
done
