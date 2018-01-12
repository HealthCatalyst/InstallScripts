Write-output "Version 2017.12.20.2"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/setup-loadbalancer.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

$AKS_OPEN_TO_PUBLIC = ""
$AKS_USE_SSL = ""

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
    az login
}

$AKS_SUBSCRIPTION_ID = az account show --query "id" --output tsv

$AKS_PERS_RESOURCE_GROUP_BASE64 = kubectl get secret azure-secret -o jsonpath='{.data.resourcegroup}' --ignore-not-found=true
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

$AKS_PERS_LOCATION = az group show --name $AKS_PERS_RESOURCE_GROUP --query "location" -o tsv
Write-Output "Using location: [$AKS_PERS_LOCATION]"

Do { $AKS_OPEN_TO_PUBLIC = Read-Host "Do you want this cluster open to public? (y/n)"}
while ([string]::IsNullOrWhiteSpace($AKS_OPEN_TO_PUBLIC))

Do { $AKS_USE_SSL = Read-Host "Do you want to setup SSL? (y/n)"}
while ([string]::IsNullOrWhiteSpace($AKS_USE_SSL))

kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

# http://blog.kubernetes.io/2017/04/configuring-private-dns-zones-upstream-nameservers-kubernetes.html
kubectl delete -f "$GITHUB_URL/azure/cafe-kube-dns.yml" --ignore-not-found=true
Start-Sleep -Seconds 10
kubectl create -f "$GITHUB_URL/azure/cafe-kube-dns.yml"
# to debug dns: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#inheriting-dns-from-the-node

if ($AKS_USE_SSL -eq "y" ) {
    # ask for tls cert files
    Do { $AKS_SSL_CERT_FOLDER = Read-Host "What folder has the tls.crt and tls.key files? (absolute path e.g., c:\temp\certs)"}
    while ([string]::IsNullOrWhiteSpace($AKS_SSL_CERT_FOLDER) -or (!(Test-Path -Path "$AKS_SSL_CERT_FOLDER")))
      
    $AKS_SSL_CERT_FOLDER_UNIX_PATH = (($AKS_SSL_CERT_FOLDER -replace "\\", "/")).ToLower().Trim("/")    

    kubectl delete secret traefik-cert-ahmn -n kube-system

    Write-Output "Storing TLS certs as kubernetes secret"
    kubectl create secret generic traefik-cert-ahmn -n kube-system --from-file="$AKS_SSL_CERT_FOLDER_UNIX_PATH/tls.crt" --from-file="$AKS_SSL_CERT_FOLDER_UNIX_PATH/tls.key"

    Write-Output "Deploy the SSL ingress controller"
    # kubectl delete -f "$GITHUB_URL/azure/ingress.ssl.yml"
    kubectl create -f "$GITHUB_URL/azure/ingress.ssl.yml"
}
else {
    Write-Output "Deploy the non-SSL ingress controller"
    # kubectl delete -f "$GITHUB_URL/azure/ingress.yml"
    kubectl create -f "$GITHUB_URL/azure/ingress.yml"
}

if ("$AKS_OPEN_TO_PUBLIC" -eq "y") {
    Write-Output "Setting up a public load balancer"

    $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    if ([string]::IsNullOrWhiteSpace($publicip)) {
        az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --location $AKS_PERS_LOCATION --allocation-method Static
        $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    }  

    Write-Host "Using Public IP: [$publicip]"

    # kubectl delete svc traefik-ingress-service-public -n kube-system
    $serviceyaml = @"
kind: Service
apiVersion: v1
metadata:
  name: traefik-ingress-service-public
  namespace: kube-system
  labels:
    k8s-traefik: traefik    
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
    - protocol: TCP
      port: 80
      name: web
    - protocol: TCP
      port: 443
      name: ssl      
  type: LoadBalancer
  # Special notes for Azure: To use user-specified public type loadBalancerIP, a static type public IP address resource needs to be created first, 
  # and it should be in the same resource group of the cluster. 
  # note that in the case of AKS, that resource group is MC_<resourcegroup>_<cluster>
  # Then you could specify the assigned IP address as loadBalancerIP
  # https://kubernetes.io/docs/concepts/services-networking/service/#type-loadbalancer
  loadBalancerIP: $publicip
---
"@

    Write-Output $serviceyaml | kubectl create -f -
    #kubectl create -f "$GITHUB_URL/azure/loadbalancer-public.yml"

    #kubectl patch service traefik-ingress-service-public --loadBalancerIP=52.191.114.120

    #kubectl patch deployment traefik-ingress-controller -p '{"spec":{"loadBalancerIP":"52.191.114.120"}}'    
}
else {
    Write-Output "Setting up a private load balancer"
    kubectl create -f "$GITHUB_URL/azure/loadbalancer-internal.yml"
}

$startDate = Get-Date
$timeoutInMinutes = 10

if ("$AKS_OPEN_TO_PUBLIC" -eq "y") {
    $loadbalancer = "traefik-ingress-service-public"
}
else {
    $loadbalancer = "traefik-ingress-service-private"    
}

Write-Output "Waiting for IP to get assigned to the load balancer (Note: It can take 5 minutes or so to get the IP from azure)"
Do { 
    Start-Sleep -Seconds 10
    Write-Output "."
    $EXTERNAL_IP = $(kubectl get svc $loadbalancer -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}')
}
while ([string]::IsNullOrWhiteSpace($EXTERNAL_IP) -and ($startDate.AddMinutes($timeoutInMinutes) -gt (Get-Date)))

Write-Output "External IP: $EXTERNAL_IP"
Write-Output "To test out the load balancer, open Git Bash and run:"
Write-Output "curl -L --verbose --header 'Host: traefik-ui.minikube' 'http://$EXTERNAL_IP/'"





