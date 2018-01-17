Write-Output "Version 2018.01.17.1"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | iex;
$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/common.ps1 | Invoke-Expression;

$loggedInUser = az account show --query "user.name"  --output tsv
$AKS_USE_SSL = ""

Write-Output "user: $loggedInUser"

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

Do { $AKS_USE_SSL = Read-Host "Do you want to setup SSL? (y/n)"}
while ([string]::IsNullOrWhiteSpace($AKS_USE_SSL))

# https://kubernetes.io/docs/reference/kubectl/jsonpath/

# setup DNS
# az network dns zone create -g $AKS_PERS_RESOURCE_GROUP -n nlp.allina.healthcatalyst.net
# az network dns record-set a add-record --ipv4-address j `
#                                        --record-set-name nlp.allina.healthcatalyst.net `
#                                        --resource-group $AKS_PERS_RESOURCE_GROUP `
#                                        --zone-name 

$AKS_PERS_SHARE_NAME = "fabricnlp"

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

CreateShare -resourceGroup $AKS_PERS_RESOURCE_GROUP -sharename $AKS_PERS_SHARE_NAME

if ([string]::IsNullOrWhiteSpace($(kubectl get namespace fabricnlp --ignore-not-found=true))) {
    kubectl create namespace fabricnlp
}
else {
    Do { $deleteSecrets = Read-Host "Namespace exists.  Do you want to delete passwords and ALL data stored in this namespace? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($deleteSecrets))    
    
    if ($deleteSecrets -eq "y" ) {
        kubectl delete secret mysqlrootpassword -n fabricnlp --ignore-not-found=true
        kubectl delete secret mysqlpassword -n fabricnlp --ignore-not-found=true
        kubectl delete secret smtprelaypassword -n fabricnlp --ignore-not-found=true
               
        # need to recreate the file share when we change passwords otherwise the new password will not work with the old password stored in the share
        CreateShare -resourceGroup $AKS_PERS_RESOURCE_GROUP -sharename $AKS_PERS_SHARE_NAME -deleteExisting true
    }
}


AskForSecretValue -secretname "customerid" -prompt "Health Catalyst Customer ID (e.g., ahmn)"

$customerid = ReadSecret -secretname customerid
$customerid = $customerid.ToLower().Trim()
Write-Output "Customer ID: $customerid"

AskForPassword -secretname "mysqlrootpassword" -prompt "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricnlp"
# MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
# we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script

AskForPassword -secretname "mysqlpassword" -prompt "MySQL NLP_APP_USER password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricnlp"

AskForPasswordAnyCharacters -secretname "smtprelaypassword" -prompt "SMTP (SendGrid) Relay Key" -namespace "fabricnlp" 

Write-Output "Cleaning out any old resources in fabricnlp"

# note kubectl doesn't like spaces in between commas below
kubectl delete --all 'deployments,pods,services,ingress,persistentvolumeclaims,persistentvolumes' --namespace=fabricnlp --ignore-not-found=true

Write-Output "Waiting until all the resources are cleared up"

Do { $CLEANUP_DONE = $(kubectl get 'deployments,pods,services,ingress,persistentvolumeclaims,persistentvolumes' --namespace=fabricnlp)}
while (![string]::IsNullOrWhiteSpace($CLEANUP_DONE))

ReadYmlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/nlp-kubernetes-storage.yml" -customerid $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/nlp-kubernetes.yml" -customerid $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/nlp-kubernetes-public.yml" -customerid $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "nlp/nlp-mysql-private.yml" -customerid $customerid | kubectl create -f -

Write-Output "Setting up SSL reverse proxy"

$ingressTemplate = "nlp/nlp-ingress.yml"
if ($AKS_USE_SSL -eq "y" ) {
    $ingressTemplate = "nlp/nlp-ingress-ssl.yml"
}

ReadYmlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile $ingressTemplate -customerid $customerid | kubectl create -f -

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide

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
