#!/usr/bin/env bash
# ==============================================================================
# Encrypted Tiered Storage - Pipeline Verification Test
# ==============================================================================
set -euo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}[TEST]${NC} $*"; }

CONFIG_FILE="$HOME/.config/encrypted-tiered-storage/storage.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

LOCAL_CACHE="${LOCAL_CACHE_DIR:-$HOME/mnt/local-cache}"
TIERED_MOUNT="${TIERED_MOUNT:-$HOME/mnt/cloud-tiered}"
SYNC_SCRIPT="$HOME/.local/bin/tier-sync.sh"

info "1. Checking active mount points..."
mountpoint -q "$TIERED_MOUNT" || fail "Tiered mount $TIERED_MOUNT is not mounted."
pass "Unified mount is active ($TIERED_MOUNT)"

TEST_FILENAME="test_pipeline_$(date +%s).txt"
TEST_CONTENT="Automated pipeline test at $(date)"
TEST_FILE="${TIERED_MOUNT}/${TEST_FILENAME}"

info "2. Testing instant local write through mergerfs..."
echo "$TEST_CONTENT" > "$TEST_FILE"
if [ -f "${LOCAL_CACHE}/${TEST_FILENAME}" ]; then
    pass "File appeared instantly in fast local cache tier"
else
    fail "File was not routed to local cache tier"
fi

info "3. Executing cloud demotion sync..."
SYNC_MIN_AGE="0s" "$SYNC_SCRIPT" >/dev/null 2>&1 || fail "tier-sync.sh failed"
pass "Sync script executed cleanly"

info "4. Verifying local cache eviction..."
if [ ! -f "${LOCAL_CACHE}/${TEST_FILENAME}" ]; then
    pass "File removed from local cache tier (zero duplication)"
else
    fail "File still exists in local cache after sync"
fi

info "5. Verifying transparent read access..."
READ_CONTENT="$(cat "$TEST_FILE")"
if [ "$READ_CONTENT" = "$TEST_CONTENT" ]; then
    pass "File transparently read through unified tiered mount"
else
    fail "Read content mismatch: expected '$TEST_CONTENT', got '$READ_CONTENT'"
fi

info "6. Cleaning up test file..."
rm -f "$TEST_FILE"
pass "Test file cleaned up"

echo -e "\n${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}    ALL PIPELINE VERIFICATION TESTS PASSED SUCCESSFULLY!    ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}\n"
