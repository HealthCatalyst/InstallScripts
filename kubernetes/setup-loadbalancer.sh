#!/bin/sh
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setup-loadbalancer.sh | sh
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

ReadYmlAndReplaceCustomer () {
    baseUrl=$1
    templateFile=$2
    customerid=$3

    curl -sSL "$baseUrl/$templateFile" \
        | while read -r line; do echo "${line//CUSTOMERID/$customerid}"; done
}

AKS_IP_WHITELIST=""
customerid="hcut"
dnsrecordname="$customerid.healthcatalyst.net"

# ReadYmlAndReplaceCustomer $GITHUB_URL "azure/ingress-roles.yml" $customerid

ReadYmlAndReplaceCustomer $GITHUB_URL "kubernetes/loadbalancer/ingress-roles.yml" $customerid \
        | kubectl apply -f -

ReadYmlAndReplaceCustomer $GITHUB_URL "kubernetes/loadbalancer/ingress.yml" $customerid \
        | while read -r line; do echo "${line//WHITELISTIP/$AKS_IP_WHITELIST}"; done \
        | kubectl create -f -

ReadYmlAndReplaceCustomer $GITHUB_URL "kubernetes/loadbalancer/loadbalancer-public.yml" $customerid \
        | while read -r line; do echo "${line//PUBLICIP/$publicip}"; done \
        | kubectl create -f -


loadbalancer="traefik-ingress-service-public"
    
echo "To test out the load balancer, open Git Bash and run:"
echo "curl -L --verbose --header 'Host: dashboard.$dnsrecordname' 'http://$EXTERNAL_IP/' -k"        

