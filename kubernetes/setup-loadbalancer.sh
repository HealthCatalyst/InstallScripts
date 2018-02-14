#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setup-loadbalancer.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh")
# source ./kubernetes/common.sh

version="2018.02.13.07"

echo "---- setup-loadbalancer.sh version $version ------"

kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

AKS_IP_WHITELIST=""
publicip=""
customerid="hcut"
dnsrecordname="$customerid.healthcatalyst.net"

SaveSecretValue customerid "value" $customerid

# ReadYmlAndReplaceCustomer $GITHUB_URL "azure/ingress-roles.yml" $customerid

ReadYmlAndReplaceCustomer $GITHUB_URL "kubernetes/loadbalancer/ingress-roles.yml" $customerid \
        | kubectl apply -f -

ReadYmlAndReplaceCustomer $GITHUB_URL "kubernetes/loadbalancer/ingress.yml" $customerid \
        | ReplaceText WHITELISTIP $AKS_IP_WHITELIST \
        | kubectl create -f -

ReadYmlAndReplaceCustomer $GITHUB_URL "kubernetes/loadbalancer/loadbalancer-public.yml" $customerid \
        | ReplaceText PUBLICIP $publicip \
        | kubectl create -f -


loadbalancer="traefik-ingress-service-public"
    
echo "To test out the load balancer, open Git Bash and run:"
echo "curl -L --verbose --header 'Host: dashboard.$dnsrecordname' 'http://$EXTERNAL_IP/' -k"        

echo "---- end of setup-loadbalancer.sh version $version ------"