write-output "Version 2017.12.18.9"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | iex;

$loggedInUser = az account show --query "user.name"  --output tsv

Write-Output "user: $loggedInUser"

if ( "$loggedInUser" ) {
    $SUBSCRIPTION_NAME = az account show --query "name"  --output tsv
    Write-Output "You are currently logged in as $loggedInUser into subscription $SUBSCRIPTION_NAME"
    
    $confirmation = Read-Host "Do you want to use this account? (y/n)"
    if ($confirmation -eq 'n') {
        az login
    }    
}
else {
    # login
    az login
}

# https://kubernetes.io/docs/reference/kubectl/jsonpath/

# setup DNS
# az network dns zone create -g $AKS_PERS_RESOURCE_GROUP -n nlp.allina.healthcatalyst.net
# az network dns record-set a add-record --ipv4-address j `
#                                        --record-set-name nlp.allina.healthcatalyst.net `
#                                        --resource-group $AKS_PERS_RESOURCE_GROUP `
#                                        --zone-name 

$mysqlrootpasswordsecure = Read-host "MySQL root password" -AsSecureString 
$mysqlrootpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlrootpasswordsecure))

$mysqlpasswordsecure = Read-host "MySQL password for NLP database" -AsSecureString 
$mysqlpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlpasswordsecure))

Write-Output "WARNING: Be sure to keep the passwords in a secure place or you won't be able to access the data in the cluster afterwards"

kubectl create namespace fabricnlp

kubectl create secret generic mysqlrootpassword --namespace=fabricnlp --from-literal=password=$mysqlrootpassword

kubectl create secret generic mysqlpassword --namespace=fabricnlp --from-literal=password=$mysqlpassword

kubectl create -f https://healthcatalyst.github.io/InstallScripts/nlp/nlp-kubernetes-storage.yml

kubectl create -f https://healthcatalyst.github.io/InstallScripts/nlp/nlp-kubernetes.yml

kubectl create -f https://healthcatalyst.github.io/InstallScripts/nlp/nlp-kubernetes-public.yml

kubectl create -f https://healthcatalyst.github.io/InstallScripts/nlp/nlp-mysql-private.yml

kubectl get deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes --namespace=fabricnlp

# to get a shell
# kubectl exec -it fabric.nlp.nlpwebserver-85c8cb86b5-gkphh bash --namespace=fabricnlp

# kubectl create secret generic azure-secret --namespace=fabricnlp --from-literal=azurestorageaccountname="fabricnlp7storage" --from-literal=azurestorageaccountkey="/bYhXNstTodg3MdOvTMog/vDLSFrQDpxG/Zgkp2MlnjtOWhDBNQ2xOs6zjRoZYNjmJHya34MfzqdfOwXkMDN2A=="

Write-Output "To get status of Fabric.NLP run:"
Write-Output "kubectl get deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes --namespace=fabricnlp"

