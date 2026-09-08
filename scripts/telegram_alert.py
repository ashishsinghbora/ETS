#!/usr/bin/env python3
"""
Lightweight zero-dependency notification script.
Supports Telegram Bot API and generic HTTP webhook fallback.
Includes rate limiting (>5 alerts/min) and debouncing (duplicate messages within 60s).
Uses standard library urllib only.
"""
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

CONFIG_DIR = os.path.expanduser("~/.config/encrypted-tiered-storage")
COOLDOWN_FILE = os.path.join(CONFIG_DIR, ".alert_history.json")
MAX_ALERTS_PER_MINUTE = 5
DUPLICATE_COOLDOWN_SECONDS = 60


def get_config():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")
    webhook_url = os.environ.get("WEBHOOK_URL")
    env_file = os.path.join(CONFIG_DIR, "telegram.env")

    if os.path.exists(env_file):
        try:
            with open(env_file, "r") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        k, v = k.strip(), v.strip().strip('"').strip("'")
                        if k == "TELEGRAM_BOT_TOKEN" and not token:
                            token = v
                        elif k == "TELEGRAM_CHAT_ID" and not chat_id:
                            chat_id = v
                        elif k == "WEBHOOK_URL" and not webhook_url:
                            webhook_url = v
        except OSError as e:
            print(f"WARN: Unable to read {env_file}: {e}", file=sys.stderr)

    return token, chat_id, webhook_url


def is_rate_limited(message: str) -> bool:
    """Checks if message is duplicate within 60s or rate limit (>5/min) is exceeded."""
    now = time.time()
    msg_hash = hashlib.sha256(message.encode("utf-8")).hexdigest()

    data = {"recent_timestamps": [], "message_hashes": {}}
    if os.path.exists(COOLDOWN_FILE):
        try:
            with open(COOLDOWN_FILE, "r") as f:
                data = json.load(f)
        except Exception:
            data = {"recent_timestamps": [], "message_hashes": {}}

    # Filter out entries older than 60s
    recent_ts = [ts for ts in data.get("recent_timestamps", []) if now - ts < 60.0]
    msg_hashes = {
        h: ts
        for h, ts in data.get("message_hashes", {}).items()
        if now - ts < DUPLICATE_COOLDOWN_SECONDS
    }

    # Check duplicate
    if msg_hash in msg_hashes:
        print(
            f"WARN: Debounced duplicate alert within {DUPLICATE_COOLDOWN_SECONDS}s: {message}",
            file=sys.stderr,
        )
        return True

    # Check rate limit
    if len(recent_ts) >= MAX_ALERTS_PER_MINUTE:
        print(
            f"WARN: Alert rate limit exceeded (>{MAX_ALERTS_PER_MINUTE}/min). Suppressing alert: {message}",
            file=sys.stderr,
        )
        return True

    # Record and save
    recent_ts.append(now)
    msg_hashes[msg_hash] = now
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        tmp_file = f"{COOLDOWN_FILE}.tmp.{os.getpid()}"
        with open(tmp_file, "w") as f:
            json.dump({"recent_timestamps": recent_ts, "message_hashes": msg_hashes}, f)
        os.replace(tmp_file, COOLDOWN_FILE)
    except OSError as e:
        print(f"WARN: Could not update cooldown file: {e}", file=sys.stderr)

    return False


def send_alert(message: str):
    if is_rate_limited(message):
        return

    token, chat_id, webhook_url = get_config()
    sent = False

    # 1. Telegram delivery
    if token and chat_id:
        url = f"https://api.telegram.org/bot{token}/sendMessage"
        payload = urllib.parse.urlencode({"chat_id": chat_id, "text": message}).encode("utf-8")
        req = urllib.request.Request(url, data=payload, headers={"User-Agent": "TieredStorageAlert/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status == 200:
                    sent = True
        except Exception as e:
            print(f"WARN: Telegram notification failed: {e}", file=sys.stderr)

    # 2. Generic HTTP webhook fallback
    if webhook_url:
        json_data = json.dumps({"text": message, "content": message}).encode("utf-8")
        req = urllib.request.Request(
            webhook_url,
            data=json_data,
            headers={"Content-Type": "application/json", "User-Agent": "TieredStorageAlert/1.0"},
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                if 200 <= resp.status < 300:
                    sent = True
        except Exception as e:
            print(f"WARN: Generic webhook notification failed: {e}", file=sys.stderr)

    if not sent and not token and not webhook_url:
        print("INFO: Alert notifications disabled or unconfigured.", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: telegram_alert.py <message>", file=sys.stderr)
        sys.exit(1)
    send_alert(sys.argv[1])
