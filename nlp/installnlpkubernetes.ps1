Write-Output "Version 2017.12.20.1"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | iex;

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

# https://kubernetes.io/docs/reference/kubectl/jsonpath/

# setup DNS
# az network dns zone create -g $AKS_PERS_RESOURCE_GROUP -n nlp.allina.healthcatalyst.net
# az network dns record-set a add-record --ipv4-address j `
#                                        --record-set-name nlp.allina.healthcatalyst.net `
#                                        --resource-group $AKS_PERS_RESOURCE_GROUP `
#                                        --zone-name 

kubectl create namespace fabricnlp

if ([string]::IsNullOrWhiteSpace($(kubectl get secret mysqlrootpassword -n fabricnlp -o jsonpath='{.data.password}'))) {

    # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
    # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
    Do {
        $mysqlrootpasswordsecure = Read-host "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -AsSecureString 
        $mysqlrootpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlrootpasswordsecure))
    }
    while (($mysqlrootpassword -notmatch "^[a-z0-9!.*@\s]+$") -or ($mysqlrootpassword.Length -lt 8 ))
    kubectl create secret generic mysqlrootpassword --namespace=fabricnlp --from-literal=password=$mysqlrootpassword
}
else {
    Write-Output "mysqlrootpassword secret already set so will reuse it"
}

if ([string]::IsNullOrWhiteSpace($(kubectl get secret mysqlpassword -n fabricnlp -o jsonpath='{.data.password}'))) {

    Do {
        $mysqlpasswordsecure = Read-host "MySQL NLP_APP_USER password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -AsSecureString 
        $mysqlpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlpasswordsecure))
    }
    while (($mysqlpassword -notmatch "^[a-z0-9!.*@\s]+$") -or ($mysqlpassword.Length -lt 8 ))

    kubectl create secret generic mysqlpassword --namespace=fabricnlp --from-literal=password=$mysqlpassword
    Write-Warning "Be sure to keep the passwords in a secure place or you won't be able to access the data in the cluster afterwards"
}
else {
    Write-Output "mysqlpassword secret already set so will reuse it"
}

Write-Output "Cleaning out any old resources in fabricnlp"

# note kubectl doesn't like spaces in between commas below
kubectl delete --all 'deployments,pods,services,ingress,persistentvolumeclaims,persistentvolumes' --namespace=fabricnlp

Write-Output "Waiting until all the resources are cleared up"

Do { $CLEANUP_DONE = $(kubectl get 'deployments,pods,services,ingress,persistentvolumeclaims,persistentvolumes' --namespace=fabricnlp)}
while (![string]::IsNullOrWhiteSpace($CLEANUP_DONE))

kubectl create -f https://healthcatalyst.github.io/InstallScripts/nlp/nlp-kubernetes-storage.yml

kubectl create -f https://healthcatalyst.github.io/InstallScripts/nlp/nlp-kubernetes.yml

kubectl create -f https://healthcatalyst.github.io/InstallScripts/nlp/nlp-kubernetes-public.yml

kubectl create -f https://healthcatalyst.github.io/InstallScripts/nlp/nlp-mysql-private.yml

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp

# to get a shell
# kubectl exec -it fabric.nlp.nlpwebserver-85c8cb86b5-gkphh bash --namespace=fabricnlp

# kubectl create secret generic azure-secret --namespace=fabricnlp --from-literal=azurestorageaccountname="fabricnlp7storage" --from-literal=azurestorageaccountkey="/bYhXNstTodg3MdOvTMog/vDLSFrQDpxG/Zgkp2MlnjtOWhDBNQ2xOs6zjRoZYNjmJHya34MfzqdfOwXkMDN2A=="

Write-Output "To get status of Fabric.NLP run:"
Write-Output "kubectl get deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes --namespace=fabricnlp"

Write-Output "To launch the dashboard UI, run:"
Write-Output "kubectl proxy"
Write-Output "and then in your browser, navigate to: http://127.0.0.1:8001/ui"

$loadBalancerIP = kubectl get svc traefik-ingress-service-private -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'

Write-Output "To test out the NLP services, open Git Bash and run:"
Write-Output "curl -L --verbose --header 'Host: solr.ahmn.healthcatalyst.net' 'http://$loadBalancerIP/solr'"
Write-Output "curl -L --verbose --header 'Host: nlp.ahmn.healthcatalyst.net' 'http://$loadBalancerIP/nlpweb'"
