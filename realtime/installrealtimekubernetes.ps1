Write-Output "Version 2018.01.09.1"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

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
$AKS_PERS_RESOURCE_GROUP = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AKS_PERS_RESOURCE_GROUP_BASE64))

if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
    Do { $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group (e.g., fabricnlp-rg)"}
    while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
}
else {
    Write-Output "Using resource group: $AKS_PERS_RESOURCE_GROUP"        
}

if ([string]::IsNullOrWhiteSpace($(kubectl get namespace fabricrealtime))) {
    kubectl create namespace fabricrealtime
}

Do { $AKS_USE_SSL = Read-Host "Do you want to setup SSL? (y/n)"}
while ([string]::IsNullOrWhiteSpace($AKS_USE_SSL))

function AskForPassword ($secretname, $prompt, $namespace) {
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.password}'))) {

        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        Do {
            $mysqlrootpasswordsecure = Read-host "$prompt" -AsSecureString 
            $mysqlrootpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlrootpasswordsecure))
        }
        while (($mysqlrootpassword -notmatch "^[a-z0-9!.*@\s]+$") -or ($mysqlrootpassword.Length -lt 8 ))
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Output "$secretname secret already set so will reuse it"
    }
}

function AskForSecretValue ($secretname, $prompt, $namespace) {
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.value}'))) {

        $certhostname = ""
        Do {
            $certhostname = Read-host "$prompt"
        }
        while ($certhostname.Length -lt 1 )
    
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$certhostname
    }
    else {
        Write-Output "$secretname secret already set so will reuse it"
    }    
}

AskForPassword -secretname "mysqlrootpassword"  -prompt "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricrealtime"

AskForPassword -secretname "mysqlpassword"  -prompt "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricrealtime"

AskForSecretValue -secretname "certhostname" -prompt "Client Certificate hostname" -namespace "fabricrealtime"

AskForPassword -secretname "certpassword"  -prompt "Client Certificate password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricrealtime"

AskForPassword -secretname "rabbitmqmgmtuipassword"  -prompt "Admin password for RabbitMqMgmt" -namespace "fabricrealtime"

Write-Output "Cleaning out any old resources in fabricrealtime"

# note kubectl doesn't like spaces in between commas below
kubectl delete --all 'deployments,pods,services,ingress,persistentvolumeclaims,persistentvolumes' --namespace=fabricrealtime

Write-Output "Waiting until all the resources are cleared up"

Do { $CLEANUP_DONE = $(kubectl get 'deployments,pods,services,ingress,persistentvolumeclaims,persistentvolumes' --namespace=fabricrealtime)}
while (![string]::IsNullOrWhiteSpace($CLEANUP_DONE))

$AKS_PERS_SHARE_NAME = "fabricrealtime"
$AKS_PERS_STORAGE_ACCOUNT_NAME_BASE64 = kubectl get secret azure-secret -o jsonpath='{.data.azurestorageaccountname}'
$AKS_PERS_STORAGE_ACCOUNT_NAME = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AKS_PERS_STORAGE_ACCOUNT_NAME_BASE64))

$AZURE_STORAGE_CONNECTION_STRING = az storage account show-connection-string -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $AKS_PERS_RESOURCE_GROUP -o tsv

Write-Output "Create the file share: $AKS_PERS_SHARE_NAME"
az storage share create -n $AKS_PERS_SHARE_NAME --connection-string $AZURE_STORAGE_CONNECTION_STRING --quota 512

kubectl create -f $GITHUB_URL/realtime/realtime-kubernetes-storage.yml

kubectl create -f $GITHUB_URL/realtime/realtime-kubernetes.yml

kubectl create -f $GITHUB_URL/realtime/realtime-kubernetes-public.yml

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

$templateFile="realtime-ingress.yml"
if ($AKS_USE_SSL -eq "y" ){
    $templateFile="realtime-ingress-ssl.yml"    
}

Write-Output "Using template: $templateFile"

if ($GITHUB_URL.StartsWith("http")) { 
    Invoke-WebRequest -Uri "$GITHUB_URL/realtime/$templateFile" -ContentType "text/plain; charset=utf-8" `
    | Select-Object -Expand Content `
    | Foreach-Object {$_ -replace 'CUSTOMERID', "${customerid}"} `
    | kubectl create -f -
}
else {
    Get-Content -Path "$GITHUB_URL/realtime/$templateFile" `
        | Foreach-Object {$_ -replace 'CUSTOMERID', "${customerid}"} `
        | kubectl create -f -    
}

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
    $loadBalancerIP = kubectl get svc traefik-ingress-service-private -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
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
