$version = "2018.02.13.01"

# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/main.ps1 | iex;
#   curl -sSL  https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/main.ps1 | pwsh -c -;

Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;


# Get-Content -Path "./azure/common.ps1" | Invoke-Expression;

do {
    Write-Host "================ Health Catalyst version $version, common functions $(GetCommonVersion) ================"
    Write-Host "----- Choose Cluster -----"
    Write-Host "0: Change kube to point to another cluster"
    Write-Host "------ Install -------"
    Write-Host "1: Create a new Azure Container Service"
    Write-Host "2: Setup Load Balancer"
    Write-Host "3: Install NLP"
    Write-Host "4: Install Realtime"
    Write-Host "----- Troubleshooting ----"
    Write-Host "5: Show status of cluster"
    Write-Host "6: Launch Kubernetes Admin Dashboard"
    Write-Host "7: Show SSH commands to VMs"
    Write-Host "8: View status of DNS pods"
    Write-Host "9: Apply updates and restart all VMs"
    Write-Host "------ NLP -----"
    Write-Host "10: Show status of NLP"
    Write-Host "11: Test web sites"
    Write-Host "12: Show passwords"
    Write-Host "13: Show NLP logs"
    Write-Host "14: Restart NLP"
    Write-Host "------ Realtime -----"
    Write-Host "15: Show status of realtime"
    Write-Host "-----------"
    Write-Host "q: Quit"
    $input = Read-Host "Please make a selection"
    switch ($input) {
        '0' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            $folders = Get-ChildItem "C:\kubernetes" -directory
            for ($i = 1; $i -le $folders.count; $i++) {
                Write-Host "$i. $($folders[$i-1])"
            }              
            $index = Read-Host "Enter number of folder to use (1 - $($folders.count))"
            $folderToUse = $($folders[$index - 1])
            $fileToUse = "C:\kubernetes\$folderToUse\temp\.kube\config"
            $userKubeConfigFolder = "$env:userprofile\.kube"
            If (!(Test-Path $userKubeConfigFolder)) {
                Write-Output "Creating $userKubeConfigFolder"
                New-Item -ItemType Directory -Force -Path "$userKubeConfigFolder"
            }            
            $destinationFile = "${userKubeConfigFolder}\config"
            Write-Host "Copying $fileToUse to $destinationFile"
            Copy-Item -Path "$fileToUse" -Destination "$destinationFile"
            # set environment variable KUBECONFIG to point to this location
            $env:KUBECONFIG = "$destinationFile"
            [Environment]::SetEnvironmentVariable("KUBECONFIG", "$destinationFile", [EnvironmentVariableTarget]::User)
            Write-Host "Current cluster: $(kubectl config current-context)"            
        } 
        '1' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/create-acs-cluster.ps1 | Invoke-Expression;
        } 
        '2' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/setup-loadbalancer.ps1 | Invoke-Expression;
        } 
        '3' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | Invoke-Expression;
        } 
        '4' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | Invoke-Expression;
        } 
        '5' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            kubectl version --short
            kubectl get "deployments,pods,services,ingress,secrets" --namespace=kube-system -o wide
        } 
        '6' {
            # launch Kubernetes dashboard
            $launchJob = $true
            $existingProcess = Get-ProcessByPort 8001
            if (!([string]::IsNullOrWhiteSpace($existingProcess))) {
                Do { $confirmation = Read-Host "Another process is listening on 8001.  Do you want to kill that process? (y/n)"}
                while ([string]::IsNullOrWhiteSpace($confirmation))
            
                if ($confirmation -eq "y") {
                    Stop-ProcessByPort 8001
                }
                else {
                    $launchJob = $false
                }
            }

            if ($launchJob) {
                $job = Start-Job -Name "KubDashboard" -ScriptBlock {kubectl proxy} -ErrorAction Stop
                Wait-Job $job -Timeout 5;
                Write-Output "job state: $($job.state)"  
                Receive-Job -Job $job 6>&1  
            }

            # if ($job.state -eq 'Failed') {
            #     Receive-Job -Job $job
            #     Stop-ProcessByPort 8001
            # }
            
            # Write-Host "Your kubeconfig file is here: $env:KUBECONFIG"
            $kubectlversion = kubectl version --client=true --short=true
            if ($kubectlversion -match "v1.9") {
                Write-Host "Click Skip on login screen";
                Start-Process -FilePath "http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/";
            }
            else {
                Start-Process -FilePath "http://localhost:8001/api/v1/namespaces/kube-system/services/kubernetes-dashboard/proxy";
            }            
        } 
        '7' {        
            # $AKS_PERS_RESOURCE_GROUP = ReadSecretValue -secretname azure-secret -valueName resourcegroup
            
            if([string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP)){
                Do { 
                    $AKS_PERS_RESOURCE_GROUP = Read-Host "Resource Group"
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
            Write-Output "You can connect to master VM in Git Bash for debugging using:"
            Write-Output "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${MASTER_VM_NAME}"            

            $virtualmachines = az vm list -g $AKS_PERS_RESOURCE_GROUP --query "[?storageProfile.osDisk.osType != 'Windows'].name" -o tsv
            ForEach ($vm in $virtualmachines) {
                $firstpublicip = az vm list-ip-addresses -g $AKS_PERS_RESOURCE_GROUP -n $vm --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv
                # $privateiplist= az vm show -g $AKS_PERS_RESOURCE_GROUP -n $vm -d --query privateIps -otsv
                Write-Output "Connect to $vm"
                Write-Output "ssh -i ${SSH_PRIVATE_KEY_FILE_UNIX_PATH} azureuser@${firstpublicip}"            
            }

            Write-Output "Command to show errors: sudo journalctl -xef"
            Write-Output "Command to see apiserver logs: sudo journalctl -fu kube-apiserver"
            # systemctl list-unit-files | grep .service | grep enabled
            # https://askubuntu.com/questions/795226/how-to-list-all-enabled-services-from-systemctl

            # restart VM: az vm restart -g MyResourceGroup -n MyVm
            # list vm sizes available: az vm list-sizes --location "eastus" --query "[].name"

        } 
        '8' {
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
        '9' {
            # restart VMs
            $AKS_PERS_RESOURCE_GROUP = ReadSecretValue -secretname azure-secret -valueName resourcegroup
            UpdateOSInVMs -resourceGroup $AKS_PERS_RESOURCE_GROUP
            RestartVMsInResourceGroup -resourceGroup $AKS_PERS_RESOURCE_GROUP
            SetHostFileInVms -resourceGroup $AKS_PERS_RESOURCE_GROUP
            SetupCronTab -resourceGroup $AKS_PERS_RESOURCE_GROUP            
        } 
        '10' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide
        } 
        '11' {
           
            $loadBalancerIP = kubectl get svc traefik-ingress-service-public -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}' --ignore-not-found=true
            if ([string]::IsNullOrWhiteSpace($loadBalancerIP)) {
                $loadBalancerIP = kubectl get svc traefik-ingress-service-private -n kube-system -o jsonpath='{.status.loadBalancer.ingress[].ip}'
            }
            $customerid = ReadSecret -secretname customerid
            $customerid = $customerid.ToLower().Trim()
                                    
            Invoke-WebRequest -useb -Headers @{"Host" = "nlp.$customerid.healthcatalyst.net"} -Uri http://$loadBalancerIP/nlpweb | Select-Object -Expand Content

            Write-Output "To test out the NLP services, open Git Bash and run:"
            Write-Output "curl -L --verbose --header 'Host: solr.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/solr' -k" 
            Write-Output "curl -L --verbose --header 'Host: nlp.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlpweb' -k" 
            Write-Output "curl -L --verbose --header 'Host: nlpjobs.$customerid.healthcatalyst.net' 'http://$loadBalancerIP/nlp' -k"

            Write-Output "If you didn't setup DNS, add the following entries in your c:\windows\system32\drivers\etc\hosts file to access the urls from your browser"
            Write-Output "$loadBalancerIP solr.$customerid.healthcatalyst.net"            
            Write-Output "$loadBalancerIP nlp.$customerid.healthcatalyst.net"            
            Write-Output "$loadBalancerIP nlpjobs.$customerid.healthcatalyst.net"            

        } 
        '12' {
            Write-Host "MySql root password: $(ReadSecretPassword -secretname mysqlrootpassword -namespace fabricnlp)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword -secretname mysqlpassword -namespace fabricnlp)"
            Write-Host "SendGrid SMTP Relay key: $(ReadSecretPassword -secretname smtprelaypassword -namespace fabricnlp)"
        } 
        '13' {
            $pods = $(kubectl get pods -n fabricnlp -o jsonpath='{.items[*].metadata.name}')
            foreach ($pod in $pods.Split(" ")) {
                Write-Output "=============== Pod: $pod ================="
                kubectl logs --tail=20 $pod -n fabricnlp
            }
        } 
        '14' {
            kubectl delete --all 'pods' --namespace=fabricnlp --ignore-not-found=true                        
        } 
        '15' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide
        } 
        'q' {
            return
        }
    }
    Read-Host -Prompt "Press Enter to continue"
    [Console]::ResetColor()
    Clear-Host
}
until ($input == "q")



