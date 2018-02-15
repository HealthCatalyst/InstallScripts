# This file contains common functions for Azure
# 
$versioncommon = "2018.02.14.01"

Write-Host "Including common.ps1 version $versioncommon"
function global:GetCommonVersion() {
    return $versioncommon
}

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

function global:CreateShareInStorageAccount($storageAccountName, $resourceGroup, $sharename, $deleteExisting) { 
    $AZURE_STORAGE_CONNECTION_STRING = az storage account show-connection-string -n $storageAccountName -g $resourceGroup -o tsv
    
    if ($deleteExisting) {
        if ($(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv)) {
            Write-Output "Deleting the file share: $sharename"
            az storage share delete -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING
        
            
            Write-Output "Waiting for completion of delete for the file share: $sharename"        
            Do {
                Start-Sleep -Seconds 5 
                $SHARE_EXISTS = $(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv)
                Write-Host "."
            }
            while ($SHARE_EXISTS -ne "false")
        }
    }

    if ($(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv) -eq "false") {
        Write-Output "Creating the file share: $sharename"        
        az storage share create -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --quota 512       
    }
    else {
        Write-Output "File share already exists: $sharename"         
    }
}
function global:CreateShare($resourceGroup, $sharename, $deleteExisting) {
    $storageAccountName = ReadSecretValue -secretname azure-secret -valueName azurestorageaccountname 
    
    CreateShareInStorageAccount -storageAccountName $storageAccountName -resourceGroup $resourceGroup -sharename $sharename -deleteExisting $deleteExisting
}


# helper functions for subnet match
# from https://gallery.technet.microsoft.com/scriptcenter/Start-and-End-IP-addresses-bcccc3a9
function global:Get-FirstIP {
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
 
    # https://github.com/Azure/acs-engine/blob/master/docs/kubernetes/features.md#feat-custom-vnet
    $startaddr = $startaddr + 239 # skip the first few since they are reserved
    INT64-toIP -int $startaddr
}

function global:SetupCronTab($resourceGroup) {
    $virtualmachines = az vm list -g $resourceGroup --query "[?storageProfile.osDisk.osType != 'Windows'].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        if ($vm -match "master" ) {
            $cmd = "crontab -e; mkdir -p /opt/healthcatalyst; curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/restartkubedns.txt -o /opt/healthcatalyst/restartkubedns.sh; crontab -l | grep -v 'restartkubedns.sh' - | { cat; echo '*/10 * * * * /opt/healthcatalyst/restartkubedns.sh >> /tmp/restartkubedns.log 2>&1 \n'; } | crontab -"
            az vm run-command invoke -g $resourceGroup -n $vm --command-id RunShellScript --scripts "$cmd"
        }
    }
}

function global:UpdateOSInVMs($resourceGroup) {
    $virtualmachines = az vm list -g $resourceGroup --query "[?storageProfile.osDisk.osType != 'Windows'].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        Write-Output "Updating OS in vm: $vm"
        $cmd = "apt-get update && apt-get -y upgrade"
        az vm run-command invoke -g $resourceGroup -n $vm --command-id RunShellScript --scripts "$cmd"
    }
}


function global:RestartVMsInResourceGroup( $resourceGroup) {
    # az vm run-command invoke -g Prod-Kub-AHMN-RG -n k8s-master-37819884-0 --command-id RunShellScript --scripts "apt-get update && sudo apt-get upgrade"
    Write-Host "Restarting VMs in resource group: ${resourceGroup}: $(az vm list -g $resourceGroup --query "[].name" -o tsv)"
    az vm restart --ids $(az vm list -g $resourceGroup --query "[].id" -o tsv)

    Write-Output "Waiting for VMs to restart: $(az vm list -g $resourceGroup --query "[].name" -o tsv)"
    $virtualmachines = az vm list -g $resourceGroup --query "[].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        
        Write-Output "Waiting on $vm"
        Do { 
            Start-Sleep -Seconds 1
            $state = az vm show -g $resourceGroup -n $vm -d --query "powerState"; 
            Write-Output "Status of ${vm}: ${state}"
        }
        while (!($state = "VM running"))      
    }
}

function global:SetHostFileInVms( $resourceGroup) {
    $AKS_PERS_LOCATION = az group show --name $resourceGroup --query "location" -o tsv

    $MASTER_VM_NAME = "${resourceGroup}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
    $MASTER_VM_NAME = $MASTER_VM_NAME.ToLower()

    Write-Host "Creating hosts entries"
    $fullCmdToUpdateHostsFiles = ""
    $cmdToRemovePreviousHostEntries = ""
    $cmdToAddNewHostEntries = ""
    $virtualmachines = az vm list -g $resourceGroup --query "[?storageProfile.osDisk.osType != 'Windows'].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        $firstprivateip = az vm list-ip-addresses -g $resourceGroup -n $vm --query "[].virtualMachine.network.privateIpAddresses[0]" -o tsv
        # $privateiplist= az vm show -g $AKS_PERS_RESOURCE_GROUP -n $vm -d --query privateIps -otsv
        Write-Output "$firstprivateip $vm"

        $cmdToRemovePreviousHostEntries = $cmdToRemovePreviousHostEntries + "grep -v '${vm}' - | "
        $cmdToAddNewHostEntries = $cmdToAddNewHostEntries + " && echo '$firstprivateip $vm'"
        if ($vm -match "master" ) {
            Write-Output "$firstprivateip $MASTER_VM_NAME"
            $cmdToRemovePreviousHostEntries = $cmdToRemovePreviousHostEntries + "grep -v '${MASTER_VM_NAME}' - | "
            $cmdToAddNewHostEntries = $cmdToAddNewHostEntries + " && echo '$firstprivateip ${MASTER_VM_NAME}'"
        }
    }

    $fullCmdToUpdateHostsFiles = "cat /etc/hosts | $cmdToRemovePreviousHostEntries (cat $cmdToAddNewHostEntries ) | tee /etc/hosts; cat /etc/hosts"

    Write-Host "Command to send to VM"
    Write-Host "$fullCmdToUpdateHostsFiles"

    ForEach ($vm in $virtualmachines) {
        Write-Output "Sending command to $vm"
        az vm run-command invoke -g $resourceGroup -n $vm --command-id RunShellScript --scripts "$fullCmdToUpdateHostsFiles"
    }
}


function global:CleanResourceGroup($resourceGroup, $location, $vnet, $subnet, $subnetResourceGroup, $storageAccount) {
    Write-Output "checking if resource group already exists"
    $resourceGroupExists = az group exists --name ${resourceGroup}
    if ($resourceGroupExists -eq "true") {

        if ($(az vm list -g $resourceGroup --query "[].id" -o tsv).length -ne 0) {
            Write-Host "The resource group [${resourceGroup}] already exists with the following VMs"
            az resource list --resource-group "${resourceGroup}" --resource-type "Microsoft.Compute/virtualMachines" --query "[].id"
        
            Do { $confirmation = Read-Host "Would you like to continue (all above resources will be deleted)? (y/n)"}
            while ([string]::IsNullOrWhiteSpace($confirmation)) 

            if ($confirmation -eq 'n') {
                Read-Host "Hit ENTER to exit"
                exit 0
            }    
        }
        else {
            Write-Host "The resource group [${resourceGroup}] already exists but has no VMs"
        }

        if ("$vnet") {
            # Write-Output "removing route table"
            # az network vnet subnet update -n "${subnet}" -g "${subnetResourceGroup}" --vnet-name "${vnet}" --route-table ""
        }
        Write-Output "cleaning out the existing group: [$resourceGroup]"
        #az group delete --name $resourceGroup --verbose

        if ($(az vm list -g $resourceGroup --query "[].id" -o tsv).length -ne 0) {
            Write-Output "delete the VMs first"
            az vm delete --ids $(az vm list -g $resourceGroup --query "[].id" -o tsv) --verbose --yes
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkInterfaces" --query "[].id" -o tsv ).length -ne 0) {
            Write-Output "delete the nics"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkInterfaces" --query "[].id" -o tsv )  --verbose
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Compute/disks" --query "[].id" -o tsv ).length -ne 0) {
            Write-Output "delete the disks"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Compute/disks" --query "[].id" -o tsv )
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Compute/availabilitySets" --query "[].id" -o tsv ).length -ne 0) {
            Write-Output "delete the availabilitysets"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Compute/availabilitySets" --query "[].id" -o tsv )
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/loadBalancers" --query "[].id" -o tsv ).length -ne 0) {
            Write-Output "delete the load balancers"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/loadBalancers" --query "[].id" -o tsv )
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/applicationGateways" --query "[].id" -o tsv ).length -ne 0) {
            Write-Output "delete the application gateways"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/applicationGateways" --query "[].id" -o tsv )
        }
    
        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("$storageAccount")}).length -ne 0) {
            Write-Output "delete the storage accounts EXCEPT storage account we created in the past"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("${storageAccount}")} )
            # az resource list --resource-group fabricnlp3 --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | ForEach-Object { if (!"$_".EndsWith("${resourceGroup}storage")) {  az resource delete --ids "$_" }}    
        }
        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/publicIPAddresses" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("PublicIP")}).length -ne 0) {
            Write-Output "delete the public IPs EXCEPT Ingress IP we created in the past"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/publicIPAddresses" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("PublicIP")} )
        }
    
        if (("$vnet") -and ("$AKS_USE_AZURE_NETWORKING" -eq "n")) {
            Write-Output "Switching the subnet to a temp route table and tempnsg so we can delete the old route table and nsg"

            $routeid = $(az network route-table show --name temproutetable --resource-group $resourceGroup --query "id" -o tsv)
            if ([string]::IsNullOrWhiteSpace($routeid)) {
                Write-Output "create temproutetable"
                $routeid = az network route-table create --name temproutetable --resource-group $resourceGroup --query "id" -o tsv   
            }
            $routeid = $(az network route-table show --name temproutetable --resource-group $resourceGroup --query "id" -o tsv)
            Write-Output "temproutetable: $routeid"

            $nsg = $(az network nsg show --name tempnsg --resource-group $resourceGroup --query "id" -o tsv)
            if ([string]::IsNullOrWhiteSpace($nsg)) {
                Write-Output "create tempnsg"
                $nsg = az network nsg create --name tempnsg --resource-group $resourceGroup --query "id" -o tsv   
            }
            $nsg = $(az network nsg show --name tempnsg --resource-group $resourceGroup --query "id" -o tsv)
            Write-Output "tempnsg: $nsg"
        
            Write-Output "Updating the subnet"
            az network vnet subnet update -n "${subnet}" -g "${subnetResourceGroup}" --vnet-name "${vnet}" --route-table "$routeid" --network-security-group "$nsg"


            if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/routeTables" --query "[?name != 'temproutetable'].id" -o tsv ).length -ne 0) {
                Write-Output "delete the routes EXCEPT the temproutetable we just created"
                az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/routeTables" --query "[?name != 'temproutetable'].id" -o tsv)
            }
            if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkSecurityGroups" --query "[?name != 'tempnsg'].id" -o tsv).length -ne 0) {
                Write-Output "delete the nsgs EXCEPT the tempnsg we just created"
                az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkSecurityGroups" --query "[?name != 'tempnsg'].id" -o tsv)
            }
        }
        else {
            if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/routeTables" --query "[].id" -o tsv).length -ne 0) {
                Write-Output "delete the routes EXCEPT the temproutetable we just created"
                az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/routeTables" --query "[].id" -o tsv)
            }
            $networkSecurityGroup = "$($resourceGroup.ToLower())-nsg"
            if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkSecurityGroups" --query "[?name != '${$networkSecurityGroup}'].id" -o tsv ).length -ne 0) {
                Write-Output "delete the network security groups"
                az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkSecurityGroups" --query "[?name != '${$networkSecurityGroup}'].id" -o tsv )
            }
    
        }
        # note: do not delete the Microsoft.Network/publicIPAddresses otherwise the loadBalancer will get a new IP
    }
    else {
        Write-Output "Create the Resource Group"
        az group create --name $resourceGroup --location $location --verbose
    }

}

function global:CreateStorageIfNotExists($resourceGroup) {
    $location = az group show --name $resourceGroup --query "location" -o tsv

    $storageAccountName = Read-Host "Storage Account Name (leave empty for default)"
    if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
        $storageAccountName = "${resourceGroup}storage"
        # remove non-alphanumeric characters and use lowercase since azure doesn't allow those in a storage account
        $storageAccountName = $storageAccountName -replace '[^a-zA-Z0-9]', ''
        $storageAccountName = $storageAccountName.ToLower()
        Write-Output "Using storage account: [$storageAccountName]"
    }
    Write-Output "Checking to see if storage account exists"
    $storageAccountCanBeCreated = az storage account check-name --name $storageAccountName --query "nameAvailable" --output tsv
    
    if ($storageAccountCanBeCreated -ne "True" ) {
        az storage account check-name --name $storageAccountName   
        
        Do { $confirmation = Read-Host "Storage account, [$storageAccountName], already exists.  Delete it?  (WARNING: deletes data) (y/n)"}
        while ([string]::IsNullOrWhiteSpace($confirmation)) 
    
        if ($confirmation -eq 'y') {
            az storage account delete -n $storageAccountName -g $resourceGroup
            Write-Output "Creating storage account: [${storageAccountName}]"
            # https://docs.microsoft.com/en-us/azure/storage/common/storage-quickstart-create-account?tabs=azure-cli
            az storage account create -n $storageAccountName -g $resourceGroup -l $location --kind StorageV2 --sku Standard_LRS                       
        }    
    }
    else {
        Write-Output "Creating storage account: [${storageAccountName}]"
        az storage account create -n $storageAccountName -g $resourceGroup -l $location --kind StorageV2 --sku Standard_LRS            
    }    

    return $storageAccountName
}

function global:GetVnet($subscriptionId) {
    #Create an hashtable variable 
    [hashtable]$Return = @{} 

    Do { $confirmation = Read-Host "Would you like to connect to an existing virtual network? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($confirmation))
    
    if ($confirmation -eq 'y') {
        Write-Output "Finding existing vnets..."
        # az network vnet list --query "[].[name,resourceGroup ]" -o tsv    
    
        $vnets = az network vnet list --query "[].[name]" -o tsv
    
        Do { 
            Write-Output "------  Existing vnets -------"
            for ($i = 1; $i -le $vnets.count; $i++) {
                Write-Host "$i. $($vnets[$i-1])"
            }    
            Write-Output "------  End vnets -------"
    
            $index = Read-Host "Enter number of vnet to use (1 - $($vnets.count))"
            $vnetName = $($vnets[$index - 1])
        }
        while ([string]::IsNullOrWhiteSpace($vnetName))    
    
        $subnetResourceGroup = az network vnet list --query "[?name == '$vnetName'].resourceGroup" -o tsv
        Write-Output "Using subnet resource group: [$subnetResourceGroup]"
    
        Write-Output "Finding existing subnets in $vnetName ..."
        $subnets = az network vnet subnet list --resource-group $subnetResourceGroup --vnet-name $vnetName --query "[].name" -o tsv
            
        if ($subnets.count -eq 1) {
            Write-Output "There is only one subnet called $subnets so choosing that"
            $subnetName = $subnets
        }
        else {
            Do { 
                Write-Output "------  Subnets in $vnetName -------"
                for ($i = 1; $i -le $subnets.count; $i++) {
                    Write-Host "$i. $($subnets[$i-1])"
                }    
                Write-Output "------  End Subnets -------"
        
                Write-Host "NOTE: Each customer should have their own subnet.  Do not put multiple customers in the same subnet"
                $index = Read-Host "Enter number of subnet to use (1 - $($subnets.count))"
                $subnetName = $($subnets[$index - 1])
            }
            while ([string]::IsNullOrWhiteSpace($subnetName)) 
        }
    
        # verify the subnet exists
        $mysubnetid = "/subscriptions/${subscriptionId}/resourceGroups/${subnetResourceGroup}/providers/Microsoft.Network/virtualNetworks/${vnet}/subnets/${subnetName}"
    
        $subnetexists = az resource show --ids $mysubnetid --query "id" -o tsv
        if (!"$subnetexists") {
            Write-Host "The subnet was not found: $mysubnetid"
            Read-Host "Hit ENTER to exit"
            exit 0        
        }
        else {
            Write-Output "Found subnet: [$mysubnetid]"
        }
        
        Write-Output "Looking up CIDR for Subnet: [${subnetName}]"
        $subnetCidr = az network vnet subnet show --name ${subnetName} --resource-group ${subnetResourceGroup} --vnet-name ${vnet} --query "addressPrefix" --output tsv
    
        Write-Output "Subnet CIDR=[$subnetCidr]"
        # suggest and ask for the first static IP to use
        $firstStaticIP = ""
        $suggestedFirstStaticIP = Get-FirstIP -ip ${subnetCidr}
    
        $firstStaticIP = Read-Host "First static IP: (default: $suggestedFirstStaticIP )"
        
        if ([string]::IsNullOrWhiteSpace($firstStaticIP)) {
            $firstStaticIP = "$suggestedFirstStaticIP"
        }
    
        Write-Output "First static IP=[${firstStaticIP}]"
    }
    else {
        # create a vnet
        # create a subnet
    
        # az network vnet create -g MyResourceGroup -n MyVnet --address-prefix 10.0.0.0/16 --subnet-name MySubnet --subnet-prefix 10.0.0.0/24    
    }
    
        
    #Assign all return values in to hashtable
    $Return.AKS_VNET_NAME = $vnetName
    $Return.AKS_SUBNET_NAME = $subnetName
    $Return.AKS_SUBNET_RESOURCE_GROUP = $subnetResourceGroup
    $Return.AKS_FIRST_STATIC_IP = $firstStaticIP
    $Return.AKS_SUBNET_ID = $mysubnetid

    #Return the hashtable
    Return $Return     
}

function global:DownloadAzCliIfNeeded() {
    # install az cli from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest
    $desiredAzClVersion = "2.0.26"
    $downloadazcli = $False
    if (!(Test-CommandExists az)) {
        $downloadazcli = $True
    }
    else {
        $azcurrentversion = az -v | Select-String "azure-cli" | Select-Object -exp line
        # we should get: azure-cli (2.0.22)
        $azversionMatches = $($azcurrentversion -match "$desiredAzClVersion")
        if (!$azversionMatches) {
            Write-Output "az version $azcurrentversion is not the same as desired version: $desiredAzClVersion"
            $downloadazcli = $True
        }
    }

    if ($downloadazcli) {
        $azCliFile = ([System.IO.Path]::GetTempPath() + ("az-cli-latest.msi"))
        $url = "https://azurecliprod.blob.core.windows.net/msi/azure-cli-latest.msi"
        Write-Output "Downloading az-cli-latest.msi from url $url to $azCliFile"
        If (Test-Path $azCliFile) {
            Remove-Item $azCliFile
        }
        (New-Object System.Net.WebClient).DownloadFile($url, $azCliFile)
        # https://kevinmarquette.github.io/2016-10-21-powershell-installing-msi-files/
        Write-Output "Running MSI to install az"
        $azCliInstallLog = ([System.IO.Path]::GetTempPath() + ('az-cli-latest.log'))
        # msiexec flags: https://msdn.microsoft.com/en-us/library/windows/desktop/aa367988(v=vs.85).aspx
        Start-Process -Verb runAs msiexec.exe -Wait -ArgumentList "/i $azCliFile /qn /L*e $azCliInstallLog"
        Write-Output "Finished installing az-cli-latest.msi"
    }
    
}

function global:CreateSSHKey($resourceGroup, $localFolder) {
    #Create an hashtable variable 
    [hashtable]$Return = @{} 

    $folderForSSHKey = "$localFolder\ssh\$resourceGroup"

    if (!(Test-Path -Path "$folderForSSHKey")) {
        Write-Output "$folderForSSHKey does not exist.  Creating it..."
        New-Item -ItemType directory -Path "$folderForSSHKey"
    }
    
    # check if SSH key is present.  If not, generate it
    $privateKeyFile = "$folderForSSHKey\id_rsa"
    $privateKeyFileUnixPath = "/" + (($privateKeyFile -replace "\\", "/") -replace ":", "").ToLower().Trim("/")    
    
    if (!(Test-Path "$privateKeyFile")) {
        Write-Output "SSH key does not exist in $privateKeyFile."
        Write-Output "Please open Git Bash and run:"
        Write-Output "ssh-keygen -t rsa -b 2048 -q -N '' -C azureuser@linuxvm -f $privateKeyFileUnixPath"
        Read-Host "Hit ENTER after you're done"
    }
    else {
        Write-Output "SSH key already exists at $privateKeyFile so using it"
    }
    
    $publicKeyFile = "$folderForSSHKey\id_rsa.pub"
    $sshKey = Get-Content "$publicKeyFile" -First 1
    Write-Output "SSH Public Key=$sshKey"

    
    $Return.AKS_SSH_KEY = $sshKey
    $Return.SSH_PUBLIC_KEY_FILE = $publicKeyFile

    #Return the hashtable
    Return $Return     
        
}

function global:CheckIfUserLogged() {
    write-output "Checking if you're already logged in..."

    # to print out the result to screen also use: <command> | Tee-Object -Variable cmdOutput
    $loggedInUser = az account show --query "user.name"  --output tsv
    
    # get azure login and subscription
    Write-Output "user: $loggedInUser"
    
    if ( "$loggedInUser" ) {
        $subscriptionName = az account show --query "name"  --output tsv
        Write-Output "You are currently logged in as [$loggedInUser] into subscription [$subscriptionName]"
        
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
    
    $subscriptionId = az account show --query "id" --output tsv

    Return $subscriptionId
}

function global:GetResourceGroupAndLocation($defaultResourceGroup) {
    #Create an hashtable variable 
    [hashtable]$Return = @{} 

    Do { 
        $resourceGroup = Read-Host "Resource Group (leave empty for $defaultResourceGroup)"
        if ([string]::IsNullOrWhiteSpace($resourceGroup)) {
            $resourceGroup = $defaultResourceGroup
        }
    }
    while ([string]::IsNullOrWhiteSpace($resourceGroup))
    
    Write-Output "Using resource group [$resourceGroup]"
    
    Write-Output "checking if resource group already exists"
    $resourceGroupExists = az group exists --name ${AKS_PERS_RESOURCE_GROUP}
    if ($resourceGroupExists -ne "true") {
        Write-Output "Create the Resource Group"
        az group create --name $resourceGroup --location $AKS_PERS_LOCATION --verbose

        Do { $location = Read-Host "Location: (e.g., eastus)"}
        while ([string]::IsNullOrWhiteSpace($location))    
    }
    
    $Return.AKS_PERS_RESOURCE_GROUP = $resourceGroup
    $Return.AKS_PERS_LOCATION = $location

    #Return the hashtable
    Return $Return         
}
#-------------------
Write-Host "end common.ps1 version $versioncommon"
