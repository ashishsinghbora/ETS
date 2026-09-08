#!/usr/bin/env bash
# ==============================================================================
# Encrypted Tiered Cloud Storage - One-Command Automated Setup
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Colors for terminal output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

# Parse command line flags
FETCH_LATEST_MERGERFS=false
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    --latest        Fetch and install the latest mergerfs release from GitHub
    --dry-run       Validate environment and configuration without changing files
    -h, --help      Show this help message and exit
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
    --latest)
        FETCH_LATEST_MERGERFS=true
        shift
        ;;
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    -h | --help)
        usage
        ;;
    *)
        error "Unknown argument: $1 (run with --help for usage)"
        ;;
    esac
done

echo -e "${BOLD}${BLUE}"
echo "============================================================"
echo "    Encrypted Tiered Cloud Storage Pipeline Installer       "
echo "============================================================"
echo -e "${NC}"

# 1. Environment & Architecture Detection
if [ "$(uname -s)" != "Linux" ]; then
    error "Encrypted Tiered Storage relies on Linux FUSE (mergerfs) and systemd --user. $(uname -s) is not supported."
fi

ARCH="$(uname -m)"
info "Detected architecture: $ARCH"

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    info "Detected OS: ${PRETTY_NAME:-$ID}"
fi

# Preserve caller environment overrides
ENV_CLOUD_REMOTE="${CLOUD_REMOTE:-}"
ENV_CLOUD_REMOTE_FOLDER="${CLOUD_REMOTE_FOLDER:-}"
ENV_CRYPT_REMOTE="${CRYPT_REMOTE:-}"
ENV_STORAGE_BASE_DIR="${STORAGE_BASE_DIR:-}"
ENV_LOCAL_CACHE_DIR="${LOCAL_CACHE_DIR:-}"
ENV_CLOUD_REMOTE_MOUNT="${CLOUD_REMOTE_MOUNT:-}"
ENV_TIERED_MOUNT="${TIERED_MOUNT:-}"
ENV_SYNC_MIN_AGE="${SYNC_MIN_AGE:-}"
ENV_SYNC_INTERVAL="${SYNC_INTERVAL:-}"
ENV_SYNC_BWLIMIT="${SYNC_BWLIMIT:-}"
ENV_PANIC_THRESHOLD="${PANIC_THRESHOLD:-}"
ENV_PANIC_TARGET="${PANIC_TARGET:-}"

# 2. Load Configuration
if [ -f "$CONFIG_FILE" ]; then
    info "Loading configuration from ${CONFIG_FILE}..."
    chmod 600 "$CONFIG_FILE"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    warn "config.env not found. Creating from config.env.example..."
    if [ -f "${SCRIPT_DIR}/config.env.example" ]; then
        cp "${SCRIPT_DIR}/config.env.example" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    else
        error "config.env.example is missing."
    fi
fi

# Re-apply caller environment overrides if provided
[ -n "$ENV_CLOUD_REMOTE" ] && CLOUD_REMOTE="$ENV_CLOUD_REMOTE"
[ -n "$ENV_CLOUD_REMOTE_FOLDER" ] && CLOUD_REMOTE_FOLDER="$ENV_CLOUD_REMOTE_FOLDER"
[ -n "$ENV_CRYPT_REMOTE" ] && CRYPT_REMOTE="$ENV_CRYPT_REMOTE"
[ -n "$ENV_STORAGE_BASE_DIR" ] && STORAGE_BASE_DIR="$ENV_STORAGE_BASE_DIR"
[ -n "$ENV_LOCAL_CACHE_DIR" ] && LOCAL_CACHE_DIR="$ENV_LOCAL_CACHE_DIR"
[ -n "$ENV_CLOUD_REMOTE_MOUNT" ] && CLOUD_REMOTE_MOUNT="$ENV_CLOUD_REMOTE_MOUNT"
[ -n "$ENV_TIERED_MOUNT" ] && TIERED_MOUNT="$ENV_TIERED_MOUNT"
[ -n "$ENV_SYNC_MIN_AGE" ] && SYNC_MIN_AGE="$ENV_SYNC_MIN_AGE"
[ -n "$ENV_SYNC_INTERVAL" ] && SYNC_INTERVAL="$ENV_SYNC_INTERVAL"
[ -n "$ENV_SYNC_BWLIMIT" ] && SYNC_BWLIMIT="$ENV_SYNC_BWLIMIT"
[ -n "$ENV_PANIC_THRESHOLD" ] && PANIC_THRESHOLD="$ENV_PANIC_THRESHOLD"
[ -n "$ENV_PANIC_TARGET" ] && PANIC_TARGET="$ENV_PANIC_TARGET"

# Set defaults
CLOUD_REMOTE="${CLOUD_REMOTE:-gdrive}"
CLOUD_REMOTE_FOLDER="${CLOUD_REMOTE_FOLDER:-encrypted}"
CRYPT_REMOTE="${CRYPT_REMOTE:-gcrypt}"
STORAGE_BASE_DIR="${STORAGE_BASE_DIR:-$HOME/mnt}"
LOCAL_CACHE_DIR="${LOCAL_CACHE_DIR:-$STORAGE_BASE_DIR/local-cache}"
CLOUD_REMOTE_MOUNT="${CLOUD_REMOTE_MOUNT:-$STORAGE_BASE_DIR/gcrypt-remote}"
TIERED_MOUNT="${TIERED_MOUNT:-$STORAGE_BASE_DIR/cloud-tiered}"
SYNC_MIN_AGE="${SYNC_MIN_AGE:-15m}"
SYNC_INTERVAL="${SYNC_INTERVAL:-20m}"
SYNC_BWLIMIT="${SYNC_BWLIMIT:-5M}"
SYNC_TRANSFERS="${SYNC_TRANSFERS:-2}"
SYNC_CHECKERS="${SYNC_CHECKERS:-2}"
RCLONE_RC_ADDR="${RCLONE_RC_ADDR:-127.0.0.1:5572}"
PANIC_THRESHOLD="${PANIC_THRESHOLD:-80}"
PANIC_TARGET="${PANIC_TARGET:-60}"
SMART_FILER_ENABLED="${SMART_FILER_ENABLED:-false}"
TELEGRAM_ALERTS_ENABLED="${TELEGRAM_ALERTS_ENABLED:-false}"
MERGERFS_VERSION="${MERGERFS_VERSION:-2.42.0}"

# Input validation
DURATION_REGEX='^(([0-9]+(ms|s|m|h|d|w|M|y))+|0|off)$'
if ! [[ "$SYNC_MIN_AGE" =~ $DURATION_REGEX ]]; then
    error "Invalid SYNC_MIN_AGE format: '$SYNC_MIN_AGE'. Expected format like 15m, 1h, 0, or off."
fi

if ! [[ "$SYNC_INTERVAL" =~ $DURATION_REGEX ]]; then
    error "Invalid SYNC_INTERVAL format: '$SYNC_INTERVAL'. Expected format like 20m, 1h, 0, or off."
fi

if ! [[ "$PANIC_THRESHOLD" =~ ^[0-9]+$ ]] || ! [[ "$PANIC_TARGET" =~ ^[0-9]+$ ]]; then
    error "PANIC_THRESHOLD ('$PANIC_THRESHOLD') and PANIC_TARGET ('$PANIC_TARGET') must be integers."
fi

if [ "$PANIC_TARGET" -ge "$PANIC_THRESHOLD" ] || [ "$PANIC_THRESHOLD" -gt 100 ] || [ "$PANIC_TARGET" -lt 0 ]; then
    error "Invalid panic thresholds. Must satisfy: 0 <= PANIC_TARGET ($PANIC_TARGET) < PANIC_THRESHOLD ($PANIC_THRESHOLD) <= 100."
fi

if [ "$DRY_RUN" = true ]; then
    info "Dry run requested. Validated configuration:"
    echo "  CLOUD_REMOTE:        ${CLOUD_REMOTE}"
    echo "  CLOUD_REMOTE_FOLDER: ${CLOUD_REMOTE_FOLDER}"
    echo "  CRYPT_REMOTE:        ${CRYPT_REMOTE}"
    echo "  STORAGE_BASE_DIR:    ${STORAGE_BASE_DIR}"
    echo "  LOCAL_CACHE_DIR:     ${LOCAL_CACHE_DIR}"
    echo "  CLOUD_REMOTE_MOUNT:  ${CLOUD_REMOTE_MOUNT}"
    echo "  TIERED_MOUNT:        ${TIERED_MOUNT}"
    echo "  SYNC_MIN_AGE:        ${SYNC_MIN_AGE}"
    echo "  SYNC_INTERVAL:       ${SYNC_INTERVAL}"
    echo "  PANIC_THRESHOLD:     ${PANIC_THRESHOLD}%"
    echo "  PANIC_TARGET:        ${PANIC_TARGET}%"
    success "Dry run validation completed successfully."
    exit 0
fi

# Ensure directories exist
mkdir -p "$HOME/.local/bin" "$HOME/.config/encrypted-tiered-storage" "$HOME/.config/systemd/user"
mkdir -p "$LOCAL_CACHE_DIR" "$CLOUD_REMOTE_MOUNT" "$TIERED_MOUNT" "$TIERED_MOUNT/.immediate_sync"
export PATH="$HOME/.local/bin:$PATH"

# 3. Check / Install Dependencies
info "Checking rclone..."
if ! command -v rclone &>/dev/null; then
    warn "rclone is not installed. Attempting official installation..."
    curl -fsSL https://rclone.org/install.sh | bash || error "Failed to install rclone. Please install manually."
fi
success "rclone is available: $(rclone version | head -n1)"

info "Checking mergerfs..."
if [ "$FETCH_LATEST_MERGERFS" = true ]; then
    info "Querying latest mergerfs version from GitHub..."
    LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/trapexit/mergerfs/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ -n "$LATEST_TAG" ]; then
        MERGERFS_VERSION="$LATEST_TAG"
        info "Latest mergerfs version found: $MERGERFS_VERSION"
    else
        warn "Could not determine latest mergerfs version; defaulting to $MERGERFS_VERSION"
    fi
fi

if ! command -v mergerfs &>/dev/null; then
    info "mergerfs not found. Installing static prebuilt binary ($MERGERFS_VERSION) for $ARCH..."
    MFS_TAG="$MERGERFS_VERSION"
    case "$ARCH" in
    x86_64) MFS_ARCH="linux_amd64" ;;
    aarch64 | arm64) MFS_ARCH="linux_arm64" ;;
    armv7l | armhf) MFS_ARCH="linux_armhf" ;;
    *) error "Unsupported architecture for prebuilt mergerfs: $ARCH" ;;
    esac

    TMP_DIR="$(mktemp -d)"
    TAR_URL="https://github.com/trapexit/mergerfs/releases/download/${MFS_TAG}/mergerfs-${MFS_TAG}-static-${MFS_ARCH}.tar.gz"
    info "Downloading $TAR_URL..."
    curl -fsSL "$TAR_URL" -o "${TMP_DIR}/mergerfs.tar.gz"
    tar -xzf "${TMP_DIR}/mergerfs.tar.gz" -C "$HOME/.local/" --strip-components=2 usr/local/bin/
    rm -f "$HOME/.local/bin/mergerfs-fusermount"
    chmod +x "$HOME/.local/bin/mergerfs"*
    rm -rf "$TMP_DIR"
fi
success "mergerfs is available: $(mergerfs -V | head -n1)"

info "Checking inotify-tools (for .immediate_sync bypass)..."
if ! command -v inotifywait &>/dev/null; then
    warn "inotifywait not found. Attempting package manager installation..."
    OS_FAMILY="${ID:-} ${ID_LIKE:-}"
    case "$OS_FAMILY" in
    *debian* | *ubuntu* | *raspbian*)
        sudo apt-get update -y || true
        sudo apt-get install -y inotify-tools || true
        ;;
    *arch* | *manjaro*)
        sudo pacman -S --noconfirm inotify-tools || true
        ;;
    *fedora* | *rhel* | *centos*)
        sudo dnf install -y inotify-tools || true
        ;;
    *alpine*)
        sudo apk add inotify-tools || true
        ;;
    esac
    if ! command -v inotifywait &>/dev/null; then
        warn "inotify-tools could not be installed automatically. Immediate sync will fall back to polling."
    else
        success "inotify-tools installed successfully."
    fi
else
    success "inotifywait is available."
fi

info "Checking exiftool (for Smart Filer photo EXIF routing)..."
if ! command -v exiftool &>/dev/null; then
    warn "exiftool not found. Attempting package manager installation..."
    OS_FAMILY="${ID:-} ${ID_LIKE:-}"
    case "$OS_FAMILY" in
    *debian* | *ubuntu* | *raspbian*)
        sudo apt-get update -y || true
        sudo apt-get install -y libimage-exiftool-perl || true
        ;;
    *arch* | *manjaro*)
        sudo pacman -S --noconfirm perl-image-exiftool || true
        ;;
    *fedora* | *rhel* | *centos*)
        sudo dnf install -y perl-Image-ExifTool || true
        ;;
    *alpine*)
        sudo apk add exiftool || true
        ;;
    esac
    if ! command -v exiftool &>/dev/null; then
        warn "exiftool is not installed. Smart Filer will fall back to file mtime for photo dates."
    else
        success "exiftool installed successfully."
    fi
else
    success "exiftool is available."
fi

info "Checking Python environment and TUI packages (textual, rich)..."
if command -v python3 &>/dev/null; then
    if ! python3 -c "import textual, rich" &>/dev/null; then
        info "Installing optional visual dashboard dependencies (textual, rich)..."
        python3 -m pip install --user textual rich 2>/dev/null || pip3 install --user textual rich --break-system-packages 2>/dev/null || warn "Could not install textual/rich automatically. ets-monitor will run in CLI mode."
    fi
    success "Python environment is ready."
else
    warn "python3 is not installed. Install python3 for alert scripts and ets-monitor."
fi

# Ensure ~/.local/bin is permanently in user shell PATH across bashrc, zshrc, and profile
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$rc" ] && ! grep -q 'PATH=.*\.local/bin' "$rc"; then
        # shellcheck disable=SC2016
        echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$rc"
    fi
done

# Create root-level convenience symlinks
ln -sf scripts/ets-monitor "${SCRIPT_DIR}/ets-monitor"
ln -sf scripts/ets-setup "${SCRIPT_DIR}/ets-setup"
ln -sf scripts/doctor.sh "${SCRIPT_DIR}/doctor.sh"

# 4. Verify Cloud Remote
info "Checking cloud remote ${CLOUD_REMOTE}:..."
if ! rclone lsd "${CLOUD_REMOTE}:" &>/dev/null; then
    echo -e "${RED}[ERROR] Remote ${CLOUD_REMOTE}: is not configured or not accessible.${NC}"
    echo "Please run: rclone config to authenticate your cloud drive first."
    exit 1
fi
success "Cloud remote ${CLOUD_REMOTE}: verified."

# Create remote encrypted storage folder
rclone mkdir "${CLOUD_REMOTE}:${CLOUD_REMOTE_FOLDER}"

# 5. Configure Crypt Remote
GENERATED_PASSWORD=false
if [ -z "${CRYPT_PASSWORD:-}" ]; then
    GENERATED_PASSWORD=true
    if command -v python3 &>/dev/null; then
        CRYPT_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
    else
        CRYPT_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)"
    fi
fi

info "Configuring crypt remote ${CRYPT_REMOTE}: backed by ${CLOUD_REMOTE}:${CLOUD_REMOTE_FOLDER}..."
rclone config create "$CRYPT_REMOTE" crypt \
    remote "${CLOUD_REMOTE}:${CLOUD_REMOTE_FOLDER}" \
    filename_encryption standard \
    directory_name_encryption true \
    password "$CRYPT_PASSWORD" >/dev/null

rclone config password "$CRYPT_REMOTE" password "$CRYPT_PASSWORD" >/dev/null
success "Crypt remote ${CRYPT_REMOTE}: configured successfully."

if [ "$GENERATED_PASSWORD" = true ]; then
    echo -e "\n${RED}${BOLD}============================================================${NC}"
    echo -e "${YELLOW}${BOLD}⚠️  CRITICAL: BACK UP YOUR ENCRYPTION PASSWORD NOW!${NC}"
    echo -e "${BOLD}Password:${NC} ${GREEN}${CRYPT_PASSWORD}${NC}"
    echo -e "Losing this password means permanent loss of encrypted data."
    echo -e "${RED}${BOLD}============================================================${NC}\n"
fi

# 6. Install Scripts & Environment Configuration
info "Installing scripts and user configuration..."
RCLONE_BIN="$(command -v rclone)"
MERGERFS_BIN="$(command -v mergerfs)"
ALERT_SCRIPT="$HOME/.local/bin/telegram_alert.py"
SYNC_SCRIPT="$HOME/.local/bin/tier-sync.sh"
IMMEDIATE_SCRIPT="$HOME/.local/bin/immediate-sync.sh"
QUOTA_SCRIPT="$HOME/.local/bin/quota-monitor.sh"
SMART_FILER_SCRIPT="$HOME/.local/bin/smart-filer.sh"
DOCTOR_SCRIPT="$HOME/.local/bin/doctor.sh"
WATCHDOG_SCRIPT="$HOME/.local/bin/watchdog.sh"

cp "${SCRIPT_DIR}/scripts/tier-sync.sh" "$SYNC_SCRIPT"
cp "${SCRIPT_DIR}/scripts/immediate-sync.sh" "$IMMEDIATE_SCRIPT"
cp "${SCRIPT_DIR}/scripts/quota-monitor.sh" "$QUOTA_SCRIPT"
cp "${SCRIPT_DIR}/scripts/smart-filer.sh" "$SMART_FILER_SCRIPT"
cp "${SCRIPT_DIR}/scripts/doctor.sh" "$DOCTOR_SCRIPT"
cp "${SCRIPT_DIR}/scripts/watchdog.sh" "$WATCHDOG_SCRIPT"
cp "${SCRIPT_DIR}/scripts/telegram_alert.py" "$ALERT_SCRIPT"
cp "${SCRIPT_DIR}/scripts/ets-setup" "$HOME/.local/bin/ets-setup"
cp "${SCRIPT_DIR}/scripts/ets-monitor" "$HOME/.local/bin/ets-monitor"
chmod +x "$SYNC_SCRIPT" "$IMMEDIATE_SCRIPT" "$QUOTA_SCRIPT" "$SMART_FILER_SCRIPT" "$DOCTOR_SCRIPT" "$WATCHDOG_SCRIPT" "$ALERT_SCRIPT" "$HOME/.local/bin/ets-setup" "$HOME/.local/bin/ets-monitor"

# Save persistent storage config
cat <<EOF_ENV >"$HOME/.config/encrypted-tiered-storage/storage.env"
LOCAL_CACHE_DIR="${LOCAL_CACHE_DIR}"
CLOUD_REMOTE_MOUNT="${CLOUD_REMOTE_MOUNT}"
TIERED_MOUNT="${TIERED_MOUNT}"
CRYPT_REMOTE="${CRYPT_REMOTE}"
SYNC_MIN_AGE="${SYNC_MIN_AGE}"
SYNC_BWLIMIT="${SYNC_BWLIMIT}"
SYNC_TRANSFERS="${SYNC_TRANSFERS}"
SYNC_CHECKERS="${SYNC_CHECKERS}"
RCLONE_RC_ADDR="${RCLONE_RC_ADDR}"
PANIC_THRESHOLD="${PANIC_THRESHOLD}"
PANIC_TARGET="${PANIC_TARGET}"
SMART_FILER_ENABLED="${SMART_FILER_ENABLED}"
EOF_ENV
chmod 600 "$HOME/.config/encrypted-tiered-storage/storage.env"

# Save Telegram configuration
cat <<EOF_TEL >"$HOME/.config/encrypted-tiered-storage/telegram.env"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
EOF_TEL
chmod 600 "$HOME/.config/encrypted-tiered-storage/telegram.env"

# 7. Render & Install Systemd User Units
info "Deploying systemd user units..."

render_template() {
    local src="$1"
    local dst="$2"
    sed -e "s|{{RCLONE_BIN}}|${RCLONE_BIN}|g" \
        -e "s|{{MERGERFS_BIN}}|${MERGERFS_BIN}|g" \
        -e "s|{{CRYPT_REMOTE}}|${CRYPT_REMOTE}|g" \
        -e "s|{{CLOUD_REMOTE_MOUNT}}|${CLOUD_REMOTE_MOUNT}|g" \
        -e "s|{{LOCAL_CACHE_DIR}}|${LOCAL_CACHE_DIR}|g" \
        -e "s|{{TIERED_MOUNT}}|${TIERED_MOUNT}|g" \
        -e "s|{{SYNC_SCRIPT}}|${SYNC_SCRIPT}|g" \
        -e "s|{{IMMEDIATE_SCRIPT}}|${IMMEDIATE_SCRIPT}|g" \
        -e "s|{{QUOTA_SCRIPT}}|${QUOTA_SCRIPT}|g" \
        -e "s|{{WATCHDOG_SCRIPT}}|${WATCHDOG_SCRIPT}|g" \
        -e "s|{{ALERT_SCRIPT}}|${ALERT_SCRIPT}|g" \
        -e "s|{{SYNC_INTERVAL}}|${SYNC_INTERVAL}|g" \
        -e "s|{{RCLONE_RC_ADDR}}|${RCLONE_RC_ADDR}|g" \
        "$src" >"$dst"
}

render_template "${SCRIPT_DIR}/systemd/rclone-mount.service.template" "$HOME/.config/systemd/user/rclone-mount.service"
render_template "${SCRIPT_DIR}/systemd/mergerfs-mount.service.template" "$HOME/.config/systemd/user/mergerfs-mount.service"
render_template "${SCRIPT_DIR}/systemd/tier-sync.service.template" "$HOME/.config/systemd/user/tier-sync.service"
render_template "${SCRIPT_DIR}/systemd/tier-sync.timer.template" "$HOME/.config/systemd/user/tier-sync.timer"
render_template "${SCRIPT_DIR}/systemd/immediate-sync.service.template" "$HOME/.config/systemd/user/immediate-sync.service"
render_template "${SCRIPT_DIR}/systemd/quota-monitor.service.template" "$HOME/.config/systemd/user/quota-monitor.service"
render_template "${SCRIPT_DIR}/systemd/quota-monitor.timer.template" "$HOME/.config/systemd/user/quota-monitor.timer"
render_template "${SCRIPT_DIR}/systemd/watchdog.service.template" "$HOME/.config/systemd/user/watchdog.service"
render_template "${SCRIPT_DIR}/systemd/telegram-alert@.service.template" "$HOME/.config/systemd/user/telegram-alert@.service"

# Reload and enable services
systemctl --user daemon-reload
systemctl --user enable --now rclone-mount.service mergerfs-mount.service tier-sync.timer quota-monitor.timer watchdog.service

if command -v inotifywait &>/dev/null; then
    systemctl --user enable --now immediate-sync.service
    success "immediate-sync.service started."
fi

success "Systemd user services and timers started."

# Enable lingering so services survive user logout
loginctl enable-linger "$USER" 2>/dev/null || true

# Generate initial quota file
"$QUOTA_SCRIPT" 2>/dev/null || true

# 8. Test Telegram Notification (if configured)
if [ "${TELEGRAM_ALERTS_ENABLED}" = "true" ] && [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    info "Sending test Telegram alert..."
    if "$ALERT_SCRIPT" "🚀 Encrypted Tiered Storage successfully deployed on $(hostname)!" 2>/dev/null; then
        success "Telegram notification sent!"
    else
        warn "Could not send Telegram test message. Please verify BOT_TOKEN and CHAT_ID."
    fi
fi

# 9. Verify Mounts
sleep 2
if mountpoint -q "$CLOUD_REMOTE_MOUNT" && mountpoint -q "$TIERED_MOUNT"; then
    success "All storage tiers mounted and active!"
else
    error "One or more mount points failed to activate. Check journalctl --user -xe."
fi

echo -e "\n${GREEN}${BOLD}Setup Completed Successfully! 🎉${NC}"
echo -e "Unified Storage Mount: ${CYAN}${TIERED_MOUNT}${NC}"
echo -e "Write your files directly to this directory."
echo -e "Run ${BOLD}doctor.sh${NC} anytime to verify system health."
echo -e "Run ${BOLD}ets-monitor${NC} for real-time dashboard and live controls."
