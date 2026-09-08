# Changelog

All notable changes to **Encrypted Tiered Storage** will be documented in this file.

## [2.0.0] - 2026-09-08

### Added
- **Mount Watchdog Daemon (`watchdog.sh` & `watchdog.service`)**: Automated mount health monitoring daemon performing timed I/O checks; automatically triggers lazy FUSE unmount (`fusermount -uz`), service restart, and Telegram recovery notifications upon mount hangs.
- **Interactive TUI Setup Wizard (`scripts/ets-setup`)**: Full Textual-based terminal wizard with rclone remote auto-detection, path builders, input validation, and direct installation execution.
- **Live Terminal Monitor Dashboard (`scripts/ets-monitor`)**: Textual-powered live dashboard featuring storage capacity gauges, systemd service status grid, log stream, and interactive hotkeys (`F` full sync, `S` smart filer, `P` panic eviction).
- **Multi-Cloud Union Pooling Guide (`docs/MULTI-CLOUD.md`)**: Complete architectural guide and configuration templates for aggregating multiple cloud providers (Google Drive, OneDrive, B2, S3) into a single virtual encrypted pool via rclone `union`.
- **CI / CD Automation (`.github/workflows/ci.yml`)**: Automated GitHub Actions workflow testing shellcheck, shfmt, Python compilation, and dry-run setup input validation.
- **Contribution Guidelines (`CONTRIBUTING.md`)**: Comprehensive documentation covering local dummy testing, bash/Python coding standards, and PR workflows.

### Improved & Hardened
- **Alert Rate Limiting & Debouncing (`scripts/telegram_alert.py`)**: Added duplicate alert suppression within 60s and rate-limiting (>5 alerts/min) to eliminate runaway alert cascades.
- **Concurrency Locking (`scripts/tier-sync.sh`)**: Added `flock` non-blocking file locking on `/tmp/tier-sync-${USER}.lock` to prevent overlapping runs.
- **Graceful Polling Fallback (`scripts/immediate-sync.sh`)**: Added automatic fallback to 30s polling when `inotifywait` is unavailable.
- **Smart Filer Race Condition Safety (`scripts/smart-filer.sh`)**: Fixed git archive race by inspecting deep file modification times (`find -mmin -60`).
- **Setup & Secret Hygiene (`setup.sh`)**: Added OS validation (Linux-only check), CLI flags (`--latest`, `--dry-run`), strict input validation for durations and panic thresholds, and `chmod 600` secret permissions.
- **Codebase Quality**: 100% clean ShellCheck analysis and standardized `shfmt -i 4` formatting across all shell scripts.

## [1.1.0] - 2026-09-08

### Added
- **Hybrid LRU Eviction**: Implemented dual-pass eviction in `tier-sync.sh`:
  - Routine time rule: evicts files older than `SYNC_MIN_AGE`.
  - Emergency panic rule: triggers when local disk usage $\ge$ `PANIC_THRESHOLD` (default 80%), sorting files by access time (oldest atime first) and evicting until usage $\le$ `PANIC_TARGET` (default 60%).
  - Added `--dry-run` flag support to `tier-sync.sh`.
- **Immediate Sync Bypass**: Added `.immediate_sync/` directory watched in real-time by `immediate-sync.service` using `inotifywait`. Files dropped here are immediately offloaded to the cloud tier, bypassing eviction schedules.
- **Real-Time Quota Monitor**: Added `quota-monitor.sh` and `quota-monitor.timer` (running every 5m) which queries `rclone about` and writes human-readable capacity stats to `~/.quota.txt`. Added `statfs_ignore=ro` mergerfs mount option to pass through remote capacity to `df`.
- **Smart Filer (Auto-Organization)**: Added `smart-filer.sh` (config-gated via `SMART_FILER_ENABLED=false` by default) supporting:
  - Documents (`.pdf`, `.doc`, `.docx`, `.odt`) renamed to `YYYY-MM-DD_name.ext` and routed to `Documents/`.
  - Photos (`.jpg`, `.jpeg`, `.png`, `.heic`) organized into `Photos/YYYY/MM/` using EXIF `DateTimeOriginal` or file mtime.
  - Inactive Git repositories (unmodified for > 1 hour) auto-archived into `<repo>.tar.gz`.
- **Pipeline Health Doctor**: Added `doctor.sh` diagnostic utility checking core binaries, mount health, systemd units, and cloud connectivity with a PASS/WARN/FAIL summary.
- **Real-World Use Cases Guide**: Created `docs/USE-CASES.md` covering Media Servers (Plex/Jellyfin), Surveillance NVRs (Frigate), Private Cloud (Nextcloud), Torrent Seeding, and Game Server World Backups.
- **Generic Webhook Alerts**: Extended alert notifier to support generic HTTP webhooks (Discord, Slack, n8n, etc.) alongside Telegram.
- **Test Suite**: Extended `test.sh` to a full 10-phase verification test suite.

## [1.0.0] - 2026-09-08

### Added
- Initial release with client-side `rclone crypt` AES-256 encryption.
- MergerFS tiered storage mount routing writes to fast local cache tier.
- Background routine timer demoting files older than 15 minutes.
- Rootless systemd user unit templates with `OnFailure` Telegram alerting.
- Single-command installer `setup.sh` and safe uninstaller `uninstall.sh`.
