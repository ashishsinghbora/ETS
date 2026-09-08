# 📚 Real-World Use Cases & Application Configurations

This guide provides concrete, battle-tested configuration blueprints for integrating applications with **Encrypted Tiered Storage**.

> **Note on Storage Realities:** Storage capacity is bounded by your cloud provider's actual quota plan (e.g. 2 TB Google Workspace, 5 TB Google One, etc.). "Zero-buffer" refers to local write/read caching performance before files are lazily demoted to encrypted cloud storage.

---

## 1. Zero-Buffer 4K Media Server (Plex / Jellyfin / Emby)

### The Challenge
Directly downloading 40–80 GB 4K remuxes to an rclone cloud mount causes socket timeouts, buffer exhaustion, and API rate limiting. Playing recently downloaded media directly from cloud mounts can also cause initial buffering delays.

### Architecture Blueprint
- **Download Client (qBittorrent / SABnzbd):** Set completed download directory to `~/mnt/cloud-tiered/Media`.
- **Media Server (Plex / Jellyfin):** Point library paths to `~/mnt/cloud-tiered/Media/Movies` and `~/mnt/cloud-tiered/Media/TV`.
- **Flow:**
  1. Downloader writes to `~/mnt/cloud-tiered/Media` at full local NVMe/SSD speed without network lag.
  2. You can immediately watch the newly downloaded media in Plex with zero buffering because it resides on local SSD cache.
  3. After `SYNC_MIN_AGE` passes, the file is encrypted with AES-256 and uploaded to cloud storage in the background.
  4. The local file is deleted, freeing disk space. The file remains visible at the exact same path in Plex, streamed on demand via rclone VFS cache.

### Recommended `config.env` Tuning
```env
SYNC_MIN_AGE="6h"           # Keep freshly downloaded media on fast local SSD for 6 hours
SYNC_INTERVAL="30m"         # Offload batches every 30 minutes
SYNC_BWLIMIT="15M"          # Avoid saturating your home connection
PANIC_THRESHOLD="85"        # Evict older media early if disk exceeds 85%
PANIC_TARGET="65"
```

---

## 2. NVR & Security Camera Archive (Frigate / Blue Iris)

### The Challenge
Surveillance systems generate continuous 24/7 write streams. Writing continuous 1080p/4K streams directly to cloud mounts leads to dropped frames, broken MP4 headers, and high network retry rates.

### Architecture Blueprint
- **Frigate / NVR Storage Path:** Point video storage to `~/mnt/cloud-tiered/Surveillance`.
- **Flow:**
  1. Camera footage writes continuously to local SSD cache with zero dropped frames.
  2. A longer `SYNC_INTERVAL` batches video segments (e.g., 1-hour or 2-hour segments) into fewer rclone API calls, keeping cloud API costs low.
  3. Evicted segments remain viewable from Frigate's event browser seamlessly.

### Recommended `config.env` Tuning
```env
SYNC_MIN_AGE="2h"           # Keep at least 2 hours of recent event recordings on SSD
SYNC_INTERVAL="1h"          # Upload in larger hourly batches
SYNC_BWLIMIT="8M"           # Limit bandwidth to protect camera feed ingress
PANIC_THRESHOLD="75"        # Surveillance storage must never hit 100% full
PANIC_TARGET="50"
```

---

## 3. Self-Hosted Cloud Storage (Nextcloud / ownCloud)

### The Challenge
Nextcloud local storage quickly runs out of space on home servers or Raspberry Pis. Mounting an external unencrypted cloud storage directly in Nextcloud exposes user files to third-party cloud providers.

### Architecture Blueprint
- **Nextcloud Data Directory:** Point Nextcloud data or an "External Storage (Local)" folder to `~/mnt/cloud-tiered/NextcloudData`.
- **Flow:**
  1. Web and mobile file uploads to Nextcloud land instantly on fast local SSD with snappy UI response.
  2. In the background, older documents, pictures, and archives are moved to the encrypted cloud tier.
  3. Nextcloud users continue seeing all files in the web interface and mobile app without realizing files are encrypted in Google Drive.

### Recommended `config.env` Tuning
```env
SYNC_MIN_AGE="1h"           # Offload inactive files after 1 hour
SYNC_INTERVAL="20m"
SYNC_BWLIMIT="0"            # Unlimited speed on fast fiber connections
PANIC_THRESHOLD="80"
PANIC_TARGET="60"
SMART_FILER_ENABLED="false" # Let Nextcloud manage internal folder layout
```

---

## 4. Seedbox & Data Hoarding (Torrent Seeding)

### The Challenge
Torrents need to stay accessible for seeding after downloading. Immediate eviction breaks active torrent seeding, while manual offloading requires tedious file management.

### Architecture Blueprint
- **Torrent Client (Transmission / Deluge / rTorrent):**
  - **Incomplete folder:** `/tmp/incomplete` or `~/mnt/local-cache/incomplete`
  - **Completed download folder:** `~/mnt/cloud-tiered/Torrents`
- **Flow:**
  1. Set a generous `SYNC_MIN_AGE` (e.g. 24h to 72h) matching your seeding requirement.
  2. While seeding during the first 24–72 hours, reads occur with lightning speed off the local cache.
  3. Once the seeding window expires, files are automatically archived to the encrypted cloud tier.

### Recommended `config.env` Tuning
```env
SYNC_MIN_AGE="48h"          # Seed for 2 full days before cloud offload
SYNC_INTERVAL="1h"
SYNC_BWLIMIT="10M"          # Dedicate part of upstream to uploads, rest to seeding
PANIC_THRESHOLD="90"        # If torrent influx spikes, panic rule evicts oldest seeded items
PANIC_TARGET="70"
```

---

## 5. Game Server World Backups (Minecraft, Palworld, Valheim)

### The Challenge
Hourly and daily game server backups consume tens of gigabytes of disk space. Generating backups directly to cloud mounts freezes server tick rates (TPS drops) during backup compression.

### Architecture Blueprint
- **Backup Script / Plugin:** Save tarball backups to `~/mnt/cloud-tiered/GameBackups`.
- **Flow:**
  1. Automated backup scripts write `.tar.gz` files instantly to the local cache tier with zero server lag.
  2. Files older than 30 minutes are moved to Google Drive automatically.
  3. `.quota.txt` can be read by monitoring scripts or Discord bots to report backup size and remaining cloud capacity.
  4. For emergency server saves, drop files into `~/mnt/cloud-tiered/.immediate_sync/` to offload off-site instantly!

### Recommended `config.env` Tuning
```env
SYNC_MIN_AGE="30m"          # Offload shortly after creation
SYNC_INTERVAL="15m"
SYNC_BWLIMIT="0"            # Fast offload
PANIC_THRESHOLD="80"
PANIC_TARGET="50"
```

---

## Summary Matrix

| Application | Recommended `SYNC_MIN_AGE` | `SYNC_INTERVAL` | `PANIC_THRESHOLD` |
| :--- | :---: | :---: | :---: |
| **Media Server (Plex/Jellyfin)** | `6h` | `30m` | `85%` |
| **NVR / Security (Frigate)** | `2h` | `1h` | `75%` |
| **Private Cloud (Nextcloud)** | `1h` | `20m` | `80%` |
| **Seedbox / Hoarding** | `48h` | `1h` | `90%` |
| **Game Server Backups** | `30m` | `15m` | `80%` |
