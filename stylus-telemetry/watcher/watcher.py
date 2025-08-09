import json
import sqlite3
from pathlib import Path
from datetime import datetime, timezone
import pytz
import time
import os
import requests
import hashlib

# File paths
jsonl_path = Path("/data/stylus_logs.jsonl")
db_path = Path("/data/stylus_logs.db")
meta_path = Path("/data/stylus_logs.meta")
last_alert_path = Path("/data/stylus_logs.lastalert")

# Alert config from environment
ALERT_TYPE = os.getenv("ALERT_TYPE", "none")
SLACK_WEBHOOK = os.getenv("SLACK_WEBHOOK")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")

def read_last_position():
    try:
        return int(meta_path.read_text().strip()) if meta_path.exists() else 0
    except:
        return 0

def write_last_position(position):
    meta_path.write_text(str(position))

def read_last_alert():
    return last_alert_path.read_text().strip() if last_alert_path.exists() else ""

def write_last_alert(alert_hash):
    last_alert_path.write_text(alert_hash)

def normalize_message(message: str) -> str:
    return " ".join(message.strip().split())

def send_alert(message):
    print(f"[🚨] Sending alert via {ALERT_TYPE}...")
    try:
        if ALERT_TYPE == "slack" and SLACK_WEBHOOK:
            res = requests.post(SLACK_WEBHOOK, json={"text": message})
            print(f"[✅] Slack response: {res.status_code} {res.text}")
        elif ALERT_TYPE == "telegram" and TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            res = requests.post(url, data={"chat_id": TELEGRAM_CHAT_ID, "text": message})
            print(f"[✅] Telegram response: {res.status_code} {res.text}")
        else:
            print("[⚠️] No valid alert config found.")
    except Exception as e:
        print(f"[⚠️] Alert error: {e}")

def update_database():
    last_pos = read_last_position()
    new_pos = last_pos

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER,
            command TEXT,
            subcommand TEXT,
            args TEXT,
            output TEXT,
            duration REAL
        )
    ''')

    with open(jsonl_path, 'r') as f:
        for i, line in enumerate(f, start=1):
            if i <= last_pos:
                continue
            try:
                data = json.loads(line.strip())
                dt = datetime.strptime(data["timestamp"], '%Y-%m-%d %H:%M:%S')
                ts = int(pytz.timezone("Europe/Istanbul").localize(dt).astimezone(timezone.utc).timestamp())

                cursor.execute('''
                    INSERT INTO logs (timestamp, command, subcommand, args, output, duration)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (
                    ts,
                    data.get("command", ""),
                    data.get("subcommand", ""),
                    data.get("args", ""),
                    data.get("output", ""),
                    float(data.get("duration", 0))
                ))

                output = data.get("output", "").lower()
                base_alert = any(x in output for x in ["error", "unrecognized", "failed"])
                alert_type = ""
                if "the following required arguments were not provided" in output:
                    alert_type = "⚠️ Missing Argument"
                elif "unrecognized" in output:
                    alert_type = "❓ Unrecognized Command"

                if base_alert:
                    title = f"{alert_type} –" if alert_type else "🚨 Stylus CLI Error Detected!"
                    msg = f"{title}\n\n*Command:* `{data.get('command', '')} {data.get('subcommand', '')} {data.get('args', '')}`\n*Output:*\n{data.get('output', '')}"
                    msg_hash = hashlib.sha256(normalize_message(msg).encode()).hexdigest()
                    if msg_hash != read_last_alert():
                        send_alert(msg)
                        write_last_alert(msg_hash)

                new_pos = i

            except Exception as e:
                print(f"[⚠️] Line {i} error: {e}")

    conn.commit()
    conn.close()
    write_last_position(new_pos)
    print(f"✅ {new_pos - last_pos} new entries added.")

if __name__ == "__main__":
    print("🔁 Polling started...")
    while True:
        try:
            update_database()
        except Exception as e:
            print(f"[⚠️] Poll error: {e}")
        time.sleep(1)

