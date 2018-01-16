Write-output "Version 2018.01.16.3"

# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/main.ps1 | iex;

function ReadSecret($secretname, $namespace){
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    $secretbase64 = kubectl get secret $secretname -o jsonpath='{.data.value}' -n $namespace
    $secretvalue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretbase64))
    return $secretvalue
}

do {
    Clear-Host
    Write-Host "================ Health Catalyst ================"

    Write-Host "1: Create a new Azure Container Service"
    Write-Host "2: Setup Load Balancer"
    Write-Host "3: Show status of cluster"
    Write-Host "4: Launch Kubernetes Dashboard"
    Write-Host "------ NLP -----"
    Write-Host "5: Install NLP"
    Write-Host "6: Show status of NLP"
    Write-Host "7: Test web sites"
    Write-Host "------ Realtime -----"
    Write-Host "8: Install Realtime"
    Write-Host "9: Show status of realtime"
    Write-Host "-----------"
    Write-Host "q: Quit"
    $input = Read-Host "Please make a selection"
    switch ($input) {
        '1' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/create-acs-cluster.ps1 | Invoke-Expression;
        } 
        '2' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/setup-loadbalancer.ps1 | Invoke-Expression;
        } 
        '3' {
            kubectl get "deployments,pods,services,ingress,secrets" --namespace=kube-system -o wide
        } 
        '4' {
            Start-Job -Name "KubDashboard" -ScriptBlock {kubectl proxy}
            Start-Process -FilePath http://localhost:8001/ui        } 
        '5' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | Invoke-Expression;
        } 
        '6' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide
        } 
        '7' {
           
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
        } 
        '8' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | Invoke-Expression;
        } 
        '9' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide
        } 
        'q' {
            return
        }
    }
    pause
}
until ($input -eq 'q')



