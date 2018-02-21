Write-Output "--- installnlpkubernetes.ps1 Version 2018.02.20.04 ---"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | iex;
# $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
$GITHUB_URL = "C:\Catalyst\git\Installscripts"

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

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

if ([string]::IsNullOrWhiteSpace($(kubectl get secret traefik-cert-ahmn -o jsonpath='{.data}' -n kube-system --ignore-not-found=true))) {
    $AKS_USE_SSL = ""
}
else {
    $AKS_USE_SSL = "y"
}

# https://kubernetes.io/docs/reference/kubectl/jsonpath/

# setup DNS
# az network dns zone create -g $AKS_PERS_RESOURCE_GROUP -n nlp.allina.healthcatalyst.net
# az network dns record-set a add-record --ipv4-address j `
#                                        --record-set-name nlp.allina.healthcatalyst.net `
#                                        --resource-group $AKS_PERS_RESOURCE_GROUP `
#                                        --zone-name 

$AKS_PERS_SHARE_NAME = "fabricnlp"
$AKS_PERS_BACKUP_SHARE_NAME = "${AKS_PERS_SHARE_NAME}backups"

CreateShare -resourceGroup $AKS_PERS_RESOURCE_GROUP -sharename $AKS_PERS_SHARE_NAME
CreateShare -resourceGroup $AKS_PERS_RESOURCE_GROUP -sharename $AKS_PERS_BACKUP_SHARE_NAME

$namespace="fabricnlp"

if ([string]::IsNullOrWhiteSpace($(kubectl get namespace $namespace --ignore-not-found=true))) {
    kubectl create namespace $namespace
}
else {
    Do { $deleteSecrets = Read-Host "Namespace exists.  Do you want to delete passwords and ALL data stored in this namespace? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($deleteSecrets))    
    
    if ($deleteSecrets -eq "y" ) {
        kubectl delete secret mysqlrootpassword -n $namespace --ignore-not-found=true
        kubectl delete secret mysqlpassword -n $namespace --ignore-not-found=true
        kubectl delete secret smtprelaypassword -n $namespace --ignore-not-found=true
               
        # need to recreate the file share when we change passwords otherwise the new password will not work with the old password stored in the share
        CreateShare -resourceGroup $AKS_PERS_RESOURCE_GROUP -sharename $AKS_PERS_SHARE_NAME -deleteExisting true
    }
}

AskForSecretValue -secretname "customerid" -prompt "Health Catalyst Customer ID (e.g., ahmn)"

$customerid = ReadSecret -secretname customerid
$customerid = $customerid.ToLower().Trim()
Write-Output "Customer ID: $customerid"

SaveSecretValue -secretname nlpweb-external-url -valueName url -value "nlp.$customerid.healthcatalyst.net" -namespace $namespace
SaveSecretValue -secretname jobserver-external-url -valueName url -value "nlpjobs.$customerid.healthcatalyst.net" -namespace $namespace

AskForPassword -secretname "mysqlrootpassword" -prompt "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "$namespace"
# MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
# we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script

AskForPassword -secretname "mysqlpassword" -prompt "MySQL NLP_APP_USER password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "$namespace"

AskForPasswordAnyCharacters -secretname "smtprelaypassword" -prompt "SMTP (SendGrid) Relay Key" -namespace "$namespace" -defaultvalue "" 

CleanOutNamespace -namespace $namespace

# Write-Host "Deploying roles"
# $folder = "kubernetes/loadbalancer/roles"
# foreach ($file in "ingress-roles.yaml".Split(" ")) { 
#     ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
# }

Write-Host "-- Deploying volumes --"
$folder="volumes"
foreach ($file in "mysqlserver.yaml solrserver.yaml jobserver.yaml mysqlbackup.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying volume claims --"
$folder="volumeclaims"
foreach ($file in "mysqlserver.yaml solrserver.yaml jobserver.yaml mysqlbackup.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying pods --"
$folder="pods"
foreach ($file in "mysqlserver.yaml solrserver.yaml jobserver.yaml nlpwebserver.yaml mysqlclient.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying cluster services --"
$folder="services/cluster"
foreach ($file in "mysqlserver.yaml solrserver.yaml jobserver.yaml nlpwebserver.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying external services --"
$folder="services/external"
foreach ($file in "solrserver.yaml jobserver.yaml nlpwebserver.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying HTTP proxies --"
$folder="ingress/http"
foreach ($file in "web.yaml solr.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying TCP proxies --"
$folder="ingress/tcp"
foreach ($file in "mysqlserver.internal.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "-- Deploying jobs --"
$folder="jobs"
foreach ($file in "mysqlserver-backup-cron.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=$namespace -o wide

# to get a shell
# kubectl exec -it fabric.nlp.nlpwebserver-85c8cb86b5-gkphh bash --namespace=fabricnlp

# kubectl create secret generic azure-secret --namespace=fabricnlp --from-literal=azurestorageaccountname="fabricnlp7storage" --from-literal=azurestorageaccountkey="/bYhXNstTodg3MdOvTMog/vDLSFrQDpxG/Zgkp2MlnjtOWhDBNQ2xOs6zjRoZYNjmJHya34MfzqdfOwXkMDN2A=="

$loadBalancerIP = kubectl get svc traefik-ingress-service-public -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}' --ignore-not-found=true
if ([string]::IsNullOrWhiteSpace($loadBalancerIP)) {
    $loadBalancerIP = kubectl get svc traefik-ingress-service-private -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
}

Write-Output "To test out the NLP services, open Git Bash and run:"
Write-Output "curl -L --verbose --header 'Host: solr.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/solr' -k"
Write-Output "curl -L --verbose --header 'Host: nlp.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlpweb' -k"
Write-Output "curl -L --verbose --header 'Host: nlpjobs.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlp' -k"

Write-Output "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
Write-Output "$loadBalancerIP solr.$customerid.healthcatalyst.net"            
Write-Output "$loadBalancerIP nlp.$customerid.healthcatalyst.net"            
Write-Output "$loadBalancerIP nlpjobs.$customerid.healthcatalyst.net"            
