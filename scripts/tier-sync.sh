#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:${PATH}"

# Concurrency protection: prevent overlapping timer and manual runs
LOCK_FILE="/tmp/tier-sync-${USER:-user}.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] tier-sync is already running. Exiting to avoid concurrent race."
    exit 0
fi

# Preserve caller environment overrides
ENV_SYNC_MIN_AGE="${SYNC_MIN_AGE:-}"
ENV_PANIC_THRESHOLD="${PANIC_THRESHOLD:-}"
ENV_PANIC_TARGET="${PANIC_TARGET:-}"
ENV_DRY_RUN="${DRY_RUN:-}"

CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

LOCAL_CACHE="${LOCAL_CACHE_DIR:-$HOME/mnt/local-cache}"
REMOTE_DEST="${CRYPT_REMOTE:-gcrypt}:"
MIN_AGE="${ENV_SYNC_MIN_AGE:-${SYNC_MIN_AGE:-15m}}"
BWLIMIT="${SYNC_BWLIMIT:-5M}"
TRANSFERS="${SYNC_TRANSFERS:-2}"
CHECKERS="${SYNC_CHECKERS:-2}"
RC_ADDR="${RCLONE_RC_ADDR:-127.0.0.1:5572}"
PANIC_THRESHOLD="${ENV_PANIC_THRESHOLD:-${PANIC_THRESHOLD:-80}}"
PANIC_TARGET="${ENV_PANIC_TARGET:-${PANIC_TARGET:-60}}"
LOG_TO_FILE="${LOG_TO_FILE:-false}"
LOG_FILE="${LOG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.log}"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ] || [ "$ENV_DRY_RUN" = "true" ]; then
    DRY_RUN=true
fi

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    if [ "$LOG_TO_FILE" = "true" ] && [ -n "$LOG_FILE" ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "$msg" >>"$LOG_FILE"
    fi
}

if [ ! -d "$LOCAL_CACHE" ]; then
    log "ERROR: Local cache directory $LOCAL_CACHE does not exist." >&2
    exit 1
fi

get_cache_usage() {
    df -P "$LOCAL_CACHE" | awk 'NR==2 {print $5}' | tr -d '%'
}

# ------------------------------------------------------------------------------
# 1. PANIC RULE: Evict oldest files (by access time) if disk usage >= PANIC_THRESHOLD
# ------------------------------------------------------------------------------
current_usage="$(get_cache_usage)"
if [ "$current_usage" -ge "$PANIC_THRESHOLD" ]; then
    log "[PANIC] Local cache filesystem usage ($current_usage%) >= panic threshold ($PANIC_THRESHOLD%). Starting LRU eviction..."

    # Sort files in LOCAL_CACHE by atime (oldest first: %A@)
    find "$LOCAL_CACHE" -mindepth 1 -type f -printf '%A@ %p\0' 2>/dev/null | sort -z -n | while IFS= read -r -d '' entry; do
        curr="$(get_cache_usage)"
        if [ "$curr" -le "$PANIC_TARGET" ]; then
            log "[PANIC] Local cache usage dropped to $curr% (target <= $PANIC_TARGET%). Panic eviction complete."
            break
        fi

        filepath="${entry#* }"
        [ -f "$filepath" ] || continue
        relpath="${filepath#"$LOCAL_CACHE"/}"

        # Smart Filer hook if enabled
        if [ "${SMART_FILER_ENABLED:-false}" = "true" ] && [ -x "$HOME/.local/bin/smart-filer.sh" ]; then
            filepath="$("$HOME/.local/bin/smart-filer.sh" "$filepath" 2>/dev/null || echo "$filepath")"
            [ -f "$filepath" ] || continue
            relpath="${filepath#"$LOCAL_CACHE"/}"
        fi

        log "[PANIC] Evicting LRU file: $relpath (cache usage: $curr%, target <= $PANIC_TARGET%)"
        if [ "$DRY_RUN" = true ]; then
            log "[DRY-RUN] [PANIC] Would move $filepath -> ${REMOTE_DEST}${relpath}"
        else
            rclone moveto "$filepath" "${REMOTE_DEST}${relpath}" \
                --bwlimit "$BWLIMIT" \
                --stats-one-line
        fi
    done

    if [ "$DRY_RUN" != true ]; then
        find "$LOCAL_CACHE" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    fi
else
    log "[ROUTINE] Local cache usage ($current_usage%) < panic threshold ($PANIC_THRESHOLD%). Panic eviction skipped."
fi

# ------------------------------------------------------------------------------
# 2. ROUTINE RULE: Evict files older than SYNC_MIN_AGE
# ------------------------------------------------------------------------------
log "[ROUTINE] Starting routine time-based sync from $LOCAL_CACHE to $REMOTE_DEST (files older than $MIN_AGE)..."

# Smart Filer hook for routine pass if enabled
if [ "${SMART_FILER_ENABLED:-false}" = "true" ] && [ -x "$HOME/.local/bin/smart-filer.sh" ]; then
    "$HOME/.local/bin/smart-filer.sh" --git-dirs 2>/dev/null || true
    find "$LOCAL_CACHE" -mindepth 1 -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
        "$HOME/.local/bin/smart-filer.sh" "$f" 2>/dev/null || true
    done
fi

RCLONE_EXTRA_ARGS=()
if [ "$DRY_RUN" = true ]; then
    RCLONE_EXTRA_ARGS+=(--dry-run)
fi

rclone move "$LOCAL_CACHE" "$REMOTE_DEST" \
    --min-age "$MIN_AGE" \
    --bwlimit "$BWLIMIT" \
    --transfers "$TRANSFERS" \
    --checkers "$CHECKERS" \
    --delete-empty-src-dirs \
    --fast-list \
    --stats-one-line \
    --stats 1m \
    "${RCLONE_EXTRA_ARGS[@]}"

# Refresh rclone mount VFS directory cache so demoted files are immediately visible
if [ "$DRY_RUN" != true ]; then
    rclone rc --rc-addr "$RC_ADDR" vfs/refresh recursive=true >/dev/null 2>&1 || true
fi

log "[ROUTINE] Tier-sync completed successfully."
