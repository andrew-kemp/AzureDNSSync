#!/bin/bash

set -e

# === Configurable variables ===
SCRIPT_NAME="azurednssync.py"
INSTALL_DIR="/etc/azurednssync"
CERT_DIR="/etc/ssl/private"
CERT_NAME="dnssync"
COMBINED_PEM="$CERT_DIR/dnssync-combined.pem"
PYTHON_DEPS="python3 python3-pip"
PIP_DEPS="azure-identity azure-mgmt-dns pyyaml requests"

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

if ! command_exists pip3; then
    echo "Installing pip3..."
    sudo apt-get install -y python3-pip
fi

if ! command_exists openssl; then
    echo "Installing openssl..."
    sudo apt-get install -y openssl
fi

# --- 2. Ensure required python modules are installed ---

echo_title "Installing required Python modules"

sudo pip3 install --upgrade $PIP_DEPS

# --- 3. Create install directory ---

echo_title "Setting up script directory"

sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$CERT_DIR"
sudo chmod 700 "$INSTALL_DIR"
sudo chmod 700 "$CERT_DIR"

# --- 4. Copy script ---

if [ ! -f "$SCRIPT_NAME" ]; then
    echo "ERROR: $SCRIPT_NAME not found in current directory!"
    exit 1
fi

sudo cp "$SCRIPT_NAME" "$INSTALL_DIR/"
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
echo "  1. Run: sudo python3 $INSTALL_DIR/$SCRIPT_NAME"
echo "     -- and follow the prompts to complete configuration."
echo "  2. Upload the certificate to your Azure AD App Registration."
echo "  3. Enjoy automatic DNS sync!"
