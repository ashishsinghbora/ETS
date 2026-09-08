#!/usr/bin/env bash
# ==============================================================================
# Encrypted Tiered Storage - Health & Diagnostic Doctor
# ==============================================================================
set -euo pipefail
export PATH="$HOME/.local/bin:${PATH}"

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

pass() { echo -e "  [${GREEN}PASS${NC}] $*"; }
fail() {
    echo -e "  [${RED}FAIL${NC}] $*"
    FAILED=$((FAILED + 1))
}
warn() {
    echo -e "  [${YELLOW}WARN${NC}] $*"
    WARNINGS=$((WARNINGS + 1))
}

FAILED=0
WARNINGS=0

CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

STORAGE_BASE_DIR="${STORAGE_BASE_DIR:-$HOME/mnt}"
LOCAL_CACHE="${LOCAL_CACHE_DIR:-$STORAGE_BASE_DIR/local-cache}"
REMOTE_MOUNT="${CLOUD_REMOTE_MOUNT:-$STORAGE_BASE_DIR/gcrypt-remote}"
TIERED_MOUNT="${TIERED_MOUNT:-$STORAGE_BASE_DIR/cloud-tiered}"
CRYPT="${CRYPT_REMOTE:-gcrypt}"

echo -e "\n${BOLD}${CYAN}============================================================${NC}"
echo -e "${BOLD}${CYAN}       Encrypted Tiered Storage Pipeline Doctor             ${NC}"
echo -e "${BOLD}${CYAN}============================================================${NC}\n"

# 1. Binary Dependencies
echo -e "${BOLD}1. Core & Optional Binaries:${NC}"
if command -v rclone &>/dev/null; then
    pass "rclone: $(rclone version 2>/dev/null | head -n1)"
else
    fail "rclone is not installed or not in PATH."
fi

if command -v mergerfs &>/dev/null; then
    pass "mergerfs: $(mergerfs -V 2>/dev/null | head -n1)"
else
    fail "mergerfs is not installed or not in PATH."
fi

if command -v inotifywait &>/dev/null; then
    pass "inotifywait: available ($(which inotifywait))"
else
    warn "inotifywait not found. .immediate_sync bypass is inactive."
fi

if command -v exiftool &>/dev/null; then
    pass "exiftool: available (v$(exiftool -ver 2>/dev/null || echo 'unknown'))"
else
    warn "exiftool not found. Smart Filer image routing will fall back to mtime."
fi

# 2. Mount Health
echo -e "\n${BOLD}2. Storage Mount Health:${NC}"
if mountpoint -q "$REMOTE_MOUNT"; then
    pass "Encrypted cloud remote mount is active ($REMOTE_MOUNT)"
else
    fail "Encrypted cloud remote mount is NOT mounted ($REMOTE_MOUNT)"
fi

if mountpoint -q "$TIERED_MOUNT"; then
    pass "Unified tiered mount is active ($TIERED_MOUNT)"
else
    fail "Unified tiered mount is NOT mounted ($TIERED_MOUNT)"
fi

if [ -d "$LOCAL_CACHE" ]; then
    pass "Local cache directory exists ($LOCAL_CACHE)"
else
    fail "Local cache directory is missing ($LOCAL_CACHE)"
fi

# 3. Systemd Units & Timers
echo -e "\n${BOLD}3. Systemd User Units:${NC}"
check_unit() {
    local unit="$1"
    # check type
    if systemctl --user is-active --quiet "$unit"; then
        pass "$unit is active and running"
    else
        if [ "$unit" = "immediate-sync.service" ] && ! command -v inotifywait &>/dev/null; then
            warn "$unit is inactive (inotifywait is not installed)"
        else
            fail "$unit is NOT active ($(systemctl --user is-active "$unit" 2>/dev/null || echo 'failed'))"
        fi
    fi
}

check_unit "rclone-mount.service"
check_unit "mergerfs-mount.service"
check_unit "immediate-sync.service"
check_unit "watchdog.service"
check_unit "tier-sync.timer" "timer"
check_unit "quota-monitor.timer" "timer"

# 4. Remote Connectivity
echo -e "\n${BOLD}4. Cloud Remote Connectivity:${NC}"
if rclone lsd "${CRYPT}:" &>/dev/null; then
    pass "Crypt remote '${CRYPT}:' is reachable and decrypting successfully"
else
    fail "Cannot list or decrypt remote '${CRYPT}:'. Check network or credentials."
fi

# 5. Summary
echo -e "\n${BOLD}============================================================${NC}"
if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  RESULT: ALL CHECKS PASSED! Storage pipeline is 100% healthy.${NC}"
elif [ "$FAILED" -eq 0 ]; then
    echo -e "${YELLOW}${BOLD}  RESULT: Pipeline is functional with $WARNINGS warning(s).${NC}"
else
    echo -e "${RED}${BOLD}  RESULT: Pipeline has $FAILED failure(s) that need attention!${NC}"
fi
echo -e "${BOLD}============================================================${NC}\n"

exit "$FAILED"
