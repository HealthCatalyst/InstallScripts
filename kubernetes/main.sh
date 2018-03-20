#!/bin/bash
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/main.sh | bash
#
#
version="2018.03.20.01"

GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

source <(curl -sSL "$GITHUB_URL/kubernetes/common.sh?p=$RANDOM")
# source ./kubernetes/common.sh

mkdir -p $HOME/bin
installscript="$HOME/bin/dos"
if [[ ! -f "$installscript" ]]; then
    echo "#!/bin/bash" > $installscript
    echo "curl -sSL $GITHUB_URL/kubernetes/main.sh?p=$RANDOM | bash" >> $installscript
    chmod +x $installscript
    echo "NOTE: Next time just type 'dos' to bring up this menu"

    # from http://web.archive.org/web/20120621035133/http://www.ibb.net/~anne/keyboard/keyboard.html
    # curl -o ~/.inputrc "$GITHUB_URL/kubernetes/inputrc"
fi

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
    echo "7: Setup Kubernetes Dashboard"
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
    echo "35: Show load balancer logs"
    echo "37: Test DNS"
    echo "38: Show contents of shared folder"
    echo "39: Show dashboard url"
    echo "------ NLP -----"
    echo "41: Show status of NLP"
    echo "42: Test web sites"
    echo "43: Show NLP passwords"
    echo "44: Show detailed status of NLP"
    echo "45: Show NLP logs"
    # echo "46: Restart NLP"
    echo "------ Realtime -----"
    echo "51: Show status of realtime"
    echo "52: Show web site urls"
    echo "53: Show realtime passwords"
    echo "54: Show Realtime detailed status"
    echo "55: Show Realtime logs"
    echo "56: Show urls to download client certificates"
    echo "57: Show DNS entries for /etc/hosts"
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
    7)  curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/kubernetes/dashboard/setup-kubdashboard.sh?p=$RANDOM | bash
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
    35) kubectl logs --namespace=kube-system -l k8s-app=traefik-ingress-lb-onprem --tail=100
    ;;
    37)  # from https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/#debugging-dns-resolution
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
    38)  ls -al /mnt/data
        ;;
    39)  dnshostname=$(ReadSecret "dnshostname")
        echo "You can access the kubernetes dashboard at: https://${dnshostname}/api/ "
        secretname=$(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')
        token=$(ReadSecretValue "$secretname" "token" "kube-system")
        echo "----------- Bearer Token ---------------"
        echo $token
        echo "-------- End of Bearer Token -------------"
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
    52) certhostname=$(ReadSecret certhostname fabricrealtime)
        echo "Send HL7 to Mirth: server=${certhostname} port=6661"
        echo "Rabbitmq Queue: server=${certhostname} port=5671"
        echo "RabbitMq Mgmt UI is at: http://${certhostname}/rabbitmq/"
        echo "Mirth Mgmt UI is at: http://${certhostname}/mirth/"
        ;;
    53)  Write-Host "MySql root password: $(ReadSecretPassword mysqlrootpassword fabricrealtime)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword mysqlpassword fabricrealtime)"
            Write-Host "certhostname: $(ReadSecret certhostname fabricrealtime)"
            Write-Host "certpassword: $(ReadSecretPassword certpassword fabricrealtime)"
            Write-Host "rabbitmq mgmtui user: admin password: $(ReadSecretPassword rabbitmqmgmtuipassword fabricrealtime)"
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
    56) certhostname=$(ReadSecret certhostname fabricrealtime)
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
    57) echo "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
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
