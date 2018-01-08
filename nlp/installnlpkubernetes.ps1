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

if ([string]::IsNullOrWhiteSpace($(kubectl get namespace fabricnlp))) {
    kubectl create namespace fabricnlp
}

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

        Do {
            $certhostname = Read-host "$prompt"
        }
        while ($certhostname.Length -lt 8 )
    
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$certhostname
    }
    else {
        Write-Output "$secretname secret already set so will reuse it"
    }    
}


AskForPassword -secretname "mysqlrootpassword" -prompt "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricnlp"
    # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
    # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script

AskForPassword -secretname "mysqlpassword" -prompt "MySQL NLP_APP_USER password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" -namespace "fabricnlp"

AskForPassword -secretname "smtprelaypassword" -prompt "SMTP (SendGrid) Relay Key" -namespace "fabricnlp"

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

Write-Output "Setting up SSL reverse proxy"

AskForSecretValue -secretname "customerid" -prompt "Health Catalyst Customer ID (e.g., ahmn)" -namespace "fabricnlp"

$customeridbase64 = kubectl get secret customerid -n fabricnlp -o jsonpath='{.data.value}'
$customerid = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($customeridbase64))
Write-Output "Customer ID:" $customerid

# $customerid="ahmn"
# ingress for web services
# for SSL, from: https://github.com/containous/traefik/issues/2329
$serviceyaml = @"
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nlp-ingress
  namespace: fabricnlp
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  tls:
    - secretName: ssl-ahmn
      hosts:
        - solr.$customerid.healthcatalyst.net
        - nlp.$customerid.healthcatalyst.net
        - nlpjobs.$customerid.healthcatalyst.net
  rules:
  - host: solr.$customerid.healthcatalyst.net
    http:
      paths:
      - backend:
          serviceName: solrserverpublic
          servicePort: 80
  - host: nlp.$customerid.healthcatalyst.net
    http:
      paths:
      - backend:
          serviceName: nlpserverpublic
          servicePort: 80
  - host: nlpjobs.$customerid.healthcatalyst.net
    http:
      paths:
      - backend:
          serviceName: nlpjobsserverpublic
          servicePort: 80---
"@

    Write-Output $serviceyaml | kubectl create -f -

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp

# to get a shell
# kubectl exec -it fabric.nlp.nlpwebserver-85c8cb86b5-gkphh bash --namespace=fabricnlp

# kubectl create secret generic azure-secret --namespace=fabricnlp --from-literal=azurestorageaccountname="fabricnlp7storage" --from-literal=azurestorageaccountkey="/bYhXNstTodg3MdOvTMog/vDLSFrQDpxG/Zgkp2MlnjtOWhDBNQ2xOs6zjRoZYNjmJHya34MfzqdfOwXkMDN2A=="

Write-Output "To get status of Fabric.NLP run:"
Write-Output "kubectl get deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes --namespace=fabricnlp"

Write-Output "To launch the dashboard UI, run:"
Write-Output "kubectl proxy"
Write-Output "and then in your browser, navigate to: http://127.0.0.1:8001/ui"

$loadBalancerIP = kubectl get svc traefik-ingress-service-public -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
if([string]::IsNullOrWhiteSpace($loadBalancerIP)){
    $loadBalancerIP = kubectl get svc traefik-ingress-service-private -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
}

Write-Output "To test out the NLP services, open Git Bash and run:"
Write-Output "curl -L --verbose --header 'Host: solr.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/solr'"
Write-Output "curl -L --verbose --header 'Host: nlp.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlpweb'"
