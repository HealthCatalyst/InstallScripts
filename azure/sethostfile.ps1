
Write-Output "-------------- sethostfile.ps1 version 2018.02.01.01 --------------------------"

Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/common.ps1 | Invoke-Expression;

$AKS_PERS_RESOURCE_GROUP = ReadSecretValue -secretname azure-secret -valueName resourcegroup
                           
$AKS_PERS_LOCATION = az group show --name $AKS_PERS_RESOURCE_GROUP --query "location" -o tsv

$MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"

Write-Host "hosts entries"
$fullCmdToUpdateHostsFiles=""
$cmdToRemovePreviousHostEntries=""
$cmdToAddNewHostEntries=""
$virtualmachines = az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[].name" -o tsv
ForEach ($vm in $virtualmachines) {
    $firstprivateip = az vm list-ip-addresses -g $AKS_PERS_RESOURCE_GROUP -n $vm --query "[].virtualMachine.network.privateIpAddresses[0]" -o tsv
    # $privateiplist= az vm show -g $AKS_PERS_RESOURCE_GROUP -n $vm -d --query privateIps -otsv
    Write-Output "$firstprivateip $vm"

    $cmdToRemovePreviousHostEntries = $cmdToRemovePreviousHostEntries + "grep -v '${vm}'  /etc/hosts | "
    $cmdToAddNewHostEntries = $cmdToAddNewHostEntries + " && echo '$firstprivateip $vm'"
    if ($vm -match "master" ) {
        Write-Output "$firstprivateip $MASTER_VM_NAME"
        $cmdToRemovePreviousHostEntries = $cmdToRemovePreviousHostEntries + "grep -v '${MASTER_VM_NAME}'  /etc/hosts | "
        $cmdToAddNewHostEntries = $cmdToAddNewHostEntries + " && echo '$firstprivateip ${MASTER_VM_NAME}'"
    }
}

$fullCmdToUpdateHostsFiles="$cmdToRemovePreviousHostEntries (cat $cmdToAddNewHostEntries )"

Write-Host "$fullCmdToUpdateHostsFiles"

Write-Output "----------------- end sethostfile.ps1 ----------------------------"
