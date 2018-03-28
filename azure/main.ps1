$version = "2018.03.27.01"

# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/main.ps1 | iex;
#   curl -sSL  https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/main.ps1 | pwsh -Interactive -NoExit -c -;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1?f=$randomstring | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;


# Get-Content -Path "./azure/common.ps1" | Invoke-Expression;

$userinput = ""
while ($userinput -ne "q") {
    Write-Host "================ Health Catalyst version $version, common functions $(GetCommonVersion) ================"
    Write-Warning "CURRENT CLUSTER: $(kubectl config current-context 2> $null)"
    Write-Host "0: Change kube to point to another cluster"
    Write-Host "------ Infrastructure -------"
    Write-Host "1: Create a new Azure Container Service"
    Write-Host "2: Setup Load Balancer"
    Write-Host "3: Start VMs in Resource Group"
    Write-Host "4: Stop VMs in Resource Group"
    Write-Host "5: Renew Azure token"
    Write-Host "6: Show NameServers to add in GoDaddy"
    Write-Host "7: Setup Azure DNS entries"
    Write-Host "8: Show DNS entries to make in CAFE DNS"
    Write-Host "------ Install -------"
    Write-Host "11: Install NLP"
    Write-Host "12: Install Realtime"
    Write-Host "----- Troubleshooting ----"
    Write-Host "20: Show status of cluster"
    Write-Host "21: Launch Kubernetes Admin Dashboard"
    Write-Host "22: Show SSH commands to VMs"
    Write-Host "23: View status of DNS pods"
    Write-Host "24: Restart all VMs"
    Write-Host "25: Flush DNS on local machine"
    Write-Host "------ Load Balancer -------"
    Write-Host "30: Test load balancer"
    Write-Host "31: Fix load balancers"
    Write-Host "32: Show load balancer logs"
    Write-Host "33: Launch Load Balancer Dashboard"
    Write-Host "------ NLP -----"
    Write-Host "40: Show status of NLP"
    Write-Host "41: Show detailed status of NLP"
    Write-Host "42: Test web sites"
    Write-Host "43: Show passwords"
    Write-Host "44: Show NLP logs"
    Write-Host "45: Restart NLP"
    Write-Host "46: Show commands to SSH to NLP containers"
    Write-Host "------ Realtime -----"
    Write-Host "51: Show status of realtime"
    Write-Host "-----------"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '0' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            $folders = Get-ChildItem "C:\kubernetes" -directory
            for ($i = 1; $i -le $folders.count; $i++) {
                Write-Host "$i. $($folders[$i-1])"
            }              
            $index = Read-Host "Enter number of folder to use (1 - $($folders.count))"
            $folderToUse = $($folders[$index - 1])

            SwitchToKubCluster -folderToUse "C:\kubernetes\$folderToUse"
        } 
        '1' {
            Invoke-WebRequest -useb $GITHUB_URL/azure/create-acs-cluster.ps1?f=$randomstring | Invoke-Expression;
            Invoke-WebRequest -useb $GITHUB_URL/kubernetes/setup-loadbalancer.ps1?f=$randomstring | Invoke-Expression;
        } 
        '2' {
            Invoke-WebRequest -useb $GITHUB_URL/kubernetes/setup-loadbalancer.ps1?f=$randomstring | Invoke-Expression;
        } 
        '3' {
            Do { 
                $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group"
            }
            while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
            az vm start --ids $(az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[].id" -o tsv) 
        } 
        '4' {
            Do { 
                $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group"
            }
            while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
            az vm stop --ids $(az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[].id" -o tsv) 
        } 
        '5' {
            $expiresOn = $(az account get-access-token --query "expiresOn" -o tsv)
            Do { $confirmation = Read-Host "Your current access token expires on $expiresOn. Do you want to login again to get a new access token? (y/n)"}
            while ([string]::IsNullOrWhiteSpace($confirmation))
        
            if ($confirmation -eq "y") {
                az account clear
                az login
            }
        }         
        '6' {
            $DNS_RESOURCE_GROUP = Read-Host "Resource group containing DNS zones? (default: dns)"
            if ([string]::IsNullOrWhiteSpace($DNS_RESOURCE_GROUP)) {
                $DNS_RESOURCE_GROUP = "dns"
            }

            $customerid = ReadSecret -secretname customerid
            $customerid = $customerid.ToLower().Trim()

            $dnsrecordname = "$customerid.healthcatalyst.net"
                    
            ShowNameServerEntries -dnsResourceGroup $DNS_RESOURCE_GROUP -dnsrecordname $dnsrecordname
        } 
        '7' {
            $DNS_RESOURCE_GROUP = Read-Host "Resource group containing DNS zones? (default: dns)"
            if ([string]::IsNullOrWhiteSpace($DNS_RESOURCE_GROUP)) {
                $DNS_RESOURCE_GROUP = "dns"
            }

            $customerid = ReadSecret -secretname customerid
            $customerid = $customerid.ToLower().Trim()

            $dnsrecordname = "$customerid.healthcatalyst.net"

            $loadBalancerIPResult = GetLoadBalancerIPs
            $EXTERNAL_IP = $loadBalancerIPResult.ExternalIP

            SetupDNS -dnsResourceGroup $DNS_RESOURCE_GROUP -dnsrecordname $dnsrecordname -externalIP $EXTERNAL_IP 
        }
        '8' {
            WriteDNSCommands
        } 
        '11' {
            Invoke-WebRequest -useb $GITHUB_URL/nlp/installnlpkubernetes.ps1?f=$randomstring | Invoke-Expression;
        } 
        '12' {
            InstallStack -namespace "fabricrealtime" -baseUrl $GITHUB_URL -appfolder "realtime" -isAzure 1
        } 
        '20' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            kubectl version --short
            kubectl get "deployments,pods,services,ingress,secrets,nodes" --namespace=kube-system -o wide
        } 
        '21' {
            # launch Kubernetes dashboard
            $launchJob = $true
            $myPortArray = 8001,8002,8003,8004,8005,8006,8007,8008,8009,8010,8011,8012,8013,8014,8015,8016,8017,8018,8019,8020,8021,8022,8023,8024,8025,8026,8027,8028,8029,8030,8031,8032,8033,8034,8035,8036,8037,8038,8039
            $port = $(FindOpenPort -portArray $myPortArray).Port
            Write-Host "Starting Kub Dashboard on port $port"
            # $existingProcess = Get-ProcessByPort 8001
            # if (!([string]::IsNullOrWhiteSpace($existingProcess))) {
            #     Do { $confirmation = Read-Host "Another process is listening on 8001.  Do you want to kill that process? (y/n)"}
            #     while ([string]::IsNullOrWhiteSpace($confirmation))
            
            #     if ($confirmation -eq "y") {
            #         Stop-ProcessByPort 8001
            #     }
            #     else {
            #         $launchJob = $false
            #     }
            # }

            if ($launchJob) {
                # https://stackoverflow.com/questions/19834643/powershell-how-to-pre-evaluate-variables-in-a-scriptblock-for-start-job
                $sb = [scriptblock]::Create("kubectl proxy -p $port")
                $job = Start-Job -Name "KubDashboard" -ScriptBlock $sb -ErrorAction Stop
                Wait-Job $job -Timeout 5;
                Write-Output "job state: $($job.state)"  
                Receive-Job -Job $job 6>&1  
            }

            # if ($job.state -eq 'Failed') {
            #     Receive-Job -Job $job
            #     Stop-ProcessByPort 8001
            # }
            
            # Write-Host "Your kubeconfig file is here: $env:KUBECONFIG"
            $kubectlversion = $(kubectl version --short=true)[1]
            if ($kubectlversion -match "v1.8") {
                Write-Host "Launching http://localhost:$port/api/v1/namespaces/kube-system/services/kubernetes-dashboard/proxy in the web browser"
                Start-Process -FilePath "http://localhost:$port/api/v1/namespaces/kube-system/services/kubernetes-dashboard/proxy";
            }
            else {
                Write-Host "Launching http://localhost:$port/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/ in the web browser"
                Write-Host "Click Skip on login screen";
                Start-Process -FilePath "http://localhost:$port/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/";
            }            
        } 
        '22' {        
            $DEFAULT_RESOURCE_GROUP = ReadSecretValue -secretname azure-secret -valueName resourcegroup
            
            if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
                Do { 
                    $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group: (default: $DEFAULT_RESOURCE_GROUP)"
                    if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
                        $AKS_PERS_RESOURCE_GROUP = $DEFAULT_RESOURCE_GROUP
                    }
                }
                while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
            }

            $AKS_PERS_LOCATION = az group show --name $AKS_PERS_RESOURCE_GROUP --query "location" -o tsv
    
            $AKS_LOCAL_FOLDER = Read-Host "Folder to store SSH keys (default: c:\kubernetes)"
            if ([string]::IsNullOrWhiteSpace($AKS_LOCAL_FOLDER)) {$AKS_LOCAL_FOLDER = "C:\kubernetes"}
    
            $AKS_FOLDER_FOR_SSH_KEY = "$AKS_LOCAL_FOLDER\ssh\$AKS_PERS_RESOURCE_GROUP"
            $SSH_PRIVATE_KEY_FILE = "$AKS_FOLDER_FOR_SSH_KEY\id_rsa"
            $SSH_PRIVATE_KEY_FILE_UNIX_PATH = "/" + (($SSH_PRIVATE_KEY_FILE -replace "\\", "/") -replace ":", "").ToLower().Trim("/")                                       
            $MASTER_VM_NAME = "${AKS_PERS_RESOURCE_GROUP}.${AKS_PERS_LOCATION}.cloudapp.azure.com"
            # Write-Output "You can connect to master VM in Git Bash for debugging using:"
            # Write-Output "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${MASTER_VM_NAME}"            

            $virtualmachines = az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[?storageProfile.osDisk.osType != 'Windows'].name" -o tsv
            ForEach ($vm in $virtualmachines) {
                $firstpublicip = az vm list-ip-addresses -g $AKS_PERS_RESOURCE_GROUP -n $vm --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv
                if ([string]::IsNullOrEmpty($firstpublicip)) {
                    $firstpublicip = az vm show -g $AKS_PERS_RESOURCE_GROUP -n $vm -d --query privateIps -otsv
                    $firstpublicip = $firstpublicip.Split(",")[0]
                }
                Write-Output "Connect to ${vm}:"
                Write-Output "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${firstpublicip}"            
            }

            Write-Output "Command to show errors: sudo journalctl -xef --priority 0..3"
            Write-Output "Command to see apiserver logs: sudo journalctl -fu kube-apiserver"
            Write-Output "Command to see kubelet status: sudo systemctl status kubelet"
            # sudo systemctl restart kubelet.service
            # sudo service kubelet status
            # /var/log/pods
            
            Write-Output "Cheat Sheet for journalctl: https://www.cheatography.com/airlove/cheat-sheets/journalctl/"
            # systemctl list-unit-files | grep .service | grep enabled
            # https://askubuntu.com/questions/795226/how-to-list-all-enabled-services-from-systemctl

            # restart VM: az vm restart -g MyResourceGroup -n MyVm
            # list vm sizes available: az vm list-sizes --location "eastus" --query "[].name"

        } 
        '23' {
            kubectl get pods -l k8s-app=kube-dns -n kube-system -o wide
            Do { $confirmation = Read-Host "Do you want to restart DNS pods? (y/n)"}
            while ([string]::IsNullOrWhiteSpace($confirmation))
            
            if ($confirmation -eq 'y') {
                $failedItems = kubectl get pods -l k8s-app=kube-dns -n kube-system -o jsonpath='{range.items[*]}{.metadata.name}{\"\n\"}{end}'
                ForEach ($line in $failedItems) {
                    Write-Host "Deleting pod $line"
                    kubectl delete pod $line -n kube-system
                } 
            }             
        } 
        '24' {
            # restart VMs
            $AKS_PERS_RESOURCE_GROUP = ReadSecretValue -secretname azure-secret -valueName resourcegroup
            # UpdateOSInVMs -resourceGroup $AKS_PERS_RESOURCE_GROUP
            RestartVMsInResourceGroup -resourceGroup $AKS_PERS_RESOURCE_GROUP
            SetHostFileInVms -resourceGroup $AKS_PERS_RESOURCE_GROUP
            SetupCronTab -resourceGroup $AKS_PERS_RESOURCE_GROUP          
        } 
        '25' {
            Read-Host "Script needs elevated privileges to flushdns.  Hit ENTER to launch script to set PATH"
            Start-Process powershell -verb RunAs -ArgumentList "ipconfig /flushdns"
        } 
        '30' {
            $AKS_PERS_RESOURCE_GROUP = ReadSecretValue -secretname azure-secret -valueName resourcegroup

            $urlAndIPForLoadBalancer=$(GetUrlAndIPForLoadBalancer "$AKS_PERS_RESOURCE_GROUP")
            $url=$($urlAndIPForLoadBalancer.Url)
            $ip=$($urlAndIPForLoadBalancer.IP)
                                    
            # Invoke-WebRequest -useb -Headers @{"Host" = "nlp.$customerid.healthcatalyst.net"} -Uri http://$loadBalancerIP/nlpweb | Select-Object -Expand Content
    
            Write-Output "To test out the load balancer, open Git Bash and run:"
            Write-Output "curl --header 'Host: $url' 'http://$ip/' -k" 
            } 
        '31' {
            $DEFAULT_RESOURCE_GROUP = ReadSecretValue -secretname azure-secret -valueName resourcegroup
            
            if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
                Do { 
                    $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group: (default: $DEFAULT_RESOURCE_GROUP)"
                    if ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)) {
                        $AKS_PERS_RESOURCE_GROUP = $DEFAULT_RESOURCE_GROUP
                    }
                }
                while ([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP))
            }
            FixLoadBalancers -resourceGroup $AKS_PERS_RESOURCE_GROUP
        } 
        '32' {
            $pods = $(kubectl get pods -l k8s-traefik=traefik -n kube-system -o jsonpath='{.items[*].metadata.name}')
            foreach ($pod in $pods.Split(" ")) {
                Write-Output "=============== Pod: $pod ================="
                kubectl logs --tail=20 $pod -n kube-system 
            }
        }         
        '33' {
            $customerid = ReadSecret -secretname customerid
            $customerid = $customerid.ToLower().Trim()
            Write-Host "Launching http://dashboard.$customerid.healthcatalyst.net in the web browser"
            Start-Process -FilePath "http://dashboard.$customerid.healthcatalyst.net";
        }         
        '40' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide
        } 
        '41' {
            $pods = $(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
            foreach ($pod in $pods.Split(" ")) {
                Write-Output "=============== Describe Pod: $pod ================="
                kubectl describe pods $pod -n fabricnlp 
            }            
        } 
        '42' {
            $loadBalancerIP = kubectl get svc traefik-ingress-service-public -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}' --ignore-not-found=true
            $loadBalancerInternalIP = kubectl get svc traefik-ingress-service-internal -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
            if ([string]::IsNullOrWhiteSpace($loadBalancerIP)) {
                $loadBalancerIP = $loadBalancerInternalIP
            }
            $customerid = ReadSecret -secretname customerid
            $customerid = $customerid.ToLower().Trim()
                                    
            # Invoke-WebRequest -useb -Headers @{"Host" = "nlp.$customerid.healthcatalyst.net"} -Uri http://$loadBalancerIP/nlpweb | Select-Object -Expand Content

            Write-Output "To test out the NLP services, open Git Bash and run:"
            Write-Output "curl -L --verbose --header 'Host: solr.$customerid.healthcatalyst.net' 'http://$loadBalancerInternalIP/solr' -k" 
            Write-Output "curl -L --verbose --header 'Host: nlp.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlpweb' -k" 
            Write-Output "curl -L --verbose --header 'Host: nlpjobs.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlp' -k"

            Write-Output "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
            Write-Output "$loadBalancerInternalIP solr.$customerid.healthcatalyst.net"            
            Write-Output "$loadBalancerIP nlp.$customerid.healthcatalyst.net"            
            Write-Output "$loadBalancerIP nlpjobs.$customerid.healthcatalyst.net"
            
            # clear Google DNS cache: http://www.redsome.com/flush-clear-dns-cache-google-chrome-browser/
            Write-Host "Launching http://solr.$customerid.healthcatalyst.net/solr in the web browser"
            Start-Process -FilePath "http://solr.$customerid.healthcatalyst.net/solr";
            Write-Host "Launching http://nlp.$customerid.healthcatalyst.net/nlpweb in the web browser"
            Start-Process -FilePath "http://nlp.$customerid.healthcatalyst.net/nlpweb";
        } 
        '43' {
            Write-Host "MySql root password: $(ReadSecretPassword -secretname mysqlrootpassword -namespace fabricnlp)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword -secretname mysqlpassword -namespace fabricnlp)"
            Write-Host "SendGrid SMTP Relay key: $(ReadSecretPassword -secretname smtprelaypassword -namespace fabricnlp)"
        } 
        '44' {
            $pods = $(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
            foreach ($pod in $pods.Split(" ")) {
                Write-Output "=============== Pod: $pod ================="
                kubectl logs --tail=20 $pod -n fabricnlp
            }
        } 
        '45' {
            kubectl delete --all 'pods' --namespace=fabricnlp --ignore-not-found=true                        
        } 
        '46' {
            $pods = $(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
            foreach ($pod in $pods.Split(" ")) {
                Write-Output "kubectl exec -it $pod -n fabricnlp -- sh"
            }
        } 
        '51' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide
        } 
        'q' {
            return
        }
    }
    $userinput = Read-Host -Prompt "Press Enter to continue or q to exit"
    if($userinput -eq "q"){
        return
    }
    [Console]::ResetColor()
    Clear-Host
}
