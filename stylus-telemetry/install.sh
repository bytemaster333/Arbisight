#!/bin/bash

echo "🚀 Starting ArbiSight CLI Logger installation..."

# 1. Detect user shell profile (bash vs zsh)
if [[ "$SHELL" == *"zsh" ]]; then
  SHELL_RC="$HOME/.zshrc"
else
  SHELL_RC="$HOME/.bashrc"
fi

# 2. OS Detection
OS=$(uname)
echo "🖥️ Detected OS: $OS"

# 3. Docker Check
if ! command -v docker &> /dev/null; then
  echo "❌ Docker not installed. Please install Docker before continuing."
  exit 1
fi

# 4. Docker Compose Check
if command -v docker compose &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  echo "❌ Docker Compose not found. Please install or update Docker."
  exit 1
fi

# 5. Create Folder
INSTALL_DIR="$HOME/ArbiSight/stylus-telemetry"
cd "$INSTALL_DIR" || exit 1
mkdir -p data

# 6. Add CLI Logger to shell profile
if ! grep -q "function stylus_logger()" "$SHELL_RC"; then
  echo "🔧 Injecting logger into $SHELL_RC..."

  cat <<'EOF' >> "$SHELL_RC"

# ArbiSight CLI Logger (cross-platform)

function stylus_logger() {
    START_TIME=$(date +%s.%N)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    OUTPUT=$(command "$@" 2>&1)
    END_TIME=$(date +%s.%N)
    DURATION=$(awk "BEGIN {delta = $END_TIME - $START_TIME; printf \"%.9f\", delta}")

    COMMAND_FULL="$*"

    COMMAND="cargo stylus"

    SUBCOMMAND=$(echo "$COMMAND_FULL" | awk '{for(i=1;i<=NF;i++) if($i=="stylus") {print $(i+1); exit}}')
    [[ -z "$SUBCOMMAND" ]] && SUBCOMMAND="unknown"

    ARGS=$(echo "$COMMAND_FULL" | sed -E "s/.*stylus[[:space:]]+[^[:space:]]+[[:space:]]*//")

    SANITIZED_OUTPUT=$(echo "$OUTPUT" | head -c 1000 | tr '\n' ' ' | sed 's/"/\\"/g')
    JSON="{\"timestamp\":\"$TIMESTAMP\", \"command\":\"$COMMAND\", \"subcommand\":\"$SUBCOMMAND\", \"args\":\"$ARGS\", \"output\":\"$SANITIZED_OUTPUT\", \"duration\":$DURATION}"

    mkdir -p "$HOME/ArbiSight/stylus-telemetry/data"
    echo "$JSON" >> "$HOME/ArbiSight/stylus-telemetry/data/stylus_logs.jsonl"
    echo "$OUTPUT"
}

function cargo() {
    if [[ "$1" == "stylus" ]]; then
        shift
        stylus_logger cargo stylus "$@"
    else
        command cargo "$@"
    fi
}
EOF

  echo "✅ Logger function added to $SHELL_RC"
else
  echo "ℹ️ Logger already exists in $SHELL_RC"
fi

# 7. Reload shell profile
source "$SHELL_RC"

# 8. Alert Setup (via .env for watcher.py)
echo -n "Do you want to enable alert notifications? (y/n): "
read ALERT_ENABLE

ENV_FILE=".env"
> "$ENV_FILE"

if [[ "$ALERT_ENABLE" =~ ^[Yy]$ ]]; then
  echo "Choose alert platform:"
  echo "1) Telegram"
  echo "2) Slack"
  echo -n "Enter choice [1-2]: "
  read ALERT_CHOICE

  if [[ "$ALERT_CHOICE" == "1" ]]; then
    echo -n "Enter your Telegram bot token: "
    read TELE_TOKEN
    echo -n "Enter your Telegram chat ID: "
    read TELE_CHATID
    echo "ALERT_TYPE=telegram" >> "$ENV_FILE"
    echo "TELEGRAM_BOT_TOKEN=$TELE_TOKEN" >> "$ENV_FILE"
    echo "TELEGRAM_CHAT_ID=$TELE_CHATID" >> "$ENV_FILE"
    echo "✅ Telegram alert configured in .env"
  elif [[ "$ALERT_CHOICE" == "2" ]]; then
    echo -n "Enter your Slack webhook URL: "
    read SLACK_WEBHOOK
    echo "ALERT_TYPE=slack" >> "$ENV_FILE"
    echo "SLACK_WEBHOOK=$SLACK_WEBHOOK" >> "$ENV_FILE"
    echo "✅ Slack alert configured in .env"
  else
    echo "❌ Invalid choice. Skipping alert setup."
  fi
else
  echo "ALERT_TYPE=none" >> "$ENV_FILE"
  echo "⏭️ Skipping alert integration. No alerts will be sent."
fi

# 9. Start Docker Services
echo "🐳 Launching services with Docker..."
sudo $DOCKER_CMD up -d

echo "🎉 All done! Restart your terminal or run: source $SHELL_RC"
