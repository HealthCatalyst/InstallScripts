Write-Host "--- create-bare-metal Version 2018.03.23.02 ----"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/create-bare-metal.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

$AKS_SERVICE_PRINCIPAL_NAME = ""
$AKS_SUPPORT_WINDOWS_CONTAINERS = "n"

DownloadAzCliIfNeeded

$AKS_SUBSCRIPTION_ID = $(GetLoggedInUserInfo).AKS_SUBSCRIPTION_ID

# ask for customerid
Do { $customerid = Read-Host "Health Catalyst Customer ID (e.g., ahmn)"}
while ([string]::IsNullOrWhiteSpace($customerid))

Write-Host "Customer ID: $customerid"

# ask for resource group name to create
$DEFAULT_RESOURCE_GROUP = "Test-Kub-$($customerid.ToUpper())-RG"

$ResourceGroupInfo = GetResourceGroupAndLocation -defaultResourceGroup $DEFAULT_RESOURCE_GROUP
$AKS_PERS_RESOURCE_GROUP = $ResourceGroupInfo.AKS_PERS_RESOURCE_GROUP
$AKS_PERS_LOCATION = $ResourceGroupInfo.AKS_PERS_LOCATION

$AKS_SUPPORT_WINDOWS_CONTAINERS = Read-Host "Support Windows containers (y/n) (default: n)"
if ([string]::IsNullOrWhiteSpace($AKS_SUPPORT_WINDOWS_CONTAINERS)) {
    $AKS_SUPPORT_WINDOWS_CONTAINERS = "n"
}

# service account to own the resources
$AKS_SERVICE_PRINCIPAL_NAME = Read-Host "Service account to use (default: ${AKS_PERS_RESOURCE_GROUP}Kubernetes)"
if ([string]::IsNullOrWhiteSpace($AKS_SERVICE_PRINCIPAL_NAME)) {
    $AKS_SERVICE_PRINCIPAL_NAME = "${AKS_PERS_RESOURCE_GROUP}Kubernetes"
}

# where to store the SSH keys on local machine
$AKS_LOCAL_FOLDER = Read-Host "Folder to store SSH keys (default: c:\kubernetes)"

if ([string]::IsNullOrWhiteSpace($AKS_LOCAL_FOLDER)) {$AKS_LOCAL_FOLDER = "C:\kubernetes"}

if (!(Test-Path -Path "$AKS_LOCAL_FOLDER")) {
    Write-Host "$AKS_LOCAL_FOLDER does not exist.  Creating it..."
    New-Item -ItemType directory -Path $AKS_LOCAL_FOLDER
}

AddFolderToPathEnvironmentVariable -folder $AKS_LOCAL_FOLDER

$SSHKeyInfo = CreateSSHKey -resourceGroup $AKS_PERS_RESOURCE_GROUP -localFolder $AKS_LOCAL_FOLDER
$SSH_PUBLIC_KEY_FILE = $SSHKeyInfo.SSH_PUBLIC_KEY_FILE
$SSH_PRIVATE_KEY_FILE_UNIX_PATH = $SSHKeyInfo.SSH_PRIVATE_KEY_FILE_UNIX_PATH

DownloadKubectl -localFolder $AKS_LOCAL_FOLDER

if ([string]::IsNullOrEmpty($(kubectl config current-context 2> $null))) {
    Write-Host "kube config is not set"
}
else {
    if (${AKS_PERS_RESOURCE_GROUP} -ieq $(kubectl config current-context 2> $null) ) {
        Write-Host "Current kub config points to this cluster"
    }
    else {
        $clustername = "${AKS_PERS_RESOURCE_GROUP}"
        $fileToUse = "$AKS_LOCAL_FOLDER\$clustername\temp\.kube\config"
        if (Test-Path $fileToUse) {
            SwitchToKubCluster -folderToUse "${AKS_LOCAL_FOLDER}\${clustername}" 
        }
        else {
            CleanKubConfig
        }        
    }        
}


# see if the user wants to use a specific virtual network
$VnetInfo = GetVnet -subscriptionId $AKS_SUBSCRIPTION_ID
$AKS_VNET_NAME = $VnetInfo.AKS_VNET_NAME
$AKS_SUBNET_NAME = $VnetInfo.AKS_SUBNET_NAME
$AKS_SUBNET_RESOURCE_GROUP = $VnetInfo.AKS_SUBNET_RESOURCE_GROUP
$AKS_SUBNET_ID = $VnetInfo.AKS_SUBNET_ID

CleanResourceGroup -resourceGroup ${AKS_PERS_RESOURCE_GROUP} -location $AKS_PERS_LOCATION -vnet $AKS_VNET_NAME `
    -subnet $AKS_SUBNET_NAME -subnetResourceGroup $AKS_SUBNET_RESOURCE_GROUP `
    -storageAccount $AKS_PERS_STORAGE_ACCOUNT_NAME

$AKS_PERS_STORAGE_ACCOUNT_NAME = $(CreateStorageIfNotExists -resourceGroup $AKS_PERS_RESOURCE_GROUP).AKS_PERS_STORAGE_ACCOUNT_NAME

Write-Host "Using Storage Account: $AKS_PERS_STORAGE_ACCOUNT_NAME"

CreateShareInStorageAccount -storageAccountName $AKS_PERS_STORAGE_ACCOUNT_NAME -resourceGroup $AKS_PERS_RESOURCE_GROUP -sharename "data"

$NETWORK_SECURITY_GROUP = "cluster-nsg"
Write-Host "Creating network security group: $NETWORK_SECURITY_GROUP"
$nsg = az network nsg create --name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP --query "id" -o tsv 

Write-Host "Creating rule: allow_ssh"
az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n allow_ssh --priority 100 `
    --source-address-prefixes "*" --source-port-ranges '*' `
    --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow `
    --protocol Tcp --description "allow ssh access." `
    --query "provisioningState" -o tsv

Write-Host "Creating rule: allow_rdp"
az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n allow_rdp `
    --priority 101 `
    --source-address-prefixes "*" --source-port-ranges '*' `
    --destination-address-prefixes '*' --destination-port-ranges 3389 --access Allow `
    --protocol Tcp --description "allow RDP access." `
    --query "provisioningState" -o tsv

$sourceTagForHttpAccess = "Internet"
if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpPort" --nsg-name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Host "Creating rule: HttpPort"
    az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpPort --priority 500 `
        --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
        --protocol Tcp --description "allow HTTP access from $sourceTagForHttpAccess." `
        --query "provisioningState" -o tsv
}
else {
    Write-Host "Updating rule: HttpPort"
    az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpPort --priority 500 `
        --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
        --protocol Tcp --description "allow HTTP access from $sourceTagForHttpAccess." `
        --query "provisioningState" -o tsv
}

if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpsPort" --nsg-name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Host "Creating rule: HttpsPort"
    az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpsPort --priority 501 `
        --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
        --protocol Tcp --description "allow HTTPS access from $sourceTagForHttpAccess." `
        --query "provisioningState" -o tsv
}
else {
    Write-Host "Updating rule: HttpsPort"
    az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpsPort --priority 501 `
        --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
        --protocol Tcp --description "allow HTTPS access from $sourceTagForHttpAccess." `
        --query "provisioningState" -o tsv
}    

$nsgid = az network nsg list --resource-group ${AKS_PERS_RESOURCE_GROUP} --query "[?name == '${NETWORK_SECURITY_GROUP}'].id" -o tsv
Write-Host "Found ID for ${AKS_PERS_NETWORK_SECURITY_GROUP}: $nsgid"

Write-Host "Setting NSG into subnet"
az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --network-security-group "$nsgid" --query "provisioningState" -o tsv

# to list available images: az vm image list --output table
# to list CentOS images: az vm image list --offer CentOS --publisher OpenLogic --all --output table
$urn = "OpenLogic:CentOS:7.4:latest"

Write-Host "Creating master"
$VMInfo = CreateVM -vm "k8s-master" -resourceGroup $AKS_PERS_RESOURCE_GROUP `
    -subnetId $AKS_SUBNET_ID `
    -networkSecurityGroup $NETWORK_SECURITY_GROUP `
    -publicKeyFile $SSH_PUBLIC_KEY_FILE `
    -image $urn

Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@$($VMInfo.IP)"

Write-Host "Creating linux vm 1"
$VMInfo = CreateVM -vm "k8s-linux-agent-1" -resourceGroup $AKS_PERS_RESOURCE_GROUP `
    -subnetId $AKS_SUBNET_ID `
    -networkSecurityGroup $NETWORK_SECURITY_GROUP `
    -publicKeyFile $SSH_PUBLIC_KEY_FILE `
    -image $urn

Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@$($VMInfo.IP)"

Write-Host "Creating linux vm 2"
$VMInfo = CreateVM -vm "k8s-linux-agent-2" -resourceGroup $AKS_PERS_RESOURCE_GROUP `
    -subnetId $AKS_SUBNET_ID `
    -networkSecurityGroup $NETWORK_SECURITY_GROUP `
    -publicKeyFile $SSH_PUBLIC_KEY_FILE `
    -image $urn

Write-Host "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@$($VMInfo.IP)"

if ($AKS_SUPPORT_WINDOWS_CONTAINERS -eq "y") {
    Write-Host "Creating windows vm 1"
    $vm = "k8swindows1"
    $PUBLIC_IP_NAME = "${vm}PublicIP"
    $ip = az network public-ip create --name $PUBLIC_IP_NAME `
        --resource-group $AKS_PERS_RESOURCE_GROUP `
        --allocation-method Static --query "publicIp.ipAddress" -o tsv

    az network nic create `
        --resource-group $AKS_PERS_RESOURCE_GROUP `
        --name "${vm}-nic" `
        --subnet $AKS_SUBNET_ID `
        --network-security-group $NETWORK_SECURITY_GROUP `
        --public-ip-address $PUBLIC_IP_NAME

    # Update for your admin password
    $AdminPassword = "ChangeYourAdminPassword1"

    # to list Windows images: az vm image list --offer WindowsServer --all --output table
    $urn = "MicrosoftWindowsServer:WindowsServerSemiAnnual:Datacenter-Core-1709-with-Containers-smalldisk:1709.0.20171012"
    $urn = "Win2016Datacenter"
    az vm create --resource-group $AKS_PERS_RESOURCE_GROUP --name $vm `
        --image "$urn" `
        --size Standard_DS2_v2 `
        --admin-username azureuser --admin-password $AdminPassword `
        --nics "${vm}-nic" `
        --query "provisioningState" -o tsv

    # https://stackoverflow.com/questions/43914269/how-to-run-simple-custom-commands-on-a-azure-vm-win-7-8-10-server-post-deploy
    # az vm extension set -n CustomScriptExtension --publisher Microsoft.Compute --version 1.8 --vm-name DVWinServerVMB --resource-group DVResourceGroup --settings "{'commandToExecute': 'powershell.exe md c:\\test'}"

}


