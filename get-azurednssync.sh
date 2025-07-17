#!/bin/bash

# Download the AzureDNSSync installer
curl -fsSL https://raw.githubusercontent.com/andrew-kemp/AzureDNSSync/main/install.sh -o install.sh

# Make it executable
chmod +x install.sh

# Run the installer with sudo
sudo ./install.sh

# Optionally, clean up the installer after running
# rm -f install.sh
