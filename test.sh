#!/usr/bin/env bash
# ==============================================================================
# Encrypted Tiered Storage - Full Pipeline Verification Test Suite
# ==============================================================================
set -euo pipefail
export PATH="$HOME/.local/bin:${PATH}"

RED="\033[0;31m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

pass() { echo -e "  [${GREEN}PASS${NC}] $*"; }
fail() {
    echo -e "  [${RED}FAIL${NC}] $*" >&2
    exit 1
}
info() { echo -e "\n${CYAN}${BOLD}[TEST $1]${NC} $2"; }

CONFIG_FILE="$HOME/.config/encrypted-tiered-storage/storage.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

LOCAL_CACHE="${LOCAL_CACHE_DIR:-$HOME/mnt/local-cache}"
TIERED_MOUNT="${TIERED_MOUNT:-$HOME/mnt/cloud-tiered}"
CRYPT_REMOTE_NAME="${CRYPT_REMOTE:-gcrypt}"
SYNC_SCRIPT="$HOME/.local/bin/tier-sync.sh"
QUOTA_SCRIPT="$HOME/.local/bin/quota-monitor.sh"
SMART_FILER_SCRIPT="$HOME/.local/bin/smart-filer.sh"
DOCTOR_SCRIPT="$HOME/.local/bin/doctor.sh"

TEST_FILENAME="test_pipeline_$(date +%s).txt"
IMM_TEST_NAME="imm_test_$(date +%s).txt"
PANIC_FILE_PATTERN="panic_lru_test_*.txt"
FAKE_GIT_PREFIX="fake_git_"

cleanup() {
    rm -f "${TIERED_MOUNT}/${TEST_FILENAME}" 2>/dev/null || true
    rm -f "${TIERED_MOUNT}/.immediate_sync/${IMM_TEST_NAME}" 2>/dev/null || true
    find "${TIERED_MOUNT}" -maxdepth 1 -name "$PANIC_FILE_PATTERN" -delete 2>/dev/null || true
    find "${LOCAL_CACHE}" -maxdepth 1 -name "$PANIC_FILE_PATTERN" -delete 2>/dev/null || true
    find "${LOCAL_CACHE}" -maxdepth 1 -name "${FAKE_GIT_PREFIX}*" -exec rm -rf {} + 2>/dev/null || true
    rclone deletefile "${CRYPT_REMOTE_NAME}:${IMM_TEST_NAME}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo -e "${BOLD}${CYAN}============================================================${NC}"
echo -e "${BOLD}${CYAN}    Running Encrypted Tiered Storage Verification Suite     ${NC}"
echo -e "${BOLD}${CYAN}============================================================${NC}"

# 1. Mount Points
info "1" "Checking active storage mount points..."
mountpoint -q "$TIERED_MOUNT" || fail "Tiered mount $TIERED_MOUNT is not mounted."
pass "Unified mount is active ($TIERED_MOUNT)"

# 2. Instant Local Write
TEST_CONTENT="Automated pipeline test at $(date)"
TEST_FILE="${TIERED_MOUNT}/${TEST_FILENAME}"

info "2" "Testing instant local write through mergerfs..."
echo "$TEST_CONTENT" >"$TEST_FILE"
if [ -f "${LOCAL_CACHE}/${TEST_FILENAME}" ]; then
    pass "File appeared instantly in fast local cache tier"
else
    fail "File was not routed to local cache tier"
fi

# 3. Routine Demotion Sync
info "3" "Executing routine cloud demotion sync..."
SYNC_MIN_AGE="0s" "$SYNC_SCRIPT" >/dev/null 2>&1 || fail "tier-sync.sh failed"
pass "Sync script executed cleanly"

# 4. Local Cache Eviction
info "4" "Verifying local cache eviction..."
if [ ! -f "${LOCAL_CACHE}/${TEST_FILENAME}" ]; then
    pass "File removed from local cache tier (zero duplication)"
else
    fail "File still exists in local cache after sync"
fi

# 5. Transparent Read
info "5" "Verifying transparent read access..."
READ_CONTENT="$(cat "$TEST_FILE")"
if [ "$READ_CONTENT" = "$TEST_CONTENT" ]; then
    pass "File transparently read through unified tiered mount"
else
    fail "Read content mismatch: expected '$TEST_CONTENT', got '$READ_CONTENT'"
fi
rm -f "$TEST_FILE"
pass "Test file cleaned up"

# 6. Immediate Sync Bypass
info "6" "Testing .immediate_sync bypass folder..."
mkdir -p "${TIERED_MOUNT}/.immediate_sync"
IMM_TEST_FILE="${TIERED_MOUNT}/.immediate_sync/${IMM_TEST_NAME}"
echo "Immediate bypass payload $(date)" >"$IMM_TEST_FILE"

# Wait for inotifywatcher / process to offload
MAX_WAIT=60
WAITED=0
while [ -f "$IMM_TEST_FILE" ] && [ "$WAITED" -lt "$MAX_WAIT" ]; do
    sleep 1
    WAITED=$((WAITED + 1))
done

if [ ! -f "$IMM_TEST_FILE" ]; then
    pass ".immediate_sync file captured and offloaded in ${WAITED}s"
else
    fail ".immediate_sync file was not offloaded within ${MAX_WAIT}s"
fi

# Clean up offloaded file from remote
rclone deletefile "${CRYPT_REMOTE_NAME}:${IMM_TEST_NAME}" 2>/dev/null || true
pass "Immediate sync test file cleaned up"

# 7. Panic LRU Eviction Test
info "7" "Testing panic-rule LRU eviction..."
PANIC_FILE="${TIERED_MOUNT}/panic_lru_test_$(date +%s).txt"
echo "Panic payload $(date)" >"$PANIC_FILE"
PANIC_OUTPUT="$(PANIC_THRESHOLD=1 PANIC_TARGET=1 "$SYNC_SCRIPT" --dry-run 2>&1 || true)"
if echo "$PANIC_OUTPUT" | grep -q "\[PANIC\]"; then
    pass "Panic rule triggered correctly and logged [PANIC]"
else
    fail "Panic rule did not log [PANIC]: $PANIC_OUTPUT"
fi
rm -f "$PANIC_FILE" 2>/dev/null || true
pass "Panic rule eviction logic verified"

# 8. Quota Monitor
info "8" "Verifying real-time quota monitor..."
"$QUOTA_SCRIPT"
QUOTA_FILE="${TIERED_MOUNT}/.quota.txt"
if [ -f "$QUOTA_FILE" ] && grep -q "Cloud Capacity" "$QUOTA_FILE" && grep -q "Local Cache" "$QUOTA_FILE"; then
    pass ".quota.txt exists and contains valid metrics"
    echo -e "${CYAN}    $(head -n 2 "$QUOTA_FILE" | tr '\n' ' | ')${NC}"
else
    fail ".quota.txt missing or format invalid"
fi

# 9. Smart Filer Test
info "9" "Verifying Smart Filer organization rules..."
TEST_DOC="${LOCAL_CACHE}/testdoc_$(date +%s).pdf"
touch "$TEST_DOC"
"$SMART_FILER_SCRIPT" "$TEST_DOC" >/dev/null 2>&1 || true
DOC_COUNT="$(find "${LOCAL_CACHE}/Documents" -name "*testdoc*" 2>/dev/null | wc -l)"
if [ "$DOC_COUNT" -gt 0 ]; then
    pass "Smart Filer routed and renamed document into Documents/"
else
    fail "Smart Filer failed to organize document"
fi

# Test git archiving
FAKE_GIT_DIR="${LOCAL_CACHE}/fake_git_$(date +%s)"
mkdir -p "${FAKE_GIT_DIR}/.git"
touch -d "2 hours ago" "$FAKE_GIT_DIR" "${FAKE_GIT_DIR}/.git"
"$SMART_FILER_SCRIPT" --git-dirs >/dev/null 2>&1 || true
if [ -f "${FAKE_GIT_DIR}.tar.gz" ] && [ ! -d "$FAKE_GIT_DIR" ]; then
    pass "Smart Filer archived inactive git repository into .tar.gz"
else
    fail "Smart Filer failed to archive inactive git repo"
fi
# Clean up smart filer test artifacts
rm -rf "${LOCAL_CACHE}/Documents" "${FAKE_GIT_DIR}.tar.gz"
pass "Smart Filer test artifacts cleaned up"

# 10. Doctor Diagnostic
info "10" "Running doctor.sh health check..."
if "$DOCTOR_SCRIPT" >/dev/null; then
    pass "doctor.sh reports 100% healthy pipeline"
else
    fail "doctor.sh detected issues"
fi

echo -e "\n${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}    ALL 10 VERIFICATION TESTS PASSED SUCCESSFULLY! 🎉      ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}\n"
