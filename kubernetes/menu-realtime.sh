#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/menu-realtime.sh | bash
#
version="2018.03.28.01"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh?p=$RANDOM")
# source ./kubernetes/common.sh

input=""
while [[ "$input" != "q" ]]; do

    echo "================ Health Catalyst Realtime version $version, common functions $(GetCommonVersion) ================"
    echo "------ Install -------"
    echo "1: Install Realtime"
    echo "------ Status --------"
    echo "2: Show status of realtime"
    echo "3: Show web site urls"
    echo "4: Show realtime passwords"
    echo "5: Show Realtime detailed status"
    echo "6: Show Realtime logs"
    echo "7: Show urls to download client certificates"
    echo "8: Show DNS entries for /etc/hosts"
    echo "-------------------------------"
    echo "q: Quit"

    read -p "Please make a selection:" -e input  < /dev/tty 

    case "$input" in
    1)  curl -sSL -o installstack.ps1 https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/installstack.ps1?p=$RANDOM
        clear
        pwsh -f installstack.ps1 -namespace "fabricrealtime" -appfolder "realtime" -isAzure 0 -NonInteractive | tee ./installstack.log
        ;;
    2)  kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide
        ;;
    3) certhostname=$(ReadSecret certhostname fabricrealtime)
        echo "Send HL7 to Mirth: server=${certhostname} port=6661"
        echo "Rabbitmq Queue: server=${certhostname} port=5671"
        echo "RabbitMq Mgmt UI is at: http://${certhostname}/rabbitmq/"
        echo "Mirth Mgmt UI is at: http://${certhostname}/mirth/"
        ;;
    4)  Write-Host "MySql root password: $(ReadSecretPassword mysqlrootpassword fabricrealtime)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword mysqlpassword fabricrealtime)"
            Write-Host "certhostname: $(ReadSecret certhostname fabricrealtime)"
            Write-Host "certpassword: $(ReadSecretPassword certpassword fabricrealtime)"
            Write-Host "rabbitmq mgmtui user: admin password: $(ReadSecretPassword rabbitmqmgmtuipassword fabricrealtime)"
        ;;
    5)  pods=$(kubectl get pods -n fabricrealtime -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Describe Pod: $pod ================="
                kubectl describe pods $pod -n fabricrealtime
                read -n1 -r -p "Press space to continue..." key < /dev/tty
        done
        ;;
    6)  pods=$(kubectl get pods -n fabricrealtime -o jsonpath='{.items[*].metadata.name}')
        for pod in $pods
        do
                Write-Output "=============== Logs for Pod: $pod ================="
                kubectl logs --tail=20 $pod -n fabricrealtime
                read -n1 -r -p "Press space to continue..." key < /dev/tty
        done
        ;;
    7) certhostname=$(ReadSecret certhostname fabricrealtime)
        certpassword=$(ReadSecretPassword certpassword fabricrealtime)
        url="http://${certhostname}/certificates/client/fabricrabbitmquser_client_cert.p12"
        echo "Download the client certificate:"
        echo "$url"
        echo "Double-click and install in Local Machine. password: $certpassword"
        echo "Open Certificate Management, right click on cert and give everyone access to key"
        
        url="http://${certhostname}/certificates/client/fabric_ca_cert.p12"
        echo "Optional: Download the CA certificate:"
        echo "$url"
        echo "Double-click and install in Local Machine. password: $certpassword"
        ;;
    8) echo "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
        loadBalancerIP="$(dig +short myip.opendns.com @resolver1.opendns.com)"
        certhostname="$(ReadSecret certhostname fabricrealtime)"
        echo "$loadBalancerIP $certhostname"            
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
