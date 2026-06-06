param(
    [string]$RG = "threatlens-lab",
    [string]$LOCATION = "southeastasia",
    [string]$VNET = "threatlens-vnet",
    [string]$BastionSubnetName = "AzureBastionSubnet",
    [string]$BastionSubnetPrefix = "10.0.4.0/27",
    [string]$BastionName = "threatlens-bastion",
    [string]$BastionPublicIPName = "threatlens-bastion-pip"
)

Write-Host "Deploying Azure infrastructure for ThreatLens..."
Write-Host "Resource Group: $RG"
Write-Host "Location: $LOCATION"
Write-Host "Virtual Network: $VNET"
Write-Host "Bastion Subnet: $BastionSubnetName ($BastionSubnetPrefix)"
Write-Host "Bastion Name: $BastionName"
Write-Host "Bastion Public IP: $BastionPublicIPName"
Write-Host "Note: All VMs are private. Use Azure Bastion for access."

# Create resource group
Write-Host "Creating Resource Group: $RG..."
az group create --name $RG --location $LOCATION
az network vnet create --resource-group $RG --name $VNET --address-prefix 10.0.0.0/16
az network vnet subnet create --resource-group $RG --vnet-name $VNET --name attacker-subnet --address-prefix 10.0.1.0/24
az network vnet subnet create --resource-group $RG --vnet-name $VNET --name victim-subnet --address-prefix 10.0.2.0/24
az network vnet subnet create --resource-group $RG --vnet-name $VNET --name siem-subnet --address-prefix 10.0.3.0/24
az network vnet subnet create --resource-group $RG --vnet-name $VNET --name $BastionSubnetName --address-prefix $BastionSubnetPrefix
az network nsg create --resource-group $RG --name attacker-nsg
az network nsg create --resource-group $RG --name victim-nsg
az network nsg create --resource-group $RG --name siem-nsg

# Harden network access: Bastion handles management access. VMs do not need public SSH exposure.
az network nsg rule create --resource-group $RG --nsg-name attacker-nsg --name allow-ssh-from-bastion --priority 100 --source-address-prefixes $BastionSubnetPrefix --destination-port-ranges 22 --access Allow --protocol Tcp --direction Inbound
az network nsg rule create --resource-group $RG --nsg-name attacker-nsg --name allow-to-victim --priority 200 --destination-address-prefixes 10.0.2.0/24 --destination-port-ranges '*' --access Allow --protocol '*' --direction Outbound
az network nsg rule create --resource-group $RG --nsg-name attacker-nsg --name deny-to-siem --priority 300 --destination-address-prefixes 10.0.3.0/24 --destination-port-ranges '*' --access Deny --protocol '*' --direction Outbound
az network nsg rule create --resource-group $RG --nsg-name victim-nsg --name allow-ssh-from-bastion --priority 100 --source-address-prefixes $BastionSubnetPrefix --destination-port-ranges 22 --access Allow --protocol Tcp --direction Inbound
az network nsg rule create --resource-group $RG --nsg-name victim-nsg --name allow-http-from-attacker --priority 150 --source-address-prefixes 10.0.1.0/24 --destination-port-ranges 80 --access Allow --protocol Tcp --direction Inbound
az network nsg rule create --resource-group $RG --nsg-name victim-nsg --name allow-attacker-inbound --priority 200 --source-address-prefixes 10.0.1.0/24 --destination-port-ranges '*' --access Allow --protocol '*' --direction Inbound
az network nsg rule create --resource-group $RG --nsg-name victim-nsg --name allow-beats-to-siem --priority 300 --destination-address-prefixes 10.0.3.0/24 --destination-port-ranges 5044 --access Allow --protocol Tcp --direction Outbound
az network nsg rule create --resource-group $RG --nsg-name siem-nsg --name allow-ssh-from-bastion --priority 100 --source-address-prefixes $BastionSubnetPrefix --destination-port-ranges 22 --access Allow --protocol Tcp --direction Inbound
az network nsg rule create --resource-group $RG --nsg-name siem-nsg --name allow-beats-inbound --priority 200 --source-address-prefixes 10.0.2.0/24 --destination-port-ranges 5044 --access Allow --protocol Tcp --direction Inbound

# Create Bastion public IP and Bastion host for private VM access
az network public-ip create --resource-group $RG --name $BastionPublicIPName --sku Standard --allocation-method Static
az network bastion create --name $BastionName --resource-group $RG --public-ip-address $BastionPublicIPName --vnet-name $VNET --location $LOCATION --idle-timeout 180
