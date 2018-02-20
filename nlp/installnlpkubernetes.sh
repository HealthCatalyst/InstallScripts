#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
version="2018.02.16.03"

echo "---- installnlpkubernetes.sh version $version ------"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh")

# source ./kubernetes/common.sh

namespace="fabricnlp"

if [[ -z $(kubectl get namespace $namespace --ignore-not-found=true) ]]; then
    echo "Creating namespace: $namespace"
    # kubectl create -f $GITHUB_URL/nlp/nlp-namespace.yml
    kubectl create namespace $namespace
else
    while : ; do
        read -p "$namespace namespace exists.  Do you want to delete passwords and ALL data stored in this namespace? (y/n): " deleteSecrets < /dev/tty
        if [[ ! -z "$deleteSecrets" ]]; then
            break
        fi
    done

    if [[ $deleteSecrets == "y" ]]; then    
        echo "Deleting passwords"
        kubectl delete secret mysqlrootpassword -n $namespace --ignore-not-found=true
        kubectl delete secret mysqlpassword -n $namespace --ignore-not-found=true
        kubectl delete secret smtprelaypassword -n $namespace --ignore-not-found=true

        sudo rm -rf /mnt/data/*
    fi
fi

customerid="$(ReadSecret customerid)"
if [[ -z "$customerid" ]]; then
    echo "customerid not set"
fi
customerid="${customerid,,}"
echo "Customer ID: $customerid"

loadBalancerIP="$(dig +short myip.opendns.com @resolver1.opendns.com)"
echo "My WAN/Public IP address: ${loadBalancerIP}"

CleanOutNamespace $namespace

SaveSecretValue "nlpweb-external-url" url "${loadBalancerIP}/nlpweb"  $namespace
SaveSecretValue "jobserver-external-url" url "${loadBalancerIP}/nlp"  $namespace

AskForPassword "mysqlrootpassword" "MySQL root password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" "$namespace"
# MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
# we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script

AskForPassword "mysqlpassword" "MySQL NLP_APP_USER password (> 8 chars, min 1 number, 1 lowercase, 1 uppercase, 1 special [!.*@] )" "$namespace"

AskForPasswordAnyCharacters "smtprelaypassword" "SMTP (SendGrid) Relay Key" "$namespace" "" 

echo "-- Deploying volumes --"
folder="volumes"
for fname in "mysqlserver.onprem.yaml" "solrserver.onprem.yaml" "jobserver.onprem.yaml" "mysqlbackup.onprem.yaml"
do
    echo "Deploying nlp/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "nlp/$folder/$fname" $customerid | kubectl create -f -
done

echo "-- Deploying volume claims --"
folder="volumeclaims"
for fname in "mysqlserver.yaml" "solrserver.yaml" "jobserver.yaml" "mysqlbackup.yaml"
do
    echo "Deploying nlp/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "nlp/$folder/$fname" $customerid | kubectl create -f -
done

echo "-- Deploying pods --"
folder="pods"
for fname in "mysqlserver.yaml" "solrserver.yaml" "jobserver.yaml" "nlpwebserver.yaml" "mysqlclient.yaml"
do
    echo "Deploying nlp/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "nlp/$folder/$fname" $customerid | kubectl create -f -
done

echo "-- Deploying cluster services --"
folder="services/cluster"
for fname in "mysqlserver.yaml" "solrserver.yaml" "jobserver.yaml" "nlpwebserver.yaml"
do
    echo "Deploying nlp/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "nlp/$folder/$fname" $customerid | kubectl create -f -
done

echo "-- Deploying external services --"
folder="services/external"
for fname in "solrserver.yaml" "jobserver.yaml" "nlpwebserver.yaml"
do
    echo "Deploying nlp/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "nlp/$folder/$fname" $customerid | kubectl create -f -
done

echo "-- Deploying HTTP proxies --"
folder="ingress/http"
for fname in "web.onprem.yaml"
do
    echo "Deploying nlp/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "nlp/$folder/$fname" $customerid | kubectl create -f -
done

echo "-- Deploying TCP proxies --"
folder="ingress/tcp"
for fname in "mysqlserver.onprem.yaml"
do
    echo "Deploying nlp/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "nlp/$folder/$fname" $customerid | kubectl create -f -
done

echo "-- Deploying jobs --"
folder="jobs"
for fname in "mysqlserver-backup-cron.yaml"
do
    echo "Deploying nlp/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "nlp/$folder/$fname" $customerid | kubectl create -f -
done

kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=$namespace -o wide

WaitForPodsInNamespace $namespace 5

# to get a shell
# kubectl exec -it fabric.nlp.nlpwebserver-85c8cb86b5-gkphh bash --namespace=fabricnlp

# kubectl create secret generic azure-secret --namespace=fabricnlp --from-literal=azurestorageaccountname="fabricnlp7storage" --from-literal=azurestorageaccountkey="/bYhXNstTodg3MdOvTMog/vDLSFrQDpxG/Zgkp2MlnjtOWhDBNQ2xOs6zjRoZYNjmJHya34MfzqdfOwXkMDN2A=="

echo "To test out the NLP services, open Git Bash and run:"
echo "curl -L --verbose --header 'Host: solr.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/solr' -k"
echo "curl -L --verbose --header 'Host: nlp.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlpweb' -k"
echo "curl -L --verbose --header 'Host: nlpjobs.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlp' -k"

echo "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
echo "$loadBalancerIP solr.$customerid.healthcatalyst.net"            
echo "$loadBalancerIP nlp.$customerid.healthcatalyst.net"            
echo "$loadBalancerIP nlpjobs.$customerid.healthcatalyst.net"            

echo "---- end of installnlpkubernetes.sh version $version ------"
