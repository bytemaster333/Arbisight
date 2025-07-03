FROM python:3.10-slim

WORKDIR /app

COPY watcher.py .

RUN pip install watchdog
RUN pip install pytz

CMD ["python", "watcher.py"]
