#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:${PATH}"

CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

LOCAL_CACHE="${LOCAL_CACHE_DIR:-$HOME/mnt/local-cache}"
TIERED_MOUNT="${TIERED_MOUNT:-$HOME/mnt/cloud-tiered}"
REMOTE="${CRYPT_REMOTE:-gcrypt}:"
QUOTA_FILE="${TIERED_MOUNT}/.quota.txt"

if [ ! -d "$TIERED_MOUNT" ]; then
    exit 0
fi

# 1. Cloud capacity
CLOUD_LINE="Cloud Capacity: Quota reporting not supported by this remote"
ABOUT_JSON="$(rclone about "$REMOTE" --json 2>/dev/null || true)"
if [ -n "$ABOUT_JSON" ] && command -v python3 &>/dev/null; then
    PARSED=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
    used = data.get("used", 0)
    total = data.get("total")
    
    def fmt(b):
        if b is None: return "Unknown"
        b = float(b)
        for u in ["B", "KB", "MB", "GB", "TB", "PB"]:
            if b < 1024.0 or u == "PB":
                return f"{b:.2f} {u}"
            b /= 1024.0

    if total:
        pct = (float(used) / float(total)) * 100
        print(f"{fmt(used)} / {fmt(total)} Used ({pct:.1f}%)")
    else:
        print(f"{fmt(used)} Used")
except Exception:
    sys.exit(1)
' "$ABOUT_JSON" 2>/dev/null || true)

    if [ -n "$PARSED" ]; then
        CLOUD_LINE="Cloud Capacity: $PARSED"
    fi
fi

# 2. Local cache usage
LOCAL_USED="$(du -sh "$LOCAL_CACHE" 2>/dev/null | awk '{print $1}')"
LOCAL_USED="${LOCAL_USED:-0B}"
LOCAL_DISK_INFO="$(df -h "$LOCAL_CACHE" 2>/dev/null | awk 'NR==2 {print $2 " (" $5 " full)"}')"
LOCAL_LINE="Local Cache:    $LOCAL_USED / ${LOCAL_DISK_INFO:-Local Disk}"

# 3. Write human-readable quota file atomically
TMP_QUOTA="${QUOTA_FILE}.tmp.$$"
printf "%s\n%s\nLast updated:   %s\n" "$CLOUD_LINE" "$LOCAL_LINE" "$(date)" > "$TMP_QUOTA"
mv "$TMP_QUOTA" "$QUOTA_FILE"
