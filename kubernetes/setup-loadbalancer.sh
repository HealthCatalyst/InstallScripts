#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setup-loadbalancer.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh?p=$RANDOM")
# source ./kubernetes/common.sh

version="2018.03.16.01"

echo "---- setup-loadbalancer.sh version $version ------"

# enable running pods on master
# kubectl taint node mymasternode node-role.kubernetes.io/master:NoSchedule

kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

AKS_IP_WHITELIST=""
publicip=""
customerid="hcut"
dnsrecordname="$customerid.healthcatalyst.net"

SaveSecretValue customerid "value" $customerid

yamlfile="kubernetes/loadbalancer/configmaps/config.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="kubernetes/loadbalancer/roles/ingress-roles.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="kubernetes/loadbalancer/pods/ingress-onprem.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="kubernetes/loadbalancer/services/cluster/dashboard-onprem.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="kubernetes/loadbalancer/services/external/loadbalancer-onprem.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

yamlfile="kubernetes/loadbalancer/ingress/default-onprem.yaml"
echo "Downloading $GITHUB_URL/$yamlfile"
ReadYamlAndReplaceCustomer $GITHUB_URL "$yamlfile" $customerid \
        | kubectl apply -f -

loadbalancer="traefik-ingress-service-public"
loadBalancerIP="$(dig +short myip.opendns.com @resolver1.opendns.com)"
echo "My WAN/Public IP address: ${loadBalancerIP}"
    
echo "To test out the load balancer, open Git Bash and run:"
echo "curl -L --verbose --header 'Host: dashboard.$dnsrecordname' 'http://$loadBalancerIP/' -k"        

echo "---- end of setup-loadbalancer.sh version $version ------"