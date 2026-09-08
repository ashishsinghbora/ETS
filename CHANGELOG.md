# Changelog

All notable changes to **Encrypted Tiered Storage** will be documented in this file.

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
