Write-Output "Version 2018.01.21.01"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

$loggedInUser = az account show --query "user.name"  --output tsv

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

Do { $AKS_USE_SSL = Read-Host "Do you want to setup SSL? (y/n)"}
while ([string]::IsNullOrWhiteSpace($AKS_USE_SSL))



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

ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/realtime-kubernetes-storage.yml" -customerid $customerid | kubectl create -f -

ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/realtime-kubernetes.yml" -customerid $customerid | kubectl create -f -

ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "realtime/realtime-kubernetes-public.yml" -customerid $customerid | kubectl create -f -

$ipname = "InterfaceEnginePublicIP"
$publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n $ipname --query "ipAddress" -o tsv;
if ([string]::IsNullOrWhiteSpace($publicip)) {
    az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n $ipname --allocation-method Static
    $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n $ipname --query "ipAddress" -o tsv;
} 
Write-Host "Using Interface Engine Public IP: [$publicip]"

# Write-Output "Checking if DNS entries exist"
# https://kubernetes.io/docs/reference/kubectl/jsonpath/

# setup DNS
# az network dns zone create -g $AKS_PERS_RESOURCE_GROUP -n nlp.allina.healthcatalyst.net
# az network dns record-set a add-record --ipv4-address j `
#                                        --record-set-name nlp.allina.healthcatalyst.net `
#                                        --resource-group $AKS_PERS_RESOURCE_GROUP `
#                                        --zone-name 

$serviceyaml = @"
kind: Service
apiVersion: v1
metadata:
  name: interfaceengine-direct-port
  namespace: fabricrealtime
spec:
  selector:
    app: interfaceengine
  ports:
  - name: interfaceengine
    protocol: TCP
    port: 6661
    targetPort: 6661
  type: LoadBalancer  
  # Special notes for Azure: To use user-specified public type loadBalancerIP, a static type public IP address resource needs to be created first, 
  # and it should be in the same resource group of the cluster. 
  # Then you could specify the assigned IP address as loadBalancerIP
  # https://kubernetes.io/docs/concepts/services-networking/service/#type-loadbalancer
  loadBalancerIP: $publicip
---
"@

Write-Output $serviceyaml | kubectl create -f -

AskForSecretValue -secretname "customerid" -prompt "Health Catalyst Customer ID (e.g., ahmn)" -namespace "fabricrealtime"

$customeridbase64 = kubectl get secret customerid -n fabricrealtime -o jsonpath='{.data.value}'
$customerid = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($customeridbase64))
Write-Output "Customer ID:" $customerid

$templateFile = "realtime/realtime-ingress.yml"
if ($AKS_USE_SSL -eq "y" ) {
    $templateFile = "realtime/realtime-ingress-ssl.yml"    
}

Write-Output "Using template: $templateFile"

ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile $templateFile -customerid $customerid

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide

# to get a shell
# kubectl exec -it fabric.nlp.nlpwebserver-85c8cb86b5-gkphh bash --namespace=fabricrealtime

# kubectl create secret generic azure-secret --namespace=fabricrealtime --from-literal=azurestorageaccountname="fabricrealtime7storage" --from-literal=azurestorageaccountkey="/bYhXNstTodg3MdOvTMog/vDLSFrQDpxG/Zgkp2MlnjtOWhDBNQ2xOs6zjRoZYNjmJHya34MfzqdfOwXkMDN2A=="

Write-Output "To get status of Fabric.NLP run:"
Write-Output "kubectl get deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes --namespace=fabricrealtime -o wide"

Write-Output "To launch the dashboard UI, run:"
Write-Output "kubectl proxy"
Write-Output "and then in your browser, navigate to: http://127.0.0.1:8001/ui"

$loadBalancerIP = kubectl get svc traefik-ingress-service-public -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
if ([string]::IsNullOrWhiteSpace($loadBalancerIP)) {
    $loadBalancerIP = kubectl get svc traefik-ingress-service-internal -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
}

Write-Output "To test out the NLP services, open Git Bash and run:"
Write-Output "curl -L --verbose --header 'Host: certificates.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/client'"

Write-Output "Connect to interface engine at: $publicip port 6661"

Write-Output "if you want, you can download the CA (Certificate Authority) cert from this url"
Write-Output "http://certificates.$customerid.healthcatalyst.net/client/fabric_ca_cert.p12"

Write-Output "-------------------------------"
Write-Output "you can download the client certificate from this url:"
Write-Output "http://certificates.$customerid.healthcatalyst.net/client/fabricrabbitmquser_client_cert.p12"
Write-Output "-------------------------------"

Write-Output "Waiting for load balancer IP to get assigned to interface engine..."
Do {
    $loadBalancerIP = $(kubectl get service interfaceengine-direct-port -n fabricrealtime -o jsonpath='{.spec.loadBalancerIP}');
    Write-Output "."
    Start-Sleep -Seconds 5
}
while ([string]::IsNullOrWhiteSpace($loadBalancerIP))

Write-Output "Load Balancer IP: $loadBalancerIP"
