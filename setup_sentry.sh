#!/bin/bash

# Step 1: Ask for the private key and store it in a variable
read -sp "Enter the private key: " PRIVATEKEY
echo ""

# Step 2: Ask for the Telegram bot token, chat id, and message thread id and store them in variables
read -p "Enter Telegram Bot Token: " TELEGRAMBOTTOKEN
read -p "Enter Telegram Chat ID: " TELEGRAMCHATID
read -p "Enter Telegram Message Thread ID: " TELEGRAMMESSAGETHREADID

# Step 3: Install Node.js, Expect, Curl, and Unzip
sudo apt update
sudo apt install -y nodejs expect curl unzip

# Step 4: Download and unzip the Sentry Node CLI
curl -L -o /root/sentry-node-cli-linux.zip https://github.com/xai-foundation/sentry/releases/latest/download/sentry-node-cli-linux.zip
unzip /root/sentry-node-cli-linux.zip -d /root/
chmod +x /root/sentry-node-cli-linux

# Step 5: Create the /root/start.sh script
cat <<EOF > /root/start.sh
# Define your Telegram Bot API URL with your bot token
TELEGRAM_URL="https://api.telegram.org/bot$TELEGRAMBOTTOKEN/sendMessage"

# Define your Telegram Chat ID
CHAT_ID="$TELEGRAMCHATID"

# Function to send messages to Telegram
send_to_telegram() {
    local message=\$1
    curl -s -X POST \$TELEGRAM_URL -d chat_id=\$CHAT_ID -d text="\$message" -d message_thread_id=$TELEGRAMMESSAGETHREADID -d parse_mode="MarkdownV2" > /dev/null
}

buffer=()

run_sentry_node() {
    expect -c "
    exp_internal 1
    log_user 1
    spawn /root/sentry-node-cli-linux
    expect \"\$\"
    send \"boot-operator\r\"
    expect \"Enter the private key of the operator:\"
    send \"$PRIVATEKEY\r\"
    expect \"Do you want to use a whitelist for the operator runtime\"
    send \"n\r\"
    interact
    "
}

run_sentry_node | while IFS= read -r line
do
    buffer+=("\$line")
    if [ \${#buffer[@]} -eq 20 ]; then
        send_to_telegram "\\\`\\\`\\\`log\$(printf ' %s\n' "\${buffer[@]}")\\\`\\\`\\\`"
        buffer=()
        sleep 1
    fi
done
EOF

chmod +x /root/start.sh

# Step 6: Create the /root/start.js Node script
cat <<EOF > /root/start.js
const { exec } = require("child_process");
exec("/bin/bash /root/start.sh", (error, stdout, stderr) => {});
EOF

# Step 7: Create the sentry-node.service
cat <<EOF > /etc/systemd/system/sentry-node.service
[Unit]
Description=Sentry Node Service
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/node /root/start.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl enable sentry-node.service
sudo systemctl start sentry-node.service
