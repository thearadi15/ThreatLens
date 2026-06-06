param(
    [string]$RG = "threatlens-lab",
    [string]$VNET = "threatlens-vnet"
)

# This script creates the lab VMs without public IP addresses.
# Use Azure Bastion or VPN to access these machines.

# VM 1: Attacker
Write-Host "Deploying Attacker VM..."
az vm create --resource-group $RG --name attacker-vm --image Ubuntu2204 --size Standard_D2s_v3 --vnet-name $VNET --subnet attacker-subnet --nsg attacker-nsg --admin-username attacker --generate-ssh-keys --public-ip-address "" --output table

# VM 2: Victim
Write-Host "Deploying Victim VM..."
az vm create --resource-group $RG --name victim-vm --image Ubuntu2204 --size Standard_D2s_v3 --vnet-name $VNET --subnet victim-subnet --nsg victim-nsg --admin-username victim --generate-ssh-keys --public-ip-address "" --output table

# VM 3: ELK SIEM
Write-Host "Deploying SIEM VM..."
az vm create --resource-group $RG --name elk-siem --image Ubuntu2204 --size Standard_D4s_v3 --vnet-name $VNET --subnet siem-subnet --nsg siem-nsg --admin-username elkadmin --generate-ssh-keys --public-ip-address "" --output table

# Enable Auto-Shutdown
Write-Host "Configuring Auto-Shutdown..."
$vms = @("attacker-vm", "victim-vm", "elk-siem")
foreach ($vm in $vms) {
    az vm auto-shutdown --resource-group $RG --name $vm --time 2300 --email "your@email.com"
}
