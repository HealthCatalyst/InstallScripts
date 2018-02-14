#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/main.sh | sh
#
#
version="2018.02.13.02"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh")
# source ./kubernetes/common.sh

GetCommonVersion

input=""
while [ "$input" != "q" ]; do

    echo "================ Health Catalyst version $version, common functions $(GetCommonVersion) ================"
    echo "------ Install -------"
    echo "1: Add this VM as Master"
    echo "2: Add this VM as Worker"
    echo "3: Setup Load Balancer"
    echo "4: Install NLP"
    echo "5: Install Realtime"
    echo "----- Troubleshooting ----"
    echo "6: Show status of cluster"
    echo "6: Launch Kubernetes Admin Dashboard"
    echo "8: View status of DNS pods"
    echo "9: Apply updates and restart all VMs"
    echo "------ NLP -----"
    echo "10: Show status of NLP"
    echo "11: Test web sites"
    echo "12: Show passwords"
    echo "13: Show NLP logs"
    echo "14: Restart NLP"
    echo "------ Realtime -----"
    echo "15: Show status of realtime"
    echo "-----------"
    echo "q: Quit"

    read -p "Please make a selection:" -e input

    case "$input" in
    1)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupnode.txt | sh
        curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupmaster.txt | sh
        ;;
    2) curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupnode.txt | sh
        ;;
    3)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setup-loadbalancer.sh | sh
        ;;
    4)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.sh | sh
        ;;
    6)  echo "Current cluster: $(kubectl config current-context)"
        kubectl version --short
        kubectl get "deployments,pods,services,ingress,secrets" --namespace=kube-system -o wide
        ;;
    q) echo  "Sending SIGKILL signal" 
    ;;
    *) echo "Signal number $1 is not processed"
    ;;
    esac

read -p "Press Enter to Continue"
done
