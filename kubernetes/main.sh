#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/main.sh | bash
#
#
version="2018.03.14.05"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh?p=$RANDOM")
# source ./kubernetes/common.sh

input=""
while [[ "$input" != "q" ]]; do

    echo "================ Health Catalyst version $version, common functions $(GetCommonVersion) ================"
    echo "------ Master Node -------"
    echo "1: Add this VM as Master"
    echo "2: Show all nodes"
    echo "3: Join a new node to this cluster"
    echo "4: Mount shared folder"
    echo "5: Mount Azure Storage as shared folder"
    echo "6: Setup Load Balancer"
    echo "7: Test DNS"
    echo "8: Show contents of shared folder"
    echo "------ Worker Node -------"
    echo "12: Add this VM as Worker"
    echo "14: Mount shared folder"
    echo "15: Mount Azure Storage as shared folder"
    echo "------ Product Install -------"
    echo "25: Install NLP"
    echo "26: Install Realtime"
    echo "----- Troubleshooting ----"
    echo "31: Show status of cluster"
    # echo "32: Launch Kubernetes Admin Dashboard"
    # echo "33: View status of DNS pods"
    # echo "34: Apply updates and restart all VMs"
    echo "------ NLP -----"
    echo "41: Show status of NLP"
    # echo "42: Test web sites"
    echo "43: Show passwords"
    echo "44: Show detailed status of NLP"
    echo "45: Show NLP logs"
    # echo "46: Restart NLP"
    echo "------ Realtime -----"
    echo "51: Show status of realtime"
    echo "54: Show Realtime detailed status"
    echo "55: Show Realtime logs"
    echo "-----------"
    echo "q: Quit"

    read -p "Please make a selection:" -e input  < /dev/tty 

    case "$input" in
    1)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupnode.txt?p=$RANDOM | bash
        curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupmaster.txt?p=$RANDOM | bash
        curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setup-loadbalancer.sh?p=$RANDOM | bash
        ;;
    2)  echo "Current cluster: $(kubectl config current-context)"
        kubectl version --short
        kubectl get "nodes"
        ;;
    3)  echo "Run this command on the new node to join this cluster:"
        echo "sudo $(sudo kubeadm token create --print-join-command)"
        ;;
    4)  mountSMB
        ;;
    5)  mountAzureFile
        ;;
    6)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setup-loadbalancer.sh?p=$RANDOM | bash
        ;;
    7)  # from https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#debugging-dns-resolution
        echo "To resolve DNS issues: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#debugging-dns-resolution"
        echo "----------- Checking if DNS pods are running -----------"
        kubectl get pods --namespace=kube-system -l k8s-app=kube-dns
        echo "----------- Checking if DNS service is running -----------"
        kubectl get svc --namespace=kube-system
        echo "----------- Checking if DNS endpoints are exposed ------------"
        kubectl get ep kube-dns --namespace=kube-system
        echo "----------- Checking logs for DNS service -----------"
        kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c kubedns
        kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c dnsmasq
        kubectl logs --namespace=kube-system $(kubectl get pods --namespace=kube-system -l k8s-app=kube-dns -o name) -c sidecar        
        echo "----------- Creating a busybox pod to test DNS -----------"
        while [[ ! -z "$(kubectl get pods busybox -n default -o jsonpath='{.status.phase}' --ignore-not-found=true)" ]]; do
            echo "Waiting for busybox to terminate"
            echo "."
            sleep 5
        done

        kubectl create -f https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/busybox.yml
        while [[ "$(kubectl get pods busybox -n default -o jsonpath='{.status.phase}')" != "Running" ]]; do
            echo "."
            sleep 5
        done
        kubectl exec busybox nslookup kubernetes.default
        kubectl exec busybox cat /etc/resolv.conf
        kubectl delete -f https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/busybox.yml
        ;;
    8)  ls -al /mnt/data
        ;;
    12)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/setupnode.txt?p=$RANDOM | bash
        ;;
    14)  mountSMB
        ;;
    15)  mountAzureFile
        ;;
    25)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.sh?p=$RANDOM | bash
        ;;
    26)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.sh?p=$RANDOM | bash
        ;;
    31)  echo "Current cluster: $(kubectl config current-context)"
        kubectl version --short
        kubectl get "deployments,pods,services,nodes,ingress,secrets" --namespace=kube-system -o wide
        ;;
    41)  kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide
        ;;
    43)  Write-Host "MySql root password: $(ReadSecretPassword mysqlrootpassword fabricnlp)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword mysqlpassword fabricnlp)"
            Write-Host "SendGrid SMTP Relay key: $(ReadSecretPassword smtprelaypassword fabricnlp)"
        ;;
    44)  pods=$(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Describe Pod: $pod ================="
                kubectl describe pods $pod -n fabricnlp
                read -n1 -r -p "Press space to continue..." key < /dev/tty
        done
        ;;
    45)  pods=$(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Logs for Pod: $pod ================="
                kubectl logs --tail=20 $pod -n fabricnlp
                read -n1 -r -p "Press space to continue..." key < /dev/tty
        done
        ;;
    51)  kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide
        ;;
    53)  Write-Host "MySql root password: $(ReadSecretPassword mysqlrootpassword fabricrealtime)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword mysqlpassword fabricrealtime)"
            Write-Host "certhostname: $(ReadSecretPassword certhostname fabricrealtime)"
            Write-Host "certpassword: $(ReadSecretPassword certpassword fabricrealtime)"
            Write-Host "rabbitmqmgmtuipassword: $(ReadSecretPassword rabbitmqmgmtuipassword fabricrealtime)"
        ;;
    54)  pods=$(kubectl get pods -n fabricrealtime -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Describe Pod: $pod ================="
                kubectl describe pods $pod -n fabricrealtime
                read -n1 -r -p "Press space to continue..." key < /dev/tty
        done
        ;;
    55)  pods=$(kubectl get pods -n fabricrealtime -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Logs for Pod: $pod ================="
                kubectl logs --tail=20 $pod -n fabricrealtime
                read -n1 -r -p "Press space to continue..." key < /dev/tty
        done
        ;;

    q) echo  "Exiting" 
    ;;
    *) echo "Menu item $1 is not known"
    ;;
    esac

echo ""
read -p "[Press Enter to Continue]" < /dev/tty 
clear
done
