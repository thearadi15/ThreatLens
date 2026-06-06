# Phase 2 — Lab Setup on Microsoft Azure
## ThreatLens: End-to-End SOC Detection & Threat Hunting Platform

---

## Prerequisites

- Azure for Students account activated at: https://azure.microsoft.com/en-us/free/students
- Azure CLI installed on your Windows machine
- SSH client (Windows Terminal or MobaXterm)

### Install Azure CLI on Windows
```powershell
winget install Microsoft.AzureCLI
az login
az account show   # verify your subscription is active
```

---

## Step 1 — Create Resource Group & Virtual Network

```bash
# Set variables (use these throughout all commands)
RG="threatlens-lab"
LOCATION="eastus"
VNET="threatlens-vnet"

# Create resource group
az group create --name $RG --location $LOCATION

# Create VNet with address space
az network vnet create \
  --resource-group $RG \
  --name $VNET \
  --address-prefix 10.0.0.0/16

# Create 4 subnets: attacker, victim, SIEM, and Bastion
az network vnet subnet create --resource-group $RG --vnet-name $VNET \
  --name attacker-subnet --address-prefix 10.0.1.0/24

az network vnet subnet create --resource-group $RG --vnet-name $VNET \
  --name victim-subnet --address-prefix 10.0.2.0/24

az network vnet subnet create --resource-group $RG --vnet-name $VNET \
  --name siem-subnet --address-prefix 10.0.3.0/24

az network vnet subnet create --resource-group $RG --vnet-name $VNET \
  --name AzureBastionSubnet --address-prefix 10.0.4.0/27
```

## Step 1a — Deploy Azure Bastion

```bash
# Create the Bastion public IP
az network public-ip create --resource-group $RG --name bastion-pip --sku Standard --allocation-method Static

# Deploy Azure Bastion for private VM access
az network bastion create --resource-group $RG --name threatlens-bastion \
  --public-ip-address bastion-pip --vnet-name $VNET --location $LOCATION
```

---

## Step 2 — Create Network Security Groups (NSGs)

> Security note: this deployment should restrict management access to a fixed IP range or Azure Bastion/VPN. Avoid opening SSH or Kibana to the public internet.

### NSG for Attacker VM
```bash
az network nsg create --resource-group $RG --name attacker-nsg

# Allow SSH from Azure Bastion only
az network nsg rule create --resource-group $RG --nsg-name attacker-nsg \
  --name allow-ssh-from-bastion --priority 100 \
  --source-address-prefixes 10.0.4.0/27 --destination-port-ranges 22 \
  --access Allow --protocol Tcp --direction Inbound

# Allow attacker to reach victim subnet
az network nsg rule create --resource-group $RG --nsg-name attacker-nsg \
  --name allow-to-victim --priority 200 \
  --destination-address-prefixes 10.0.2.0/24 --destination-port-ranges '*' \
  --access Allow --protocol '*' --direction Outbound

# DENY attacker from reaching SIEM (critical isolation)
az network nsg rule create --resource-group $RG --nsg-name attacker-nsg \
  --name deny-to-siem --priority 300 \
  --destination-address-prefixes 10.0.3.0/24 --destination-port-ranges '*' \
  --access Deny --protocol '*' --direction Outbound
```

### NSG for Victim VM
```bash
az network nsg create --resource-group $RG --name victim-nsg

# Allow SSH from Azure Bastion only
az network nsg rule create --resource-group $RG --nsg-name victim-nsg \
  --name allow-ssh-from-bastion --priority 100 \
  --source-address-prefixes 10.0.4.0/27 --destination-port-ranges 22 \
  --access Allow --protocol Tcp --direction Inbound

# Allow all inbound from attacker subnet (we want attacks to hit)
az network nsg rule create --resource-group $RG --nsg-name victim-nsg \
  --name allow-attacker-inbound --priority 200 \
  --source-address-prefixes 10.0.1.0/24 --destination-port-ranges '*' \
  --access Allow --protocol '*' --direction Inbound

# Allow victim to push logs to SIEM (Beats port 5044)
az network nsg rule create --resource-group $RG --nsg-name victim-nsg \
  --name allow-beats-to-siem --priority 300 \
  --destination-address-prefixes 10.0.3.0/24 --destination-port-ranges 5044 \
  --access Allow --protocol Tcp --direction Outbound
```

### NSG for SIEM VM
```bash
az network nsg create --resource-group $RG --name siem-nsg

# Allow SSH from Azure Bastion only
az network nsg rule create --resource-group $RG --nsg-name siem-nsg \
  --name allow-ssh-from-bastion --priority 100 \
  --source-address-prefixes 10.0.4.0/27 --destination-port-ranges 22 \
  --access Allow --protocol Tcp --direction Inbound

# Allow Beats ingestion from victim subnet only
az network nsg rule create --resource-group $RG --nsg-name siem-nsg \
  --name allow-beats-inbound --priority 200 \
  --source-address-prefixes 10.0.2.0/24 --destination-port-ranges 5044 \
  --access Allow --protocol Tcp --direction Inbound

# Access Kibana via Bastion tunnel only
az network nsg rule create --resource-group $RG --nsg-name siem-nsg \
  --name allow-kibana-from-bastion --priority 300 \
  --source-address-prefixes 10.0.4.0/27 --destination-port-ranges 5601 \
  --access Allow --protocol Tcp --direction Inbound
```

---

## Step 3 — Deploy the 3 VMs

### VM 1: Attacker (Ubuntu + Attack Tools)
```bash
az vm create \
  --resource-group $RG \
  --name attacker-vm \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --vnet-name $VNET \
  --subnet attacker-subnet \
  --nsg attacker-nsg \
  --admin-username attacker \
  --generate-ssh-keys \
  --public-ip-address "" \
  --output table
```

### VM 2: Victim (Ubuntu + Vulnerable Services)
```bash
az vm create \
  --resource-group $RG \
  --name victim-vm \
  --image Ubuntu2204 \
  --size Standard_B1ms \
  --vnet-name $VNET \
  --subnet victim-subnet \
  --nsg victim-nsg \
  --admin-username victim \
  --generate-ssh-keys \
  --public-ip-address "" \
  --output table
```

### VM 3: ELK SIEM (Ubuntu + ELK Stack)
```bash
az vm create \
  --resource-group $RG \
  --name elk-siem \
  --image Ubuntu2204 \
  --size Standard_B4ms \
  --vnet-name $VNET \
  --subnet siem-subnet \
  --nsg siem-nsg \
  --admin-username elkadmin \
  --generate-ssh-keys \
  --public-ip-address "" \
  --output table
```

### Enable Auto-Shutdown on All VMs (Save Credits)
```bash
for VM in attacker-vm victim-vm elk-siem; do
  az vm auto-shutdown \
    --resource-group $RG \
    --name $VM \
    --time 2300 \
    --email "your@email.com"
done
```

---

## Step 4 — Install ELK Stack on SIEM VM

SSH into the SIEM VM:
```bash
ssh elkadmin@<elk-siem-public-ip>
```

### 4a. Java & System Prerequisites
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https wget curl gnupg2 software-properties-common
```

### 4b. Add Elastic Repository
```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
```

### 4c. Install Elasticsearch
```bash
sudo apt install -y elasticsearch

# Configure Elasticsearch
sudo tee /etc/elasticsearch/elasticsearch.yml > /dev/null <<'EOF'
cluster.name: threatlens-siem
node.name: elk-siem-node1
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: true
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
EOF

# Set JVM heap (half of available RAM = 8 GB on B4ms)
sudo tee /etc/elasticsearch/jvm.options.d/heap.options > /dev/null <<'EOF'
-Xms4g
-Xmx4g
EOF

sudo systemctl daemon-reload
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch

# Generate built-in passwords (SAVE THESE OUTPUT VALUES)
sudo /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto
```

### 4d. Install Logstash
```bash
sudo apt install -y logstash

# Set Logstash JVM heap
sudo tee /etc/logstash/jvm.options.d/heap.options > /dev/null <<'EOF'
-Xms512m
-Xmx1g
EOF

sudo systemctl enable logstash
```

### 4e. Install Kibana
```bash
sudo apt install -y kibana

sudo tee /etc/kibana/kibana.yml > /dev/null <<'EOF'
server.port: 5601
server.host: "0.0.0.0"
server.name: "threatlens-kibana"
elasticsearch.hosts: ["http://localhost:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "REPLACE_WITH_KIBANA_SYSTEM_PASSWORD"
xpack.security.enabled: true
xpack.encryptedSavedObjects.encryptionKey: "threatlens_32char_key_here_1234"
EOF

sudo systemctl enable kibana
sudo systemctl start kibana
```

---

## Step 5 — Configure Logstash Pipelines

### Main pipeline config
```bash
sudo tee /etc/logstash/conf.d/threatlens.conf > /dev/null <<'EOF'
input {
  beats {
    port => 5044
    type => "beats"
  }
}

filter {
  # Parse auth.log (SSH brute force detection)
  if [log][file][path] =~ "auth.log" {
    grok {
      match => {
        "message" => [
          "%{SYSLOGTIMESTAMP:timestamp} %{HOSTNAME:hostname} sshd\[%{POSINT:pid}\]: %{DATA:ssh_event} for %{DATA:ssh_user} from %{IP:src_ip} port %{NUMBER:src_port}",
          "%{SYSLOGTIMESTAMP:timestamp} %{HOSTNAME:hostname} sshd\[%{POSINT:pid}\]: %{DATA:ssh_event} password for %{DATA:ssh_user} from %{IP:src_ip}"
        ]
      }
    }
    mutate { add_field => { "log_type" => "auth" } }
  }

  # Parse Apache access log
  if [log][file][path] =~ "apache" {
    grok {
      match => {
        "message" => '%{COMBINEDAPACHELOG}'
      }
    }
    mutate {
      convert => { "response" => "integer" }
      convert => { "bytes" => "integer" }
      add_field => { "log_type" => "apache" }
    }
    # Flag suspicious HTTP responses
    if [response] == 403 or [response] == 500 {
      mutate { add_tag => ["suspicious_http"] }
    }
  }

  # Parse auditd logs
  if [log][file][path] =~ "audit" {
    grok {
      match => {
        "message" => "type=%{WORD:audit_type} msg=audit\(%{NUMBER:audit_epoch}:%{NUMBER:audit_seq}\): %{GREEDYDATA:audit_data}"
      }
    }
    mutate { add_field => { "log_type" => "audit" } }
  }

  # GeoIP enrichment for source IPs
  if [src_ip] {
    geoip {
      source => "src_ip"
      target => "geoip"
    }
  }

  # Timestamp normalization
  date {
    match => ["timestamp", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss"]
    target => "@timestamp"
  }

  # MITRE ATT&CK tagging
  if [ssh_event] =~ "Failed" {
    mutate {
      add_field => {
        "mitre_tactic"    => "Credential Access"
        "mitre_technique" => "T1110.001"
        "mitre_name"      => "Brute Force: Password Guessing"
        "severity"        => "medium"
      }
    }
  }
}

output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    user => "elastic"
    password => "REPLACE_WITH_ELASTIC_PASSWORD"
    index => "logs-%{[log_type]}-%{+YYYY.MM.dd}"
  }

  # Debug output (disable in production)
  # stdout { codec => rubydebug }
}
EOF

sudo systemctl start logstash
sudo systemctl status logstash
```

---

## Step 6 — Setup Victim VM (Ubuntu + Vulnerable Services)

> Note: This step is designed for lab training only. For a production-style SOC deployment, skip intentionally vulnerable services and use real workloads with secure authentication.

SSH into victim VM using Azure Bastion:
```bash
az network bastion ssh --name threatlens-bastion --resource-group $RG \
  --target-resource-id $(az vm show --resource-group $RG --name victim-vm --query id -o tsv) \
  --auth-type ssh --username victim --ssh-key ~/.ssh/id_rsa
```

### 6a. Install Vulnerable Services
```bash
sudo apt update && sudo apt upgrade -y

# OpenSSH with weak password (intentional)
# NOTE: This is only for a lab environment. Do not use this in production.
sudo apt install -y openssh-server
sudo useradd -m -s /bin/bash labuser
echo "labuser:password123" | sudo chpasswd
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Apache + PHP for DVWA
sudo apt install -y apache2 php php-mysqli php-gd php-xml mysql-server git

# DVWA (Damn Vulnerable Web App)
cd /var/www/html
sudo git clone https://github.com/digininja/DVWA.git dvwa
sudo cp dvwa/config/config.inc.php.dist dvwa/config/config.inc.php
sudo chown -R www-data:www-data dvwa/
sudo chmod -R 755 dvwa/

# MySQL setup for DVWA
sudo mysql -e "CREATE DATABASE dvwa;"
sudo mysql -e "CREATE USER 'dvwa'@'localhost' IDENTIFIED BY 'p@ssw0rd';"
sudo mysql -e "GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

sudo sed -i "s/\$_DVWA\[ 'db_password' \] = 'p@ssw0rd';/\$_DVWA[ 'db_password' ] = 'p@ssw0rd';/" /var/www/html/dvwa/config/config.inc.php
sudo systemctl restart apache2

# vsftpd (vulnerable FTP)
sudo apt install -y vsftpd
sudo sed -i 's/#write_enable=YES/write_enable=YES/' /etc/vsftpd.conf
sudo sed -i 's/#anon_upload_enable=YES/anon_upload_enable=YES/' /etc/vsftpd.conf
sudo systemctl restart vsftpd
```

### 6b. Install auditd (Syscall Monitoring)
```bash
sudo apt install -y auditd audispd-plugins

# Load audit rules for maximum visibility
sudo tee /etc/audit/rules.d/threatlens.rules > /dev/null <<'EOF'
# Delete existing rules
-D

# Monitor privilege escalation
-a always,exit -F arch=b64 -S execve -F euid=0 -k priv_exec
-w /etc/sudoers -p wa -k sudoers_change
-w /etc/passwd -p wa -k passwd_change

# Monitor network connections
-a always,exit -F arch=b64 -S connect -k network_connect
-a always,exit -F arch=b64 -S bind -k network_bind

# Monitor shell spawns (reverse shell detection)
-a always,exit -F arch=b64 -S execve -F exe=/bin/bash -k shell_exec
-a always,exit -F arch=b64 -S execve -F exe=/bin/sh -k shell_exec
-a always,exit -F arch=b64 -S execve -F exe=/usr/bin/nc -k netcat_exec
-a always,exit -F arch=b64 -S execve -F exe=/usr/bin/ncat -k netcat_exec

# Monitor file reads of sensitive files
-w /etc/shadow -p r -k shadow_read
-w /root/.ssh -p r -k ssh_key_read

# Monitor log deletion (defense evasion)
-w /var/log -p wa -k log_modification
EOF

sudo augenrules --load
sudo systemctl enable auditd
sudo systemctl restart auditd
```

---

## Step 7 — Deploy Beats Agents on Victim VM

### 7a. Install Filebeat
```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update
sudo apt install -y filebeat auditbeat

# Filebeat config
sudo tee /etc/filebeat/filebeat.yml > /dev/null <<'EOF'
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/auth.log
      - /var/log/syslog
    fields:
      log_type: syslog
    fields_under_root: true

  - type: log
    enabled: true
    paths:
      - /var/log/apache2/access.log
      - /var/log/apache2/error.log
    fields:
      log_type: apache
    fields_under_root: true

output.logstash:
  hosts: ["10.0.3.10:5044"]

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
EOF

sudo systemctl enable filebeat
sudo systemctl start filebeat
```

### 7b. Install Auditbeat
```bash
sudo tee /etc/auditbeat/auditbeat.yml > /dev/null <<'EOF'
auditbeat.modules:
  - module: auditd
    audit_rules: |
      -a always,exit -F arch=b64 -S execve -k exec
      -a always,exit -F arch=b64 -S connect -k network
      -w /etc/passwd -p wa -k passwd
      -w /etc/shadow -p wa -k shadow

  - module: file_integrity
    paths:
      - /bin
      - /usr/bin
      - /etc

  - module: system
    datasets:
      - host
      - login
      - process
      - socket
      - user
    period: 10s

output.logstash:
  hosts: ["10.0.3.10:5044"]
EOF

sudo systemctl enable auditbeat
sudo systemctl start auditbeat
```

---

## Step 8 — Setup Attacker VM

SSH into attacker VM:
```bash
ssh attacker@<attacker-vm-public-ip>
```

```bash
sudo apt update && sudo apt upgrade -y

# Install all attack tools
sudo apt install -y \
  nmap \
  hydra \
  netcat-openbsd \
  sqlmap \
  gobuster \
  curl \
  python3 \
  python3-pip \
  git

# Install Metasploit Framework
curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall
chmod 755 msfinstall
sudo ./msfinstall

# Verify all tools
nmap --version
hydra --version
msfconsole --version
sqlmap --version
```

---

## Step 9 — Verify the Full Pipeline

### Test log shipping end-to-end:
```bash
# On victim VM — generate a test SSH failure
ssh wronguser@localhost

# On SIEM VM — check if log arrived in Elasticsearch
curl -X GET "localhost:9200/logs-auth-*/_search?q=ssh_event:Failed&pretty" \
  -u elastic:YOUR_PASSWORD
```

### Access Kibana:
```bash
# From your Windows machine, create SSH tunnel to Kibana
ssh -L 5601:localhost:5601 elkadmin@<elk-siem-public-ip>

# Open browser: http://localhost:5601
# Login: elastic / <your generated password>
```

---

## Lab Status Checklist

| Component | Command to Verify |
|-----------|------------------|
| Elasticsearch | `curl -u elastic:PASS http://elk-ip:9200/_cluster/health` |
| Logstash | `sudo systemctl status logstash` |
| Kibana | `sudo systemctl status kibana` |
| Filebeat (victim) | `sudo systemctl status filebeat` |
| Auditbeat (victim) | `sudo systemctl status auditbeat` |
| DVWA | `curl http://victim-ip/dvwa/` |
| Attack tools | `nmap --version && hydra --version` |

---

## IP Reference Table

| VM | Private IP | Role |
|----|-----------|------|
| attacker-vm | 10.0.1.10 | Kali equivalent |
| victim-vm | 10.0.2.10 | Target |
| elk-siem | 10.0.3.10 | SIEM |

---

## Next: Phase 3 → Attack Simulation
All lab components are live. Phase 3 covers exact attack commands with expected log output for each scenario.
