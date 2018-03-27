Write-output "--- create-acs-cluster Version 2018.03.27.01 ----"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/create-acs-cluster.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;


write-output "Checking if you're already logged in..."

DownloadAzCliIfNeeded

$config = $(ReadConfigFile).Config
Write-Host $config

$userInfo=$(GetLoggedInUserInfo)
$AKS_SUBSCRIPTION_ID = $userInfo.AKS_SUBSCRIPTION_ID
$IS_CAFE_ENVIRONMENT=$userInfo.IS_CAFE_ENVIRONMENT

$customerid=$($config.customerid)

Write-Output "Customer ID: $customerid"

$AKS_PERS_RESOURCE_GROUP = $config.azure.resourceGroup
$AKS_PERS_LOCATION = $config.azure.location

CreateResourceGroupIfNotExists -resourceGroup $AKS_PERS_RESOURCE_GROUP -location $AKS_PERS_LOCATION

$AKS_SUPPORT_WINDOWS_CONTAINERS = $config.azure.create_windows_containers
$AKS_USE_AZURE_NETWORKING = $config.azure.use_azure_networking

if ($AKS_SUPPORT_WINDOWS_CONTAINERS) {
    # azure networking is not supported with windows containers
    if($AKS_USE_AZURE_NETWORKING){
        Write-Error "Azure networking is not supported with Windows containers"
    }
}

# service account to own the resources
$AKS_SERVICE_PRINCIPAL_NAME = $config.service_principal.name

if ([string]::IsNullOrWhiteSpace($AKS_SERVICE_PRINCIPAL_NAME)) {
    $AKS_SERVICE_PRINCIPAL_NAME = "${AKS_PERS_RESOURCE_GROUP}Kubernetes"
}

# where to store the SSH keys on local machine
$AKS_LOCAL_FOLDER = $config.local_folder

if ([string]::IsNullOrWhiteSpace($AKS_LOCAL_FOLDER)) {$AKS_LOCAL_FOLDER = "C:\kubernetes"}

if (!(Test-Path -Path "$AKS_LOCAL_FOLDER")) {
    Write-Output "$AKS_LOCAL_FOLDER does not exist.  Creating it..."
    New-Item -ItemType directory -Path $AKS_LOCAL_FOLDER
}

AddFolderToPathEnvironmentVariable -folder $AKS_LOCAL_FOLDER

$SSHKeyInfo = CreateSSHKey -resourceGroup $AKS_PERS_RESOURCE_GROUP -localFolder $AKS_LOCAL_FOLDER
$AKS_SSH_KEY = $SSHKeyInfo.AKS_SSH_KEY
$SSH_PRIVATE_KEY_FILE_UNIX_PATH = $SSHKeyInfo.SSH_PRIVATE_KEY_FILE_UNIX_PATH
DownloadKubectl -localFolder $AKS_LOCAL_FOLDER

# download acs-engine
$ACS_ENGINE_FILE = "$AKS_LOCAL_FOLDER\acs-engine.exe"
$DESIRED_ACS_ENGINE_VERSION = "v0.13.0"
$downloadACSEngine = "n"
if (!(Test-Path "$ACS_ENGINE_FILE")) {
    $downloadACSEngine = "y"
}
else {
    $acsengineversion = acs-engine version
    $acsengineversion = $acsengineversion -match "^Version: v[0-9.]+"
    $acsengineversion = "[$acsengineversion]"
    if ( !$acsengineversion.equals("[Version: $DESIRED_ACS_ENGINE_VERSION]")) {
        $downloadACSEngine = "y"
    }
}
if ($downloadACSEngine -eq "y") {
    $url = "https://github.com/Azure/acs-engine/releases/download/${DESIRED_ACS_ENGINE_VERSION}/acs-engine-${DESIRED_ACS_ENGINE_VERSION}-windows-amd64.zip"
    Write-Output "Downloading acs-engine.exe from $url to $ACS_ENGINE_FILE"
    Remove-Item -Path "$ACS_ENGINE_FILE"

    DownloadFile -url $url -targetFile "$AKS_LOCAL_FOLDER\acs-engine.zip"

    Expand-Archive -Path "$AKS_LOCAL_FOLDER\acs-engine.zip" -DestinationPath "$AKS_LOCAL_FOLDER" -Force
    Copy-Item -Path "$AKS_LOCAL_FOLDER\acs-engine-${DESIRED_ACS_ENGINE_VERSION}-windows-amd64\acs-engine.exe" -Destination $ACS_ENGINE_FILE
}
else {
    Write-Output "acs-engine.exe already exists at $ACS_ENGINE_FILE"    
}

Write-Output "ACS Engine version"
acs-engine version

$AKS_CLUSTER_NAME = "kubcluster"
# $AKS_CLUSTER_NAME = Read-Host "Cluster Name: (e.g., fabricnlpcluster)"

$AKS_PERS_STORAGE_ACCOUNT_NAME = $(CreateStorageIfNotExists -resourceGroup $AKS_PERS_RESOURCE_GROUP -deleteStorageAccountIfExists $config.storage_account.delete_if_exists).AKS_PERS_STORAGE_ACCOUNT_NAME

$AKS_VNET_NAME = $config.networking.vnet
$AKS_SUBNET_NAME = $config.networking.subnet
$AKS_SUBNET_RESOURCE_GROUP = $config.networking.subnet_resource_group

# see if the user wants to use a specific virtual network
$VnetInfo = GetVnetInfo -subscriptionId $AKS_SUBSCRIPTION_ID -subnetResourceGroup $AKS_SUBNET_RESOURCE_GROUP -vnetName $AKS_VNET_NAME -subnetName $AKS_SUBNET_NAME
$AKS_FIRST_STATIC_IP = $VnetInfo.AKS_FIRST_STATIC_IP
$AKS_SUBNET_CIDR = $VnetInfo.AKS_SUBNET_CIDR

CleanResourceGroup -resourceGroup ${AKS_PERS_RESOURCE_GROUP} -location $AKS_PERS_LOCATION -vnet $AKS_VNET_NAME `
    -subnet $AKS_SUBNET_NAME -subnetResourceGroup $AKS_SUBNET_RESOURCE_GROUP `
    -storageAccount $AKS_PERS_STORAGE_ACCOUNT_NAME

# Read-Host "continue?"

Write-Output "checking if Service Principal already exists"
$AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv

$myscope = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_PERS_RESOURCE_GROUP}"

# https://docs.microsoft.com/en-us/azure/active-directory/active-directory-passwords-policy
if ("$AKS_SERVICE_PRINCIPAL_CLIENTID") {
    Write-Host "Service Principal already exists with name: [$AKS_SERVICE_PRINCIPAL_NAME]"
    $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = ReadSecretPassword -secretname "serviceprincipal"
    if ([string]::IsNullOrWhiteSpace($AKS_SERVICE_PRINCIPAL_CLIENTSECRET)) {

        if($($config.service_principal.delete_if_exists)) {
            Write-Output "Deleting service principal:$AKS_SERVICE_PRINCIPAL_CLIENTID ..."
            az ad sp delete --id "$AKS_SERVICE_PRINCIPAL_CLIENTID" --verbose
            # https://github.com/Azure/azure-cli/issues/1332
            Write-Output "Sleeping to wait for Service Principal to propagate"
            Start-Sleep -Seconds 30;
    
            Write-Output "Creating Service Principal: [$AKS_SERVICE_PRINCIPAL_NAME]"
            $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Owner" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
            # the above command changes the color because it retries role assignment creation
            [Console]::ResetColor()
        }
        else {
        }
    }
    else {
        Write-Host "Found past servicePrincipal client secret: $AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
    }

    # https://github.com/Azure/azure-cli/issues/1332
    Write-Output "Sleeping to wait for Service Principal to propagate"
    Start-Sleep -Seconds 30;
    $AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv
    Write-Output "created $AKS_SERVICE_PRINCIPAL_NAME clientId=$AKS_SERVICE_PRINCIPAL_CLIENTID clientsecret=$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
}
else {
    Write-Output "Creating Service Principal: [$AKS_SERVICE_PRINCIPAL_NAME]"
    $AKS_SERVICE_PRINCIPAL_CLIENTSECRET = az ad sp create-for-rbac --role="Contributor" --scopes="$myscope" --name ${AKS_SERVICE_PRINCIPAL_NAME} --query "password" --output tsv
    # https://github.com/Azure/azure-cli/issues/1332
    Write-Output "Sleeping to wait for Service Principal to propagate"
    Start-Sleep -Seconds 30;
    [Console]::ResetColor()

    $AKS_SERVICE_PRINCIPAL_CLIENTID = az ad sp list --display-name ${AKS_SERVICE_PRINCIPAL_NAME} --query "[].appId" --output tsv
    Write-Output "created $AKS_SERVICE_PRINCIPAL_NAME clientId=$AKS_SERVICE_PRINCIPAL_CLIENTID clientsecret=$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
}

if ("$AKS_SUBNET_RESOURCE_GROUP") {
    Write-Output "Giving service principal access to vnet resource group: [${AKS_SUBNET_RESOURCE_GROUP}]"
    $subnetscope = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}"
    az role assignment create --assignee $AKS_SERVICE_PRINCIPAL_CLIENTID --role "contributor" --scope "$subnetscope"
}

Write-Output "Create Azure Container Service cluster"

$mysubnetid = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${AKS_VNET_NAME}/subnets/${AKS_SUBNET_NAME}"

$dnsNamePrefix = "$AKS_PERS_RESOURCE_GROUP"

# az acs create --orchestrator-type kubernetes --resource-group $AKS_PERS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --generate-ssh-keys --agent-count=3 --agent-vm-size Standard_B2ms
#az acs create --orchestrator-type kubernetes --resource-group fabricnlpcluster --name cluster1 --service-principal="$AKS_SERVICE_PRINCIPAL_CLIENTID" --client-secret="$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"  --generate-ssh-keys --agent-count=3 --agent-vm-size Standard_D2 --master-vnet-subnet-id="$mysubnetid" --agent-vnet-subnet-id="$mysubnetid"

# choose the right template based on user choice
$templateFile = "acs.template.json"
if (!"$AKS_VNET_NAME") {
    $templateFile = "acs.template.nosubnet.json"    
}
elseif ($AKS_SUPPORT_WINDOWS_CONTAINERS) {
    # https://github.com/Azure/acs-engine/issues/1767
    $templateFile = "acs.template.linuxwindows.json"    
}
elseif ($AKS_USE_AZURE_NETWORKING) {
    $templateFile = "acs.template.azurenetwork.json"             
}

Write-Output "Using template: $GITHUB_URL/azure/$templateFile"

$AKS_LOCAL_TEMP_FOLDER = "$AKS_LOCAL_FOLDER\$AKS_PERS_RESOURCE_GROUP\temp"
if (!(Test-Path -Path "$AKS_LOCAL_TEMP_FOLDER")) {
    New-Item -ItemType directory -Path "$AKS_LOCAL_TEMP_FOLDER"
}

# sometimes powershell starts in a strange folder where the current user doesn't have permissions
# so CD into the temp folder to avoid errors
Set-Location -Path $AKS_LOCAL_TEMP_FOLDER

$output = "$AKS_LOCAL_TEMP_FOLDER\acs.json"
Write-Output "Downloading parameters file from github to $output"
if (Test-Path $output) {
    Remove-Item $output
}

# download the template file from github
if ($GITHUB_URL.StartsWith("http")) { 
    Write-Output "Downloading file: $GITHUB_URL/azure/$templateFile"
    Invoke-WebRequest -Uri "$GITHUB_URL/azure/$templateFile" -OutFile $output -ContentType "text/plain; charset=utf-8"
}
else {
    Copy-Item -Path "$GITHUB_URL/azure/$templateFile" -Destination "$output"
}

# subnet CIDR to mask
# https://doc.m0n0.ch/quickstartpc/intro-CIDR.html
$WINDOWS_PASSWORD = "replacepassword1234$"
Write-Output "replacing values in the acs.json file"
Write-Output "AKS_SSH_KEY: $AKS_SSH_KEY"
Write-Output "AKS_SERVICE_PRINCIPAL_CLIENTID: $AKS_SERVICE_PRINCIPAL_CLIENTID"
Write-Output "AKS_SERVICE_PRINCIPAL_CLIENTSECRET: $AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
Write-Output "SUBNET: ${mysubnetid}"
Write-Output "DNS NAME: ${dnsNamePrefix}"
Write-Output "FIRST STATIC IP: $AKS_FIRST_STATIC_IP"
Write-Output "WINDOWS PASSWORD: $WINDOWS_PASSWORD"
Write-Output "AKS_SUBNET_CIDR: $AKS_SUBNET_CIDR"
$MyFile = (Get-Content $output) | 
    Foreach-Object {$_ -replace 'REPLACE-SSH-KEY', "${AKS_SSH_KEY}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-CLIENTID', "${AKS_SERVICE_PRINCIPAL_CLIENTID}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-CLIENTSECRET', "${AKS_SERVICE_PRINCIPAL_CLIENTSECRET}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-SUBNET', "${mysubnetid}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-DNS-NAME-PREFIX', "${dnsNamePrefix}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-FIRST-STATIC-IP', "${AKS_FIRST_STATIC_IP}"}  | 
    Foreach-Object {$_ -replace 'REPLACE-WINDOWS-PASSWORD', "${WINDOWS_PASSWORD}"}  | 
    Foreach-Object {$_ -replace 'REPLACE_VNET_CIDR', "${AKS_SUBNET_CIDR}"}  

    

# have to do it this way instead of Outfile so we can get a UTF-8 file without BOM
# from https://stackoverflow.com/questions/5596982/using-powershell-to-write-a-file-in-utf-8-without-the-bom
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
[System.IO.File]::WriteAllLines($output, $MyFile, $Utf8NoBomEncoding)

$acsoutputfolder = "$AKS_LOCAL_TEMP_FOLDER\_output\$dnsNamePrefix"
if (!(Test-Path -Path "$acsoutputfolder")) {
    New-Item -ItemType directory -Path "$acsoutputfolder"
}

Write-Output "Deleting everything in the output folder"
Remove-Item -Path $acsoutputfolder -Recurse -Force

Write-Output "Generating ACS engine template"

# acs-engine deploy --subscription-id "$AKS_SUBSCRIPTION_ID" `
#                     --dns-prefix $dnsNamePrefix --location $AKS_PERS_LOCATION `
#                     --resource-group $AKS_PERS_RESOURCE_GROUP `
#                     --api-model "$output" `
#                     --output-directory "$acsoutputfolder"

acs-engine generate $output --output-directory $acsoutputfolder

if ($AKS_SUPPORT_WINDOWS_CONTAINERS) {

    if ("$AKS_VNET_NAME") {
        Write-Output "Adding subnet to azuredeploy.json to work around acs-engine bug"
        $outputdeployfile = "$acsoutputfolder\azuredeploy.json"
        # https://github.com/Azure/acs-engine/issues/1767
        # "subnet": "${mysubnetid}"
        # replace     "vnetSubnetID": "[parameters('masterVnetSubnetID')]"
        # "subnet": "[parameters('masterVnetSubnetID')]"

        #there is a bug in acs-engine: https://github.com/Azure/acs-engine/issues/1767
        $mydeployjson = Get-Content -Raw -Path $outputdeployfile | ConvertFrom-Json
        $mydeployjson.variables | Add-Member -Type NoteProperty -Name 'subnet' -Value "[parameters('masterVnetSubnetID')]"
        $outjson = ConvertTo-Json -InputObject $mydeployjson -Depth 10
        Set-Content -Path $outputdeployfile -Value $outjson  
    }
}

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

Write-Output "Validating deployment"
az group deployment validate `
    --template-file "$acsoutputfolder\azuredeploy.json" `
    --resource-group $AKS_PERS_RESOURCE_GROUP `
    --parameters "$acsoutputfolder\azuredeploy.parameters.json"

Write-Output "Starting deployment..."

az group deployment create `
    --template-file "$acsoutputfolder\azuredeploy.json" `
    --resource-group $AKS_PERS_RESOURCE_GROUP -n $AKS_CLUSTER_NAME `
    --parameters "$acsoutputfolder\azuredeploy.parameters.json" `
    --verbose	

# Write-Output "Saved to $acsoutputfolder\azuredeploy.json"

# if joining a vnet, and not using azure networking then we have to manually set the route-table
if ("$AKS_VNET_NAME") {
    if (!$AKS_USE_AZURE_NETWORKING) {
        Write-Output "Attaching route table"
        # https://github.com/Azure/acs-engine/blob/master/examples/vnet/k8s-vnet-postdeploy.sh
        $rt = az network route-table list -g "${AKS_PERS_RESOURCE_GROUP}" --query "[?name != 'temproutetable'].id" -o tsv
        $nsg = az network nsg list --resource-group ${AKS_PERS_RESOURCE_GROUP} --query "[?name != 'tempnsg'].id" -o tsv

        Write-Output "new route: $rt"
        Write-Output "new nsg: $nsg"

        az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --route-table "$rt" --network-security-group "$nsg"
        
        Write-Output "Sleeping to let subnet be updated"
        Start-Sleep -Seconds 30

        az network route-table delete --name temproutetable --resource-group $AKS_PERS_RESOURCE_GROUP
        az network nsg delete --name tempnsg --resource-group $AKS_PERS_RESOURCE_GROUP
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

# store kube config in local folder
if (!(Test-Path -Path "$env:userprofile\.kube")) {
    Write-Output "$env:userprofile\.kube does not exist.  Creating it..."
    New-Item -ItemType directory -Path "$env:userprofile\.kube"
}
if (!(Test-Path -Path "$AKS_LOCAL_TEMP_FOLDER\.kube")) {
    New-Item -ItemType directory -Path "$AKS_LOCAL_TEMP_FOLDER\.kube"
}

$privateIpOfMasterVM = $(GetPrivateIPofMasterVM -resourceGroup $AKS_PERS_RESOURCE_GROUP).PrivateIP
$publicNameOfMasterVM = $(GetPublicNameofMasterVM -resourceGroup $AKS_PERS_RESOURCE_GROUP).Name
$kubeconfigjsonfile = "$acsoutputfolder\kubeconfig\kubeconfig.$AKS_PERS_LOCATION.json"

if($IS_CAFE_ENVIRONMENT){
    Write-Host "Replacing master vm name, [$publicNameOfMasterVM], with private ip, [$privateIpOfMasterVM], in kube config file"
    (Get-Content "$kubeconfigjsonfile").replace("$publicNameOfMasterVM", "$privateIpOfMasterVM") | Set-Content "$kubeconfigjsonfile"    
}

Copy-Item -Path "$kubeconfigjsonfile" -Destination "$env:userprofile\.kube\config"

Copy-Item -Path "$kubeconfigjsonfile" -Destination "$AKS_LOCAL_TEMP_FOLDER\.kube\config"

# If ((Get-Content "$($env:windir)\system32\Drivers\etc\hosts" ) -notcontains "127.0.0.1 hostname1")  
#  {ac -Encoding UTF8  "$($env:windir)\system32\Drivers\etc\hosts" "127.0.0.1 hostname1" }

$MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
Write-Output "You can connect to master VM in Git Bash for debugging using:"
Write-Output "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${MASTER_VM_NAME}"

Write-Output "Check nodes via kubectl"
# set the environment variable so kubectl gets the new config
$env:KUBECONFIG = "${HOME}\.kube\config"
kubectl get nodes -o=name

# wait until the nodes are up
$nodeCount = 0

while ($nodeCount -lt 3) {
    $lines = kubectl get nodes -o=name | Measure-Object -Line
    $nodeCount = $lines.Lines
    Start-Sleep -s 10
}

# create storage account

Write-Output "Get storage account key"
$STORAGE_KEY = az storage account keys list --resource-group $AKS_PERS_RESOURCE_GROUP --account-name $AKS_PERS_STORAGE_ACCOUNT_NAME --query "[0].value" --output tsv

# Write-Output "Storagekey: [$STORAGE_KEY]"

Write-Output "Creating kubernetes secret for Azure Storage Account: azure-secret"
kubectl create secret generic azure-secret --from-literal=resourcegroup="${AKS_PERS_RESOURCE_GROUP}" --from-literal=azurestorageaccountname="${AKS_PERS_STORAGE_ACCOUNT_NAME}" --from-literal=azurestorageaccountkey="${STORAGE_KEY}"
Write-Output "Creating kubernetes secret for customerid: customerid"
kubectl create secret generic customerid --from-literal=value=$customerid
Write-Output "Creating kubernetes secret for vnet: azure-vnet"
kubectl create secret generic azure-vnet --from-literal=vnet="${AKS_VNET_NAME}" --from-literal=subnet="${AKS_SUBNET_NAME}" --from-literal=subnetResourceGroup="${AKS_SUBNET_RESOURCE_GROUP}"
Write-Output "Creating kubernetes secret for service principal"
kubectl create secret generic serviceprincipal --from-literal=clientid="$AKS_SERVICE_PRINCIPAL_CLIENTID" --from-literal=password="$AKS_SERVICE_PRINCIPAL_CLIENTSECRET"
if (![string]::IsNullOrEmpty($WINDOWS_PASSWORD)) {
    Write-Output "Creating kubernetes secret for windows VM"
    kubectl create secret generic windowspassword --from-literal=password="$WINDOWS_PASSWORD"
}

kubectl get "deployments,pods,services,ingress,secrets" --namespace=kube-system -o wide

# kubectl patch deployment kube-dns-v20 -n kube-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","image":"172.20.34.206:5000/myapp:img:3.0"}]}}}}'
# kubectl patch deployment kube-dns-v20 -n kube-system -p '{"spec":{"template":{"spec":{"restartPolicy":"Never"}}}}'

# Write-Output "Restarting DNS Pods (sometimes they get in a CrashLoopBackoff loop)"
# $failedItems = kubectl get pods -l k8s-app=kube-dns -n kube-system -o jsonpath='{range.items[*]}{.metadata.name}{\"\n\"}{end}'
# ForEach ($line in $failedItems) {
#     Write-Host "Deleting pod $line"
#     kubectl delete pod $line -n kube-system
# } 

SetHostFileInVms -resourceGroup $AKS_PERS_RESOURCE_GROUP
SetupCronTab -resourceGroup $AKS_PERS_RESOURCE_GROUP

Write-Host "Removing extra stuff that acs-engine creates"
# k8s-master-lb-24203516
# k8s-master-ip-prod-kub-sjtn-rg-24203516

# /subscriptions/f8a42a3a-8b22-4be4-8413-0b6911c77242/resourceGroups/Prod-Kub-AHMN-RG/providers/Microsoft.Network/networkInterfaces/k8s-master-37819884-nic-0

# command to update hosts
# grep -v " k8s-master-37819884-0" /etc/hosts | grep -v "k8s-linuxagent-37819884-0" - | grep -v "k8s-linuxagent-37819884-1" - | grep -v "prod-kub-ahmn-rg.westus.cloudapp.azure.com" - | tee /etc/hosts
# | ( cat - && echo "foo" && echo "bar")
# | tee /etc/hosts

# copy the file into /etc/cron.hourly/
# chmod +x ./restartkubedns.sh
# sudo mv ./restartkubedns.sh /etc/cron.hourly/
# grep CRON /var/log/syslog
# * * * * * /etc/cron.hourly/restartkubedns.sh >>/tmp/restartkubedns.log
# https://stackoverflow.com/questions/878600/how-to-create-a-cron-job-using-bash-automatically-without-the-interactive-editor
# crontab -l | { cat; echo "*/10 * * * * /etc/cron.hourly/restartkubedns.sh >>/tmp/restartkubedns.log"; } | crontab -
# az vm extension set --resource-group Prod-Kub-AHMN-RG --vm-name k8s-master-37819884-0 --name customScript --publisher Microsoft.Azure.Extensions --protected-settings "{'commandToExecute': 'whoami;touch /tmp/me.txt'}"
# az vm run-command invoke -g Prod-Kub-AHMN-RG -n k8s-master-37819884-0 --command-id RunShellScript --scripts "whomai"
# az vm run-command invoke -g Prod-Kub-AHMN-RG -n k8s-master-37819884-0 --command-id RunShellScript --scripts "crontab -l | { cat; echo '*/10 * * * * /etc/cron.hourly/restartkubedns.sh >>/tmp/restartkubedns.log 2>&1'; } | crontab -"

Write-Output "Run the following to see status of the cluster"
Write-Output "kubectl get deployments,pods,services,ingress,secrets --namespace=kube-system -o wide"
