#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/main.sh | bash
#
#
version="2018.02.14.03"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh")
# source ./kubernetes/common.sh

GetCommonVersion

input=""
while [[ "$input" != "q" ]]; do

    echo "================ Health Catalyst version $version, common functions $(GetCommonVersion) ================"
    echo "------ Install -------"
    echo "1: Add this VM as Master"
    echo "2: Add this VM as Worker"
    echo "3. Join a new node to this cluster"
    echo "4: Setup Load Balancer"
    echo "5: Install NLP"
    echo "6: Install Realtime"
    echo "----- Troubleshooting ----"
    echo "11: Show status of cluster"
    echo "12: Launch Kubernetes Admin Dashboard"
    echo "13: View status of DNS pods"
    echo "14: Apply updates and restart all VMs"
    echo "------ NLP -----"
    echo "21: Show status of NLP"
    echo "22: Test web sites"
    echo "23: Show passwords"
    echo "24: Show NLP logs"
    echo "25: Restart NLP"
    echo "------ Realtime -----"
    echo "31: Show status of realtime"
    echo "-----------"
    echo "q: Quit"

    read -p "Please make a selection:" -e input  < /dev/tty 

    case "$input" in
    1)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupnode.txt | bash
        curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupmaster.txt | bash
        ;;
    2) curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupnode.txt | bash
        ;;
    3)  echo "Run this command on the new node to join this cluster:"
        echo "sudo $(sudo kubeadm token create --print-join-command)"
        ;;
    4)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setup-loadbalancer.sh | bash
        ;;
    5)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.sh | bash
        ;;
    11)  echo "Current cluster: $(kubectl config current-context)"
        kubectl version --short
        kubectl get "deployments,pods,services,ingress,secrets" --namespace=kube-system -o wide
        ;;
    21)  kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide
        ;;
    23)  Write-Host "MySql root password: $(ReadSecretPassword mysqlrootpassword fabricnlp)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword mysqlpassword fabricnlp)"
            Write-Host "SendGrid SMTP Relay key: $(ReadSecretPassword smtprelaypassword fabricnlp)"
        ;;
    24)  pods=$(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Describe Pod: $pod ================="
                kubectl describe pods $pod -n fabricnlp
                read -n1 -r -p "Press space to continue..." key
        done

        for pod in $pods
        do
                Write-Output "=============== Logs for Pod: $pod ================="
                kubectl logs --tail=20 $pod -n fabricnlp
                read -n1 -r -p "Press space to continue..." key
        done
        ;;
    q) echo  "Exiting" 
    ;;
    *) echo "Menu item $1 is not known"
    ;;
    esac

read -p "Press Enter to Continue" < /dev/tty 
clear
done
