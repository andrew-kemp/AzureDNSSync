#!/bin/bash
: <<'SYNOPSIS'
AzureDNSSync Installer

Author: Andrew Kemp <andrew@kemponline.co.uk>
Version: 1.3.0
First Created: 2024-06-01
Last Updated: 2025-07-17

Synopsis:
    This installer sets up AzureDNSSync for automatic dynamic DNS updates on Azure DNS.
    - Prompts for all configuration (Azure, DNS, and email/SMTP details).
    - Writes config.yaml and smtp_auth.key.
    - Installs and enables systemd service and timer for scheduled runs.
    - Handles all permissions and environment setup.

Dependencies:
    - bash
    - python3, pip, venv
    - systemd

License: MIT
SYNOPSIS

set -e

INSTALL_DIR="/etc/azurednssync"
VENV_DIR="$INSTALL_DIR/venv"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
SMTP_KEY_FILE="$INSTALL_DIR/smtp_auth.key"
SERVICE_FILE="/etc/systemd/system/azurednssync.service"
TIMER_FILE="/etc/systemd/system/azurednssync.timer"

echo "==== AzureDNSSync Installer v1.3.0 ===="

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
   echo "Please run as root (sudo $0)"
   exit 1
fi

mkdir -p "$INSTALL_DIR"

# Download or copy the latest azurednssync.py
if [ ! -f "$INSTALL_DIR/azurednssync.py" ]; then
    echo "Copy or download your azurednssync.py into $INSTALL_DIR before running this installer."
    exit 1
fi

# Set up Python virtual environment and dependencies
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install azure-identity azure-mgmt-dns requests pyyaml

# Prompt for config
read -p "Azure Tenant ID: " TENANT_ID
read -p "Azure Application ID (client_id): " CLIENT_ID
read -p "Azure Subscription ID: " SUBSCRIPTION_ID
read -p "Azure Resource Group: " RESOURCE_GROUP
read -p "DNS Zone Name (e.g. example.com): " ZONE_NAME
read -p "DNS Record Set Name (e.g. ip): " RECORD_SET_NAME
read -p "DNS TTL [300]: " TTL
TTL=${TTL:-300}
read -p "Notification Email From: " EMAIL_FROM
read -p "Notification Email To: " EMAIL_TO
read -p "SMTP Server: " SMTP_SERVER
read -p "SMTP Port [587]: " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-587}
read -p "SMTP Username: " SMTP_USERNAME
read -sp "SMTP Password: " SMTP_PASSWORD
echo
read -p "Path to Azure app certificate [/etc/ssl/private/dnssync-combined.pem]: " CERT_PATH
CERT_PATH=${CERT_PATH:-/etc/ssl/private/dnssync-combined.pem}
read -sp "Certificate password (if any, else leave blank): " CERT_PASSWORD
echo

# Prompt for frequency (schedule in minutes)
read -p "How often should the updater run (in minutes)? [5]: " SCHEDULE_MINUTES
SCHEDULE_MINUTES=${SCHEDULE_MINUTES:-5}

# Write config.yaml
cat > "$CONFIG_FILE" <<EOF
tenant_id: $TENANT_ID
client_id: $CLIENT_ID
subscription_id: $SUBSCRIPTION_ID
certificate_path: $CERT_PATH
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

# Write smtp_auth.key
cat > "$SMTP_KEY_FILE" <<EOF
username:$SMTP_USERNAME
password:$SMTP_PASSWORD
EOF
chmod 600 "$SMTP_KEY_FILE"

# Write the systemd service file
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Azure DNS Sync (periodic updater)
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/azurednssync.py
EOF

# Write the systemd timer file
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run Azure DNS Sync every $SCHEDULE_MINUTES minutes

[Timer]
OnBootSec=${SCHEDULE_MINUTES}min
OnUnitActiveSec=${SCHEDULE_MINUTES}min

[Install]
WantedBy=timers.target
EOF

# Reload systemd, enable and start the timer
systemctl daemon-reload
systemctl enable azurednssync.timer
systemctl restart azurednssync.timer

echo "Installation complete."
echo "You can check the status with: sudo systemctl status azurednssync.timer"
echo "Logs: sudo journalctl -u azurednssync.service"
