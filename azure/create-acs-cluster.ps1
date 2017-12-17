write-output "Version 2017.12.17.1"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/create-acs-cluster.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
#$GITHUB_URL = "."

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
$AKS_OPEN_TO_PUBLIC = ""
$AKS_USE_AZURE_NETWORKING = "no"

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

$AKS_LOCAL_FOLDER = Read-Host "Folder to store SSH keys: (default: c:\kubernetes)"

if (!"$AKS_LOCAL_FOLDER") {$AKS_LOCAL_FOLDER = "C:\kubernetes"}

if (!(Test-Path -Path "$AKS_LOCAL_FOLDER")) {
    Write-Output "$AKS_LOCAL_FOLDER does not exist.  Creating it..."
    New-Item -ItemType directory -Path $AKS_LOCAL_FOLDER
}

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

# check if SSH key is present
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

$KUBECTL_FILE = "$AKS_LOCAL_FOLDER\kubectl.exe"
if (!(Test-Path "$KUBECTL_FILE")) {
    Write-Output "Downloading kubectl.exe to $KUBECTL_FILE"
    $url = "https://storage.googleapis.com/kubernetes-release/release/v1.8.0/bin/windows/amd64/kubectl.exe"
    (New-Object System.Net.WebClient).DownloadFile($url, $KUBECTL_FILE)
}
else {
    Write-Output "kubectl already exists at $KUBECTL_FILE"    
}

# echo download as-engine
$ACS_ENGINE_FILE = "$AKS_LOCAL_FOLDER\acs-engine.exe"
if (!(Test-Path "$ACS_ENGINE_FILE")) {
    Write-Output "Downloading acs-engine.exe to $ACS_ENGINE_FILE"
    $url = "https://github.com/Azure/acs-engine/releases/download/v0.10.0/acs-engine-v0.10.0-windows-amd64.zip"
    (New-Object System.Net.WebClient).DownloadFile($url, "$AKS_LOCAL_FOLDER\acs-engine.zip")
    Expand-Archive -Path "$AKS_LOCAL_FOLDER\acs-engine.zip" -DestinationPath "$AKS_LOCAL_FOLDER" -Force
    Copy-Item -Path "$AKS_LOCAL_FOLDER\acs-engine-v0.10.0-windows-amd64\acs-engine.exe" -Destination $ACS_ENGINE_FILE
}
else {
    Write-Output "acs-engine.exe already exists at $ACS_ENGINE_FILE"    
}

$AKS_PERS_LOCATION = Read-Host "Location: (e.g., eastus)"

$AKS_CLUSTER_NAME = "kubcluster"
# $AKS_CLUSTER_NAME = Read-Host "Cluster Name: (e.g., fabricnlpcluster)"

$AKS_PERS_STORAGE_ACCOUNT_NAME = Read-Host "Storage Account Name: (leave empty for default)"

# $AKS_PERS_SHARE_NAME = Read-Host "Storage File share Name: (leave empty for default)"

# see if the user wants to use a specific virtual network
$AKS_VNET_NAME = Read-Host "Virtual Network Name: (leave empty for default)"

if ("$AKS_VNET_NAME") {
    $AKS_SUBNET_NAME = Read-Host "Subnet Name"
    $AKS_SUBNET_RESOURCE_GROUP = Read-Host "Resource Group of Subnet"

    # verify the subnet exists
    $mysubnetid = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${AKS_VNET_NAME}/subnets/${AKS_SUBNET_NAME}"

    $subnetexists = az resource show --ids $mysubnetid --query "id" -o tsv
    if (!"$subnetexists") {
        Write-Host "The subnet was not found: $mysubnetid"
        Read-Host "Hit ENTER to exit"
        exit 0        
    }
    else {
        Write-Output "Found subnet: $mysubnetid"
    }
}

$AKS_OPEN_TO_PUBLIC = Read-Host "Do you want this cluster open to public? (y/n)"


Write-Output "checking if resource group already exists"
$resourceGroupExists = az group exists --name ${AKS_PERS_RESOURCE_GROUP}
if ($resourceGroupExists -eq "true") {

    if ($(az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[].id" -o tsv).length -ne 0) {
        Write-Host "The resource group ${AKS_PERS_RESOURCE_GROUP} already exists with the following VMs"
        az resource list --resource-group "${AKS_PERS_RESOURCE_GROUP}" --resource-type "Microsoft.Compute/virtualMachines" --query "[].id"
        $confirmation = Read-Host "Would you like to continue (all above resources will be deleted)? (y/n)"
        if ($confirmation -eq 'n') {
            Read-Host "Hit ENTER to exit"
            exit 0
        }    
    }
    else {
        Write-Host "The resource group ${AKS_PERS_RESOURCE_GROUP} already exists but has no VMs"
    }

    if ("$AKS_VNET_NAME") {
        # Write-Output "removing route table"
        # az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --route-table ""
    }
    Write-Output "cleaning out the existing group: $AKS_PERS_RESOURCE_GROUP"
    #az group delete --name $AKS_PERS_RESOURCE_GROUP --verbose

    if ($(az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[].id" -o tsv).length -ne 0) {
        Write-Output "delete the VMs first"
        az vm delete --ids $(az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[].id" -o tsv) --verbose --yes
    }

    if ($(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Network/networkInterfaces" --query "[].id" -o tsv ).length -ne 0) {
        Write-Output "delete the nics"
        az resource delete --ids $(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Network/networkInterfaces" --query "[].id" -o tsv )  --verbose
    }

    if ($(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Compute/disks" --query "[].id" -o tsv ).length -ne 0) {
        Write-Output "delete the disks"
        az resource delete --ids $(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Compute/disks" --query "[].id" -o tsv )
    }

    if ($(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Compute/availabilitySets" --query "[].id" -o tsv ).length -ne 0) {
        Write-Output "delete the availabilitysets"
        az resource delete --ids $(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Compute/availabilitySets" --query "[].id" -o tsv )
    }

    if ($(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Network/loadBalancers" --query "[].id" -o tsv ).length -ne 0) {
        Write-Output "delete the load balancers"
        az resource delete --ids $(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Network/loadBalancers" --query "[].id" -o tsv )
    }
    if ($(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Network/networkSecurityGroups" --query "[].id" -o tsv ).length -ne 0) {
        Write-Output "delete the network security groups"
        az resource delete --ids $(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Network/networkSecurityGroups" --query "[].id" -o tsv )
    }
    if ($(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("${AKS_PERS_RESOURCE_GROUP}storage")}).length -ne 0) {
        Write-Output "delete the storage accounts EXCEPT storage account we created in the past"
        az resource delete --ids $(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("${AKS_PERS_RESOURCE_GROUP}storage")} )
        # az resource list --resource-group fabricnlp3 --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | ForEach-Object { if (!"$_".EndsWith("${AKS_PERS_RESOURCE_GROUP}storage")) {  az resource delete --ids "$_" }}    
    }
    if ($(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Network/publicIPAddresses" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("IngressPublicIP")}).length -ne 0) {
        Write-Output "delete the pulbi IPs EXCEPT Ingress IP we created in the past"
        az resource delete --ids $(az resource list --resource-group $AKS_PERS_RESOURCE_GROUP --resource-type "Microsoft.Network/publicIPAddresses" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("IngressPublicIP")} )
    }
    
    
        
    # note: do not delete the Microsoft.Network/publicIPAddresses otherwise the loadBalancer will get a new IP
}
else {
    Write-Output "Create the Resource Group"
    az group create --name $AKS_PERS_RESOURCE_GROUP --location $AKS_PERS_LOCATION --verbose
}


Write-Output "checking if Service Principal already exists"
$AKS_SERVICE_PRINCIPAL_NAME = "${AKS_PERS_RESOURCE_GROUP}Kubernetes"
$AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv

$myscope = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_PERS_RESOURCE_GROUP}"

if ("$AKS_SERVICE_PRINCIPAL_CLIENTID") {
    Write-Host "Service Principal already exists with name: $AKS_SERVICE_PRINCIPAL_NAME"
    Write-Output "Deleting..."
    az ad sp delete --id "$AKS_SERVICE_PRINCIPAL_CLIENTID" --verbose
    # https://github.com/Azure/azure-cli/issues/1332
    Write-Output "Sleeping to wait for Service Principal to propagate"
    Start-Sleep -Seconds 30;

    Write-Output "Creating Service Principal: $AKS_SERVICE_PRINCIPAL_NAME"
    $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Owner" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
    # https://github.com/Azure/azure-cli/issues/1332
    Write-Output "Sleeping to wait for Service Principal to propagate"
    Start-Sleep -Seconds 30;
    $AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv
    Write-Output "created $AKS_SERVICE_PRINCIPAL_NAME clientId=$AKS_SERVICE_PRINCIPAL_CLIENTID clientsecret=$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
    
}
else {
    Write-Output "Creating Service Principal: $AKS_SERVICE_PRINCIPAL_NAME"
    $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Contributor" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
    # https://github.com/Azure/azure-cli/issues/1332
    Write-Output "Sleeping to wait for Service Principal to propagate"
    Start-Sleep -Seconds 30;

    $AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv
    Write-Output "created $AKS_SERVICE_PRINCIPAL_NAME clientId=$AKS_SERVICE_PRINCIPAL_CLIENTID clientsecret=$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
}

if ("$AKS_SUBNET_RESOURCE_GROUP") {
    Write-Output "Giving service principal access to vnet resource group: ${AKS_SUBNET_RESOURCE_GROUP}"
    $subnetscope = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}"
    az role assignment create --assignee $AKS_SERVICE_PRINCIPAL_CLIENTID --role "contributor" --scope "$subnetscope"
}

Write-Output "Create Azure Container Service cluster"

$mysubnetid = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${AKS_VNET_NAME}/subnets/${AKS_SUBNET_NAME}"

$dnsNamePrefix = "$AKS_PERS_RESOURCE_GROUP"

# az acs create --orchestrator-type kubernetes --resource-group $AKS_PERS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --generate-ssh-keys --agent-count=3 --agent-vm-size Standard_B2ms
#az acs create --orchestrator-type kubernetes --resource-group fabricnlpcluster --name cluster1 --service-principal="$AKS_SERVICE_PRINCIPAL_CLIENTID" --client-secret="$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"  --generate-ssh-keys --agent-count=3 --agent-vm-size Standard_D2 --master-vnet-subnet-id="$mysubnetid" --agent-vnet-subnet-id="$mysubnetid"

$templateFile = "acs.template.json"
if (!"$AKS_VNET_NAME") {
    $templateFile = "acs.template.nosubnet.json"    
}

$output = "$env:TEMP\acs.json"
Write-Output "Downloading parameters file from github to $output"
if (Test-Path $output) {
    Remove-Item $output
}

# Write-Output "Invoke-WebRequest -Uri $url -OutFile $output -ContentType 'text/plain; charset=utf-8'"
if ($GITHUB_URL.StartsWith("http")) { 
    Write-Output "Downloading file: $GITHUB_URL/azure/$templateFile"
    Invoke-WebRequest -Uri "$GITHUB_URL/azure/$templateFile" -OutFile $output -ContentType "text/plain; charset=utf-8"
}
else {
    Copy-Item -Path "$GITHUB_URL/azure/$templateFile" -Destination "$output"
}

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
 
    $startaddr = $startaddr + 256 # skip the first few since they are reserved
    INT64-toIP -int $startaddr
}

$AKS_FIRST_STATIC_IP = ""
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

# acs-engine deploy --subscription-id "$AKS_SUBSCRIPTION_ID" `
#                     --dns-prefix $dnsNamePrefix --location $AKS_PERS_LOCATION `
#                     --resource-group $AKS_PERS_RESOURCE_GROUP `
#                     --api-model "$output" `
#                     --output-directory "$acsoutputfolder"

acs-engine generate $output --output-directory $acsoutputfolder

# --orchestrator-version 1.8 `
# --ssh-key-value 

# az acs create `
#     --orchestrator-type kubernetes `
#     --dns-prefix ${dnsNamePrefix} `
#     --resource-group $AKS_PERS_RESOURCE_GROUP `
#     --name $AKS_CLUSTER_NAME `
#     --location $AKS_PERS_LOCATION `
#     --service-principal="$AKS_SERVICE_PRINCIPAL_CLIENTID" `
#     --client-secret="$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"  `
#     --agent-count=3 --agent-vm-size Standard_D2 `
#     --master-vnet-subnet-id="$mysubnetid" `
#     --agent-vnet-subnet-id="$mysubnetid"

Write-Output "Starting deployment..."

az group deployment create `
    --template-file "$acsoutputfolder\azuredeploy.json" `
    --resource-group $AKS_PERS_RESOURCE_GROUP -n $AKS_CLUSTER_NAME `
    --parameters "$acsoutputfolder\azuredeploy.parameters.json" `
    --verbose	

# Write-Output "Saved to $acsoutputfolder\azuredeploy.json"

if ("$AKS_VNET_NAME") {
    if ("$AKS_USE_AZURE_NETWORKING" -eq "no") {
        Write-Output "Attach route table"
        # https://github.com/Azure/acs-engine/blob/master/examples/vnet/k8s-vnet-postdeploy.sh
        $rt = az network route-table list -g "${AKS_PERS_RESOURCE_GROUP}" --query "[].id" -o tsv
        az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --route-table "$rt"
    }
}

# az.cmd acs kubernetes get-credentials `
#     --resource-group=$AKS_PERS_RESOURCE_GROUP `
#     --name=$AKS_CLUSTER_NAME

# Write-Output "Getting kube config by ssh to the master VM"
# $MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
# $SSH_PRIVATE_KEY_FILE = "$env:userprofile\.ssh\id_rsa"

# if (Get-Module -ListAvailable -Name Posh-SSH) {
# }
# else {
#     Install-Module Posh-SSH -Scope CurrentUser -Force
# }

# # from http://www.powershellmagazine.com/2014/07/03/posh-ssh-open-source-ssh-powershell-module/
# $User = "azureuser"
# $Credential = New-Object System.Management.Automation.PSCredential($User, (new-object System.Security.SecureString))
# # New-SSHSession -ComputerName ${MASTER_VM_NAME} -KeyFile "${SSH_PRIVATE_KEY_FILE}" -Credential $Credential -AcceptKey -Verbose -Force
# # Invoke-SSHCommand -Command "cat ./.kube/config" -SessionId 0 
# Get-SCPFile -LocalFile "$env:userprofile\.kube\config" -RemoteFile "./.kube/config" -ComputerName ${MASTER_VM_NAME} -KeyFile "${SSH_PRIVATE_KEY_FILE}" -Credential $Credential -AcceptKey -Verbose -Force
# Remove-SSHSession -SessionId 0

if (!(Test-Path -Path "$env:userprofile\.kube")) {
    Write-Output "$env:userprofile\.kube does not exist.  Creating it..."
    New-Item -ItemType directory -Path "$env:userprofile\.kube"
}

Copy-Item -Path "$acsoutputfolder\kubeconfig\kubeconfig.$AKS_PERS_LOCATION.json" -Destination "$env:userprofile\.kube\config"

$MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
Write-Output "You can connect to master VM in Git Bash for debugging using:"
Write-Output "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${MASTER_VM_NAME}"

Write-Output "Check nodes via kubectl"
kubectl get nodes -o=name

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
        $confirmation = Read-Host "Storage account, $AKS_PERS_STORAGE_ACCOUNT_NAME, already exists.  Delete it?  (Warning: deletes data) (y/n)"
        if ($confirmation -eq 'y') {
            az storage account delete -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $AKS_PERS_RESOURCE_GROUP
        }    
    }
    else {
        Write-Output "Using storage account: ${AKS_PERS_STORAGE_ACCOUNT_NAME}"
        az storage account create -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $AKS_PERS_RESOURCE_GROUP -l $AKS_PERS_LOCATION --sku Standard_LRS            
    }
}
else {
    Write-Output "Checking to see if storage account $AKS_PERS_STORAGE_ACCOUNT_NAME exists"
    $storageaccountexists = az storage account check-name --name $AKS_PERS_STORAGE_ACCOUNT_NAME --query "nameAvailable" --output tsv

    if ($storageaccountexists -ne "True" ) {
        Write-Error "Storage account, $AKS_PERS_STORAGE_ACCOUNT_NAME, does not exist."
        Read-Host "Hit ENTER to exit"
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
kubectl create -f "$GITHUB_URL/azure/ingress.yml"

if ("$AKS_OPEN_TO_PUBLIC" -eq "y") {
    Write-Output "Setting up a public load balancer"

    az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --location $AKS_PERS_LOCATION --allocation-method Static
    $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;

    $serviceyaml = @"
kind: Service
apiVersion: v1
metadata:
  name: traefik-ingress-service-public
  namespace: kube-system
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
    - protocol: TCP
      port: 80
      name: web
    - protocol: TCP
      port: 443
      name: ssl      
  type: LoadBalancer
  # Special notes for Azure: To use user-specified public type loadBalancerIP, a static type public IP address resource needs to be created first, 
  # and it should be in the same resource group of the cluster. 
  # note that in the case of AKS, that resource group is MC_<resourcegroup>_<cluster>
  # Then you could specify the assigned IP address as loadBalancerIP
  # https://kubernetes.io/docs/concepts/services-networking/service/#type-loadbalancer
  loadBalancerIP: $publicip
---
"@

    Write-Output $serviceyaml | kubectl create -f -
    #kubectl create -f "$GITHUB_URL/azure/loadbalancer-public.yml"

    #kubectl patch service traefik-ingress-service-public --loadBalancerIP=52.191.114.120

    #kubectl patch deployment traefik-ingress-controller -p '{"spec":{"loadBalancerIP":"52.191.114.120"}}'    
}
else {
    Write-Output "Setting up a private load balancer"
    kubectl create -f "$GITHUB_URL/azure/loadbalancer-internal.yml"
}

kubectl get "deployments,pods,services,ingress,secrets" --namespace=kube-system

