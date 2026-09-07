#!/usr/bin/env bash
set -euo pipefail

# Default fallback values (overridden by environment or config)
CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

LOCAL_CACHE="${LOCAL_CACHE_DIR:-$HOME/mnt/local-cache}"
REMOTE_DEST="${CRYPT_REMOTE:-gcrypt}:"
MIN_AGE="${SYNC_MIN_AGE:-15m}"
BWLIMIT="${SYNC_BWLIMIT:-5M}"
TRANSFERS="${SYNC_TRANSFERS:-2}"
CHECKERS="${SYNC_CHECKERS:-2}"
RC_ADDR="${RCLONE_RC_ADDR:-127.0.0.1:5572}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [ ! -d "$LOCAL_CACHE" ]; then
    log "ERROR: Local cache directory $LOCAL_CACHE does not exist." >&2
    exit 1
fi

log "Starting tier-sync from $LOCAL_CACHE to $REMOTE_DEST (files older than $MIN_AGE)..."

rclone move "$LOCAL_CACHE" "$REMOTE_DEST" \
    --min-age "$MIN_AGE" \
    --bwlimit "$BWLIMIT" \
    --transfers "$TRANSFERS" \
    --checkers "$CHECKERS" \
    --delete-empty-src-dirs \
    --fast-list \
    --stats-one-line \
    --stats 1m

# Refresh rclone mount VFS directory cache so demoted files are immediately visible
rclone rc --rc-addr "$RC_ADDR" vfs/refresh recursive=true >/dev/null 2>&1 || true

log "Tier-sync completed successfully."
