$version = "2018.01.17.2"

# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/main.ps1 | iex;
Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/common.ps1 | Invoke-Expression;

# Get-Content -Path "./azure/common.ps1" | Invoke-Expression;

do {
    Write-Host "================ Health Catalyst version $version, common functions $(GetCommonVersion) ================"
    Write-Host "0: Change kube to point to another cluster"
    Write-Host "1: Create a new Azure Container Service"
    Write-Host "2: Setup Load Balancer"
    Write-Host "3: Show status of cluster"
    Write-Host "4: Launch Kubernetes Dashboard"
    Write-Host "5: SSH to Master VM"
    Write-Host "6: View status of DNS pods"
    Write-Host "------ NLP -----"
    Write-Host "7: Install NLP"
    Write-Host "8: Show status of NLP"
    Write-Host "9: Test web sites"
    Write-Host "10: Show passwords"
    Write-Host "------ Realtime -----"
    Write-Host "11: Install Realtime"
    Write-Host "12: Show status of realtime"
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
            Write-Host "Copying $fileToUse to $env:userprofile\.kube\config"
            Copy-Item -Path $fileToUse -Destination "$env:userprofile\.kube\config"
            $env:KUBECONFIG = "${HOME}\.kube\config"
            Write-Host "Current cluster: $(kubectl config current-context)"            
        } 
        '1' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/create-acs-cluster.ps1 | Invoke-Expression;
        } 
        '2' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/setup-loadbalancer.ps1 | Invoke-Expression;
        } 
        '3' {
            Write-Host "Current cluster: $(kubectl config current-context)"
            kubectl get "deployments,pods,services,ingress,secrets" --namespace=kube-system -o wide
        } 
        '4' {
            $job = Start-Job -Name "KubDashboard" -ScriptBlock {kubectl proxy}
            Start-Process -FilePath "http://localhost:8001/api/v1/namespaces/kube-system/services/kubernetes-dashboard/proxy"
            Start-Sleep -Seconds 5
            Receive-Job -Job $job
        } 
        '5' {        
            $AKS_PERS_RESOURCE_GROUP_BASE64 = kubectl get secret azure-secret -o jsonpath='{.data.resourcegroup}'
            if (![string]::IsNullOrWhiteSpace($AKS_PERS_RESOURCE_GROUP_BASE64)) {
                $AKS_PERS_RESOURCE_GROUP = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AKS_PERS_RESOURCE_GROUP_BASE64))
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

            Write-Output "Command to show errors: sudo journalctl -xef"
            Write-Output "Command to see apiserver logs: sudo journalctl -fu kube-apiserver"
            # systemctl list-unit-files | grep .service | grep enabled
            # https://askubuntu.com/questions/795226/how-to-list-all-enabled-services-from-systemctl

        } 
        '6' {
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
        '7' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | Invoke-Expression;
        } 
        '8' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide
        } 
        '9' {
           
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
        '10' {
            Write-Host "MySql root password: $(ReadSecretPassword -secretname mysqlrootpassword -namespace fabricnlp)"
            Write-Host "MySql NLP_APP_USER password: $(ReadSecretPassword -secretname mysqlpassword -namespace fabricnlp)"
            Write-Host "SendGrid SMTP Relay key: $(ReadSecretPassword -secretname smtprelaypassword -namespace fabricnlp)"
        } 
        '11' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | Invoke-Expression;
        } 
        '12' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide
        } 
        'q' {
            return
        }
    }
    pause
    [Console]::ResetColor()
    Clear-Host
}
until ($input -eq 'q')



