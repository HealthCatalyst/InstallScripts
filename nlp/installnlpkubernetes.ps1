Write-Output "Version 2018.01.12.1"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | iex;
$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

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

if ([string]::IsNullOrWhiteSpace($(kubectl get namespace fabricnlp --ignore-not-found=true))) {
    kubectl create namespace fabricnlp
}
else {
    Do { $deleteSecrets = Read-Host "Namespace exists.  Do you want to delete passwords stored in this namespace? (y/n)"}
    while ([string]::IsNullOrWhiteSpace($deleteSecrets))    
    
    if ($deleteSecrets -eq "y" ) {
        kubectl delete secret mysqlrootpassword -n fabricnlp --ignore-not-found=true
        kubectl delete secret mysqlpassword -n fabricnlp --ignore-not-found=true
        kubectl delete secret smtprelaypassword -n fabricnlp --ignore-not-found=true
    }
}

function GeneratePassword() {
    $Length = 3
    $set1 = "abcdefghijklmnopqrstuvwxyz".ToCharArray()
    $set2 = "0123456789".ToCharArray()
    $set3 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()
    $set4 = "!.*@".ToCharArray()        
    $result = ""
    for ($x = 0; $x -lt $Length; $x++) {
        $result += $set1 | Get-Random
        $result += $set2 | Get-Random
        $result += $set3 | Get-Random
        $result += $set4 | Get-Random
    }
    return $result
}

function AskForPassword ($secretname, $prompt, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.password}' --ignore-not-found=true))) {

        $mysqlrootpassword = ""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        Do {
            $mysqlrootpasswordsecure = Read-host "$prompt (leave empty for auto-generated)" -AsSecureString 
            if ($mysqlrootpasswordsecure.Length -lt 1) {
                $mysqlrootpassword = GeneratePassword
            }
            else {
                $mysqlrootpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlrootpasswordsecure))                
            }
        }
        while (($mysqlrootpassword -notmatch "^[a-z0-9!.*@\s]+$") -or ($mysqlrootpassword.Length -lt 8 ))
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Output "$secretname secret already set so will reuse it"
    }
}

function AskForPasswordAnyCharacters ($secretname, $prompt, $namespace, $defaultvalue) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.password}' --ignore-not-found=true))) {

        $mysqlrootpassword = ""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        Do {
            $mysqlrootpasswordsecure = Read-host "$prompt (leave empty for default)" -AsSecureString 
            if ($mysqlrootpasswordsecure.Length -lt 1) {
                $mysqlrootpassword = $defaultvalue
            }
            else {
                $mysqlrootpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlrootpasswordsecure))                
            }
        }
        while ($mysqlrootpassword.Length -lt 8 )
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Output "$secretname secret already set so will reuse it"
    }
}

function AskForSecretValue ($secretname, $prompt, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.value}' --ignore-not-found=true))) {

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

function ReadYmlAndReplaceCustomer($templateFile, $customerid ) {
    if ($GITHUB_URL.StartsWith("http")) { 
        #        Write-Output "Reading from url: $GITHUB_URL/$templateFile"
        Invoke-WebRequest -Uri "$GITHUB_URL/$templateFile" -UseBasicParsing -ContentType "text/plain; charset=utf-8" `
            | Select-Object -Expand Content `
            | Foreach-Object {$_ -replace 'CUSTOMERID', "$customerid"}
    }
    else {
        #        Write-Output "Reading from local file: $GITHUB_URL/$templateFile"
        Get-Content -Path "$GITHUB_URL/$templateFile" `
            | Foreach-Object {$_ -replace 'CUSTOMERID', "$customerid"} 
    }
}

AskForSecretValue -secretname "customerid" -prompt "Health Catalyst Customer ID (e.g., ahmn)"

$customeridbase64 = kubectl get secret customerid -o jsonpath='{.data.value}' 
$customerid = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($customeridbase64))
Write-Output "Customer ID:" $customerid

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

ReadYmlAndReplaceCustomer -templateFile "nlp/nlp-kubernetes-storage.yml" -customerid $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer -templateFile "nlp/nlp-kubernetes.yml" -customerid $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer -templateFile "nlp/nlp-kubernetes-public.yml" -customerid $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer -templateFile "nlp/nlp-mysql-private.yml" -customerid $customerid | kubectl create -f -

Write-Output "Setting up SSL reverse proxy"

$ingressTemplate = "nlp/nlp-ingress.yml"
if ($AKS_USE_SSL -eq "y" ) {
    $ingressTemplate = "nlp/nlp-ingress-ssl.yml"
}

ReadYmlAndReplaceCustomer -templateFile $ingressTemplate -customerid $customerid | kubectl create -f -

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide

# to get a shell
# kubectl exec -it fabric.nlp.nlpwebserver-85c8cb86b5-gkphh bash --namespace=fabricnlp

# kubectl create secret generic azure-secret --namespace=fabricnlp --from-literal=azurestorageaccountname="fabricnlp7storage" --from-literal=azurestorageaccountkey="/bYhXNstTodg3MdOvTMog/vDLSFrQDpxG/Zgkp2MlnjtOWhDBNQ2xOs6zjRoZYNjmJHya34MfzqdfOwXkMDN2A=="

Write-Output "To get status of Fabric.NLP run:"
Write-Output "kubectl get deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes --namespace=fabricnlp -o wide"

Write-Output "To launch the dashboard UI, run:"
Write-Output "kubectl proxy"
Write-Output "and then in your browser, navigate to: http://127.0.0.1:8001/ui"

$loadBalancerIP = kubectl get svc traefik-ingress-service-public -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}' --ignore-not-found=true
if ([string]::IsNullOrWhiteSpace($loadBalancerIP)) {
    $loadBalancerIP = kubectl get svc traefik-ingress-service-private -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
}

Write-Output "To test out the NLP services, open Git Bash and run:"
Write-Output "curl -L --verbose --header 'Host: solr.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/solr'"
Write-Output "curl -L --verbose --header 'Host: nlp.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlpweb'"
