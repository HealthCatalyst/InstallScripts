Write-Output "Version 2018.03.21.01"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

DownloadAzCliIfNeeded

$loggedInUser = az account show --query "user.name"  --output tsv
$AKS_USE_SSL = ""

Write-Output "user: $loggedInUser"

$AKS_PERS_RESOURCE_GROUP_BASE64 = kubectl get secret azure-secret -o jsonpath='{.data.resourcegroup}'
if (![string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP_BASE64)) {
    $AKS_PERS_RESOURCE_GROUP = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AKS_PERS_RESOURCE_GROUP_BASE64))
}

if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
    Do { $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group (e.g., fabricnlp-rg)"}
    while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
}
else {
    Write-Output "Using resource group: $AKS_PERS_RESOURCE_GROUP"        
}

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

if ([string]::IsNullOrWhiteSpace($(kubectl get namespace fabricrealtime --ignore-not-found=true))) {
    kubectl create namespace fabricrealtime
}
else {
    Do { $deleteSecrets = Read-Host "Namespace exists.  Do you want to delete passwords and data stored in this namespace? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($deleteSecrets))    
    
    if ($deleteSecrets -eq "y" ) {
        kubectl delete secret mysqlrootpassword -n fabricrealtime --ignore-not-found=true
        kubectl delete secret mysqlpassword -n fabricrealtime --ignore-not-found=true
        kubectl delete secret certhostname -n fabricrealtime --ignore-not-found=true
        kubectl delete secret certpassword -n fabricrealtime --ignore-not-found=true
        kubectl delete secret rabbitmqmgmtuipassword -n fabricrealtime --ignore-not-found=true
    }
}

AskForPassword -secretname "mysqlrootpassword"  -prompt "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricrealtime"

AskForPassword -secretname "mysqlpassword"  -prompt "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricrealtime"

AskForSecretValue -secretname "certhostname" -prompt "Client Certificate hostname" -namespace "fabricrealtime"

AskForPassword -secretname "certpassword"  -prompt "Client Certificate password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricrealtime"

AskForPassword -secretname "rabbitmqmgmtuipassword"  -prompt "Admin password for RabbitMqMgmt" -namespace "fabricrealtime"

CleanOutNamespace -namespace $namespace

$AKS_PERS_SHARE_NAME = "fabricrealtime"
$AKS_PERS_STORAGE_ACCOUNT_NAME_BASE64 = kubectl get secret azure-secret -o jsonpath='{.data.azurestorageaccountname}'
$AKS_PERS_STORAGE_ACCOUNT_NAME = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AKS_PERS_STORAGE_ACCOUNT_NAME_BASE64))

$AZURE_STORAGE_CONNECTION_STRING = az storage account show-connection-string -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $AKS_PERS_RESOURCE_GROUP -o tsv

Write-Output "Create the file share: $AKS_PERS_SHARE_NAME"
az storage share create -n $AKS_PERS_SHARE_NAME --connection-string $AZURE_STORAGE_CONNECTION_STRING --quota 512

AskForSecretValue -secretname "customerid" -prompt "Health Catalyst Customer ID (e.g., ahmn)"

$customerid = ReadSecret -secretname customerid
$customerid = $customerid.ToLower().Trim()
Write-Output "Customer ID: $customerid"

Write-Host "-- Deploying volumes --"
$folder = "volumes"
foreach ($file in "certificateserver.yaml mysqlserver.yaml rabbitmq-cert.yaml rabbitmq.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying volume claims --"
$folder = "volumeclaims"
foreach ($file in "certificateserver.yaml mysqlserver.yaml rabbitmq-cert.yaml rabbitmq.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying pods --"
$folder = "pods"
foreach ($file in "certificateserver.yaml mysqlserver.yaml interfaceengine.yaml rabbitmq.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying cluster services --"
$folder = "services/cluster"
foreach ($file in "certificateserver.yaml mysqlserver.yaml interfaceengine.yaml rabbitmq.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying external services --"
$folder = "services/external"
foreach ($file in "certificateserver.yaml rabbitmq.yaml interfaceengine.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying HTTP proxies --"
$folder = "ingress/http"
    foreach ($file in "web.yaml rabbitmq.yaml interfaceengine.yaml".Split(" ")) { 
        ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/${folder}/${file}" -customerid $customerid | kubectl apply -f -
    }

Write-Host "-- Deploying TCP proxies --"
$folder = "ingress/tcp"
foreach ($file in "mysqlserver.yaml interfaceengine.yaml rabbitmq.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide

$loadBalancerIP = kubectl get svc traefik-ingress-service-public -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}' --ignore-not-found=true
if ([string]::IsNullOrWhiteSpace($loadBalancerIP)) {
    $loadBalancerIP = kubectl get svc traefik-ingress-service-internal -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
}
$loadBalancerInternalIP = kubectl get svc traefik-ingress-service-internal -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'

Write-Host "Sleeping for 10 seconds so kube services get IPs assigned"
Start-Sleep -Seconds 10

FixLoadBalancers -resourceGroup $AKS_PERS_RESOURCE_GROUP
