# 🌌 ArbiSight – Stylus CLI Telemetry Logger & Dashboard

**ArbiSight** is a developer-focused monitoring and analytics toolkit that captures and visualizes command-line interactions with the `cargo stylus` CLI on the Arbitrum Stylus platform. It logs, parses, and visualizes Stylus developer behavior in real time, providing insights, alerting, and a full-featured Grafana dashboard — all with zero code modifications required.

> ⚡ Built for CLI developers.  
> 📊 Powered by JSONL + SQLite + Grafana.  
> 🔔 Real-time alerts via Telegram and Slack.

---

## 🚀 Features

- ✅ Parses `cargo stylus` commands and subcommands with duration and metadata
- ✅ Stores logs in structured `.jsonl` format for flexible processing
- ✅ Auto-forwards data to a SQLite database using a lightweight Python watcher
- ✅ Provides a pre-built Grafana dashboard for visualizing command patterns
- ✅ Supports alerting on failed deploys, repeated errors, and anomalies
- ✅ Installation script works on both **Ubuntu** and **macOS**
- ✅ Optional Telegram or Slack notifications — set up interactively

---

## 🧠 Architecture

```text
+---------------------+      +---------------------+      +----------------------+
|  Developer Terminal | ---> |  CLI Logger (Shell) | ---> | stylus_logs.jsonl    |
|  cargo stylus ..... |      |  bash/zsh override  |      | Structured JSON Lines|
+---------------------+      +---------------------+      +----------------------+
                                                                     |
                                                                     v
                                                          +----------------------+
                                                          |  Watcher (Python)    |
                                                          |  Monitors .jsonl     |
                                                          |  Writes to SQLite DB |
                                                          +----------------------+
                                                                     |
                                                                     v
                                                        +---------------------------+
                                                        | Grafana + SQLite Plugin   |
                                                        | Real-time Dashboards      |
                                                        +---------------------------+
                                                                     |
                                                                     v
                                                        +---------------------------+
                                                        | Alert Manager             |
                                                        | Slack/Telegram/Webhook    |
                                                        +---------------------------+
```

---

## 📂 Directory Structure
```text
stylus-telemetry/
├── install.sh                     # Cross-platform setup script
├── watcher/
│   └── watcher.py                 # JSONL-to-SQLite forwarder
├── grafana/
│   └── provisioning/
│       ├── alerting/              # Alert rule & contact point YAMLs
│       └── dashboards/            # JSON Grafana dashboards
├── data/
│   ├── stylus_logs.jsonl          # Raw telemetry logs
│   └── stylus_logs.db             # SQLite database (auto-generated)
├── docker-compose.yml            # Grafana + Watcher services
└── README.md                      # This file
```

---

## ⚙️ Installation

### Requirements:

- Docker + Docker Compose

- cargo stylus installed

### Steps:

#### Clone the repo
```bash
git clone https://github.com/bytemaster333/ArbiSight.git
cd ArbiSight/stylus-telemetry
```
#### Make the install script executable
```bash
chmod +x install.sh
```
#### Run it
```bash
./install.sh
```
#### You'll be asked if you want to enable alerts, and guided through the setup for Telegram or Slack.

---

## 🛠️ How It Works
The install.sh script injects a custom shell function into your .bashrc or .zshrc file, overriding the cargo stylus command. When you run commands like:
```bash
cargo stylus deploy
```
…it captures:

- Timestamp

- Subcommand (deploy)

- Arguments

- Output

- Duration in seconds

These are stored line-by-line in ~/Arbisight/stylus-telemetry/data/stylus_logs.jsonl.

---

## 📡 Log Watching & Forwarding

A lightweight Python script (watcher.py) continuously watches the .jsonl file and updates a SQLite database (stylus_logs.db). This enables:

- Fast dashboard queries

- Time-series metrics

- SQL-based filtering

🐍 The watcher runs in Docker and restarts automatically.

---

## 📊 Dashboards (Grafana)

ArbiSight includes pre-built dashboards showing:

- Subcommand Usage Breakdown

- Deployment Duration Trends

- Success vs Failure Counts

- Timeline View of CLI Activity

- Heatmap of Activity by Hour

Accessible via: http://localhost:3000
Default credentials: admin / admin

---

## 📢 Alerts & Notifications

Optional alerts are configured during setup.

✅ Supported:
- Telegram

- Slack

### 🔔 Built-in Alert Rule:
Triggers when any CLI output includes the word error, within the last 5 minutes.

---

## 💬 Feedback & Contributions
Please open an issue or pull request on GitHub.
For ideas, bugs, or integration feedback, join the discussion!
