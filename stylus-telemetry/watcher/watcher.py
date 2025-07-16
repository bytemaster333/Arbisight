import json
import sqlite3
from pathlib import Path
from datetime import datetime, timezone
import pytz
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import time

jsonl_path = Path("/data/stylus_logs.jsonl")
db_path = Path("/data/stylus_logs.db")
meta_path = Path("/data/stylus_logs.meta")

def read_last_position():
    try:
        if meta_path.exists():
            return int(meta_path.read_text().strip())
    except Exception:
        pass
    return 0

def write_last_position(position):
    meta_path.write_text(str(position))

class JSONLHandler(FileSystemEventHandler):
    def on_modified(self, event):
        if event.src_path == str(jsonl_path):
            print(f"🔄 {jsonl_path.name} changed, updating the database...")
            update_database()

def update_database():
    last_position = read_last_position()
    new_position = last_position

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

    with open(jsonl_path, 'r') as file:
        for i, line in enumerate(file, start=1):
            if i <= last_position:
                continue
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)

                timestamp_str = data.get("timestamp", "")
                dt_obj = datetime.strptime(timestamp_str, '%Y-%m-%d %H:%M:%S')
                dt_local = pytz.timezone("Europe/Istanbul").localize(dt_obj)
                dt_utc = dt_local.astimezone(timezone.utc)
                timestamp_epoch = int(dt_utc.timestamp())

                cursor.execute('''
                    INSERT INTO logs (timestamp, command, subcommand, args, output, duration)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (
                    timestamp_epoch,
                    data.get("command", ""),
                    data.get("subcommand", ""),
                    data.get("args", ""),
                    data.get("output", ""),
                    float(data.get("duration", 0))
                ))
                new_position = i
            except Exception as e:
                print(f"[⚠️] Line {i} error: {e}")

    conn.commit()
    conn.close()
    write_last_position(new_position)
    print(f"✅ {new_position - last_position} add new.")

if __name__ == "__main__":
    print("👀 Watching the JSONL file...")
    update_database()
    event_handler = JSONLHandler()
    observer = Observer()
    observer.schedule(event_handler, path=str(jsonl_path.parent), recursive=False)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
