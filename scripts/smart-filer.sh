#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:${PATH}"

CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

LOCAL_CACHE="${LOCAL_CACHE_DIR:-$HOME/mnt/local-cache}"
LOG_TO_FILE="${LOG_TO_FILE:-false}"
LOG_FILE="${LOG_FILE:-$HOME/.config/encrypted-tiered-storage/storage.log}"

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] [SMART-FILER] $*"
    echo "$msg"
    if [ "$LOG_TO_FILE" = "true" ] && [ -n "$LOG_FILE" ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "$msg" >>"$LOG_FILE"
    fi
}

process_git_dirs() {
    [ -d "$LOCAL_CACHE" ] || return 0
    find "$LOCAL_CACHE" -mindepth 1 -maxdepth 4 -type d -name ".git" -print0 2>/dev/null | while IFS= read -r -d '' git_dir; do
        local repo_dir
        repo_dir="$(dirname "$git_dir")"
        [ -d "$repo_dir" ] || continue

        # Safety: Check if ANY file inside the repo was modified within the last 60 minutes
        if [ -n "$(find "$repo_dir" -mmin -60 -print -quit 2>/dev/null)" ]; then
            log "Skipping active git repository (modified within last 60m): $(basename "$repo_dir")"
            continue
        fi

        local repo_name parent_dir archive_path
        repo_name="$(basename "$repo_dir")"
        parent_dir="$(dirname "$repo_dir")"
        archive_path="${parent_dir}/${repo_name}.tar.gz"
        log "Archiving inactive git repository: $repo_name -> ${repo_name}.tar.gz"
        tar -czf "$archive_path" -C "$parent_dir" "$repo_name"
        rm -rf "$repo_dir"
        log "Archived and replaced with: $archive_path"
    done
}

process_file() {
    local target="$1"
    [ -f "$target" ] || {
        echo "$target"
        return 0
    }

    local filename ext lower_ext
    filename="$(basename "$target")"
    ext="${filename##*.}"
    lower_ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"

    local base_no_date="$filename"
    if [[ "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_(.*)$ ]]; then
        base_no_date="${BASH_REMATCH[1]}"
    fi

    case "$lower_ext" in
    pdf | doc | docx | odt)
        local mdate new_name dest_dir new_path
        mdate="$(date -d "@$(stat -c %Y "$target")" +%Y-%m-%d)"
        new_name="${mdate}_${base_no_date}"
        dest_dir="${LOCAL_CACHE}/Documents"
        mkdir -p "$dest_dir"
        new_path="${dest_dir}/${new_name}"
        if [ "$target" != "$new_path" ]; then
            log "Organizing document: $filename -> Documents/$new_name"
            mv "$target" "$new_path"
            echo "$new_path"
            return 0
        fi
        ;;

    jpg | jpeg | png | heic)
        local img_date=""
        if command -v exiftool &>/dev/null; then
            img_date="$(exiftool -s -s -s -d "%Y-%m-%d %Y %m" -DateTimeOriginal "$target" 2>/dev/null || true)"
        fi
        if [ -z "$img_date" ]; then
            img_date="$(date -d "@$(stat -c %Y "$target")" "+%Y-%m-%d %Y %m")"
        fi
        local ymd year month new_name dest_dir new_path
        read -r ymd year month <<<"$img_date"
        new_name="${ymd}_${base_no_date}"
        dest_dir="${LOCAL_CACHE}/Photos/${year}/${month}"
        mkdir -p "$dest_dir"
        new_path="${dest_dir}/${new_name}"
        if [ "$target" != "$new_path" ]; then
            log "Organizing photo: $filename -> Photos/${year}/${month}/$new_name"
            mv "$target" "$new_path"
            echo "$new_path"
            return 0
        fi
        ;;
    esac

    echo "$target"
}

if [ "${1:-}" = "--git-dirs" ]; then
    process_git_dirs
elif [ -n "${1:-}" ]; then
    process_file "$1"
else
    process_git_dirs
    find "$LOCAL_CACHE" -mindepth 1 -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
        process_file "$f" >/dev/null
    done
fi
