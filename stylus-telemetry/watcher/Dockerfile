FROM python:3.10-slim

WORKDIR /app

COPY watcher.py .

RUN pip install --no-cache-dir watchdog pytz requests

CMD ["python3", "-u", "watcher.py"]
