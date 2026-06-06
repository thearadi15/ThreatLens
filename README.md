# ThreatLens SOC Lab

ThreatLens is a cloud-based SOC training lab built for Azure. It includes an attacker host, a victim host, and an ELK SIEM environment.

## What changed for real-life use

- NSG rules are hardened to restrict SSH and Kibana access to a fixed management IP.
- The victim web service is isolated so it is not publicly exposed by default.
- Sensitive credentials are removed from the repository and must be stored securely outside Git.
- Use Azure Bastion or VPN for safer management access whenever possible.

## Files

- `scripts/deploy_infra.ps1` — deploys VNet, subnets, hardened NSG rules, and Azure Bastion
- `scripts/deploy_vms.ps1` — deploys attacker, victim, and SIEM VMs without public IPs
- `docs/phase2_lab_setup.md` — step-by-step Azure deployment and configuration guide
- `docs/threatlens_comprehensive_docs.md` — full architecture and operational documentation

## Deploy

1. Open PowerShell and confirm Azure CLI is installed.
2. Run the infrastructure deployment script:
   ```powershell
   .\scripts\deploy_infra.ps1
   ```
3. Run the VM deployment script:
   ```powershell
   .\scripts\deploy_vms.ps1
   ```
4. The VMs are created without public IP addresses in a private VNet. Use Azure Bastion to access them.
5. Follow the docs in `docs/phase2_lab_setup.md` to complete the SIEM and VM configuration.

## Access VMs via Azure Bastion

After deployment, use Azure Bastion to connect:

```bash
# SSH to attacker VM
az network bastion ssh --name threatlens-bastion --resource-group threatlens-lab \
  --target-resource-id $(az vm show --resource-group threatlens-lab --name attacker-vm --query id -o tsv) \
  --auth-type ssh --username attacker --ssh-key ~/.ssh/id_rsa

# SSH to victim VM
az network bastion ssh --name threatlens-bastion --resource-group threatlens-lab \
  --target-resource-id $(az vm show --resource-group threatlens-lab --name victim-vm --query id -o tsv) \
  --auth-type ssh --username victim --ssh-key ~/.ssh/id_rsa

# SSH to SIEM VM
az network bastion ssh --name threatlens-bastion --resource-group threatlens-lab \
  --target-resource-id $(az vm show --resource-group threatlens-lab --name elk-siem --query id -o tsv) \
  --auth-type ssh --username elkadmin --ssh-key ~/.ssh/id_rsa
```

## Security

- Do not keep real passwords or IPs in `credentials.txt`.
- Use Azure Key Vault for secrets in production.
- Restrict management access to your office or VPN IP ranges.

## Secure deployment checklist

1. All VMs are deployed without public IP addresses for maximum security.
2. Use Azure Bastion exclusively for SSH access to all VMs.
3. No SSH key material or credentials should be stored in the repository.
4. Kibana access is restricted to Bastion or private VPN tunnels only.
5. Do not deploy weak or intentionally vulnerable services in production.
6. Use real application workloads and log sources for a production SOC environment.
7. Store all credentials securely outside the repository using Azure Key Vault.
