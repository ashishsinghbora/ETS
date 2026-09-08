#!/usr/bin/env bash
# ==============================================================================
# Encrypted Tiered Storage - Mount Watchdog Daemon
# ==============================================================================
set -euo pipefail
export PATH="$HOME/.local/bin:${PATH}"

CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

CLOUD_REMOTE_MOUNT="${CLOUD_REMOTE_MOUNT:-$HOME/mnt/gcrypt-remote}"
TIERED_MOUNT="${TIERED_MOUNT:-$HOME/mnt/cloud-tiered}"
ALERT_SCRIPT="${ALERT_SCRIPT:-$HOME/.local/bin/telegram_alert.py}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-30}"
WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-10}"
LOG_FILE="${LOG_FILE:-$HOME/.config/encrypted-tiered-storage/watchdog.log}"
LOG_TO_FILE="${LOG_TO_FILE:-false}"

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WATCHDOG] $*"
    echo "$msg"
    if [ "$LOG_TO_FILE" = "true" ] && [ -n "$LOG_FILE" ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "$msg" >>"$LOG_FILE"
    fi
}

send_alert() {
    local text="$1"
    if [ -x "$ALERT_SCRIPT" ]; then
        "$ALERT_SCRIPT" "$text" 2>/dev/null || true
    fi
}

check_health() {
    # Check systemd service status first
    if ! systemctl --user is-active --quiet rclone-mount.service; then
        log "rclone-mount.service is not active"
        return 1
    fi
    if ! systemctl --user is-active --quiet mergerfs-mount.service; then
        log "mergerfs-mount.service is not active"
        return 1
    fi

    # Check mount points
    if ! mountpoint -q "$CLOUD_REMOTE_MOUNT"; then
        log "Cloud mountpoint $CLOUD_REMOTE_MOUNT is not mounted"
        return 1
    fi
    if ! mountpoint -q "$TIERED_MOUNT"; then
        log "Tiered mountpoint $TIERED_MOUNT is not mounted"
        return 1
    fi

    # Test I/O responsiveness with strict timeout
    if ! timeout "$WATCHDOG_TIMEOUT" stat "$TIERED_MOUNT" >/dev/null 2>&1; then
        log "stat timed out or failed on $TIERED_MOUNT"
        return 1
    fi

    local healthcheck_file="${TIERED_MOUNT}/.healthcheck"
    if ! timeout "$WATCHDOG_TIMEOUT" touch "$healthcheck_file" >/dev/null 2>&1; then
        log "touch timed out or failed on $healthcheck_file"
        return 1
    fi

    return 0
}

recover() {
    log "Initiating automatic recovery procedure..."
    send_alert "⚠️ [WATCHDOG] Tiered storage mount hang detected on $(hostname). Attempting automated recovery..."

    # Lazy unmount potentially hung FUSE mounts
    fusermount -uz "$TIERED_MOUNT" 2>/dev/null || true
    fusermount -uz "$CLOUD_REMOTE_MOUNT" 2>/dev/null || true
    sleep 2

    # Restart underlying services
    systemctl --user restart rclone-mount.service mergerfs-mount.service || true
    sleep 3

    # Check recovery result
    if mountpoint -q "$CLOUD_REMOTE_MOUNT" && mountpoint -q "$TIERED_MOUNT"; then
        log "Recovery succeeded: all mounts restored and active"
        send_alert "♻️ [WATCHDOG] Tiered storage mounts recovered successfully on $(hostname)."
    else
        log "Recovery failed: mounts are still inactive"
        send_alert "🚨 [WATCHDOG] Automated recovery failed on $(hostname)! Manual intervention required."
    fi
}

running=true
trap 'running=false; log "Watchdog stopping..."; exit 0' SIGINT SIGTERM

log "Starting watchdog daemon (interval: ${WATCHDOG_INTERVAL}s, timeout: ${WATCHDOG_TIMEOUT}s)..."

while [ "$running" = true ]; do
    if ! check_health; then
        recover
    fi
    sleep "$WATCHDOG_INTERVAL" &
    wait $!
done
