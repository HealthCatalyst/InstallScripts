# This file contains common functions for Azure
# 
$versioncommon = "2018.03.13.01"

Write-Host "---- Including common.ps1 version $versioncommon -----"
function global:GetCommonVersion() {
    return $versioncommon
}

function global:CreateShareInStorageAccount($storageAccountName, $resourceGroup, $sharename, $deleteExisting) { 
    $AZURE_STORAGE_CONNECTION_STRING = az storage account show-connection-string -n $storageAccountName -g $resourceGroup -o tsv
    
    # Write-Host "Storage connection string: $AZURE_STORAGE_CONNECTION_STRING"

    if ($deleteExisting) {
        if ($(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv)) {
            Write-Host "Deleting the file share: $sharename"
            az storage share delete -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING
        
            
            Write-Host "Waiting for completion of delete for the file share: $sharename"        
            Do {
                Start-Sleep -Seconds 5 
                $SHARE_EXISTS = $(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv)
                Write-Host "."
            }
            while ($SHARE_EXISTS -ne "false")
        }
    }

    if ($(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv) -eq "false") {
        Write-Host "Creating the file share: $sharename"        
        az storage share create -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --quota 512       
    }
    else {
        Write-Host "File share already exists: $sharename"         
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
            $cmd = "crontab -e; mkdir -p /opt/healthcatalyst; curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/restartkubedns.txt -o /opt/healthcatalyst/restartkubedns.sh; chmod +x /opt/healthcatalyst/restartkubedns.sh; crontab -l | grep -v 'restartkubedns.sh' - | { cat; echo '*/10 * * * * /opt/healthcatalyst/restartkubedns.sh >> /tmp/restartkubedns.log 2>&1 \n'; } | crontab -"
            az vm run-command invoke -g $resourceGroup -n $vm --command-id RunShellScript --scripts "$cmd"
        }
    }
}

function global:UpdateOSInVMs($resourceGroup) {
    $virtualmachines = az vm list -g $resourceGroup --query "[?storageProfile.osDisk.osType != 'Windows'].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        Write-Host "Updating OS in vm: $vm"
        $cmd = "apt-get update && apt-get -y upgrade"
        az vm run-command invoke -g $resourceGroup -n $vm --command-id RunShellScript --scripts "$cmd"
    }
}


function global:RestartVMsInResourceGroup( $resourceGroup) {
    # az vm run-command invoke -g Prod-Kub-AHMN-RG -n k8s-master-37819884-0 --command-id RunShellScript --scripts "apt-get update && sudo apt-get upgrade"
    Write-Host "Restarting VMs in resource group: ${resourceGroup}: $(az vm list -g $resourceGroup --query "[].name" -o tsv)"
    az vm restart --ids $(az vm list -g $resourceGroup --query "[].id" -o tsv)

    Write-Host "Waiting for VMs to restart: $(az vm list -g $resourceGroup --query "[].name" -o tsv)"
    $virtualmachines = az vm list -g $resourceGroup --query "[].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        
        Write-Host "Waiting on $vm"
        Do { 
            Start-Sleep -Seconds 1
            $state = az vm show -g $resourceGroup -n $vm -d --query "powerState"; 
            Write-Host "Status of ${vm}: ${state}"
        }
        while (!($state = "VM running"))      
    }

    # sudo systemctl restart etcd 
    ForEach ($vm in $virtualmachines) {
        if ($vm -match "master" ) {
            Write-Host "Sending command to master($vm) to restart etcd due to bug: https://github.com/Azure/acs-engine/issues/2282"
            az vm run-command invoke -g $resourceGroup -n $vm --command-id RunShellScript --scripts "systemctl restart etcd"
        }
    }

    # systemctl enable etcd.service
    

}

function global:FixEtcdRestartIssueOnMaster( $resourceGroup) {

    $virtualmachines = az vm list -g $resourceGroup --query "[].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        if ($vm -match "master" ) {
            Write-Host "Sending command to master($vm) to enable etcd due to bug: https://github.com/Azure/acs-engine/issues/2282"
            # https://github.com/Azure/acs-engine/pull/2329/commits/e3ef0578f268bf00e6065414acffdfd7ebb4e90b
            az vm run-command invoke -g $resourceGroup -n $vm --command-id RunShellScript --scripts "systemctl enable etcd.service"
        }
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
        Write-Host "$firstprivateip $vm"

        $cmdToRemovePreviousHostEntries = $cmdToRemovePreviousHostEntries + "grep -v '${vm}' - | "
        $cmdToAddNewHostEntries = $cmdToAddNewHostEntries + " && echo '$firstprivateip $vm'"
        if ($vm -match "master" ) {
            Write-Host "$firstprivateip $MASTER_VM_NAME"
            $cmdToRemovePreviousHostEntries = $cmdToRemovePreviousHostEntries + "grep -v '${MASTER_VM_NAME}' - | "
            $cmdToAddNewHostEntries = $cmdToAddNewHostEntries + " && echo '$firstprivateip ${MASTER_VM_NAME}'"
        }
    }

    $fullCmdToUpdateHostsFiles = "cat /etc/hosts | $cmdToRemovePreviousHostEntries (cat $cmdToAddNewHostEntries ) | tee /etc/hosts; cat /etc/hosts"

    Write-Host "Command to send to VM"
    Write-Host "$fullCmdToUpdateHostsFiles"

    ForEach ($vm in $virtualmachines) {
        Write-Host "Sending command to $vm"
        az vm run-command invoke -g $resourceGroup -n $vm --command-id RunShellScript --scripts "$fullCmdToUpdateHostsFiles"
    }
}


function global:CleanResourceGroup($resourceGroup, $location, $vnet, $subnet, $subnetResourceGroup, $storageAccount) {
    Write-Host "checking if resource group already exists"
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
            # Write-Host "removing route table"
            # az network vnet subnet update -n "${subnet}" -g "${subnetResourceGroup}" --vnet-name "${vnet}" --route-table ""
        }
        Write-Host "cleaning out the existing group: [$resourceGroup]"
        #az group delete --name $resourceGroup --verbose

        if ($(az vm list -g $resourceGroup --query "[].id" -o tsv).length -ne 0) {
            Write-Host "delete the VMs first"
            az vm delete --ids $(az vm list -g $resourceGroup --query "[].id" -o tsv) --verbose --yes
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkInterfaces" --query "[].id" -o tsv ).length -ne 0) {
            Write-Host "delete the nics"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkInterfaces" --query "[].id" -o tsv )  --verbose
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Compute/disks" --query "[].id" -o tsv ).length -ne 0) {
            Write-Host "delete the disks"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Compute/disks" --query "[].id" -o tsv )
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Compute/availabilitySets" --query "[].id" -o tsv ).length -ne 0) {
            Write-Host "delete the availabilitysets"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Compute/availabilitySets" --query "[].id" -o tsv )
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/loadBalancers" --query "[].id" -o tsv ).length -ne 0) {
            Write-Host "delete the load balancers"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/loadBalancers" --query "[].id" -o tsv )
        }

        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/applicationGateways" --query "[].id" -o tsv ).length -ne 0) {
            Write-Host "delete the application gateways"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/applicationGateways" --query "[].id" -o tsv )
        }
    
        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("$storageAccount")}).length -ne 0) {
            Write-Host "delete the storage accounts EXCEPT storage account we created in the past"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("${storageAccount}")} )
            # az resource list --resource-group fabricnlp3 --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" -o tsv | ForEach-Object { if (!"$_".EndsWith("${resourceGroup}storage")) {  az resource delete --ids "$_" }}    
        }
        if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/publicIPAddresses" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("PublicIP")}).length -ne 0) {
            Write-Host "delete the public IPs EXCEPT Ingress IP we created in the past"
            az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/publicIPAddresses" --query "[].id" -o tsv | Where-Object {!"$_".EndsWith("PublicIP")} )
        }
    
        if (("$vnet") ) {
            if (![string]::IsNullOrWhiteSpace($(az network vnet subnet show -n "${subnet}" -g "${subnetResourceGroup}" --vnet-name "${vnet}" --query "networkSecurityGroup.id"))) {
                # Write-Host "Switching the subnet to a temp route table and tempnsg so we can delete the old route table and nsg"

                # $routeid = $(az network route-table show --name temproutetable --resource-group $resourceGroup --query "id" -o tsv)
                # if ([string]::IsNullOrWhiteSpace($routeid)) {
                #     Write-Host "create temproutetable"
                #     $routeid = az network route-table create --name temproutetable --resource-group $resourceGroup --query "id" -o tsv   
                # }
                # $routeid = $(az network route-table show --name temproutetable --resource-group $resourceGroup --query "id" -o tsv)
                # Write-Host "temproutetable: $routeid"

                # $nsg = $(az network nsg show --name tempnsg --resource-group $resourceGroup --query "id" -o tsv)
                # if ([string]::IsNullOrWhiteSpace($nsg)) {
                #     Write-Host "create tempnsg"
                #     $nsg = az network nsg create --name tempnsg --resource-group $resourceGroup --query "id" -o tsv   
                # }
                # $nsg = $(az network nsg show --name tempnsg --resource-group $resourceGroup --query "id" -o tsv)
                # Write-Host "tempnsg: $nsg"
        
                Write-Host "Updating the subnet"
                az network vnet subnet update -n "${subnet}" -g "${subnetResourceGroup}" --vnet-name "${vnet}" --route-table="" --network-security-group=""

                #az network vnet subnet update -n "${subnet}" -g "${subnetResourceGroup}" --vnet-name "${vnet}" --route-table "$routeid" --network-security-group "$nsg"
            }
        
            if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/routeTables" --query "[?name != 'temproutetable'].id" -o tsv ).length -ne 0) {
                Write-Host "delete the routes EXCEPT the temproutetable we just created"
                az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/routeTables" --query "[?name != 'temproutetable'].id" -o tsv)
            }
            if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkSecurityGroups" --query "[?name != 'tempnsg'].id" -o tsv).length -ne 0) {
                Write-Host "delete the nsgs EXCEPT the tempnsg we just created"
                az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkSecurityGroups" --query "[?name != 'tempnsg'].id" -o tsv)
            }
        }
        else {
            if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/routeTables" --query "[].id" -o tsv).length -ne 0) {
                Write-Host "delete the routes EXCEPT the temproutetable we just created"
                az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/routeTables" --query "[].id" -o tsv)
            }
            $networkSecurityGroup = "$($resourceGroup.ToLower())-nsg"
            if ($(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkSecurityGroups" --query "[?name != '${$networkSecurityGroup}'].id" -o tsv ).length -ne 0) {
                Write-Host "delete the network security groups"
                az resource delete --ids $(az resource list --resource-group $resourceGroup --resource-type "Microsoft.Network/networkSecurityGroups" --query "[?name != '${$networkSecurityGroup}'].id" -o tsv )
            }
    
        }
        # note: do not delete the Microsoft.Network/publicIPAddresses otherwise the loadBalancer will get a new IP
    }
    else {
        Write-Host "Create the Resource Group"
        az group create --name $resourceGroup --location $location --verbose
    }

}

function global:CreateStorageIfNotExists($resourceGroup) {
    #Create an hashtable variable 
    [hashtable]$Return = @{} 

    $location = az group show --name $resourceGroup --query "location" -o tsv

    $storageAccountName = Read-Host "Storage Account Name (leave empty for default)"
    if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
        $storageAccountName = "${resourceGroup}storage"
        # remove non-alphanumeric characters and use lowercase since azure doesn't allow those in a storage account
        $storageAccountName = $storageAccountName -replace '[^a-zA-Z0-9]', ''
        $storageAccountName = $storageAccountName.ToLower()
        if ($storageAccountName.Length > 24) {
            $storageAccountName = $storageAccountName.Substring(0, 24) # azure does not allow names longer than 24
        }
        Write-Host "Using storage account: [$storageAccountName]"
    }
    Write-Host "Checking to see if storage account exists"
    $storageAccountCanBeCreated = az storage account check-name --name $storageAccountName --query "nameAvailable" --output tsv
    
    if ($storageAccountCanBeCreated -ne "True" ) {
        az storage account check-name --name $storageAccountName   
        
        Write-Warning "Storage account, [$storageAccountName], already exists.  Deleting it will remove this data permanently"
        Do { $confirmation = Read-Host "Delete storage account: (WARNING: deletes data) (y/n)"}
        while ([string]::IsNullOrWhiteSpace($confirmation)) 
    
        if ($confirmation -eq 'y') {
            az storage account delete -n $storageAccountName -g $resourceGroup
            Write-Host "Creating storage account: [${storageAccountName}]"
            # https://docs.microsoft.com/en-us/azure/storage/common/storage-quickstart-create-account?tabs=azure-cli
            az storage account create -n $storageAccountName -g $resourceGroup -l $location --kind StorageV2 --sku Standard_LRS                       
        }    
    }
    else {
        Write-Host "Creating storage account: [${storageAccountName}]"
        az storage account create -n $storageAccountName -g $resourceGroup -l $location --kind StorageV2 --sku Standard_LRS            
    }    

    $Return.AKS_PERS_STORAGE_ACCOUNT_NAME = $storageAccountName
    return $Return
}

function global:GetVnet($subscriptionId) {
    #Create an hashtable variable 
    [hashtable]$Return = @{} 

    Write-Host "Subscription Id; $subscriptionId"

    $confirmation = 'y'
    # Do { $confirmation = Read-Host "Would you like to connect to an existing virtual network? (y/n)"}
    # while ([string]::IsNullOrWhiteSpace($confirmation))
    
    if ($confirmation -eq 'y') {

        # see if we had previously connected to a vnet
        $vnetName = ReadSecretValue -secretname azure-vnet -valueName vnet
        $subnetName = ReadSecretValue -secretname azure-vnet -valueName subnet
        $subnetResourceGroup = ReadSecretValue -secretname azure-vnet -valueName subnetResourceGroup

        
        if ([string]::IsNullOrEmpty($vnetName)) {
        }
        else {
            Do {
                $confirmation = Read-Host "Kubernetes secret shows vnet=$vnetName and subnet=$subnetName.  Do you want to use these? (y/n)"
            }
            while ([string]::IsNullOrEmpty($confirmation))

            if ($confirmation -eq "n") {
                $vnetName = ""
            }
        }

        if ([string]::IsNullOrEmpty($vnetName)) {
            Write-Host "Finding existing vnets..."
            # az network vnet list --query "[].[name,resourceGroup ]" -o tsv    
    
            $vnets = az network vnet list --query "[].[name]" -o tsv
    
            Do { 
                Write-Host "------  Existing vnets -------"
                for ($i = 1; $i -le $vnets.count; $i++) {
                    Write-Host "$i. $($vnets[$i-1])"
                }    
                Write-Host "------  End vnets -------"
    
                Do {
                    $index = Read-Host "Enter number of vnet to use (1 - $($vnets.count))"
                }
                while ([string]::IsNullOrWhiteSpace($index)) 

                $vnetName = $($vnets[$index - 1])
            }
            while ([string]::IsNullOrWhiteSpace($vnetName))    
    
            Write-Host "Searching for vnet named $vnetName ..."
            $subnetResourceGroup = az network vnet list --query "[?name == '$vnetName'].resourceGroup" -o tsv
            Write-Host "Using subnet resource group: [$subnetResourceGroup]"
    
            Write-Host "Finding existing subnets in $vnetName ..."
            $subnets = az network vnet subnet list --resource-group $subnetResourceGroup --vnet-name $vnetName --query "[].name" -o tsv
            
            if ($subnets.count -eq 1) {
                Write-Host "There is only one subnet called $subnets so choosing that"
                $subnetName = $subnets
            }
            else {
                Do { 
                    Write-Host "------  Subnets in $vnetName -------"
                    for ($i = 1; $i -le $subnets.count; $i++) {
                        Write-Host "$i. $($subnets[$i-1])"
                    }    
                    Write-Host "------  End Subnets -------"
        
                    Write-Host "NOTE: Each customer should have their own subnet.  Do not put multiple customers in the same subnet"
                    $index = Read-Host "Enter number of subnet to use (1 - $($subnets.count))"
                    $subnetName = $($subnets[$index - 1])
                }
                while ([string]::IsNullOrWhiteSpace($subnetName)) 
            }        
        }
    
        # verify the subnet exists
        $mysubnetid = "/subscriptions/${subscriptionId}/resourceGroups/${subnetResourceGroup}/providers/Microsoft.Network/virtualNetworks/${vnetName}/subnets/${subnetName}"
    
        $subnetexists = az resource show --ids $mysubnetid --query "id" -o tsv
        if (!"$subnetexists") {
            Write-Host "The subnet was not found: $mysubnetid"
            Read-Host "Hit ENTER to exit"
            exit 0        
        }
        else {
            Write-Host "Found subnet: [$mysubnetid]"
        }
        
        Write-Host "Looking up CIDR for Subnet: [${subnetName}]"
        $subnetCidr = az network vnet subnet show --name ${subnetName} --resource-group ${subnetResourceGroup} --vnet-name ${vnetname} --query "addressPrefix" --output tsv
    
        Write-Host "Subnet CIDR=[$subnetCidr]"
        # suggest and ask for the first static IP to use
        $firstStaticIP = ""
        $suggestedFirstStaticIP = Get-FirstIP -ip ${subnetCidr}
    
        # $firstStaticIP = Read-Host "First static IP: (default: $suggestedFirstStaticIP )"
        
        if ([string]::IsNullOrWhiteSpace($firstStaticIP)) {
            $firstStaticIP = "$suggestedFirstStaticIP"
        }
    
        Write-Host "First static IP=[${firstStaticIP}]"
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
    $Return.AKS_SUBNET_CIDR = $subnetCidr

    #Return the hashtable
    Return $Return     
}

function global:Test-CommandExists {
    Param ($command)
    # from https://blogs.technet.microsoft.com/heyscriptingguy/2013/02/19/use-a-powershell-function-to-see-if-a-command-exists/
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try {if (Get-Command $command) {RETURN $true}}
    Catch {Write-Host "$command does not exist"; RETURN $false}
    Finally {$ErrorActionPreference = $oldPreference}
} #end function test-CommandExists

function global:Get-ProcessByPort( [ValidateNotNullOrEmpty()] [int] $Port ) {    
    $netstat = netstat.exe -ano | Select-Object -Skip 4
    $p_line = $netstat | Where-Object { $p = ( -split $_ | Select-Object -Index 1) -split ':' | Select-Object -Last 1; $p -eq $Port } | Select-Object -First 1
    if (!$p_line) { return; } 
    $p_id = $p_line -split '\s+' | Select-Object -Last 1
    return $p_id;
}

function global:FindOpenPort($portArray) {
    [hashtable]$Return = @{} 

    ForEach ($port in $portArray) {
        $result = Get-ProcessByPort $port
        if ([string]::IsNullOrEmpty($result)) {
            $Return.Port = $port
            return $Return
        }
    }   
    $Return.Port = 0

    return $Return
}

function global:AddFolderToPathEnvironmentVariable($folder) {
    # add the c:\kubernetes folder to system PATH
    Write-Host "Checking if $folder is in PATH"
    $pathItems = ($env:path).split(";")
    if ( $pathItems -notcontains "$folder") {
        Write-Host "Adding $folder to system path"
        $oldpath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH).path
        # see if the registry value is wrong too
        if ( ($oldpath).split(";") -notcontains "$folder") {
            $newpath = "$oldpath;$folder"
            Read-Host "Script needs elevated privileges to set PATH.  Hit ENTER to launch script to set PATH"
            Start-Process powershell -verb RunAs -ArgumentList "Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH -Value '$newPath'; Read-Host 'Press ENTER'"
            Write-Host "New PATH:"
            $newpath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH).path
            Write-Host "$newpath".split(";")
        }
        # for current session set the PATH too.  the above only takes effect if powershell is reopened
        $ENV:PATH = "$ENV:PATH;$folder"
        Write-Host "Set path for current powershell session"
        Write-Host ($env:path).split(";")
    }
    else {
        Write-Host "$folder is already in PATH"
    }
}
function global:DownloadAzCliIfNeeded() {
    # install az cli from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest
    $desiredAzClVersion = "2.0.27"
    $downloadazcli = $False
    if (!(Test-CommandExists az)) {
        $downloadazcli = $True
    }
    else {
        $azcurrentversion = az -v | Select-String "azure-cli" | Select-Object -exp line
        # we should get: azure-cli (2.0.22)
        $azversionMatches = $($azcurrentversion -match "$desiredAzClVersion")
        if (!$azversionMatches) {
            Write-Host "az version $azcurrentversion is not the same as desired version: $desiredAzClVersion"
            $downloadazcli = $True
        }
    }

    if ($downloadazcli) {
        $azCliFile = ([System.IO.Path]::GetTempPath() + ("az-cli-latest.msi"))
        $url = "https://azurecliprod.blob.core.windows.net/msi/azure-cli-latest.msi"
        Write-Host "Downloading az-cli-latest.msi from url $url to $azCliFile"
        If (Test-Path $azCliFile) {
            Remove-Item $azCliFile -Force
        }

        DownloadFile -url $url -targetFile $azCliFile

        # https://kevinmarquette.github.io/2016-10-21-powershell-installing-msi-files/
        Write-Host "Running MSI to install az"
        $azCliInstallLog = ([System.IO.Path]::GetTempPath() + ('az-cli-latest.log'))
        # msiexec flags: https://msdn.microsoft.com/en-us/library/windows/desktop/aa367988(v=vs.85).aspx
        # Start-Process -Verb runAs msiexec.exe -Wait -ArgumentList "/i $azCliFile /qn /L*e $azCliInstallLog"
        Start-Process -Verb runAs msiexec.exe -Wait -ArgumentList "/i $azCliFile"
        Write-Host "Finished installing az-cli-latest.msi"
    }
    
}

function global:CreateSSHKey($resourceGroup, $localFolder) {
    #Create an hashtable variable 
    [hashtable]$Return = @{} 

    $folderForSSHKey = "$localFolder\ssh\$resourceGroup"

    if (!(Test-Path -Path "$folderForSSHKey")) {
        Write-Host "$folderForSSHKey does not exist.  Creating it..."
        New-Item -ItemType directory -Path "$folderForSSHKey"
    }
    
    # check if SSH key is present.  If not, generate it
    $privateKeyFile = "$folderForSSHKey\id_rsa"
    $privateKeyFileUnixPath = "/" + (($privateKeyFile -replace "\\", "/") -replace ":", "").ToLower().Trim("/")    
    
    if (!(Test-Path "$privateKeyFile")) {
        Write-Host "SSH key does not exist in $privateKeyFile."
        Write-Host "Please open Git Bash and run:"
        Write-Host "ssh-keygen -t rsa -b 2048 -q -N '' -C azureuser@linuxvm -f $privateKeyFileUnixPath"
        Read-Host "Hit ENTER after you're done"
    }
    else {
        Write-Host "SSH key already exists at $privateKeyFile so using it"
    }
    
    $publicKeyFile = "$folderForSSHKey\id_rsa.pub"
    $sshKey = Get-Content "$publicKeyFile" -First 1
    Write-Host "SSH Public Key=$sshKey"

    
    $Return.AKS_SSH_KEY = $sshKey
    $Return.SSH_PUBLIC_KEY_FILE = $publicKeyFile
    $Return.SSH_PRIVATE_KEY_FILE_UNIX_PATH = $privateKeyFileUnixPath

    #Return the hashtable
    Return $Return     
        
}

function global:CheckIfUserLogged() {

    #Create an hashtable variable 
    [hashtable]$Return = @{} 

    Write-Host "Checking if you're already logged in..."

    # to print out the result to screen also use: <command> | Tee-Object -Variable cmdOutput
    $loggedInUser = $(az account show --query "user.name"  --output tsv)
    
    # get azure login and subscription
    Write-Host "user ${loggedInUser}"
    
    if ( "$loggedInUser" ) {
        $subscriptionName = az account show --query "name"  --output tsv
        Write-Host "You are currently logged in as [$loggedInUser] into subscription [$subscriptionName]"
        
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
    
    $subscriptionId = $(az account show --query "id" --output tsv)

    Write-Host "SubscriptionId: ${subscriptionId}"

    $Return.AKS_SUBSCRIPTION_ID = "$subscriptionId"
    return $Return
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
    
    Write-Host "Using resource group [$resourceGroup]"
    
    Write-Host "checking if resource group already exists"
    $resourceGroupExists = az group exists --name ${resourceGroup}
    if ($resourceGroupExists -ne "true") {
        Do { $location = Read-Host "Location: (e.g., eastus)"}
        while ([string]::IsNullOrWhiteSpace($location))    

        Write-Host "Create the Resource Group"
        az group create --name $resourceGroup --location $location --verbose
    }
    else {
        $location = az group show --name $resourceGroup --query "location" -o tsv
    }
    
    $Return.AKS_PERS_RESOURCE_GROUP = $resourceGroup
    $Return.AKS_PERS_LOCATION = $location

    #Return the hashtable
    Return $Return         
}

function global:SetNetworkSecurityGroupRule($resourceGroup, $networkSecurityGroup, $rulename, $ruledescription, $sourceTag, $port, $priority ) {
    if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "$rulename" --nsg-name $networkSecurityGroup --resource-group $resourceGroup))) {
        Write-Host "Creating rule: $rulename"
        az network nsg rule create -g $resourceGroup --nsg-name $networkSecurityGroup -n "$rulename" --priority $priority `
            --source-address-prefixes "${sourceTag}" --source-port-ranges '*' `
            --destination-address-prefixes '*' --destination-port-ranges $port --access Allow `
            --protocol Tcp --description "$ruledescription" `
            --query "provisioningState" -o tsv
    }
    else {
        Write-Host "Updating rule: $rulename"

        az network nsg rule update -g $resourceGroup --nsg-name $networkSecurityGroup -n "$rulename" --priority $priority `
            --source-address-prefixes "${sourceTag}" --source-port-ranges '*' `
            --destination-address-prefixes '*' --destination-port-ranges $port --access Allow `
            --protocol Tcp --description "$ruledescription" `
            --query "provisioningState" -o tsv
    }
    
}
function global:DeleteNetworkSecurityGroupRule($resourceGroup, $networkSecurityGroup, $rulename ) {
    if (![string]::IsNullOrWhiteSpace($(az network nsg rule show --name "$rulename" --nsg-name $networkSecurityGroup --resource-group $resourceGroup))) {
        Write-Host "Deleting $rulename rule"
        az network nsg rule delete -g $resourceGroup --nsg-name $networkSecurityGroup -n $rulename
    }    
}

function global:DownloadKubectl($localFolder) {
    # download kubectl
    $kubeCtlFile = "$localFolder\kubectl.exe"
    $desiredKubeCtlVersion = "v1.9.2"
    $downloadkubectl = "n"
    if (!(Test-Path "$kubeCtlFile")) {
        $downloadkubectl = "y"
    }
    else {
        $kubectlversion = kubectl version --client=true --short=true
        Write-Host "kubectl version: $kubectlversion"
        $kubectlversionMatches = $($kubectlversion -match "$desiredKubeCtlVersion")
        if (!$kubectlversionMatches) {
            $downloadkubectl = "y"
        }
    }
    if ( $downloadkubectl -eq "y") {
        $url = "https://storage.googleapis.com/kubernetes-release/release/${desiredKubeCtlVersion}/bin/windows/amd64/kubectl.exe"
        Write-Host "Downloading kubectl.exe from url $url to $kubeCtlFile"
        Remove-Item -Path "$kubeCtlFile" -Force
        DownloadFile -url $url -targetFile $kubeCtlFile
    }
    else {
        Write-Host "kubectl already exists at $kubeCtlFile"    
    }
    
}

function global:DownloadFileNew($url, $targetFile) {
    $wc = New-Object net.webclient
    $wc.Downloadfile($url, $targetFile)
}
function global:DownloadFile($url, $targetFile) {
    # from https://stackoverflow.com/questions/21422364/is-there-any-way-to-monitor-the-progress-of-a-download-using-a-webclient-object
    $uri = New-Object "System.Uri" "$url"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.set_Timeout(15000) #15 second timeout
    # $request.Proxy = $null
    $response = $request.GetResponse()
    $totalLength = [System.Math]::Floor($response.get_ContentLength() / 1024)
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
    $buffer = new-object byte[] 4096KB
    Write-Host "Buffer length: $($buffer.length)"
    $count = $responseStream.Read($buffer, 0, $buffer.length)
    $downloadedBytes = $count
    while ($count -gt 0) {
        $targetStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer, 0, $buffer.length)
        # Write-Host "read: $count bytes"
        $downloadedBytes = $downloadedBytes + $count
        Write-Progress -activity "Downloading file '$($url.split('/') | Select-Object -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes / 1024)) / $totalLength) * 100)
        [System.Console]::CursorLeft = 0 
        [System.Console]::Write("Downloading '$($url.split('/') | Select-Object -Last 1)': {0}K of {1}K", [System.Math]::Floor($downloadedBytes / 1024), $totalLength) 
    }

    Write-Progress -activity "Finished downloading file '$($url.split('/') | Select-Object -Last 1)'"
    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}

function global:FixLoadBalancers($resourceGroup) {
    # hacks here to get around bugs in the acs-engine loadbalancer code
    Write-Host "Checking if load balancers are setup correctly for resourceGroup: $resourceGroup"
    # 1. assign the nics to the loadbalancer

    # find loadbalancer with name 
    $loadbalancer = "${resourceGroup}-internal"
    $loadbalancerBackendPoolName = $resourceGroup # the name may change in the future so we should look it up
    # for each worker VM
    $virtualmachines = az vm list -g $resourceGroup --query "[].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        if ($vm -match "master" ) {}
        else {
            # for each worker VM
            Write-Host "Checking VM: $vm"
            # get first nic
            # $nic = "k8s-linuxagent-14964077-nic-0"
            $nicId = $(az vm nic list -g $resourceGroup --vm-name $vm --query "[].id" -o tsv)
            $nic = $(az network nic show --ids $nicId --resource-group $resourceGroup --query "name" -o tsv)

            # get first ipconfig of nic
            $ipconfig = $(az network nic ip-config list --resource-group $resourceGroup --nic-name $nic --query "[?primary].name" -o tsv)

            $loadbalancerForNic = $(az network nic ip-config show --resource-group $resourceGroup --nic-name $nic --name $ipconfig --query "loadBalancerBackendAddressPools[].id" -o tsv)
            # if loadBalancerBackendAddressPools is missing then
            if ([string]::IsNullOrEmpty($loadbalancerForNic)) {
                Write-Warning "Fixing load balancer for vm: $vm by adding nic $nic with ip-config $ipconfig to backend pool $loadbalancerBackendPoolName in load balancer $loadbalancer "
                # --lb-address-pools: Space-separated list of names or IDs of load balancer address pools to associate with the NIC. If names are used, --lb-name must be specified.
                az network nic ip-config update --resource-group $resourceGroup --nic-name $nic --name $ipconfig --lb-name $loadbalancer --lb-address-pools $loadbalancerBackendPoolName
            }
            elseif (!($($loadbalancerForNic -contains $loadbalancer))) {
                Write-Host "nic is already bound to load balancer $loadbalancerForNic with ip-config $ipconfig"
                Write-Host "adding internal load balancer to secondary ip-config"
                # get the first secondary ipconfig
                $ipconfig = $(az network nic ip-config list --resource-group $resourceGroup --nic-name $nic --query "[?!primary].name" -o tsv)[0]
                $loadbalancerForNic = $(az network nic ip-config show --resource-group $resourceGroup --nic-name $nic --name $ipconfig --query "loadBalancerBackendAddressPools[].id" -o tsv)
                if ([string]::IsNullOrEmpty($loadbalancerForNic)) {
                    Write-Warning "Fixing load balancer for vm: $vm by adding nic $nic with ip-config $ipconfig to backend pool $loadbalancerBackendPoolName in load balancer $loadbalancer "
                    # --lb-address-pools: Space-separated list of names or IDs of load balancer address pools to associate with the NIC. If names are used, --lb-name must be specified.
                    az network nic ip-config update --resource-group $resourceGroup --nic-name $nic --name $ipconfig --lb-name $loadbalancer --lb-address-pools $loadbalancerBackendPoolName
                }
                else {
                    Write-Host "Load Balancer with ip-config $ipconfig is already setup properly for vm: $vm"
                }
            }
            else {
                Write-Host "Load Balancer with ip-config $ipconfig is already setup properly for vm: $vm"
            }
        }
    }

    # 2. fix the ports in load balancing rules
    Write-Host "Checking if the correct ports are setup in the load balancer"

    # get frontendip configs for this IP
    # $idToIPTuplesJson=$(az network lb frontend-ip list --resource-group=$AKS_PERS_RESOURCE_GROUP --lb-name $loadbalancer --query "[*].[id,privateIpAddress]")
    # $idToIPTuplesJson = $(az network lb frontend-ip list --resource-group=$AKS_PERS_RESOURCE_GROUP --lb-name $loadbalancer --query "[*].{id:id,ip:privateIpAddress}")
    $idToIPTuples = $(az network lb frontend-ip list --resource-group=$resourceGroup --lb-name $loadbalancer --query "[*].{id:id,ip:privateIpAddress}") | ConvertFrom-Json
    $services = $($(kubectl get services --all-namespaces -o json) | ConvertFrom-Json).items
    $loadBalancerServices = @()
    Write-Host "---- Searching for kub services of type LoadBalancer"
    foreach ($service in $services) {
        if ($($service.spec.type -eq "LoadBalancer")) {
            if ($service.status.loadBalancer.ingress.Count -gt 0) {
                Write-Host "Found kub services $($service.metadata.name) with $($service.status.loadBalancer.ingress[0].ip)"
                $loadBalancerServices += $service
            }
            else {
                Write-Host "Found kub services $($service.metadata.name) but it has no ingress IP so skipping it"
            }
        }
    }
    Write-Host "---- Finished searching for kub services of type LoadBalancer"

    ForEach ($tuple in $idToIPTuples) {
        Write-Host "---------- tuple: $($tuple.ip)  $($tuple.id) ------------------"
        $rulesForIp = $(az network lb rule list --resource-group $resourceGroup --lb-name $loadbalancer --query "[?frontendIpConfiguration.id == '$($tuple.id)'].{frontid:frontendIpConfiguration.id,name:name,backendPort:backendPort,frontendPort: frontendPort}") | ConvertFrom-Json

        ForEach ($service in $loadBalancerServices) {
            Write-Host "-------- Checking kub service: $($service.metadata.name) ----"
            # first check ports for internal loadbalancer
            $loadBalancerIp = $($service.status.loadBalancer.ingress[0].ip)
            # Write-Host "Checking tuple ip $($tuple.ip) with loadBalancer Ip $loadBalancerIp"
            if ($tuple.ip -eq $loadBalancerIp) {
                #this is the right load balancer
                ForEach ($rule in $rulesForIp) {
                    Write-Host "----- Checking rule $($rule.name) ----"
                    # Write-Host "tuple $($tuple.ip) matches loadBalancerIP: $loadBalancerIp"
                    # match rule.backendPort to $loadbalancerInfo.spec.ports
                    ForEach ( $loadbalancerPortInfo in $($service.spec.ports)) {
                        # Write-Host "Rule: $rule "
                        # Write-Host "LoadBalancer:$loadbalancerPortInfo"
                        if ($($rule.frontendPort) -eq $($loadbalancerPortInfo.port)) {
                            Write-Host "Found matching frontend ports: rule: $($rule.frontendPort) of rule $($rule.name) and loadbalancer: $($loadbalancerPortInfo.port) from $($loadbalancerPortInfo.name)"
                            if ($($rule.backendPort) -ne $($loadbalancerPortInfo.nodePort)) {
                                Write-Warning "Backend ports don't match.  Will change $($rule.backendPort) to $($loadbalancerPortInfo.nodePort)"
                                # set the rule backendPort to nodePort instead
                                $rule.backendPort = $loadbalancerPortInfo.nodePort
                                az network lb rule update --lb-name $loadbalancer --name $($rule.name) --resource-group $resourceGroup --backend-port $loadbalancerPortInfo.nodePort
                            }
                            else {
                                Write-Host "Skipping changing backend port since it already matches $($rule.backendPort) vs $($loadbalancerPortInfo.nodePort)"
                            }
                        }
                        else {
                            Write-Host "Skipping rule $($rule.name): Rule port: $($rule.backendPort) is not a match for loadbalancerPort $($loadbalancerPortInfo.port) from $($loadbalancerPortInfo.name)"                    
                        }
                    }
                }
                # get port from kubernetes service
            }
            else {
                Write-Host "Skipping tuple since tuple ip $($tuple.ip) does not match loadBalancerIP: $loadBalancerIp"
            }
        }
        Write-Host ""
    }
    # end hacks
}

function global:SetupDNS($dnsResourceGroup, $dnsrecordname, $externalIP) {
    Write-Host "Setting DNS zones"

    if ([string]::IsNullOrWhiteSpace($(az network dns zone show --name "$dnsrecordname" -g $dnsResourceGroup))) {
        Write-Host "Creating DNS zone: $dnsrecordname"
        az network dns zone create --name "$dnsrecordname" -g $dnsResourceGroup
    }

    Write-Host "Create A record for * in zone: $dnsrecordname"
    az network dns record-set a add-record --ipv4-address $externalIP --record-set-name "*" --resource-group $dnsResourceGroup --zone-name "$dnsrecordname"

    ShowNameServerEntries -dnsResourceGroup $dnsResourceGroup -dnsrecordname $dnsrecordname
}

function global:ShowNameServerEntries($dnsResourceGroup, $dnsrecordname) {
    # list out the name servers
    Write-Host "Name servers to set in GoDaddy for *.$dnsrecordname"
    az network dns zone show -g $dnsResourceGroup -n "$dnsrecordname" --query "nameServers" -o tsv
}

function global:GetLoadBalancerIPs() {
    [hashtable]$Return = @{} 

    $startDate = Get-Date
    $timeoutInMinutes = 10
    $loadbalancer = "traefik-ingress-service-public"
    $loadbalancerInternal = "traefik-ingress-service-internal" 

    Write-Host "Waiting for IP to get assigned to the load balancer (Note: It can take upto 5 minutes for Azure to finish creating the load balancer)"
    Do { 
        Start-Sleep -Seconds 10
        Write-Host "."
        $externalIP = $(kubectl get svc $loadbalancer -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}')
    }
    while ([string]::IsNullOrWhiteSpace($externalIP) -and ($startDate.AddMinutes($timeoutInMinutes) -gt (Get-Date)))
    Write-Host "External IP: $externalIP"
    
    if ($AKS_CLUSTER_ACCESS_TYPE -eq "2") {
        Write-Host "Waiting for IP to get assigned to the internal load balancer (Note: It can take upto 5 minutes for Azure to finish creating the load balancer)"
        Do { 
            Start-Sleep -Seconds 10
            Write-Host "."
            $internalIP = $(kubectl get svc $loadbalancerInternal -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}')
        }
        while ([string]::IsNullOrWhiteSpace($internalIP) -and ($startDate.AddMinutes($timeoutInMinutes) -gt (Get-Date)))
        Write-Host "Internal IP: $internalIP"
    }

    $Return.ExternalIP = $externalIP
    $Return.InternalIP = $internalIP
    
    return $Return
}
function global:CheckUrl($url, $hostHeader) {

    [hashtable]$Return = @{} 

    $Request = [Net.HttpWebRequest]::Create($url)
    $Request.Host = $hostHeader
    $Response = $Request.GetResponse()

    $respstream = $Response.GetResponseStream(); 
    $sr = new-object System.IO.StreamReader $respstream; 
    $result = $sr.ReadToEnd(); 
    write-host "$result"

    $Return.Response = $result
    $Return.StatusCode = $Response.StatusCode
    $Return.StatusDescription = $Response.StatusDescription
    return $Return
}
function global:GetDNSCommands() {

    [hashtable]$Return = @{} 

    $myCommands = @()

    $loadBalancerInternalIP = kubectl get svc traefik-ingress-service-internal -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}' --ignore-not-found=true
    
    $internalDNSEntries = $(kubectl get ing --all-namespaces -l expose=internal -o jsonpath="{.items[*]..spec.rules[*].host}" --ignore-not-found=true).Split(" ")
    ForEach ($dns in $internalDNSEntries) { 
        $dnsWithoutDomain = $dns -replace ".healthcatalyst.net", ""
        $myCommands += "dnscmd cafeaddc-01.cafe.healthcatalyst.com /recorddelete healthcatalyst.net $dnsWithoutDomain A /f"
        $myCommands += "dnscmd cafeaddc-01.cafe.healthcatalyst.com /recordadd healthcatalyst.net $dnsWithoutDomain A $loadBalancerInternalIP"
        # $myCommands += "dnscmd cafeaddc-01.cafe.healthcatalyst.com /recorddelete healthcatalyst.net $dns PTR /f"
        # $myCommands += "dnscmd cafeaddc-01.cafe.healthcatalyst.com /recordadd 10.in-addr-arpa $loadBalancerInternalIP PTR $dns"
    }

    $loadBalancerIP = kubectl get svc traefik-ingress-service-public -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}' --ignore-not-found=true
    
    $externalDNSEntries = $(kubectl get ing --all-namespaces -l expose=external -o jsonpath="{.items[*]..spec.rules[*].host}" --ignore-not-found=true).Split(" ")

    ForEach ($dns in $externalDNSEntries) { 
        if (($internalDNSEntries.Contains($dns))) {
            # already included in internal load balancer
        }
        else {
            $dnsWithoutDomain = $dns -replace ".healthcatalyst.net", ""
            $myCommands += "dnscmd cafeaddc-01.cafe.healthcatalyst.com /recorddelete healthcatalyst.net $dnsWithoutDomain A /f"
            $myCommands += "dnscmd cafeaddc-01.cafe.healthcatalyst.com /recordadd healthcatalyst.net $dnsWithoutDomain A $loadBalancerIP"
            # $myCommands += "dnscmd cafeaddc-01.cafe.healthcatalyst.com /recorddelete healthcatalyst.net $dns PTR /f"
            # $myCommands += "dnscmd cafeaddc-01.cafe.healthcatalyst.com /recordadd 10.in-addr-arpa $loadBalancerIP PTR $dns"        
        }
    }
    $Return.Commands = $myCommands
    return $Return
}
function global:WriteDNSCommands() {
    $myCommands = $(GetDNSCommands).Commands
    Write-Host "To setup DNS entries in CAFE environment, remote desktop to CAFE DNS server: 10.5.2.4"
    Write-Host "Open Powershell window and paste the following:"
    ForEach ($myCommand in $myCommands) {
        Write-Host $myCommand
    }
    Write-Host ""
}

function global:GetPublicNameofMasterVM($resourceGroup) {
    [hashtable]$Return = @{} 

    $resourceGroupLocation = az group show --name $resourceGroup --query "location" -o tsv

    $masterVMName = "${resourceGroup}.${resourceGroupLocation}.cloudapp.azure.com"

    $Return.Name = $masterVMName
    return $Return
}

function global:GetPrivateIPofMasterVM($resourceGroup) {
    [hashtable]$Return = @{} 

    $virtualmachines = az vm list -g $resourceGroup --query "[?storageProfile.osDisk.osType != 'Windows'].name" -o tsv
    ForEach ($vm in $virtualmachines) {
        if ($vm -match "master" ) {
            $firstprivateip = az vm list-ip-addresses -g $resourceGroup -n $vm --query "[].virtualMachine.network.privateIpAddresses[0]" -o tsv
        }
    }

    $Return.PrivateIP = $firstprivateip
    return $Return
}

function global:CreateVM($vm, $resourceGroup, $subnetId, $networkSecurityGroup, $publicKeyFile, $image) {
    [hashtable]$Return = @{} 

    $publicIP = "${vm}PublicIP"
    Write-Host "Creating public IP: $publicIP"
    $ip = az network public-ip create --name $publicIP `
        --resource-group $resourceGroup `
        --allocation-method Static --query "publicIp.ipAddress" -o tsv
    
    Write-Host "Creating NIC: ${vm}-nic"
    az network nic create `
        --resource-group $resourceGroup `
        --name "${vm}-nic" `
        --subnet $subnetId `
        --network-security-group $networkSecurityGroup `
        --public-ip-address $publicIP `
        --query "provisioningState" -o tsv
    
    Write-Host "Creating VM: ${vm} from image: $urn"
    az vm create --resource-group $resourceGroup --name $vm `
        --image "$image" `
        --size Standard_DS2_v2 `
        --admin-username azureuser --ssh-key-value $publicKeyFile `
        --nics "${vm}-nic"    
        
    $Return.IP = $ip
    return $Return                 
}
#-------------------
Write-Host "end common.ps1 version $versioncommon"
