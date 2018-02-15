Write-output "--- create-bare-metal Version 2018.02.14.01 ----"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/create-bare-metal.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

$AKS_PERS_RESOURCE_GROUP = ""
$AKS_PERS_LOCATION = ""
$AKS_CLUSTER_NAME = ""
$AKS_PERS_STORAGE_ACCOUNT_NAME = ""
$AKS_SUBSCRIPTION_ID = ""
$AKS_VNET_NAME = ""
$AKS_SUBNET_NAME = ""
$AKS_SUBNET_RESOURCE_GROUP = ""
$AKS_SSH_KEY = ""
$AKS_FIRST_STATIC_IP = ""
$AKS_USE_AZURE_NETWORKING = "n"
$AKS_SERVICE_PRINCIPAL_NAME = ""
$AKS_SUPPORT_WINDOWS_CONTAINERS = "n"

write-output "Checking if you're already logged in..."

# to print out the result to screen also use: <command> | Tee-Object -Variable cmdOutput
$loggedInUser = az account show --query "user.name"  --output tsv

# get azure login and subscription
Write-Output "user: $loggedInUser"

if ( "$loggedInUser" ) {
    $SUBSCRIPTION_NAME = az account show --query "name"  --output tsv
    Write-Output "You are currently logged in as [$loggedInUser] into subscription [$SUBSCRIPTION_NAME]"
    
    Do { $confirmation = Read-Host "Do you want to use this account? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($confirmation))

    if ($confirmation -eq 'n') {
        az login
    }    
}
else {
    # login
    az login
}

$AKS_SUBSCRIPTION_ID = az account show --query "id" --output tsv

# ask for customerid
Do { $customerid = Read-Host "Health Catalyst Customer ID (e.g., ahmn)"}
while ([string]::IsNullOrWhiteSpace($customerid))

Write-Output "Customer ID: $customerid"

# ask for resource group name to create
$DEFAULT_RESOURCE_GROUP = "Prod-Kub-$($customerid.ToUpper())-RG"
Do { 
    $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group (leave empty for $DEFAULT_RESOURCE_GROUP)"
    if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
        $AKS_PERS_RESOURCE_GROUP = $DEFAULT_RESOURCE_GROUP
    }
}
while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))

Write-Output "Using resource group [$AKS_PERS_RESOURCE_GROUP]"

Do { $AKS_PERS_LOCATION = Read-Host "Location: (e.g., eastus)"}
while ([string]::IsNullOrWhiteSpace($AKS_PERS_LOCATION))

$AKS_SUPPORT_WINDOWS_CONTAINERS = Read-Host "Support Windows containers (y/n) (default: n)"
if ([string]::IsNullOrWhiteSpace($AKS_SUPPORT_WINDOWS_CONTAINERS)) {
    $AKS_SUPPORT_WINDOWS_CONTAINERS = "n"
}

if ("$AKS_SUPPORT_WINDOWS_CONTAINERS" -eq "n") {
    # azure networking is not supported with windows containers
    # do we want to use azure networking or kube networking
    $AKS_USE_AZURE_NETWORKING = Read-Host "Use Azure networking (default: y)"
    if ([string]::IsNullOrWhiteSpace($AKS_USE_AZURE_NETWORKING)) {
        $AKS_USE_AZURE_NETWORKING = "y"
    }
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
    Write-Output "$AKS_LOCAL_FOLDER does not exist.  Creating it..."
    New-Item -ItemType directory -Path $AKS_LOCAL_FOLDER
}

# add the c:\kubernetes folder to system PATH
Write-Output "Checking if $AKS_LOCAL_FOLDER is in PATH"
$pathItems = ($env:path).split(";")
if ( $pathItems -notcontains "$AKS_LOCAL_FOLDER") {
    Write-Output "Adding $AKS_LOCAL_FOLDER to system path"
    $oldpath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH).path
    # see if the registry value is wrong too
    if ( ($oldpath).split(";") -notcontains "$AKS_LOCAL_FOLDER") {
        $newpath = "$oldpath;$AKS_LOCAL_FOLDER"
        Read-Host "Script needs elevated privileges to set PATH.  Hit ENTER to launch script to set PATH"
        Start-Process powershell -verb RunAs -ArgumentList "Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH -Value '$newPath'; Read-Host 'Press ENTER'"
        Write-Output "New PATH:"
        $newpath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH).path
        Write-Output "$newpath".split(";")
    }
    # for current session set the PATH too.  the above only takes effect if powershell is reopened
    $ENV:PATH = "$ENV:PATH;$AKS_LOCAL_FOLDER"
    Write-Output "Set path for current powershell session"
    Write-Output ($env:path).split(";")
}
else {
    Write-Output "$AKS_LOCAL_FOLDER is already in PATH"
}

$AKS_FOLDER_FOR_SSH_KEY = "$AKS_LOCAL_FOLDER\ssh\$AKS_PERS_RESOURCE_GROUP"

if (!(Test-Path -Path "$AKS_FOLDER_FOR_SSH_KEY")) {
    Write-Output "$AKS_FOLDER_FOR_SSH_KEY does not exist.  Creating it..."
    New-Item -ItemType directory -Path "$AKS_FOLDER_FOR_SSH_KEY"
}

# check if SSH key is present.  If not, generate it
$SSH_PRIVATE_KEY_FILE = "$AKS_FOLDER_FOR_SSH_KEY\id_rsa"
$SSH_PRIVATE_KEY_FILE_UNIX_PATH = "/" + (($SSH_PRIVATE_KEY_FILE -replace "\\", "/") -replace ":", "").ToLower().Trim("/")    

if (!(Test-Path "$SSH_PRIVATE_KEY_FILE")) {
    Write-Output "SSH key does not exist in $SSH_PRIVATE_KEY_FILE."
    Write-Output "Please open Git Bash and run:"
    Write-Output "ssh-keygen -t rsa -b 2048 -q -N '' -C azureuser@linuxvm -f $SSH_PRIVATE_KEY_FILE_UNIX_PATH"
    Read-Host "Hit ENTER after you're done"
}
else {
    Write-Output "SSH key already exists at $SSH_PRIVATE_KEY_FILE so using it"
}

$SSH_PUBLIC_KEY_FILE = "$AKS_FOLDER_FOR_SSH_KEY\id_rsa.pub"
$AKS_SSH_KEY = Get-Content "$SSH_PUBLIC_KEY_FILE" -First 1
Write-Output "SSH Public Key=$AKS_SSH_KEY"

# download kubectl
$KUBECTL_FILE = "$AKS_LOCAL_FOLDER\kubectl.exe"
$DESIRED_KUBECTL_VERSION = "v1.9.2"
$downloadkubectl = "n"
if (!(Test-Path "$KUBECTL_FILE")) {
    $downloadkubectl = "y"
}
else {
    $kubectlversion = kubectl version --client=true --short=true
    $kubectlversionMatches = $($kubectlversion -match "$DESIRED_KUBECTL_VERSION")
    if (!$kubectlversionMatches) {
        $downloadkubectl = "y"
    }
}
if ( $downloadkubectl -eq "y") {
    $url = "https://storage.googleapis.com/kubernetes-release/release/${DESIRED_KUBECTL_VERSION}/bin/windows/amd64/kubectl.exe"
    Write-Output "Downloading kubectl.exe from url $url to $KUBECTL_FILE"
    Remove-Item -Path "$KUBECTL_FILE"
    (New-Object System.Net.WebClient).DownloadFile($url, $KUBECTL_FILE)
}
else {
    Write-Output "kubectl already exists at $KUBECTL_FILE"    
}

$AKS_VNET_NAME = "kubnettest"
$AKS_SUBNET_NAME = "kubsubnet"
$AKS_SUBNET_RESOURCE_GROUP = "Imran"
$AKS_SUBNET_ID = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${AKS_VNET_NAME}/subnets/${AKS_SUBNET_NAME}"

CleanResourceGroup -resourceGroup ${AKS_PERS_RESOURCE_GROUP} -location $AKS_PERS_LOCATION -vnet $AKS_VNET_NAME `
    -subnet $AKS_SUBNET_NAME -subnetResourceGroup $AKS_SUBNET_RESOURCE_GROUP `
    -storageAccount $AKS_PERS_STORAGE_ACCOUNT_NAME

# az network vnet create -g $AKS_PERS_RESOURCE_GROUP -n $AKS_VNET_NAME --address-prefix 10.0.0.0/16 --subnet-name $AKS_SUBNET_NAME --subnet-prefix 10.0.0.0/19

$MASTER_VM_NAME = "k8s-master"
$NETWORK_SECURITY_GROUP = "cluster-nsg"
$nsg = az network nsg create --name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP --query "id" -o tsv 

Write-Output "Creating rule: allow_ssh"
az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n allow_ssh --priority 100 `
    --source-address-prefixes "*" --source-port-ranges '*' `
    --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow `
    --protocol Tcp --description "allow ssh access." `
    --query "provisioningState" -o tsv

Write-Output "Creating rule: allow_rdp"
az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n allow_rdp `
    --priority 101 `
    --source-address-prefixes "*" --source-port-ranges '*' `
    --destination-address-prefixes '*' --destination-port-ranges 3389 --access Allow `
    --protocol Tcp --description "allow RDP access." `
    --query "provisioningState" -o tsv

if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpPort" --nsg-name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Output "Creating rule: HttpPort"
    az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpPort --priority 500 `
        --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
        --protocol Tcp --description "allow HTTP access from $sourceTagForHttpAccess." `
        --query "provisioningState" -o tsv
}
else {
    Write-Output "Updating rule: HttpPort"
    az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpPort --priority 500 `
        --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
        --protocol Tcp --description "allow HTTP access from $sourceTagForHttpAccess." `
        --query "provisioningState" -o tsv
}

if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpsPort" --nsg-name $NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Output "Creating rule: HttpsPort"
    az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpsPort --priority 501 `
        --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
        --protocol Tcp --description "allow HTTPS access from $sourceTagForHttpAccess." `
        --query "provisioningState" -o tsv
}
else {
    Write-Output "Updating rule: HttpsPort"
    az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $NETWORK_SECURITY_GROUP -n HttpsPort --priority 501 `
        --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
        --protocol Tcp --description "allow HTTPS access from $sourceTagForHttpAccess." `
        --query "provisioningState" -o tsv
}    

$nsgid = az network nsg list --resource-group ${AKS_PERS_RESOURCE_GROUP} --query "[?name == '${NETWORK_SECURITY_GROUP}'].id" -o tsv
Write-Output "Found ID for ${AKS_PERS_NETWORK_SECURITY_GROUP}: $nsgid"

Write-Output "Setting NSG into subnet"
az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --network-security-group "$nsgid" --query "provisioningState" -o tsv

    
Write-Output "Creating master"
$PUBLIC_IP_NAME = "${MASTER_VM_NAME}PublicIP"
$ip = az network public-ip create --name $PUBLIC_IP_NAME `
    --resource-group $AKS_PERS_RESOURCE_GROUP `
    --allocation-method Static --query "publicIp.ipAddress" -o tsv

az network nic create `
    --resource-group $AKS_PERS_RESOURCE_GROUP `
    --name "${MASTER_VM_NAME}-nic" `
    --subnet $AKS_SUBNET_ID `
    --network-security-group $NETWORK_SECURITY_GROUP `
    --public-ip-address $PUBLIC_IP_NAME

az vm create --resource-group $AKS_PERS_RESOURCE_GROUP --name $MASTER_VM_NAME `
    --image CentOs --size Standard_DS2_v2 `
    --admin-username azureuser --ssh-key-value $SSH_PUBLIC_KEY_FILE `
    --nics "${MASTER_VM_NAME}-nic"

Write-Output "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${ip}"

Write-Output "Creating linux vm 1"
$vm = "k8s-linux-agent-1"
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

az vm create --resource-group $AKS_PERS_RESOURCE_GROUP --name $vm `
    --image CentOs --size Standard_DS2_v2 `
    --admin-username azureuser --ssh-key-value $SSH_PUBLIC_KEY_FILE `
    --nics "${vm}-nic"

Write-Output "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${ip}"

Write-Output "Creating windows vm 1"
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

$urn = "MicrosoftWindowsServer:WindowsServerSemiAnnual:Datacenter-Core-1709-with-Containers-smalldisk:1709.0.20171012"
$urn = "Win2016Datacenter"
az vm create --resource-group $AKS_PERS_RESOURCE_GROUP --name $vm `
    --image "$urn" `
    --size Standard_DS2_v2 `
    --admin-username azureuser --admin-password $AdminPassword `
    --nics "${vm}-nic"



# https://stackoverflow.com/questions/43914269/how-to-run-simple-custom-commands-on-a-azure-vm-win-7-8-10-server-post-deploy
# az vm extension set -n CustomScriptExtension --publisher Microsoft.Compute --version 1.8 --vm-name DVWinServerVMB --resource-group DVResourceGroup --settings "{'commandToExecute': 'powershell.exe md c:\\test'}"

