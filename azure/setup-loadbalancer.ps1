Write-output "Version 2018.02.20.02"

#
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/setup-loadbalancer.ps1 | iex;

# $GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
$GITHUB_URL = "C:\Catalyst\git\Installscripts"

# Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/common.ps1 | Invoke-Expression;
Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

$AKS_OPEN_TO_PUBLIC = ""
$AKS_USE_SSL = ""
$AKS_IP_WHITELIST = ""

$loggedInUser = az account show --query "user.name"  --output tsv

Write-Output "user: $loggedInUser"

# choose Azure login and subscription
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

# Get resource group name from kube secrets
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

# Get location name from resource group
$AKS_PERS_LOCATION = az group show --name $AKS_PERS_RESOURCE_GROUP --query "location" -o tsv
Write-Output "Using location: [$AKS_PERS_LOCATION]"

$customerid = ReadSecret -secretname customerid
$customerid = $customerid.ToLower().Trim()
Write-Output "Customer ID: $customerid"

# Ask input from user
Do { 
    Write-Host "How do you want to control access to this cluster:"
    Write-Host "1: Allow anyone to access it"
    Write-Host "2: Only allow certain IP ranges to access it"
    Write-Host "3: Only allow computers inside the subnet to access it"
    Write-Host "-------------"

    $AKS_CLUSTER_ACCESS_TYPE = Read-Host "Enter number of option to use (1 - 3)"
}
while ([string]::IsNullOrWhiteSpace($AKS_CLUSTER_ACCESS_TYPE))  

# read the vnet and subnet info from kubernetes secret
$AKS_VNET_NAME = ReadSecretValue -secretname azure-vnet -valueName "vnet"
$AKS_SUBNET_NAME = ReadSecretValue -secretname azure-vnet -valueName "subnet"
$AKS_SUBNET_RESOURCE_GROUP = ReadSecretValue -secretname azure-vnet -valueName "subnetResourceGroup"

Write-Output "Found vnet info from secret: vnet: $AKS_VNET_NAME, subnet: $AKS_SUBNET_NAME, subnetResourceGroup: $AKS_SUBNET_RESOURCE_GROUP"

$AKS_ALLOW_ADMIN_ACCESS_OUTSIDE_VNET = Read-Host "Do you want to allow admin access to this cluster from outside the vnet: ${AKS_VNET_NAME}? (y/n) (default: n)"

if ([string]::IsNullOrWhiteSpace($AKS_ALLOW_ADMIN_ACCESS_OUTSIDE_VNET)) {
    $AKS_ALLOW_ADMIN_ACCESS_OUTSIDE_VNET = "n"
}

$AKS_IP_WHITELIST = ""
if ($AKS_CLUSTER_ACCESS_TYPE -eq "2") {

    $currentWhitelistIP = ReadSecretValue -secretname whitelistip -valueName iprange

    Do { 
        if (![string]::IsNullOrWhiteSpace($currentWhitelistIP)) {
            $AKS_IP_WHITELIST = Read-Host "Enter IP range that should be able to access this cluster: ( ex: 127.0.0.1/32 192.168.1.7. separate multiple IPs by a space.) (default: $currentWhitelistIP)"
            if ([string]::IsNullOrWhiteSpace($AKS_IP_WHITELIST)) {
                $AKS_IP_WHITELIST = $currentWhitelistIP
            }    
        }
        else {
            $AKS_IP_WHITELIST = Read-Host "Enter IP range that should be able to access this cluster: ( ex: 127.0.0.1/32 192.168.1.7. separate multiple IPs by a space.)"            
        }
    }
    while ([string]::IsNullOrWhiteSpace($AKS_IP_WHITELIST))

    # $AKS_IP_WHITELIST_ITEMS = $AKS_IP_WHITELIST.split(" ")

    # $WHITELIST = ""

    # foreach ($cidr in $AKS_IP_WHITELIST_ITEMS) {
    #     if (![string]::IsNullOrWhiteSpace($WHITELIST)) {
    #         $WHITELIST = "${WHITELIST} "
    #     }
    #     $WHITELIST = "${WHITELIST}${cidr}"
    # }

    # $AKS_IP_WHITELIST = "$WHITELIST"
    Write-Output "Whitelist: $AKS_IP_WHITELIST"

    SaveSecretValue -secretname whitelistip -valueName iprange -value "${AKS_IP_WHITELIST}"
}

$AKS_USE_WAF = "n"
# $AKS_USE_WAF = Read-Host "Do you want to use Azure Application Gateway with WAF? (y/n) (default: n)"

# if ([string]::IsNullOrWhiteSpace($AKS_USE_WAF)) {
#     $AKS_USE_WAF = "n"
# }

if ([string]::IsNullOrWhiteSpace($(kubectl get secret traefik-cert-ahmn -o jsonpath='{.data}' -n kube-system --ignore-not-found=true))) {
    Do { $AKS_USE_SSL = Read-Host "Do you want to setup SSL? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($AKS_USE_SSL))
}
else {
    $AKS_USE_SSL = "y"
    Write-Output "SSL cert already stored as secret (traefik-cert-ahmn) so setting up SSL"
}

Do { $SETUP_DNS = Read-Host "Do you want to setup DNS entries in Azure? (y/n)"}
while ([string]::IsNullOrWhiteSpace($SETUP_DNS))

# if we need to setup DNS then ask which resourceGroup to use
if ($SETUP_DNS -eq "y") {
    $DNS_RESOURCE_GROUP = Read-Host "Resource group containing DNS zones? (default: dns)"
    if ([string]::IsNullOrWhiteSpace($DNS_RESOURCE_GROUP)) {
        $DNS_RESOURCE_GROUP = "dns"
    }
}


Write-Output "Setting up Network Security Group for the subnet"

# setup network security group
$AKS_PERS_NETWORK_SECURITY_GROUP = "$($AKS_PERS_RESOURCE_GROUP.ToLower())-nsg"

if ([string]::IsNullOrWhiteSpace($(az network nsg show -g $AKS_PERS_RESOURCE_GROUP -n $AKS_PERS_NETWORK_SECURITY_GROUP))) {

    Write-Output "Creating the Network Security Group for the subnet"
    az network nsg create -g $AKS_PERS_RESOURCE_GROUP -n $AKS_PERS_NETWORK_SECURITY_GROUP
}
else {
    Write-Output "Network Security Group already exists: $AKS_PERS_NETWORK_SECURITY_GROUP"
}

Write-Output "Adding or updating rules to Network Security Group for the subnet"
$sourceTagForAdminAccess = "VirtualNetwork"
if ($AKS_ALLOW_ADMIN_ACCESS_OUTSIDE_VNET -eq "y") {
    $sourceTagForAdminAccess = "Internet"
    Write-Output "Enabling admin access to cluster from Internet"
}

$sourceTagForHttpAccess = "Internet"
if (![string]::IsNullOrWhiteSpace($AKS_IP_WHITELIST)) {
    $sourceTagForHttpAccess = $AKS_IP_WHITELIST
}

if (![string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpPort" --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Output "Deleting HttpPort rule so we can create it later"
    az network nsg rule delete -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n HttpPort
}

if (![string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpsPort" --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Output "Deleting HttpsPort rule so we can create it later"
    az network nsg rule delete -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n HttpsPort
}    

if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "allow_kube_tls" --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Output "Creating rule: allow_kube_tls"
    az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n allow_kube_tls --priority 100 `
        --source-address-prefixes "${sourceTagForAdminAccess}" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
        --protocol Tcp --description "allow kubectl and HTTPS access from ${sourceTagForAdminAccess}." `
        --query "provisioningState" -o tsv
}
else {
    Write-Output "Updating rule: allow_kube_tls"

    az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n allow_kube_tls --priority 100 `
        --source-address-prefixes "${sourceTagForAdminAccess}" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
        --protocol Tcp --description "allow kubectl access and HTTPS from ${sourceTagForAdminAccess}." `
        --query "provisioningState" -o tsv
}
if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "allow_http" --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Output "Creating rule: allow_http"
    az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n allow_http --priority 101 `
        --source-address-prefixes "${sourceTagForAdminAccess}" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
        --protocol Tcp --description "allow HTTP access from ${sourceTagForAdminAccess}." `
        --query "provisioningState" -o tsv
}
else {
    Write-Output "Updating rule: allow_http"
    az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n allow_http --priority 101 `
        --source-address-prefixes "${sourceTagForAdminAccess}" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
        --protocol Tcp --description "allow HTTP access from ${sourceTagForAdminAccess}." `
        --query "provisioningState" -o tsv
}

if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "allow_ssh" --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Output "Creating rule: allow_ssh"
    az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n allow_ssh --priority 104 `
        --source-address-prefixes "${sourceTagForAdminAccess}" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow `
        --protocol Tcp --description "allow ssh access from ${sourceTagForAdminAccess}." `
        --query "provisioningState" -o tsv
}
else {
    Write-Output "Updating rule: allow_ssh"
    az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n allow_ssh --priority 104 `
        --source-address-prefixes "${sourceTagForAdminAccess}" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow `
        --protocol Tcp --description "allow ssh access from ${sourceTagForAdminAccess}." `
        --query "provisioningState" -o tsv
}

if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "mysql" --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
    Write-Output "Creating rule: mysql"
    az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n mysql --priority 205 `
        --source-address-prefixes "${sourceTagForAdminAccess}" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 3306 --access Allow `
        --protocol Tcp --description "allow mysql access from ${sourceTagForAdminAccess}." `
        --query "provisioningState" -o tsv
}
else {
    Write-Output "Updating rule: mysql"
    az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n mysql --priority 205 `
        --source-address-prefixes "${sourceTagForAdminAccess}" --source-port-ranges '*' `
        --destination-address-prefixes '*' --destination-port-ranges 3306 --access Allow `
        --protocol Tcp --description "allow mysql access from ${sourceTagForAdminAccess}." `
        --query "provisioningState" -o tsv
}

# if we already have opened the ports for admin access then we're not allowed to add another rule for opening them
if (($sourceTagForHttpAccess -eq "Internet") -and ($sourceTagForAdminAccess -eq "Internet")) {
    Write-Output "Since we already have rules open port 80 and 443 to the Internet, we do not need to create separate ones for the Internet"
}
else {
    if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpPort" --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
        Write-Output "Creating rule: HttpPort"
        az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n HttpPort --priority 500 `
            --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
            --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
            --protocol Tcp --description "allow HTTP access from $sourceTagForHttpAccess." `
            --query "provisioningState" -o tsv
    }
    else {
        Write-Output "Updating rule: HttpPort"
        az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n HttpPort --priority 500 `
            --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
            --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow `
            --protocol Tcp --description "allow HTTP access from $sourceTagForHttpAccess." `
            --query "provisioningState" -o tsv
    }

    if ([string]::IsNullOrWhiteSpace($(az network nsg rule show --name "HttpsPort" --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP --resource-group $AKS_PERS_RESOURCE_GROUP))) {
        Write-Output "Creating rule: HttpsPort"
        az network nsg rule create -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n HttpsPort --priority 501 `
            --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
            --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
            --protocol Tcp --description "allow HTTPS access from $sourceTagForHttpAccess." `
            --query "provisioningState" -o tsv
    }
    else {
        Write-Output "Updating rule: HttpsPort"
        az network nsg rule update -g $AKS_PERS_RESOURCE_GROUP --nsg-name $AKS_PERS_NETWORK_SECURITY_GROUP -n HttpsPort --priority 501 `
            --source-address-prefixes "$sourceTagForHttpAccess" --source-port-ranges '*' `
            --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow `
            --protocol Tcp --description "allow HTTPS access from $sourceTagForHttpAccess." `
            --query "provisioningState" -o tsv
    }    
}

$nsgid = az network nsg list --resource-group ${AKS_PERS_RESOURCE_GROUP} --query "[?name == '${AKS_PERS_NETWORK_SECURITY_GROUP}'].id" -o tsv
Write-Output "Found ID for ${AKS_PERS_NETWORK_SECURITY_GROUP}: $nsgid"

Write-Output "Setting NSG into subnet"
az network vnet subnet update -n "${AKS_SUBNET_NAME}" -g "${AKS_SUBNET_RESOURCE_GROUP}" --vnet-name "${AKS_VNET_NAME}" --network-security-group "$nsgid" --query "provisioningState" -o tsv

# set up WAF if requested
if ($AKS_USE_WAF -eq "n") {
    if (($AKS_CLUSTER_ACCESS_TYPE -eq "1" ) -or ($AKS_CLUSTER_ACCESS_TYPE -eq "2")) {
        $AKS_OPEN_TO_PUBLIC = "y"
    }
}
else {
    $AKS_OPEN_TO_PUBLIC = "n"
    $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    if ([string]::IsNullOrWhiteSpace($publicip)) {
        az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --location $AKS_PERS_LOCATION --allocation-method Static
        $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    }  

    Write-Host "Using Public IP: [$publicip]"
    # get vnet and subnet name
    Do { $confirmation = Read-Host "Would you like to connect the Azure WAF to an existing virtual network? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($confirmation))

    if ($confirmation -eq 'y') {
        Write-Output "Finding existing vnets..."
        # az network vnet list --query "[].[name,resourceGroup ]" -o tsv    

        $vnets = az network vnet list --query "[].[name]" -o tsv

        Do { 
            Write-Output "------  Existing vnets -------"
            for ($i = 1; $i -le $vnets.count; $i++) {
                Write-Host "$i. $($vnets[$i-1])"
            }    
            Write-Output "------  End vnets -------"

            $index = Read-Host "Enter number of vnet to use (1 - $($vnets.count))"
            $AKS_VNET_NAME = $($vnets[$index - 1])
        }
        while ([string]::IsNullOrWhiteSpace($AKS_VNET_NAME))    

        if ("$AKS_VNET_NAME") {
        
            # Do { $AKS_SUBNET_RESOURCE_GROUP = Read-Host "Resource Group of Virtual Network"}
            # while ([string]::IsNullOrWhiteSpace($AKS_SUBNET_RESOURCE_GROUP)) 

            $AKS_SUBNET_RESOURCE_GROUP = az network vnet list --query "[?name == '$AKS_VNET_NAME'].resourceGroup" -o tsv
            Write-Output "Using subnet resource group: [$AKS_SUBNET_RESOURCE_GROUP]"

            Write-Output "Finding existing subnets in $AKS_VNET_NAME ..."
            $subnets = az network vnet subnet list --resource-group $AKS_SUBNET_RESOURCE_GROUP --vnet-name $AKS_VNET_NAME --query "[].name" -o tsv
        
            Do { 
                Write-Output "------  Subnets in $AKS_VNET_NAME -------"
                for ($i = 1; $i -le $subnets.count; $i++) {
                    Write-Host "$i. $($subnets[$i-1])"
                }    
                Write-Output "------  End Subnets -------"

                Write-Host "NOTE: Each customer should have their own gateway subnet.  This subnet should be different than the cluster subnet"
                $index = Read-Host "Enter number of subnet to use (1 - $($subnets.count))"
                $AKS_SUBNET_NAME = $($subnets[$index - 1])
            }
            while ([string]::IsNullOrWhiteSpace($AKS_SUBNET_NAME)) 

        }
    }  

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

if ($AKS_USE_SSL -eq "y" ) {
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

Write-Host "Deploying configmaps"
$folder = "kubernetes/loadbalancer/configmaps"
if ($AKS_USE_SSL -eq "y" ) {
    foreach ($file in "config.ssl.yaml".Split(" ")) { 
        ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
    }
}
else {
    foreach ($file in "config.yaml".Split(" ")) { 
        Write-Host "$GITHUB_URL ${folder}/${file}"
        ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
    }
}
Write-Host "Deploying roles"
$folder = "kubernetes/loadbalancer/roles"
foreach ($file in "ingress-roles.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "Deploying pods"
$folder = "kubernetes/loadbalancer/pods"
if ($AKS_USE_SSL -eq "y" ) {
    foreach ($file in "ingress-azure.ssl.yaml".Split(" ")) { 
        ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
    }    
}
else {
    foreach ($file in "ingress-azure.yaml".Split(" ")) { 
        ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
    }
}
foreach ($file in "ingress-azure.internal.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "Deploying services"
$folder = "kubernetes/loadbalancer/services"
foreach ($file in "dashboard.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
}

Write-Host "Deploying ingress"
$folder = "kubernetes/loadbalancer/ingress"
if ($AKS_USE_SSL -eq "y" ) {
    foreach ($file in "dashboard.ssl.yaml".Split(" ")) { 
        ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
    }
}
else {
    foreach ($file in "dashboard.yaml".Split(" ")) { 
        ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
    }    
}
foreach ($file in "default.yaml default-internal.yaml".Split(" ")) { 
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
}    

if ("$AKS_OPEN_TO_PUBLIC" -eq "y") {
    Write-Output "Setting up a public load balancer"

    $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    if ([string]::IsNullOrWhiteSpace($publicip)) {
        az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --location $AKS_PERS_LOCATION --allocation-method Static
        $publicip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n IngressPublicIP --query "ipAddress" -o tsv;
    }  

    Write-Host "Using Public IP: [$publicip]"

    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "kubernetes/loadbalancer/services/loadbalancer-public.yaml" -customerid $customerid `
        | Foreach-Object {$_ -replace 'PUBLICIP', "$publicip"} `
        | kubectl create -f -


    if ($AKS_CLUSTER_ACCESS_TYPE -eq "2") {
        # if we are restricting IPs then also deploy an internal load balancer
        Write-Output "Setting up a internal load balancer also since we are restricting IPs"
        ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "kubernetes/loadbalancer/services/loadbalancer-internal.yaml" -customerid $customerid `
            | kubectl create -f -
          
    }
    #kubectl create -f "$GITHUB_URL/azure/loadbalancer-public.yaml"

    #kubectl patch service traefik-ingress-service-public --loadBalancerIP=52.191.114.120

    #kubectl patch deployment traefik-ingress-controller -p '{"spec":{"loadBalancerIP":"52.191.114.120"}}'    
}
else {
    Write-Output "Setting up an internal load balancer"
    ReadYamlAndReplaceCustomer -baseUrl $GITHUB_URL -templateFile "kubernetes/loadbalancer/services/loadbalancer-internal.yaml" -customerid $customerid `
    | kubectl create -f -
}

$startDate = Get-Date
$timeoutInMinutes = 10

if ("$AKS_OPEN_TO_PUBLIC" -eq "y") {
    $loadbalancer = "traefik-ingress-service-public"
}
else {
    $loadbalancer = "traefik-ingress-service-private"    
}

$INTERNAL_IP = ""

Write-Output "Waiting for IP to get assigned to the load balancer (Note: It can take upto 5 minutes for Azure to finish creating the load balancer)"
Do { 
    Start-Sleep -Seconds 10
    Write-Output "."
    $EXTERNAL_IP = $(kubectl get svc $loadbalancer -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}')
}
while ([string]::IsNullOrWhiteSpace($EXTERNAL_IP) -and ($startDate.AddMinutes($timeoutInMinutes) -gt (Get-Date)))
Write-Output "External IP: $EXTERNAL_IP"

if ($AKS_CLUSTER_ACCESS_TYPE -eq "2") {
    Write-Output "Waiting for IP to get assigned to the internal load balancer (Note: It can take upto 5 minutes for Azure to finish creating the load balancer)"
    Do { 
        Start-Sleep -Seconds 10
        Write-Output "."
        $INTERNAL_IP = $(kubectl get svc traefik-ingress-service-private -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}')
    }
    while ([string]::IsNullOrWhiteSpace($INTERNAL_IP) -and ($startDate.AddMinutes($timeoutInMinutes) -gt (Get-Date)))
    Write-Output "Internal IP: $INTERNAL_IP"
}


$dnsrecordname = "$customerid.healthcatalyst.net"

if ($AKS_USE_WAF -eq "y") {

    # $nsgname = "IngressNSG"
    # $iprangetoallow = ""
    # if ([string]::IsNullOrEmpty($(az network nsg show --name "$nsgname" --resource-group "$AKS_PERS_RESOURCE_GROUP" ))) {
    #     az network nsg create --name "$nsgname" --resource-group "$AKS_PERS_RESOURCE_GROUP"
    # }

    # if ([string]::IsNullOrEmpty($(az network nsg rule show --nsg-name "$nsgname" --name "IPFilter" --resource-group "$AKS_PERS_RESOURCE_GROUP" ))) {
    #     # Rule priority, between 100 (highest priority) and 4096 (lowest priority). Must be unique for each rule in the collection.
    #     # Space-separated list of CIDR prefixes or IP ranges. Alternatively, specify ONE of 'VirtualNetwork', 'AzureLoadBalancer', 'Internet' or '*' to match all IPs.
    #     az network nsg rule create --name "IPFilter" `
    #         --nsg-name "$nsgname" `
    #         --priority 220 `
    #         --resource-group "$AKS_PERS_RESOURCE_GROUP" `
    #         --description "IP Filtering" `
    #         --access "Allow" `
    #         --source-address-prefixes "$iprangetoallow"
    # }

    # Write-Output "Creating network security group to restrict IP address"

    Write-Output "Setting up Azure Application Gateway"

    $gatewayName = "${customerid}Gateway"

    az network application-gateway show --name "$gatewayName" --resource-group "$AKS_PERS_RESOURCE_GROUP"
    $gatewayipName = "${gatewayName}PublicIP"

    Write-Output "Checking if Application Gateway already exists"
    if ([string]::IsNullOrEmpty($(az network application-gateway show --name "$gatewayName" --resource-group "$AKS_PERS_RESOURCE_GROUP" ))) {

        # note application gateway provides no way to specify the resourceGroup of the vnet so we HAVE to create the App Gateway in the same resourceGroup
        # as the vnet and NOT in the resourceGroup of the cluster
        $gatewayip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n "$gatewayipName" --query "ipAddress" -o tsv;
        if ([string]::IsNullOrWhiteSpace($gatewayip)) {
            az network public-ip create -g $AKS_PERS_RESOURCE_GROUP -n "$gatewayipName" --location $AKS_PERS_LOCATION --allocation-method Dynamic

            # Write-Output "Waiting for IP address to get assigned to $gatewayipName"
            # Do { 
            #     Start-Sleep -Seconds 10
            #     Write-Output "."                
            #     $gatewayip = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n "$gatewayipName" --query "ipAddress" -o tsv; 
            # }
            # while ([string]::IsNullOrWhiteSpace($gatewayip))
        }  
    
        # Write-Host "Using Gateway IP: [$gatewayip]"

        $mysubnetid = "/subscriptions/${AKS_SUBSCRIPTION_ID}/resourceGroups/${AKS_SUBNET_RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${AKS_VNET_NAME}/subnets/${AKS_SUBNET_NAME}"
            
        Write-Output "Using subnet id: $mysubnetid"

        Write-Output "Creating new application gateway with WAF (This can take 10-15 minutes)"
        # https://docs.microsoft.com/en-us/cli/azure/network/application-gateway?view=azure-cli-latest#az_network_application_gateway_create

        az network application-gateway create `
            --sku WAF_Medium `
            --name "$gatewayName" `
            --location "$AKS_PERS_LOCATION" `
            --resource-group "$AKS_PERS_RESOURCE_GROUP" `
            --vnet-name "$AKS_VNET_NAME" `
            --subnet "$mysubnetid" `
            --public-ip-address "$gatewayipName" `
            --servers "$EXTERNAL_IP"  `
    
        # https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-faq

        Write-Output "Waiting for Azure Application Gateway to be created."
        az network application-gateway wait `
            --name "$gatewayName" `
            --resource-group "$AKS_PERS_RESOURCE_GROUP" `
            --created
    }
    else {

        # # set public IP
        $frontendPoolName = az network application-gateway show --name "$gatewayName" --resource-group "$AKS_SUBNET_RESOURCE_GROUP" --query "frontendIpConfigurations[0].name" -o tsv
        Write-Output "Setting $gatewayipName as IP for frontend pool $frontendPoolName"
        az network application-gateway frontend-ip update `
            --gateway-name "$gatewayName" `
            --resource-group "$AKS_PERS_RESOURCE_GROUP" `
            --name "$frontendPoolName" `
            --public-ip-address "$gatewayipName"

        $backendPoolName = az network application-gateway show --name "$gatewayName" --resource-group "$AKS_SUBNET_RESOURCE_GROUP" --query "backendAddressPools[0].name" -o tsv
        Write-Output "Setting $EXTERNAL_IP as IP for backend pool $backendPoolName"
        # set backend private IP
        az network application-gateway address-pool update  `
            --gateway-name "$gatewayName" `
            --resource-group "$AKS_PERS_RESOURCE_GROUP" `
            --name "$backendPoolName" `
            --servers "$EXTERNAL_IP"

        az network application-gateway wait `
            --name "$gatewayName" `
            --resource-group "$AKS_PERS_RESOURCE_GROUP" `
            --updated            
    }

    if ($(az network application-gateway waf-config show --gateway-name "$gatewayName" --resource-group "$AKS_PERS_RESOURCE_GROUP" --query "firewallMode" -o tsv) -eq "Prevention") {
    }
    else {
        Write-Output "Enabling Prevention mode of firewall"
        az network application-gateway waf-config set `
            --enabled true `
            --firewall-mode Prevention `
            --gateway-name "$gatewayName" `
            --resource-group "$AKS_PERS_RESOURCE_GROUP" `
            --rule-set-type "OWASP" `
            --rule-set-version "3.0"            
    }
    
    # if ([string]::IsNullOrEmpty($(az network application-gateway probe show --gateway-name "$gatewayName" --name "MyCustomProbe" --resource-group "$AKS_SUBNET_RESOURCE_GROUP"))) {
    #     # create a custom probe
    #     az network application-gateway probe create --gateway-name "$gatewayName" `
    #         --resource-group "$AKS_SUBNET_RESOURCE_GROUP" `
    #         --name "MyCustomProbe" `
    #         --path "/" `
    #         --protocol "Http" `
    #         --host "dashboard.${dnsrecordname}"

    #     # associate custom probe with HttpSettings: appGatewayBackendHttpSettings
    #     az network application-gateway http-settings update --gateway-name "$gatewayName" `
    #         --name "appGatewayBackendHttpSettings" `
    #         --resource-group "$AKS_SUBNET_RESOURCE_GROUP" `
    #         --probe "MyCustomProbe" `
    #         --enable-probe true `
    #         --host-name "dashboard.${dnsrecordname}"
    # }


    Write-Output "Checking for health of backend pool"
    az network application-gateway show-backend-health `
        --name "$gatewayName" `
        --resource-group "$AKS_PERS_RESOURCE_GROUP" `
        --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].health"

    # set EXTERNAL_IP to be the IP of the Application Gateway
    $EXTERNAL_IP = az network public-ip show -g $AKS_PERS_RESOURCE_GROUP -n "$gatewayipName" --query "ipAddress" -o tsv;
}

if ($SETUP_DNS -eq "y") {
    # set up DNS zones
    Write-Output "Setting DNS zones"

    if ([string]::IsNullOrWhiteSpace($(az network dns zone show --name "$dnsrecordname" -g $DNS_RESOURCE_GROUP))) {
        Write-Output "Creating DNS zone: $dnsrecordname"
        az network dns zone create --name "$dnsrecordname" -g $DNS_RESOURCE_GROUP
    }

    Write-Output "Create A record for * in zone: $dnsrecordname"
    az network dns record-set a add-record --ipv4-address $EXTERNAL_IP --record-set-name "*" --resource-group $DNS_RESOURCE_GROUP --zone-name "$dnsrecordname"

    # list out the name servers
    Write-Output "Name servers to set in GoDaddy for *.$dnsrecordname"
    az network dns zone show -g $DNS_RESOURCE_GROUP -n "$dnsrecordname" --query "nameServers" -o tsv
}
else {
    Write-Output "To access the urls from your browser, add the following entries in your c:\windows\system32\drivers\etc\hosts file"
    Write-Output "$EXTERNAL_IP dashboard.$dnsrecordname"
}

Write-Output "External IP: $EXTERNAL_IP"
if ($AKS_CLUSTER_ACCESS_TYPE -eq "2") {
    Write-Output "Internal IP: $INTERNAL_IP"
}

if ($AKS_CLUSTER_ACCESS_TYPE -eq "2") {
    # Write-Output "Testing internal load balancer"
    # Invoke-WebRequest -useb -Headers @{"Host" = "dashboard.$dnsrecordname"} -Uri http://$INTERNAL_IP/ | Select-Object -Expand Content
    
    Write-Output "To test out the load balancer since the vnet, open Git Bash and run:"
    Write-Output "curl -L --verbose --header 'Host: dashboard.$dnsrecordname' 'http://$INTERNAL_IP/' -k"

    Write-Output "To test out the load balancer from one of the whitelist IPs, open Git Bash and run:"
    Write-Output "curl -L --verbose --header 'Host: dashboard.$dnsrecordname' 'http://$EXTERNAL_IP/' -k"        
}
else {
    # Write-Output "Testing load balancer"
    # Invoke-WebRequest -useb -Headers @{"Host" = "dashboard.$dnsrecordname"} -Uri http://$EXTERNAL_IP/ | Select-Object -Expand Content
    
    Write-Output "To test out the load balancer, open Git Bash and run:"
    Write-Output "curl -L --verbose --header 'Host: dashboard.$dnsrecordname' 'http://$EXTERNAL_IP/' -k"        
}





