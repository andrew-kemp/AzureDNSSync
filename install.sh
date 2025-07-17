#!/bin/bash

set -e

SCRIPT_NAME="azurednssync.py"
INSTALL_DIR="/etc/azurednssync"
CERT_DIR="/etc/ssl/private"
CERT_NAME="dnssync"
COMBINED_PEM="$CERT_DIR/dnssync-combined.pem"
PYTHON_DEPS="python3 python3-venv"
PIP_DEPS="azure-identity azure-mgmt-dns pyyaml requests"
VENV_DIR="$INSTALL_DIR/venv"
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
    sudo apt-get update
    sudo apt-get install -y python3
fi
if ! dpkg -s python3-venv &>/dev/null; then
    echo "Installing python3-venv..."
    sudo apt-get install -y python3-venv
fi
if ! command_exists openssl; then
    echo "Installing openssl..."
    sudo apt-get install -y openssl
fi

# 2. Create install and cert directories
echo_title "Setting up script and certificate directories"
sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$CERT_DIR"
sudo chmod 700 "$INSTALL_DIR"
sudo chmod 700 "$CERT_DIR"

# 3. Set up Python virtual environment
echo_title "Setting up Python virtual environment"
if [ ! -d "$VENV_DIR" ]; then
    sudo python3 -m venv "$VENV_DIR"
fi
sudo "$VENV_DIR/bin/pip" install --upgrade pip
sudo "$VENV_DIR/bin/pip" install $PIP_DEPS

# 4. Download azurednssync.py from GitHub
echo_title "Downloading $SCRIPT_NAME from GitHub"
curl -fsSL "$GITHUB_RAW_URL" -o "/tmp/$SCRIPT_NAME"
sudo cp "/tmp/$SCRIPT_NAME" "$INSTALL_DIR/"
sudo chmod 700 "$INSTALL_DIR/$SCRIPT_NAME"

# 5. Generate certificate and key
echo_title "Generating self-signed certificate"
cd "$CERT_DIR"
if [ ! -f "${CERT_NAME}.key" ] || [ ! -f "${CERT_NAME}.crt" ]; then
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "${CERT_NAME}.key" \
        -out "${CERT_NAME}.crt" \
        -subj "/CN=azurednssync"
    sudo chmod 600 "${CERT_NAME}.key" "${CERT_NAME}.crt"
else
    echo "Certificate files already exist: ${CERT_NAME}.key, ${CERT_NAME}.crt"
fi

# 6. Create combined PEM file
echo_title "Combining key and cert into PEM"
sudo sh -c "cat ${CERT_NAME}.key ${CERT_NAME}.crt > $COMBINED_PEM"
sudo chmod 600 "$COMBINED_PEM"

# 7. Display public certificate block for Azure
echo_title "Azure App Registration Certificate Block"
echo "Copy the block below and paste it into your Azure AD App Registration as a public certificate:"
echo
sudo awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/ {print}' "$CERT_DIR/${CERT_NAME}.crt"
echo

# --- NEW: Prompt to continue after copying the certificate block ---
if [ -t 1 ]; then
    echo
    read -rsp "Press Enter to continue once you have copied the certificate block to Azure..." dummy
    echo
fi

# 8. Initial configuration wizard (optional) and cron job setup
VENV_PY="$VENV_DIR/bin/python"
CRON_LINE="*/5 * * * * $VENV_PY $INSTALL_DIR/$SCRIPT_NAME > /dev/null 2>&1"

if [ -t 1 ]; then
    while true; do
        echo
        read -rp "Would you like to run the AzureDNSSync configuration wizard now? [Y/n]: " RUNCONF
        case "$RUNCONF" in
            [Yy]*|"")
                echo_title "Starting AzureDNSSync configuration wizard..."
                sudo "$VENV_PY" "$INSTALL_DIR/$SCRIPT_NAME"
                break
                ;;
            [Nn]*)
                echo
                echo "You can run the configuration wizard later with:"
                echo "  sudo $VENV_PY $INSTALL_DIR/$SCRIPT_NAME"
                break
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done
else
    echo_title "Manual Configuration Required"
    echo "No interactive terminal detected."
    echo "Please run the configuration wizard manually with:"
    echo "  sudo $VENV_PY $INSTALL_DIR/$SCRIPT_NAME"
    echo
fi

# (Re)install the cron job to use the venv Python
echo_title "Setting up cron job"
# Remove any old jobs for azurednssync
( sudo crontab -l | grep -v "$SCRIPT_NAME" ; echo "$CRON_LINE" ) | sudo crontab -

echo
echo "=============================="
echo "INSTALLATION COMPLETE"
echo "=============================="
echo "Next steps:"
echo "1. Upload the certificate block above to your Azure App Registration."
echo "2. If config is not yet completed, run:"
echo "   sudo $VENV_PY $INSTALL_DIR/$SCRIPT_NAME"
echo "3. The updater will now run every 5 minutes via cron."
echo "Log file: $INSTALL_DIR/update.log"
echo
