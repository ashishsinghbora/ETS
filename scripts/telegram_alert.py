#!/usr/bin/env python3
"""
Lightweight zero-dependency notification script.
Supports Telegram Bot API and generic HTTP webhook fallback.
Uses standard library urllib only.
"""
import sys
import os
import urllib.request
import urllib.parse
import json

def get_config():
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")
    webhook_url = os.environ.get("WEBHOOK_URL")
    env_file = os.path.expanduser("~/.config/encrypted-tiered-storage/telegram.env")
    
    if os.path.exists(env_file):
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
    return token, chat_id, webhook_url

def send_alert(message):
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
            headers={"Content-Type": "application/json", "User-Agent": "TieredStorageAlert/1.0"}
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
