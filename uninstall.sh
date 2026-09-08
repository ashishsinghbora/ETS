#!/usr/bin/env bash
# ==============================================================================
# Encrypted Tiered Storage - Safe Uninstaller
# ==============================================================================
set -euo pipefail

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

echo -e "${YELLOW}${BOLD}Stopping and disabling systemd units...${NC}"
systemctl --user stop watchdog.service immediate-sync.service quota-monitor.timer quota-monitor.service mergerfs-mount.service rclone-mount.service tier-sync.timer tier-sync.service 2>/dev/null || true
systemctl --user disable watchdog.service immediate-sync.service quota-monitor.timer quota-monitor.service mergerfs-mount.service rclone-mount.service tier-sync.timer tier-sync.service 2>/dev/null || true

echo -e "${CYAN}Checking and unmounting active mounts...${NC}"
STORAGE_BASE_DIR="${STORAGE_BASE_DIR:-$HOME/mnt}"
fusermount -u "${STORAGE_BASE_DIR}/cloud-tiered" 2>/dev/null || true
fusermount -u "${STORAGE_BASE_DIR}/gcrypt-remote" 2>/dev/null || true

echo -e "${CYAN}Removing systemd unit files...${NC}"
rm -f "$HOME/.config/systemd/user/rclone-mount.service"
rm -f "$HOME/.config/systemd/user/mergerfs-mount.service"
rm -f "$HOME/.config/systemd/user/tier-sync.service"
rm -f "$HOME/.config/systemd/user/tier-sync.timer"
rm -f "$HOME/.config/systemd/user/telegram-alert@.service"
rm -f "$HOME/.config/systemd/user/immediate-sync.service"
rm -f "$HOME/.config/systemd/user/quota-monitor.service"
rm -f "$HOME/.config/systemd/user/quota-monitor.timer"
rm -f "$HOME/.config/systemd/user/watchdog.service"
systemctl --user daemon-reload

echo -e "${CYAN}Removing installed scripts from ~/.local/bin...${NC}"
rm -f "$HOME/.local/bin/tier-sync.sh" \
    "$HOME/.local/bin/immediate-sync.sh" \
    "$HOME/.local/bin/quota-monitor.sh" \
    "$HOME/.local/bin/smart-filer.sh" \
    "$HOME/.local/bin/doctor.sh" \
    "$HOME/.local/bin/watchdog.sh" \
    "$HOME/.local/bin/telegram_alert.py" \
    "$HOME/.local/bin/ets-setup" \
    "$HOME/.local/bin/ets-monitor"

echo -e "${GREEN}${BOLD}Uninstallation complete!${NC}"
echo "Note: Your local cache directory, cloud remote files, and rclone config were NOT deleted."
