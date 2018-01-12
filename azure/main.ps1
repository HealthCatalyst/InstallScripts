
# This script is meant for quick & easy install via:
#   curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/azure/main.ps1 | iex;

do {
    Write-Host "================ Health Catalyst ================"

    Write-Host "1: Create a new Azure Container Service"
    Write-Host "2: Setup Load Balancer"
    Write-Host "3: Show status of cluster"
    Write-Host "------ NLP -----"
    Write-Host "4: Install NLP"
    Write-Host "5: Show status of NLP"
    Write-Host "------ Realtime -----"
    Write-Host "6: Install Realtime"
    Write-Host "7: Show status of realtime"
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
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.ps1 | Invoke-Expression;
        } 
        '5' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricnlp -o wide
        } 
        '6' {
            Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | Invoke-Expression;
        } 
        '7' {
            kubectl get 'deployments,pods,services,ingress,secrets,persistentvolumeclaims,persistentvolumes,nodes' --namespace=fabricrealtime -o wide
        } 
        'q' {
            return
        }
    }
    pause
}
until ($input -eq 'q')



