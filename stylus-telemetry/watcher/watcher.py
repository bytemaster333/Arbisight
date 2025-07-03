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
meta_path = Path("/data/stylus_logs.meta")  # JSONL'de en son hangi satır işlendi

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
            print(f"🔄 {jsonl_path.name} değişti, veritabanı güncelleniyor...")
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
                continue  # Bu satır daha önce işlendi
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)

                # 🛠️ ISO formatlı timestamp varsa direkt parse edelim
                timestamp_str = data.get("timestamp", "")
                dt_obj = datetime.strptime(timestamp_str, '%Y-%m-%d %H:%M:%S')  # naive
                dt_local = pytz.timezone("Europe/Istanbul").localize(dt_obj)   # Yerel saat olarak işaretle
                dt_utc = dt_local.astimezone(timezone.utc)                     # UTC'ye çevir
                timestamp_epoch = int(dt_utc.timestamp())                      # Epoch saniyesi olarak kaydet

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
                print(f"[⚠️] Satır {i} hata: {e}")

    conn.commit()
    conn.close()
    write_last_position(new_position)
    print(f"✅ {new_position - last_position} yeni kayıt eklendi.")

if __name__ == "__main__":
    print("👀 JSONL dosyası izleniyor...")
    update_database()  # ilk başta dosyayı bir kere çalıştır
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
