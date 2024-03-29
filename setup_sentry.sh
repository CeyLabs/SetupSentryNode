#!/bin/bash

BASE_DIR="$HOME/sentryNodes" # Change this to the user's home directory

# Create the BASE_DIR if it doesn't exist
if [ ! -d "$BASE_DIR" ]; then
    mkdir -p "$BASE_DIR"
    echo "Created directory $BASE_DIR"
fi

# Function to check if the node directory already exists
node_exists() {
    local node_name=$1
    if [ -d "${BASE_DIR}/${node_name}" ]; then
        return 0 # returns true (0) if the directory exists
    else
        return 1 # returns false (1) if the directory does not exist
    fi
}

# Function to generate the next available node name
generate_node_name() {
    local count=1
    while true; do
        local node_name="sentry_node_${count}"
        if ! node_exists "$node_name"; then
            echo "$node_name"
            return
        fi
        ((count++))
    done
}

# Ask for the node name or use the default
while true; do
    read -p "Enter the name of the node (leave blank for default): " NODENAME
    if [ -z "$NODENAME" ]; then
        NODENAME=$(generate_node_name)
        echo "Using default name: $NODENAME"
        break
    elif node_exists "$NODENAME"; then
        echo "A node with the name $NODENAME already exists. Please enter a different name."
    else
        echo "Node name set to: $NODENAME"
        break
    fi
done

NODE_DIR="${BASE_DIR}/${NODENAME}"
mkdir -p "$NODE_DIR"
echo "Created directory $NODE_DIR for node files"

# Ask for the private key
read -sp "Enter the private key: " PRIVATEKEY
PRIVATEKEY=$(echo $PRIVATEKEY | tr -d '[:space:]') # Remove spaces and newlines
echo ""

# Ask for Telegram details
read -p "Enter Telegram Bot Token: " TELEGRAMBOTTOKEN
read -p "Enter Telegram Chat ID: " TELEGRAMCHATID
read -p "Enter Telegram Message Thread ID: " TELEGRAMMESSAGETHREADID

# Install necessary packages (NVM, Expect, Curl, and Unzip) without using sudo
sudo apt update
sudo apt install -y expect curl unzip
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash

# Source NVM to set up Node.js and npm without sudo
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
nvm install --lts

# Get the path of the newly installed Node.js
NODE_JS_PATH=$(which node)

# Download and unzip the Sentry Node CLI into the node-specific directory
curl -L -o "${NODE_DIR}/sentry-node-cli-linux.zip" "https://github.com/xai-foundation/sentry/releases/latest/download/sentry-node-cli-linux.zip"
unzip "${NODE_DIR}/sentry-node-cli-linux.zip" -d "$NODE_DIR/"
chmod +x "${NODE_DIR}/sentry-node-cli-linux"

# Main Telegram message thread ID for logs
MAIN_LOGS_THREAD_ID=2192

# Create the start.sh script for the node
cat <<EOF > "${NODE_DIR}/start.sh"
# Define your Telegram Bot API URL with your bot token
TELEGRAM_URL="https://api.telegram.org/bot$TELEGRAMBOTTOKEN/sendMessage"

# Define your Telegram Chat ID
CHAT_ID="$TELEGRAMCHATID"

# Function to send messages to Telegram
send_to_telegram() {
    local message=\$1
    local thread_id=\$2
    curl -s -X POST \$TELEGRAM_URL -d chat_id=\$CHAT_ID -d text="\$message" -d message_thread_id=\$thread_id -d parse_mode="MarkdownV2" > /dev/null
}

buffer=()

run_sentry_node() {
    expect -c "
    exp_internal 1
    log_user 1
    spawn ${NODE_DIR}/sentry-node-cli-linux
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
    if [[ "\$line" == *"assertion"* ]]; then
        send_to_telegram "\\\`Assertion: \$line\\\`" $MAIN_LOGS_THREAD_ID
    else
        buffer+=("\$line")
        if [ \${#buffer[@]} -eq 20 ]; then
            send_to_telegram "\\\`\\\`\\\`log\$(printf ' %s\n' "\${buffer[@]}")\\\`\\\`\\\`" $TELEGRAMMESSAGETHREADID
            buffer=()
            sleep 1
        fi
    fi
done
EOF
chmod +x "${NODE_DIR}/start.sh"

# Create the start.js Node script for the node
cat <<EOF > "${NODE_DIR}/start.js"
const { exec } = require("child_process");
exec("/bin/bash $HOME/sentryNodes/${NODENAME}/start.sh", (error, stdout, stderr) => {
    if (error) {
        console.log(\`error: \${error.message}\`);
        return;
    }
    if (stderr) {
        console.log(\`stderr: \${stderr}\`);
        return;
    }
    console.log(\`stdout: \${stdout}\`);
});
EOF

# Create the systemd service file for the node
SERVICE_FILE="$HOME/.config/systemd/user/${NODENAME}-sentry-node.service"
mkdir -p "$HOME/.config/systemd/user/"
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Sentry Node Service for $NODENAME

[Service]
Type=simple
ExecStart=$NODE_JS_PATH ${NODE_DIR}/start.js

[Install]
WantedBy=default.target
EOF

# Enable and start the service
systemctl --user enable "${NODENAME}-sentry-node.service"
systemctl --user start "${NODENAME}-sentry-node.service"

echo "Sentry Node ${NODENAME} setup completed."
