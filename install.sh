#!/bin/bash

: <<'SYNOPSIS'
AzureDNSSync Unified Installer

Author: Andrew Kemp <andrew@kemponline.co.uk>
Version: 1.4.0
First Created: 2024-06-01
Last Updated: 2025-07-17

Synopsis:
    - Installs Python/venv if needed, and required pip packages.
    - Handles all directory setup and permissions.
    - Generates or detects self-signed cert and key, combines to PEM, shows public cert for Azure.
    - Prompts for all config values (with examples, grouped).
    - Writes config.yaml and smtp_auth.key.
    - Creates and enables systemd service and timer for scheduled runs.
    - No cron job—uses systemd (recommended).

License: MIT
SYNOPSIS

set -e

SCRIPT_NAME="azurednssync.py"
INSTALL_DIR="/etc/azurednssync"
CERT_DIR="/etc/ssl/private"
CERT_NAME="dnssync"
COMBINED_PEM="$CERT_DIR/dnssync-combined.pem"
PYTHON_DEPS="python3 python3-venv"
PIP_DEPS="azure-identity azure-mgmt-dns pyyaml requests"
VENV_DIR="$INSTALL_DIR/venv"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
SMTP_KEY_FILE="$INSTALL_DIR/smtp_auth.key"
SERVICE_FILE="/etc/systemd/system/azurednssync.service"
TIMER_FILE="/etc/systemd/system/azurednssync.timer"
GITHUB_RAW_URL="https://raw.githubusercontent.com/andrew-kemp/AzureDNSSync/main/azurednssync.py"

command_exists() {
    command -v "$1" &>/dev/null
}

echo_title() {
    echo
    echo "=============================="
    echo "$@"
    echo "=============================="
}

# 1. Ensure required system packages are installed
echo_title "Checking/installing system dependencies"
if ! command_exists python3; then
    echo "Installing python3..."
    apt-get update
    apt-get install -y python3
fi
if ! dpkg -s python3-venv &>/dev/null; then
    echo "Installing python3-venv..."
    apt-get install -y python3-venv
fi
if ! command_exists openssl; then
    echo "Installing openssl..."
    apt-get install -y openssl
fi
if ! command_exists curl; then
    echo "Installing curl..."
    apt-get install -y curl
fi

# 2. Create install and cert directories
echo_title "Setting up script and certificate directories"
mkdir -p "$INSTALL_DIR"
mkdir -p "$CERT_DIR"
chmod 700 "$INSTALL_DIR"
chmod 700 "$CERT_DIR"

# 3. Set up Python virtual environment
echo_title "Setting up Python virtual environment"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install $PIP_DEPS

# 4. Download azurednssync.py from GitHub
echo_title "Ensuring $SCRIPT_NAME is present"
if [ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
    echo "Downloading latest $SCRIPT_NAME from GitHub..."
    curl -fsSL "$GITHUB_RAW_URL" -o "/tmp/$SCRIPT_NAME"
    cp "/tmp/$SCRIPT_NAME" "$INSTALL_DIR/"
fi
chmod 700 "$INSTALL_DIR/$SCRIPT_NAME"

# 5. Generate certificate and key if not present
echo_title "Generating self-signed certificate (if needed)"
cd "$CERT_DIR"
if [ ! -f "${CERT_NAME}.key" ] || [ ! -f "${CERT_NAME}.crt" ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "${CERT_NAME}.key" \
        -out "${CERT_NAME}.crt" \
        -subj "/CN=azurednssync"
    chmod 600 "${CERT_NAME}.key" "${CERT_NAME}.crt"
else
    echo "Certificate files already exist: ${CERT_NAME}.key, ${CERT_NAME}.crt"
fi

# 6. Create combined PEM file
echo_title "Combining key and cert into PEM"
cat "${CERT_NAME}.key" "${CERT_NAME}.crt" > "$COMBINED_PEM"
chmod 600 "$COMBINED_PEM"

# 7. Display public certificate block for Azure
echo_title "Azure App Registration Certificate Block"
echo "Copy the block below and paste it into your Azure AD App Registration as a public certificate:"
echo
awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/ {print}' "$CERT_DIR/${CERT_NAME}.crt"
echo

# 8. Prompt for config with grouped sections and secure password input
echo
echo "--- Azure DNS Dynamic Updater Initial Configuration ---"
echo

echo "Azure Configuration:"
read -p "Tenant ID [00000000-0000-0000-0000-000000000000]: " TENANT_ID
TENANT_ID=${TENANT_ID:-00000000-0000-0000-0000-000000000000}
read -p "Application ID [11111111-2222-3333-4444-555555555555]: " CLIENT_ID
CLIENT_ID=${CLIENT_ID:-11111111-2222-3333-4444-555555555555}
read -p "Subscription ID [abcdef12-3456-7890-abcd-ef1234567890]: " SUBSCRIPTION_ID
SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-abcdef12-3456-7890-abcd-ef1234567890}
read -p "Resource Group [EXAMPLE_RESOURCE_GROUP]: " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-EXAMPLE_RESOURCE_GROUP}
read -p "Zone Name [example.com]: " ZONE_NAME
ZONE_NAME=${ZONE_NAME:-example.com}
read -p "Record Set Name [ip]: " RECORD_SET_NAME
RECORD_SET_NAME=${RECORD_SET_NAME:-ip}
read -p "TTL [300]: " TTL
TTL=${TTL:-300}
read -sp "Certificate password (if any, else leave blank): " CERT_PASSWORD
echo

echo
echo "Email/SMTP Configuration:"
read -p "Email Address From [dns-sync@example.com]: " EMAIL_FROM
EMAIL_FROM=${EMAIL_FROM:-dns-sync@example.com}
read -p "Email Address To [admin@example.com]: " EMAIL_TO
EMAIL_TO=${EMAIL_TO:-admin@example.com}
read -p "SMTP Server [smtp.example.com]: " SMTP_SERVER
SMTP_SERVER=${SMTP_SERVER:-smtp.example.com}
read -p "SMTP Port [587]: " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-587}

echo
echo "--- SMTP Credentials ---"
read -p "SMTP Username [apikey]: " SMTP_USERNAME
SMTP_USERNAME=${SMTP_USERNAME:-apikey}
read -sp "SMTP API Key or password: " SMTP_PASSWORD
echo

read -p "How often should the updater run (in minutes)? [5]: " SCHEDULE_MINUTES
SCHEDULE_MINUTES=${SCHEDULE_MINUTES:-5}

# 9. Write config.yaml
cat > "$CONFIG_FILE" <<EOF
tenant_id: $TENANT_ID
client_id: $CLIENT_ID
subscription_id: $SUBSCRIPTION_ID
certificate_path: $COMBINED_PEM
resource_group: $RESOURCE_GROUP
zone_name: $ZONE_NAME
record_set_name: $RECORD_SET_NAME
ttl: $TTL
email_from: $EMAIL_FROM
email_to: $EMAIL_TO
smtp_server: $SMTP_SERVER
smtp_port: $SMTP_PORT
certificate_password: "$CERT_PASSWORD"
EOF
chmod 600 "$CONFIG_FILE"

# 10. Write smtp_auth.key
cat > "$SMTP_KEY_FILE" <<EOF
username:$SMTP_USERNAME
password:$SMTP_PASSWORD
EOF
chmod 600 "$SMTP_KEY_FILE"
echo "SMTP credentials saved to $SMTP_KEY_FILE (permissions set to 600)"

echo
echo "Configuration complete! All settings saved."
echo

# 11. Write the systemd service file
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Azure DNS Sync (periodic updater)
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/$SCRIPT_NAME
EOF

# 12. Write the systemd timer file
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run Azure DNS Sync every $SCHEDULE_MINUTES minutes

[Timer]
OnBootSec=${SCHEDULE_MINUTES}min
OnUnitActiveSec=${SCHEDULE_MINUTES}min

[Install]
WantedBy=timers.target
EOF

# 13. Reload systemd, enable and start the timer
systemctl daemon-reload
systemctl enable azurednssync.timer
systemctl restart azurednssync.timer

echo
echo "=============================="
echo "INSTALLATION COMPLETE"
echo "=============================="
echo "Next steps:"
echo "1. Upload the certificate block above to your Azure App Registration."
echo "2. The updater will run every $SCHEDULE_MINUTES minutes via systemd timer."
echo "3. To reconfigure, run: sudo $VENV_DIR/bin/python $INSTALL_DIR/$SCRIPT_NAME --reconfig"
echo "   (This updates config.yaml and smtp_auth.key. To change schedule, rerun installer.)"
echo "4. Check status: sudo systemctl status azurednssync.timer"
echo "   Logs: sudo journalctl -u azurednssync.service"
echo "5. If you ever need to update the script, rerun this installer."
echo
