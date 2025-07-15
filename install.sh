#!/bin/bash

set -e

# === Configurable variables ===
SCRIPT_NAME="azurednssync.py"
INSTALL_DIR="/etc/azurednssync"
CERT_DIR="/etc/ssl/private"
CERT_NAME="dnssync"
COMBINED_PEM="$CERT_DIR/dnssync-combined.pem"
PYTHON_DEPS="python3 python3-venv"
PIP_DEPS="azure-identity azure-mgmt-dns pyyaml requests"
VENV_DIR="$INSTALL_DIR/venv"
GITHUB_RAW_URL="https://raw.githubusercontent.com/andrew-kemp/AzureDNSSync/refs/heads/main/azurednssync.py"

# === Functions ===

command_exists() {
    command -v "$1" &>/dev/null
}

echo_title() {
    echo
    echo "=============================="
    echo "$@"
    echo "=============================="
}

# --- 1. Ensure required system packages are installed ---

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

# --- 2. Create install and cert directories ---

echo_title "Setting up script and certificate directories"

sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$CERT_DIR"
sudo chmod 700 "$INSTALL_DIR"
sudo chmod 700 "$CERT_DIR"

# --- 3. Set up Python virtual environment ---

echo_title "Setting up Python virtual environment"

if [ ! -d "$VENV_DIR" ]; then
    sudo python3 -m venv "$VENV_DIR"
fi

# Upgrade pip and install Python dependencies in venv
sudo "$VENV_DIR/bin/pip" install --upgrade pip
sudo "$VENV_DIR/bin/pip" install $PIP_DEPS

# --- 4. Download azurednssync.py from GitHub ---

echo_title "Downloading $SCRIPT_NAME from GitHub"

curl -fsSL "$GITHUB_RAW_URL" -o "/tmp/$SCRIPT_NAME"
sudo cp "/tmp/$SCRIPT_NAME" "$INSTALL_DIR/"
sudo chmod 700 "$INSTALL_DIR/$SCRIPT_NAME"

# --- 5. Generate certificate and key ---

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

# --- 6. Create combined PEM file ---

echo_title "Combining key and cert into PEM"

sudo sh -c "cat ${CERT_NAME}.key ${CERT_NAME}.crt > $COMBINED_PEM"
sudo chmod 600 "$COMBINED_PEM"

# --- 7. Print App Registration (Azure) details ---

echo_title "App Registration File (for Azure)"

echo "You will need to upload the following PEM file to your Azure AD App Registration:"
echo "    $COMBINED_PEM"
echo
echo "The file contains:"
echo "----------------------------------"
sudo cat "$COMBINED_PEM"
echo "----------------------------------"
echo
echo "When registering the certificate in Azure, use the public certificate portion (-----BEGIN CERTIFICATE----- ...)."
echo "Keep the combined PEM file secure and private."
echo
echo "Next steps:"
echo "  1. Run: sudo $VENV_DIR/bin/python $INSTALL_DIR/$SCRIPT_NAME"
echo "     -- and follow the prompts to complete configuration."
echo "  2. Upload the certificate to your Azure AD App Registration."
echo "  3. Enjoy automatic DNS sync!"
