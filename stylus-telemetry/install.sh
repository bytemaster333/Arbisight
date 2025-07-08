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

# 5. Clone repository
REPO_URL="https://github.com/bytemaster333/Arbisight.git"
INSTALL_DIR="$HOME/stylus-telemetry"

if [ ! -d "$INSTALL_DIR" ]; then
  git clone "$REPO_URL" "$INSTALL_DIR"
else
  echo "✅ Repository already cloned."
fi

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

    mkdir -p "$HOME/stylus-telemetry/data"
    echo "$JSON" >> "$HOME/stylus-telemetry/data/stylus_logs.jsonl"
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

# 8. Alert Setup (Optional)
echo -n "Do you want to enable alert notifications? (y/n): "
read ALERT_ENABLE

if [[ "$ALERT_ENABLE" =~ ^[Yy]$ ]]; then
  echo "Choose alert platform:"
  echo "1) Telegram"
  echo "2) Slack"
  echo -n "Enter choice [1-2]: "
  read ALERT_CHOICE

  mkdir -p grafana/provisioning/alerting

  if [[ "$ALERT_CHOICE" == "1" ]]; then
    echo -n "Enter your Telegram bot token: "
    read TELE_TOKEN
    echo -n "Enter your Telegram chat ID: "
    read TELE_CHATID

    cat > grafana/provisioning/alerting/01-contact-points.yaml <<EOF
apiVersion: 1
contactPoints:
  - orgId: 1
    name: telegram
    receivers:
      - uid: telegram-receiver
        type: telegram
        settings:
          bottoken: "$TELE_TOKEN"
          chatid: "$TELE_CHATID"
          disable_notification: false
          disable_web_page_preview: false
          protect_content: false
        disableResolveMessage: false
EOF

    RECEIVER_NAME="telegram"
    RECEIVER_UID="telegram-receiver"

  elif [[ "$ALERT_CHOICE" == "2" ]]; then
    echo -n "Enter your Slack webhook URL: "
    read SLACK_WEBHOOK

    cat > grafana/provisioning/alerting/01-contact-points.yaml <<EOF
apiVersion: 1
contactPoints:
  - orgId: 1
    name: slack
    receivers:
      - uid: slack-receiver
        type: slack
        settings:
          url: "$SLACK_WEBHOOK"
        disableResolveMessage: false
EOF

    RECEIVER_NAME="slack"
    RECEIVER_UID="slack-receiver"

  else
    echo "❌ Invalid choice. Skipping alert setup."
    exit 0
  fi

  cat > grafana/provisioning/alerting/02-alert-rules.yaml <<EOF
apiVersion: 1
groups:
  - orgId: 1
    name: Stylus Alerts
    folder: Stylus Alerts
    interval: 10s
    rules:
      - uid: stylus-error
        title: Stylus Alerts
        condition: C
        data:
          - refId: A
            queryType: table
            relativeTimeRange:
              from: 600
              to: 0
            datasourceUid: stylus-cli
            model:
              rawSql: |
                SELECT timestamp AS time,
                       COUNT(*) AS value
                FROM logs
                WHERE lower(output) LIKE '%error%'
                  AND timestamp >= strftime('%s', 'now', '-5 minutes')
                GROUP BY strftime('%Y-%m-%d %H:%M', timestamp, 'unixepoch')
                HAVING COUNT(*) > 0
              format: table
              refId: A
          - refId: B
            datasourceUid: __expr__
            model:
              expression: A
              type: reduce
              reducer: last
              refId: B
          - refId: C
            datasourceUid: __expr__
            model:
              expression: B
              type: threshold
              conditions:
                - evaluator:
                    type: gt
                    params: [0]
                  operator:
                    type: and
                  reducer:
                    type: last
                  query:
                    params: [C]
        noDataState: NoData
        execErrState: Error
        for: 10s
        annotations:
          summary: "🚨 Stylus CLI Error — Command failed"
          description: |
            Stylus CLI returned an error.
            Please check the logs for more information.
        isPaused: false
        notification_settings:
          receiver: $RECEIVER_NAME
EOF

  echo "✅ $RECEIVER_NAME alert rule and contact point created."
else
  echo "⏭️ Skipping alert integration."
fi

# 9. Start Docker Services
echo "🐳 Launching services with Docker..."
sudo $DOCKER_CMD up -d

echo "🎉 All done! Restart your terminal or run: source $SHELL_RC"
