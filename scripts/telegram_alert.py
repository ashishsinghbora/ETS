#!/usr/bin/env python3
"""
Lightweight zero-dependency Telegram notification script.
Uses standard library urllib only.
"""
import sys
import os
import urllib.request
import urllib.parse

def get_config():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")
    env_file = os.path.expanduser("~/.config/encrypted-tiered-storage/telegram.env")
    
    if (not token or not chat_id) and os.path.exists(env_file):
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
    return token, chat_id

def send_alert(message):
    token, chat_id = get_config()
    if not token or not chat_id:
        print("WARN: Telegram alerting disabled or unconfigured.", file=sys.stderr)
        return
    
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    payload = urllib.parse.urlencode({"chat_id": chat_id, "text": message}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"User-Agent": "TieredStorageAlert/1.0"})
    
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status != 200:
                print(f"ERROR: Telegram API responded with status {resp.status}", file=sys.stderr)
                sys.exit(1)
    except Exception as e:
        print(f"ERROR: Failed to deliver Telegram alert: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: telegram_alert.py <message>", file=sys.stderr)
        sys.exit(1)
    send_alert(sys.argv[1])
