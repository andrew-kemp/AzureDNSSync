# AzureDNSSync

AzureDNSSync is a simple dynamic DNS updater for Azure DNS. It runs as a background service on your Ubuntu server, detects when your public IP address changes, and updates your Azure DNS record automatically. Inspired by services like DynDNS, but built for Azure using secure authentication.

## Features

- Detects public IP changes and updates Azure DNS records
- Runs as a local systemd service on Ubuntu 24.04+
- Uses Azure Entra (Azure AD) App Registration for secure API authentication
- Configurable via YAML

## Requirements

- Ubuntu 24.04+
- Python 3.10+
- Azure subscription with DNS Zone
- Registered Azure Entra App with API permissions to manage DNS zones

## Quickstart

1. **Clone this repo:**
   ```bash
   git clone https://github.com/YOURUSER/AzureDNSSync.git
   cd AzureDNSSync
   ```

2. **Copy and configure settings:**
   ```bash
   cp azure_dnssync/config.yaml.example azure_dnssync/config.yaml
   # Edit azure_dnssync/config.yaml with your Azure and DNS details
   ```

3. **Create Python virtual environment and install requirements:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

4. **Test run:**
   ```bash
   python -m azure_dnssync
   ```

5. **(Optional) Set up as a systemd service:**
   See `contrib/azurednssync.service` for instructions.

## Configuration

Edit `azure_dnssync/config.yaml`:

```yaml
tenant_id: "YOUR_AZURE_TENANT_ID"
client_id: "YOUR_APP_CLIENT_ID"
client_secret: "YOUR_APP_CLIENT_SECRET"
subscription_id: "YOUR_AZURE_SUBSCRIPTION_ID"
resource_group: "YOUR_RESOURCE_GROUP_NAME"
zone_name: "example.com"
record_name: "home"
ttl: 300
ip_detect_url: "https://api.ipify.org"
```

## License

MIT

## Credits

Inspired by DynDNS, DuckDNS, and Azure’s own samples.
