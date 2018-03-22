#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setup-loadbalancer.sh | bash
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh?p=$RANDOM")
# source ./kubernetes/common.sh

version="2018.03.19.01"

echo "---- setup-kubdashboard.sh version $version ------"

# enable running pods on master
# kubectl taint node mymasternode node-role.kubernetes.io/master:NoSchedule

kubectl -n kube-system delete $(kubectl -n kube-system get pod -o name | grep dashboard)

# kubectl delete 'pods,services,configMaps,deployments,ingress' -l k8s-traefik=traefik -n kube-system --ignore-not-found=true

# kubectl delete ServiceAccount traefik-ingress-controller-serviceaccount -n kube-system --ignore-not-found=true

# https://github.com/kubernetes/dashboard/wiki/Accessing-Dashboard---1.7.X-and-above

echo "-- Deploying roles --"
folder="roles"
for fname in "heapster-rbac.yaml" "dashboard-user.yaml"
do
    echo "Deploying kubernetes/dashboard/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "kubernetes/dashboard/$folder/$fname" "" | kubectl apply -f -
done

echo "-- Deploying pods --"
folder="pods"
for fname in "influxdb.yaml" "grafana.yaml" "heapster.yaml" "kubernetes-dashboard.yaml"
do
    echo "Deploying kubernetes/dashboard/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "kubernetes/dashboard/$folder/$fname" "" | kubectl apply -f -
done

echo "-- Deploying ingress --"
folder="ingress/http"
for fname in "dashboard.yaml"
do
    echo "Deploying kubernetes/dashboard/$folder/$fname"
    ReadYamlAndReplaceCustomer $GITHUB_URL "kubernetes/dashboard/$folder/$fname" "" | kubectl apply -f -
done

echo "---- end of setup-kubdashboard.sh version $version ------"