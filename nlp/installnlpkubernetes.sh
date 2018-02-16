#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
version="2018.02.14.06"

echo "---- installnlpkubernetes.sh version $version ------"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh")

# source ./kubernetes/common.sh

if [[ -z $(kubectl get namespace fabricnlp --ignore-not-found=true) ]]; then
    echo "Creating namespace: fabricnlp"
    # kubectl create -f $GITHUB_URL/nlp/nlp-namespace.yml
    kubectl create namespace fabricnlp
else
    while : ; do
        read -p "Namespace exists.  Do you want to delete passwords and ALL data stored in this namespace? (y/n): " deleteSecrets < /dev/tty
        if [[ ! -z "$deleteSecrets" ]]; then
            break
        fi
    done

    if [[ $deleteSecrets == "y" ]]; then    
        echo "Deleting passwords"
        kubectl delete secret mysqlrootpassword -n fabricnlp --ignore-not-found=true
        kubectl delete secret mysqlpassword -n fabricnlp --ignore-not-found=true
        kubectl delete secret smtprelaypassword -n fabricnlp --ignore-not-found=true

        sudo rm -rf /mnt/data/*
    fi
fi

customerid="$(ReadSecret customerid)"
if [[ -z "$customerid" ]]; then
    echo "customerid not set"
fi
customerid="${customerid,,}"
echo "Customer ID: $customerid"

AskForPassword "mysqlrootpassword" "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" "fabricnlp"
# MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
# we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script

AskForPassword "mysqlpassword" "MySQL NLP_APP_USER password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" "fabricnlp"

AskForPasswordAnyCharacters "smtprelaypassword" "SMTP (SendGrid) Relay Key" "fabricnlp" "" 

echo "Cleaning out any old resources in fabricnlp"

# note kubectl doesn't like spaces in between commas below
kubectl delete --all 'deployments,pods,services,ingress,persistentvolumeclaims,persistentvolumes,jobs,cronjobs' --namespace=fabricnlp --ignore-not-found=true

echo "Waiting until all the resources are cleared up"

CLEANUP_DONE="n"
while [[ ! -z "$CLEANUP_DONE" ]]; do
    CLEANUP_DONE=$(kubectl get 'deployments,pods,services,ingress,persistentvolumeclaims,persistentvolumes' --namespace=fabricnlp)
done

ReadYmlAndReplaceCustomer $GITHUB_URL "nlp/nlp-kubernetes-storage-onprem.yml" $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer $GITHUB_URL "nlp/nlp-kubernetes.yml" $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer $GITHUB_URL "nlp/nlp-kubernetes-public.yml" $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer $GITHUB_URL "nlp/nlp-mysql-private.yml" $customerid | kubectl create -f -

ReadYmlAndReplaceCustomer $GITHUB_URL "nlp/nlp-backups-cronjob.yml" $customerid | kubectl create -f -

echo "Setting up reverse proxy"

ingressTemplate="nlp/nlp-ingress.onprem.yml"
echo "Using template: $ingressTemplate"

ReadYmlAndReplaceCustomer $GITHUB_URL $ingressTemplate $customerid | kubectl create -f -

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide

WaitForPodsInNamespace fabricnlp

# to get a shell
# kubectl exec -it fabric.nlp.nlpwebserver-85c8cb86b5-gkphh bash --namespace=fabricnlp

# kubectl create secret generic azure-secret --namespace=fabricnlp --from-literal=azurestorageaccountname="fabricnlp7storage" --from-literal=azurestorageaccountkey="/bYhXNstTodg3MdOvTMog/vDLSFrQDpxG/Zgkp2MlnjtOWhDBNQ2xOs6zjRoZYNjmJHya34MfzqdfOwXkMDN2A=="

loadBalancerIP="$(dig +short myip.opendns.com @resolver1.opendns.com)"
echo "My WAN/Public IP address: ${loadBalancerIP}"


echo "To test out the NLP services, open Git Bash and run:"
echo "curl -L --verbose --header 'Host: solr.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/solr' -k"
echo "curl -L --verbose --header 'Host: nlp.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlpweb' -k"
echo "curl -L --verbose --header 'Host: nlpjobs.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlp' -k"

echo "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
echo "$loadBalancerIP solr.$customerid.healthcatalyst.net"            
echo "$loadBalancerIP nlp.$customerid.healthcatalyst.net"            
echo "$loadBalancerIP nlpjobs.$customerid.healthcatalyst.net"            

echo "---- end of installnlpkubernetes.sh version $version ------"
