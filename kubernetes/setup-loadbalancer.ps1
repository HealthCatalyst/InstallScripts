Write-output "Version 2018.03.27.01"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/setup-loadbalancer.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "C:\Catalyst\git\Installscripts"

Write-Host "GITHUB_URL: $GITHUB_URL"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

$config = $(ReadConfigFile).Config
Write-Host $config

$AKS_IP_WHITELIST = ""

$userInfo = $(GetLoggedInUserInfo)
# $AKS_SUBSCRIPTION_ID = $userInfo.AKS_SUBSCRIPTION_ID
# $IS_CAFE_ENVIRONMENT = $userInfo.IS_CAFE_ENVIRONMENT

$AKS_PERS_RESOURCE_GROUP = $config.azure.resourceGroup
$AKS_PERS_LOCATION = $config.azure.location

# Get location name from resource group
$AKS_PERS_LOCATION = az group show --name $AKS_PERS_RESOURCE_GROUP --query "location" -o tsv
Write-Output "Using location: [$AKS_PERS_LOCATION]"

$customerid = $config.customerid
$customerid = $customerid.ToLower().Trim()
Write-Output "Customer ID: $customerid"

$ingressExternal = $config.ingress.external
$ingressInternal = $config.ingress.internal
$AKS_IP_WHITELIST = $config.ingress.external_ip_whitelist

# read the vnet and subnet info from kubernetes secret
$AKS_VNET_NAME = $config.networking.vnet
$AKS_SUBNET_NAME = $config.networking.subnet
$AKS_SUBNET_RESOURCE_GROUP = $config.networking.subnet_resource_group

Write-Output "Found vnet info from secret: vnet: $AKS_VNET_NAME, subnet: $AKS_SUBNET_NAME, subnetResourceGroup: $AKS_SUBNET_RESOURCE_GROUP"

if ($ingressExternal -eq "whitelist") {
    Write-Output "Whitelist: $AKS_IP_WHITELIST"

    SaveSecretValue -secretname whitelistip -valueName iprange -value "${AKS_IP_WHITELIST}"
}

Write-Output "Setting up Network Security Group for the subnet"

# setup network security group
$AKS_PERS_NETWORK_SECURITY_GROUP = "$($AKS_PERS_RESOURCE_GROUP.ToLower())-nsg"

if ([string]::IsNullOrWhiteSpace($(az network nsg show -g $AKS_PERS_RESOURCE_GROUP -n $AKS_PERS_NETWORK_SECURITY_GROUP))) {

    Write-Output "Creating the Network Security Group for the subnet"
    az network nsg create -g $AKS_PERS_RESOURCE_GROUP -n $AKS_PERS_NETWORK_SECURITY_GROUP --query "provisioningState"
}
else {
    Write-Output "Network Security Group already exists: $AKS_PERS_NETWORK_SECURITY_GROUP"
}

if ($($config.network_security_group.create_nsg_rules)) {
    Write-Output "Adding or updating rules to Network Security Group for the subnet"
    $sourceTagForAdminAccess = "VirtualNetwork"
    if($($config.allow_kubectl_from_outside_vnet)){
        $sourceTagForAdminAccess = "Internet"
        Write-Output "Enabling admin access to cluster from Internet"
    }

    $sourceTagForHttpAccess = "Internet"
    if (![string]::IsNullOrWhiteSpace($AKS_IP_WHITELIST)) {
        $sourceTagForHttpAccess = $AKS_IP_WHITELIST
    }

    DeleteNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP -rulename "HttpPort"
    DeleteNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP -rulename "HttpsPort"

    SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
        -rulename "allow_kube_tls" `
        -ruledescription "allow kubectl and HTTPS access from ${sourceTagForAdminAccess}." `
        -sourceTag "${sourceTagForAdminAccess}" -port 443 -priority 100 

    SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
        -rulename "allow_http" `
        -ruledescription "allow HTTP access from ${sourceTagForAdminAccess}." `
        -sourceTag "${sourceTagForAdminAccess}" -port 80 -priority 101
            
    SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
        -rulename "allow_ssh" `
        -ruledescription "allow SSH access from ${sourceTagForAdminAccess}." `
        -sourceTag "${sourceTagForAdminAccess}" -port 22 -priority 104

    SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
        -rulename "allow_mysql" `
        -ruledescription "allow MySQL access from ${sourceTagForAdminAccess}." `
        -sourceTag "${sourceTagForAdminAccess}" -port 3306 -priority 205
            
    # if we already have opened the ports for admin access then we're not allowed to add another rule for opening them
    if (($sourceTagForHttpAccess -eq "Internet") -and ($sourceTagForAdminAccess -eq "Internet")) {
        Write-Output "Since we already have rules open port 80 and 443 to the Internet, we do not need to create separate ones for the Internet"
    }
    else {
        if($($config.ingress.external) -ne "vnetonly"){
            SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
                -rulename "HttpPort" `
                -ruledescription "allow HTTP access from ${sourceTagForHttpAccess}." `
                -sourceTag "${sourceTagForHttpAccess}" -port 80 -priority 500
    
            SetNetworkSecurityGroupRule -resourceGroup $AKS_PERS_RESOURCE_GROUP -networkSecurityGroup $AKS_PERS_NETWORK_SECURITY_GROUP `
                -rulename "HttpsPort" `
                -ruledescription "allow HTTPS access from ${sourceTagForHttpAccess}." `
                -sourceTag "${sourceTagForHttpAccess}" -port 443 -priority 501
        }
    }

    $nsgid = az network nsg list --resource-group ${AKS_PERS_RESOURCE_GROUP} --query "[?name == '${AKS_PERS_NETWORK_SECURITY_GROUP}'].id" -o tsv
    Write-Output "Found ID for ${AKS_PERS_NETWORK_SECURITY_GROUP}: $nsgid"

    Write-Output "Setting NSG into subnet"
    az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --network-security-group "$nsgid" --query "provisioningState" -o tsv
}

# delete existing containers
kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true


# set Google DNS servers to resolve external  urls
# http://blog.kubernetes.io/2017/04/configuring-private-dns-zones-upstream-nameservers-kubernetes.html
kubectl delete -f "$GITHUB_URL/kubernetes/loadbalancer/dns/upstream.yaml" --ignore-not-found=true
Start-Sleep -Seconds 10
kubectl create -f "$GITHUB_URL/kubernetes/loadbalancer/dns/upstream.yaml"
# to debug dns: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#inheriting-dns-from-the-node

kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

if ($($config.ssl) ) {
    # if the SSL cert is not set in kube secrets then ask for the files
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret traefik-cert-ahmn -o jsonpath='{.data}' -n kube-system --ignore-not-found=true))) {
        # ask for tls cert files
        Do { $AKS_SSL_CERT_FOLDER = Read-Host "What folder has the tls.crt and tls.key files? (absolute path e.g., c:\temp\certs)"}
        while ([string]::IsNullOrWhiteSpace($AKS_SSL_CERT_FOLDER) -or (!(Test-Path -Path "$AKS_SSL_CERT_FOLDER")))
      
        $AKS_SSL_CERT_FOLDER_UNIX_PATH = (($AKS_SSL_CERT_FOLDER -replace "\\", "/")).ToLower().Trim("/")    

        kubectl delete secret traefik-cert-ahmn -n kube-system --ignore-not-found=true

        Write-Output "Storing TLS certs as kubernetes secret"
        kubectl create secret generic traefik-cert-ahmn -n kube-system --from-file="$AKS_SSL_CERT_FOLDER_UNIX_PATH/tls.crt" --from-file="$AKS_SSL_CERT_FOLDER_UNIX_PATH/tls.key"
    }
}

Write-Host "GITHUB_URL: $GITHUB_URL"

# setting up traefik
# https://github.com/containous/traefik/blob/master/docs/user-guide/kubernetes.md

Write-Host "Deploying configmaps"
$folder = "kubernetes/loadbalancer/configmaps"
if ($($config.ssl)) {
    $files = "config.ssl.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid
}
else {
    $files = "config.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid
}

$kubectlversion = $(kubectl version --short=true)[1]
if ($kubectlversion -match "v1.8") {
    Write-Host "Since kubectlversion ($kubectlversion) is less than 1.9 no roles are needed"
}
else {
    Write-Host "Deploying roles"
    $folder = "kubernetes/loadbalancer/roles"
    $files = "ingress-roles.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid
}

Write-Host "Deploying pods"
$folder = "kubernetes/loadbalancer/pods"

if ($($config.ingress.internal) -eq "public" ) {
    $files = "ingress-azure.both.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid
}
else {
    if ($($config.ssl) ) {
        $files = "ingress-azure.ssl.yaml ingress-azure.internal.ssl.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid
    }
    else {
        $files = "ingress-azure.yaml ingress-azure.internal.yaml"
        DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid
    }    
}

Write-Host "Deploying services"
$folder = "kubernetes/loadbalancer/services/cluster"
$files = "dashboard.yaml dashboard-internal.yaml"
DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid

Write-Host "Deploying ingress"
$folder = "kubernetes/loadbalancer/ingress"

if ($($config.ssl) ) {
    $files = "dashboard.ssl.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid
}
else {
    $files = "dashboard.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid
}

$folder = "kubernetes/loadbalancer/services/external"

if ("$($config.ingress.external)" -ne "vnetonly") {
    Write-Output "Setting up a public load balancer"

    $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    if ([string]::IsNullOrWhiteSpace($publicip)) {
        az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --location $AKS_PERS_LOCATION --allocation-method Static
        $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    }  

    Write-Host "Using Public IP: [$publicip]"

    Write-Output "Setting up external load balancer"
    $files = "loadbalancer.external.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid -public_ip $publicip
}
else {
    Write-Output "Setting up an external load balancer"
    $files = "loadbalancer.external.restricted.yaml"
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid -public_ip $publicip
}

if ($($config.ingress.internal) -ne "public" ) {
    Write-Output "Setting up an internal load balancer"
    if ("$($config.ingress.internal)" -eq "public") {
        $files = "loadbalancer.internal.open.yaml"
    }
    else {
        $files = "loadbalancer.internal.yaml"

    }
    DownloadAndDeployYamlFiles -folder $folder -files $files -baseUrl $GITHUB_URL -customerid $customerid -public_ip $publicip
}

$loadBalancerIPResult = GetLoadBalancerIPs
$EXTERNAL_IP = $loadBalancerIPResult.ExternalIP
$INTERNAL_IP = $loadBalancerIPResult.InternalIP

FixLoadBalancers -resourceGroup $AKS_PERS_RESOURCE_GROUP

$dnsrecordname = $($config.dns.name)

SaveSecretValue -secretname "dnshostname" -valueName "value" -value $dnsrecordname

if ($($config.dns.create_dns_entries)) {
    SetupDNS -dnsResourceGroup $DNS_RESOURCE_GROUP -dnsrecordname $dnsrecordname -externalIP $EXTERNAL_IP 
}
else {
    Write-Output "To access the urls from your browser, add the following entries in your c:\windows\system32\drivers\etc\hosts file"
    Write-Output "$EXTERNAL_IP $dnsrecordname"
}


