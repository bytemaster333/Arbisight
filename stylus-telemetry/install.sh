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

# ArbiSight CLI Logger
function stylus_logger() {
    START_TIME=$(date +%s.%N)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    OUTPUT=$(command "$@" 2>&1)
    END_TIME=$(date +%s.%N)
    DURATION=$(awk "BEGIN {delta = $END_TIME - $START_TIME; printf \"%.9f\", delta}")

    COMMAND_FULL="$*"

    if [[ "$COMMAND_FULL" =~ cargo[[:space:]]stylus([[:space:]]+([a-zA-Z0-9_-]+))?(.*) ]]; then
        SUBCOMMAND="${BASH_REMATCH[2]:-unknown}"
        ARGS="${BASH_REMATCH[3]}"
    else
        SUBCOMMAND="unknown"
        ARGS=""
    fi

    SANITIZED_OUTPUT=$(echo "$OUTPUT" | head -c 1000 | tr '\n' ' ' | sed 's/"/\\"/g')
    JSON="{\"timestamp\":\"$TIMESTAMP\", \"command\":\"$COMMAND_FULL\", \"subcommand\":\"$SUBCOMMAND\", \"args\":\"$ARGS\", \"output\":\"$SANITIZED_OUTPUT\", \"duration\":$DURATION}"

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

# 8. Telegram Alert Setup (Optional)
echo -n "Do you want to enable Telegram alert notifications? (y/n): "
read TELE_ENABLE

if [[ "$TELE_ENABLE" =~ ^[Yy]$ ]]; then
  echo -n "Enter your Telegram bot token: "
  read TELE_TOKEN
  echo -n "Enter your Telegram chat ID: "
  read TELE_CHATID

  mkdir -p grafana/provisioning/alerting

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
                SELECT timestamp AS time, COUNT(*) AS value
                FROM logs
                WHERE output LIKE '%error%'
                AND timestamp >= strftime('%s', 'now', '-5 minutes')
                GROUP BY strftime('%Y-%m-%d %H:%M', timestamp, 'unixepoch')
                ORDER BY time ASC
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
          receiver: telegram
EOF

  echo "✅ Telegram alert rule and contact point created."
else
  echo "⏭️ Skipping Telegram alert integration."
fi

# 9. Start Docker Services
echo "🐳 Launching services with Docker..."
sudo $DOCKER_CMD up -d

echo "🎉 All done! Restart your terminal or run: source $SHELL_RC"
