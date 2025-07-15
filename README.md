# AzureDNSSync

A secure dynamic DNS updater for Azure DNS using a Service Principal and certificate authentication.

---

## Features

- Updates an Azure DNS A record with your current public IP.
- Uses a Service Principal with certificate for secure, automated, passwordless authentication.
- Runs on a schedule (via cron).
- Notifies via email on changes (optional).
- Simple installer script and initial configuration wizard.

---

## Prerequisites

- **An Azure Subscription**
- **A Linux machine (Debian/Ubuntu recommended) with `sudo` privileges**
- **Python 3.8+** (and `python3-venv` package)
- **App Registration** in Azure AD with certificate authentication and proper IAM/RBAC permissions

---

## 1. Create an Azure App Registration

1. Go to [Azure Portal](https://portal.azure.com/) > **Azure Active Directory** > **App registrations** > **New registration**
2. Name: `AzureDNSSync` (or any name)
3. Redirect URI: leave blank
4. After creation, note your:
   - **Directory (tenant) ID**
   - **Application (client) ID**

### Add a Certificate

5. In the App Registration, go to **Certificates & secrets** > **Certificates**
6. When you run `install.sh` (below), it will generate a certificate.  
   After install, copy the certificate block shown and add as a new certificate here.

### Assign Azure DNS Permissions

7. Go to your DNS Zone's resource group in the portal.
8. Under **Access control (IAM)**, add a **Role Assignment**:
   - **Role**: `DNS Zone Contributor` (or `Contributor` if you want full access)
   - **Assign access to**: `App Registration` you created above

---

## 2. Install on your Server

Clone or download this repo, or just download the two files:

- `install.sh`
- `azurednssync.py`

### Run the installer

```bash
chmod +x install.sh
sudo ./install.sh
```

- This script:
  - Installs dependencies in a Python virtual environment (no system pollution)
  - Downloads the latest `azurednssync.py`
  - Generates a private key and certificate in `/etc/ssl/private/`
  - Combines key and cert into a PEM for use by Azure SDK
  - Shows you the certificate block to copy into Azure App Registration
  - Optionally runs the initial configuration wizard

---

## 3. Configure the Updater

If you didn't run the wizard at the end of install, run:

```bash
sudo /etc/azurednssync/venv/bin/python /etc/azurednssync/azurednssync.py
```

- Enter your Azure IDs, resource group, zone, record, and SMTP config (if you want notifications).
- The script will set up a cron job for periodic updates.

---

## 4. AzureDNSSync Operation

- The updater runs via cron as configured (default: every 5 minutes).
- It checks your public IP, updates the Azure DNS A record if it changes, and sends an email notification if configured.
- Logs are stored in `/etc/azurednssync/update.log`

---

## Security Notes

- Private key, certificate, and config are stored in `/etc/ssl/private` and `/etc/azurednssync` with restrictive permissions.
- Do **not** share your private key or combined PEM.
- Only the **public certificate** block is used for Azure App Registration.

---

## Troubleshooting

- If you get `ModuleNotFoundError`, ensure install.sh completed successfully.
- Check logs in `/etc/azurednssync/update.log`
- To re-run configuration:  
  `sudo /etc/azurednssync/venv/bin/python /etc/azurednssync/azurednssync.py`
- To re-install: re-run `sudo ./install.sh`

---

## Uninstall

```bash
sudo crontab -e  # Remove the AzureDNSSync cron job
sudo rm -rf /etc/azurednssync/
sudo rm /etc/ssl/private/dnssync.key /etc/ssl/private/dnssync.crt /etc/ssl/private/dnssync-combined.pem
```

---

## License

MIT
