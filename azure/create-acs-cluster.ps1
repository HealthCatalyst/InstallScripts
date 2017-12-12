write-output "Version 1.068"

#
# This script is meant for quick & easy install via:
#   curl -sSL https://healthcatalyst.github.io/InstallScripts/azure/createkubernetescluster.txt | sh -s

# Remember: no spaces allowed in variable set commands in bash

$AKS_PERS_RESOURCE_GROUP = ""
$AKS_PERS_LOCATION = ""
$AKS_CLUSTER_NAME = ""
$AKS_PERS_STORAGE_ACCOUNT_NAME = ""
$AKS_PERS_SHARE_NAME = ""
$AKS_SUBSCRIPTION_ID = ""
$AKS_VNET_NAME = ""
$AKS_SUBNET_NAME = ""
$AKS_SUBNET_RESOURCE_GROUP = ""
$AKS_SSH_KEY = ""
$AKS_FIRST_STATIC_IP = ""

write-output "Checking if you're already logged in..."

# to print out the result to screen also use: <command> | Tee-Object -Variable cmdOutput
$loggedInUser = az account show --query "user.name"  --output tsv

Write-Output "user: $loggedInUser"

if ( "$loggedInUser" ) {
    $SUBSCRIPTION_NAME = az account show --query "name"  --output tsv
    Write-Output "You are currently logged in as $loggedInUser into subscription $SUBSCRIPTION_NAME"
    
    $confirmation = Read-Host "Do you want to use this account? (y/n)"
    if ($confirmation -eq 'n') {
        az login
    }    
}
else {
    # login
    az login
}

$AKS_SUBSCRIPTION_ID = az account show --query "id" --output tsv

$AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group: (e.g., fabricnlp-rg)"

$AKS_PERS_LOCATION = Read-Host "Location: (e.g., eastus)"

$AKS_CLUSTER_NAME = "kubcluster"
# $AKS_CLUSTER_NAME = Read-Host "Cluster Name: (e.g., fabricnlpcluster)"

$AKS_PERS_STORAGE_ACCOUNT_NAME = Read-Host "Storage Account Name: (leave empty for default)"

$AKS_PERS_SHARE_NAME = Read-Host "Storage File share Name: (leave empty for default)"

# see if the user wants to use a specific virtual network
$AKS_VNET_NAME = Read-Host "Virtual Network Name: (leave empty for default)"

if ("$AKS_VNET_NAME") {
    $AKS_SUBNET_NAME = Read-Host "Subnet Name"
    $AKS_SUBNET_RESOURCE_GROUP = Read-Host "Resource Group of Subnet"
}

Write-Output "checking if resource group already exists"
$resourceGroupExists = az group exists --name ${AKS_PERS_RESOURCE_GROUP}
if ($resourceGroupExists -eq "true") {
    Write-Host "The resource group ${AKS_PERS_RESOURCE_GROUP} already exists with these resources:"
    az resource list --resource-group "${AKS_PERS_RESOURCE_GROUP}" --query "id"
    $confirmation = Read-Host "Would you like to delete it (all above resources will be deleted)? (y/n)"
    if ($confirmation -eq 'n') {
        exit 0
    }    
    Write-Output "delete existing group: $AKS_PERS_RESOURCE_GROUP"
    az group delete --name $AKS_PERS_RESOURCE_GROUP --verbose
}

Write-Output "Create the Resource Group"
az group create --name $AKS_PERS_RESOURCE_GROUP --location $AKS_PERS_LOCATION --verbose

Write-Output "checking if Service Principal already exists"
$AKS_SERVICE_PRINCIPAL_NAME = "${AKS_PERS_RESOURCE_GROUP}Kubernetes"
$AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv

$myscope = "/subscriptions/${AKS_SUBSCRIPTION_ID}"

if ("$AKS_SERVICE_PRINCIPAL_CLIENTID") {
    Write-Host "Service Principal already exists with name: $AKS_SERVICE_PRINCIPAL_NAME"
    Write-Output "Deleting..."
    az ad sp delete --id "$AKS_SERVICE_PRINCIPAL_CLIENTID" --verbose
    Write-Output "Creating Service Principal: $AKS_SERVICE_PRINCIPAL_NAME"
    $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Contributor" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
    Write-Output "created $AKS_SERVICE_PRINCIPAL_NAME clientId=$AKS_SERVICE_PRINCIPAL_CLIENTID clientsecret=$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
}
else {
    Write-Output "Creating Service Principal: $AKS_SERVICE_PRINCIPAL_NAME"
    $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Contributor" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
    $AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv
    Write-Output "created $AKS_SERVICE_PRINCIPAL_NAME clientId=$AKS_SERVICE_PRINCIPAL_CLIENTID clientsecret=$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
}

Write-Output "Create Azure Container Service cluster"

$mysubnetid = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${AKS_VNET_NAME}/subnets/${AKS_SUBNET_NAME}"

$SSH_PUBLIC_KEY_FILE = "$env:userprofile/.ssh/id_rsa.pub"
if (!(Test-Path "$SSH_PUBLIC_KEY_FILE")) {
    Write-Output "SSH key does not exist in $SSH_PUBLIC_KEY_FILE.  Creating it..."
    ssh-keygen -t rsa -b 2048 -q -N "" -C azureuser@linuxvm -f "$SSH_PUBLIC_KEY_FILE"
}

$AKS_SSH_KEY = Get-Content "$SSH_PUBLIC_KEY_FILE" -First 1

$dnsNamePrefix = "$AKS_PERS_RESOURCE_GROUP"

# az acs create --orchestrator-type kubernetes --resource-group $AKS_PERS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --generate-ssh-keys --agent-count=3 --agent-vm-size Standard_B2ms
#az acs create --orchestrator-type kubernetes --resource-group fabricnlpcluster --name cluster1 --service-principal="$AKS_SERVICE_PRINCIPAL_CLIENTID" --client-secret="$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"  --generate-ssh-keys --agent-count=3 --agent-vm-size Standard_D2 --master-vnet-subnet-id="$mysubnetid" --agent-vnet-subnet-id="$mysubnetid"

$url = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/acs.template.json"
if (!"$AKS_VNET_NAME") {
    $url = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/acs.template.nosubnet.json"    
}

$output = "$env:TEMP\acs.json"
Write-Output "Downloading parameters file from github to $output"
if (Test-Path $output) {
    Remove-Item $output
}

# Write-Output "Invoke-WebRequest -Uri $url -OutFile $output -ContentType 'text/plain; charset=utf-8'"

Invoke-WebRequest -Uri $url -OutFile $output -ContentType "text/plain; charset=utf-8"

if ("$AKS_VNET_NAME") {
    Write-Output "Looking up CIDR for Subnet: ${AKS_SUBNET_NAME}"
    $AKS_SUBNET_CIDR = az network vnet subnet show --name ${AKS_SUBNET_NAME} --resource-group ${AKS_SUBNET_RESOURCE_GROUP} --vnet-name ${AKS_VNET_NAME} --query "addressPrefix" --output tsv

    Write-Output "Subnet CIDR=$AKS_SUBNET_CIDR"
}

# helper functions for subnet match
# from https://gallery.technet.microsoft.com/scriptcenter/Start-and-End-IP-addresses-bcccc3a9
function Get-FirstIP {
    <# 
  .SYNOPSIS  
    Get the IP addresses in a range 
  .EXAMPLE 
   Get-IPrange -start 192.168.8.2 -end 192.168.8.20 
  .EXAMPLE 
   Get-IPrange -ip 192.168.8.2 -mask 255.255.255.0 
  .EXAMPLE 
   Get-IPrange -ip 192.168.8.3 -cidr 24 
#> 
 
    param 
    ( 
        [string]$start, 
        [string]$end, 
        [string]$ip, 
        [string]$mask, 
        [int]$cidr 
    ) 
 
    function IP-toINT64 () { 
        param ($ip) 
 
        $octets = $ip.split(".") 
        return [int64]([int64]$octets[0] * 16777216 + [int64]$octets[1] * 65536 + [int64]$octets[2] * 256 + [int64]$octets[3]) 
    } 
 
    function INT64-toIP() { 
        param ([int64]$int) 

        return (([math]::truncate($int / 16777216)).tostring() + "." + ([math]::truncate(($int % 16777216) / 65536)).tostring() + "." + ([math]::truncate(($int % 65536) / 256)).tostring() + "." + ([math]::truncate($int % 256)).tostring() )
    } 
 
    if ($ip.Contains("/")) {
        $Temp = $ip.Split("/")
        $ip = $Temp[0]
        $cidr = $Temp[1]
    }

    if ($ip) {$ipaddr = [Net.IPAddress]::Parse($ip)} 
    if ($cidr) {$maskaddr = [Net.IPAddress]::Parse((INT64-toIP -int ([convert]::ToInt64(("1" * $cidr + "0" * (32 - $cidr)), 2)))) } 
    if ($mask) {$maskaddr = [Net.IPAddress]::Parse($mask)} 
    if ($ip) {$networkaddr = new-object net.ipaddress ($maskaddr.address -band $ipaddr.address)} 
    if ($ip) {$broadcastaddr = new-object net.ipaddress (([system.net.ipaddress]::parse("255.255.255.255").address -bxor $maskaddr.address -bor $networkaddr.address))} 
 
    if ($ip) { 
        $startaddr = IP-toINT64 -ip $networkaddr.ipaddresstostring 
        $endaddr = IP-toINT64 -ip $broadcastaddr.ipaddresstostring 
    }
    else { 
        $startaddr = IP-toINT64 -ip $start 
        $endaddr = IP-toINT64 -ip $end 
    } 
 
    $startaddr = $startaddr + 10 # skip the first few since they are reserved
    INT64-toIP -int $startaddr
}

$AKS_FIRST_STATIC_IP=""
$AKS_SUBNET_CIDR=""
if ("$AKS_VNET_NAME") {
    $suggestedFirstStaticIP = Get-FirstIP -ip ${AKS_SUBNET_CIDR}

    $AKS_FIRST_STATIC_IP = Read-Host "First static IP: (default: $suggestedFirstStaticIP )"
    if (!"$AKS_FIRST_STATIC_IP") {
        $AKS_FIRST_STATIC_IP = "$suggestedFirstStaticIP"
    }

    Write-Output "First static IP=${AKS_FIRST_STATIC_IP}"
}

# subnet CIDR to mask
# https://doc.m0n0.ch/quickstartpc/intro-CIDR.html

Write-Output "replacing values in the acs.json file"
$MyFile = (Get-Content $output) | 
    Foreach-Object {$_ -replace 'REPLACE-SSH-KEY', "${AKS_SSH_KEY}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-CLIENTID', "${AKS_SERVICE_PRINCIPAL_CLIENTID}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-CLIENTSECRET', "${AKS_SERVICE_PRINCIPAL_CLIENTSECRET}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-SUBNET', "${mysubnetid}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-DNS-NAME-PREFIX', "${dnsNamePrefix}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-FIRST-STATIC-IP', "${AKS_FIRST_STATIC_IP}"}  | 
    Foreach-Object {$_ -replace 'REPLACE_VNET_CIDR', "${AKS_SUBNET_CIDR}"}  

# have to do it this way instead of Outfile so we can get a UTF-8 file without BOM
# from https://stackoverflow.com/questions/5596982/using-powershell-to-write-a-file-in-utf-8-without-the-bom
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
[System.IO.File]::WriteAllLines($output, $MyFile, $Utf8NoBomEncoding)

$acsoutputfolder = "$env:TEMP\_output\$dnsNamePrefix"

Write-Output "Generating ACS engine template"
acs-engine generate "$output" --output-directory "$acsoutputfolder"

az group deployment create `
    --template-file "$acsoutputfolder\azuredeploy.json" `
    --resource-group $AKS_PERS_RESOURCE_GROUP -n $AKS_CLUSTER_NAME `
    --parameters "$acsoutputfolder\azuredeploy.parameters.json" `
    --mode Complete --verbose	

Write-Output "Saved to $acsoutputfolder\azuredeploy.json"

if ("$AKS_VNET_NAME") {
    Write-Output "Attach route table"
    # https://github.com/Azure/acs-engine/blob/master/examples/vnet/k8s-vnet-postdeploy.sh
    $rt = az network route-table list -g "${AKS_PERS_RESOURCE_GROUP}" | jq -r '.[].id'
    az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --route-table "$rt"
}

Write-Output "Getting kube config by ssh to the master VM"
$MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
$SSH_PRIVATE_KEY_FILE = "$env:userprofile\.ssh\id_rsa"

if (Get-Module -ListAvailable -Name Posh-SSH) {
}
else {
    Install-Module Posh-SSH -Scope CurrentUser -Force
}

$User = "azureuser"
$Credential = New-Object System.Management.Automation.PSCredential($User, (new-object System.Security.SecureString))
New-SSHSession -ComputerName ${MASTER_VM_NAME} -KeyFile "${SSH_PRIVATE_KEY_FILE}" -Credential $Credential -AcceptKey -Verbose -Force
Invoke-SSHCommand -Command "cat ./.kube/config" -SessionId 0 | Out-File "$env:userprofile\.kube\config"
Remove-SSHSession -SessionId 0
# ssh -i "${SSH_PRIVATE_KEY_FILE}" "azureuser@${MASTER_VM_NAME}" cat ./.kube/config > "$env:userprofile\.kube\config"

Write-Output "Check nodes via kubectl"
kubectl get nodes

$nodeCount = 0

while ($nodeCount -lt 3) {
    $lines = kubectl get nodes -o=name | Measure-Object -Line
    $nodeCount = $lines.Lines
    Start-Sleep -s 10
}

Write-Output "Create the storage account"
if (!"$AKS_PERS_STORAGE_ACCOUNT_NAME") {
    $AKS_PERS_STORAGE_ACCOUNT_NAME = "${AKS_PERS_RESOURCE_GROUP}storage"
    Write-Output "Checking to see if storage account exists"
    $storageaccountexists = az storage account check-name --name $AKS_PERS_STORAGE_ACCOUNT_NAME --query "nameAvailable" --output tsv

    if ($storageaccountexists -ne "True" ) {
        az storage account check-name --name $AKS_PERS_STORAGE_ACCOUNT_NAME   
        Write-Error "Storage account, $AKS_PERS_STORAGE_ACCOUNT_NAME, already exists.  Please check and delete first"
        exit 0
    }

    Write-Output "Using storage account: ${AKS_PERS_STORAGE_ACCOUNT_NAME}"
    az storage account create -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $AKS_PERS_RESOURCE_GROUP -l $AKS_PERS_LOCATION --sku Standard_LRS
}
else {
    Write-Output "Checking to see if storage account exists"
    $storageaccountexists = az storage account check-name --name $AKS_PERS_STORAGE_ACCOUNT_NAME --query "nameAvailable" --output tsv

    if ($storageaccountexists -ne "True" ) {
        Write-Error "Storage account, $AKS_PERS_STORAGE_ACCOUNT_NAME, does not exist."
        exit 0
    }
    
}
if (!"${AKS_PERS_SHARE_NAME}") {
    $AKS_PERS_SHARE_NAME = "fileshare"
    Write-Output "Using share name: ${AKS_PERS_SHARE_NAME}"
}

# Export the connection string as an environment variable, this is used when creating the Azure file share
# $AZURE_STORAGE_CONNECTION_STRING = az storage account show-connection-string -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $AKS_PERS_RESOURCE_GROUP -o tsv

# Write-Output "Create the file share"
# az storage share create -n $AKS_PERS_SHARE_NAME --connection-string $AZURE_STORAGE_CONNECTION_STRING

Write-Output "Get storage account key"
$STORAGE_KEY = az storage account keys list --resource-group $AKS_PERS_RESOURCE_GROUP --account-name $AKS_PERS_STORAGE_ACCOUNT_NAME --query "[0].value" --output tsv

Write-Output "Storagekey: $STORAGE_KEY"

Write-Output "Creating kubernetes secret"
kubectl create secret generic azure-secret --from-literal=azurestorageaccountname="${AKS_PERS_STORAGE_ACCOUNT_NAME}" --from-literal=azurestorageaccountkey="${STORAGE_KEY}"

Write-Output "Deploy the ingress controller"
kubectl create -f ingress.yml

kubectl create -f loadbalancer-internal.yml

kubectl get deployments, pods, services, ingress, secrets --namespace=kube-system

