param([String]$namespace, [String]$appfolder, [int]$isAzure)
# the above MUST be the first line
Write-Host "Received parameters:"
Write-Host "namespace:$namespace"
Write-Host "appfolder:$appfolder"
Write-Host "isAzure:$isAzure"
Write-Host "----"
Write-Host "Version 2018.03.28.01"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

if ($isAzure) {
    DownloadAzCliIfNeeded
    $userInfo = $(GetLoggedInUserInfo)
}

if ($isAzure) {
    CreateAzureStorage -namespace $namespace
}
else {
    CreateOnPremStorage -namespace $namespace    
}

LoadStack -namespace $namespace -baseUrl $GITHUB_URL -appfolder "$appfolder" -isAzure $isAzure

if ($isAzure) {
    WaitForLoadBalancers -resourceGroup $(GetResourceGroup).ResourceGroup
}