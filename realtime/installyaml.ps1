Write-Output "Version 2018.03.23.01"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

DownloadAzCliIfNeeded
GetLoggedInUserInfo

$namespace = "fabricrealtime"

$AKS_PERS_RESOURCE_GROUP = ReadSecretValue -secretname azure-secret -valueName "resourcegroup"

if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
    Write-Error "secret azure-secret not found"
    exit
}
Write-Output "Using resource group: $AKS_PERS_RESOURCE_GROUP"        

if ([string]::IsNullOrWhiteSpace($(kubectl get namespace $namespace --ignore-not-found=true))) {
    kubectl create namespace $namespace
}

GenerateSecretPassword -secretname "mysqlrootpassword" -namespace "fabricrealtime"

GenerateSecretPassword -secretname "mysqlpassword" -namespace "fabricrealtime"

# read dns
AskForSecretValue -secretname "certhostname" -prompt "Client Certificate hostname" -namespace "fabricrealtime"

GenerateSecretPassword -secretname "certpassword" -namespace "fabricrealtime"

GenerateSecretPassword -secretname "rabbitmqmgmtuipassword" -namespace "fabricrealtime"

CleanOutNamespace -namespace $namespace

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
