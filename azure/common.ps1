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
            # az network vnet subnet update -n "${subnet}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${vnet}" --route-table ""
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

Write-Host "end common.ps1 version $versioncommon"
