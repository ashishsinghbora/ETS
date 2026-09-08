# 🌐 Multi-Cloud Pooling Guide: Combining Multiple Cloud Providers

This guide explains how to combine multiple cloud accounts (e.g. Google Drive, Microsoft OneDrive, Dropbox, Proton Drive, Backblaze B2, or S3) into a single unified storage pool using the `rclone union` backend, and encrypting the entire pool seamlessly with `rclone crypt` before presenting it to ETS.

---

## 🏗️ Architecture

```
                                  User Files
                                      │
                      ┌───────────────┴──────────────┐
                      │    MergerFS Tiered Mount     │
                      │   (~/mnt/cloud-tiered)       │
                      └───────┬──────────────┬───────┘
                              │              │
                    (Instant Local Write) (Transparent Read)
                              │              │
                              ▼              ▼
                     ┌────────────────┐ ┌──────────────────────────┐
                     │ Local SSD Tier │ │   Rclone Crypt Remote    │
                     │ (~/mnt/local)  │ │      (unioncrypt:)       │
                     └────────────────┘ └────────────┬─────────────┘
                                                     │
                                            (Encrypted Layer)
                                                     │
                                                     ▼
                                        ┌──────────────────────────┐
                                        │    Rclone Union Remote   │
                                        │      (cloud-pool:)       │
                                        └────────────┬─────────────┘
                                                     │
                             ┌───────────────────────┼───────────────────────┐
                             │                       │                       │
                             ▼                       ▼                       ▼
                    ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
                    │  Google Drive   │     │   OneDrive 1TB  │     │  Backblaze B2   │
                    │    (gdrive:)    │     │   (onedrive:)   │     │     (b2:)       │
                    └─────────────────┘     └─────────────────┘     └─────────────────┘
```

---

## 1. Configure Underlying Cloud Providers

First, authenticate each individual cloud remote in rclone as usual:

```bash
rclone config
```

Verify your remotes:
```bash
rclone listremotes
# Output:
# gdrive:
# onedrive:
# b2storage:
```

---

## 2. Create the Rclone Union Remote

The `union` remote pools multiple backends together. Run `rclone config` or edit `~/.config/rclone/rclone.conf` directly:

### Sample `~/.config/rclone/rclone.conf` Union Entry

```ini
[cloud-pool]
type = union
upstreams = gdrive:encrypted_pool onedrive:encrypted_pool b2storage:bucket-name/pool
action_policy = mfs
create_policy = mfs
search_policy = ff
```

### Policy Options Explained

| Policy Option | Meaning | Recommended For |
|---|---|---|
| `mfs` (Most Free Space) | Writes new files to the cloud provider with the most free storage space remaining | **Recommended** for multi-cloud quota balancing |
| `lfs` (Least Free Space) | Fills up one cloud provider completely before spilling into the next | Filling free tiers sequentially |
| `rand` (Random) | Distributes files randomly across all active cloud providers | Load balancing network requests |
| `epall` (Existing Path All) | Preserves existing directory structures across all remotes | Multi-remote mirroring / syncing |

---

## 3. Layer Crypt Encryption Over the Union Pool

Now create the encrypted layer (`unioncrypt:`) that targets `cloud-pool:`:

```bash
rclone config create unioncrypt crypt \
    remote "cloud-pool:" \
    filename_encryption standard \
    directory_name_encryption true \
    password "YOUR_STRONG_PASSWORD_HERE"
```

Verify that the encrypted union layer can be read and written:
```bash
rclone mkdir unioncrypt:
rclone lsd unioncrypt:
```

---

## 4. Integrate with Encrypted Tiered Storage (ETS)

Configure your `config.env` to point to the encrypted union:

```env
# Point ETS directly to the encrypted union
CLOUD_REMOTE="cloud-pool"
CLOUD_REMOTE_FOLDER=""
CRYPT_REMOTE="unioncrypt"

# Cache paths
STORAGE_BASE_DIR="$HOME/mnt"
LOCAL_CACHE_DIR="$HOME/mnt/local-cache"
CLOUD_REMOTE_MOUNT="$HOME/mnt/gcrypt-remote"
TIERED_MOUNT="$HOME/mnt/cloud-tiered"

# Policy
SYNC_MIN_AGE="15m"
SYNC_INTERVAL="20m"
SYNC_BWLIMIT="10M"
PANIC_THRESHOLD="80"
PANIC_TARGET="60"
```

Run the setup installer:
```bash
./setup.sh
```

---

## 5. Benefits of Multi-Cloud Tiered Pooling

1. **Free Tier Aggregation:** Pool 15 GB (Google Drive) + 5 GB (OneDrive) + 10 GB (Mega) + 10 GB (Box) into an aggregate 40 GB encrypted zero-buffer storage tier.
2. **Failover & Redundancy:** If one cloud provider imposes daily API quotas, `action_policy = mfs` automatically diverts subsequent demotions to the alternative cloud remotes with remaining headroom.
3. **Provider Agnostic:** Upgrade or rotate cloud backends at any time without changing local file paths or interrupting application mounts (Plex, Nextcloud, Docker).
