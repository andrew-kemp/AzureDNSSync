# 🚀 AzureDNSSync

**AzureDNSSync** is your friendly, no-fuss dynamic DNS updater for Azure DNS!  
It runs quietly in the background on your Ubuntu server, automatically keeping your DNS record up to date whenever your public IP changes—so your domain always points to the right place.

---

## ✨ Features

- ⏰ **Automatic public IP detection** whenever your IP changes
- 🔑 **Secure authentication** using Azure Entra (Azure AD) App Certificate
- 📝 **Simple YAML configuration**—easy to set up, easy to read
- 🛡️ **Runs as a systemd service & timer** (no cron needed!)
- 📧 **Email notifications** whenever your DNS is updated
- 🦾 **Works on vanilla Ubuntu 24.04+** (installs all dependencies for you)
- 🛠️ **Self-generates certificates** and handles all the permissions magic
- 🌍 **Minimal requirements:** No GUI, no browser, just SSH in and go!

---

## 🛒 Requirements

- Ubuntu 24.04 or later
- Python 3.10+
- An Azure subscription (with a DNS Zone set up)
- An Azure Entra (AD) App Registration with certificate authentication and DNS Zone permissions (see below)
- An SMTP mail account for notifications (optional, but highly recommended!)

---

## 🚦 Super-Quick Install

**You don’t need to clone this repo or mess with pip manually!**  
Just run the installer script below and follow the prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/andrew-kemp/AzureDNSSync/main/install.sh -o install.sh
chmod +x install.sh
sudo ./install.sh
```

- The script will:
  - Install all required system packages and Python dependencies
  - Generate a private certificate for Azure App Registration (and display the public part for you)
  - Prompt you for your Azure and DNS details (with helpful examples)
  - Write all configuration and credentials securely
  - Set up a systemd service and timer (runs every 5 minutes by default)
  - Done! 🎉

---

## 🧙 Initial Setup Walkthrough

During install, you’ll be asked for:

**Azure Details:**
- Tenant ID (looks like `00000000-0000-0000-0000-000000000000`)
- Application (Client) ID (`11111111-2222-3333-4444-555555555555`)
- Subscription ID
- Resource Group (where your DNS zone lives)
- DNS Zone Name (e.g. `example.com`)
- Record Set Name (e.g. `ip`)
- TTL (e.g. `300`)

**SMTP Email Details:**
- Who the notifications come from and go to
- SMTP server/port/username/password

**Certificate Password:**
- Optional, leave blank unless you want to encrypt your generated certificate

---

## 🏛️ Azure Setup: Certificate-Based App Registration

1. In Azure Portal, go to **Azure Active Directory → App registrations → New registration**.
2. Under your app, go to **Certificates & Secrets → Certificates → Upload certificate**.
   - Use the **public certificate block** displayed by the installer.
3. Assign the app **DNS Zone Contributor** role to your DNS resource group.

---

## 🛠️ Advanced: Reconfiguring or Customizing

- **Change config or SMTP details:**  
  ```bash
  sudo /etc/azurednssync/venv/bin/python /etc/azurednssync/azurednssync.py --reconfig
  ```
- **Change how often it runs:**  
  Edit and rerun the installer, or tweak `/etc/systemd/system/azurednssync.timer`.
- **Check service status or logs:**
  ```bash
  sudo systemctl status azurednssync.timer
  sudo journalctl -u azurednssync.service
  ```

---

## 🔬 How It Works

1. Detects your **current public IP** (via [ipify.org](https://www.ipify.org/))
2. Checks your **Azure DNS A record**
3. If your IP has changed, updates your DNS and **sends you an email notification**
4. Logs all actions to `/etc/azurednssync/update.log` (last 7 days kept)

---

## 💡 Example config.yaml

```yaml
tenant_id: "11016236-4dbc-43a6-8310-be803173fc43"
client_id: "ad2c13fe-115e-410d-a3bb-9ad80725fd7f"
subscription_id: "13869b4a-7bd0-4f35-a796-3ea82f39c884"
certificate_path: "/etc/ssl/private/dnssync-combined.pem"
resource_group: "DNS_Zones"
zone_name: "andykemp.cloud"
record_set_name: "ip"
ttl: 300
email_from: "AzureDNSSync@andykemp.cloud"
email_to: "andrew@kemponline.co.uk"
smtp_server: "mail.smtp2go.com"
smtp_port: 587
certificate_password: ""
```
(SMTP username/password are stored separately in `/etc/azurednssync/smtp_auth.key`, permissions 600.)

---

## ❓ FAQ

**Q: Will this overwrite my DNS record every time?**  
A: No! It only updates if your public IP changes.

**Q: Can I run this on other Linux distros?**  
A: It’s designed for Ubuntu, but should work on any systemd-based distro with minor tweaks.

**Q: Is my password visible when I enter it?**  
A: Nope, password prompts are fully hidden (no echo).

**Q: Where does the installer put everything?**  
A: `/etc/azurednssync` for config/code/venv, `/etc/ssl/private` for certs, and systemd units.

**Q: Where can I get help?**  
A: [Open an issue](https://github.com/andrew-kemp/AzureDNSSync/issues) or ping [@andrew-kemp](https://github.com/andrew-kemp)!

---

## 📝 License

MIT

---

## 🙏 Credits

Inspired by DynDNS, DuckDNS, and Azure’s own samples.  
Big thanks to the open source community!  
