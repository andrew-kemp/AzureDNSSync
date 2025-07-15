import os
import yaml
import requests
import subprocess
from datetime import datetime, timedelta
import smtplib
from email.mime.text import MIMEText

try:
    from azure.identity import CertificateCredential
    from azure.mgmt.dns import DnsManagementClient
    from azure.mgmt.dns.models import ARecord, RecordSet
except ImportError:
    print("Azure packages not installed! Please run 'pip install azure-identity azure-mgmt-dns'")
    exit(1)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(SCRIPT_DIR, "config.yaml")
LAST_IP_FILE = os.path.join(SCRIPT_DIR, "last_ip.txt")
LOG_FILE = os.path.join(SCRIPT_DIR, "update.log")
SMTP_KEY_FILE = os.path.join(SCRIPT_DIR, "smtp_auth.key")
IP_DETECT_URL = "https://api.ipify.org"

DEFAULTS = {
    "tenant_id": "00000000-0000-0000-0000-000000000000",  # Example GUID
    "client_id": "11111111-2222-3333-4444-555555555555",  # Example GUID
    "certificate_path": "/etc/ssl/private/dnssync-combined.pem",
    "resource_group": "EXAMPLE_RESOURCE_GROUP",
    "zone_name": "example.com",
    "record_set_name": "dynamic",
    "ttl": 300,
    "email_from": "dns-sync@example.com",
    "email_to": "admin@example.com",
    "smtp_server": "smtp.example.com",
    "smtp_port": 587,
    "smtp_username": "apikey",
    "smtp_password": "SG.xxxxxxxx.yyyyyyyyzzzzzzzz",  # Example API key
    "schedule_minutes": 5,
    "scheduled": True,
    "subscription_id": "abcdef12-3456-7890-abcd-ef1234567890", # Example GUID
    "certificate_password": ""
}

def log_update(message):
    seven_days_ago = datetime.now() - timedelta(days=7)
    pruned_lines = []
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE, "r") as log:
            for line in log:
                try:
                    date_str = line[:19]
                    log_time = datetime.strptime(date_str, '%Y-%m-%d %H:%M:%S')
                except Exception:
                    pruned_lines.append(line)
                    continue
                if log_time >= seven_days_ago:
                    pruned_lines.append(line)
    pruned_lines.append(message + "\n")
    with open(LOG_FILE, "w") as log:
        log.writelines(pruned_lines)
    print(message)

def prompt_and_store_smtp_key(keyfile_path, defaults):
    print("\n--- SMTP Credentials ---\n")
    smtp_username = input(f"SMTP Username [{defaults.get('smtp_username', 'apikey')}]: ").strip() or defaults.get('smtp_username', 'apikey')
    smtp_password = input(f"SMTP API Key or password [{defaults.get('smtp_password', '')}]: ").strip() or defaults.get('smtp_password', '')
    with open(keyfile_path, "w") as kf:
        kf.write(f"username:{smtp_username}\npassword:{smtp_password}\n")
    os.chmod(keyfile_path, 0o600)
    print(f"SMTP credentials saved to {keyfile_path} (permissions set to 600)")

def prompt_config(defaults):
    print("\n--- Azure DNS Dynamic Updater Initial Configuration ---\n")
    config = {}

    # AZURE SECTION
    print("\nAzure Configuration:")
    config['tenant_id'] = input(f"Tenant ID [{defaults['tenant_id']}]: ").strip() or defaults['tenant_id']
    config['client_id'] = input(f"Client ID [{defaults['client_id']}]: ").strip() or defaults['client_id']
    config['certificate_path'] = input(f"Certificate Path [{defaults['certificate_path']}]: ").strip() or defaults['certificate_path']
    config['resource_group'] = input(f"Resource Group [{defaults['resource_group']}]: ").strip() or defaults['resource_group']
    config['zone_name'] = input(f"Zone Name [{defaults['zone_name']}]: ").strip() or defaults['zone_name']
    config['record_set_name'] = input(f"Record Set Name [{defaults['record_set_name']}]: ").strip() or defaults['record_set_name']
    config['ttl'] = int(input(f"TTL [{defaults['ttl']}]: ").strip() or defaults['ttl'])

    # EMAIL SECTION
    print("\nEmail/SMTP Configuration:")
    config['email_from'] = input(f"Email Address From [{defaults['email_from']}]: ").strip() or defaults['email_from']
    config['email_to'] = input(f"Email Address To [{defaults['email_to']}]: ").strip() or defaults['email_to']
    config['smtp_server'] = input(f"SMTP Server [{defaults['smtp_server']}]: ").strip() or defaults['smtp_server']
    config['smtp_port'] = int(input(f"SMTP Port [{defaults['smtp_port']}]: ").strip() or defaults['smtp_port'])

    # SMTP CREDENTIALS SECTION
    prompt_and_store_smtp_key(SMTP_KEY_FILE, defaults)

    # SCHEDULER SECTION
    print("\nScheduling Configuration:")
    while True:
        schedule_minutes = input(f"How often should the updater run (in minutes)? [{defaults['schedule_minutes']}]: ").strip()
        if not schedule_minutes or schedule_minutes.lower() in ("y", "yes"):
            config['schedule_minutes'] = defaults['schedule_minutes']
            break
        try:
            config['schedule_minutes'] = int(schedule_minutes)
            break
        except ValueError:
            print("Please enter a number (in minutes), or press Enter to accept the default.")
    config['scheduled'] = True

    config["subscription_id"] = defaults["subscription_id"]
    config["certificate_password"] = defaults["certificate_password"]
    return config

def read_smtp_key(keyfile_path):
    username = password = None
    try:
        with open(keyfile_path, "r") as kf:
            for line in kf:
                if line.startswith("username:"):
                    username = line.split(":", 1)[1].strip()
                elif line.startswith("password:"):
                    password = line.split(":", 1)[1].strip()
        return username, password
    except Exception as e:
        log_update(f"{datetime.now()}: Failed to read SMTP key file: {e}")
        return None, None

def send_email(subject, body, config):
    smtp_username, smtp_password = read_smtp_key(SMTP_KEY_FILE)
    if not smtp_username or not smtp_password:
        log_update("SMTP credentials missing; cannot send email.")
        return
    try:
        msg = MIMEText(body)
        msg['Subject'] = subject
        msg['From'] = config.get("email_from")
        msg['To'] = config.get("email_to")

        smtp_server = config.get("smtp_server")
        smtp_port = int(config.get("smtp_port", 587))

        server = smtplib.SMTP(smtp_server, smtp_port)
        server.starttls()
        server.login(smtp_username, smtp_password)
        server.sendmail(msg['From'], [msg['To']], msg.as_string())
        server.quit()
        log_update(f"{datetime.now()}: Email sent to {msg['To']}")
    except Exception as e:
        log_update(f"{datetime.now()}: Failed to send email: {e}")

def schedule_cron(minutes):
    python_path = subprocess.check_output(['which', 'python3']).decode().strip()
    script_path = os.path.abspath(__file__)
    cron_line = f"*/{minutes} * * * * {python_path} {script_path} > /dev/null 2>&1\n"
    try:
        existing = subprocess.check_output(['crontab', '-l'], stderr=subprocess.STDOUT).decode()
    except subprocess.CalledProcessError:
        existing = ""
    if cron_line not in existing:
        updated = existing + cron_line
        proc = subprocess.Popen(['crontab', '-'], stdin=subprocess.PIPE)
        proc.communicate(updated.encode())
        print("Cron job added.")
    else:
        print("Crontab entry already exists.")

def load_or_create_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            config = yaml.safe_load(f) or {}
        updated = False
        for key, default in DEFAULTS.items():
            if key not in config:
                config[key] = default
                updated = True
        if updated:
            with open(CONFIG_FILE, "w") as f:
                yaml.safe_dump(config, f)
        # Ensure SMTP key file exists and is valid
        if not os.path.exists(SMTP_KEY_FILE):
            prompt_and_store_smtp_key(SMTP_KEY_FILE, DEFAULTS)
        # Always ensure the cron is scheduled based on config
        schedule_cron(config.get('schedule_minutes', DEFAULTS["schedule_minutes"]))
        return config
    else:
        config = prompt_config(DEFAULTS.copy())
        schedule_cron(config["schedule_minutes"])
        with open(CONFIG_FILE, "w") as f:
            yaml.safe_dump(config, f)
        return config

def get_public_ip():
    try:
        return requests.get(IP_DETECT_URL, timeout=10).text.strip()
    except Exception as e:
        log_update(f"{datetime.now()}: Failed to detect public IP: {e}")
        return None

def get_dns_record_ip(record_name):
    try:
        output = subprocess.check_output(
            ['nslookup', record_name], stderr=subprocess.STDOUT
        ).decode()
        lines = output.splitlines()
        found_question = False
        for line in lines:
            if line.strip().startswith('Name:'):
                found_question = True
            if found_question and line.strip().startswith('Address:'):
                ip = line.strip().split('Address:')[1].strip()
                return ip
        for line in lines[::-1]:
            if "Address:" in line:
                parts = line.split("Address:")
                if len(parts) > 1:
                    ip = parts[1].strip()
                    if "." in ip:
                        return ip
        return None
    except Exception as e:
        log_update(f"{datetime.now()}: Failed to get DNS record IP with nslookup: {e}")
        return None

def get_azure_dns_ip(config):
    try:
        credential = CertificateCredential(
            tenant_id=config["tenant_id"],
            client_id=config["client_id"],
            certificate_path=config["certificate_path"],
            password=config["certificate_password"] if config["certificate_password"] else None
        )
        dns_client = DnsManagementClient(credential, config["subscription_id"])
        record_set = dns_client.record_sets.get(
            resource_group_name=config["resource_group"],
            zone_name=config["zone_name"],
            relative_record_set_name=config["record_set_name"],
            record_type="A",
        )
        if record_set.a_records and len(record_set.a_records) > 0:
            return record_set.a_records[0].ipv4_address
        else:
            return None
    except Exception as e:
        log_update(f"{datetime.now()}: Failed to get Azure DNS IP: {e}")
        return None

def get_last_ip():
    if os.path.exists(LAST_IP_FILE):
        with open(LAST_IP_FILE, "r") as f:
            return f.read().strip()
    return None

def set_last_ip(ip):
    with open(LAST_IP_FILE, "w") as f:
        f.write(ip)

def update_azure_dns(new_ip, config):
    try:
        credential = CertificateCredential(
            tenant_id=config["tenant_id"],
            client_id=config["client_id"],
            certificate_path=config["certificate_path"],
            password=config["certificate_password"] if config["certificate_password"] else None
        )
        dns_client = DnsManagementClient(credential, config["subscription_id"])
        try:
            record_set = dns_client.record_sets.get(
                resource_group_name=config["resource_group"],
                zone_name=config["zone_name"],
                relative_record_set_name=config["record_set_name"],
                record_type="A",
            )
        except Exception as e:
            log_update(f"{datetime.now()}: Creating new DNS record set: {e}")
            record_set = RecordSet(ttl=int(config["ttl"]), a_records=[])
        old_ips = [a.ipv4_address for a in getattr(record_set, "a_records", [])] if hasattr(record_set, "a_records") else []
        record_set.a_records = [ARecord(ipv4_address=new_ip)]
        record_set.ttl = int(config["ttl"])
        dns_client.record_sets.create_or_update(
            resource_group_name=config["resource_group"],
            zone_name=config["zone_name"],
            relative_record_set_name=config["record_set_name"],
            record_type="A",
            parameters=record_set
        )
        log_update(f"{datetime.now()}: Azure DNS updated from {old_ips[0] if old_ips else '(none)'} to {new_ip}")
        return True
    except Exception as e:
        log_update(f"{datetime.now()}: Azure DNS update failed: {e}")
        return False

def main():
    config = load_or_create_config()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    public_ip = get_public_ip()
    if not public_ip:
        log_update(f"{now}: Could not retrieve public IP.")
        return

    record_fqdn = f"{config['record_set_name']}.{config['zone_name']}"
    dns_ip = get_dns_record_ip(record_fqdn)
    if dns_ip:
        log_update(f"{now}: Current DNS for {record_fqdn} resolves to {dns_ip}")
    else:
        log_update(f"{now}: Could not resolve DNS for {record_fqdn}")

    azure_dns_ip = get_azure_dns_ip(config)
    if azure_dns_ip:
        log_update(f"{now}: Azure DNS for {record_fqdn} is set to {azure_dns_ip}")
    else:
        log_update(f"{now}: Azure DNS for {record_fqdn} is not set")

    if public_ip == dns_ip and public_ip == azure_dns_ip:
        log_update(f"{now}: Public IP, DNS record, and Azure DNS already match ({public_ip}). Nothing to do.")
        return

    last_ip = get_last_ip()
    if public_ip == last_ip and public_ip == azure_dns_ip:
        log_update(f"{now}: IP {public_ip} unchanged since last run and matches Azure, but DNS does not match. Proceeding to update Azure DNS anyway.")
    else:
        log_update(f"{now}: IP changed, DNS or Azure out of sync. Updating Azure DNS.")

    if update_azure_dns(public_ip, config):
        msg = f"{now}: {record_fqdn} updated in Azure from {azure_dns_ip or '(none)'} to {public_ip}"
        log_update(msg)
        set_last_ip(public_ip)
        send_email(
            subject=f"Azure DNS Updated: {record_fqdn}",
            body=msg,
            config=config
        )
    else:
        log_update(f"{now}: Failed to update DNS to {public_ip}")

if __name__ == "__main__":
    main()
